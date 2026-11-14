-- Stub harness: Forever Essentials, Map Markers by kind (EllesmereUIForeverEssentials_MapTravel.lua).
-- One toggle per kind of marker (boats, zeppelins, skycutters, the tram, portals, dungeons, raids,
-- zone exits, flight points), in the options cog and, while Map Markers is on, as a section of the
-- world map's own filter menu:
--   * off, nothing is registered or built; on, the menu section is registered once and the pins
--     are a data provider's, as before;
--   * each kind shows or hides on its own: a dock with a boat and a zeppelin keeps the one still
--     shown, dungeons and raids part, on zone, continent and world maps;
--   * a kind never set follows the older set it belonged to (Transports, Instance Entrances), and
--     a kind once set wins over it, with nothing migrated;
--   * the menu section: a divider, a title and one checkbox per kind in the list's order, added
--     once per menu, each row's kind its data, every row sharing one getter and one setter; a
--     click flips that kind, redraws the pins and leaves the menu open;
--   * with every kind off the provider is dropped and the section stays; turning Map Markers
--     off takes the section away.
-- The real file is loaded whole over the module's own settings kit (cut from the main file),
-- with stubbed frames, map data and a model of the game's menu registry.
--   lua .tools/tests/test_fe_map_markers_kinds.lua        (from the repository root)
local ROOT = arg and arg[1] or "."
local FE = ROOT .. "/EllesmereUIForeverEssentials/EllesmereUIForeverEssentials"

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource(FE .. "_MapTravel.lua")
local DATA_SRC = ReadSource(FE .. "_MapTravelData.lua")
local KIT = ReadSource(FE .. ".lua"):match("\n(function ns%.Feature%(dbKey, defaults, defaultPos%)\n.-\nend)\n")
assert(KIT, "the settings kit was not found in the module's main file")
local OPT_SRC = ReadSource(ROOT .. "/EllesmereUIOptions/EUI_ForeverEssentials_General_Options.lua")
-- The widget methods the file calls: a mock answers those with a no-op.
local METHODS = {}
for name in SRC:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end

local TAG = "MENU_WORLD_MAP_TRACKING"
local KINDS = { "boats", "zeppelins", "skycutters", "trams", "portals", "dungeons", "raids", "exits", "flights" }
local LABELS = { "Boats", "Zeppelins", "Skycutters", "Tram", "Portals", "Dungeons", "Raids", "Zone Exits", "Flight Points" }
local BOAT, ZEPPELIN, TRAM, SKYCUTTER, PORTAL = "flightmasterferry", "vehicle-air-horde", "vehicle-alliancecart", "vehicle-air-alliance", "mageportalalliance"

-- Maps: the world (1), a continent (10), two zones (101, 102).
local WORLD, CONTINENT, ZONE_A, ZONE_B = 1, 10, 101, 102
-- Places: zone A has a dock with a boat and a zeppelin, a tram station, a dungeon, a raid, a road
-- out and a flight master; zone B a skycutter, a portal and a dungeon.
local function Places()
    return {
        transports = {
            [ZONE_A] = { { 20, 20, "boat", ZONE_B, 1 }, { 22, 21, "zeppelin", ZONE_B, 2 }, { 60, 60, "tram", ZONE_B, 3 } },
            [ZONE_B] = { { 40, 40, "skycutter", ZONE_A, 4 }, { 80, 80, "portal", ZONE_A, 5 } },
        },
        exits = { [ZONE_A] = { { 50, 5, ZONE_B } } },
        instances = {
            [ZONE_A] = { { 30, 70, 9001, false }, { 35, 75, 9002, true, "Main Entrance" } },
            [ZONE_B] = { { 10, 10, 9003, false } },
        },
    }
end

-- One session of the client. saved: the settings as an earlier session left them (or nil).
-- opts.realData: the module's own places instead of the test's.
local function Session(saved, opts)
    opts = opts or {}
    local S = { frames = {}, mapID = ZONE_A, mapShown = false, placed = 0, added = 0, removed = 0, modifyCalls = 0, live = 0, translated = {} }
    local function MakeObj(kind, parent)
        local o = { _kind = kind, _parent = parent, _shown = true, _scripts = {}, _events = {} }
        setmetatable(o, { __index = function(_, k)
            if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
            if k == "Show" then return function(self) self._shown = true end end
            if k == "Hide" then return function(self) self._shown = false end end
            if k == "IsShown" then return function(self) return self._shown end end
            if k == "GetParent" then return function(self) return self._parent end end
            if k == "SetScript" then return function(self, s, fn) self._scripts[s] = fn end end
            if k == "RegisterEvent" then return function(self, ev) self._events[ev] = true end end
            if k == "UnregisterEvent" then return function(self, ev) self._events[ev] = nil end end
            if k == "UnregisterAllEvents" then return function(self) self._events = {} end end
            if k == "CreateTexture" then
                return function()
                    local tex = MakeObj("Texture")
                    tex.SetAtlas = function() S.placed = S.placed + 1 end
                    tex.SetTexture = tex.SetAtlas
                    return tex
                end
            end
            if k == "CreateFontString" then
                return function()
                    local fs = MakeObj("FontString")
                    fs.SetText = function(self, text) self._text = text end
                    return fs
                end
            end
            if METHODS[k] then return function() end end
            return nil
        end })
        S.frames[#S.frames + 1] = o
        return o
    end
    local canvas = MakeObj("Frame")
    canvas.GetSize = function() return 1000, 600 end
    canvas.GetScale = function() return 1 end

    EUI_CLIENT_BLOCKED = nil
    EllesmereUIDB = { mapTravel = saved }
    EllesmereUI = {
        IS_FOREVER = true,
        L = function(s)
            S.translated[s] = true
            return s
        end,
        Lf = function(s, ...) return s:format(...) end,
        COLOR_CODES = { DIM = "", BRAND = "", WHITE = "" },
        ShowWidgetTooltip = function() end,
        HideWidgetTooltip = function() end,
        Print = function() end,
        CombatQueue = { Defer = function(_, fn) fn() end },
    }
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    InCombatLockdown = function() return false end
    CreateFrame = function(kind, _, parent) return MakeObj(kind, parent) end
    CreateFromMixins = function(mixin)
        local o = {}
        for k, v in pairs(mixin) do o[k] = v end
        return o
    end
    MapCanvasDataProviderMixin = {
        OnAdded = function(self, map) self.owningMap = map end,
        GetMap = function(self) return self.owningMap end,
    }
    MAP_PIN_HYPERLINK, UNDISCOVERED_NEUTRAL_FLIGHTPOINT, UNDISCOVERED_FACTION_FLIGHTPOINT = "Map Pin", "Undiscovered", "Undiscovered %s"
    FACTION_HORDE, FACTION_ALLIANCE = "Horde", "Alliance"
    UnitFactionGroup = function() return "Alliance" end
    GetRealZoneText = function(id) return "Instance " .. id end
    Enum = {
        UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 },
        FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
    }
    local MAPS = {
        [WORLD] = { mapType = 1, parentMapID = 0, name = "World" },
        [CONTINENT] = { mapType = 2, parentMapID = WORLD, name = "Continent" },
        [ZONE_A] = { mapType = 3, parentMapID = CONTINENT, name = "Zone A" },
        [ZONE_B] = { mapType = 3, parentMapID = CONTINENT, name = "Zone B" },
    }
    local RECTS = {
        [CONTINENT] = { [ZONE_A] = { 0.1, 0.4, 0.1, 0.4 }, [ZONE_B] = { 0.5, 0.9, 0.5, 0.9 } },
        [WORLD] = { [ZONE_A] = { 0.2, 0.3, 0.2, 0.3 }, [ZONE_B] = { 0.6, 0.7, 0.6, 0.7 } },
    }
    C_Map = {
        GetMapInfo = function(id) return MAPS[id] or (opts.realData and { mapType = 3, parentMapID = CONTINENT, name = "Zone " .. id }) or nil end,
        GetMapRectOnMap = function(zone, map)
            local r = RECTS[map] and RECTS[map][zone]
            if r then return r[1], r[2], r[3], r[4] end
            if opts.realData and RECTS[map] then return 0.2, 0.8, 0.2, 0.8 end
        end,
        GetAreaInfo = function(id) return "Area " .. id end,
        CanSetUserWaypointOnMap = function() return true end,
    }
    C_TaxiMap = {
        ShouldMapShowTaxiNodes = function() return false end,
        GetTaxiNodesForMap = function(id)
            if id ~= ZONE_A then return {} end
            return { { position = { x = 0.5, y = 0.5 }, faction = 0, name = "Crossroads", isUndiscovered = false, atlasName = "" } }
        end,
    }
    C_AddOns = { IsAddOnLoaded = function() return true end }
    WorldMapFrame = {
        ScrollContainer = { Child = canvas },
        GetMapID = function() return S.mapID end,
        IsShown = function() return S.mapShown end,
        GetPinFrameLevelsManager = function() return { GetValidFrameLevel = function() return 2000 end } end,
        AddDataProvider = function(self, p)
            S.added = S.added + 1
            S.provider = p
            p:OnAdded(self)
        end,
        RemoveDataProvider = function(_, p)
            S.removed = S.removed + 1
            S.provider = nil
            p:RemoveAllData()
        end,
        GetGlobalAlpha = function() return 1 end,
    }

    -- The game's menu registry: a callback registered for a tag is called for every menu built
    -- under it from then on, and at once for the last one built; its handle takes it out again.
    local registered, lastBuilt = {}, nil
    MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }
    Menu = {
        ModifyMenu = function(tag, callback)
            assert(tag == TAG, "a menu other than the map's filter menu was modified: " .. tostring(tag))
            S.modifyCalls = S.modifyCalls + 1
            if lastBuilt then callback(lastBuilt.owner, lastBuilt) end
            local handle = {}
            registered[handle] = callback
            S.live = S.live + 1
            function handle:Unregister()
                if registered[self] then
                    registered[self] = nil
                    S.live = S.live - 1
                end
            end
            return handle
        end,
    }
    -- The map builds its filter menu (every time it shows, and when the menu opens).
    function S.BuildMenu()
        local d = { owner = {}, items = {} }
        function d:CreateDivider() self.items[#self.items + 1] = { kind = "divider" } end
        function d:CreateTitle(text) self.items[#self.items + 1] = { kind = "title", text = text } end
        function d:CreateCheckbox(text, isSelected, setSelected, data)
            local row = { kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected, data = data }
            self.items[#self.items + 1] = row
            return row
        end
        lastBuilt = d
        for _, callback in pairs(registered) do callback(d.owner, d) end
        return d
    end
    -- The checkbox rows of a built menu, and a row by its label.
    function S.Rows(d)
        local rows = {}
        for _, it in ipairs(d.items) do
            if it.kind == "checkbox" then rows[#rows + 1] = it end
        end
        return rows
    end
    function S.Row(d, label)
        for _, it in ipairs(d.items) do
            if it.kind == "checkbox" and it.text == label then return it end
        end
    end
    -- As the game's menu does: both functions get the row's data.
    function S.Ticked(row) return row.isSelected(row.data) end
    function S.Click(row) return row.setSelected(row.data, { buttonName = "LeftButton" }, {}) end

    local module = {}
    assert(loadstring("local ns = ...\n" .. KIT, "=Feature"))(module)
    assert(loadstring(DATA_SRC, "=MapTravelData.lua"))("EllesmereUIForeverEssentials", module)
    if not opts.realData then module.MapTravelData = Places end
    assert(loadstring(SRC, "=MapTravel.lua"))("EllesmereUIForeverEssentials", module)
    S.MT = assert(EllesmereUI._MapTravel, "the options entry points were not published")

    function S.Login()
        for _, f in ipairs(S.frames) do
            if f._events.PLAYER_LOGIN then f._scripts.OnEvent(f, "PLAYER_LOGIN") end
        end
    end
    -- The world map shows a map: its providers are refreshed.
    function S.ShowMap(mapID)
        S.mapID, S.mapShown = mapID, true
        if S.provider then S.provider:RefreshAllData() end
    end
    function S.CloseMap() S.mapShown = false end
    -- The pins on screen: the shown frames of the pin layer.
    function S.Pins()
        local layer
        for _, f in ipairs(S.frames) do
            if f._parent == canvas then layer = f end
        end
        local pins = {}
        if not layer then return pins end
        for _, f in ipairs(S.frames) do
            if f._parent == layer and f._shown then pins[#pins + 1] = f end
        end
        return pins
    end
    -- How many pins wear this art, and the first of them.
    function S.Art(atlas)
        local n, first = 0, nil
        for _, p in ipairs(S.Pins()) do
            if p.atlas == atlas then
                n = n + 1
                first = first or p
            end
        end
        return n, first
    end
    -- The options cog's write of one kind.
    function S.Set(key, v)
        S.MT.Cfg()[key] = v
        S.MT.Apply()
    end
    return S
end

local function Shows(S)
    local parts = {}
    for _, p in ipairs(S.Pins()) do parts[#parts + 1] = p.atlas end
    table.sort(parts)
    return #parts .. " [" .. table.concat(parts, ", ") .. "]"
end

-------------------------------------------------------------------------------
-- 1. off: nothing registered, nothing built
-------------------------------------------------------------------------------
do
    local S = Session(nil)
    S.Login()
    check(S.modifyCalls == 0 and S.live == 0, "Map Markers off: the map's filter menu is modified")
    check(S.added == 0 and S.provider == nil, "Map Markers off: a data provider is added to the map")
    local d = S.BuildMenu()
    check(#d.items == 0, "Map Markers off: the filter menu got " .. #d.items .. " entries")
    S.ShowMap(ZONE_A)
    check(#S.Pins() == 0, "Map Markers off: pins are drawn")
    check(EllesmereUIDB.mapTravel == nil, "Map Markers off: settings were written at login")
    -- what the options page reads is published whether it is on or off
    for name in OPT_SRC:gmatch("MT%.([%a_]+)") do
        check(S.MT[name] ~= nil, "the options page reads MT." .. name .. ", which the module does not publish")
    end
    check(type(S.MT.Kinds) == "table" and #S.MT.Kinds == #KINDS, "the module does not publish its " .. #KINDS .. " kinds")
    for i, key in ipairs(KINDS) do
        check(S.MT.Kinds and S.MT.Kinds[i] == key, "kind " .. i .. " is not " .. key)
        check(S.MT.Labels and S.MT.Labels[key] == LABELS[i], "the label of " .. key .. " is not " .. LABELS[i])
    end
end

-------------------------------------------------------------------------------
-- 2. on: the pins of every kind, by map
-------------------------------------------------------------------------------
do
    local S = Session({ enabled = true })
    S.Login()
    check(S.modifyCalls == 1 and S.live == 1, "Map Markers on: the filter menu is not registered once (" .. S.modifyCalls .. " calls, " .. S.live .. " live)")
    check(S.added == 1 and S.provider ~= nil, "Map Markers on: the data provider is not added once")
    S.ShowMap(ZONE_A)
    -- the dock (a boat and a zeppelin on one pin), the tram, a dungeon, a raid, an exit, a flight master
    check(#S.Pins() == 6, "zone A, every kind: " .. Shows(S))
    local n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == 2, "the dock is not one pin counting its boat and its zeppelin")
    check(dock and dock.tip:find("Boat to", 1, true) and dock.tip:find("Zeppelin to", 1, true), "the dock's tooltip does not list both of its transports")
    check(S.Art(TRAM) == 1 and S.Art("dungeon") == 1 and S.Art("raid") == 1 and S.Art("poi-traveldirections-arrow") == 1 and S.Art("flightmaster") == 1,
        "zone A lacks a tram, dungeon, raid, exit or flight pin: " .. Shows(S))
    S.ShowMap(CONTINENT)
    -- every transport and every entrance of both zones; no exits or flight masters
    check(#S.Pins() == 7, "the continent, every kind: " .. Shows(S))
    check(S.Art(SKYCUTTER) == 1 and S.Art(PORTAL) == 1 and S.Art("dungeon") == 2 and S.Art("raid") == 1, "the continent's pins: " .. Shows(S))
    S.ShowMap(WORLD)
    check(#S.Pins() == 4 and S.Art("dungeon") == 0 and S.Art("raid") == 0, "the world map, transports alone: " .. Shows(S))

    -- the same map and toggles again: the pins are kept, not rebuilt
    local before = S.placed
    S.provider:RefreshAllData()
    S.provider.OnMapChanged()
    check(S.placed == before, "a refresh with nothing changed rebuilt the pins")
    check(S.modifyCalls == 1, "a refresh registered the menu again")
end

-------------------------------------------------------------------------------
-- 3. each kind on its own
-------------------------------------------------------------------------------
do
    local S = Session({ enabled = true })
    S.Login()
    S.ShowMap(ZONE_A)
    -- the dock keeps the transport still shown
    S.Set("zeppelins", false)
    local n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == "" and not dock.tip:find("Zeppelin", 1, true), "zeppelins off: the dock does not show its boat alone")
    check(S.Art(ZEPPELIN) == 0 and #S.Pins() == 6, "zeppelins off: " .. Shows(S))
    S.Set("zeppelins", true)
    n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == 2, "zeppelins on again: the dock does not count both again")
    S.Set("boats", false)
    n, dock = S.Art(ZEPPELIN)
    check(n == 1 and dock.count._text == "" and S.Art(BOAT) == 0, "boats off: the dock does not show its zeppelin alone: " .. Shows(S))
    S.Set("zeppelins", false)
    check(S.Art(BOAT) == 0 and S.Art(ZEPPELIN) == 0 and S.Art(TRAM) == 1 and #S.Pins() == 5, "boats and zeppelins off: " .. Shows(S))
    S.Set("trams", false)
    check(S.Art(TRAM) == 0 and #S.Pins() == 4, "the tram off: " .. Shows(S))
    S.Set("boats", true); S.Set("zeppelins", true); S.Set("trams", true)

    -- dungeons and raids part
    S.Set("dungeons", false)
    check(S.Art("dungeon") == 0 and S.Art("raid") == 1 and #S.Pins() == 5, "dungeons off: " .. Shows(S))
    S.ShowMap(CONTINENT)
    check(S.Art("dungeon") == 0 and S.Art("raid") == 1, "dungeons off on the continent: " .. Shows(S))
    S.Set("dungeons", true); S.Set("raids", false)
    check(S.Art("dungeon") == 2 and S.Art("raid") == 0, "raids off on the continent: " .. Shows(S))
    S.ShowMap(ZONE_A)
    check(S.Art("dungeon") == 1 and S.Art("raid") == 0, "raids off: " .. Shows(S))
    S.Set("raids", true)

    -- skycutters and portals (zone B's, seen from the world map)
    S.ShowMap(WORLD)
    S.Set("skycutters", false)
    check(S.Art(SKYCUTTER) == 0 and S.Art(PORTAL) == 1 and #S.Pins() == 3, "skycutters off: " .. Shows(S))
    S.Set("portals", false)
    check(S.Art(PORTAL) == 0 and #S.Pins() == 2, "portals off: " .. Shows(S))
    S.Set("skycutters", true); S.Set("portals", true)

    -- exits and flight points
    S.ShowMap(ZONE_A)
    S.Set("exits", false)
    check(S.Art("poi-traveldirections-arrow") == 0 and #S.Pins() == 5, "zone exits off: " .. Shows(S))
    S.Set("flights", false)
    check(S.Art("flightmaster") == 0 and #S.Pins() == 4, "flight points off: " .. Shows(S))
    S.Set("exits", true); S.Set("flights", true)
    check(#S.Pins() == 6, "every kind on again: " .. Shows(S))

    -- two kinds changed in one write (a reset, an import): as many kinds on as before, another set
    S.Set("zeppelins", false)
    local c = S.MT.Cfg()
    c.boats, c.zeppelins = false, true
    S.MT.Apply()
    n, dock = S.Art(ZEPPELIN)
    check(n == 1 and S.Art(BOAT) == 0, "boats and zeppelins swapped in one write: " .. Shows(S))
    S.Set("boats", true)

    -- a change made while the map is closed shows at its next open, on the same map
    S.CloseMap()
    local before = S.placed
    S.Set("zeppelins", false)
    check(S.placed == before, "a change with the map closed drew pins")
    S.ShowMap(ZONE_A)
    n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == "" and S.Art(ZEPPELIN) == 0, "a kind turned off with the map closed still shows at the next open: " .. Shows(S))
    S.Set("zeppelins", true)
    -- and on another map (zone A with every kind, then zone B with one kind fewer)
    S.CloseMap()
    S.Set("boats", false)
    S.ShowMap(ZONE_B)
    check(#S.Pins() == 3 and S.Art(SKYCUTTER) == 1 and S.Art(PORTAL) == 1 and S.Art("dungeon") == 1,
        "another map opened after a change with the map closed: " .. Shows(S))
    S.Set("boats", true)
    S.ShowMap(ZONE_A)
    check(#S.Pins() == 6, "back on zone A with every kind: " .. Shows(S))

    -- every kind off: the provider goes; one on: it is back
    for _, key in ipairs(KINDS) do S.Set(key, false) end
    check(S.provider == nil and S.removed == 1, "every kind off: the data provider stays on the map")
    check(#S.Pins() == 0, "every kind off: " .. Shows(S))
    check(S.live == 1, "every kind off: the menu section is gone while Map Markers is on")
    S.Set("raids", true)
    check(S.provider ~= nil and S.added == 2, "a kind on again: the data provider is not back")
    check(#S.Pins() == 1 and S.Art("raid") == 1, "a kind on again: " .. Shows(S))
end

-------------------------------------------------------------------------------
-- 4. settings from before: an unset kind follows its older set
-------------------------------------------------------------------------------
do
    local saved = { enabled = true, transports = false }
    local S = Session(saved)
    S.Login()
    S.ShowMap(ZONE_A)
    check(S.Art(BOAT) == 0 and S.Art(ZEPPELIN) == 0 and S.Art(TRAM) == 0 and #S.Pins() == 4, "Transports off before: " .. Shows(S))
    for _, key in ipairs({ "boats", "zeppelins", "skycutters", "trams", "portals" }) do
        check(S.MT.Want(key) == false, "Transports off before: " .. key .. " reads as shown")
    end
    for _, key in ipairs({ "dungeons", "raids", "exits", "flights" }) do
        check(S.MT.Want(key) == true, "Transports off before: " .. key .. " reads as hidden")
    end
    -- a kind set now wins over the older set, which is left as it was
    S.Set("boats", true)
    local n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == "" and S.Art(ZEPPELIN) == 0 and S.Art(TRAM) == 0, "boats turned on over Transports off: " .. Shows(S))
    check(saved.transports == false and saved.boats == true, "the older Transports setting was rewritten")
    check(saved.zeppelins == nil and saved.trams == nil, "kinds nobody set were written")

    local saved2 = { enabled = true, instances = false }
    local T = Session(saved2)
    T.Login()
    T.ShowMap(ZONE_A)
    check(T.Art("dungeon") == 0 and T.Art("raid") == 0 and #T.Pins() == 4, "Instance Entrances off before: " .. Shows(T))
    check(T.MT.Want("dungeons") == false and T.MT.Want("raids") == false and T.MT.Want("boats") == true, "Instance Entrances off before: the kinds read wrong")
    T.Set("raids", true)
    check(T.Art("raid") == 1 and T.Art("dungeon") == 0, "raids turned on over Instance Entrances off: " .. Shows(T))
    check(saved2.instances == false, "the older Instance Entrances setting was rewritten")

    -- the older exits and flight point switches are the kinds' own keys
    local U = Session({ enabled = true, exits = false, flights = false })
    U.Login()
    U.ShowMap(ZONE_A)
    check(U.Art("poi-traveldirections-arrow") == 0 and U.Art("flightmaster") == 0 and #U.Pins() == 4, "Zone Exits and Flight Points off before: " .. Shows(U))
    check(U.MT.Want("exits") == false and U.MT.Want("flights") == false, "the older exits and flights settings are not read")

    -- every older set off: nothing to draw, so no provider, and the section still shows
    local V = Session({ enabled = true, transports = false, instances = false, exits = false, flights = false })
    V.Login()
    check(V.provider == nil and V.added == 0, "every older set off: a data provider is added")
    check(V.live == 1, "every older set off: the menu section is not registered")
end

-------------------------------------------------------------------------------
-- 5. the map's filter menu
-------------------------------------------------------------------------------
do
    local saved = { enabled = true }
    local S = Session(saved)
    S.Login()
    S.ShowMap(ZONE_A)
    local d = S.BuildMenu()
    check(#d.items == 2 + #KINDS, "the filter menu got " .. #d.items .. " entries, not a divider, a title and " .. #KINDS .. " rows")
    check(d.items[1] and d.items[1].kind == "divider", "the section does not start with a divider")
    check(d.items[2] and d.items[2].kind == "title" and d.items[2].text == "Map Markers", "the section has no Map Markers title")
    check(S.translated["Map Markers"], "the section's title is not translated")
    for _, label in ipairs(LABELS) do
        check(S.translated[label], "the row label " .. label .. " is not translated")
    end
    local rows = S.Rows(d)
    for i, key in ipairs(KINDS) do
        local row = rows[i]
        check(row and row.text == LABELS[i], "row " .. i .. " is not " .. LABELS[i])
        check(row and row.data == key, "row " .. i .. " does not carry its kind (" .. tostring(row and row.data) .. ")")
        check(row and S.Ticked(row) == true, "row " .. LABELS[i] .. " is not ticked")
        check(row and row.isSelected == rows[1].isSelected and row.setSelected == rows[1].setSelected,
            "row " .. LABELS[i] .. " has functions of its own")
    end
    -- the next menu: built fresh, the same two functions
    local d2 = S.BuildMenu()
    local rows2 = S.Rows(d2)
    check(#d2.items == 2 + #KINDS, "the next menu got " .. #d2.items .. " entries")
    check(rows2[1] and rows2[1].isSelected == rows[1].isSelected and rows2[9] and rows2[9].setSelected == rows[1].setSelected,
        "the next menu's rows were given new functions")
    check(#d.items == 2 + #KINDS, "the first menu was given the section again")

    -- a click: that kind flips, the pins follow, the menu stays open
    local before = S.placed
    local resp = S.Click(S.Row(d2, "Zeppelins"))
    check(resp == nil or resp == MenuResponse.Refresh, "a click asks the menu to close (" .. tostring(resp) .. ")")
    check(saved.zeppelins == false, "a click on Zeppelins did not turn the kind off")
    check(S.Ticked(S.Row(d2, "Zeppelins")) == false and S.Ticked(S.Row(d2, "Boats")) == true, "the rows do not show the new state")
    local n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == "" and S.placed > before, "a click did not redraw the pins")
    check(S.MT.Want("zeppelins") == false, "the options cog does not read the menu's change")
    S.Click(S.Row(d2, "Zeppelins"))
    check(saved.zeppelins == true and S.Ticked(S.Row(d2, "Zeppelins")) == true, "a second click did not turn the kind back on")
    n, dock = S.Art(BOAT)
    check(n == 1 and dock.count._text == 2, "a second click did not bring the zeppelin back to the dock")
    -- the cog's change shows in the menu
    S.Set("raids", false)
    check(S.Ticked(S.Row(d2, "Raids")) == false, "the menu does not read the cog's change")
    S.Set("raids", true)
    -- every row from the menu: off, then on
    for _, row in ipairs(rows2) do S.Click(row) end
    check(S.provider == nil and #S.Pins() == 0, "every row unticked: " .. Shows(S))
    local d3 = S.BuildMenu()
    check(#d3.items == 2 + #KINDS, "every kind off: the section is gone from the menu")
    for _, row in ipairs(S.Rows(d3)) do
        check(S.Ticked(row) == false, "every kind off: row " .. row.text .. " is ticked")
    end
    S.Click(S.Row(d3, "Flight Points"))
    check(S.provider ~= nil and #S.Pins() == 1 and S.Art("flightmaster") == 1, "one row ticked again: " .. Shows(S))
    check(S.modifyCalls == 1 and S.live == 1, "the clicks registered the menu again (" .. S.modifyCalls .. " calls)")
end

-------------------------------------------------------------------------------
-- 6. Map Markers off and on: the section goes and comes back, once per menu
-------------------------------------------------------------------------------
do
    local S = Session(nil)
    S.Login()
    -- the map was opened before Map Markers is turned on: the game hands that menu over at once
    local old = S.BuildMenu()
    S.Set("enabled", true)
    check(S.modifyCalls == 1 and S.live == 1, "turned on: the menu is not registered once")
    check(#old.items == 2 + #KINDS, "turned on: the menu built last did not get the section once (" .. #old.items .. " entries)")
    S.Set("enabled", false)
    check(S.live == 0, "turned off: the menu callback stays registered")
    check(S.provider == nil, "turned off: the data provider stays on the map")
    local d = S.BuildMenu()
    check(#d.items == 0, "turned off: a new menu still gets the section")
    -- on again: the menu built last (d) gets it once; the older one is not given a second
    S.Set("enabled", true)
    check(S.live == 1 and S.modifyCalls == 2, "turned on again: the menu is not registered again once")
    check(#d.items == 2 + #KINDS and #old.items == 2 + #KINDS, "turned on again: " .. #d.items .. " and " .. #old.items .. " entries")
    S.Set("enabled", false)
    S.Set("enabled", true)
    check(#d.items == 2 + #KINDS, "off and on with the same menu last built: it got the section twice (" .. #d.items .. " entries)")
    check(S.live == 1, "off and on: " .. S.live .. " callbacks live")
    -- the options writes do not register again while it is on
    S.Set("boats", false); S.Set("boats", true)
    check(S.modifyCalls == 3 and S.live == 1, "a kind's change registered the menu again")
end

-------------------------------------------------------------------------------
-- 7. the module's own places: every transport's kind has a toggle
-------------------------------------------------------------------------------
do
    local S = Session({ enabled = true }, { realData = true })
    S.Login()
    S.ShowMap(WORLD)
    local all = #S.Pins()
    check(all > 10, "the module's own places draw " .. all .. " transport pins on the world map")
    local ARTS = { boats = BOAT, zeppelins = ZEPPELIN, skycutters = SKYCUTTER, trams = TRAM, portals = PORTAL }
    for _, key in ipairs({ "boats", "zeppelins", "skycutters", "trams", "portals" }) do S.Set(key, false) end
    check(S.provider ~= nil and #S.Pins() == 0, "every transport kind off leaves " .. #S.Pins() .. " transport pins on the world map")
    -- each kind alone draws pins, all in its own art
    for key, art in pairs(ARTS) do
        S.Set(key, true)
        local n = S.Art(art)
        check(n > 0 and n == #S.Pins(), key .. " alone: " .. n .. " of " .. #S.Pins() .. " pins wear its art")
        S.Set(key, false)
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_fe_map_markers_kinds (%d checks)"):format(count))
