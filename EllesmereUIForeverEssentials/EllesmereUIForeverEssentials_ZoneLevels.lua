if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ZoneLevels.lua  (WoW Forever only)
--  Shows the level range of the zone under the cursor on a continent map,
--  as the map does on its own wherever C_Map.GetMapLevels has data (it
--  returns 0 on Forever), colored by the quest difficulty colors.
--
--  Taint: nothing of Blizzard's map is hooked or written to, only read. A frame
--  of our own, child of the map's scroll container (so it only updates while
--  the map shows), reads the cursor and the canvas geometry through widget
--  API and shows the range in a text of its own under the zone name.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.zoneLevels; unset keys read these.
local F = module.Feature("zoneLevels", { enabled = false })

-- uiMapID = { min, max }
local LEVELS = {
    -- Eastern Kingdoms
    [1426] = { 1, 10 },   -- Dun Morogh
    [1429] = { 1, 10 },   -- Elwynn Forest
    [1420] = { 1, 10 },   -- Tirisfal Glades
    [1432] = { 10, 20 },  -- Loch Modan
    [1436] = { 10, 20 },  -- Westfall
    [1421] = { 10, 20 },  -- Silverpine Forest
    [1433] = { 15, 25 },  -- Redridge Mountains
    [1431] = { 18, 30 },  -- Duskwood
    [1437] = { 20, 30 },  -- Wetlands
    [1424] = { 20, 30 },  -- Hillsbrad Foothills
    [1416] = { 30, 40 },  -- Alterac Mountains
    [1417] = { 30, 40 },  -- Arathi Highlands
    [1434] = { 30, 45 },  -- Stranglethorn Vale
    [1418] = { 35, 45 },  -- Badlands
    [1435] = { 35, 45 },  -- Swamp of Sorrows
    [1425] = { 40, 50 },  -- The Hinterlands
    [1427] = { 43, 50 },  -- Searing Gorge
    [1419] = { 45, 55 },  -- Blasted Lands
    [1428] = { 50, 58 },  -- Burning Steppes
    [1422] = { 51, 58 },  -- Western Plaguelands
    [1423] = { 53, 60 },  -- Eastern Plaguelands
    [1430] = { 55, 60 },  -- Deadwind Pass
    [2548] = { 35, 45 },  -- Riverglades (Forever)
    -- Kalimdor
    [1411] = { 1, 10 },   -- Durotar
    [1412] = { 1, 10 },   -- Mulgore
    [1438] = { 1, 10 },   -- Teldrassil
    [1439] = { 10, 20 },  -- Darkshore
    [1413] = { 10, 25 },  -- The Barrens
    [1442] = { 15, 27 },  -- Stonetalon Mountains
    [1440] = { 18, 30 },  -- Ashenvale
    [1441] = { 25, 35 },  -- Thousand Needles
    [1443] = { 30, 40 },  -- Desolace
    [1445] = { 35, 45 },  -- Dustwallow Marsh
    [1444] = { 40, 50 },  -- Feralas
    [1446] = { 40, 50 },  -- Tanaris
    [1447] = { 45, 55 },  -- Azshara
    [1448] = { 48, 55 },  -- Felwood
    [1449] = { 48, 55 },  -- Un'Goro Crater
    [1451] = { 55, 60 },  -- Silithus
    [1452] = { 55, 60 },  -- Winterspring
    [2482] = { 55, 60 },  -- Mount Hyjal (Forever)
    [2652] = { 35, 45 },  -- Shen'dralas (Forever)
    -- Elsewhere
    [2521] = { 1, 12 },   -- Zephras Isle (Forever)
}

local UPDATE_INTERVAL = 0.15
local TEXT_OFFSET_Y   = -50  -- just under the map's own area name

local watcher  -- ours; nil until the setting is first on

-- The map's own format: the range is colored like a quest of the nearest level.
local function LevelsText(lv)
    local lo, hi = lv[1], lv[2]
    local level = UnitLevel("player")
    local c
    if level < lo then
        c = GetQuestDifficultyColor(lo)
    elseif level > hi then
        c = GetQuestDifficultyColor(hi - 2)  -- a zone below the player is never yellow
    else
        c = QuestDifficultyColors["difficult"]
    end
    return ("|cff%02x%02x%02x(%d-%d)|r"):format(c.r * 255, c.g * 255, c.b * 255, lo, hi)
end

-- The zone (child map) under the cursor, or nil. Same lookup as the map's own
-- label, with the cursor normalized against the canvas by widget API only.
local function HoveredZone(self)
    if not self.scroll:IsMouseOver() then return nil end
    local canvas = self.scroll.Child
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not (left and top) or width == 0 or height == 0 then return nil end
    local cx, cy = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    local x = (cx / scale - left) / width
    local y = (top - cy / scale) / height
    local mapID = WorldMapFrame:GetMapID()
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if info and info.mapID ~= mapID then return info.mapID end
end

local function OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < UPDATE_INTERVAL then return end
    self.elapsed = 0
    local zone = HoveredZone(self)
    local lv = zone and LEVELS[zone]
    if zone == self.zone and lv == self.lv then return end
    self.zone, self.lv = zone, lv
    if lv then
        self.text:SetText(LevelsText(lv))
        self.text:Show()
    else
        self.text:Hide()
    end
end

local function Build()
    local scroll = WorldMapFrame.ScrollContainer
    watcher = CreateFrame("Frame", nil, scroll)
    watcher:SetAllPoints()
    watcher:SetFrameStrata("HIGH")
    watcher.scroll = scroll
    watcher.elapsed = 0
    watcher.text = watcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    watcher.text:SetPoint("TOP", 0, TEXT_OFFSET_Y)
    watcher.text:Hide()
    watcher:SetScript("OnUpdate", OnUpdate)
end

-- Nothing exists (no frame or event) until the setting is first on; while it
-- is off the frame stays hidden, so it never updates. The world map loads on
-- demand, so building may wait for it.
local waiter
local function Apply()
    if watcher then
        watcher:SetShown(F.Enabled())
        return
    end
    if not F.Enabled() then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then Build() return end
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_WorldMap" then return end
            self:UnregisterEvent("ADDON_LOADED")
            Build()
        end)
    end
    waiter:RegisterEvent("ADDON_LOADED")
end

-- Options-page entry points.
EllesmereUI._ZoneLevels = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
