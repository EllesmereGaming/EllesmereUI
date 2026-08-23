if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...

local function ItemIDFromData(data)
    if not data then return end
    if data.id then return tonumber(data.id) end
    if data.hyperlink then return C_Item.GetItemInfoInstant(data.hyperlink) end
end

local function AddGoalLine(tooltip, data)
    if not ns.GetProfile().showItemTooltips then return end
    local itemID = ItemIDFromData(data)
    if not itemID then return end
    if not tooltip._eultClearHook then
        tooltip._eultClearHook = true
        tooltip:HookScript("OnTooltipCleared", function(self) self._eultGoalItemID = nil end)
    end
    if tooltip._eultGoalItemID == itemID then return end
    local goal = ns.GetAnyGoal(itemID)
    if not goal then return end
    tooltip._eultGoalItemID = itemID
    local priority = EllesmereUI.L(ns.PRIORITY_NAMES[goal.priority] or "Nice to have")
    local state = goal.state == "archived" and EllesmereUI.L("Obtained") or EllesmereUI.L("Open")
    local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
    tooltip:AddLine(EllesmereUI.Lf("EllesmereUI Loot Tracker: %1$s (%2$s)", priority, state), color[1], color[2], color[3])
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddGoalLine)
end

local function FindJournalSource(itemID)
    local journal = _G.EncounterJournal
    if not journal then return end
    local instanceID = journal.instanceID
    local encounterID = journal.encounterID
    local specID = ns.ResolveSpecID()
    local difficultyID = EJ_GetDifficulty and EJ_GetDifficulty() or 16

    for _, source in ipairs(ns.GetSources("raid")) do
        if source.journalInstanceID == instanceID
            and (not encounterID or source.journalEncounterID == encounterID) then
            for _, item in ipairs(ns.GetCatalog(source, specID, difficultyID)) do
                if item.itemID == itemID then return source, item, difficultyID end
            end
        end
    end
    for _, source in ipairs(ns.GetSources("dungeon")) do
        if source.journalInstanceID == instanceID then
            for _, item in ipairs(ns.GetCatalog(source, specID)) do
                if item.itemID == itemID then return source, item end
            end
        end
    end
end

local hookedJournal
local function HookEncounterJournal()
    if hookedJournal or type(_G.EncounterJournal_Loot_OnClick) ~= "function" then return end
    hookedJournal = true
    hooksecurefunc("EncounterJournal_Loot_OnClick", function(button)
        if not IsAltKeyDown() then return end
        local itemID = button and (button.itemID or button.id)
        if not itemID and button and button.link then itemID = C_Item.GetItemInfoInstant(button.link) end
        if not itemID then return end
        local source, item, difficultyID = FindJournalSource(itemID)
        if not source then return end
        local targetLevel = source.kind == "raid"
            and ns.GetRaidTargetLevel(source, ns.ResolveSpecID(), difficultyID, itemID)
            or ns.GetMPlusTargetLevel(ns.GetProfile().selectedKeyLevel)
        ns.CycleGoal(source, item, nil, difficultyID, targetLevel)
        if GameTooltip and GameTooltip:IsShown() then GameTooltip:Hide() end
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_EncounterJournal" then HookEncounterJournal() end
end)
if C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then HookEncounterJournal() end
