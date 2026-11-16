-- Stub harness: Bags virtual views (RegisterVirtualView in
-- EllesmereUIBags_Categories.lua), the real file run over stubs. A view is a
-- runtime-only entry in the sidebar's top list that groups the bags another way
-- while selected: its selection numbers are stable for the session, the group
-- list is cleaned and ordered, classify() answers map to a group position (0 =
-- Other), a provider error counts as Other, an open view that unregisters falls
-- back to All Items, and with no view registered nothing changes.
-- A view may keep EUI's Pinned and Recent sections (keepPinned / keepRecent). As
-- in All Items, a Pinned or Recent item is in its group too.
-- Junk (what Sell Junk sells, while the Junk Marker is on) is never offered to
-- the provider: it files in a Junk section of our own, drawn last. An item whose
-- link has not loaded is not offered and not drawn.
-- The pieces of the other Bags files that carry a view (the stamp block and the
-- list options of EUI_Bags_Refresh.lua, the bucket loop, section order and
-- section keys of EllesmereUIBags_List.lua, the lists and sections of
-- EllesmereUIBags_Grid.lua, the sidebar's count and entries, the stack
-- splitter's rule, the header count) are cut out by their first and last lines
-- (a moved line fails here by name) and run over stubs.
--   lua .tools/tests/test_bags_virtual_views.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
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
local ITEMS = { [100] = IC.Armor, [101] = IC.Consumable, [102] = IC.Armor, [103] = IC.Miscellaneous,
    [200] = IC.Miscellaneous, [201] = IC.Questitem, [202] = IC.Armor, [203] = IC.Miscellaneous, [204] = IC.Armor }

-- A fresh manager over stubs. T.sel is the bags' selection (ns.GetSelection /
-- SetSelection), T.db the account table, profile the Bags profile.
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
    T.db = env.EllesmereUIDB
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
    T.sel = -10
    CM:RefreshVirtualViews()
    check(T.repaints == 0 and T.Flush() == 0, "RefreshVirtualViews repaints nothing while no view is registered")
    T.sel = 0

    -- 2. A view: its own entry, no category touched, nothing saved
    check(CM:RegisterVirtualView("sample.view", {
        name = "Sample View", icon = 133784, order = 5, classify = Answer("sell"),
        groups = { { id = "sell", name = "Sell", order = 2 }, { id = "keep", name = "Keep", order = 1 } },
    }), "register returns true")
    check(T.repaints == 0 and T.Flush() == 1 and T.repaints == 1, "register repaints once, on the next frame")
    check(T.bankPaints == 0, "a view registering does not repaint the bank (it shows no views)")
    local views = CM:GetViews()
    check(views and #views == 1, "one view listed")
    check(views[1].id == "sample.view" and views[1].name == "Sample View" and views[1].icon == 133784, "id, name and icon kept")
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
    check(not Dump(profile):find("sample.view", 1, true), "no view id in the saved data")
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == (function()
        for i, c in ipairs(CM:GetCategories()) do if c._defaultName == "Armor" then return i end end
    end)(), "the categories classify as before")

    -- RefreshVirtualViews repaints the bags, and only while a view is selected:
    -- nobody is looking at a provider's answers anywhere else
    local before = T.repaints
    for _, sel in ipairs({ 0, -1, -2, -3, 4 }) do
        T.sel = sel
        CM:RefreshVirtualViews()
        check(T.Flush() == 0 and T.repaints == before, "RefreshVirtualViews repainted with selection " .. sel)
    end
    T.sel = -10
    CM:RefreshVirtualViews()
    check(T.repaints == before and T.Flush() == 1 and T.repaints == before + 1, "RefreshVirtualViews repaints the bags on the next frame")
    CM:RefreshVirtualViews(); CM:RefreshVirtualViews()
    check(T.Flush() == 1 and T.repaints == before + 2 and T.Flush() == 0, "many requests in a frame make one repaint")
    check(T.bankPaints == 0, "a view's refresh does not repaint the bank")
    -- a virtual category changing in the same frame still gets its bank repaint, once
    check(CM:RegisterVirtualCategory("sample.cat", { name = "Cat", classify = function() return false end }), "a virtual category registers")
    CM:RefreshVirtualViews()
    check(T.Flush() == 1 and T.repaints == before + 3 and T.bankPaints == 1, "a category change and a view refresh in one frame: one repaint, the bank too")
    CM:RefreshVirtualViews()
    check(T.Flush() == 1 and T.bankPaints == 1, "the next view refresh leaves the bank alone again")
    CM:UnregisterVirtualCategory("sample.cat")
    T.Flush()
    T.sel = 0

    -- unregister: back to nothing
    local bank = T.bankPaints
    check(CM:UnregisterVirtualView("sample.view"), "unregister returns true")
    check(T.Flush() == 1 and T.bankPaints == bank, "a view leaving repaints the bags, not the bank")
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
    local function View(id)
        for _, w in ipairs(CM:GetViews()) do if w.id == id then return w end end
    end
    local v = View("g")
    check(#v.groups == 2 and v.groups[1].id == "b" and v.groups[2].id == "a", "bad and duplicate groups are dropped")
    check(v.groups[1].name == "b" and v.groups[1].order == 0, "a group's name falls back to its id, order to 0")
    check(v.otherName == "Rest", "otherName is kept")
    -- the list view's session collapse keys: by the group's id, so a provider that
    -- registers again with its groups in another order moves no collapsed state
    check(v.groups[1].key == "Virtual:view:g:g:b" and v.groups[2].key == "Virtual:view:g:g:a", "a group's collapse key: " .. tostring(v.groups[1].key))
    check(v.otherKey == "Virtual:view:g:other", "the Other section's collapse key: " .. tostring(v.otherKey))
    CM:RegisterVirtualView("g", { classify = Answer("b"), groups = { { id = "b", order = 5 }, { id = "a", order = 1 } } })
    v = View("g")
    check(v.groups[1].id == "a" and v.groups[1].key == "Virtual:view:g:g:a" and v.groups[2].key == "Virtual:view:g:g:b",
        "a new group order keeps each group's collapse key")
    check(View("bare").otherKey == "Virtual:view:bare:other", "each view has its own Other key")
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
    T.sel = -10   -- the view is open, so only the classify guard holds the refresh back
    local before = T.repaints
    CM:ClassifyView(CM:GetViewByIndex(-10), "item:100", 100, 0, 1, 1)
    check(seen and seen[1] == false and seen[2] == false, "inside classify, register and unregister are refused")
    check(#CM:GetViews() == 1 and CM:GetViews()[1].id == "v", "the view list did not change")
    check(T.Flush() == 0 and T.repaints == before, "and a refresh from inside classify asks for no repaint")
    CM:RefreshVirtualViews()
    check(T.Flush() == 1 and T.repaints == before + 1, "after classify a refresh repaints again")
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
-- The same for the fields of a table constructor: a function returning that table
local function Fields(file, from, to, params)
    local src = ReadSource(file)
    local a = assert(src:find(from, 1, true), "start marker: " .. from)
    local b = assert(src:find(to, a, true), "end marker: " .. to)
    return assert(loadstring("return function(" .. params .. ")\nreturn {\n" .. src:sub(a, b - 1) .. "\n}\nend", "=" .. file))()
end

-- 9. Refresh: what each shown item is stamped with: its group (_vg, always), and the marks of
-- the items the Pinned and Recent sections repeat (_vgPin, _vgRec, _vgOnly). As in All Items the
-- item stays in its group too; only a pinned item hidden in its category (_pinnedOnly) leaves it.
do
    local stamp = Block("EllesmereUIBags/EUI_Bags_Refresh.lua",
        "local view = EUI_CategoryManager:GetViewByIndex(selectedCategoryIndex)\n    if view then",
        "    -- 4b.",
        "EUI_CategoryManager, selectedCategoryIndex, displayItems, showPinned, pinnedSet, showRecent, EUI_Bags, IsItemPinned")
    local CM, profile, T = Load()
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
        for i, d in ipairs(items) do out[i] = { g = d._vg, pin = d._vgPin, rec = d._vgRec, only = d._vgOnly, junk = d._vgJunk } end
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
    for i = 1, 5 do check(r[i].junk == nil, "an item that is no junk is marked junk: " .. i) end
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

    -- 9b. Junk stays junk: what Sell Junk sells is never offered to the provider.
    -- 200 grey, 201 a grey quest item, 202 marked by the player, 203 grey but filed in
    -- another category, 204 no junk, and one whose link has not loaded.
    local asked
    local function JunkRun(keepPinned, pinSet)
        asked = {}
        CM:RegisterVirtualView("v", {
            classify = function(_, id) asked[id] = (asked[id] or 0) + 1; return "a" end,
            groups = { { id = "a" } }, keepPinned = keepPinned,
        })
        local list = {}
        for _, it in ipairs({ { 200, 0 }, { 201, 0 }, { 202, 2 }, { 203, 0 }, { 204, 1 } }) do
            list[#list + 1] = { itemLink = "item:" .. it[1], info = { itemID = it[1], quality = it[2] }, bag = 0, slot = it[1] }
        end
        -- no link yet, with stamps an earlier pass left
        list[6] = { info = { itemID = 100, quality = 1 }, bag = 0, slot = 6, _vg = 1, _vgJunk = true, _vgPin = true, _vgRec = true, _vgOnly = true }
        -- stamped junk by an earlier pass, no junk now
        list[5]._vgJunk = true
        stamp(CM, -10, list, true, pinSet, true, { _recentItems = nil }, IsPinned)
        return list
    end
    T.db.bagItemAssignments = { [202] = "Junk", [203] = "Armor" }
    pinCalls = 0
    local list = JunkRun(true, { [200] = true, [100] = true })
    check(list[1]._vgJunk == true and list[1]._vg == 0 and not asked[200], "a grey item is junk and is not offered to the provider")
    check(list[2]._vgJunk == nil and list[2]._vg == 1 and asked[201] == 1, "a grey quest item is no junk: offered")
    check(list[3]._vgJunk == true and not asked[202], "an item the player marked is junk whatever its quality")
    check(list[4]._vgJunk == nil and list[4]._vg == 1 and asked[203] == 1, "a grey item filed in another category is no junk: offered")
    check(list[5]._vgJunk == nil and list[5]._vg == 1 and asked[204] == 1, "an item that stopped being junk loses the mark")
    check(list[1]._vgPin == true, "pinned junk is still repeated in Pinned")
    check(list[6]._vg == nil and list[6]._vgJunk == nil and list[6]._vgPin == nil and list[6]._vgRec == nil and list[6]._vgOnly == nil,
        "an item whose link has not loaded is left unstamped, old stamps cleared")
    check(not asked[100] and pinCalls == 5, "and it is neither offered nor pin-tested: " .. pinCalls)
    -- the Junk Marker off: nothing is junk, everything is offered
    profile.bagShowJunkIcon = false
    list = JunkRun(nil, nil)
    for i = 1, 5 do
        check(list[i]._vgJunk == nil and list[i]._vg == 1, "the Junk Marker off: item " .. i .. " is offered and grouped")
    end
    check(asked[200] == 1 and asked[202] == 1, "the Junk Marker off: grey and marked items reach the provider")
    profile.bagShowJunkIcon = nil
    T.db.bagItemAssignments = nil

    -- 9c. The auto-size estimate counts the view's sections: its groups, Other, the
    -- kept Pinned / Recent, and our Junk section while the Junk Marker is on
    local estimate = Block("EllesmereUIBags/EUI_Bags_Refresh.lua",
        "            n = #displayItems\n            S = #view.groups + 1",
        "        elseif selectedCategoryIndex == -2 then",
        "displayItems, view, EUI_CategoryManager, n, S", "n, S")
    local n, S = estimate({ 1, 2, 3 }, { groups = { {}, {} }, keepPinned = true }, CM)
    check(n == 3 and S == 5, "the estimate with the Junk Marker on: " .. tostring(S))
    profile.bagShowJunkIcon = false
    n, S = estimate({ 1 }, { groups = { {}, {} }, keepPinned = true, keepRecent = true }, CM)
    check(n == 1 and S == 5, "the estimate with the Junk Marker off: " .. tostring(S))
    profile.bagShowJunkIcon = nil

    -- 9d. The list's options: Pinned and Recent only when the view keeps them, and the
    -- rules of every other selection unchanged
    local opts = Fields("EllesmereUIBags/EUI_Bags_Refresh.lua",
        "            view = view,\n", "        })\n        sf:SetPoint",
        "view, showRecent, isAllItems, selectedCategoryIndex, BP, EUI_Bags, isRecentView, displayItems, liveItems, liveEmpty, showPinned, pinnedSet")
    local P = {}
    local function BPs() return P end
    local bagsStub = { _recentItems = recent }
    local function Opts(view, sel, all)
        return opts(view, true, all, sel, BPs, bagsStub, false, {}, {}, nil, true, pins)
    end
    local o = Opts({ keepPinned = true, keepRecent = true }, -10, false)
    check(o.view ~= nil and o.pinned == pins and o.recent == recent, "a view that keeps both: the list gets both sets")
    o = Opts({ keepPinned = true }, -10, false)
    check(o.pinned == pins and o.recent == nil, "a view that keeps Pinned alone")
    o = Opts({ keepRecent = true }, -10, false)
    check(o.pinned == nil and o.recent == recent, "a view that keeps Recent alone")
    o = Opts({}, -10, false)
    check(o.pinned == nil and o.recent == nil, "a view that keeps neither: no sets, whatever the OneBag settings say")
    P.bagRecentInOneBag = true
    o = Opts({}, -10, false)
    check(o.pinned == nil and o.recent == nil, "a view is no slot view: the OneBag switches do not reach it")
    o = Opts(nil, -1, false)
    check(o.view == nil and o.pinned == pins and o.recent == recent, "OneBag keeps its own rules")
    P.bagRecentInOneBag, P.bagPinnedInOneBag = nil, false
    o = Opts(nil, -1, false)
    check(o.pinned == nil and o.recent == nil, "OneBag with both switched off")
    o = Opts(nil, 0, true)
    check(o.pinned == pins and o.recent == recent, "All Items keeps both")
    o = Opts(nil, 4, false)
    check(o.pinned == nil and o.recent == nil, "a category keeps neither")

    -- 9e. The header count: a view shows the whole bag, so it counts slots as All Items does
    local header = Block("EllesmereUIBags/EUI_Bags_Refresh.lua",
        "        local format = BP().bagSlotCountFormat",
        "        EUI_Bags.Header.itemCount:SetText(countText)",
        "BP, EllesmereUI, selectedCategoryIndex, EUI_CategoryManager, totalCount, FormatSlots, regularUsed, regularTotal, reagentUsed, reagentTotal",
        "countText")
    local EUIStub = { Lf = function(fmt, ...) return fmt:format(...) end }
    local function Slots(used, total) return used .. "/" .. total end
    local function Header(sel) return header(function() return {} end, EUIStub, sel, CM, 7, Slots, 10, 20, 1, 4) end
    check(Header(3) == "7 Items", "a category counts its items: " .. tostring(Header(3)))
    check(Header(0) == "11/24" and Header(-1) == "11/24" and Header(-2) == "11/24", "All Items, OneBag and MultiBag count slots")
    check(Header(-10) == "11/24", "a view counts slots: " .. tostring(Header(-10)))
    check(Header(-11) == "7 Items", "a selection number no view holds is no view: " .. tostring(Header(-11)))
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
    -- junk files in our own Junk section, never in a group or in Other
    adds = Run(view, {
        Item(20, 0, { _vgJunk = true }),
        Item(21, 0, { _vgJunk = true, _vgPin = true }),
        Item(22, 0, { _vgJunk = true, _vgPin = true, _vgOnly = true, _pinnedOnly = true }),
        Item(23, 0, { _vgJunk = true, _vgRec = true }),
    }, { [21] = true, [22] = true }, { [23] = true })
    w = Where(adds)
    check(w[20] == "junk", "junk is in the Junk section: " .. tostring(w[20]))
    check(w[21] == "junk,pinned" and w[23] == "junk,recent", "pinned or recent junk is repeated there as any item is: " .. tostring(w[21]) .. " / " .. tostring(w[23]))
    check(w[22] == "pinned", "pinned junk hidden in its category is in Pinned only: " .. tostring(w[22]))
    -- an item whose link has not loaded is not drawn
    adds = Run(view, { { info = { itemID = 30 }, categoryIndex = 1, _vg = 1, _lvQuality = 1 } }, nil, nil)
    check(#adds == 0, "an item with no link is not listed")
    -- not a view: the old behaviour stays (a pinned item shows in Pinned and in its category)
    adds = Run(nil, { Item(1, nil) }, { [1] = true }, { [1] = true })
    local keys = {}
    for _, a in ipairs(adds) do keys[#keys + 1] = tostring(a.key) end
    table.sort(keys)
    check(table.concat(keys, ",") == "1,pinned,recent", "not a view: pinned and recent items still show in their category too")
    adds = Run(nil, { Item(1, 0, { _vgJunk = true }) }, nil, nil)
    check(#adds == 1 and adds[1].key == 1, "not a view: a stale junk mark is not read")

    -- 10b. The section order: Pinned, Recent, the groups, Other, and Junk last, however
    -- few saved categories there are
    local sort = Block("EllesmereUIBags/EllesmereUIBags_List.lua",
        "    local RANK = { pinned = -2", "    local pinnedLabel, recentLabel",
        "view, EUI_CategoryManager, order")
    local function Order(v, saved, keyList)
        local order = {}
        for i, k in ipairs(keyList) do order[i] = { key = k } end
        sort(v, { GetSavedCount = function() return saved end }, order)
        local out = {}
        for i, b in ipairs(order) do out[i] = tostring(b.key) end
        return table.concat(out, ",")
    end
    check(Order(view, 1, { "junk", 3, 1, "recent", 2, "pinned" }) == "pinned,recent,1,2,3,junk",
        "a view's sections: " .. Order(view, 1, { "junk", 3, 1, "recent", 2, "pinned" }))
    check(Order(view, 40, { "junk", 3, 1 }) == "1,3,junk", "Junk is last with many saved categories too")
    check(Order(nil, 3, { 5, "junk", 3, 1, "pinned" }) == "pinned,1,3,junk,5",
        "not a view: Junk after the last saved category, virtual categories after it")

    -- 10c. A section's name and collapse key: a group's own, Other's, and ours for Junk
    local section = Block("EllesmereUIBags/EllesmereUIBags_List.lua",
        "        local label, secKey, count\n", "        count = count or (",
        "b, view, junkLabel, pinnedLabel, recentLabel, slotView, special, C_Container, L, ns, cats", "label, secKey")
    local CM = Load()
    CM:RegisterVirtualView("v", { otherName = "Rest", classify = Answer(nil),
        groups = { { id = "sell", name = "Sell", order = 1 }, { id = "keep", name = "Keep", order = 2 } } })
    local real = CM:GetViewByIndex(-10)
    local function Section(key, v)
        return section({ key = key, n = 0 }, v, "Trash", "Pins", "New", nil, nil, nil, function(s) return s end, {}, cats)
    end
    local label, key = Section(1, real)
    check(label == "Sell" and key == "Virtual:view:v:g:sell", "group 1's section: " .. tostring(label) .. " / " .. tostring(key))
    label, key = Section(2, real)
    check(label == "Keep" and key == "Virtual:view:v:g:keep", "group 2's section: " .. tostring(key))
    label, key = Section(3, real)
    check(label == "Rest" and key == "Virtual:view:v:other", "the Other section: " .. tostring(label) .. " / " .. tostring(key))
    label, key = Section("junk", real)
    check(label == "Trash" and key == "junk", "the Junk section is ours, under the Junk category's name")
    label, key = Section("pinned", real)
    check(label == "Pins" and key == "pinned", "the Pinned section is ours")
    label, key = Section("recent", real)
    check(label == "New" and key == "recent", "the Recent section is ours")
    label, key = Section(1, nil)
    check(label == "Cat" and key == "Cat", "not a view: the category's name and key")
end

-- 11. Grid: the lists a view draws (Pinned, Recent, one per group, Other, Junk)
do
    local bucket = Block("EllesmereUIBags/EllesmereUIBags_Grid.lua",
        "        local byGroup = { [-3] = {}, [-2] = {}, [-1] = {} }",
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
        Item(9, 0, { _vgJunk = true }),
        Item(10, 0, { _vgJunk = true, _vgPin = true }),
        Item(11, 0, { _vgJunk = true, _vgPin = true, _vgOnly = true }),
        Item(12, nil, { _vgPin = true, _vgRec = true, _vgJunk = true }),
    }
    local by = bucket(2, items)
    local function Ids(list) local o = {} for _, d in ipairs(list) do o[#o + 1] = d.id end return table.concat(o, ",") end
    check(Ids(by[-1]) == "1,3,8,10,11", "Pinned list: every marked item, also the ones hidden in their category: " .. Ids(by[-1]))
    check(Ids(by[-2]) == "2,3", "Recent list: " .. Ids(by[-2]))
    check(Ids(by[1]) == "1,2", "group 1 keeps its pinned and recent items, not the one hidden in its category: " .. Ids(by[1]))
    check(Ids(by[2]) == "3,4", "group 2: " .. Ids(by[2]))
    check(Ids(by[0]) == "5,7", "Other: group 0 and an unknown group: " .. Ids(by[0]))
    check(Ids(by[-3]) == "9,10", "Junk list: junk, also pinned junk, not the one hidden in its category: " .. Ids(by[-3]))
    by = bucket(2, { Item(1, 1), Item(2, 2) })
    check(#by[-1] == 0 and #by[-2] == 0 and #by[-3] == 0 and #by[1] == 1 and #by[2] == 1, "no marks: no Pinned, no Recent, no Junk, groups only")
    by = bucket(0, { Item(1, 0), Item(2, 0, { _vgJunk = true }) })
    check(Ids(by[0]) == "1" and Ids(by[-3]) == "2", "a view with no groups: Other and Junk")

    -- 11b. The sections drawn, in order: Pinned and Recent by the same switches as All
    -- Items, every group, Other, and Junk last under the Junk category's name
    local draw = Block("EllesmereUIBags/EllesmereUIBags_Grid.lua",
        "        -- Same switches as All Items: Show Pinned Items / Show Recent Items\n",
        "    else\n        if selectedGroupName then",
        "byGroup, view, showPinned, pinnedSet, BP, EUI_Bags, RenderViewSection, EllesmereUI, groups, nGroups, EUI_CategoryManager")
    local EUIStub = { L = function(s) return "<" .. s .. ">" end }
    local function Draw(by2, view, o)
        local calls = {}
        local profile = { bagShowRecentItems = o.recentShown }
        draw(by2, view, o.showPinned, o.pinnedSet, function() return profile end, { _recentItems = o.recentSet },
            function(label, list, kind) calls[#calls + 1] = label .. ":" .. #list .. (kind and (":" .. kind) or "") end,
            EUIStub, view.groups, #view.groups,
            { GetCategories = function() return o.cats or {} end, _junkCatIdx = o.junkIdx, JUNK_KEY = "Junk" })
        return table.concat(calls, " | ")
    end
    local view = { groups = { { name = "Sell" }, { name = "Keep" } }, otherName = "Rest", keepPinned = true, keepRecent = true }
    local function By(pin, rec, g1, g2, other, junk)
        local function N(n) local t = {} for i = 1, n do t[i] = i end return t end
        return { [-1] = N(pin), [-2] = N(rec), [-3] = N(junk), [0] = N(other), [1] = N(g1), [2] = N(g2) }
    end
    local cats = { { name = "Armor" }, { name = "Trash", isJunk = true } }
    local got = Draw(By(1, 2, 3, 0, 4, 5), view, { showPinned = true, pinnedSet = {}, recentSet = {}, cats = cats, junkIdx = 2 })
    check(got == "<Pinned Items>:1:pinned | <Recent Items>:2:recent | Sell:3 | Keep:0 | Rest:4 | Trash:5", "the sections of a view: " .. got)
    got = Draw(By(0, 0, 1, 1, 0, 0), view, { showPinned = true, pinnedSet = {}, recentSet = {}, cats = cats, junkIdx = 2 })
    check(got == "<Pinned Items>:0:pinned | <Recent Items>:0:recent | Sell:1 | Keep:1 | Rest:0",
        "kept Pinned and Recent draw while empty (their + cell, their hint); no Junk section without junk: " .. got)
    got = Draw(By(0, 0, 1, 1, 0, 0), view, { showPinned = false, pinnedSet = {}, recentSet = {}, recentShown = false, cats = cats })
    check(got == "Sell:1 | Keep:1 | Rest:0", "Show Pinned Items and Show Recent Items off: " .. got)
    got = Draw(By(0, 0, 1, 1, 2, 3), { groups = view.groups, otherName = "Rest" }, { showPinned = true, pinnedSet = {}, recentSet = {}, cats = cats, junkIdx = 2 })
    check(got == "Sell:1 | Keep:1 | Rest:2 | Trash:3", "a view that keeps neither: " .. got)
    got = Draw(By(0, 0, 0, 0, 0, 1), { groups = {}, otherName = "Other" }, { cats = cats })
    check(got == "Other:0 | Junk:1", "no junk category found: the Junk section still draws, under its key: " .. got)
end

-- 12. The sidebar: a view is one more fixed entry of the top list, after the three
-- built-in ones and before the offline Bank
do
    local make = Block("EllesmereUIBags/EUI_Bags_Sidebar.lua",
        "local function OfflineBankOn()", "local function GetSidebarWidth()",
        "ns, EUI_CategoryManager", "FixedViewCount, OfflineBankOn")
    local views
    local CMStub = { GetViews = function() return views end }
    local offline = false
    local nsStub = { Offline = { Enabled = function() return offline end } }
    local Count, BankOn = make(nsStub, CMStub)
    check(Count() == 3 and BankOn() == false, "no view, no offline bank: three fixed entries")
    offline = true
    check(Count() == 4 and BankOn() == true, "the offline bank adds one")
    views = { { idx = -10, name = "One", icon = 1 }, { idx = -11, name = "Two", icon = 2, isAtlas = true } }
    check(Count() == 6, "two views add two: " .. Count())
    offline = false
    check(Count() == 5, "two views without the offline bank: " .. Count())
    check(make({}, CMStub)() == 5, "no offline module at all")

    local entries = Block("EllesmereUIBags/EUI_Bags_Sidebar.lua",
        "    -- virtual views (EUI_CategoryManager:RegisterVirtualView), after the three\n",
        "    -- Split-mode set children",
        "EUI_CategoryManager, displayList, totalCount, OfflineBankOn, EllesmereUI")
    local function Entries(bank)
        local list = { { catIdx = 0 }, { catIdx = -1 }, { catIdx = -2 } }
        entries(CMStub, list, 42, function() return bank end, { L = function(s) return s end })
        local out = {}
        for i, e in ipairs(list) do out[i] = tostring(e.catIdx) end
        return table.concat(out, ","), list
    end
    local order, list = Entries(true)
    check(order == "0,-1,-2,-10,-11,-3", "the top list with two views and the offline bank: " .. order)
    check(list[4].name == "One" and list[4].icon == 1 and list[4].count == 42 and list[5].isAtlas == true,
        "a view's entry carries its name, icon and the bag's item count")
    check(Entries(false) == "0,-1,-2,-10,-11", "without the offline bank")
    views = nil
    check(Entries(true) == "0,-1,-2,-3" and Entries(false) == "0,-1,-2", "no view: the list as before")
end

-- 13. The stack splitter: a view draws no empty slots, so a split places its stack
-- once, as in All Items and a category
do
    local rule = Block("EllesmereUIBags/EUI_Bags_Shared.lua",
        "        local placeOnce = (window == EUI_Bags", "        if not placeOnce and BP().bagStackSplitter",
        "window, EUI_Bags, selectedCategoryIndex, EUI_CategoryManager", "placeOnce")
    local CM = Load()
    CM:RegisterVirtualView("v", { classify = Answer(nil) })
    local bags, bank = {}, {}
    check(rule(bags, bags, 0, CM) == true and rule(bags, bags, 6, CM) == true, "All Items and a category place once")
    check(rule(bags, bags, -1, CM) == false and rule(bags, bags, -2, CM) == false, "OneBag and MultiBag do not")
    check(rule(bags, bags, -10, CM) == true, "a view places once")
    check(rule(bags, bags, -11, CM) == false and rule(bags, bags, -3, CM) == false, "a number no view holds does not")
    check(rule(bank, bags, -10, CM) == false and rule(bank, bags, 0, CM) == false, "another window never does")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_bags_virtual_views (" .. count .. " checks)")
