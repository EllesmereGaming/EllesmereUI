-- Stub harness: Bags virtual categories (RegisterVirtualCategory in
-- EllesmereUIBags_Categories.lua), the real file run over stubs. They are
-- runtime-only: they sit after every saved category (and after Junk), SaveState
-- and the index-keyed visual order skip them, an unregistered provider leaves
-- nothing behind, and with no provider nothing changes.
--   lua .tools/tests/test_bags_virtual_categories.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- A table as one comparable string (keys sorted)
local function Dump(v)
    if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Dump(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local IC = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7,
    ItemEnhancement = 8, Recipe = 9, Questitem = 12, Miscellaneous = 15 }

-- item id -> class id (what GetItemInfoInstant would say)
local ITEMS = { [100] = IC.Armor, [101] = IC.Consumable, [102] = IC.Armor, [103] = IC.Miscellaneous }

-- A fresh manager over stubs. opts.bags: false = no EUI_Bags global.
local function Load(opts)
    opts = opts or {}
    local T = { repaints = 0, bankPaints = 0, errors = 0, invalidated = 0 }
    local profile = {}
    local EllesmereUI = {
        L = function(s) return s end,
        Lite = { IsDBReady = function() return true end },
        _bagsDB = { profile = profile },
    }
    local env = {
        EllesmereUI = EllesmereUI,
        EllesmereUIDB = {},
        Enum = { ItemClass = IC },
        C_Item = {
            GetItemInfoInstant = function(link) local id = tonumber(tostring(link):match("(%d+)")) return id, nil, nil, nil, nil, ITEMS[id] end,
            GetItemInfo = function() return nil, nil, 1 end,
        },
        C_Container = { GetContainerItemQuestInfo = function() return nil end },
        C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end },
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        securecallfunction = function(fn, ...)
            local ok = pcall(fn, ...)
            if not ok then T.errors = T.errors + 1 end
        end,
    }
    env._G = env
    setmetatable(env, { __index = _G })
    local ns = { SpecialBags = function() return nil end, RefreshOpenBank = function() T.bankPaints = T.bankPaints + 1 end }
    local chunk = assert(loadstring(ReadSource("EllesmereUIBags/EllesmereUIBags_Categories.lua"), "=EllesmereUIBags_Categories.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIBags", ns)
    local CM = env._G.EUI_CategoryManager
    if opts.bags ~= false then
        env.EUI_Bags = {
            InvalidateSetCategories = function() T.invalidated = T.invalidated + 1; CM:OnEquipmentSetsChanged() end,
            RefreshInventory = function() T.repaints = T.repaints + 1 end,
        }
    end
    return CM, profile, T
end

local function Names(CM)
    local out = {}
    for i, c in ipairs(CM:GetCategories()) do out[i] = c._defaultName end
    return out
end
local function IndexOf(CM, key)
    for i, c in ipairs(CM:GetCategories()) do if c._defaultName == key then return i end end
end
local function ClaimIDs(...)
    local set = {}
    for _, id in ipairs({ ... }) do set[id] = true end
    return function(link, id) return set[id] end
end

-- 1. No provider: the list and the saved data are what they were
do
    local CM, profile = Load()
    local base = Names(CM)
    CM:SaveState()
    local saved = Dump(profile)
    check(#base > 5, "default categories built")
    check(not CM:IsVirtual(#base), "IsVirtual: false for the last real category")
    check(not CM:IsVirtual(nil), "IsVirtual(nil) is false")
    check(CM:GetSavedCount() == #base, "GetSavedCount is the whole list without providers")
    check(not CM:UnregisterVirtualCategory("nope"), "unregistering an unknown id is false")
    CM:RefreshVirtualCategories()  -- nothing registered: must not error

    -- 2. A provider: tail of the list, nothing saved, no index moves
    local _, _, T
    CM, profile, T = Load()
    base = Names(CM)
    check(CM:RegisterVirtualCategory("T.Sell", { name = "ItemTree: Sell", icon = 134400, order = 2, classify = ClaimIDs(100) }),
        "register returns true")
    check(T.invalidated == 1 and T.repaints == 1 and T.bankPaints == 1, "register rebuilds and repaints once")
    local cats = CM:GetCategories()
    check(#cats == #base + 1, "one category added")
    check(cats[#cats].isVirtual and cats[#cats]._defaultName == "Virtual:T.Sell", "the virtual category is last")
    check(cats[#cats].name == "ItemTree: Sell" and cats[#cats].noGroup and cats[#cats].noMove, "name, noGroup, noMove")
    for i = 1, #base do check(cats[i]._defaultName == base[i], "index " .. i .. " did not move") end
    check(CM:IsVirtual(#cats) and not CM:IsVirtual(#base), "IsVirtual marks only the tail")
    check(CM:GetSavedCount() == #base, "GetSavedCount skips the tail")
    check(not CM:CanAssignToCategory(#cats), "items cannot be assigned to a virtual category")
    CM:SaveState()
    check(Dump(profile) == saved, "SaveState writes the same with a provider as without")

    -- classification
    local vIdx = #cats
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == vIdx, "a claimed item files in the virtual category")
    check(CM:ClassifyItem("item:102", 102, 0, 1, 1) == IndexOf(CM, "Armor"), "an unclaimed item uses the built-in rules")
    local items = {
        { bag = 0, slot = 1, info = { itemID = 100, quality = 1 }, itemLink = "item:100" },
        { bag = 0, slot = 2, info = { itemID = 102, quality = 1 }, itemLink = "item:102" },
    }
    local counts = CM:ClassifyAll(items)
    check(counts[vIdx] == 1 and items[1].categoryIndex == vIdx, "ClassifyAll counts the virtual category")

    -- a user's own filing beats a provider
    CM:AssignItem(100, "Consumables")
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == IndexOf(CM, "Consumables"), "an assigned item skips the providers")
    CM:UnassignItem(100)

    -- renames and custom categories: saved data stays free of the virtual one
    local idx = CM:AddCustomCategory("Mine")
    check(idx and idx < vIdx + 1 and not CM:IsVirtual(idx), "a custom category lands before the tail")
    CM:SaveState()
    check(not Dump(profile):find("Virtual", 1, true), "no 'Virtual' in the saved data")
    check(#profile.bagCategoryOrder == #base + 1, "saved order lists real categories only")

    -- 3. Reordering: nothing moves among or after the virtual tail
    CM, profile = Load()
    CM:RegisterVirtualCategory("A", { name = "A", classify = ClaimIDs(1) })
    CM:RegisterVirtualCategory("B", { name = "B", order = -1, classify = ClaimIDs(2) })
    cats = CM:GetCategories()
    check(cats[#cats]._defaultName == "Virtual:A" and cats[#cats - 1]._defaultName == "Virtual:B",
        "providers sort by order, then id")
    local n = CM:GetSavedCount()
    check(cats[n].isJunk, "Junk is the last saved category")
    CM:ReorderCategory(#cats, 1)
    check(cats[#cats]._defaultName == "Virtual:A", "a virtual category does not move")
    CM:ReorderCategory(n - 1, #cats + 1)
    check(cats[n].isJunk and cats[n + 1].isVirtual, "a drop past the tail stays before Junk")
    CM:ReorderCategory(3, n + 1)
    check(cats[n].isJunk and cats[n + 1].isVirtual and cats[n + 2].isVirtual, "a drop on the tail stays before Junk")
    check(CM:GetSavedCount() == n, "saved count stays")

    -- Junk Marker off: no Junk, a drop lands after the last real category
    CM, profile = Load()
    profile.bagShowJunkIcon = false
    CM:InitCategories()
    CM:RegisterVirtualCategory("A", { name = "A", classify = ClaimIDs(1) })
    cats = CM:GetCategories()
    n = CM:GetSavedCount()
    check(not cats[n].isJunk, "no Junk while its marker is off")
    local from = 3  -- past the two noMove rows
    local who = cats[from]
    CM:ReorderCategory(from, #cats + 1)
    check(cats[n] == who and cats[n + 1].isVirtual, "the last real slot, before the tail")

    -- 4. Claim order, errors, re-registering, unregistering
    CM, profile = Load()
    local asked = {}
    CM:RegisterVirtualCategory("late", { name = "Late", order = 5, classify = function(l, id) asked[#asked + 1] = "late"; return id == 100 end })
    CM:RegisterVirtualCategory("early", { name = "Early", order = 1, classify = function(l, id, bag, slot, q)
        asked[#asked + 1] = "early:" .. tostring(bag) .. ":" .. tostring(slot) .. ":" .. tostring(q)
        return id == 100
    end })
    cats = CM:GetCategories()
    check(CM:ClassifyItem("item:100", 100, 3, 4, 2) == #cats - 1, "the first claim by order wins")
    check(asked[1] == "early:3:4:2" and #asked == 1, "providers get link args and stop at the first claim")
    local T4
    CM, profile, T4 = Load()
    CM:RegisterVirtualCategory("boom", { name = "Boom", classify = function() error("provider bug") end })
    CM:RegisterVirtualCategory("ok", { name = "Ok", order = 1, classify = ClaimIDs(100) })
    cats = CM:GetCategories()
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == #cats, "a provider that errors does not stop the next one")
    check(T4.errors == 1, "the error went to the error handler")
    check(CM:ClassifyItem("item:101", 101, 0, 1, 1) == IndexOf(CM, "Consumables"), "after an error the built-in rules still run")
    check(CM:RegisterVirtualCategory("ok", { name = "Ok2", order = 1, classify = ClaimIDs(103) }), "register again")
    cats = CM:GetCategories()
    check(#cats == CM:GetSavedCount() + 2 and cats[#cats].name == "Ok2", "an id registered again is replaced")

    check(not CM:RegisterVirtualCategory("", { classify = ClaimIDs() }), "empty id refused")
    check(not CM:RegisterVirtualCategory(5, { classify = ClaimIDs() }), "non-string id refused")
    check(not CM:RegisterVirtualCategory("x", { name = "X" }), "no classify refused")
    check(not CM:RegisterVirtualCategory("x"), "no def refused")

    -- unregistering: back to the original list and saved data
    local CM5, profile5, T5 = Load()
    local base5 = Names(CM5)
    CM5:SaveState()
    local saved5 = Dump(profile5)
    CM5:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    CM5:RegisterVirtualCategory("b", { name = "B", classify = ClaimIDs(101) })
    CM5:SaveState()
    check(CM5:UnregisterVirtualCategory("a") and CM5:UnregisterVirtualCategory("b"), "unregister returns true")
    CM5:SaveState()
    check(Dump(profile5) == saved5, "saved data is unchanged after the providers left")
    local after = Names(CM5)
    check(#after == #base5, "the list is back to its length")
    for i = 1, #base5 do check(after[i] == base5[i], "index " .. i .. " is back") end
    check(CM5:ClassifyItem("item:100", 100, 0, 1, 1) == IndexOf(CM5, "Armor"), "no provider answers any more")
    check(CM5:GetSavedCount() == #after, "GetSavedCount is the whole list again")
    check(T5.repaints == 4, "every change repainted")

    -- with no EUI_Bags yet: the list is dropped for the next build
    local CM6 = Load({ bags = false })
    CM6:RegisterVirtualCategory("z", { name = "Z", classify = ClaimIDs(100) })
    local c6 = CM6:GetCategories()
    check(c6[#c6]._defaultName == "Virtual:z", "a provider registered before the bags exist still builds")

    -- RefreshVirtualCategories repaints
    local CM7, _, T7 = Load()
    CM7:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    local before = T7.repaints
    CM7:RefreshVirtualCategories()
    check(T7.repaints == before + 1 and T7.bankPaints >= 2, "RefreshVirtualCategories repaints the bags and the bank")
end

-- 5. The index-keyed visual order (EUI_Bags_Data.lua) never saves a virtual category
do
    local SRC = ReadSource("EllesmereUIBags/EUI_Bags_Data.lua")
    local a = assert(SRC:find("local function GetVisualOrder()", 1, true), "GetVisualOrder missing")
    local e = assert(SRC:find("-- Clear saved visual order for a group", a, true), "end of ApplySavedOrder missing")
    local BLOCK = SRC:sub(a, e - 1)
    local CM, profile = Load()
    CM:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    local vIdx = #CM:GetCategories()
    local chunk = assert(loadstring("local BP, EUI_CategoryManager = ...\n" .. BLOCK
        .. "\nreturn SaveCategoryOrder, ApplySavedOrder", "=EUI_Bags_Data.lua"))
    local Save, Apply = chunk(function() return profile end, CM)
    local list = {
        { info = { itemID = 5 }, bag = 0, slot = 1 },
        { info = { itemID = 6 }, bag = 0, slot = 2 },
    }
    Save(vIdx, list)
    check(profile.bagVisualOrder == nil, "a virtual category's order is not saved")
    Save(2, list)
    check(profile.bagVisualOrder and profile.bagVisualOrder[2] and #profile.bagVisualOrder[2] == 2, "a real category's order still saves")
    profile.bagVisualOrder[vIdx] = { 6, 5 }
    Apply(vIdx, list)
    check(list[1].info.itemID == 5 and list[1]._savedPos == nil, "a virtual category's order is not applied")
    Apply(2, list)
    check(list[1]._savedPos == 1, "a real category's order still applies")
    Save("Some Group", list)
    check(profile.bagVisualOrder["Some Group"], "a group name key still saves")
end

if fails == 0 then print("OK") else print(fails .. " failure(s)"); os.exit(1) end
