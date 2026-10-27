if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Forever.lua
--
-- WoW Forever only: quest sorting, filtering and zone auto-track (behind the
-- Experimental Quest Tools switch), objective progress colors, completion
-- sounds and party progress announcements. Nothing here exists on retail:
-- the file returns above, and the loader, the skin and the options reach it
-- only through EQT fields that are nil there.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT
local function Cfg(k) return EQT.Cfg(k) end

-- Progress color stops: the defaults below, the paint fallbacks and the
-- options swatches all read this one table.
local OBJ_STOPS = {
    Start = { 1.0, 0.4, 0.4 },
    Mid   = { 1.0, 1.0, 0.4 },
    End   = { 0.4, 1.0, 0.4 },
}
EQT.OBJ_STOPS = OBJ_STOPS

-- Defaults, merged into the module's table before its DB is made at login.
do
    local qt = ns.QT_DEFAULTS.profile.questTracker
    -- Unlocks sorting, filtering and auto-track (experimental).
    qt.questWatchExperimental = false
    -- Sorting: Quest Log Order unless another mode is picked; "mixed" keeps
    -- completed quests where the mode puts them.
    qt.questSortMode      = "log"
    qt.questSortCompleted = "mixed"
    qt.questSortThenBy    = "none"
    -- Filters: untrack matching quests, re-track when they pass. The
    -- Filter Quests switch gates the per-filter choices.
    qt.filterEnabled      = false
    qt.filterZone         = true
    qt.filterCompleted    = false
    qt.filterTrivial      = false
    qt.filterRepeatable   = false
    qt.filterHeaderToggle = false
    -- Tracks quests listed under the current zone or dungeon.
    qt.autoTrackZone      = false
    -- Progress feedback: alert sound keys ("none" = off), party chat.
    qt.soundObjective     = "none"
    qt.soundQuest         = "none"
    qt.announceProgress   = false
    -- Objective line colors (EllesmereUI style only).
    qt.objProgressColor   = false
    qt.objDimCompleted    = false
    qt.objDimAlpha        = 45
    for name, c in pairs(OBJ_STOPS) do
        qt["obj" .. name .. "R"], qt["obj" .. name .. "G"], qt["obj" .. name .. "B"] = c[1], c[2], c[3]
    end
end

-------------------------------------------------------------------------------
-- Gamepad interface style: Blizzard's SmartNavigation drives the tracker from
-- secure code, so watch list edits (whose synchronous handlers rewrite its
-- navigation and can empty a list under D-pad focus) and the recolors in the
-- block hover hook stand down. Decided once logged in; a later style switch
-- stands the tools down too and asks for a reload, once.
-------------------------------------------------------------------------------
local standDown, styleAsked
local function StandDown()
    if standDown == nil then standDown = EllesmereUI.PadGamepadUI() end
    return standDown
end
EQT.QuestToolsStandDown = StandDown

-------------------------------------------------------------------------------
-- Quest sorting, filtering and zone auto-track. The tracker lists watched
-- quests in watch-index order, so editing the watch list sorts and filters
-- it without touching the tracker. Blizzard's zone-change distance sort is
-- switched off while the tools are on (Quest Log Order at least), and turning
-- them off puts the watch list back in quest log order once. Frame is built
-- on first enable and unregistered while everything is off.
-------------------------------------------------------------------------------
local watchFrame
local watchPending = false
local sortStuck = false     -- last rebuild did not take; see ApplySort
local restoreOrder = false  -- the tools turned off: the next pass sorts by quest log
local sortWasOn = false
local logUpdatePending = false
local instancePass = false  -- one pass on entering a dungeon; see CanEditWatches
local selfEdit = false      -- inside our own watch edit: its events are ours
local sortIDs, sortGroup, sortKey, sortKey2, sortRank = {}, {}, {}, {}, {}
local watched = {}
local updated, completeSeen = {}, {}  -- QUEST_WATCH_UPDATE probe

-- The pass's quest log snapshot: one GetInfo per entry per pass.
local logList = {}                                           -- every entry, log order
local logInfo, logHeader, logZone, logIndex = {}, {}, {}, {}  -- by questID
local passZone, passInInstance, passInstance

local function Exp() return Cfg("questWatchExperimental") == true and not StandDown() end
-- Quest Log Order is the base mode (a saved "default", the retired Blizzard
-- order mode, reads as it).
local function SortMode()
    local m = Cfg("questSortMode")
    if m == nil or m == "default" then return "log" end
    return m
end
local function SortCompleted() return Cfg("questSortCompleted") or "mixed" end
-- Secondary key; ignored when the primary is already unique per quest.
local function SortThenBy()
    if SortMode() == "log" then return "none" end
    return Cfg("questSortThenBy") or "none"
end
-- The tools keep the watch list sorted while they are on.
local function SortOn() return Exp() end
local function SortUses(key) return SortMode() == key or SortThenBy() == key end

-- A filter counts only while Filter Quests is on.
local function FilterCfg(k) return Exp() and Cfg("filterEnabled") and Cfg(k) end
local function FilterOn()
    return FilterCfg("filterZone") or FilterCfg("filterCompleted") or FilterCfg("filterTrivial")
        or FilterCfg("filterRepeatable")
end
local function AutoOn() return Exp() and Cfg("autoTrackZone") end

-- Per character (watch lists are per character, profiles may be shared), in
-- the account DB: hidden = untracked by a filter, exempt = re-tracked by the
-- player, auto = tracked by zone auto-track, declined = auto-tracked then
-- untracked by the player (left alone until they leave the zone).
local CHAR_SETS = { "hidden", "exempt", "auto", "declined" }
local charDB
local function CharDB()
    if charDB then return charDB end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local all = EllesmereUIDB.questWatchChars
    if type(all) ~= "table" then all = {}; EllesmereUIDB.questWatchChars = all end
    local guid = UnitGUID("player")
    local sv = all[guid]
    if type(sv) ~= "table" then sv = {}; all[guid] = sv end
    for _, k in ipairs(CHAR_SETS) do
        if type(sv[k]) ~= "table" then sv[k] = {} end
    end
    charDB = sv
    return sv
end

-- Leftovers from a feature that was turned off still need undoing. Reads only.
local function HasLeftovers()
    local all = EllesmereUIDB and EllesmereUIDB.questWatchChars
    local sv = type(all) == "table" and all[UnitGUID("player")]
    if type(sv) ~= "table" then return false end
    for _, k in ipairs(CHAR_SETS) do
        if type(sv[k]) == "table" and next(sv[k]) ~= nil then return true end
    end
    return false
end

local function WatchesActive()
    if StandDown() then return false end
    return SortOn() or FilterOn() or AutoOn() or HasLeftovers()
end

local function FillWatched()
    wipe(watched)
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then watched[questID] = true end
    end
end

local function Snapshot()
    wipe(logList); wipe(logInfo); wipe(logHeader); wipe(logZone); wipe(logIndex)
    passZone = GetRealZoneText()
    passInInstance = IsInInstance()
    passInstance = passInInstance and GetInstanceInfo() or nil
    local title, headerIdx = nil, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            logList[#logList + 1] = info
            if info.isHeader then
                title, headerIdx = info.title, i
            elseif info.questID then
                local questID = info.questID
                logInfo[questID], logHeader[questID] = info, title
                logZone[questID], logIndex[questID] = headerIdx, i
            end
        end
    end
end

-- "Current area": the quest log header names the zone the player is in, or
-- the instance (exact names: a city is its own zone, so Orgrimmar is not
-- Durotar). Quests under a class or profession header name no zone, so in
-- the open world a quest whose objectives are on the current map counts too;
-- inside an instance that flag also counts the parent zone's quests, so only
-- the header decides there.
local function InArea(info, header)
    if header and (header == passZone or (passInInstance and header == passInstance)) then
        return true
    end
    return not passInInstance and info.isOnMap == true
end

local function IsFiltered(questID, superID)
    if questID == superID then return false end
    local info = logInfo[questID]
    if not info then return false end
    if FilterCfg("filterCompleted") and C_QuestLog.IsComplete(questID) then return true end
    if FilterCfg("filterTrivial") and C_QuestLog.IsQuestTrivial(questID) then return true end
    if FilterCfg("filterRepeatable") and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then return true end
    if FilterCfg("filterZone") and not InArea(info, logHeader[questID]) then return true end
    return false
end

-- Our own watch edits: QUEST_WATCH_LIST_CHANGED fires inside the call.
local function AddWatch(questID)
    selfEdit = true
    C_QuestLog.AddQuestWatch(questID)
    selfEdit = false
end
local function RemoveWatch(questID)
    selfEdit = true
    C_QuestLog.RemoveQuestWatch(questID)
    selfEdit = false
end

local function ApplyFilter()
    local db = CharDB()
    local hidden, exempt = db.hidden, db.exempt
    local on = FilterOn()
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    FillWatched()
    -- Exemptions end when the player untracks the quest.
    for questID in pairs(exempt) do
        if not on or not watched[questID] then exempt[questID] = nil end
    end
    for questID in pairs(hidden) do
        -- IsOnQuest, not a log index: collapsed headers and loading screens
        -- hide indexes.
        if not C_QuestLog.IsOnQuest(questID) then
            hidden[questID] = nil
        elseif watched[questID] then
            -- The player tracked it again: leave it tracked.
            hidden[questID] = nil
            if on and IsFiltered(questID, superID) then exempt[questID] = true end
        elseif not on or not IsFiltered(questID, superID) then
            hidden[questID] = nil
            AddWatch(questID)
        end
    end
    if not on then return end
    for questID in pairs(watched) do
        if not exempt[questID] and IsFiltered(questID, superID) then
            hidden[questID] = true
            db.auto[questID] = nil
            RemoveWatch(questID)
        end
    end
end

-- Tracks quests in the current area (see InArea) and untracks them again on
-- leaving.
local function ApplyAutoTrack()
    local db = CharDB()
    local hidden, auto, declined = db.hidden, db.auto, db.declined
    local on = AutoOn()
    if not on and next(auto) == nil and next(declined) == nil then return end
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    FillWatched()
    for questID in pairs(auto) do
        if not watched[questID] then
            auto[questID] = nil
            declined[questID] = true
        end
    end
    local free = Constants.QuestWatchConsts.MAX_QUEST_WATCHES - C_QuestLog.GetNumQuestWatches()
    local header
    for i = 1, #logList do
        local info = logList[i]
        if info.isHeader then
            header = info.title
        elseif not info.isHidden and not info.isTask and not info.isBounty then
            local questID = info.questID
            if on and InArea(info, header) then
                if free > 0 and not watched[questID] and not declined[questID]
                   and not hidden[questID] and not IsFiltered(questID, superID) then
                    auto[questID] = true
                    free = free - 1
                    AddWatch(questID)
                end
            else
                declined[questID] = nil
                if auto[questID] then
                    auto[questID] = nil
                    RemoveWatch(questID)
                end
            end
        end
    end
    -- Quests that left the log.
    for questID in pairs(auto) do
        if not C_QuestLog.IsOnQuest(questID) then auto[questID] = nil end
    end
    for questID in pairs(declined) do
        if not on or not C_QuestLog.IsOnQuest(questID) then declined[questID] = nil end
    end
end

local function CompareQuests(a, b)
    if sortGroup[a] ~= sortGroup[b] then return sortGroup[a] < sortGroup[b] end
    if sortKey[a] ~= sortKey[b] then return sortKey[a] < sortKey[b] end
    if sortKey2[a] ~= sortKey2[b] then return sortKey2[a] < sortKey2[b] end
    return sortRank[a] < sortRank[b]
end

-- Lower sorts first. Recurring = dailies / weeklies.
local QC = Enum.QuestClassification
local TYPE_RANK = {
    [QC.Campaign] = 1, [QC.Legendary] = 2, [QC.Important] = 3, [QC.Meta] = 4,
    [QC.Questline] = 5, [QC.Normal] = 6, [QC.Recurring] = 7,
}

local function SortKeyFor(mode, questID, rank)
    if mode == "zone" then
        return logZone[questID] or 0
    elseif mode == "progress" then
        -- Most complete first: negated share of all objective counts.
        if C_QuestLog.IsComplete(questID) then return -1 end
        local objectives = C_QuestLog.GetQuestObjectives(questID)
        local have, need = 0, 0
        if objectives then
            for _, obj in ipairs(objectives) do
                local req = obj.numRequired
                if type(req) == "number" and req > 0 then
                    have, need = have + math.min(obj.numFulfilled or 0, req), need + req
                end
            end
        end
        return need > 0 and -(have / need) or 0
    elseif mode == "type" then
        local info = logInfo[questID]
        if not info then return 6 end
        local r = TYPE_RANK[info.questClassification] or 6
        if r == 6 and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then r = 7 end
        return r
    elseif mode == "log" then
        return logIndex[questID] or 0
    elseif mode == "level" then
        local info = logInfo[questID]
        return info and (info.difficultyLevel or info.level) or 0
    elseif mode == "name" then
        local info = logInfo[questID]
        return info and info.title and info.title:lower() or ""
    elseif mode == "none" then
        return 0
    end
    return rank
end

-- mode / completed / thenBy: the settings' choices, or the restore pass's
-- plain quest log order.
local function ApplySort(mode, completed, thenBy)
    wipe(sortGroup); wipe(sortKey); wipe(sortKey2); wipe(sortRank)
    local count = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            count = count + 1
            sortIDs[count] = questID
            sortRank[questID] = count
            local group = 1
            if completed ~= "mixed" then
                local done = C_QuestLog.IsComplete(questID) == true
                group = ((completed == "top") == done) and 1 or 2
            end
            sortGroup[questID] = group
            sortKey[questID] = SortKeyFor(mode, questID, count)
            sortKey2[questID] = SortKeyFor(thenBy, questID, count)
        end
    end
    for i = #sortIDs, count + 1, -1 do sortIDs[i] = nil end
    table.sort(sortIDs, CompareQuests)

    -- AddQuestWatch inserts at the top, so re-add the out-of-place head in
    -- reverse; the already-correct tail is left alone.
    local last
    for i = count, 1, -1 do
        if sortRank[sortIDs[i]] ~= i then last = i; break end
    end
    if not last then sortStuck = false; return end
    -- The previous rebuild did not produce its order: skip one pass so an
    -- order the game will not take cannot loop.
    if sortStuck then sortStuck = false; return end

    -- No super-track restore here: setting it from addon code taints the
    -- world map.
    for i = last, 1, -1 do
        RemoveWatch(sortIDs[i])
        AddWatch(sortIDs[i])
    end
    -- Read the order back; the guard only arms when it did not take.
    local n = 0
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            n = n + 1
            if questID ~= sortIDs[n] then sortStuck = true; return end
        end
    end
end

-- Watch list edits fire QUEST_WATCH_LIST_CHANGED synchronously, so Blizzard's
-- tracker, quest log and super-track handlers run under our taint (and the
-- tracker flush they schedule). Under aura restrictions that flush can
-- hard-error in the scenario tracker, so edits happen out of combat and
-- encounters, never with the map open (its quest pin rebuild would run tainted
-- too), and in the open world. The one instance edit is the pass as the player
-- enters a 5-player dungeon (out of combat, from its loading screen), which
-- brings its quests back under Current Zone Only and auto-track; leaving an
-- instance (loading screen + zone events) re-runs the pass.
local function MapOpen() return WorldMapFrame ~= nil and WorldMapFrame:IsShown() end

local function CanEditWatches()
    if IsInInstance() and not instancePass then return false end
    if MapOpen() then return false end
    if InCombatLockdown() then return false end
    if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress() then return false end
    return true
end

local QueueWatches  -- defined below; the map callback needs it
local mapDeferred = false

-- Retry when the map closes. EventRegistry dispatches through
-- securecallfunction, so our callback stays out of the map's chain; it is
-- dropped again once it ran.
local function OnMapHide()
    EventRegistry:UnregisterCallback("WorldMapOnHide", EQT)
    if not mapDeferred then return end
    mapDeferred = false
    QueueWatches()
end

local function ApplyWatches()
    watchPending = false
    selfEdit = false
    -- A pass queued before a style switch stood the tools down.
    if StandDown() then return end
    if not CanEditWatches() then
        instancePass = false
        if MapOpen() and not mapDeferred then
            mapDeferred = true
            EventRegistry:RegisterCallback("WorldMapOnHide", OnMapHide, EQT)
        end
        -- Combat / open-world encounter: retry when it ends. Instances wait
        -- for the zone events on the way out.
        if not IsInInstance() then
            if InCombatLockdown() then ns.CombatQueue.Defer("QuestWatches", QueueWatches) end
            watchFrame:RegisterEvent("ENCOUNTER_END")
        end
        return
    end
    instancePass = false
    watchFrame:UnregisterEvent("ENCOUNTER_END")
    -- Log not loaded yet (loading screens): nothing reliable to act on.
    if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
    Snapshot()
    ApplyFilter()
    ApplyAutoTrack()
    -- The tools were turned off: the watch list goes back to quest log order
    -- once, after the filter and auto-track passes gave back their quests.
    if restoreOrder then
        restoreOrder = false
        ApplySort("log", "mixed", "none")
    end
    if SortOn() then ApplySort(SortMode(), SortCompleted(), SortThenBy()) end
    -- Last pass after everything was turned off: put the frame to sleep.
    if not WatchesActive() then watchFrame:UnregisterAllEvents() end
end

function QueueWatches()
    if watchPending then return end
    watchPending = true
    C_Timer.After(0, ApplyWatches)
end

-- A style switch since login: the tools stand down until a reload.
local function StyleCheck()
    if styleAsked or EllesmereUI.PadGamepadUI() == StandDown() then return end
    styleAsked = true
    standDown = true
    EQT.ApplyQuestWatches()
    -- The Gamepad style's D-pad cannot reach the popup, so chat says it too.
    -- A confirm, not RequestReload: an event cannot reload, its click can.
    EllesmereUI.PrintError(EllesmereUI.L("The interface style changed. Type /reload so the quest tracker matches it."))
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Reload Required"),
        message     = EllesmereUI.L("The interface style changed. Reload so the quest tracker matches it."),
        confirmText = EllesmereUI.L("Reload Now"),
        cancelText  = EllesmereUI.L("Later"),
        reload      = true,
    })
end

-- QUEST_WATCH_UPDATE fires before the log holds the new counts, so the probe
-- waits for the QUEST_LOG_UPDATE that follows it, and a pass runs only when
-- a quest turned complete or back (or Progress sorts the list).
local function OnWatchEvent(_, event, arg1)
    if event == "QUEST_WATCH_LIST_CHANGED" then
        if not selfEdit then QueueWatches() end
    elseif event == "QUEST_WATCH_UPDATE" then
        if arg1 then updated[arg1] = true end
        logUpdatePending = true
    elseif event == "QUEST_LOG_UPDATE" then
        if not logUpdatePending then return end
        logUpdatePending = false
        local need = SortUses("progress")
        for questID in pairs(updated) do
            updated[questID] = nil
            local done = C_QuestLog.IsComplete(questID) == true
            local was = completeSeen[questID]
            completeSeen[questID] = done
            if was ~= done and (was ~= nil or done) then need = true end
        end
        if need then QueueWatches() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local inInstance, kind = IsInInstance()
        instancePass = inInstance and kind == "party"
        QueueWatches()
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- The style is read one frame after the transition event.
        C_Timer.After(0, StyleCheck)
    else
        QueueWatches()
    end
end

-- These two events only drive Blizzard's distance sort on the tracker
-- (ObjectiveTrackerFrameMixin:OnEvent), so while the tools keep the watch
-- list sorted they are off instead of fighting it. Re-registered when the
-- tools are turned off.
local blizzSortOff = false
local BLIZZ_SORT_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }
local function ApplyBlizzardSort()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    local off = SortOn()
    if off == blizzSortOff then return end
    blizzSortOff = off
    for _, event in ipairs(BLIZZ_SORT_EVENTS) do
        if off then otf:UnregisterEvent(event) else otf:RegisterEvent(event) end
    end
end

-- Filter Quests button on the Quests header, left of its minimize button.
-- Built on first enable; the skin tints it and switches its mouse off with
-- the tracker's (EQT.FilterToggle).
local function FilterToggleTip()
    return Cfg("filterEnabled") and "Quest Filters On" or "Quest Filters Off"
end

local function ApplyFilterToggle()
    local want = Exp() and Cfg("filterHeaderToggle") == true
    local btn = EQT.FilterToggle
    if not btn then
        if not want then return end
        local qt = _G.QuestObjectiveTracker
        local header = qt and qt.Header
        local minBtn = header and header.MinimizeButton
        if not minBtn then return end
        btn = CreateFrame("Button", nil, header)
        btn:SetSize(minBtn:GetSize())
        btn:SetPoint("RIGHT", minBtn, "LEFT", -2, 0)
        -- Above the minimize button's header-wide hit rect (SkinHeader).
        btn:SetFrameLevel(minBtn:GetFrameLevel() + 1)
        btn:SetNormalAtlas("ui-questtrackerbutton-filter")
        btn:SetPushedAtlas("ui-questtrackerbutton-filter-pressed")
        btn:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
        btn:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, FilterToggleTip()) end)
        btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        btn:SetScript("OnClick", function(self)
            EQT.Set("filterEnabled", not Cfg("filterEnabled"))
            EQT.ApplyQuestWatches()
            EllesmereUI:RefreshPage()
            EllesmereUI.ShowWidgetTooltip(self, FilterToggleTip())
        end)
        EQT.FilterToggle = btn
        EQT.SkinHeader(header)
        if EQT._trackerMouseOff then EQT.MouseOff(btn) end
    end
    btn:SetShown(want)
    btn:SetAlpha(Cfg("filterEnabled") and 1 or 0.4)
end

-- Options / profile entry point.
function EQT.ApplyQuestWatches()
    ApplyBlizzardSort()
    ApplyFilterToggle()
    -- The tools turned off (or a profile without them): the next pass puts
    -- the watch list back in quest log order.
    local sortOn = SortOn()
    if sortWasOn and not sortOn then restoreOrder = true end
    sortWasOn = sortOn
    if sortOn or StandDown() then restoreOrder = false end
    local on = WatchesActive()
    if not watchFrame then
        if not (on or restoreOrder) then return end
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", OnWatchEvent)
    end
    watchFrame:UnregisterAllEvents()
    sortStuck, logUpdatePending, instancePass = false, false, false
    wipe(updated)
    if not on then
        -- The restore pass puts the frame back to sleep once it ran.
        if restoreOrder then QueueWatches() end
        return
    end
    local zoneModes = FilterCfg("filterZone") or AutoOn()
    watchFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    -- The current area changes on these.
    if zoneModes then
        watchFrame:RegisterEvent("ZONE_CHANGED")
        watchFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    end
    -- Entering or leaving an instance ends on a loading screen.
    if zoneModes then watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD") end
    -- Objective progress can flip a quest to complete.
    if (sortOn and (SortCompleted() ~= "mixed" or SortUses("progress"))) or FilterCfg("filterCompleted") then
        watchFrame:RegisterEvent("QUEST_WATCH_UPDATE")
        watchFrame:RegisterEvent("QUEST_LOG_UPDATE")
    end
    -- Quests turn trivial as the player levels.
    if FilterCfg("filterTrivial") then watchFrame:RegisterEvent("PLAYER_LEVEL_UP") end
    -- New quests are not always auto-watched by Blizzard.
    if AutoOn() then watchFrame:RegisterEvent("QUEST_ACCEPTED") end
    if not (C_EventUtils and C_EventUtils.IsEventValid
            and not C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION")) then
        watchFrame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
    end
    QueueWatches()
end

-------------------------------------------------------------------------------
-- Quest progress: completion sounds and party announcements. Objective
-- counts are cached per quest; QUEST_WATCH_UPDATE marks a quest and the
-- QUEST_LOG_UPDATE after it (when the new counts are readable) compares.
-- Frame is built on first enable and unregistered while both are off.
-------------------------------------------------------------------------------
local progFrame
local progCache = {}   -- questID -> { [objectiveIndex] = numFulfilled, done = bool }
local progDirty = {}
local needSeed = false

-- WC3 peon voice lines shipped with the game client (sound/creature/peon).
-- FileDataIDs, not SoundKit ids, so PlaySoundKey routes them separately.
local PEON_SOUNDS = {
    { "peoncomplete", "Peon: Work Complete", 558132 },
    { "peonready",    "Peon: Ready to Work", 558137 },
    { "peonyes1",     "Peon: Yes 1",         558136 },
    { "peonyes2",     "Peon: Yes 2",         558139 },
    { "peonyes3",     "Peon: Yes 3",         558147 },
    { "peonyes4",     "Peon: Yes 4",         558140 },
    { "peonwhat1",    "Peon: What 1",        558141 },
    { "peonwhat2",    "Peon: What 2",        558134 },
    { "peonwhat3",    "Peon: What 3",        558143 },
    { "peonwhat4",    "Peon: What 4",        558135 },
    { "peonpissed1",  "Peon: Annoyed 1",     558133 },
    { "peonpissed2",  "Peon: Annoyed 2",     558144 },
    { "peonpissed3",  "Peon: Annoyed 3",     558142 },
    { "peonpissed4",  "Peon: Annoyed 4",     558146 },
}
local peonFile = {}

local soundPaths
function EQT.Sounds()
    if not soundPaths then
        local names, order
        soundPaths, names, order = EllesmereUI.BuildAlertSoundTables()
        -- After the bundled sounds, before the media library's "---" block.
        for i, p in ipairs(PEON_SOUNDS) do
            soundPaths[p[1]], names[p[1]], peonFile[p[1]] = p[3], p[2], p[3]
            table.insert(order, #EllesmereUI.ALERT_SOUND_ORDER + i, p[1])
        end
        EllesmereUI.AppendSharedMediaSounds(soundPaths, names, order)
        EQT.SoundNames, EQT.SoundOrder = names, order
    end
    return soundPaths, EQT.SoundNames, EQT.SoundOrder
end

-- Also the options dropdown's preview: the peon lines are FileDataIDs.
local function PlaySoundKey(key)
    if not key or key == "none" then return end
    EllesmereUI.PlaySoundPath(EQT.Sounds()[key], peonFile[key] ~= nil)
end
EQT.PlaySoundKey = PlaySoundKey

local function ProgressOn()
    return (Cfg("soundObjective") or "none") ~= "none"
        or (Cfg("soundQuest") or "none") ~= "none"
        or Cfg("announceProgress")
end

-- Party or instance group only; never raids, never in chat lockdown.
local function Announce(questID, text)
    if not Cfg("announceProgress") or not text or text == "" then return end
    if IsInRaid() then return end
    local chatType
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then chatType = "INSTANCE_CHAT"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then chatType = "PARTY"
    else return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    C_ChatInfo.SendChatMessage("[EUI] " .. title .. ": " .. text, chatType)
end

-- Records the quest's current counts. Returns false when it has no data yet.
local function SeedQuest(questID)
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then return false end
    local entry = progCache[questID] or {}
    for i, obj in ipairs(objectives) do entry[i] = obj.numFulfilled or 0 end
    entry.done = C_QuestLog.IsComplete(questID) == true
    progCache[questID] = entry
    return true
end

local function CheckQuest(questID)
    local prev = progCache[questID]
    if not prev then SeedQuest(questID); return end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then return end
    local objDone = false
    for i, obj in ipairs(objectives) do
        local n = obj.numFulfilled or 0
        if prev[i] and n > prev[i] then
            Announce(questID, obj.text)
            if obj.finished then objDone = true end
        end
        prev[i] = n
    end
    local done = C_QuestLog.IsComplete(questID) == true
    if done and not prev.done then
        Announce(questID, QUEST_COMPLETE or "Complete")
        PlaySoundKey(Cfg("soundQuest"))
    elseif objDone then
        PlaySoundKey(Cfg("soundObjective"))
    end
    prev.done = done
end

local function SeedAll()
    wipe(progCache)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then SeedQuest(info.questID) end
    end
end

local function OnProgressEvent(_, event, questID)
    if event == "QUEST_WATCH_UPDATE" then
        if questID then progDirty[questID] = true end
    elseif event == "QUEST_LOG_UPDATE" then
        -- The cache fills here, once the log has entries, not at login.
        if needSeed then
            if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
            needSeed = false
            SeedAll()
        end
        for id in pairs(progDirty) do
            progDirty[id] = nil
            CheckQuest(id)
        end
    elseif event == "QUEST_ACCEPTED" then
        if questID then SeedQuest(questID) end
    elseif event == "QUEST_REMOVED" then
        if questID then progCache[questID] = nil end
    end
end

-- Options / profile entry point.
function EQT.ApplyQuestProgress()
    local on = ProgressOn()
    if not progFrame then
        if not on then return end
        progFrame = CreateFrame("Frame")
        progFrame:SetScript("OnEvent", OnProgressEvent)
    end
    progFrame:UnregisterAllEvents()
    wipe(progDirty)
    wipe(progCache)
    needSeed = on
    if not on then return end
    progFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    progFrame:RegisterEvent("QUEST_LOG_UPDATE")
    progFrame:RegisterEvent("QUEST_ACCEPTED")
    progFrame:RegisterEvent("QUEST_REMOVED")
end

-------------------------------------------------------------------------------
-- Objective line colors (EllesmereUI style; painted by the skin): a progress
-- gradient over the three color stops and/or dimmed finished lines. Blizzard
-- recolors a line only when its color style changes, so ours holds between
-- passes. Each line is stamped with what it was painted from (its text,
-- Blizzard's color style and the settings), and only a line whose stamp moved
-- is painted again: an unchanged block costs no objective lookup.
-------------------------------------------------------------------------------
local colored    = setmetatable({}, { __mode = "k" })
local stampText  = setmetatable({}, { __mode = "k" })
local stampStyle = setmetatable({}, { __mode = "k" })
local stampGen   = setmetatable({}, { __mode = "k" })

local STOPS = {
    { "objStartR", "objStartG", "objStartB", def = OBJ_STOPS.Start },
    { "objMidR",   "objMidG",   "objMidB",   def = OBJ_STOPS.Mid },
    { "objEndR",   "objEndG",   "objEndB",   def = OBJ_STOPS.End },
}
-- Every setting the paint reads; a change moves the generation, which every
-- line's stamp carries.
local COLOR_KEYS = { "objProgressColor", "objDimCompleted", "objDimAlpha" }
for _, s in ipairs(STOPS) do
    for i = 1, 3 do COLOR_KEYS[#COLOR_KEYS + 1] = s[i] end
end
local colorSnap, colorGen = {}, 0
local function ColorGen()
    local db = EQT.DB()
    local moved = false
    for i = 1, #COLOR_KEYS do
        local k = COLOR_KEYS[i]
        local v = db[k]
        if colorSnap[k] ~= v then colorSnap[k] = v; moved = true end
    end
    if moved then colorGen = colorGen + 1 end
    return colorGen
end

local function StopRGB(s)
    local db = EQT.DB()
    return db[s[1]] or s.def[1], db[s[2]] or s.def[2], db[s[3]] or s.def[3]
end

local function ProgressRGB(f)
    local s1, s2
    if f < 0.5 then
        s1, s2, f = STOPS[1], STOPS[2], f * 2
    else
        s1, s2, f = STOPS[2], STOPS[3], f * 2 - 1
    end
    local r1, g1, b1 = StopRGB(s1)
    local r2, g2, b2 = StopRGB(s2)
    return r1 + (r2 - r1) * f, g1 + (g2 - g1) * f, b1 + (b2 - b1) * f
end

-- Back to Blizzard's color.
local function Restore(fs)
    local style = fs.colorStyle
    if style then fs:SetTextColor(style.r, style.g, style.b, 1) end
    colored[fs], stampText[fs], stampStyle[fs], stampGen[fs] = nil, nil, nil, nil
end

-- Whether the skin should hand blocks over: a mode is on, or lines still
-- carry our color.
function EQT.ObjColorsWanted()
    return Cfg("objProgressColor") or Cfg("objDimCompleted") or next(colored) ~= nil
end

function EQT.ColorObjectiveLines(block)
    local lines = block and block.usedLines
    if not lines then return end
    local progress, dim = Cfg("objProgressColor"), Cfg("objDimCompleted")
    local questID = type(block.id) == "number" and block.id
    if not ((progress or dim) and questID) or StandDown() or EllesmereUI.PadGamepadUI() then
        if next(colored) == nil then return end
        for _, line in pairs(lines) do
            local fs = line.Text
            if fs and colored[fs] then Restore(fs) end
        end
        return
    end
    local gen = ColorGen()
    local stale = false
    for key, line in pairs(lines) do
        local fs = line.Text
        if fs then
            if type(key) == "number" then
                if stampGen[fs] ~= gen or stampText[fs] ~= fs:GetText() or stampStyle[fs] ~= fs.colorStyle then
                    stale = true; break
                end
            elseif colored[fs] then
                stale = true; break
            end
        end
    end
    if not stale then return end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    local alpha = (Cfg("objDimAlpha") or 45) / 100
    for key, line in pairs(lines) do
        local fs = line.Text
        local obj = objectives and type(key) == "number" and objectives[key]
        if fs and obj then
            local text, style = fs:GetText(), fs.colorStyle
            if stampGen[fs] ~= gen or stampText[fs] ~= text or stampStyle[fs] ~= style then
                local r, g, b = 1, 1, 1
                if style then r, g, b = style.r, style.g, style.b end
                local req = obj.numRequired
                if progress then
                    -- Finished lines take the End color, not Blizzard's grey.
                    if obj.finished then
                        r, g, b = ProgressRGB(1)
                    elseif type(req) == "number" and req > 0 then
                        r, g, b = ProgressRGB((obj.numFulfilled or 0) / req)
                    end
                end
                fs:SetTextColor(r, g, b, (dim and obj.finished) and alpha or 1)
                colored[fs] = true
                stampText[fs], stampStyle[fs], stampGen[fs] = text, style, gen
            end
        elseif fs then
            -- A non-objective line on a recycled frame.
            if colored[fs] then Restore(fs) end
            -- An index with no objective is stamped too, so it cannot keep
            -- the block stale.
            if objectives and type(key) == "number" then
                stampText[fs], stampStyle[fs], stampGen[fs] = fs:GetText(), fs.colorStyle, gen
            end
        end
    end
end
