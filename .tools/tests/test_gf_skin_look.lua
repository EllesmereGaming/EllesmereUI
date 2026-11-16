-- Stub harness for two parts of the Group Finder that are cut out of their
-- files by their first and last lines and run over stubs (the files themselves
-- need the whole game around them):
--   EUI_GroupFinder_Search.lua  the skin state (XF.SkinOn: read once per session
--     through the window engine, never latched before login), the border colour
--     it picks, a square's rest and picked look in either look (a white edge,
--     or a green tint on Blizzard's button), Blizzard's tooltip box and check
--     box on our menus with the skin off (and no border of ours made for them),
--     the button every filter bar button and square is made from, and the tab
--     the Your Class filter is read for;
--   EUI_GroupFinder_Extras.lua  the has / missing class rows: Your Class keeps a
--     key and a pick of its own on the raids tab; Bloodlust and Battle Res read
--     one key each here (the raids tab's own copy of those comes from the
--     settings proxy: test_gf_char_filters.lua).
-- A moved first or last line fails here by name.
--   lua .tools/tests/test_gf_skin_look.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end

-------------------------------------------------------------------------------
--  The search file's cut
-------------------------------------------------------------------------------
local SEARCH = ReadSource("EllesmereUIGroupFinder/EUI_GroupFinder_Search.lua")
local body = Cut(SEARCH, "-- the skin's window engine, so our buttons follow its theme\n", "ns.BOTTOM_Y = BOTTOM_Y\n", "the skin state")
local button = Cut(SEARCH, "local function SkinnedButton(parent, w, h, keepKeys, decorate)\n", "\nlocal function DropButton(", "the button")
local CHUNK = "local CM, XF, ns = ...\n" .. body .. button .. "\nreturn ThemeBorder, SkinnedButton\n"

-- o.skins = false: Blizzard Skins+ is not loaded; o.style: what the window engine
-- answers for the Group Finder window; o.logged = false: before login
local function Fresh(o)
    o = o or {}
    local W = { styleReads = 0, borders = {}, made = {}, skinned = {}, colors = {}, style = o.style or "eui",
        logged = o.logged ~= false }
    local CM = { _ModuleNS = {}, PanelPP = {
        SetBorderColor = function(f, r, g, b, a) W.colors[#W.colors + 1] = { f, r, g, b, a } end,
        CreateBorder = function(f) W.borders[#W.borders + 1] = f end,
    }, MakeBorder = function(f)
        W.borders[#W.borders + 1] = f
        return { _frame = f, SetColor = function(self, ...) self.color = { ... } end }
    end }
    if o.skins ~= false then
        CM._ModuleNS.EllesmereUIBlizzardSkin = { WSkin = (not o.noWSkin) and { Theme = o.theme,
            Button = function(b, keep) W.skinned[#W.skinned + 1] = { b, keep } end } or nil }
        if not o.noStyleFn then
            CM.GetBlizzWindowStyle = function(key)
                W.styleReads = W.styleReads + 1
                W.key = key
                return W.style
            end
        end
    end
    IsLoggedIn = function() return W.logged end
    CreateFrame = function(kind, name, parent, template)
        local f = setmetatable({ _kind = kind, _parent = parent, _template = template, _calls = {} }, {
            __index = function(_, k)
                if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
                return function(self) self._calls[#self._calls + 1] = k end
            end,
        })
        W.made[#W.made + 1] = f
        return f
    end
    local XF, ns = { EMPTY = {} }, {}  -- XF.EMPTY: set by the file above the cut
    local ThemeBorder, SkinnedButton = assert(loadstring(CHUNK, "=search-cut"))(CM, XF, ns)
    return W, XF, ns, ThemeBorder, SkinnedButton
end
local function Last(W) return unpack(W.colors[#W.colors]) end
local function Called(f, name)
    for _, k in ipairs(f._calls) do if k == name then return true end end
    return false
end

-- 1. the skin state
do
    local W, XF, ns = Fresh({ skins = false })
    check(XF.SkinOn() == false and ns.SkinOn == XF.SkinOn, "Blizzard Skins+ off reads as skinned")
    W, XF = Fresh({ style = "eui" })
    check(XF.SkinOn() == true and W.key == "lfg", "the EllesmereUI skin reads as off, or another window was asked")
    W, XF = Fresh({ style = "modern" })
    check(XF.SkinOn() == true, "the Modern skin reads as off")
    W, XF = Fresh({ style = "off" })
    check(XF.SkinOn() == false, "a window skin that is off reads as on")
    W, XF = Fresh({ noStyleFn = true })
    check(XF.SkinOn() == false, "no window engine reader and the skin reads as on")
    W, XF = Fresh({ noWSkin = true })
    check(XF.SkinOn() == false, "no window engine to dress our buttons and the skin reads as on")
end

-- 2. read once per session: a card toggle changes nothing until the reload
do
    local W, XF = Fresh({ style = "eui" })
    check(XF.SkinOn() == true, "on at login")
    W.style = "off"
    for _ = 1, 5 do check(XF.SkinOn() == true, "the look flipped after the card was turned off") end
    check(W.styleReads == 1, "the window engine was asked again: " .. W.styleReads)
    W, XF = Fresh({ style = "off" })
    check(XF.SkinOn() == false, "off at login")
    W.style = "eui"
    check(XF.SkinOn() == false and W.styleReads == 1, "the look flipped after the card was turned on")
    -- before login nothing is kept
    W, XF = Fresh({ style = "off", logged = false })
    check(XF.SkinOn() == false and XF.skinOn == nil, "the state was kept before login")
    W.style = "eui"
    check(XF.SkinOn() == true and XF.skinOn == nil, "the state before login did not follow the setting")
    W.logged = true
    check(XF.SkinOn() == true and XF.skinOn == true, "the state was not kept at login")
    W.style = "off"
    check(XF.SkinOn() == true, "the look flipped after login")
end

-- 3. the border colour: the theme's, a fallback, or Blizzard's grey
do
    local W, XF, ns, ThemeBorder = Fresh({ skins = false })
    local r, g, b, a = ThemeBorder()
    check(r == 0.38 and g == 0.38 and b == 0.38 and a == 1 and ns.ThemeBorder == ThemeBorder, "the stock grey")
    W, XF, ns, ThemeBorder = Fresh({ theme = { brdR = 0.1, brdG = 0.2, brdB = 0.3, brdA = 0.4 } })
    r, g, b, a = ThemeBorder()
    check(r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4, "the theme's border colour")
    W, XF, ns, ThemeBorder = Fresh({})
    r, g, b, a = ThemeBorder()
    check(r == 0.2 and g == 0.2 and b == 0.2 and a == 1, "the fallback border colour")
    W, XF, ns, ThemeBorder = Fresh({ style = "off", theme = { brdR = 0.1, brdG = 0.2, brdB = 0.3, brdA = 0.4 } })
    r = ThemeBorder()
    check(r == 0.38, "a skin that is off still gave the theme's colour")
end

-- a texture that keeps its last vertex colour
local function Art()
    return { SetVertexColor = function(self, r, g, b) self.tint = { r, g, b } end }
end

-- 4. a square's rest and picked look: a white edge with the skin on; with it
--    off no edge of ours, the button's own art and its icon tinted green
do
    local theme = { brdR = 0.1, brdG = 0.2, brdB = 0.3, brdA = 0.4 }
    local W, XF = Fresh({ theme = theme })
    local sq, edge = CreateFrame("Button"), {}
    XF.RestBorder(edge)
    local f, r, g, b, a = Last(W)
    check(f == edge and r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4, "skinned: the rest edge is not the theme's")
    XF.PickBorder(sq, edge, true)
    f, r, g, b, a = Last(W)
    check(f == edge and r == 1 and g == 1 and b == 1 and a == 1, "skinned: a picked square has no white edge")
    XF.PickBorder(sq, edge, false)
    f, r, g, b, a = Last(W)
    check(f == edge and r == 0.1 and a == 0.4, "skinned: an unpicked square did not go back to the theme's edge")
    check(not Called(sq, "LockHighlight") and not Called(sq, "UnlockHighlight"), "skinned: the highlight was held")

    W, XF = Fresh({ style = "off", theme = theme })
    sq, edge = CreateFrame("Button"), {}
    XF.RestBorder(edge)
    f, r, g, b, a = Last(W)
    check(f == edge and r == 0 and g == 0 and b == 0 and a == 0, "stock: the rest edge is not clear")
    local art, ic = Art(), Art()
    rawset(sq, "stockArt", { art }); rawset(sq, "icon", ic)
    XF.PickBorder(sq, edge, true)
    f, r, g, b, a = Last(W)
    check(f == edge and a == 0, "stock: a picked square got an edge of ours")
    check(not Called(sq, "LockHighlight"), "stock: a picked square holds the highlight")
    XF.PickBorder({}, edge, true)  -- a square with no art listed and no icon: nothing to tint
    check(art.tint[1] == 0.45 and art.tint[2] == 1 and art.tint[3] == 0.45, "stock: a picked square's box is not tinted green")
    check(ic.tint[1] == 0.7 and ic.tint[2] == 1 and ic.tint[3] == 0.7, "stock: a picked square's icon is not tinted green")
    XF.PickBorder(sq, edge, false)
    check(art.tint[1] == 1 and art.tint[2] == 1 and art.tint[3] == 1 and ic.tint[1] == 1, "stock: an unpicked square stays tinted")
    -- a boss square: green while picked alive, red while picked dead
    XF.TintSquare(sq, "alive")
    check(art.tint[1] == 0.45 and art.tint[2] == 1, "stock: a boss picked alive is not green")
    XF.TintSquare(sq, "dead")
    check(art.tint[1] == 1 and art.tint[2] == 0.4 and ic.tint[2] == 0.6, "stock: a boss picked dead is not red")
    XF.TintSquare(sq, nil)
    check(art.tint[2] == 1 and ic.tint[2] == 1, "stock: an unpicked boss stays tinted")
end

-- 4b. a button's "filtering" look: our green edge with the skin on, the tint
--     with it off (where no edge is made at all)
do
    local W, XF = Fresh({ style = "eui" })
    local shown
    local btn = { activeEdge = { SetShown = function(_, v) shown = v end, Hide = function() shown = "hidden" end } }
    XF.ActiveLook(btn, true)
    check(shown == true, "skinned: the green edge did not show")
    XF.ActiveLook(btn, false)
    check(shown == false, "skinned: the green edge stayed")
    XF.ActiveLook({}, true)  -- no edge yet: nothing to do

    W, XF = Fresh({ style = "off" })
    local art = Art()
    btn = { stockArt = { art } }
    XF.ActiveLook(btn, true)
    check(art.tint[1] == 0.45 and art.tint[2] == 1, "stock: a filtering button is not tinted green")
    XF.ActiveLook(btn, false)
    check(art.tint[1] == 1, "stock: a button that stopped filtering stays tinted")
end

-- 4c. Blizzard's tooltip box, check box and plain button on our own frames
--     with the skin off; with it on our own look stays and the ring is ours
do
    local mixed = 0
    Mixin = function(t, m) mixed = mixed + 1; for k, v in pairs(m) do t[k] = v end return t end
    BackdropTemplateMixin = {
        SetBackdrop = function(self, b) self.backdrop = b end,
        SetBackdropColor = function(self, ...) self.fillColor = { ... } end,
        SetBackdropBorderColor = function(self, ...) self.edgeColor = { ... } end,
        OnBackdropSizeChanged = function() end,
    }
    TOOLTIP_DEFAULT_BACKGROUND_COLOR, TOOLTIP_DEFAULT_COLOR = nil, nil
    local function Box() return { HookScript = function(self, ev, fn) self.hook = { ev, fn } end } end
    local function Tex() return { Hide = function(self) self.hidden = true end } end

    local W, XF, ns = Fresh({ style = "eui" })
    local box, bg = Box(), Tex()
    check(XF.StockBox(box, bg) == false and box.backdrop == nil and not bg.hidden and mixed == 0, "skinned: a menu took Blizzard's box")

    W, XF, ns = Fresh({ style = "off" })
    check(ns.StockBox == XF.StockBox and ns.NewButton == XF.NewButton and ns.ActiveLook == XF.ActiveLook, "the helpers are not shared with the other files")
    check(XF.StockBox(box, bg) == true and bg.hidden == true, "stock: our flat fill stayed")
    check(box.backdrop == XF.STOCK_BOTH and box.hook[1] == "OnSizeChanged" and box.hook[2] == BackdropTemplateMixin.OnBackdropSizeChanged,
        "stock: not Blizzard's tooltip box, or it does not follow its frame's size")
    check(box.fillColor[4] == 0.95 and box.edgeColor[1] == 1, "stock: the box has no fill or edge colour")
    XF.StockBox(box, nil, "fill")
    check(mixed == 1, "the backdrop mixin was added twice to one frame")
    check(box.backdrop == XF.STOCK_FILL, "stock: a fill-only box")
    box.fillColor, box.edgeColor = nil, nil
    XF.StockBox(box, nil, "edge")
    check(box.backdrop == XF.STOCK_EDGE and box.fillColor == nil and box.edgeColor ~= nil, "stock: an edge-only box was filled")
    XF.StockBox(box, nil, "fillL")
    check(box.backdrop == XF.STOCK_FILL_L and XF.STOCK_FILL_L.insets.right == 0, "stock: the left column keeps an inset where the columns meet")
    XF.StockBox(box, nil, "fillR")
    check(box.backdrop == XF.STOCK_FILL_R and XF.STOCK_FILL_R.insets.left == 0, "stock: the right column keeps an inset where the columns meet")

    -- the check box: Blizzard's art and no ring of ours with the skin off
    local function Check() return { tex = nil, SetTexture = function(self, t) self.tex = t end,
        ClearAllPoints = function() end, SetPoint = function() end } end
    local cb, cbg, fill = {}, Check(), Check()
    check(XF.CheckRing(cb) == nil and #W.borders == 0, "stock: a ring of ours was made for a check box")
    check(XF.StockCheck(cb, cbg, fill) == true, "stock: the check box kept our look")
    check(cbg.tex == "Interface\\Buttons\\UI-CheckBox-Up" and fill.tex == "Interface\\Buttons\\UI-CheckBox-Check", "stock: not Blizzard's check box art")
    local shown
    fill.SetShown = function(_, v) shown = v end
    XF.PaintCheck({ stock = true }, fill, nil, true)  -- no ring: none may be touched
    check(shown == true, "stock: a ticked box shows no tick")
    XF.PaintCheck({ stock = true }, fill, nil, false)
    check(shown == false, "stock: an unticked box keeps its tick")
    local b = XF.NewButton(cb)
    check(b._template == "UIMenuButtonStretchTemplate" and b._parent == cb, "stock: a plain button is not Blizzard's menu button")

    W, XF = Fresh({ style = "modern" })
    cbg, fill = Check(), Check()
    local ring = XF.CheckRing(cb)
    check(ring ~= nil and #W.borders == 1 and W.borders[1] == cb, "skinned: a check box has no ring")
    check(XF.StockCheck(cb, cbg, fill) == false and cbg.tex == nil, "skinned: a check box took Blizzard's art")
    Accent = function() return 0.1, 0.2, 0.3 end
    fill.SetShown = function(_, v) shown = v end
    fill.SetColorTexture = function(self, ...) self.color = { ... } end
    XF.PaintCheck({}, fill, ring, true)
    check(shown == true and fill.color[1] == 0.1 and ring.color[1] == 0.1 and ring.color[4] == 0.8, "skinned: a ticked box is not in the accent")
    XF.PaintCheck({}, fill, ring, false)
    check(shown == false and ring.color[1] == 0.25, "skinned: an unticked box keeps the accent ring")
    Accent = nil
    check(XF.NewButton(cb)._template == nil, "skinned: a plain button took Blizzard's template")
    -- the boxes that are built pass no ring to the stock art, and ask for theirs through the one maker
    local _, rings = SEARCH:gsub("%.ring = XF%.CheckRing%(", "")
    check(rings == 3 and not SEARCH:find(".ring = CM.MakeBorder(", 1, true), "a check box makes its ring outside XF.CheckRing")
    check(SEARCH:find("if XF.SkinOn() and not diffBtn.activeEdge then", 1, true) ~= nil, "the Filters button makes its green edge with the skin off")
end

-- 5. the button every filter bar button and square is made from
do
    local W, XF, ns, _, SkinnedButton = Fresh({ style = "off" })
    local parent, keep, decorated = {}, { "Icon" }, nil
    local b = SkinnedButton(parent, 30, 30, keep, function(btn) decorated = btn end)
    check(b._template == "UIMenuButtonStretchTemplate" and b._parent == parent and decorated == b, "stock: not Blizzard's menu button")
    check(#W.borders == 0, "stock: a border of ours was made on the button")
    check(#W.skinned == 0, "stock: the window engine dressed the button")

    W, XF, ns, _, SkinnedButton = Fresh({ skins = false })
    b = SkinnedButton(parent, 30, 30, keep)
    check(b._template == "UIMenuButtonStretchTemplate" and #W.borders == 0, "Blizzard Skins+ off: not Blizzard's menu button")

    W, XF, ns, _, SkinnedButton = Fresh({ style = "modern" })
    decorated = nil
    b = SkinnedButton(parent, 30, 30, keep, function(btn) decorated = btn end)
    check(b._template == nil and decorated == b, "skinned: the button took Blizzard's template")
    check(#W.skinned == 1 and W.skinned[1][1] == b and W.skinned[1][2] == keep, "skinned: the window engine did not dress the button")
    check(#W.borders == 0, "skinned: a second border was made")
end

-- 6. Your Class is read for the tab in view: the filter counts as active, and
--    the class filter is handed the tab; Reset clears both ticks
do
    local active = Cut(SEARCH, "function XF.ExtraFilterActive()\n", "-- info: the result's readable info", "the active check")
    local keep = Cut(SEARCH, "function XF.ExtraKeep(id, info, need)\n", "-- results are secret in restricted content", "the keep check")
    local chunk = "local SP, DUNGEONS, RAIDS, Cfg, ns, XF, IsSecret = ...\n" .. active .. keep
    local SP, cfg, ns, XF, seen = { categoryID = 2 }, {}, {}, { COUNT_ROLES = {} }, {}
    C_LFGList = { GetSearchResultMemberCounts = function() return nil end }
    ns.ExtraClassKeep = function(id, info, c, raids)
        seen[#seen + 1] = raids
        return true
    end
    assert(loadstring(chunk, "=tab-cut"))(SP, 2, 3, function() return cfg end, ns, XF, function() return false end)
    check(XF.ExtraFilterActive() == false, "nothing ticked counts as a filter")
    cfg.extraMyClass = true
    check(XF.ExtraFilterActive() == true, "dungeons: the Your Class tick does not count as a filter")
    SP.categoryID = 3
    check(XF.ExtraFilterActive() == false, "raids: the dungeons tick counts as a filter")
    cfg.extraMyClass, cfg.raidMyClass = nil, true
    check(XF.ExtraFilterActive() == true, "raids: the Your Class tick does not count as a filter")
    SP.categoryID = 2
    check(XF.ExtraFilterActive() == false, "dungeons: the raids tick counts as a filter")
    SP.categoryID = 6
    cfg.extraMyClass = true
    check(XF.ExtraFilterActive() == false, "another category has an own filter")
    -- the class filter is told which tab it runs for
    SP.categoryID = 2
    check(XF.ExtraKeep(1, {}) == true and seen[#seen] == false, "dungeons: the class filter was run for the raids tab")
    SP.categoryID = 3
    check(XF.ExtraKeep(1, {}) == true and seen[#seen] == true, "raids: the class filter was run for the dungeons tab")
    check(SEARCH:find("c.extraMyClass, c.raidMyClass = nil, nil", 1, true) ~= nil, "Reset does not clear both Your Class ticks")
    check(SEARCH:find("FLAG_KEYS = XF.FLAG_KEYS, raids = raids,", 1, true) ~= nil, "the class rows are not told their tab")
end

-------------------------------------------------------------------------------
--  The extras file's cut: the has / missing class rows
-------------------------------------------------------------------------------
do
    local EXTRAS = ReadSource("EllesmereUIGroupFinder/EUI_GroupFinder_Extras.lua")
    local rows = Cut(EXTRAS, "local LUST = {", "GFNS.ExtraClassRows = function", "the class rows")
    local keepFn = Cut(EXTRAS, "-- false = drop the group. secret members don't count\n",
        "-------------------------------------------------------------------------------\n--  region tags", "the class filter")
    local chunk = "local GFNS, Secret = ...\n" .. rows .. keepFn .. "\nreturn Keys, Missing, CLASS_ROWS\n"

    EllesmereUI = { L = function(s) return s end, Lf = function(s) return s end }
    local members, SECRET = {}, {}
    C_LFGList = { GetSearchResultPlayerInfo = function(id, i) return members[id] and members[id][i] end }
    function UnitClass() return "Mage", "MAGE" end
    canaccesstable = nil
    local GFNS = {}
    local Keys, Missing, ROWS = assert(loadstring(chunk, "=extras-cut"))(GFNS, function(v) return v == SECRET end)
    local Keep = GFNS.ExtraClassKeep
    check(type(Keep) == "function" and #ROWS == 3, "the class rows did not load")

    local function Group(id, ...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = { classFilename = (select(i, ...)) } end
        members[id] = t
        return { numMembers = #t }
    end
    local withMage = Group(1, "WARRIOR", "MAGE", "PRIEST")
    local noMage = Group(2, "WARRIOR", "DRUID", "PRIEST")

    -- the row's keys per tab
    local mine = ROWS[3]
    local k, p = Keys(mine, false)
    check(k == "extraMyClass" and p == "extraMyClassMissing", "the dungeons tab's keys")
    k, p = Keys(mine, true)
    check(k == "raidMyClass" and p == "raidMyClassMissing", "the raids tab's keys")
    k, p = Keys(ROWS[1], true)
    check(k == "hasLust" and p == "extraLustMissing", "Bloodlust took a raid key")
    k, p = Keys(ROWS[2], true)
    check(k == "hasBrez" and p == "extraBrezMissing", "Battle Res took a raid key")
    check(Missing({}, mine, true) == true and Missing({ raidMyClassMissing = false }, mine, true) == false
        and Missing({ extraMyClassMissing = false }, mine, true) == true, "the raids pick reads the dungeons pick")

    -- nothing ticked: every group stays, on both tabs
    check(Keep(1, withMage, {}, false) and Keep(1, withMage, {}, true), "nothing ticked dropped a group")
    -- the dungeons tick (No <class> by default) filters dungeons only
    local cfg = { extraMyClass = true }
    check(Keep(1, withMage, cfg, false) == false and Keep(2, noMage, cfg, false) == true, "dungeons: Your Class does not filter")
    check(Keep(1, withMage, cfg, true) == true and Keep(2, noMage, cfg, true) == true, "raids: the dungeons tick filtered")
    -- the raids tick is its own, with its own pick
    cfg = { raidMyClass = true }
    check(Keep(1, withMage, cfg, true) == false and Keep(2, noMage, cfg, true) == true, "raids: Your Class does not filter")
    check(Keep(1, withMage, cfg, false) == true and Keep(2, noMage, cfg, false) == true, "dungeons: the raids tick filtered")
    cfg = { raidMyClass = true, raidMyClassMissing = false }
    check(Keep(1, withMage, cfg, true) == true and Keep(2, noMage, cfg, true) == false, "raids: the Has <class> pick")
    cfg = { raidMyClass = true, extraMyClassMissing = false }
    check(Keep(1, withMage, cfg, true) == false, "raids read the dungeons pick")
    cfg = { extraMyClass = true, raidMyClassMissing = false }
    check(Keep(1, withMage, cfg, false) == false, "dungeons read the raids pick")
    cfg = { extraMyClass = true, raidMyClass = true, raidMyClassMissing = false }
    check(Keep(1, withMage, cfg, false) == false and Keep(1, withMage, cfg, true) == true, "both ticked")
    -- Bloodlust and Battle Res read one key each, whatever the tab (each tab's
    -- own value comes from the settings proxy, which this cut does not hold)
    cfg = { hasLust = true }
    check(Keep(1, withMage, cfg, false) == true and Keep(1, withMage, cfg, true) == true, "Bloodlust: a mage's group was dropped")
    check(Keep(2, noMage, cfg, false) == false and Keep(2, noMage, cfg, true) == false, "Bloodlust: a group with none stayed")
    cfg = { hasBrez = true }
    check(Keep(2, noMage, cfg, true) == true and Keep(1, withMage, cfg, true) == false, "Battle Res")
    -- a hidden member count or class keeps the group
    cfg = { raidMyClass = true }
    check(Keep(1, { numMembers = SECRET }, cfg, true) == true, "a hidden member count dropped the group")
    members[3] = { { classFilename = SECRET }, { classFilename = "PRIEST" } }
    check(Keep(3, { numMembers = 2 }, cfg, true) == true, "a hidden class counted as mine")
end

print(("group finder skin look harness: %d checks, ok"):format(n))
