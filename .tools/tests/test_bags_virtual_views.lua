-- Stub harness: Bags virtual views (RegisterVirtualView in
-- EllesmereUIBags_Categories.lua), the real file run over stubs. A view is a
-- runtime-only entry in the sidebar's top list that groups the bags another way
-- while selected: its selection numbers are stable for the session, the group
-- list is cleaned and ordered, classify() answers map to a group position (0 =
-- Other), a provider error counts as Other, an open view that unregisters falls
-- back to All Items, and with no view registered nothing changes.
-- A view may keep EUI's Pinned and Recent sections (keepPinned / keepRecent): the real
-- stamp block of EUI_Bags_Refresh.lua, the real bucketing loop of
-- EllesmereUIBags_List.lua and the real group lists of EllesmereUIBags_Grid.lua run
-- over stubs. As in All Items, a Pinned or Recent item is in its group too.
--   lua .tools/tests/test_bags_virtual_views.lua        (from the repository root)
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
local ITEMS = { [100] = IC.Armor, [101] = IC.Consumable, [102] = IC.Armor, [103] = IC.Miscellaneous }

-- A fresh manager over stubs. T.sel is the bags' selection (ns.GetSelection / SetSelection).
local function Load()
    local T = { repaints = 0, bankPaints = 0, errors = 0, sel = 0, frames = {} }
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
        CreateFrame = function()
            local f = { shown = true }
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:SetScript(_, fn) self.update = fn end
            T.frames[#T.frames + 1] = f
            return f
        end,
    }
    env._G = env
    setmetatable(env, { __index = _G })
    -- T.Flush() is one frame: it runs the update of every shown frame, returns how many ran
    function T.Flush()
        local ran = 0
        for _, f in ipairs(T.frames) do
            if f.shown and f.update then ran = ran + 1; f.update(f, 0) end
        end
        return ran
    end
    local ns = {
        SpecialBags = function() return nil end,
        RefreshOpenBank = function() T.bankPaints = T.bankPaints + 1 end,
        GetSelection = function() return T.sel, nil end,
        SetSelection = function(idx) T.sel = idx end,
    }
    local chunk = assert(loadstring(ReadSource("EllesmereUIBags/EllesmereUIBags_Categories.lua"), "=EllesmereUIBags_Categories.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIBags", ns)
    local CM = env._G.EUI_CategoryManager
    env.EUI_Bags = {
        RefreshInventory = function() T.repaints = T.repaints + 1 end,
    }
    return CM, profile, T
end

local function Names(CM)
    local out = {}
    for i, c in ipairs(CM:GetCategories()) do out[i] = c._defaultName end
    return out
end
local function Answer(id) return function() return id end end

-- 1. No view: nothing is there, nothing changes
do
    local CM, profile, T = Load()
    local base = Names(CM)
    CM:SaveState()
    local saved = Dump(profile)
    check(CM:GetViews() == nil, "GetViews is nil with no view")
    for _, n in ipairs({ 0, -1, -2, -3, -4, -9, -10, -11, 1, 5 }) do
        check(CM:GetViewByIndex(n) == nil, "GetViewByIndex(" .. n .. ") is nil with no view")
    end
    check(CM:GetViewByIndex(nil) == nil, "GetViewByIndex(nil) is nil")
    check(not CM:UnregisterVirtualView("nope"), "unregistering an unknown view is false")
    CM:RefreshVirtualViews()
    check(T.repaints == 0 and T.Flush() == 0, "RefreshVirtualViews repaints nothing while no view is registered")

    -- 2. A view: its own entry, no category touched, nothing saved
    check(CM:RegisterVirtualView("T.Tree", {
        name = "ItemTree", icon = 133784, order = 5, classify = Answer("sell"),
        groups = { { id = "sell", name = "Sell", order = 2 }, { id = "keep", name = "Keep", order = 1 } },
    }), "register returns true")
    check(T.repaints == 0 and T.Flush() == 1 and T.repaints == 1, "register repaints once, on the next frame")
    local views = CM:GetViews()
    check(views and #views == 1, "one view listed")
    check(views[1].id == "T.Tree" and views[1].name == "ItemTree" and views[1].icon == 133784, "id, name and icon kept")
    check(views[1].idx == -10, "the first view is -10")
    check(CM:GetViewByIndex(-10) == views[1], "GetViewByIndex finds it")
    check(CM:GetViewByIndex(-11) == nil and CM:GetViewByIndex(-3) == nil and CM:GetViewByIndex(0) == nil,
        "other selection numbers are not this view")
    check(views[1].groups[1].id == "keep" and views[1].groups[2].id == "sell", "groups sort by order, then id")
    check(views[1].otherName == "Other", "the default name of the Other group")
    local after = Names(CM)
    check(#after == #base, "the category list did not change length")
    for i = 1, #base do check(after[i] == base[i], "category " .. i .. " did not move") end
    CM:SaveState()
    check(Dump(profile) == saved, "SaveState writes the same with a view as without")
    check(not Dump(profile):find("T.Tree", 1, true), "no view id in the saved data")
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == (function()
        for i, c in ipairs(CM:GetCategories()) do if c._defaultName == "Armor" then return i end end
    end)(), "the categories classify as before")

    -- RefreshVirtualViews repaints while a view is registered
    local before = T.repaints
    CM:RefreshVirtualViews()
    check(T.repaints == before and T.Flush() == 1 and T.repaints == before + 1, "RefreshVirtualViews repaints the bags on the next frame")
    CM:RefreshVirtualViews(); CM:RefreshVirtualViews()
    check(T.Flush() == 1 and T.repaints == before + 2 and T.Flush() == 0, "many requests in a frame make one repaint")

    -- unregister: back to nothing
    check(CM:UnregisterVirtualView("T.Tree"), "unregister returns true")
    check(CM:GetViews() == nil and CM:GetViewByIndex(-10) == nil, "the view is gone")
    CM:SaveState()
    check(Dump(profile) == saved, "saved data is unchanged after the view left")
end

-- 3. Selection numbers: stable for the session, never reused
do
    local CM = Load()
    local function def(order) return { name = "x", order = order, classify = Answer(nil) } end
    CM:RegisterVirtualView("a", def(2))
    CM:RegisterVirtualView("b", def(1))
    local views = CM:GetViews()
    check(views[1].id == "b" and views[2].id == "a", "views sort by order, then id")
    check(views[1].idx == -11 and views[2].idx == -10, "a number follows its id, not its position")
    CM:RegisterVirtualView("a", def(9))
    check(CM:GetViews()[2].id == "a" and CM:GetViews()[2].idx == -10, "an id registered again keeps its number")
    check(#CM:GetViews() == 2, "an id registered again is replaced, not added")
    CM:UnregisterVirtualView("a")
    CM:RegisterVirtualView("c", def(0))
    check(CM:GetViewByIndex(-12) and CM:GetViewByIndex(-12).id == "c", "a new id never takes a freed number")
    CM:RegisterVirtualView("a", def(0))
    check(CM:GetViewByIndex(-10) and CM:GetViewByIndex(-10).id == "a", "an id that came back gets its old number")
end

-- 4. Arguments
do
    local CM = Load()
    check(not CM:RegisterVirtualView("", { classify = Answer(nil) }), "empty id refused")
    check(not CM:RegisterVirtualView(5, { classify = Answer(nil) }), "non-string id refused")
    check(not CM:RegisterVirtualView("x", { name = "X" }), "no classify refused")
    check(not CM:RegisterVirtualView("x"), "no def refused")
    check(CM:GetViews() == nil, "nothing registered by a refusal")
    -- a view with no groups, a nameless view, bad group entries
    check(CM:RegisterVirtualView("bare", { classify = Answer("g") }), "a view with no groups is fine")
    check(CM:GetViews()[1].name == "bare" and #CM:GetViews()[1].groups == 0, "name falls back to the id; no groups")
    check(CM:RegisterVirtualView("g", {
        otherName = "Rest", classify = Answer("b"),
        groups = { { id = "b" }, { id = "b", name = "dupe" }, { name = "no id" }, "junk", { id = "", name = "empty" },
            { id = "a", name = "A", order = 1 } },
    }), "a view with bad group entries registers")
    local v
    for _, w in ipairs(CM:GetViews()) do if w.id == "g" then v = w end end
    check(#v.groups == 2 and v.groups[1].id == "b" and v.groups[2].id == "a", "bad and duplicate groups are dropped")
    check(v.groups[1].name == "b" and v.groups[1].order == 0, "a group's name falls back to its id, order to 0")
    check(v.otherName == "Rest", "otherName is kept")
end

-- 5. Classifying: a group position, 0 for Other; errors count as Other
do
    local CM, _, T = Load()
    local args
    CM:RegisterVirtualView("v", {
        classify = function(link, id, bag, slot, q)
            args = { link, id, bag, slot, q }
            if id == 100 then return "sell" end
            if id == 101 then return "keep" end
            if id == 102 then return "nope" end
            if id == 103 then return 5 end
            if id == 104 then error("provider bug") end
            return nil
        end,
        groups = { { id = "sell", order = 1 }, { id = "keep", order = 2 } },
    })
    local view = CM:GetViewByIndex(-10)
    check(CM:ClassifyView(view, "item:100", 100, 3, 4, 2) == 1, "sell is group 1")
    check(args[1] == "item:100" and args[2] == 100 and args[3] == 3 and args[4] == 4 and args[5] == 2,
        "classify gets link, id, bag, slot, quality")
    check(CM:ClassifyView(view, "item:101", 101, 0, 1, 1) == 2, "keep is group 2")
    check(CM:ClassifyView(view, "item:102", 102, 0, 1, 1) == 0, "an unknown group id is Other")
    check(CM:ClassifyView(view, "item:103", 103, 0, 1, 1) == 0, "a non-string answer is Other")
    check(CM:ClassifyView(view, "item:105", 105, 0, 1, 1) == 0, "nil is Other")
    check(CM:ClassifyView(view, "item:104", 104, 0, 1, 1) == 0, "a provider error is Other")
    check(T.errors == 1, "the error went to the error handler")
    -- a stale answer cannot leak into the next item
    check(CM:ClassifyView(view, "item:100", 100, 0, 1, 1) == 1 and CM:ClassifyView(view, "item:105", 105, 0, 1, 1) == 0,
        "no answer carries over between items")
    -- nil bag and slot (another character's item), nil quality
    CM:ClassifyView(view, "item:100", 100, nil, nil, nil)
    check(args[3] == nil and args[4] == nil and args[5] == nil, "bag, slot and quality may be nil")
end

-- 6. An open view that leaves: back to All Items
do
    local CM, _, T = Load()
    local function def() return { name = "x", classify = Answer(nil) } end
    CM:RegisterVirtualView("a", def())
    CM:RegisterVirtualView("b", def())
    T.sel = -10
    CM:UnregisterVirtualView("b")  -- -11: not the open one
    check(T.sel == -10, "another view leaving keeps the selection")
    CM:UnregisterVirtualView("a")
    check(T.sel == 0, "the open view leaving falls back to All Items")
    T.sel = 7
    CM:RegisterVirtualView("c", def())
    CM:UnregisterVirtualView("c")
    check(T.sel == 7, "a category selection stays")
    T.sel = -2
    CM:RegisterVirtualView("c", def())
    CM:UnregisterVirtualView("c")
    check(T.sel == -2, "OneBag / MultiBag selections stay")
end

-- 7. A view's classify cannot register, unregister or ask for a repaint
do
    local CM, _, T = Load()
    local seen
    CM:RegisterVirtualView("v", {
        classify = function()
            seen = {
                CM:RegisterVirtualView("w", { classify = Answer(nil) }),
                CM:UnregisterVirtualView("v"),
            }
            CM:RefreshVirtualViews()
            return nil
        end,
    })
    T.Flush()
    local before = T.repaints
    CM:ClassifyView(CM:GetViewByIndex(-10), "item:100", 100, 0, 1, 1)
    check(seen and seen[1] == false and seen[2] == false, "inside classify, register and unregister are refused")
    check(#CM:GetViews() == 1 and CM:GetViews()[1].id == "v", "the view list did not change")
    check(T.Flush() == 0 and T.repaints == before, "and a refresh from inside classify asks for no repaint")
    check(CM:RegisterVirtualView("w", { classify = Answer(nil) }), "after classify the calls work again")
    check(CM:UnregisterVirtualView("w"), "unregister works again too")
    -- a provider that errors does not leave the guard on
    local CM2 = Load()
    CM2:RegisterVirtualView("e", { classify = function() error("bug") end })
    CM2:ClassifyView(CM2:GetViewByIndex(-10), "item:100", 100, 0, 1, 1)
    check(CM2:RegisterVirtualView("f", { classify = Answer(nil) }), "an error in classify leaves the guard off")
end

-- 8. The keep flags: kept only as true, default off
do
    local CM = Load()
    CM:RegisterVirtualView("k", { classify = Answer(nil), keepPinned = true, keepRecent = true })
    local v = CM:GetViews()[1]
    check(v.keepPinned == true and v.keepRecent == true, "both keep flags are kept")
    CM:RegisterVirtualView("k", { classify = Answer(nil), keepPinned = "yes", keepRecent = 1 })
    v = CM:GetViews()[1]
    check(v.keepPinned == nil and v.keepRecent == nil, "a keep flag is kept only as true")
    CM:RegisterVirtualView("k", { classify = Answer(nil) })
    check(CM:GetViews()[1].keepPinned == nil and CM:GetViews()[1].keepRecent == nil, "no flags: both off")
end

-- Code between two markers of a source file, as the body of a function over the given names
local function Block(file, from, to, params, ret)
    local src = ReadSource(file)
    local a = assert(src:find(from, 1, true), "start marker: " .. from)
    local b = assert(src:find(to, a, true), "end marker: " .. to)
    local body = src:sub(a, b - 1)
    return assert(loadstring("return function(" .. params .. ")\n" .. body .. (ret and ("\nreturn " .. ret) or "") .. "\nend", "=" .. file))()
end

-- 9. Refresh: what each shown item is stamped with: its group (_vg, always), and the marks of
-- the items the Pinned and Recent sections repeat (_vgPin, _vgRec, _vgOnly). As in All Items the
-- item stays in its group too; only a pinned item hidden in its category (_pinnedOnly) leaves it.
do
    local stamp = Block("EllesmereUIBags/EUI_Bags_Refresh.lua",
        "local view = EUI_CategoryManager:GetViewByIndex(selectedCategoryIndex)\n    if view then",
        "    -- 4b.",
        "EUI_CategoryManager, selectedCategoryIndex, displayItems, showPinned, pinnedSet, showRecent, EUI_Bags, IsItemPinned")
    local CM = Load()
    local pinCalls = 0
    local function IsPinned(set, link, id) pinCalls = pinCalls + 1; return set[id] == true end
    local function Items()
        local list = {}
        for _, id in ipairs({ 100, 101, 102, 103, 104 }) do
            list[#list + 1] = { itemLink = "item:" .. id, info = { itemID = id, quality = 1 }, bag = 0, slot = id }
        end
        list[5]._pinnedOnly = true   -- Hide Items in Their Categories: pinned, so not Recent
        return list
    end
    local pins = { [100] = true, [102] = true, [104] = true }
    local recent = { [101] = true, [102] = true, [104] = true }
    local function Run(def, show, pinSet, recentSet)
        CM:RegisterVirtualView("v", {
            classify = function() return "a" end, groups = { { id = "a" } },
            keepPinned = def.keepPinned, keepRecent = def.keepRecent,
        })
        local items = Items()
        stamp(CM, -10, items, show.pinned, pinSet, show.recent, { _recentItems = recentSet }, IsPinned)
        local out = {}
        for i, d in ipairs(items) do out[i] = { g = d._vg, pin = d._vgPin, rec = d._vgRec, only = d._vgOnly } end
        return out
    end
    local both = { pinned = true, recent = true }
    local r = Run({ keepPinned = true, keepRecent = true }, both, pins, recent)
    check(r[1].g == 1 and r[1].pin == true and not r[1].rec and not r[1].only, "a pinned item is in Pinned and keeps its group")
    check(r[2].g == 1 and r[2].rec == true and not r[2].pin and not r[2].only, "a recent item is in Recent and keeps its group")
    check(r[3].g == 1 and r[3].pin == true and r[3].rec == true and not r[3].only,
        "an item both pinned and recent is in Pinned, in Recent and in its group")
    check(r[4].g == 1 and not r[4].pin and not r[4].rec and not r[4].only, "any other item is in its group only")
    check(r[5].g == 1 and r[5].pin == true and r[5].only == true and not r[5].rec,
        "a pinned item hidden in its category is in Pinned only (not Recent, not its group)")
    r = Run({ keepPinned = true, keepRecent = true }, { pinned = false, recent = true }, pins, recent)
    check(not r[1].pin and not r[1].only and r[1].g == 1, "Show Pinned Items off: no Pinned, the item stays in its group")
    check(r[3].rec == true and not r[3].pin, "Show Pinned Items off: a recent item is still in Recent")
    check(not r[5].pin and not r[5].only and not r[5].rec and r[5].g == 1,
        "Show Pinned Items off: a hidden-in-category item is in its group and not Recent (the All Items rule)")
    r = Run({ keepPinned = true, keepRecent = true }, { pinned = true, recent = false }, pins, recent)
    check(r[1].pin == true and not r[2].rec and not r[3].rec and r[3].pin == true, "Show Recent Items off: no Recent")
    r = Run({ keepPinned = true, keepRecent = true }, both, nil, nil)
    check(not r[1].pin and not r[2].rec and r[1].g == 1 and r[2].g == 1, "no pin table and no recent table: groups only")
    r = Run({ keepPinned = true }, both, pins, recent)
    check(r[1].pin == true and not r[2].rec and not r[3].rec, "keepPinned alone: no Recent")
    r = Run({ keepRecent = true }, both, pins, recent)
    check(not r[1].pin and not r[1].only and r[2].rec == true and r[3].rec == true and not r[5].only,
        "keepRecent alone: no Pinned, and a pinned item is not pulled out of its group")
    pinCalls = 0
    r = Run({}, both, pins, recent)
    check(r[1].g == 1 and r[2].g == 1 and r[3].g == 1 and not r[1].pin and not r[2].rec and not r[5].only and pinCalls == 0,
        "a view with no flags: groups only, the pin test never runs")
    -- no view selected: nothing is stamped
    local items = Items()
    stamp(CM, 0, items, true, pins, true, { _recentItems = recent }, IsPinned)
    check(items[1]._vg == nil and items[1]._vgPin == nil and items[1]._vgRec == nil and pinCalls == 0,
        "no view selected: nothing stamped, nothing asked")
end

-- 10. List: a Pinned or Recent item is added to its own section AND to its group
do
    local bucket = Block("EllesmereUIBags/EllesmereUIBags_List.lua",
        "    for _, d in ipairs(items) do\n        local ci = d.categoryIndex",
        "    if slotView and opts.emptySlots then",
        "items, cats, StampItem, ns, pinnedSet, recentSet, opts, slotView, BagKey, view, hidden, junkOn, gearSlots, Add")
    local ns = {
        IsItemPinned = function(set, link, id) return set[id] == true end,
        IsArmoryGearCategory = function() return false end,
    }
    local cats = { { name = "Cat", _defaultName = "Cat" } }
    local function Run(view, items, pinSet, recentSet)
        local adds = {}
        bucket(items, cats, function() end, ns, pinSet, recentSet, {}, nil, function() return 0 end, view, {}, false, false,
            function(key, _, d) adds[#adds + 1] = { key = key, id = d.info.itemID } end)
        return adds
    end
    local function Item(id, vg, f)
        local d = { itemLink = "item:" .. id, info = { itemID = id }, categoryIndex = 1, _vg = vg, _lvQuality = 1 }
        for k, v in pairs(f or {}) do d[k] = v end
        return d
    end
    local function Where(adds)
        local w = {}
        for _, a in ipairs(adds) do w[a.id] = w[a.id] or {}; w[a.id][#w[a.id] + 1] = tostring(a.key) end
        for id, keys in pairs(w) do table.sort(keys); w[id] = table.concat(keys, ",") end
        return w
    end
    local view = { groups = { { id = "a" }, { id = "b" } } }
    local items = {
        Item(1, 1, { _vgPin = true }),
        Item(2, 1, { _vgRec = true }),
        Item(3, 2, { _vgPin = true, _vgRec = true }),
        Item(4, 2),
        Item(5, 0),
        Item(6, nil),
        Item(7, 1, { _vgPin = true, _vgOnly = true, _pinnedOnly = true }),
    }
    local adds = Run(view, items, { [1] = true, [3] = true, [7] = true }, { [2] = true, [3] = true })
    local w = Where(adds)
    check(#adds == 11, "a view: 11 adds for 7 items (a Pinned or Recent item is also in its group): " .. #adds)
    check(w[1] == "1,pinned" and w[2] == "1,recent", "a Pinned or Recent item is in its section and its group: " .. tostring(w[1]) .. " / " .. tostring(w[2]))
    check(w[3] == "2,pinned,recent", "pinned and recent: both sections and its group: " .. tostring(w[3]))
    check(w[4] == "2", "any other item is in its group only")
    check(w[5] == "3" and w[6] == "3", "Other (0 or no answer) goes after the last group")
    check(w[7] == "pinned", "a pinned item hidden in its category is in Pinned only: " .. tostring(w[7]))
    -- the marks decide, not the sets: an item in both sets but not marked stays in its group only
    adds = Run(view, { Item(8, 1) }, { [8] = true }, { [8] = true })
    check(#adds == 1 and adds[1].key == 1, "an unmarked item is in its group only, whatever the sets hold")
    -- the keep flags off: the list is given no pin or recent set
    adds = Run(view, { Item(1, 1), Item(2, 0) }, nil, nil)
    check(#adds == 2 and adds[1].key == 1 and adds[2].key == 3, "a view without the flags: groups only")
    -- not a view: the old behaviour stays (a pinned item shows in Pinned and in its category)
    adds = Run(nil, { Item(1, nil) }, { [1] = true }, { [1] = true })
    local keys = {}
    for _, a in ipairs(adds) do keys[#keys + 1] = tostring(a.key) end
    table.sort(keys)
    check(table.concat(keys, ",") == "1,pinned,recent", "not a view: pinned and recent items still show in their category too")
end

-- 11. Grid: the lists a view draws (Pinned, Recent, one per group, Other)
do
    local bucket = Block("EllesmereUIBags/EllesmereUIBags_Grid.lua",
        "        local byGroup = { [-2] = {}, [-1] = {} }",
        "        local headerIdx = 0",
        "nGroups, displayItems", "byGroup")
    local function Item(id, vg, f)
        local d = { id = id, _vg = vg }
        for k, v in pairs(f or {}) do d[k] = v end
        return d
    end
    local items = {
        Item(1, 1, { _vgPin = true }),
        Item(2, 1, { _vgRec = true }),
        Item(3, 2, { _vgPin = true, _vgRec = true }),
        Item(4, 2),
        Item(5, 0),
        Item(6, nil),
        Item(7, 9),
        Item(8, 1, { _vgPin = true, _vgOnly = true }),
    }
    local by = bucket(2, items)
    local function Ids(list) local o = {} for _, d in ipairs(list) do o[#o + 1] = d.id end return table.concat(o, ",") end
    check(Ids(by[-1]) == "1,3,8", "Pinned list: every marked item, also the one hidden in its category: " .. Ids(by[-1]))
    check(Ids(by[-2]) == "2,3", "Recent list: " .. Ids(by[-2]))
    check(Ids(by[1]) == "1,2", "group 1 keeps its pinned and recent items, not the one hidden in its category: " .. Ids(by[1]))
    check(Ids(by[2]) == "3,4", "group 2: " .. Ids(by[2]))
    check(Ids(by[0]) == "5,6,7", "Other: group 0, no answer, an unknown group: " .. Ids(by[0]))
    by = bucket(2, { Item(1, 1), Item(2, 2) })
    check(#by[-1] == 0 and #by[-2] == 0 and #by[1] == 1 and #by[2] == 1, "no marks: no Pinned, no Recent, groups only")
end

if fails == 0 then print("OK") else print(fails .. " failure(s)"); os.exit(1) end
