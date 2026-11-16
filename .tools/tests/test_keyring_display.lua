local file = assert(io.open("EllesmereUIBags/EUI_Bags_Refresh.lua", "r"))
local source = file:read("*a")
file:close()

local startAt = assert(source:find("\nlocal function KeyringDisplaySlots%(", 1)) + 1
local endAt = assert(source:find("\nlocal _anyItemPanelOpen", startAt)) - 1
local loadProjection = assert(loadstring(source:sub(startAt, endAt) .. "\nreturn KeyringDisplaySlots"))

EUI_Bags = { list = false, IsListMode = function() return EUI_Bags.list end }
local KeyringDisplaySlots = loadProjection()

local function slot(n, occupied)
    return { bag = -1, slot = n, info = occupied and { itemID = n } or nil }
end

local function ids(slots)
    local out = {}
    for i, data in ipairs(slots or {}) do out[i] = data.slot end
    return table.concat(out, ",")
end

local original = { slot(1, true), slot(2, true), slot(3, false) }
assert(KeyringDisplaySlots(original, 2, 3, false, false) == original,
    "Grid must keep the original physical slot array")

EUI_Bags.list = true
assert(ids(KeyringDisplaySlots(original, 2, 3, false, false)) == "1,2",
    "List must render occupied slots only")
assert(ids(KeyringDisplaySlots({ slot(1, false), slot(2, false) }, 0, 2, false, false)) == "",
    "empty List must render no slot rows")
EUI_Bags.list = false

assert(ids(KeyringDisplaySlots({ slot(1, false), slot(2, false) }, 0, 2, false, true)) == "1",
    "empty Compact must keep one drop target")
local gapped = KeyringDisplaySlots({ slot(1, true), slot(2, false), slot(3, true), slot(4, false) },
    2, 4, false, true)
assert(ids(gapped) == "1,2,3", "gapped Compact must preserve order and first empty slot")
assert(gapped[2].bag == -1 and gapped[2].slot == 2,
    "Compact drop target must retain the real keyring bag and slot IDs")
assert(ids(KeyringDisplaySlots({ slot(1, true), slot(2, true) }, 2, 2, false, true)) == "1,2",
    "full Compact must omit empty drop targets")
assert(ids(KeyringDisplaySlots({ slot(2, true) }, 3, 4, true, true)) == "2",
    "search-filtered Compact must omit empty drop targets")
assert(ids(KeyringDisplaySlots({ slot(1, true), slot(2, false), slot(3, true), slot(4, false) },
    2, 4, false, true)) == "1,2,3",
    "clearing search must restore one real empty drop target")

print("Keyring display behavior passed")
