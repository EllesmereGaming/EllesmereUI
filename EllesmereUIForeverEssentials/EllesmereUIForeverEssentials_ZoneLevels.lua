if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ZoneLevels.lua  (WoW Forever only)
--  Show Zone Levels: on a continent map, the level range of the hovered zone
--  under its name, colored by difficulty, as the map shows it wherever
--  C_Map.GetMapLevels has data (it returns 0 on Forever).
--  Show Fishing Skill: under it, the fishing skill the zone needs, on a
--  continent for the hovered zone, on a zone map for that zone.
--
--  The map's area label writes the hovered zone's name into its Name text,
--  only when it changes; a hooksecurefunc on that SetText reads it, and the
--  lines go in texts of our own under the label, the fishing skill in a
--  much smaller one. Nothing of Blizzard's is
--  written; no cursor reading, no OnUpdate.
--  Fishing skills: the original game's zone values, fish no longer getting
--  away 95 points above them. The zones WoW Forever added are left out until
--  their skill is known.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.zoneLevels; unset keys read these.
--   enabled   Show Zone Levels
--   fishing   Show Fishing Skill
local F = module.Feature("zoneLevels", { enabled = false, fishing = false })

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

-- uiMapID = the zone's base fishing skill: fish bite from it (at least 1) and
-- stop getting away 95 points above.
local FISHING = {
    -- Eastern Kingdoms
    [1426] = -70, [1429] = -70, [1420] = -70,                -- Dun Morogh, Elwynn Forest, Tirisfal Glades
    [1432] = -20, [1436] = -20, [1421] = -20,                -- Loch Modan, Westfall, Silverpine Forest
    [1433] = 55, [1431] = 55, [1437] = 55, [1424] = 55,      -- Redridge Mountains, Duskwood, Wetlands, Hillsbrad
    [1416] = 130, [1417] = 130, [1434] = 130, [1435] = 130,  -- Alterac, Arathi, Stranglethorn Vale, Swamp of Sorrows
    [1425] = 205, [1422] = 205,                              -- The Hinterlands, Western Plaguelands
    [1423] = 330, [1428] = 330, [1430] = 330,                -- Eastern Plaguelands, Burning Steppes, Deadwind Pass
    [1453] = -20, [1455] = -20, [1458] = -20,                -- Stormwind City, Ironforge, Undercity
    -- Kalimdor
    [1411] = -70, [1412] = -70, [1438] = -70,                -- Durotar, Mulgore, Teldrassil
    [1439] = -20, [1413] = -20,                              -- Darkshore, The Barrens
    [1442] = 55, [1440] = 55,                                -- Stonetalon Mountains, Ashenvale
    [1441] = 130, [1443] = 130, [1445] = 130,                -- Thousand Needles, Desolace, Dustwallow Marsh
    [1444] = 205, [1446] = 205, [1447] = 205, [1448] = 205, -- Feralas, Tanaris, Azshara, Felwood
    [1449] = 205, [1450] = 205,                              -- Un'Goro Crater, Moonglade
    [1451] = 330, [1452] = 330,                              -- Silithus, Winterspring
    [1454] = -20, [1456] = -20, [1457] = -20,                -- Orgrimmar, Thunder Bluff, Darnassus
}
local NO_GETAWAY = 95
local FISHING_SPELL = 7620

local byName      -- zone name (as the map writes it) = its uiMapID; built on first use
local text, fishText, areaName, waiter
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

-- "Fishing 330": the skill the zone needs, colored by the player's skill
-- (lures and gear included): red below it, yellow while fish still get away,
-- green once none do; white without Fishing.
local function FishingText(base)
    local low, high = math.max(base, 1), base + NO_GETAWAY
    local r, g, b = 1, 1, 1
    local _, _, _, fishing = GetProfessions()
    if fishing then
        local _, _, rank, _, _, _, _, modifier = GetProfessionInfo(fishing)
        local skill = rank + (modifier or 0)
        if skill < low then
            r, g, b = 1, 0.25, 0.25
        elseif skill < high then
            r, g, b = 1, 0.82, 0
        else
            r, g, b = 0.25, 1, 0.25
        end
    end
    return EllesmereUI.HexColor(r, g, b)
        .. ("%s %d|r"):format(C_Spell.GetSpellName(FISHING_SPELL) or "", low)
end

-- The area label's Name changed. On a continent, when it names one of its
-- zones: that zone's range and fishing skill. On a zone map, whatever area
-- it names: the zone's fishing skill. Both off, Apply has hidden the text.
local function OnLabelName(_, name)
    local levels, fishing = F.Enabled(), F.Get("fishing")
    if not (levels or fishing) then return end
    local zone, onContinent
    if name and name ~= "" then
        local mapID = WorldMapFrame:GetMapID()
        local info = mapID and C_Map.GetMapInfo(mapID)
        if info and info.mapType == Enum.UIMapType.Continent then
            zone, onContinent = byName[name], true
        elseif info and info.mapType == Enum.UIMapType.Zone then
            zone = mapID
        end
    end
    local lv = levels and onContinent and zone and LEVELS[zone]
    local base = fishing and zone and FISHING[zone]
    if not (lv or base) then
        text:Hide()
        fishText:Hide()
        return
    end
    text:SetShown(lv and true or false)
    if lv then text:SetText(LevelsText(lv)) end
    fishText:SetShown(base and true or false)
    if base then
        fishText:SetText(FishingText(base))
        fishText:ClearAllPoints()
        if lv then
            fishText:SetPoint("TOP", text, "BOTTOM", 0, -2)
        else
            fishText:SetPoint("TOP", areaName, "BOTTOM", 0, -6)
        end
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
    for _, list in ipairs({ LEVELS, FISHING }) do
        for id in pairs(list) do
            local info = C_Map.GetMapInfo(id)
            if info and info.name then byName[info.name] = id end
        end
    end
    local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
    holder:SetAllPoints()
    holder:SetFrameStrata("HIGH")
    areaName = label.Name
    text = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    fishText = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    -- Smaller than the zone name they sit under, the fishing skill much smaller.
    local font, size, flags = areaName:GetFont()
    if font and size then
        text:SetFont(font, math.floor(size * 0.7 + 0.5), flags)
        fishText:SetFont(font, math.max(9, math.floor(size * 0.4 + 0.5)), flags)
    end
    text:SetPoint("TOP", areaName, "BOTTOM", 0, -6)
    text:Hide()
    fishText:Hide()
    hooksecurefunc(label.Name, "SetText", OnLabelName)
end

-- Nothing exists until a setting is first on; both off, the text hides and
-- the hook returns at once. The world map loads on demand, so building may wait.
local function Apply()
    local any = F.Enabled() or F.Get("fishing")
    if hooked then
        if not any then
            text:Hide()
            fishText:Hide()
        end
        return
    end
    if not any then
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
