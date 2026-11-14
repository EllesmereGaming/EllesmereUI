if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_GatherSkill.lua  (WoW Forever only)
--  Gathering Skill in Tooltips: on a herb or ore node's tooltip, the game's
--  "Requires Herbalism" / "Requires Mining" line gains the skill the node
--  needs ("Requires Mining (75)") and, when you can gather it, the color of
--  your chance to raise your skill there, as recipes show it: orange, yellow,
--  green, grey. The game's red stays when you cannot.
--
--  World object tooltips carry no object ID, so a node is known by its name,
--  in the client's language whatever the options language. A herb node bears
--  its herb's name, read from the herb item, except the few some languages
--  name otherwise (HERB_NODES); those and the ore nodes come from the game
--  names (EllesmereUI.GameName: game data, never reworded; the client
--  language's file comes in with this module's TOC). Required skills: the
--  game's (Classic objects). Nodes WoW Forever added are left as the game
--  shows them until their skill is known.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.gatherSkill; unset keys read these.
local F = module.Feature("gatherSkill", { enabled = false })

local HERBALISM, MINING = 182, 186          -- skill lines
local HERBALISM_SPELL, MINING_SPELL = 2366, 2575

-- Herb item ID = the skill its node needs.
local HERBS = {
    [765] = 1, [2447] = 1, [2449] = 15, [785] = 50, [2450] = 70, [3820] = 85, [2453] = 100,
    [3355] = 115, [3369] = 120, [3356] = 125, [3357] = 150, [3818] = 160, [3821] = 170,
    [3358] = 185, [3819] = 195, [4625] = 205, [8831] = 210, [8836] = 220, [8838] = 230,
    [8839] = 235, [8845] = 245, [8846] = 250, [13464] = 260, [13463] = 270, [13465] = 280,
    [13466] = 285, [13467] = 290, [13468] = 300,
}

-- Ore node name (English; EllesmereUILocales/<code>_GameNames.lua hold the others) = the skill it needs.
local ORES = {
    ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65,
    ["Silver Vein"] = 75, ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75,
    ["Iron Deposit"] = 125, ["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155,
    ["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Ooze Covered Mithril Deposit"] = 175,
    ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230,
    ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
    ["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
}

-- Herb nodes some languages name unlike their herb (English node name = herb
-- item ID); their names come from EllesmereUI.GameName.
local HERB_NODES = {
    ["Silverleaf"] = 765, ["Mageroyal"] = 785, ["Grave Moss"] = 3369, ["Khadgar's Whisker"] = 3358,
    ["Firebloom"] = 4625, ["Purple Lotus"] = 8831, ["Gromsblood"] = 8846,
    ["Mountain Silversage"] = 13465, ["Plaguebloom"] = 13466,
}

-- Localized node name = { skill line, required skill }; built on first use,
-- a herb whose item is not loaded yet added when it loads.
local nodes, hooked
local missing = {}  -- herb item ID = true while its name is not loaded
local events = CreateFrame("Frame")

local function AddHerb(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then return false end
    nodes[name] = { HERBALISM, HERBS[itemID] }
    return true
end

local function Build()
    nodes = {}
    for name, lvl in pairs(ORES) do
        nodes[EllesmereUI.GameName(name)] = { MINING, lvl }
        nodes[name] = { MINING, lvl }
    end
    for name, itemID in pairs(HERB_NODES) do
        nodes[EllesmereUI.GameName(name)] = { HERBALISM, HERBS[itemID] }
    end
    for itemID in pairs(HERBS) do
        if not AddHerb(itemID) then
            missing[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    if next(missing) then events:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
end

events:SetScript("OnEvent", function(self, _, itemID, success)
    if missing[itemID] then
        -- A herb that failed to load stays as the game shows it.
        if success then AddHerb(itemID) end
        missing[itemID] = nil
        if not next(missing) then self:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
    end
end)

-- The player's skill in a gathering skill line, nil without it.
local function Skill(line)
    for _, index in ipairs({ GetProfessions() }) do
        if index then
            local _, _, rank, _, _, _, id = GetProfessionInfo(index)
            if id == line then return rank end
        end
    end
end

-- Recipe colors: orange until 25 over the need, yellow until 50, green until
-- 100, then grey.
local function OddsColor(skill, need)
    local over = skill - need
    if over < 25 then return 1, 0.5, 0.25 end
    if over < 50 then return 1, 1, 0 end
    if over < 100 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

local function OnObjectTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not F.Enabled() then return end
    local lines = data and data.lines
    local title = lines and lines[1] and lines[1].leftText
    if not title or issecretvalue(title) then return end
    if not nodes then Build() end
    local node = nodes[title]
    if not node then return end
    local skillName = C_Spell.GetSpellName(node[1] == MINING and MINING_SPELL or HERBALISM_SPELL)
    if not skillName then return end
    for i = 2, tooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not issecretvalue(text) and text:find(skillName, 1, true) then
            fs:SetText(("%s (%d)"):format(text, node[2]))
            local skill = Skill(node[1])
            if skill and skill >= node[2] then fs:SetTextColor(OddsColor(skill, node[2])) end
            tooltip:Show()
            return
        end
    end
end

-- The tooltip hook goes in the first time the setting is on; off, it returns
-- at once and no event is registered.
local function Apply()
    if not F.Enabled() then
        events:UnregisterAllEvents()
        return
    end
    -- Herbs that loaded while it was off.
    if nodes and next(missing) then
        for itemID in pairs(missing) do
            if AddHerb(itemID) then missing[itemID] = nil end
        end
        if next(missing) then events:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
    end
    if hooked then return end
    hooked = true
    -- Nothing to load where the names came in with the module's TOC.
    EllesmereUI.LoadGameNames()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
end

-- Options-page entry points.
EllesmereUI._GatherSkill = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
