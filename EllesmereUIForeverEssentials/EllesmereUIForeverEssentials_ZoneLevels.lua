if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ZoneLevels.lua  (WoW Forever only)
--  Show Zone Levels: on a continent map, the level range of the hovered zone
--  under its name, colored by difficulty, as the map shows it wherever
--  C_Map.GetMapLevels has data (it returns 0 on Forever).
--
--  The map's area label writes the hovered zone's name into its Name text,
--  only when it changes; a hooksecurefunc on that SetText reads it, and the
--  range goes in a text of our own under the label. Nothing of Blizzard's is
--  written; no cursor reading, no OnUpdate.
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

local byName      -- zone name (as the map writes it) = { min, max }; built on first use
local text, waiter
local hooked = false

-- The map's own format: the range colored like a quest of the nearest level.
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
    return EllesmereUI.HexColor(c.r, c.g, c.b) .. ("(%d-%d)|r"):format(lo, hi)
end

-- The area label's Name changed: the range when it names a zone of the shown
-- continent, nothing otherwise. Off, Apply has hidden the text.
local function OnLabelName(_, name)
    if not F.Enabled() then return end
    local lv
    if name and name ~= "" then
        local info = C_Map.GetMapInfo(WorldMapFrame:GetMapID())
        if info and info.mapType == Enum.UIMapType.Continent then lv = byName[name] end
    end
    if lv then
        text:SetText(LevelsText(lv))
        text:Show()
    else
        text:Hide()
    end
end

-- The map's area label, read from its data providers.
local function AreaLabel()
    for provider in pairs(WorldMapFrame.dataProviders or {}) do
        local label = provider.Label
        if label and label.Name and label.labelInfoByType then return label end
    end
end

local function Build()
    local label = AreaLabel()
    if not label then return end
    hooked = true
    byName = {}
    for id, lv in pairs(LEVELS) do
        local info = C_Map.GetMapInfo(id)
        if info and info.name then byName[info.name] = lv end
    end
    local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
    holder:SetAllPoints()
    holder:SetFrameStrata("HIGH")
    text = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    -- Smaller than the zone name it sits under.
    local font, size, flags = label.Name:GetFont()
    if font and size then text:SetFont(font, math.floor(size * 0.7 + 0.5), flags) end
    text:SetPoint("TOP", label.Name, "BOTTOM", 0, -6)
    text:Hide()
    hooksecurefunc(label.Name, "SetText", OnLabelName)
end

-- Nothing exists until the setting is first on; off, the text hides and the
-- hook returns at once. The world map loads on demand, so building may wait.
local function Apply()
    if hooked then
        if not F.Enabled() then text:Hide() end
        return
    end
    if not F.Enabled() then
        if waiter then waiter:UnregisterEvent("ADDON_LOADED") end
        return
    end
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
