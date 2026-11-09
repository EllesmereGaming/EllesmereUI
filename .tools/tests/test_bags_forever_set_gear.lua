-- Stub harness: the Bags equipment set lookup (BuildSetGearLookup in
-- EllesmereUIBags_Categories.lua), cut out of the real file. On WoW Forever,
-- C_EquipmentSet.GetItemLocations crashes the client inside the engine for some
-- sets (website bug #182), so there the sets' item IDs are matched against the
-- container slots instead; retail keeps GetItemLocations. Both map
-- bag*1000+slot -> setID with the first set winning.
--   lua .tools/tests/test_bags_forever_set_gear.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUIBags/EllesmereUIBags_Categories.lua")
local a = assert(SRC:find("local _setGearLookup = {}", 1, true), "the set lookup table is missing")
local f = assert(SRC:find("local function BuildSetGearLookup()", a, true), "BuildSetGearLookup missing")
local e = assert(SRC:find("\nend\n", f, true), "end of BuildSetGearLookup missing")
local BLOCK = SRC:sub(a, e + 4)

local T

local function Build(block, forever)
    T = { sets = {}, names = {}, bags = {}, locs = {}, itemReads = 0, wantNames = false }
    local EllesmereUI = { IS_FOREVER = forever }
    local C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for id in pairs(T.sets) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end,
        GetEquipmentSetInfo = function(id) return T.names[id] end,
        GetItemIDs = function(id)
            assert(forever, "retail read GetItemIDs")
            return T.sets[id]
        end,
        GetItemLocations = function(id)
            assert(not forever, "GetItemLocations called on WoW Forever (the client crashes there)")
            return T.locs[id]
        end,
    }
    local function EquipmentManager_GetLocationData(loc)
        return { isBags = loc >= 100, bag = math.floor(loc / 100) - 1, slot = loc % 100 }
    end
    local C_Container = {
        GetContainerNumSlots = function(bag) return T.bags[bag] and #T.bags[bag] or 0 end,
        GetContainerItemID = function(bag, slot)
            T.itemReads = T.itemReads + 1
            local id = T.bags[bag] and T.bags[bag][slot]
            if id ~= 0 then return id end
        end,
    }
    local Enum = { BagIndex = { Keyring = -1, Backpack = 0, Bag_1 = 1, Bag_2 = 2 } }
    local function BP() return { bagShowSetGearName = T.wantNames } end
    local function wipe(t) for k in pairs(t) do t[k] = nil end return t end
    local chunk = assert(loadstring(
        "local EllesmereUI, C_EquipmentSet, EquipmentManager_GetLocationData, C_Container, Enum, BP, wipe = ...\n"
        .. block .. "\nreturn BuildSetGearLookup, _setGearLookup, _setNames", "=EllesmereUIBags_Categories.lua"))
    return chunk(EllesmereUI, C_EquipmentSet, EquipmentManager_GetLocationData, C_Container, Enum, BP, wipe)
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function ForeverScenarios(block)
    local Build_, lookup, names = Build(block, true)
    -- No sets: nothing built, no container read.
    Build_()
    assert(Count(lookup) == 0 and T.itemReads == 0, "a character with no sets built a lookup")

    -- Two sets; item 200 is in both (the first set wins), 0 and -1 are empty / ignored slots.
    T.sets[10] = { [1] = 100, [2] = 0, [3] = -1, [5] = 200 }
    T.sets[20] = { [1] = 200, [2] = 300 }
    T.names[10], T.names[20] = "Tank", "Heal"
    T.wantNames = true
    T.bags[0] = { 100, 999, 300 }
    T.bags[1] = { 200, 200 }
    T.bags[-1] = { 5 }
    Build_()
    assert(lookup[1] == 10, "a set item in the backpack is not set gear")
    assert(lookup[2] == nil, "a non-set item became set gear")
    assert(lookup[3] == 20, "the second set's item is missing")
    assert(lookup[1001] == 10 and lookup[1002] == 10, "an item in two sets did not keep the first set")
    assert(Count(lookup) == 4, "unexpected entries: " .. Count(lookup))
    assert(names[10] == "Tank" and names[20] == "Heal", "the set names were not read")

    -- A set that lost an item: the next pass drops it (the item map is refilled).
    T.sets[10] = { [1] = 100 }
    T.sets[20] = nil
    T.wantNames = false
    Build_()
    assert(lookup[1] == 10 and lookup[1001] == nil and lookup[3] == nil, "a stale set item stayed set gear")
    assert(names[10] == nil, "set names read with the label off")

    -- A set whose item list is nil: no error, nothing built for it.
    T.sets = { [30] = false }
    Build_()
    assert(Count(lookup) == 0, "a set with no item list built entries")
end

local function RetailScenarios(block)
    local Build_, lookup = Build(block, false)
    -- loc = (bag + 1) * 100 + slot for bags; 0 / 1 / -1 are the special values; < 100 not in bags.
    T.sets[10], T.sets[20] = {}, {}
    T.locs[10] = { 101, 0, 1, -1, 50 }
    T.locs[20] = { 101, 203 }
    Build_()
    assert(lookup[1] == 10, "retail: the first set lost its slot")
    assert(lookup[1003] == 20, "retail: the second set's slot is missing")
    assert(Count(lookup) == 2, "retail: unexpected entries")
end

ForeverScenarios(BLOCK)
RetailScenarios(BLOCK)

-- Mutants: each must break a scenario.
local function Swap(text, from, to)
    local s1, s2 = text:find(from, 1, true)
    assert(s1, "mutant text not found: " .. from)
    return text:sub(1, s1 - 1) .. to .. text:sub(s2 + 1)
end
local MUTANTS = {
    { "GetItemLocations on WoW Forever", "EllesmereUI.IS_FOREVER and _foreverSetItems", "false and _foreverSetItems" },
    { "the item map is not refilled", "if foreverItems then wipe(foreverItems) end", "" },
    { "the last set wins", " and not foreverItems[itemID]", "" },
}
for _, m in ipairs(MUTANTS) do
    local mb = Swap(BLOCK, m[2], m[3])
    local ok = pcall(function() ForeverScenarios(mb); RetailScenarios(mb) end)
    assert(not ok, "mutant survived: " .. m[1])
end

print(("PASS: Bags set gear lookup on WoW Forever and retail, %d mutants killed"):format(#MUTANTS))
