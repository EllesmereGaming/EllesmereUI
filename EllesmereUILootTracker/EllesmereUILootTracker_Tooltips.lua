local ADDON_NAME, ns = ...

local hookedTooltips = setmetatable({}, { __mode = "k" })
local tooltipGoalItems = setmetatable({}, { __mode = "k" })

local function ItemIDFromData(data)
    if not data then return end
    local itemID, hyperlink = data.id, data.hyperlink
    if issecretvalue and issecretvalue(itemID) then itemID = nil end
    if issecretvalue and issecretvalue(hyperlink) then hyperlink = nil end
    if itemID then return tonumber(itemID) end
    if hyperlink then
        local resolved = C_Item.GetItemInfoInstant(hyperlink)
        if issecretvalue and issecretvalue(resolved) then return end
        return resolved
    end
end

local function AddGoalLine(tooltip, data)
    if not ns.GetProfile().showItemTooltips then return end
    local itemID = ItemIDFromData(data)
    if not itemID then return end
    if not hookedTooltips[tooltip] then
        hookedTooltips[tooltip] = true
        tooltip:HookScript("OnTooltipCleared", function(self) tooltipGoalItems[self] = nil end)
    end
    if tooltipGoalItems[tooltip] == itemID then return end
    local goal = ns.GetAnyGoal(itemID)
    if not goal then return end
    tooltipGoalItems[tooltip] = itemID
    local priority = EllesmereUI.L(ns.PRIORITY_NAMES[goal.priority] or "Nice to have")
    local state = goal.state == "archived" and EllesmereUI.L("Obtained") or EllesmereUI.L("Open")
    local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
    tooltip:AddLine(EllesmereUI.Lf("EllesmereUI Loot Tracker: %1$s (%2$s)", priority, state), color[1], color[2], color[3])
    if goal.catalyst then tooltip:AddLine(EllesmereUI.L("Catalyst planned"), 1, 0.7, 0.28) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddGoalLine)
end

-------------------------------------------------------------------------------
-- Wishlist markers on equipped and bag item icons
-------------------------------------------------------------------------------
local markers = setmetatable({}, { __mode = "k" })
local observedRoots = setmetatable({}, { __mode = "k" })
local markerRefreshQueued
local QueueMarkerRefresh
local activeGoalLookup = {}

local CHARACTER_SLOTS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot",
    "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
    "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot",
}

local function EnsureMarker(button)
    local marker = markers[button]
    if marker then return marker end
    -- Item buttons can be protected. Do not add regions to one for the first
    -- time during combat; the next inventory refresh will finish the setup.
    if InCombatLockdown and InCombatLockdown() then return end

    local bg = button:CreateTexture(nil, "OVERLAY", nil, 6)
    bg:SetSize(15, 15)
    bg:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    bg:SetColorTexture(0.025, 0.03, 0.04, 0.94)

    local glyph = button:CreateFontString(nil, "OVERLAY")
    glyph:SetPoint("CENTER", bg, "CENTER", 0, 0)
    glyph:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    glyph:SetText("W")

    marker = { bg = bg, glyph = glyph }
    markers[button] = marker
    return marker
end

local function SetMarker(button, itemID)
    local marker = markers[button]
    local goal = itemID and activeGoalLookup[itemID]
    if not goal or ns.GetProfile().showWishlistMarkers == false then
        if marker then marker.bg:Hide(); marker.glyph:Hide() end
        return
    end
    marker = marker or EnsureMarker(button)
    if not marker then return end
    local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
    marker.glyph:SetText(goal.catalyst and "C" or "W")
    marker.glyph:SetTextColor(color[1], color[2], color[3], 1)
    marker.bg:Show()
    marker.glyph:Show()
end

local function BagCoordinates(button)
    local bagID
    if button.GetBagID then
        local ok, value = pcall(button.GetBagID, button)
        if ok then bagID = value end
    end
    if bagID == nil then
        local parent = button:GetParent()
        if parent and parent.GetID then bagID = parent:GetID() end
    end
    local slotID = button.GetID and button:GetID()
    return tonumber(bagID), tonumber(slotID)
end

local function ScanBagButtons(root)
    if not root then return end
    local stack, seen = { root }, {}
    while #stack > 0 do
        local frame = table.remove(stack)
        if not seen[frame] then
            seen[frame] = true
            if frame ~= root and frame.GetObjectType then
                local objectType = frame:GetObjectType()
                if objectType == "Button" or objectType == "ItemButton" then
                    local bagID, slotID = BagCoordinates(frame)
                    if bagID and slotID and slotID > 0 then
                        local itemID = C_Container.GetContainerItemID(bagID, slotID)
                        if itemID or markers[frame] then SetMarker(frame, itemID) end
                    end
                end
            end
            if frame.GetChildren then
                local children = { frame:GetChildren() }
                for index = 1, #children do stack[#stack + 1] = children[index] end
            end
        end
    end
end

local function RefreshCharacterMarkers()
    for _, name in ipairs(CHARACTER_SLOTS) do
        local button = _G[name]
        if button then SetMarker(button, GetInventoryItemID("player", button:GetID())) end
    end
end

local function RefreshMarkersNow()
    markerRefreshQueued = nil
    activeGoalLookup = ns.GetGoalLookup()
    RefreshCharacterMarkers()
    local function ScanRoot(root)
        if not root then return end
        if not observedRoots[root] then
            observedRoots[root] = true
            root:HookScript("OnShow", QueueMarkerRefresh)
        end
        if root:IsVisible() then ScanBagButtons(root) end
    end
    ScanRoot(_G.ContainerFrameCombinedBags)
    for index = 1, (NUM_CONTAINER_FRAMES or 13) do
        ScanRoot(_G["ContainerFrame" .. index])
    end
    ScanRoot(_G.EUI_Bags)
    ScanRoot(_G.EUI_BagsReagent)
    ScanRoot(_G.EUI_BankFrame)
end

QueueMarkerRefresh = function()
    if markerRefreshQueued then return end
    markerRefreshQueued = true
    C_Timer.After(0, RefreshMarkersNow)
end

ns.RefreshWishlistMarkers = QueueMarkerRefresh
ns.RegisterCallback(function(reason)
    if reason == "goal" or reason == "spec" then QueueMarkerRefresh() end
end)

local markerEvents = CreateFrame("Frame")
markerEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
markerEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
markerEvents:RegisterEvent("BAG_UPDATE_DELAYED")
markerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
markerEvents:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
markerEvents:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
markerEvents:RegisterEvent("ADDON_LOADED")
markerEvents:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED"
        and addonName ~= "Blizzard_ContainerUI"
        and addonName ~= "Blizzard_CharacterUI"
        and addonName ~= "EllesmereUIBags" then return end
    QueueMarkerRefresh()
end)

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
