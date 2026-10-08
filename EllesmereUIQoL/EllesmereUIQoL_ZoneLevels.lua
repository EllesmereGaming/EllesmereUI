if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ZoneLevels.lua  (WoW Forever only)
--  Shows a zone's level range next to the world map's hover label, as the map
--  does on its own wherever C_Map.GetMapLevels has data (it returns 0 on
--  Forever), colored by the quest difficulty colors, for zones hovered on a
--  continent. Text of our own, anchored to Blizzard's label, which is never
--  written to.
--  Setting: EllesmereUIDB.mapZoneLevels (off by default).
-------------------------------------------------------------------------------
local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.mapZoneLevels == true
end

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

local hooked
local suffix      -- ours: " (lo-hi)" right after the hovered name

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
    return ("|cff%02x%02x%02x (%d-%d)|r"):format(c.r * 255, c.g * 255, c.b * 255, lo, hi)
end

-- Runs after the label's Name:SetText, which EvaluateLabels only calls when
-- the shown label changes: a zone hovered on a continent gets its range.
local function OnNameSet(_, text)
    suffix:Hide()
    if not Enabled() or not text or issecretvalue(text) or text == "" then return end
    -- The map label's own lookup: the child map under the cursor. Its name
    -- being the shown one rules out POI and banner labels.
    local mapID = WorldMapFrame:GetMapID()
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if not (info and info.mapID ~= mapID and info.name == text) then return end
    local lv = LEVELS[info.mapID]
    if lv then
        suffix:SetText(LevelsText(lv))
        suffix:Show()
    end
end

-- Finds the world map's area label (AreaLabelDataProvider) and hooks it once.
local function Hook()
    if hooked or not (WorldMapFrame and WorldMapFrame.dataProviders) then return end
    for provider in pairs(WorldMapFrame.dataProviders) do
        local label = provider.Label
        if label and label.Name and label.EvaluateLabels then
            local holder = CreateFrame("Frame", nil, label)
            holder:SetAllPoints()
            suffix = holder:CreateFontString(nil, "OVERLAY")
            suffix:SetFontObject(label.Name:GetFontObject())
            suffix:SetPoint("LEFT", label.Name, "RIGHT")
            suffix:Hide()

            hooksecurefunc(label.Name, "SetText", OnNameSet)
            hooked = true
            return
        end
    end
end

-- Nothing exists (no frame, event or hook) until the setting is first on; the
-- hook then idles while it is off. The world map loads on demand, so the hook
-- may wait for it.
local waiter
local function Apply()
    if hooked then
        if not Enabled() then suffix:Hide() end
        return
    end
    if not Enabled() then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then Hook() return end
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_WorldMap" then return end
            self:UnregisterEvent("ADDON_LOADED")
            Hook()
        end)
    end
    waiter:RegisterEvent("ADDON_LOADED")
end

-- EllesmereUIDB (a dependency's saved data) is already loaded here.
Apply()

-- Options toggle (Quality of Life page).
EllesmereUI._applyMapZoneLevels = Apply
