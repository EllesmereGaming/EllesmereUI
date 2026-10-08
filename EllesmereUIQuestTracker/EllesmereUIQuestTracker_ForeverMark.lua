-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_ForeverMark.lua  (WoW Forever only)
--
-- Marks quests that are not from the original game with a small blue
-- infinity, in the tracker (from the skin pass) and in the quest log.
-- Original game quest IDs all sit below 10000; anything above was added
-- later (Forever, Season of Discovery, ...).
--
-- The marks are textures of our own, kept in weak tables (never keys on
-- Blizzard frames). The quest log pass is deferred out of Blizzard's
-- QuestLogQuests_Update, and its hook only exists once that setting is on.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local FIRST_NON_CLASSIC_ID = 10000
local ATLAS = "perks-infinity"
local R, G, B = 0.30, 0.65, 1.00

local function TrackerOn() return EQT.Cfg("markNonClassicTracker") == true end
local function LogOn()     return EQT.Cfg("markNonClassicLog") == true end

local function IsNonClassic(questID)
    return type(questID) == "number" and questID >= FIRST_NON_CLASSIC_ID
end

local function NewMark(parent, w, h)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(w, h)
    t:SetVertexColor(R, G, B)
    return t
end

-------------------------------------------------------------------------------
-- Tracker: called by SkinBlock after its texture strip, for quest blocks only
-- (isQuest), so only under the EllesmereUI tracker style. Left of the title,
-- unless Blizzard's quest icons take that margin (native, reload-gated): then
-- on the right edge, the slot of the skin's own type icon, which native mode
-- hides, and only while no item or group finder button is there (rightBusy).
-------------------------------------------------------------------------------
local _trackerMarks = setmetatable({}, { __mode = "k" })

function EQT.ApplyForeverMark(block, titleFS, isQuest, native, rightBusy)
    local mark = _trackerMarks[block]
    if not (isQuest and titleFS and TrackerOn() and IsNonClassic(block.id))
       or (native and rightBusy) then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = NewMark(block, 16, 9)
        if native then
            mark:SetPoint("TOPRIGHT", block, "TOPRIGHT", -2, -1)
        else
            mark:SetPoint("RIGHT", titleFS, "LEFT", -2, 0)
        end
        _trackerMarks[block] = mark
    end
    -- The skin's full pass blanks every block texture but its own icon.
    if mark:GetAtlas() ~= ATLAS then mark:SetAtlas(ATLAS) end
    mark:Show()
end

-------------------------------------------------------------------------------
-- Quest log: title buttons come from a pool. Blizzard's POI icon fills the
-- left margin and the title runs up to the track checkbox, so the mark sits
-- under that checkbox, beside the first objective line.
-------------------------------------------------------------------------------
local _logMarks = setmetatable({}, { __mode = "k" })
local _logHooked, _logPending = false, false

local function MarkQuestLog()
    _logPending = false
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool then return end
    local on = LogOn()
    for button in pool:EnumerateActive() do
        local mark = _logMarks[button]
        if on and button.Checkbox and IsNonClassic(button.questID) then
            if not mark then
                mark = NewMark(button, 18, 10)
                mark:SetAtlas(ATLAS)
                mark:SetPoint("TOP", button.Checkbox, "BOTTOM", 0, -2)
                _logMarks[button] = mark
            end
            mark:Show()
        elseif mark then
            mark:Hide()
        end
    end
end

local function QueueQuestLog()
    if _logPending then return end
    _logPending = true
    C_Timer.After(0, MarkQuestLog)
end

-- The quest log hook only exists once its setting has been on.
local function HookQuestLog()
    if _logHooked or not LogOn() or not QuestLogQuests_Update then return end
    _logHooked = true
    hooksecurefunc("QuestLogQuests_Update", QueueQuestLog)
end

-- Login, from EQT.InitSkin (the tracker blocks are marked by the skin pass).
function EQT.InitForeverMarks()
    HookQuestLog()
end

-- Settings toggles: refresh both views.
function EQT.ApplyForeverMarks()
    HookQuestLog()
    if _logHooked then QueueQuestLog() end
    if EQT.RestyleAll then EQT.RestyleAll() end
end
