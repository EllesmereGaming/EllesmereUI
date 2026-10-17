if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_GatherSkill.lua  (WoW Forever only)
--  Gathering Skill in Tooltips: on a herb or ore node's tooltip, the game's
--  "Requires Herbalism" / "Requires Mining" line gains the skill the node
--  needs ("Requires Mining (75)") and, when you can gather it, the color of
--  your chance to raise your skill there, as recipes show it: orange, yellow,
--  green, grey. The game's red stays when you cannot.
--  minimap (off by default, in the cog): a tracked node's name on the
--  minimap's mouseover tooltip gains its required skill in that color
--  ("Silverleaf (1)"), red when you cannot gather it.
--
--  World object tooltips carry no object ID, so a node is known by its name:
--  a herb node bears its herb's name, read from the herb item in the client's
--  language; an ore node's name comes from the locale files (the game's own
--  names in each language, read through EllesmereUI.L: game data, so never
--  reworded). Required skills: the game's (Classic objects). Nodes WoW
--  Forever added are left as the game shows them until their skill is known.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.gatherSkill; unset keys read these.
local F = module.Feature("gatherSkill", { enabled = false, minimap = false })

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

-- Ore node name (English; the locale files hold the others) = the skill it needs.
local ORES = {
    ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65,
    ["Silver Vein"] = 75, ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75,
    ["Iron Deposit"] = 125, ["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155,
    ["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175, ["Ooze Covered Mithril Deposit"] = 175,
    ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230,
    ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
    ["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
}

-- Localized node name = { skill line, required skill }; built on first use,
-- a herb whose item is not loaded yet added when it loads.
local nodes, hooked
local missing = {}  -- herb item ID = true while its name is not loaded
local events = CreateFrame("Frame")

-- The minimap's mouseover tooltip is set again every frame the cursor is over
-- the minimap: each line's rewrite is remembered by its text (false: left as
-- is), forgotten when a skill, a herb name or the setting changes.
local memo, memoN, MEMO_MAX = {}, 0, 500
local function Forget()
    wipe(memo)
    memoN = 0
end

local function AddHerb(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then return false end
    nodes[name] = { HERBALISM, HERBS[itemID] }
    return true
end

local function Build()
    nodes = {}
    for name, lvl in pairs(ORES) do
        nodes[EllesmereUI.L(name)] = { MINING, lvl }
        nodes[name] = { MINING, lvl }
    end
    for itemID in pairs(HERBS) do
        if not AddHerb(itemID) then
            missing[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    if next(missing) then events:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
end

events:SetScript("OnEvent", function(self, event, itemID, success)
    if event == "SKILL_LINES_CHANGED" then
        Forget()
    elseif missing[itemID] then
        -- A herb that failed to load stays as the game shows it.
        if success then AddHerb(itemID) end
        missing[itemID] = nil
        Forget()
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

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- A minimap tooltip line rewritten: one name per line inside it (several
-- nodes under the cursor stack up), each known node's name followed by its
-- required skill. false when no name is known.
local function MinimapLine(text)
    local out, changed = {}, false
    for part in (text .. "\n"):gmatch("(.-)\n") do
        local name = part:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        local node = nodes[name]
        if node then
            local skill = Skill(node[1])
            local color = (skill and skill >= node[2]) and Hex(OddsColor(skill, node[2])) or "|cffff2020"
            part = ("%s %s(%d)|r"):format(part, color, node[2])
            changed = true
        end
        out[#out + 1] = part
    end
    return changed and table.concat(out, "\n")
end

local function OnMinimapTooltip(tooltip)
    if tooltip ~= GameTooltip or not (F.Enabled() and F.Get("minimap")) then return end
    if not nodes then Build() end
    local changed
    for i = 1, tooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not issecretvalue(text) then
            local new = memo[text]
            if new == nil then
                new = MinimapLine(text)
                if memoN >= MEMO_MAX then Forget() end
                memo[text] = new
                memoN = memoN + 1
            end
            if new then
                fs:SetText(new)
                changed = true
            end
        end
    end
    if changed then tooltip:Show() end
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
    Forget()
    if not F.Enabled() then
        events:UnregisterAllEvents()
        return
    end
    if F.Get("minimap") then
        events:RegisterEvent("SKILL_LINES_CHANGED")
    else
        events:UnregisterEvent("SKILL_LINES_CHANGED")
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
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.MinimapMouseover, OnMinimapTooltip)
end

-- Options-page entry points.
EllesmereUI._GatherSkill = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
