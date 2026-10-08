if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_QuestMark.lua  (WoW Forever only)
--  Marks quests that are not from the original game with a small blue
--  infinity in the quest log. Original game quest IDs all sit below 10000;
--  anything above was added later (Forever, Season of Discovery, ...).
--
--  The marks are textures of our own, kept in a weak table (never keys on
--  Blizzard frames). The pass is deferred out of Blizzard's
--  QuestLogQuests_Update, and that hook only exists once the feature is on.
-------------------------------------------------------------------------------
local _, module = ...

local FIRST_NON_CLASSIC_ID = 10000
local ATLAS = "perks-infinity"
local R, G, B = 0.30, 0.65, 1.00

-- Settings live in EllesmereUIDB.questMark; unset keys read these.
local F = module.Feature("questMark", { enabled = false })

local marks = setmetatable({}, { __mode = "k" })
local hooked, pending = false, false

-- Title buttons come from a pool. Blizzard's POI icon fills the left margin
-- and the title runs up to the track checkbox, so the mark sits under that
-- checkbox, beside the first objective line.
local function MarkQuestLog()
    pending = false
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool then return end
    local on = F.Enabled()
    for button in pool:EnumerateActive() do
        local mark = marks[button]
        local id = button.questID
        if on and button.Checkbox and type(id) == "number" and id >= FIRST_NON_CLASSIC_ID then
            if not mark then
                mark = button:CreateTexture(nil, "OVERLAY")
                mark:SetSize(18, 10)
                mark:SetAtlas(ATLAS)
                mark:SetVertexColor(R, G, B)
                mark:SetPoint("TOP", button.Checkbox, "BOTTOM", 0, -2)
                marks[button] = mark
            end
            mark:Show()
        elseif mark then
            mark:Hide()
        end
    end
end

local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, MarkQuestLog)
end

-- Login and the options toggle: hooks the quest log the first time the
-- feature is on, then refreshes the marks (hides them once it is off).
local function Apply()
    if not hooked and F.Enabled() and QuestLogQuests_Update then
        hooked = true
        hooksecurefunc("QuestLogQuests_Update", Queue)
    end
    if hooked then Queue() end
end

-- Options-page entry points.
EllesmereUI._QuestMark = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
