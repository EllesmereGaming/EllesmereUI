if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_RecipeMarks.lua  (WoW Forever only)
--  Mark Non-Classic Recipes: the blue infinity of Mark Non-Classic Quests on
--  recipes that are not from the original game, in the places the player
--  picks: the profession window's recipe list, a profession trainer's list,
--  and the tooltip of a recipe item. A recipe is original when its spell (its
--  item, for the tooltip) is in the original game's lists
--  (EllesmereUIForeverEssentials_RecipeMarksData.lua); any other is marked.
--
--  Marks are frames of our own kept in weak tables keyed by the row they sit
--  on; nothing of Blizzard's is written. Each list's callback is there only
--  while its choice is on, and turning a choice off hides its marks once. The
--  tooltip hook, set the first time its choice is on (hooks cannot be
--  removed), returns at once while it is off.
-------------------------------------------------------------------------------
local _, module = ...

local CM = module.ClassicMarks
local Mark = CM.Marker(module.ORIGINAL_RECIPES)
local ORIGINAL_ITEMS = module.ORIGINAL_RECIPE_ITEMS
local INITIALIZED = ScrollBoxListMixin.Event.OnInitializedFrame

-- Settings live in EllesmereUIDB.recipeMarks; unset keys read these.
local F = module.Feature("recipeMarks", { window = false, trainer = false, tooltip = false })

local function Unmark(store, row)
    local mark = store[row]
    if mark then mark:Hide() end
end

-------------------------------------------------------------------------------
--  Profession window: after the recipe's name and its craftable count
-------------------------------------------------------------------------------
local windowMarks = setmetatable({}, { __mode = "k" })
local function MarkRecipeRow(row, elementData)
    -- Both lists are trees: a row's element data is a node holding its data.
    local info = elementData:GetData().recipeInfo
    -- The list also holds categories and dividers: only recipe rows are marked.
    if not info then return Unmark(windowMarks, row) end
    Mark(windowMarks, row, true, info.recipeID, CM.AfterText,
        row.Count:IsShown() and row.Count or row.Label)
end

local function WindowBox()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    return page and page.RecipeList and page.RecipeList.ScrollBox
end

-- On this event (a talent change) Blizzard redraws the rows' craftable counts
-- alone, without initializing them again: the marks follow on the next frame.
local COUNTS_REFRESHED = "ProfessionsRecipeListMixin.Event.RefreshCraftableCount"
local function OnCountsRefreshed()
    C_Timer.After(0, function()
        local box = WindowBox()
        if box and F.Get("window") then box:ForEachFrame(MarkRecipeRow) end
    end)
end
local function WatchCounts(on)
    if on then
        EventRegistry:RegisterCallback(COUNTS_REFRESHED, OnCountsRefreshed, windowMarks)
    else
        EventRegistry:UnregisterCallback(COUNTS_REFRESHED, windowMarks)
    end
end

-------------------------------------------------------------------------------
--  Profession trainer: on the corner of the service's icon
-------------------------------------------------------------------------------
local trainerMarks = setmetatable({}, { __mode = "k" })
local function OnIcon(mark, icon)
    mark:ClearAllPoints()
    mark:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 4, 3)
end

local function MarkTrainerRow(button, elementData)
    local index = elementData:GetData().skillIndex
    -- Class trainers teach no recipes; categories have no service.
    local info = index and IsTradeskillTrainer() and C_TooltipInfo.GetTrainerService(index)
    if not (info and info.id) then return Unmark(trainerMarks, button) end
    Mark(trainerMarks, button, true, info.id, OnIcon, button.icon)
end

local function TrainerBox()
    return ClassTrainerFrame and ClassTrainerFrame.ScrollBox
end

-------------------------------------------------------------------------------
--  Recipe items: a line on the tooltip
-------------------------------------------------------------------------------
local tipHooked = false
local tipMark

local function OnItemTooltip(tooltip, data)
    if not F.Get("tooltip") or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    local id = data and data.id
    if type(id) ~= "number" or select(6, C_Item.GetItemInfoInstant(id)) ~= Enum.ItemClass.Recipe
        or CM.InList(ORIGINAL_ITEMS, id) then
        return
    end
    tipMark = tipMark or CreateAtlasMarkup(CM.ATLAS, 18, 10, 0, 0,
        math.floor(CM.R * 255), math.floor(CM.G * 255), math.floor(CM.B * 255))
    tooltip:AddLine(tipMark .. " " .. EllesmereUI.L("Non-Classic Recipe"), CM.R, CM.G, CM.B)
end

-------------------------------------------------------------------------------
--  Apply (login and every options change)
-------------------------------------------------------------------------------
local LISTS = {
    { key = "window", addon = "Blizzard_Professions", box = WindowBox, mark = MarkRecipeRow,
      store = windowMarks, watched = false, onWatch = WatchCounts },
    { key = "trainer", addon = "Blizzard_TrainerUI", box = TrainerBox, mark = MarkTrainerRow,
      store = trainerMarks, watched = false },
}
for _, list in ipairs(LISTS) do
    -- A callback with an owner gets the owner first.
    list.onFrame = function(_, row, elementData) list.mark(row, elementData) end
end

local Apply
local function ApplyList(list)
    local on = F.Get(list.key) == true
    if on == list.watched then return end
    local box = list.box()
    if not box then
        -- The list's addon loads with its first window: applied again then.
        if on and not list.waiting and not C_AddOns.IsAddOnLoaded(list.addon) then
            list.waiting = true
            EventUtil.ContinueOnAddOnLoaded(list.addon, function()
                list.waiting = nil
                Apply()
            end)
        end
        return
    end
    list.watched = on
    if on then
        box:RegisterCallback(INITIALIZED, list.onFrame, list.store)
        box:ForEachFrame(list.mark)
    else
        box:UnregisterCallback(INITIALIZED, list.store)
        CM.HideAll(list.store)
    end
    if list.onWatch then list.onWatch(on) end
end

Apply = function()
    for _, list in ipairs(LISTS) do ApplyList(list) end
    if F.Get("tooltip") and not tipHooked then
        tipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    end
end

-- Options-page entry points.
EllesmereUI._RecipeMarks = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
