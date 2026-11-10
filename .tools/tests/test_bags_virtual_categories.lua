-- Stub harness: Bags virtual categories (RegisterVirtualCategory in
-- EllesmereUIBags_Categories.lua). The real category file runs over stubs, and
-- the parts of the other Bags files that key on virtual categories are cut out
-- by text anchors.
--   runtime-only: after every saved category and after Junk, nothing of them in
--     the saved data, an unregistered provider leaves nothing behind, and with
--     no provider nothing changes
--   providers are asked before the built-in rules, never for an item the user
--     filed or marked, and never for junk (what Sell Junk sells stays in Junk)
--   a change rebuilds the list at once and repaints once, on the next frame; a
--     provider cannot register, unregister or ask for a repaint from inside its
--     own classify call
--   Sort Items orders a virtual category for the session; its sidebar row has
--     no menu and takes no drop; the list view files Junk before them
--   lua .tools/tests/test_bags_virtual_categories.lua        (from the repository root)
local CATEGORIES = BVC_CATEGORIES or "EllesmereUIBags/EllesmereUIBags_Categories.lua"
local DATA = BVC_DATA or "EllesmereUIBags/EUI_Bags_Data.lua"
local SIDEBAR = BVC_SIDEBAR or "EllesmereUIBags/EUI_Bags_Sidebar.lua"
local LIST = BVC_LIST or "EllesmereUIBags/EllesmereUIBags_List.lua"
local OFFLINE = BVC_OFFLINE or "EllesmereUIBags/EllesmereUIBags_OfflineView.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function ReadSource(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

-- The text from `from` to the first `to` after it, both included.
local function Cut(src, what, from, to)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b, e = src:find(to, a, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
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

local function Wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local IC = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7,
    ItemEnhancement = 8, Recipe = 9, Questitem = 12, Miscellaneous = 15 }

-- item id -> class id (what GetItemInfoInstant would say)
local ITEMS = { [100] = IC.Armor, [101] = IC.Consumable, [102] = IC.Armor, [103] = IC.Miscellaneous,
    [104] = IC.Questitem }

local CATEGORY_SRC = ReadSource(CATEGORIES)

-- A fresh manager over stubs. opts.bags: false = no EUI_Bags global.
-- T.Flush() is one frame: it runs the update of every shown frame and returns how many ran.
local function Load(opts)
    opts = opts or {}
    local T = { repaints = 0, bankPaints = 0, errors = 0, invalidated = 0, frames = {} }
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
        wipe = Wipe,
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
    function T.Flush()
        local ran = 0
        for _, f in ipairs(T.frames) do
            if f.shown and f.update then
                ran = ran + 1
                f.update(f, 0)
            end
        end
        return ran
    end
    local ns = { SpecialBags = function() return nil end, RefreshOpenBank = function() T.bankPaints = T.bankPaints + 1 end }
    local chunk = assert(loadstring(CATEGORY_SRC, "=EllesmereUIBags_Categories.lua"))
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

-------------------------------------------------------------------------------
-- 1. No provider: the list and the saved data are what they were
-------------------------------------------------------------------------------
local saved
do
    local CM, profile, T = Load()
    local base = Names(CM)
    CM:SaveState()
    saved = Dump(profile)
    check(#base > 5, "default categories built")
    check(not CM:IsVirtual(#base), "IsVirtual: false for the last real category")
    check(not CM:IsVirtual(nil), "IsVirtual(nil) is false")
    check(CM:GetSavedCount() == #base, "GetSavedCount is the whole list without providers")
    check(not CM:UnregisterVirtualCategory("nope"), "unregistering an unknown id is false")
    CM:RefreshVirtualCategories()  -- nothing registered: must not error
    check(#T.frames == 0 and T.Flush() == 0, "with no provider no frame is built and nothing repaints")
end

-------------------------------------------------------------------------------
-- 2. A provider: tail of the list, nothing saved, no index moves
-------------------------------------------------------------------------------
do
    local CM, profile, T = Load()
    local base = Names(CM)
    check(CM:RegisterVirtualCategory("T.Sell", { name = "Provider: Sell", icon = 134400, order = 2, classify = ClaimIDs(100) }),
        "register returns true")
    check(T.invalidated == 1, "registering rebuilds the list at once")
    check(T.repaints == 0 and T.Flush() == 1 and T.repaints == 1 and T.bankPaints == 1, "and repaints once, on the next frame")
    check(CM:IsVirtual(#base + 1), "IsVirtual answers for the new tail before anything read the list again")
    local cats = CM:GetCategories()
    check(#cats == #base + 1, "one category added")
    check(cats[#cats].isVirtual and cats[#cats]._defaultName == "Virtual:T.Sell", "the virtual category is last")
    check(cats[#cats].name == "Provider: Sell" and cats[#cats].noGroup and cats[#cats].noMove, "name, noGroup, noMove")
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
end

-------------------------------------------------------------------------------
-- 3. Reordering: nothing moves among or after the virtual tail
-------------------------------------------------------------------------------
do
    local CM, profile = Load()
    CM:RegisterVirtualCategory("A", { name = "A", classify = ClaimIDs(1) })
    CM:RegisterVirtualCategory("B", { name = "B", order = -1, classify = ClaimIDs(2) })
    local cats = CM:GetCategories()
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
end

-------------------------------------------------------------------------------
-- 4. Claim order, errors, re-registering, unregistering
-------------------------------------------------------------------------------
do
    local CM, profile = Load()
    local asked = {}
    CM:RegisterVirtualCategory("late", { name = "Late", order = 5, classify = function(l, id) asked[#asked + 1] = "late"; return id == 100 end })
    CM:RegisterVirtualCategory("early", { name = "Early", order = 1, classify = function(l, id, bag, slot, q)
        asked[#asked + 1] = "early:" .. tostring(bag) .. ":" .. tostring(slot) .. ":" .. tostring(q)
        return id == 100
    end })
    local cats = CM:GetCategories()
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
    check(CM:RegisterVirtualCategory("ok", { name = "Ok2", order = 1, classify = ClaimIDs(103) }), "register again, after a provider error")
    cats = CM:GetCategories()
    check(#cats == CM:GetSavedCount() + 2 and cats[#cats].name == "Ok2", "an id registered again is replaced")

    check(not CM:RegisterVirtualCategory("", { classify = ClaimIDs() }), "empty id refused")
    check(not CM:RegisterVirtualCategory(5, { classify = ClaimIDs() }), "non-string id refused")
    check(not CM:RegisterVirtualCategory("x", { name = "X" }), "no classify refused")
    check(not CM:RegisterVirtualCategory("x"), "no def refused")

    -- unregistering: back to the original list and saved data
    local CM5, profile5 = Load()
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

    -- with no EUI_Bags yet: the list is dropped for the next build
    local CM6 = Load({ bags = false })
    CM6:RegisterVirtualCategory("z", { name = "Z", classify = ClaimIDs(100) })
    local c6 = CM6:GetCategories()
    check(c6[#c6]._defaultName == "Virtual:z", "a provider registered before the bags exist still builds")
end

-------------------------------------------------------------------------------
-- 5. Junk is not offered: what Sell Junk sells stays in the Junk category
-------------------------------------------------------------------------------
do
    local CM, profile = Load()
    local asked = 0
    CM:RegisterVirtualCategory("keep", { name = "Keep", classify = function(l, id)
        asked = asked + 1
        return id == 103 or id == 100 or id == 104
    end })
    local cats = CM:GetCategories()
    local vIdx, junkIdx = #cats, IndexOf(CM, "Junk")
    local items = {
        { bag = 0, slot = 1, info = { itemID = 103, quality = 0 }, itemLink = "item:103" },
        { bag = 0, slot = 2, info = { itemID = 100, quality = 1 }, itemLink = "item:100" },
    }
    CM:ClassifyAll(items)
    check(junkIdx and items[1].categoryIndex == junkIdx, "a grey item stays in Junk while the Junk Marker is on")
    check(CM:IsJunk(103, 0), "and it is what Sell Junk calls junk")
    check(items[2].categoryIndex == vIdx, "the item beside it is still claimed")
    check(asked == 1, "the provider was not asked about the junk item")
    -- a grey item of the quest class is no junk, so it is offered
    check(not CM:IsJunk(104, 0) and CM:ClassifyItem("item:104", 104, 0, 3, 0) == vIdx, "a grey quest item is no junk and is offered")
    -- a marked item is junk whatever its quality
    CM:AssignItem(100, CM.JUNK_KEY)
    asked = 0
    check(CM:ClassifyItem("item:100", 100, 0, 2, 1) == junkIdx and asked == 0, "a marked item stays in Junk, unasked")
    CM:UnassignItem(100)

    -- Junk Marker off: nothing is junk, so a grey item is offered like any other
    CM, profile = Load()
    profile.bagShowJunkIcon = false
    CM:InitCategories()
    CM:RegisterVirtualCategory("keep", { name = "Keep", classify = ClaimIDs(103) })
    cats = CM:GetCategories()
    items = { { bag = 0, slot = 1, info = { itemID = 103, quality = 0 }, itemLink = "item:103" } }
    CM:ClassifyAll(items)
    check(not CM:IsJunk(103, 0) and items[1].categoryIndex == #cats, "with the Junk Marker off a grey item is offered")
end

-------------------------------------------------------------------------------
-- 6. One repaint per frame; nothing from inside a classify call
-------------------------------------------------------------------------------
do
    local CM, _, T = Load()
    CM:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    CM:RegisterVirtualCategory("b", { name = "B", classify = ClaimIDs(101) })
    CM:RefreshVirtualCategories()
    CM:UnregisterVirtualCategory("a")
    check(T.invalidated == 3, "each change of the list rebuilds it at once")
    check(T.repaints == 0 and T.bankPaints == 0, "nothing is repainted inside the calls")
    check(T.Flush() == 1 and T.repaints == 1 and T.bankPaints == 1, "one repaint of the bags and the bank on the next frame")
    check(T.Flush() == 0 and T.repaints == 1, "and none on the frame after")
    CM:RefreshVirtualCategories()
    check(T.invalidated == 3 and T.Flush() == 1 and T.repaints == 2, "a refresh repaints without rebuilding the list")
    check(#T.frames == 1, "one frame serves every request")
    CM:UnregisterVirtualCategory("b")
    check(T.Flush() == 1, "unregistering repaints on the next frame too")
    local before = T.repaints
    CM:RefreshVirtualCategories()
    check(T.Flush() == 0 and T.repaints == before, "with the last provider gone a refresh asks for nothing")

    -- from inside a classify call
    local inner = {}
    CM, _, T = Load()
    CM:RegisterVirtualCategory("re", { name = "Re", classify = function(l, id)
        inner.reg = CM:RegisterVirtualCategory("x", { name = "X", classify = function() return false end })
        inner.unreg = CM:UnregisterVirtualCategory("re")
        CM:RefreshVirtualCategories()
        return id == 100
    end })
    T.Flush()
    local n, rebuilt = #CM:GetCategories(), T.invalidated
    check(CM:ClassifyItem("item:100", 100, 0, 1, 1) == n, "a provider that calls back in still gets its claim")
    check(inner.reg == false and inner.unreg == false, "it cannot register or unregister from inside its classify call")
    check(#CM:GetCategories() == n and T.invalidated == rebuilt, "the list stays as it was")
    check(T.Flush() == 0, "and it cannot ask for a repaint from there")
    check(CM:RegisterVirtualCategory("x", { name = "X", classify = ClaimIDs() }) and #CM:GetCategories() == n + 1,
        "once the pass is over, registering works again")

    -- a kept reference to the refresh function still reports to its watchers
    CM = Load()
    CM:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    local kept, told = CM.RefreshVirtualCategories, 0
    local plain = CM.OnVirtualAnswersChanged
    check(type(plain) == "function", "the manager has the method the offline views watch")
    CM.OnVirtualAnswersChanged = function(...) told = told + 1; return plain(...) end
    kept(CM)
    check(told == 1, "a kept reference to RefreshVirtualCategories reports through it")

    -- the offline views watch that method
    local hooked = {}
    local Watch = assert(loadstring("local hooksecurefunc = ...\nlocal catHooked\nlocal function BumpCat() end\n"
        .. Cut(ReadSource(OFFLINE), "offline watch", "local function WatchCategories()", "\nend\n")
        .. "return WatchCategories\n", "=OfflineWatch"))(function(_, name) hooked[name] = true end)
    local old = rawget(_G, "EUI_CategoryManager")
    EUI_CategoryManager = CM
    Watch()
    EUI_CategoryManager = old
    check(hooked.OnVirtualAnswersChanged and hooked.InitCategories and hooked.OnEquipmentSetsChanged,
        "the offline views bump their memo on a refresh and on a rebuild")
end

-------------------------------------------------------------------------------
-- 7. The visual order (EUI_Bags_Data.lua): a virtual category's is kept for the
--    session under its key, and never saved
-------------------------------------------------------------------------------
do
    local SRC = ReadSource(DATA)
    local a = assert(SRC:find("local function GetVisualOrder()", 1, true), "GetVisualOrder missing")
    local s = assert(SRC:find("local function DetectAndApplySwaps(", a, true), "DetectAndApplySwaps missing")
    local _, e = SRC:find("\nend\n", s, true)
    assert(e, "end of DetectAndApplySwaps missing")
    local BLOCK = SRC:sub(a, e)
    local CM, profile = Load()
    CM:RegisterVirtualCategory("a", { name = "A", order = 5, classify = ClaimIDs(100) })
    local vIdx = #CM:GetCategories()
    local chunk = assert(loadstring("local BP, EUI_CategoryManager, wipe = ...\n" .. BLOCK
        .. "\nreturn SaveCategoryOrder, ApplySavedOrder, TakeBagSnapshot, DetectAndApplySwaps", "=EUI_Bags_Data.lua"))
    local Save, Apply, Snapshot, Swaps = chunk(function() return profile end, CM, Wipe)
    local function List(first, second)
        return {
            { info = { itemID = first }, bag = 0, slot = 1 },
            { info = { itemID = second }, bag = 0, slot = 2 },
        }
    end
    Save(vIdx, List(5, 6))
    check(profile.bagVisualOrder == nil, "a virtual category's order is not saved")
    local list = List(6, 5)
    Apply(vIdx, list)
    check(list[1].info.itemID == 5 and list[2].info.itemID == 6, "but it holds for the session")
    -- a stale saved entry at its index is never read
    profile.bagVisualOrder = { [vIdx] = { 6, 5 } }
    list = List(6, 5)
    Apply(vIdx, list)
    check(list[1].info.itemID == 5, "a saved order left at its index is not applied")
    profile.bagVisualOrder = nil
    -- the order follows the category when another provider moves its index
    CM:RegisterVirtualCategory("b", { name = "B", order = 1, classify = ClaimIDs(101) })
    check(#CM:GetCategories() == vIdx + 1 and CM:GetCategories()[vIdx + 1]._defaultName == "Virtual:a", "the first provider moved up one index")
    list = List(6, 5)
    Apply(vIdx + 1, list)
    check(list[1].info.itemID == 5, "its order moved with it")
    list = List(6, 5)
    Apply(vIdx, list)
    check(list[1].info.itemID == 6 and list[1]._savedPos == nil, "and the category now at the old index has none")
    -- a manual swap of two items follows in the session order
    Snapshot(List(5, 6))
    check(Swaps(List(6, 5), true) == true, "a swap of two items is seen")
    list = List(5, 6)
    Apply(vIdx + 1, list)
    check(list[1].info.itemID == 6, "and the session order follows the swap")
    -- real categories and groups as before
    Save(2, List(5, 6))
    check(profile.bagVisualOrder and profile.bagVisualOrder[2] and #profile.bagVisualOrder[2] == 2, "a real category's order still saves")
    list = List(6, 5)
    Apply(2, list)
    check(list[1].info.itemID == 5 and list[1]._savedPos == 1, "a real category's order still applies")
    Save("Some Group", List(5, 6))
    check(profile.bagVisualOrder["Some Group"], "a group name key still saves")
    check(not Dump(profile):find("Virtual", 1, true), "no 'Virtual' in the saved data")
end

-------------------------------------------------------------------------------
-- 8. The sidebar: a virtual row has no menu and takes no drop
-------------------------------------------------------------------------------
do
    local SRC = ReadSource(SIDEBAR)
    local CM = Load()
    CM:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    local cats = CM:GetCategories()
    local vIdx = #cats

    local menus = 0
    local ShowMenu = assert(loadstring("local EUI_CategoryManager, MenuUtil = ...\n"
        .. Cut(SRC, "category menu", "local function ShowCategoryContextMenu(btn, catIdx, isGroupHeader, isGroupMember)", "\nend\n")
        .. "return ShowCategoryContextMenu\n", "=SidebarMenu"))(CM, { CreateContextMenu = function() menus = menus + 1 end })
    ShowMenu({}, vIdx)
    check(menus == 0, "a right click on a virtual row builds no menu")
    ShowMenu({}, IndexOf(CM, "Armor"))
    check(menus == 1, "a right click on a real category still builds one")

    -- the drag update: what a hovered row offers the dragged category
    local body = Cut(SRC, "drag update", '_dragUpdateFrame:SetScript("OnUpdate", function()', "\nend)\n")
    body = "local OnDragUpdate = function()" .. body:sub(#'_dragUpdateFrame:SetScript("OnUpdate", function()' + 1, -#"end)\n" - 1) .. "end\n"
    local Drag = assert(loadstring([[
local EUI_CategoryManager, S = ...
local _dragFromCatIdx, _dragGhost, _dragLastTarget, _dragLastMode, _dragLastBtn = S.from
local _dragDropMode, _dragDropTarget, _dragTargetIsHeader, _dragInsertGroup
local SIDEBAR_PAD, SIDEBAR_INDENT = 2, 16
local _dragUpdateFrame = { Hide = function() end }
local function Region()
    return { shown = false, Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
        ClearAllPoints = function() end, SetPoint = function() end }
end
local line, hl = Region(), Region()
local function ComputeDropZone() return S.target, S.mode, S.btn end
local function EnsureInsertLine() return line end
local function EnsureGroupHighlight() return hl end
local function GetInsertLineY() return 0 end
local EUI_Bags = {}
]] .. body .. "OnDragUpdate()\nreturn _dragDropMode, _dragDropTarget, line.shown\n", "=SidebarDrag"))
    local from = IndexOf(CM, "Armor")
    local mode, target, lineShown = Drag(CM, { from = from, target = vIdx, mode = "above", btn = {} })
    check(mode == nil and target == nil and not lineShown, "hovering a virtual row offers no drop above it")
    mode, target, lineShown = Drag(CM, { from = from, target = vIdx, mode = "below", btn = {} })
    check(mode == nil and target == nil and not lineShown, "nor below it")
    mode, target, lineShown = Drag(CM, { from = from, target = vIdx, mode = "group", btn = {} })
    check(mode == nil and target == nil, "nor a group with it")
    local real = IndexOf(CM, "Consumables")
    mode, target, lineShown = Drag(CM, { from = from, target = real, mode = "below", btn = {} })
    check(mode == "insert" and target == real + 1 and lineShown, "a real category still takes the drop")
    mode, target = Drag(CM, { from = from, target = 1, mode = "above", btn = {} })
    check(mode == nil and target == nil, "the pinned row at the top is blocked as before")
end

-------------------------------------------------------------------------------
-- 9. The list view: Junk sorts after the last saved category, before the tail
-------------------------------------------------------------------------------
do
    local SRC = ReadSource(LIST)
    local Sort = assert(loadstring("local EUI_CategoryManager, order = ...\n"
        .. Cut(SRC, "list section order", "    -- Pinned first, category (or bag) order", "    end)\n")
        .. "return order\n", "=ListOrder"))
    local function Keys(order)
        local out = {}
        for i, b in ipairs(order) do out[i] = tostring(b.key) end
        return table.concat(out, ",")
    end
    local CM = Load()
    local n = #CM:GetCategories()
    check(Keys(Sort(CM, { { key = "junk" }, { key = n - 1 }, { key = "pinned" }, { key = 3 } })) == "pinned,3," .. (n - 1) .. ",junk",
        "with no provider Junk is the last section")
    CM:RegisterVirtualCategory("a", { name = "A", classify = ClaimIDs(100) })
    CM:RegisterVirtualCategory("b", { name = "B", classify = ClaimIDs(101) })
    check(Keys(Sort(CM, { { key = n + 2 }, { key = "junk" }, { key = n + 1 }, { key = n - 1 }, { key = "recent" } }))
        == "recent," .. (n - 1) .. ",junk," .. (n + 1) .. "," .. (n + 2), "with providers their sections follow Junk")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_bags_virtual_categories (" .. count .. " checks)")
