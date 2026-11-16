if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_QuestMarks.lua  (WoW Forever only)
--  Mark Non-Classic Quests: a small blue infinity on quests that are not
--  from the original game, in the places the player picks: at quest givers
--  (their gossip and greeting lists, and the quest text before accepting),
--  in the quest log, and on the Custom Quest Tracker's rows. A quest is
--  original when its ID is in the original game's list
--  (EllesmereUIForeverEssentials_QuestMarksData.lua); any other is marked,
--  whatever its ID.
--
--  Marks are textures on frames of our own, kept in weak tables keyed by the
--  button they sit on; nothing of Blizzard's is written. The gossip list's
--  callback and the tracker's row hook are there only while their choice is
--  on. The greeting list, the quest text and the quest log keep the hooks
--  they get the first time their choice is on (hooks cannot be removed):
--  each returns at once while its choice is off, and turning a choice off
--  hides its marks once.
-------------------------------------------------------------------------------
local _, module = ...

local ATLAS = "perks-infinity"
local R, G, B = 0.30, 0.65, 1.00

-- Settings live in EllesmereUIDB.questMarks; unset keys read these.
local F = module.Feature("questMarks", { givers = false, log = false, tracker = false })

-- id is in list, sorted first, last ID pairs.
local function InList(list, id)
    local lo, hi = 1, #list / 2
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if id < list[mid * 2 - 1] then
            hi = mid - 1
        elseif id > list[mid * 2] then
            lo = mid + 1
        else
            return true
        end
    end
    return false
end

local function NewMark(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(18, 10)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetAtlas(ATLAS)
    t:SetVertexColor(R, G, B)
    return f
end

-- A marker for the IDs missing from original: Mark(store, host, on, id,
-- place, ...) shows host's mark when id is marked here, else hides it;
-- place(mark, ...) anchors a shown one.
local function Marker(original)
    return function(store, host, on, id, place, ...)
        local mark = store[host]
        if on and type(id) == "number" and id > 0 and not InList(original, id) then
            if not mark then
                mark = NewMark(host)
                store[host] = mark
            end
            place(mark, ...)
            mark:Show()
        elseif mark then
            mark:Hide()
        end
    end
end
local Mark = Marker(module.ORIGINAL_QUESTS)

local function HideAll(store)
    for _, mark in pairs(store) do mark:Hide() end
end

-- Right after the first line of a title.
local function AfterText(mark, fs)
    mark:ClearAllPoints()
    mark:SetPoint("LEFT", fs, "TOPLEFT", math.min(fs:GetUnboundedStringWidth(), fs:GetWidth()) + 3,
        -fs:GetLineHeight() / 2)
end

-- Shared with Mark Non-Classic Recipes (EllesmereUIForeverEssentials_RecipeMarks.lua).
module.ClassicMarks = {
    ATLAS = ATLAS, R = R, G = G, B = B,
    InList = InList, Marker = Marker, HideAll = HideAll, AfterText = AfterText,
}

-------------------------------------------------------------------------------
--  Quest givers: the gossip list, the greeting list, the quest text
-------------------------------------------------------------------------------
local gossipMarks = setmetatable({}, { __mode = "k" })
local function MarkGossipButton(button, elementData)
    local kind = elementData and elementData.buttonType
    local id = (kind == GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST or kind == GOSSIP_BUTTON_TYPE_ACTIVE_QUEST)
        and elementData.info and elementData.info.questID
    -- The list holds other frames too (the greeting text is no button): only
    -- quest buttons are marked, and a reused button loses its mark.
    if not id then
        local mark = gossipMarks[button]
        if mark then mark:Hide() end
        return
    end
    Mark(gossipMarks, button, F.Get("givers"), id, AfterText, button:GetFontString())
end

local greetingMarks = setmetatable({}, { __mode = "k" })
local function MarkGreeting()
    if not F.Get("givers") then return end
    for button in QuestFrameGreetingPanel.titleButtonPool:EnumerateActive() do
        local id
        if button.isActive == 1 then
            id = GetActiveQuestID(button:GetID())
        else
            id = select(5, GetAvailableQuestInfo(button:GetID()))
        end
        Mark(greetingMarks, button, true, id, AfterText, button:GetFontString())
    end
end

local detailMarks = {}
local function MarkDetail(isDetail)
    Mark(detailMarks, QuestInfoFrame, isDetail and F.Get("givers"), isDetail and GetQuestID(),
        AfterText, QuestInfoTitleHeader)
end

local function OnGossipFrame(_, button, elementData)
    MarkGossipButton(button, elementData)
end

local giversOn, giversHooked = false, false
local function ApplyGivers()
    local on = F.Get("givers") == true
    if on == giversOn then return end
    giversOn = on
    local box = GossipFrame.GreetingPanel.ScrollBox
    if not on then
        box:UnregisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, gossipMarks)
        HideAll(gossipMarks)
        HideAll(greetingMarks)
        HideAll(detailMarks)
        return
    end
    box:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, OnGossipFrame, gossipMarks)
    if not giversHooked then
        giversHooked = true
        -- The greeting rows are filled by the panel's OnShow, and again by a
        -- direct call on QUEST_LOG_UPDATE while it is shown.
        QuestFrameGreetingPanel:HookScript("OnShow", MarkGreeting)
        hooksecurefunc("QuestFrameGreetingPanel_OnShow", MarkGreeting)
        -- The quest log's details share this display: the mark shows on the
        -- quest giver's text alone.
        hooksecurefunc("QuestInfo_Display", function(template)
            if not F.Get("givers") then return end
            MarkDetail(template == QUEST_TEMPLATE_DETAIL)
        end)
    end
    box:ForEachFrame(MarkGossipButton)
    if QuestFrameGreetingPanel:IsShown() then MarkGreeting() end
    MarkDetail(QuestFrameDetailPanel:IsShown())
end

-------------------------------------------------------------------------------
--  Quest log: under each quest's track checkbox, the title running up to it
--  and the quest's map icon filling the left margin.
-------------------------------------------------------------------------------
local logMarks = setmetatable({}, { __mode = "k" })
local function UnderCheckbox(mark, checkbox)
    mark:ClearAllPoints()
    mark:SetPoint("TOP", checkbox, "BOTTOM", 0, -2)
end
local function MarkLog()
    if not F.Get("log") then return end
    for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
        if button.Checkbox then
            Mark(logMarks, button, true, button.questID, UnderCheckbox, button.Checkbox)
        end
    end
end

-------------------------------------------------------------------------------
--  Custom Quest Tracker (EllesmereUIQuestTracker's public row hook, registered
--  while the choice is on): the mark fills the slot the tracker keeps right of
--  each title.
-------------------------------------------------------------------------------
local trackerMarks = setmetatable({}, { __mode = "k" })
local function InSlot(mark, slot)
    mark:ClearAllPoints()
    mark:SetPoint("LEFT", slot, "LEFT", 0, 0)
end
local function MarkTrackerRow(slot, questID)
    Mark(trackerMarks, slot, F.Get("tracker"), questID, InSlot, slot)
end

-------------------------------------------------------------------------------
--  Apply (login and every options change)
-------------------------------------------------------------------------------
local logOn, logHooked = false, false
local function Apply()
    ApplyGivers()

    local on = F.Get("log") == true
    if on ~= logOn then
        logOn = on
        if on and not logHooked then
            logHooked = true
            hooksecurefunc("QuestLogQuests_Update", MarkLog)
        end
        if on then MarkLog() else HideAll(logMarks) end
    end

    -- The tracker is its own addon: absent while it is turned off.
    if EllesmereUI.RegisterQuestTrackerRow then
        if F.Get("tracker") then
            EllesmereUI.RegisterQuestTrackerRow("EllesmereUIForeverEssentials", MarkTrackerRow, 18)
        else
            EllesmereUI.UnregisterQuestTrackerRow("EllesmereUIForeverEssentials")
        end
    end
end

-- Options-page entry points.
EllesmereUI._QuestMarks = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    HasTracker = function() return EllesmereUI.RegisterQuestTrackerRow ~= nil end,
}

F.Start(Apply)
