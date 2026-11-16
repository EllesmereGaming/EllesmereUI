-- Stub harness: the Merchant card's Flag/Hide Owned Items (Blizzard Skins+).
-- Cuts the feature's own section out of EllesmereUIBlizzardSkin_WindowPacks.lua
-- (from its first constant to the line before the Merchant skin function) and
-- runs it over a stand-in vendor: items by index and item ID, their tooltips,
-- the filter that re-maps the indexes, and frames that record what they are
-- told. The file's other locals the section reads (the grid, the list, the
-- window skin helpers) are stand-ins the test counts.
--   lua .tools/tests/test_blizzskin_merchant_owned.lua        (from the repository root)
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 40 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local FILE = Read("EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_WindowPacks.lua")
local A = assert(FILE:find("local OWNED_WASH_ALPHA = 0.22", 1, true), "the section's first line is gone")
local B = assert(FILE:find("\nlocal _merchantHooked = false", A, true), "the section's end is gone")
local SECTION = [[
local H = ...
local owned = {}
local ex = H.ex
local EX_NATIVE_PER_PAGE = 10
local WSkin = H.WSkin
local function ExpandActive() return H.expand end
local function EX_Update() H.exUpdates = H.exUpdates + 1 end
local function EX_ReleaseSplit() return H.splitFree end
local function UpdateCustomMerchantList(sf, child) H.listUpdates = H.listUpdates + 1; H.listArgs = { sf, child } end
]] .. FILE:sub(A, B) .. [[
return { owned = owned, SetOwnedActive = SetOwnedActive, MerchantItemKnown = MerchantItemKnown,
    BuildOwnedList = BuildOwnedList, OwnedVisible = OwnedVisible, MarkOwnedNative = MarkOwnedNative,
    MarkOwnedTile = MarkOwnedTile, MarkOwnedRow = MarkOwnedRow, SyncOwnedButton = SyncOwnedButton,
    OwnedOn = OwnedOn, events = ownedEvents, list = knownList, Count = function() return ownedCount end,
    washes = ownedWash }
]]
-- the names the grid and the list read on the shared table
check(FILE:find("if owned.markRow then owned.markRow(row, i, isBuyback) end", 1, true), "the list asks the feature per row, only once it is on")
check(FILE:find("if owned.markTile then owned.markTile(tile, index) end", 1, true), "the grid asks the feature per tile, only once it is on")
check(FILE:find("local list = owned.visible and owned.visible()", 1, true), "the grid asks which items show, only once it is on")
check(FILE:find("if OwnedOn() then SetOwnedActive(true) end", 1, true), "the Merchant skin turns the feature on only while its setting is on")

-------------------------------------------------------------------------------
--  The world: one vendor
-------------------------------------------------------------------------------
-- o: db (EllesmereUIDB), petKnown (the client's ITEM_PET_KNOWN), shown (the
-- vendor window is open at load)
local function World(o)
    o = o or {}
    local w = { created = 0, hooks = {}, tips = 0, idReads = 0, frames = {} }
    local function Obj(kind, parent)
        local t = { _kind = kind, _parent = parent, _shown = true, _level = 3, _points = {}, _regions = {}, _color = { 1, 1, 1 } }
        return setmetatable(t, { __index = function(_, k)
            if type(k) ~= "string" or not k:find("^%u") then return nil end
            if k == "GetFrameLevel" then return function(s) return s._level end end
            if k == "SetFrameLevel" then return function(s, v) s._level = v end end
            if k == "CreateTexture" then return function(s, _, layer) local r = Obj("texture", s); r._layer = layer; s._regions[#s._regions + 1] = r; return r end end
            if k == "GetFontString" then return function(s) s._fs = s._fs or Obj("fontstring", s); return s._fs end end
            if k == "GetStringWidth" then return function() return 80 end end
            if k == "Show" then return function(s) s._shown = true end end
            if k == "Hide" then return function(s) s._shown = false end end
            if k == "IsShown" then return function(s) return s._shown end end
            if k == "SetShown" then return function(s, v) s._shown = v and true or false end end
            if k == "SetPoint" then return function(s, ...) s._points[#s._points + 1] = { ... } end end
            if k == "SetColorTexture" then return function(s, r, g, b, a) s._tex = { r, g, b, a } end end
            if k == "SetVertexColor" then return function(s, r, g, b) s._color = { r, g, b } end end
            if k == "GetVertexColor" then return function(s) return s._color[1], s._color[2], s._color[3] end end
            if k == "RegisterEvent" then return function(s, e) s._events = s._events or {}; s._events[e] = true; s._regs = (s._regs or 0) + 1 end end
            if k == "UnregisterEvent" then return function(s, e) if s._events then s._events[e] = nil end end end
            if k == "UnregisterAllEvents" then return function(s) s._events = {} end end
            if k == "SetScript" then return function(s, n, fn) s["_on" .. n] = fn end end
            if k == "SetFormattedText" then return function(s, fmt, ...) s._text = fmt:format(...) end end
            if k == "SetWidth" then return function(s, v) s._w = v end end
            if k == "SetEnabled" then return function(s, v) s._enabled = v and true or false end end
            if k == "GetID" then return function(s) return s._id or 0 end end
            return function() end
        end })
    end
    w.Obj = Obj
    -- the vendor: items in merchant order (item IDs); filter: a function that picks which show
    w.items = { 11, 12, 13, 14, 15, 16 }
    w.known = { [12] = "Already known", [14] = "Collected (1/3)" }
    w.loaded = {}
    for _, id in ipairs(w.items) do w.loaded[id] = true end
    w.filter = 0
    local function Visible()
        if w.filter == 0 then return w.items end
        local t = {}
        for i = #w.items, 1, -1 do t[#t + 1] = w.items[i] end   -- another filter: the same goods, other indexes
        return t
    end
    local H = { ex = { page = 3 }, expand = false, exUpdates = 0, listUpdates = 0, splitFree = true, debounced = 0,
        WSkin = { Button = function() end, StateButtonLabel = function() end } }
    H.WSkin.Debounce = function(fn) return function() H.debounced = H.debounced + 1; H.redraw = fn end end
    w.H = H
    local merchant = Obj("Frame")
    merchant._shown = o.shown or false
    merchant.selectedTab = 1
    merchant.FilterDropdown = Obj("Frame")
    w.merchant = merchant
    local tiles = {}
    for i = 1, 10 do
        local tile = Obj("Frame")
        tile.ItemButton = Obj("Button", tile)
        tile.ItemButton.icon = Obj("texture", tile.ItemButton)
        tile.ItemButton._id = i
        tiles[i] = tile
    end
    w.tiles = tiles
    local env = setmetatable({
        EllesmereUIDB = o.db or {},
        EllesmereUI = { L = function(s) return s end, ShowWidgetTooltip = function(_, text) w.tooltip = text end,
            HideWidgetTooltip = function() w.tooltip = nil end },
        ITEM_PET_KNOWN = o.petKnown or "Collected (%d/%d)",
        ITEM_SPELL_KNOWN = "Already known",
        MerchantFrame = merchant,
        GetMerchantNumItems = function() return #Visible() end,
        GetMerchantFilter = function() return w.filter end,
        GetMerchantItemID = function(i) w.idReads = w.idReads + 1; return Visible()[i] end,
        C_Item = { IsItemDataCachedByID = function(id) return w.loaded[id] or false end },
        C_TooltipInfo = { GetMerchantItem = function(i)
            w.tips = w.tips + 1
            local id = Visible()[i]
            return { lines = { { leftText = "Item " .. tostring(id) }, { leftText = w.known[id] } } }
        end },
        CreateFrame = function(kind, _, parent)
            local f = Obj(kind, parent)
            w.created = w.created + 1
            w.frames[#w.frames + 1] = f
            return f
        end,
        hooksecurefunc = function(name, fn) w.hooks[#w.hooks + 1] = { name = name, fn = fn } end,
        SetItemButtonTextureVertexColor = function(btn, r, g, b) btn._tex = { r, g, b }; if btn.icon then btn.icon._color = { r, g, b } end end,
        SetItemButtonNormalTextureVertexColor = function(btn, r, g, b) btn._normal = { r, g, b } end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    }, { __index = _G })
    for i = 1, 10 do env["MerchantItem" .. i] = tiles[i] end
    env._G = env
    w.env = env
    w.db = env.EllesmereUIDB
    w.F = setfenv(assert(loadstring(SECTION, "=owned items")), env)(H)
    function w.Events() local n = 0 for _ in pairs(w.F.events._events or {}) do n = n + 1 end return n end
    function w.Fire(e) w.F.events._onOnEvent(w.F.events, e) end
    function w.Wash(frame) return w.F.washes[frame] end
    return w
end
local COLLECTION = { "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "NEW_RECIPE_LEARNED" }

-------------------------------------------------------------------------------
-- 1. Off: nothing hooked, registered or handed to the grid and the list
-------------------------------------------------------------------------------
do
    local w = World()
    eq(#w.hooks, 0, "off: no hook")
    eq(w.Events(), 0, "off: no event")
    eq(w.created, 1, "off: one frame at load (the event frame)")
    local o = w.F.owned
    eq(o.markRow or o.markTile or o.visible or o.syncButton, nil, "off: the grid and the list are handed nothing")
    eq(w.F.OwnedOn(), false, "the setting is off by default")
    w.db.merchantMarkOwned = true
    eq(w.F.OwnedOn(), true, "on with the Merchant skin")
    w.db.reskinMerchant = false
    eq(w.F.OwnedOn(), false, "never without the Merchant skin")
    w.db.reskinMerchant = nil
    w.db.merchantMarkOwned = "yes"
    eq(w.F.OwnedOn(), false, "only a real true turns it on")
    eq(w.tips + w.idReads, 0, "off: the vendor is never read")
end

-------------------------------------------------------------------------------
-- 2. On and off: the hook once, the events while on, all of it released
-------------------------------------------------------------------------------
do
    local w = World()
    w.F.SetOwnedActive(true)
    eq(#w.hooks, 1, "on: one hook")
    eq(w.hooks[1].name, "MerchantFrame_Update", "on Blizzard's page update")
    eq(w.Events(), 2, "on, no vendor open: two events")
    check(w.F.events._events.MERCHANT_SHOW and w.F.events._events.MERCHANT_CLOSED, "the vendor opening and closing")
    check(w.F.owned.markRow and w.F.owned.markTile and w.F.owned.visible and w.F.owned.syncButton, "the grid and the list get their four entry points")
    local regs = w.F.events._regs
    w.F.SetOwnedActive(true)
    eq(#w.hooks, 1, "on again: nothing more")
    eq(w.F.events._regs, regs, "on again: nothing registered again")

    w.Fire("MERCHANT_SHOW")
    eq(w.Events(), 6, "a vendor opens: the four collection events join")
    for _, e in ipairs(COLLECTION) do check(w.F.events._events[e], "listens to " .. e) end
    w.Fire("MERCHANT_CLOSED")
    eq(w.Events(), 2, "the vendor closes: the collection events are released")
    eq(w.H.debounced, 0, "opening and closing a vendor asks for no repaint")

    w.Fire("MERCHANT_SHOW")
    w.F.SetOwnedActive(false)
    eq(w.Events(), 0, "off: every event released")
    w.F.SetOwnedActive(true)
    eq(#w.hooks, 1, "on again later: the hook is not installed twice")
    eq(w.Events(), 2, "on again, the vendor window not shown: two events")

    -- turned on while a vendor is open: the collection events at once
    w = World({ shown = true })
    w.F.SetOwnedActive(true)
    eq(w.Events(), 6, "turned on at an open vendor: all six events")
end

-------------------------------------------------------------------------------
-- 3. Which items are owned: the tooltip, read once per item ID, only once the
--    item has loaded
-------------------------------------------------------------------------------
do
    local w = World()
    w.F.SetOwnedActive(true)
    eq(w.F.MerchantItemKnown(1), false, "an item with no owned line")
    eq(w.F.MerchantItemKnown(2), true, "Already known")
    eq(w.F.MerchantItemKnown(4), true, "Collected (1/3)")
    eq(w.tips, 3, "three tooltips read")
    w.F.MerchantItemKnown(1); w.F.MerchantItemKnown(2); w.F.MerchantItemKnown(4)
    eq(w.tips, 3, "asked again: no tooltip read")
    -- the filter re-maps the indexes with no event: the answers follow the items
    w.filter = 1                 -- item 12 is now index 5, item 14 index 3
    eq(w.F.MerchantItemKnown(5), true, "another filter: the same item, another index, still owned")
    eq(w.F.MerchantItemKnown(3), true, "another filter: the pet too")
    eq(w.F.MerchantItemKnown(6), false, "another filter: index 6 is item 11, not owned")
    eq(w.tips, 3, "the answers come from the cache by item ID")
    eq(w.F.MerchantItemKnown(99), false, "no item at an index: not owned")
    eq(select(2, w.F.MerchantItemKnown(99)), nil, "and not waiting to load")
    w.filter = 0

    -- an item still loading is not cached, and no tooltip is read for it
    w.loaded[13] = false
    w.known[13] = "Already known"
    local known, loading = w.F.MerchantItemKnown(3)
    eq(known, false, "an item still loading reads as not owned")
    eq(loading, true, "and says it is loading")
    eq(w.tips, 3, "no tooltip is read for it")
    w.loaded[13] = true
    known, loading = w.F.MerchantItemKnown(3)
    eq(known, true, "once loaded it is read")
    eq(loading, nil, "and no longer loading")
    eq(w.tips, 4, "one tooltip for it")

    -- the client's own wording for a collected pet, in any language
    for _, c in ipairs({
        { "Collected (%d/%d)", "Collected (2/3)", true },
        { "Collected (%d/%d)", "Collected (2/3) more", false },
        { "Collected (%d/%d)", "Not Collected (2/3)", false },
        { "Besitz: %1$d von %2$d.", "Besitz: 1 von 3.", true },
        { "Besitz: %1$d von %2$d.", "Besitz: 1 von 3!", false },
        { "100% [%d+%d]?", "100% [1+3]?", true },
        { "100% [%d+%d]?", "100% [1+3]", false },
    }) do
        local w2 = World({ petKnown = c[1] })
        w2.F.SetOwnedActive(true)
        w2.known[11] = c[2]
        eq(w2.F.MerchantItemKnown(1), c[3], "pet line '" .. c[2] .. "' against '" .. c[1] .. "'")
    end
end

-------------------------------------------------------------------------------
-- 4. The grid's list and the count: one walk, kept until something changes
-------------------------------------------------------------------------------
do
    local w = World({ db = { merchantMarkOwned = true, merchantHideKnown = true } })
    w.F.SetOwnedActive(true)
    local list = w.F.OwnedVisible()
    eq(table.concat(list, ","), "1,3,5,6", "hiding owned items: the indexes the grid shows")
    eq(w.F.Count(), 2, "two owned items")
    local reads, tips = w.idReads, w.tips
    eq(tips, 6, "one tooltip per item")
    w.F.OwnedVisible(); w.F.BuildOwnedList(); w.F.OwnedVisible()
    eq(w.idReads, reads, "asked again: the vendor is not walked again")
    eq(w.tips, tips, "asked again: no tooltip read")

    w.filter = 1
    list = w.F.OwnedVisible()
    eq(table.concat(list, ","), "1,2,4,6", "another filter: the list is built again, by the new indexes")
    eq(w.tips, tips, "from the cache")
    eq(w.F.Count(), 2, "still two owned")
    w.filter = 0

    -- the item count changing builds it again
    w.items[#w.items + 1] = 17
    w.loaded[17] = true
    eq(table.concat(w.F.OwnedVisible(), ","), "1,3,5,6,7", "one more item: built again")

    -- an item still loading: shown meanwhile, and the walk is done again until it loads
    w.items[#w.items + 1] = 18
    w.known[18] = "Already known"
    eq(table.concat(w.F.OwnedVisible(), ","), "1,3,5,6,7,8", "an item still loading shows for now")
    reads = w.idReads
    w.F.OwnedVisible()
    check(w.idReads > reads, "while one is loading the walk is done again")
    w.loaded[18] = true
    eq(table.concat(w.F.OwnedVisible(), ","), "1,3,5,6,7", "once loaded it is hidden")
    eq(w.F.Count(), 3, "and counted")
    reads = w.idReads
    w.F.OwnedVisible()
    eq(w.idReads, reads, "and the walk stops")

    -- not hiding, or off: every item shows
    w.db.merchantHideKnown = false
    eq(w.F.OwnedVisible(), nil, "Hide Owned off: the grid shows every item")
    w.db.merchantHideKnown = true
    w.F.SetOwnedActive(false)
    eq(w.F.OwnedVisible(), nil, "the feature off: the grid shows every item")
end

-------------------------------------------------------------------------------
-- 5. What can make an item owned: the cache goes, one repaint per burst
-------------------------------------------------------------------------------
do
    local w = World({ db = { merchantMarkOwned = true, merchantHideKnown = true }, shown = true })
    w.F.SetOwnedActive(true)
    w.F.OwnedVisible()
    local tips = w.tips
    w.known[11] = "Already known"          -- the player learns item 11
    w.Fire("NEW_RECIPE_LEARNED")
    w.Fire("NEW_RECIPE_LEARNED")
    eq(w.H.debounced, 2, "each event asks the debouncer")
    eq(table.concat(w.F.OwnedVisible(), ","), "3,5,6", "the list is read again after the event")
    check(w.tips > tips, "from fresh tooltips")
    -- the repaint the debouncer runs: whatever layout is up
    w.H.expand = true
    w.H.redraw()
    eq(w.H.exUpdates, 1, "the grid up: it is filled again")
    w.H.expand = false
    w.db.merchantShowAsList = true
    w.merchant.wSkinScrollFrame, w.merchant.wSkinScrollChild = "sf", "child"
    w.H.redraw()
    eq(w.H.listUpdates, 1, "the list up: it is filled again")
    eq(w.H.listArgs[1], "sf", "with the list's own frames")
    w.db.merchantShowAsList = false
    w.H.redraw()
    eq(w.H.exUpdates + w.H.listUpdates, 2, "the native page up: neither is touched")
    check(w.Wash(w.tiles[1]) and w.Wash(w.tiles[1])._shown, "the native page is flagged again (item 11 is now owned)")
    w.merchant._shown = false
    w.H.exUpdates = 0
    w.H.expand = true
    w.H.redraw()
    eq(w.H.exUpdates, 0, "no vendor open: no repaint")

    -- the vendor closing: the cache lasts one visit
    w.merchant._shown = true
    w.F.OwnedVisible()
    tips = w.tips
    local asked = w.H.debounced
    w.Fire("MERCHANT_CLOSED")
    eq(w.H.debounced, asked, "closing asks for no repaint")
    w.F.OwnedVisible()
    check(w.tips > tips, "the next visit reads the tooltips again")
end

-------------------------------------------------------------------------------
-- 6. The flag: a red wash on a frame of ours and a red icon
-------------------------------------------------------------------------------
do
    local w = World()
    w.F.SetOwnedActive(true)
    local made = w.created
    local tile = w.tiles[2]
    w.F.MarkOwnedTile(tile, 2)
    local wash = w.Wash(tile)
    check(wash ~= nil, "an owned tile gets a wash")
    eq(wash._kind, "Frame", "the wash is held by a frame")
    eq(wash._parent, tile, "of ours, a child of the tile")
    eq(w.created, made + 1, "one frame made for it")
    eq(wash._level, tile._level, "at the tile's own level (under its item button)")
    eq(wash._shown, true, "shown")
    local tex = wash._regions[1]
    check(tex and tex._tex and tex._tex[1] == 0.9 and tex._tex[4] == 0.22, "a red wash")
    eq(#tile._regions, 0, "nothing is added to the tile's own textures (the skin fades those)")
    eq(tile.ItemButton._tex[1], 0.9, "the icon goes red")
    eq(tile.ItemButton._tex[2], 0, "and only red")
    eq(tile.ItemButton._normal[1], 0.9, "its border too")

    -- the tile takes another item: the wash goes
    w.F.MarkOwnedTile(tile, 1)
    eq(wash._shown, false, "an item that is not owned: the wash hides")
    w.F.MarkOwnedTile(tile, 2)
    eq(w.created, made + 1, "owned again: the same wash, nothing new made")
    eq(wash._shown, true, "shown again")
    w.F.MarkOwnedTile(tile, nil)
    eq(wash._shown, false, "no item on the tile: the wash hides")

    -- an item Blizzard already dimmed (cannot be used) stays dark
    local dim = w.tiles[4]
    dim.ItemButton.icon._color = { 0.5, 0.5, 0.5 }
    w.F.MarkOwnedTile(dim, 4)
    eq(dim.ItemButton._tex[1], 0.5, "a dimmed icon goes dark red")

    -- a list row: the slot texture
    local row = w.Obj("Frame")
    row.SlotTexture = w.Obj("texture", row)
    w.F.MarkOwnedRow(row, 2, false)
    check(w.Wash(row) and w.Wash(row)._shown, "an owned list row gets a wash")
    eq(row.SlotTexture._color[1], 1, "its icon goes red")
    eq(row.SlotTexture._color[2], 0, "and only red")
    w.F.MarkOwnedRow(row, 2, true)
    eq(w.Wash(row)._shown, false, "the buyback tab flags nothing")

    -- off: the washes go and the tints we set go back to plain
    w.F.MarkOwnedRow(row, 2, false)
    w.F.MarkOwnedTile(tile, 2)
    w.F.SetOwnedActive(false)
    eq(wash._shown, false, "off: the tile's wash hides")
    eq(w.Wash(row)._shown, false, "off: the row's wash hides")
    eq(tile.ItemButton._tex[1] == 1 and tile.ItemButton._tex[2] == 1, true, "off: the icon is plain again")
    eq(row.SlotTexture._color[2], 1, "off: the row's icon is plain again")
    local tips = w.tips
    w.F.MarkOwnedTile(tile, 2)
    w.F.MarkOwnedRow(row, 2, false)
    eq(w.tips, tips, "off: the grid's and the list's calls read nothing")
    eq(wash._shown, false, "off: and flag nothing")
end

-------------------------------------------------------------------------------
-- 7. Blizzard's own page, after each of its updates
-------------------------------------------------------------------------------
do
    local w = World()
    w.F.SetOwnedActive(true)
    local hook = w.hooks[1].fn
    for i = 7, 10 do w.tiles[i]._shown = false end
    hook()
    check(w.Wash(w.tiles[2]) and w.Wash(w.tiles[2])._shown, "tile 2 (Already known) is flagged")
    check(w.Wash(w.tiles[4]) and w.Wash(w.tiles[4])._shown, "tile 4 (a collected pet) is flagged")
    eq(w.Wash(w.tiles[1]), nil, "tile 1 gets no wash")
    eq(w.Wash(w.tiles[8]), nil, "a hidden tile gets none")
    -- the next page: tile 2 now shows item 6
    w.tiles[2].ItemButton._id = 6
    hook()
    eq(w.Wash(w.tiles[2])._shown, false, "a page flip: the tile's wash follows its item")
    w.tiles[2].ItemButton._id = 2
    -- the buyback tab
    hook()
    w.merchant.selectedTab = 2
    hook()
    eq(w.Wash(w.tiles[2])._shown, false, "the buyback tab: no flag")
    w.merchant.selectedTab = 1
    -- the list or the grid is up: they flag their own tiles
    hook()
    local tips = w.tips
    w.db.merchantShowAsList = true
    w.tiles[2].ItemButton._id = 6
    hook()
    eq(w.Wash(w.tiles[2])._shown, true, "the list up: the native tiles are left alone")
    w.db.merchantShowAsList = false
    w.H.expand = true
    hook()
    eq(w.Wash(w.tiles[2])._shown, true, "the grid up: the native tiles are left alone")
    w.H.expand = false
    -- off: the hook stays, and returns at once
    w.F.SetOwnedActive(false)
    local reads = w.idReads
    w.tiles[2].ItemButton._id = 2
    local looked = 0
    w.env.MerchantFrame = setmetatable({}, { __index = function(_, k) looked = looked + 1; return w.merchant[k] end })
    hook()
    w.env.MerchantFrame = w.merchant
    eq(looked, 0, "off: the hook does not even look at the vendor window")
    eq(w.idReads, reads, "off: the hook reads nothing")
    eq(w.Wash(w.tiles[2])._shown, false, "off: and flags nothing")
    eq(w.tips, tips, "off: no tooltip read")
end

-- a tile Blizzard hid keeps the ID of the item it last showed: not flagged
do
    local w = World()
    w.F.SetOwnedActive(true)
    w.tiles[2]._shown = false
    w.hooks[1].fn()
    eq(w.Wash(w.tiles[2]), nil, "a hidden tile whose last item was owned gets no wash")
    check(w.Wash(w.tiles[4]) and w.Wash(w.tiles[4])._shown, "a shown one beside it does")
end

-------------------------------------------------------------------------------
-- 8. The header button under Expand Vendor UI
-------------------------------------------------------------------------------
do
    local w = World({ db = { merchantMarkOwned = true } })
    w.F.SetOwnedActive(true)
    local made = w.created
    w.F.SyncOwnedButton(w.merchant, true)
    local b = w.F.owned.button
    check(b ~= nil, "the grid up: the button is built")
    eq(w.created, made + 1, "one frame")
    eq(b._text, "Hide Owned (2)", "it counts the owned items")
    eq(b._enabled, true, "live while there is something to hide")
    eq(b._shown, true, "shown")
    eq(#b._points, 1, "anchored once")
    check(b._points[1][1] == "RIGHT" and b._points[1][2] == w.merchant.FilterDropdown, "left of Blizzard's filter")
    w.F.SyncOwnedButton(w.merchant, true)
    w.F.SyncOwnedButton(w.merchant, true)
    eq(w.created, made + 1, "later updates build nothing")
    eq(#b._points, 1, "and anchor nothing again")

    -- the click: hides the owned items from the first page
    b._onOnClick(b)
    eq(w.db.merchantHideKnown, true, "a click turns Hide Owned on")
    eq(w.H.ex.page, 1, "from the first page")
    eq(w.H.exUpdates, 1, "and fills the grid again")
    w.F.SyncOwnedButton(w.merchant, true)
    eq(b._text, "Show Owned (2)", "the button now offers to show them")
    b._onOnClick(b)
    eq(w.db.merchantHideKnown, false, "a second click shows them again")
    -- a stack split held open on a tile: the click waits
    w.H.splitFree = false
    w.H.ex.page = 2
    b._onOnClick(b)
    eq(w.db.merchantHideKnown, false, "a split still open: the click changes nothing")
    eq(w.H.ex.page, 2, "and leaves the page")
    eq(w.H.exUpdates, 2, "and fills nothing")
    w.H.splitFree = true

    b._onOnEnter(b)
    eq(w.tooltip, "Click to hide the items you already have, or to show them again.", "its tooltip")
    b._onOnLeave(b)
    eq(w.tooltip, nil, "hidden on leave")

    -- nothing owned: greyed, unless it is hiding (so the items can come back)
    w.known = {}
    w.Fire("NEW_TOY_ADDED")
    w.F.SyncOwnedButton(w.merchant, true)
    eq(b._text, "Hide Owned (0)", "nothing owned")
    eq(b._enabled, false, "greyed")
    w.db.merchantHideKnown = true
    w.F.SyncOwnedButton(w.merchant, true)
    eq(b._enabled, true, "live while hiding")
    -- the grid goes, or the feature is off: hidden
    w.F.SyncOwnedButton(w.merchant, false)
    eq(b._shown, false, "the grid down: hidden")
    w.F.SyncOwnedButton(w.merchant, true)
    eq(b._shown, true, "the grid back: shown")
    w.F.SetOwnedActive(false)
    w.F.SyncOwnedButton(w.merchant, true)
    eq(b._shown, false, "the feature off: hidden")

    -- a vendor window with no filter: the window's corner
    w = World({ db = { merchantMarkOwned = true } })
    w.merchant.FilterDropdown = false
    w.F.SetOwnedActive(true)
    w.F.SyncOwnedButton(w.merchant, true)
    eq(w.F.owned.button._points[1][1], "TOPRIGHT", "no filter: the window's top-right corner")
    -- off and never built: nothing is built to hide
    w = World()
    w.F.SetOwnedActive(true)
    w.F.SetOwnedActive(false)
    local n = w.created
    w.F.SyncOwnedButton(w.merchant, true)
    eq(w.created, n, "off: no button is built")
end

-------------------------------------------------------------------------------
-- 9. The options switch
-------------------------------------------------------------------------------
do
    local w = World({ shown = true })
    local Refresh = w.env.EllesmereUI._Merchant_RefreshOwned
    check(type(Refresh) == "function", "the options entry point is published")
    w.db.merchantMarkOwned = true
    for i = 7, 10 do w.tiles[i]._shown = false end
    Refresh()
    eq(#w.hooks, 1, "ticked: the hook goes in")
    eq(w.Events(), 6, "ticked at an open vendor: the events")
    check(w.Wash(w.tiles[2]) and w.Wash(w.tiles[2])._shown, "ticked: the open page is flagged at once")
    w.db.merchantMarkOwned = false
    Refresh()
    eq(w.Events(), 0, "unticked: the events go")
    eq(w.Wash(w.tiles[2])._shown, false, "unticked: the flags go")
    w.db.merchantMarkOwned = true
    w.H.expand = true
    Refresh()
    eq(w.H.exUpdates, 1, "ticked with the grid up: the grid is filled again")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_blizzskin_merchant_owned (%d checks)"):format(count))
