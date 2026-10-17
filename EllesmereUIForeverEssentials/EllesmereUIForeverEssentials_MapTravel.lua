if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MapTravel.lua  (WoW Forever only)
--  Map Markers: travel pins by zoom level. The world map shows transports,
--  a continent adds instance entrances, a zone adds flight points and its
--  exits; each set has its cog toggle. Hovering a pin names it; a left click
--  prints its map pin link in chat, as /way does, pointing at the zone it
--  stands in; a right click goes on to the map (back out a level).
--
--  As Reveal Unexplored Areas: nothing of Blizzard's map is hooked; a data
--  provider reports map changes and zoom, and the pins are frames of our own
--  on a frame of ours under the canvas.
--  Places: EllesmereUIForeverEssentials_MapTravelData.lua.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.mapTravel; unset keys read these.
local F = module.Feature("mapTravel", { enabled = false, transports = true, exits = true, instances = true,
    flights = true })

-- A set of pins shows while Map Markers is on and its cog toggle too.
local function On(key)
    return F.Get("enabled") and F.Get(key)
end

local PIN_SIZE   = 22
local ARROW_SIZE = 20
local INSTANCE_SIZE = 32  -- the portal art leaves a wide margin in its atlas

local KIND_ATLAS = {
    boat      = "flightmasterferry",
    zeppelin  = "vehicle-air-horde",
    tram      = "vehicle-alliancecart",
    skycutter = "vehicle-air-alliance",
    portal    = "mageportalalliance",
}

local data, provider, layer, waiter, taxiWatch
local added = false
local pins, used = {}, 0
local shownKey  -- what the pins show (map and toggles); nil when cleared
local shownMap  -- the map the pins are on

local function AnyOn()
    return On("transports") or On("exits") or On("instances") or On("flights")
end

-- A pin's tooltip, led by its icon (a transport's lines carry their own).
local function PinTip(p)
    if p.tip:find("^|A") or p.atlas:find("\\", 1, true) then return p.tip end
    return ("|A:%s:16:16|a "):format(p.atlas) .. p.tip
end

-- Pins that touch on screen (it depends on the zoom) share one tooltip: the
-- hovered pin's first, then each one touching it. Offsets and sizes are both
-- in the pins' own (scaled) units, as Anchor sets them.
local function PinOnEnter(self)
    local canvas = layer:GetParent()
    local w, h = canvas:GetSize()
    local cs = canvas:GetScale()
    local tip = PinTip(self)
    for i = 1, used do
        local p = pins[i]
        if p ~= self then
            local reach = (p.size + self.size) / 2
            if math.abs(p.x - self.x) * w * cs < reach and math.abs(p.y - self.y) * h * cs < reach then
                tip = tip .. "\n\n" .. PinTip(p)
            end
        end
    end
    if C_Map.CanSetUserWaypointOnMap(self.linkMap) then
        tip = tip .. "\n\n" .. EllesmereUI.COLOR_CODES.DIM .. EllesmereUI.L("Click to link it in chat.") .. "|r"
    end
    EllesmereUI.ShowWidgetTooltip(self, tip)
end

local function PinOnLeave()
    EllesmereUI.HideWidgetTooltip()
end

-- A pin's name for its link: the first line of its tooltip, without icons
-- or colors ("Boat to Menethil Harbor").
local function PinLabel(tip)
    local line = tip:match("^[^\n]*")
    line = line:gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(line)
end

-- The link C_Map.GetUserWaypointHyperlink builds, as /way prints it: x, y
-- (0..1 here) travel as 0..10000. Clicked in chat, Blizzard places the pin.
local hintedClick = false
local function PrintLink(mapID, x, y, label, atlas)
    local CC = EllesmereUI.COLOR_CODES
    local icon = atlas and not atlas:find("\\", 1, true) and ("|A:%s:16:16|a "):format(atlas) or ""
    local link = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(mapID,
        math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), MAP_PIN_HYPERLINK)
    EllesmereUI.Print(CC.BRAND .. "EllesmereUI:|r " .. link .. " " .. icon .. CC.WHITE .. label .. "|r "
        .. CC.DIM .. ("%.1f, %.1f"):format(x * 100, y * 100) .. "|r")
    if not hintedClick then
        hintedClick = true
        EllesmereUI.Print(CC.BRAND .. "EllesmereUI:|r " .. CC.DIM
            .. EllesmereUI.L("Click a link to place the pin, then click the pin on the map to track it.") .. "|r")
    end
end

-- A left click on a pin: its link in chat, led by its icon, kind and name, on
-- the zone it stands in (world and continent maps take no pin). A line
-- printed in combat taints chat history, so it waits for the end of combat.
local function PinOnMouseUp(self, button)
    if button ~= "LeftButton" or not C_Map.CanSetUserWaypointOnMap(self.linkMap) then return end
    local mapID, x, y, atlas = self.linkMap, self.linkX, self.linkY, self.atlas
    local label = self.link or PinLabel(self.tip)
    local function Print() PrintLink(mapID, x, y, label, atlas) end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("MapTravelLink", Print)
    else
        Print()
    end
end

local function Clear()
    for i = 1, used do pins[i]:Hide() end
    used = 0
    shownKey = nil
end

-- Right clicks pass through every pin to the map. SetPassThroughButtons is
-- protected in combat: set once per pin, a pin made in combat waits for its end.
local function PassRightClicks()
    for i = 1, #pins do
        local p = pins[i]
        if not p.passes then
            p:SetPassThroughButtons("RightButton")
            p.passes = true
        end
    end
end

-- The next pin from our pool: hover names it, a left click links it.
local function NextPin()
    used = used + 1
    local p = pins[used]
    if not p then
        p = CreateFrame("Frame", nil, layer)
        p:SetMouseMotionEnabled(true)
        p:SetMouseClickEnabled(true)
        p:SetScript("OnMouseUp", PinOnMouseUp)
        p.tex = p:CreateTexture(nil, "ARTWORK")
        p.tex:SetAllPoints()
        p.count = p:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        p.count:SetPoint("BOTTOMRIGHT", 4, -2)
        p:SetScript("OnEnter", PinOnEnter)
        p:SetScript("OnLeave", PinOnLeave)
        pins[used] = p
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer("MapTravelPass", PassRightClicks)
        else
            PassRightClicks()
        end
    end
    return p
end

-- Pins are scaled against the canvas, so they keep one size on screen at any
-- zoom; their offsets are in their own (scaled) units.
local function Anchor(p)
    local canvas = layer:GetParent()
    local w, h = canvas:GetSize()
    local cs = canvas:GetScale()
    p:SetScale(1 / cs)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", p.x * w * cs, -p.y * h * cs)
end

-- A pin at (x, y) of the canvas (0..1); count > 1 shows as a badge. link: its
-- kind and name for the chat line ("Dungeon: The Deadmines"). Its chat link
-- points at the shown map; a pin drawn from a zone onto a wider map points
-- back at the zone (the caller sets linkMap, linkX, linkY).
local function Place(x, y, atlas, size, tip, rotation, count, link)
    local p = NextPin()
    p.x, p.y, p.size = x, y, size
    p:SetSize(size, size)
    Anchor(p)
    if atlas:find("\\", 1, true) then p.tex:SetTexture(atlas) else p.tex:SetAtlas(atlas) end
    p.tex:SetRotation(rotation or 0)
    p.count:SetText(count and count > 1 and count or "")
    p.tip, p.link, p.atlas = tip, link, atlas
    p.linkMap, p.linkX, p.linkY = shownMap, x, y
    p:Show()
    return p
end

-- A zoom: the same pins, rescaled (rebuilding them would drop the tooltip).
local function Rescale()
    for i = 1, used do Anchor(pins[i]) end
end

local function ZoneName(uiMapID)
    local info = C_Map.GetMapInfo(uiMapID)
    return info and info.name or ""
end

local function TransportTip(t)
    -- The place alone ("Orgrimmar"), its zone when the area has no name.
    local area = C_Map.GetAreaInfo(t[5])
    local where = area and area ~= "" and area or ZoneName(t[4])
    if t[3] == "boat" then return EllesmereUI.Lf("Boat to %s", where) end
    if t[3] == "zeppelin" then return EllesmereUI.Lf("Zeppelin to %s", where) end
    if t[3] == "skycutter" then return EllesmereUI.Lf("Skycutter to %s", where) end
    if t[3] == "portal" then return EllesmereUI.Lf("Portal to %s", where) end
    return EllesmereUI.Lf("Tram to %s", where)
end

-- The instance's name, the entrance or wings it opens on, then its kind.
local function InstanceTip(i)
    local tip = GetRealZoneText(i[3])
    if i[5] then tip = tip .. "\n|cffffffff" .. EllesmereUI.L(i[5]) .. "|r" end
    return tip .. "\n" .. (i[4] and EllesmereUI.L("Raid") or EllesmereUI.L("Dungeon"))
end

-- Its chat line: "Dungeon: The Deadmines (Main Entrance)".
local function InstanceLink(i)
    local name = GetRealZoneText(i[3])
    if i[5] then name = name .. " (" .. EllesmereUI.L(i[5]) .. ")" end
    return i[4] and EllesmereUI.Lf("Raid: %s", name) or EllesmereUI.Lf("Dungeon: %s", name)
end

-- The arrow's angle toward the destination zone's middle, read on the continent.
local function ExitRotation(zone, x, y, dest)
    local info = C_Map.GetMapInfo(zone)
    local continent = info and info.parentMapID
    if not continent or continent == 0 then return 0 end
    local zl, zr, zt, zb = C_Map.GetMapRectOnMap(zone, continent)
    local l, r, t, b = C_Map.GetMapRectOnMap(dest, continent)
    if not (zl and l) then return 0 end
    local px, py = zl + x * (zr - zl), zt + y * (zb - zt)
    local dx, dy = (l + r) / 2 - px, (t + b) / 2 - py
    return math.atan2(-dx, -dy)  -- the atlas points up; screen y grows down
end

-- A zone's transports, those of one place (a dock's boats, a tower's
-- zeppelins) sharing one pin whose tooltip lists them all. Built once per zone.
local GROUP_DIST = 7  -- percent of the zone map
local transportGroups = {}
local function TransportGroups(zone)
    local groups = transportGroups[zone]
    if groups then return groups end
    groups = {}
    local list = data.transports[zone] or {}
    for i = 1, #list do
        local t = list[i]
        local g
        for j = 1, #groups do
            local h = groups[j]
            if math.abs(h.x - t[1]) < GROUP_DIST and math.abs(h.y - t[2]) < GROUP_DIST then
                g = h
                break
            end
        end
        -- Each destination on its own line, led by its transport's icon.
        local line = ("|A:%s:16:16|a %s"):format(KIND_ATLAS[t[3]], TransportTip(t))
        if g then
            g.tip = g.tip .. "\n" .. line
            g.link = g.link .. ", " .. TransportTip(t)
            g.count = g.count + 1
        else
            groups[#groups + 1] = { x = t[1], y = t[2], atlas = KIND_ATLAS[t[3]], tip = line,
                link = TransportTip(t), count = 1 }
        end
    end
    transportGroups[zone] = groups
    return groups
end

-- A zone map's pins.
local function DrawZone(zone)
    if On("transports") then
        local groups = TransportGroups(zone)
        for i = 1, #groups do
            local g = groups[i]
            Place(g.x / 100, g.y / 100, g.atlas, PIN_SIZE, g.tip, nil, g.count, g.link)
        end
    end
    if On("instances") then
        local list = data.instances[zone]
        if list then
            for i = 1, #list do
                local e = list[i]
                Place(e[1] / 100, e[2] / 100, e[4] and "raid" or "dungeon", INSTANCE_SIZE, InstanceTip(e),
                    nil, nil, InstanceLink(e))
            end
        end
    end
    if On("exits") then
        local list = data.exits[zone]
        if list then
            for i = 1, #list do
                local e = list[i]
                local x, y = e[1] / 100, e[2] / 100
                Place(x, y, "poi-traveldirections-arrow", ARROW_SIZE, ZoneName(e[3]),
                    ExitRotation(zone, x, y, e[3]), nil,
                    EllesmereUI.Lf("Path from %s to %s", ZoneName(zone), ZoneName(e[3])))
            end
        end
    end
end

-- A zone's point (0..1) on a wider map that holds it, or nil.
local function OnWiderMap(zone, map, x, y)
    local l, r, t, b = C_Map.GetMapRectOnMap(zone, map)
    if not l or r <= l or b <= t then return nil end
    x, y = l + x * (r - l), t + y * (b - t)
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- A world or continent map's pins: the transports, and on a continent the
-- instance entrances too, each linking back to its zone.
local function DrawWider(map, instances)
    if On("transports") then
        for zone in pairs(data.transports) do
            local groups = TransportGroups(zone)
            for i = 1, #groups do
                local g = groups[i]
                local x, y = OnWiderMap(zone, map, g.x / 100, g.y / 100)
                if x then
                    local p = Place(x, y, g.atlas, PIN_SIZE, g.tip, nil, g.count, g.link)
                    p.linkMap, p.linkX, p.linkY = zone, g.x / 100, g.y / 100
                end
            end
        end
    end
    if instances and On("instances") then
        for zone, list in pairs(data.instances) do
            for i = 1, #list do
                local e = list[i]
                local x, y = OnWiderMap(zone, map, e[1] / 100, e[2] / 100)
                if x then
                    local p = Place(x, y, e[4] and "raid" or "dungeon", INSTANCE_SIZE, InstanceTip(e),
                        nil, nil, InstanceLink(e))
                    p.linkMap, p.linkX, p.linkY = zone, e[1] / 100, e[2] / 100
                end
            end
        end
    end
end

-- The flight masters standing on a map (the game also lists those of the rest
-- of the continent, off its edges), the other faction's and the retired ones
-- ("zz" names) left out; none where the map draws its own.
local function FlightNodes(mapID)
    if C_TaxiMap.ShouldMapShowTaxiNodes(mapID) then return nil end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(mapID)
    if not nodes then return nil end
    local Faction = Enum.FlightPathFaction
    local mine = UnitFactionGroup("player") == "Horde" and Faction.Horde or Faction.Alliance
    local list = {}
    for i = 1, #nodes do
        local n = nodes[i]
        local x, y = n.position.x, n.position.y
        if (n.faction == Faction.Neutral or n.faction == mine) and not n.name:find("^zz")
            and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            if n.isUndiscovered then
                n.note = n.faction == Faction.Neutral and UNDISCOVERED_NEUTRAL_FLIGHTPOINT
                    or UNDISCOVERED_FACTION_FLIGHTPOINT:format(mine == Faction.Horde and FACTION_HORDE or FACTION_ALLIANCE)
            end
            if n.atlasName == "" then n.atlasName = "flightmaster" end
            list[#list + 1] = n
        end
    end
    return list
end

local function DrawFlights(mapID)
    local list = FlightNodes(mapID)
    if not list then return end
    for i = 1, #list do
        local n = list[i]
        local tip = n.note and (n.name .. "\n|cff808080" .. n.note .. "|r") or n.name
        Place(n.position.x, n.position.y, n.atlasName, PIN_SIZE, tip, nil, nil,
            EllesmereUI.Lf("Flight Point: %s", n.name))
    end
end

-- The map redraws its providers often (shows, quest and area updates): the
-- pins are rebuilt only when the map or the toggles changed, so a hovered
-- pin keeps its tooltip.
local function Refresh(force)
    local mapID = WorldMapFrame:GetMapID()
    -- One number for the map and the four toggles: no string per refresh.
    local key = mapID and (mapID * 16 + (On("transports") and 1 or 0)
        + (On("instances") and 2 or 0) + (On("exits") and 4 or 0)
        + (On("flights") and 8 or 0))
    if key and key == shownKey and force ~= true then
        Rescale()
        return
    end
    Clear()
    shownKey = key
    shownMap = mapID
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info then return end
    -- The world shows the transports; a continent adds the instance entrances;
    -- a zone adds the flight points and its exits.
    if info.mapType == Enum.UIMapType.World then
        DrawWider(mapID, false)
    elseif info.mapType == Enum.UIMapType.Continent then
        DrawWider(mapID, true)
    elseif info.mapType ~= Enum.UIMapType.Cosmic then
        if On("flights") then DrawFlights(mapID) end
        DrawZone(mapID)
    end
end

local function Build()
    data = module.MapTravelData()
    module.MapTravelData = nil

    layer = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    layer:SetAllPoints()
    -- Above the map's own points of interest (a city's pin must not take the
    -- mouse from a dock or a tower beside it).
    layer:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_LINK"))

    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged = function() Refresh() end
    provider.RefreshAllData = function() Refresh() end
    provider.RemoveAllData = Clear
    provider.OnCanvasScaleChanged = Rescale
    provider.OnGlobalAlphaChanged = function(self) layer:SetAlpha(self:GetMap():GetGlobalAlpha()) end
end

-- Nothing exists until Map Markers is first on; off, the provider is removed.
-- The world map loads on demand, so building may wait for it.
local function Apply()
    if not AnyOn() then
        if added then
            WorldMapFrame:RemoveDataProvider(provider)
            added = false
        end
        if waiter then waiter:UnregisterEvent("ADDON_LOADED") end
        if taxiWatch then taxiWatch:UnregisterEvent("TAXI_NODE_STATUS_CHANGED") end
        return
    end
    if not provider then
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if not waiter then
                waiter = CreateFrame("Frame")
                waiter:SetScript("OnEvent", function(self, _, name)
                    if name ~= "Blizzard_WorldMap" then return end
                    self:UnregisterEvent("ADDON_LOADED")
                    Apply()
                end)
            end
            waiter:RegisterEvent("ADDON_LOADED")
            return
        end
        Build()
    end
    if not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    end
    -- A flight point found: the next draw rebuilds the pins.
    if On("flights") then
        if not taxiWatch then
            taxiWatch = CreateFrame("Frame")
            taxiWatch:SetScript("OnEvent", function() shownKey = nil end)
        end
        taxiWatch:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
    elseif taxiWatch then
        taxiWatch:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
    end
    if WorldMapFrame:IsShown() then Refresh(true) end
end

-- Options-page entry points.
EllesmereUI._MapTravel = {
    Get = F.Get,
    On = On,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
