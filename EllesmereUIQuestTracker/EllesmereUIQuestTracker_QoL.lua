if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_QoL.lua
--
-- QoL layer: auto-accept, auto-turn-in, quest-item hotkey, quest sorting,
-- filtering and auto-track, progress sounds/announce, SplashFrame taint-free
-- OnHide clone.
--
-- Ported verbatim from the previous custom tracker:
--   * Auto-accept / auto-turn-in event machine (source L3421-3495)
--   * SplashFrame taint fix (source L3132-3150) -- intentional SetScript,
--     replaces Blizzard's OnHide with a clone that drops the
--     ObjectiveTrackerFrame:Update() call that taints Quest Button +
--     money frames downstream.
--   * Quest-item hotkey via SecureActionButton (source L3531-3708)
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT
local function Cfg(k) return EQT.Cfg(k) end

-------------------------------------------------------------------------------
-- SplashFrame taint fix. This is the one intentional SetScript in this
-- addon -- we are replacing Blizzard's OnHide body because calling
-- ObjectiveTrackerFrame:Update() from it taints downstream secure frames.
-------------------------------------------------------------------------------
local function InstallSplashFrameFix()
    local sf = _G.SplashFrame
    if not sf then return end
    sf:SetScript("OnHide", function(frame)
        local fromGameMenu = frame.screenInfo and frame.screenInfo.gameMenuRequest
        frame.screenInfo = nil
        if C_TalkingHead_SetConversationsDeferred then
            C_TalkingHead_SetConversationsDeferred(false)
        end
        if _G.AlertFrame and _G.AlertFrame.SetAlertsEnabled then
            _G.AlertFrame:SetAlertsEnabled(true, "splashFrame")
        end
        -- ObjectiveTrackerFrame:Update() intentionally omitted (causes taint)
        if fromGameMenu and not frame.showingQuestDialog and not InCombatLockdown() then
            if _G.GameMenuFrame then
                ShowUIPanel(_G.GameMenuFrame)
            end
        end
        frame.showingQuestDialog = nil
    end)
end

-------------------------------------------------------------------------------
-- Auto-accept / auto-turn-in
-------------------------------------------------------------------------------
-- Blizzard's trivial flag never fires for a quest that scales to the player,
-- so quests from an earlier expansion have a toggle of their own. Leveling
-- (below max level or in Chromie Time) runs through older content, so that
-- toggle waits for max level; WoW Forever has no older expansions.
local function IsIgnoredQuest(questID, isTrivial)
    if isTrivial and Cfg("autoAcceptIgnoreTrivial") then return true end
    if not Cfg("autoAcceptIgnoreOldExpansion") or not questID or questID == 0 then return false end
    if EllesmereUI.IS_FOREVER or C_PlayerInfo.IsPlayerInChromieTime()
        or UnitLevel("player") < GetMaxLevelForPlayerExpansion() then
        return false
    end
    local expansion = GetQuestExpansion(questID)
    return expansion ~= nil and expansion >= 0 and expansion < GetServerExpansionLevel()
end

-- Quest filter's older-expansion check.
local function IsOldExpansionQuest(questID)
    if not questID or questID == 0 then return false end
    local expansion = GetQuestExpansion(questID)
    return expansion ~= nil and expansion >= 0 and expansion < GetServerExpansionLevel()
end

local function InstallAutoQuests()
    local autoFrame = CreateFrame("Frame")
    local autoPreventNPCGUID = nil
    autoFrame:RegisterEvent("QUEST_DETAIL")
    autoFrame:RegisterEvent("QUEST_COMPLETE")
    autoFrame:RegisterEvent("GOSSIP_SHOW")
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local aidx = #EQT._eventFrames + 1
    EQT._eventFrames[aidx] = autoFrame
    EQT._eventRegistrations[aidx] = {"QUEST_DETAIL", "QUEST_COMPLETE", "GOSSIP_SHOW"}
    autoFrame:SetScript("OnEvent", function(_, event, ...)
        if Cfg("enabled") == false then return end

        if event == "GOSSIP_SHOW" then
            if C_GossipInfo then
                if Cfg("autoTurnIn") and C_GossipInfo.GetActiveQuests then
                    local active = C_GossipInfo.GetActiveQuests()
                    if active then
                        for _, quest in ipairs(active) do
                            if quest.questID and quest.isComplete then
                                C_GossipInfo.SelectActiveQuest(quest.questID)
                                return
                            end
                        end
                    end
                end
                if Cfg("autoAccept") and C_GossipInfo.GetAvailableQuests then
                    if Cfg("autoAcceptShiftSkip") and IsShiftKeyDown() then return end
                    local available = C_GossipInfo.GetAvailableQuests()
                    if available then
                        for i = #available, 1, -1 do
                            if IsIgnoredQuest(available[i].questID, available[i].isTrivial) then
                                table.remove(available, i)
                            end
                        end
                    end
                    if available and #available > 0 then
                        local npcGUID = UnitGUID("npc")
                        if Cfg("autoAcceptPreventMulti") then
                            if #available > 1 then
                                autoPreventNPCGUID = npcGUID
                            end
                            if autoPreventNPCGUID == npcGUID then
                                -- do nothing; let user pick manually
                            elseif available[1].questID then
                                C_GossipInfo.SelectAvailableQuest(available[1].questID)
                                return
                            end
                        elseif available[1].questID then
                            C_GossipInfo.SelectAvailableQuest(available[1].questID)
                            return
                        end
                    end
                end
            end
            return
        end

        -- QUEST_AUTOCOMPLETE handling removed: calling ShowQuestComplete() from addon
        -- execution runs Blizzard's quest-complete panel flow (ShowUIPanel, UIPanel
        -- attribute writes on WorldMapFrame) under our taint, and that state is read by
        -- every later map open -- confirmed in tester taint logs as blocked map-pin
        -- calls in combat. Blizzard's native auto-quest popup in the tracker covers
        -- this securely: the player clicks it, and if the reward has no choice, the
        -- QUEST_COMPLETE auto-turn-in below still fires.

        if event == "QUEST_DETAIL" then
            if not Cfg("autoAccept") then return end
            if Cfg("autoAcceptShiftSkip") and IsShiftKeyDown() then return end
            local questID = GetQuestID()
            if IsIgnoredQuest(questID, C_QuestLog.IsQuestTrivial(questID)) then return end
            AcceptQuest()
        elseif event == "QUEST_COMPLETE" then
            if not Cfg("autoTurnIn") then return end
            if Cfg("autoTurnInShiftSkip") and IsShiftKeyDown() then return end
            local numChoices = GetNumQuestChoices()
            if numChoices <= 1 then
                GetQuestReward(numChoices)
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Quest-item hotkey. SecureActionButton (type="item") carrying the player's
-- current quest item, reached by an OVERRIDE binding on the chosen key.
--
-- The button has to stay secure. Using an item is a protected action, and the
-- dedicated quest API, UseQuestLogSpecialItem, is itself protected, so there
-- is no insecure route to this: a plain button calling it is simply blocked.
--
-- The key used to travel through the GLOBAL binding table instead:
-- SetBinding(key, "EUI_QUESTITEM") plus SaveBindings, with a restricted
-- snippet reading GetBindingKey back out to build the click binding.
-- EUI_QUESTITEM was never declared in a Bindings.xml, so no such binding
-- command exists for the client to execute, and the round trip also took the
-- key away from whatever the player had bound there and wrote that to their
-- saved bindings. Override bindings avoid both: they execute a click on our
-- button directly, and they never touch anything persistent.
-------------------------------------------------------------------------------
local function ScanForQuestItem()
    if not C_QuestLog then return nil end
    local num = C_QuestLog.GetNumQuestLogEntries() or 0
    local fallback = nil
    for i = 1, num do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local logIdx = C_QuestLog.GetLogIndexForQuestID
                and C_QuestLog.GetLogIndexForQuestID(info.questID) or i
            local link = GetQuestLogSpecialItemInfo(logIdx)
            if link then
                local name = link:match("%[(.-)%]")
                if name then
                    local wt = C_QuestLog.GetQuestWatchType
                        and C_QuestLog.GetQuestWatchType(info.questID)
                    if wt ~= nil then return name end
                    fallback = fallback or name
                end
            end
        end
    end
    return fallback
end

-- One-time repair for profiles that ran the SetBinding version below. That
-- binding can never do anything, but it was written to the player's SAVED
-- bindings, so it sits there holding a key hostage until something clears it.
local _legacyCleared = false
local function ClearLegacyQuestItemBinding()
    if _legacyCleared or InCombatLockdown() then return end
    if not (GetBindingKey and SetBinding) then return end
    _legacyCleared = true
    local k1, k2 = GetBindingKey("EUI_QUESTITEM")
    if not (k1 or k2) then return end
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    local bindingSet = GetCurrentBindingSet and GetCurrentBindingSet()
    if SaveBindings and bindingSet and bindingSet >= 1 and bindingSet <= 2 then
        SaveBindings(bindingSet)
    end
end

local function InstallQuestItemHotkey()
    -- The button stays a SecureActionButton with type="item": quest items are
    -- ordinary bag items as far as using them goes, and the dedicated
    -- UseQuestLogSpecialItem API is PROTECTED, so a plain button calling it
    -- would be blocked. What was broken was never the use, it was the key.
    local qItemBtn = CreateFrame("Button", "EUI_QuestItemHotkeyBtn", UIParent,
        "SecureActionButtonTemplate")
    qItemBtn:SetSize(32, 32)
    qItemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    qItemBtn:SetAlpha(0)
    qItemBtn:EnableMouse(false)
    -- BOTH phases, and this is load-bearing rather than defensive.
    -- SecureActionButton_OnClick runs the action only when the click phase
    -- matches the player's "cast on key down" preference:
    --     useOnKeyDown = SecureActionButton_ShouldUseOnKeyDown(self)
    --                    -- attribute, else the ActionButtonUseKeyDown CVar
    --     clickAction  = (down and useOnKeyDown)
    --                    or (not down and not useOnKeyDown)
    -- Registered for up only, OnClick can never fire with down == true, so
    -- for anyone playing with cast-on-key-down the test is false every time
    -- and the action is silently discarded. The binding is created, the
    -- attributes are right, the click is delivered, and nothing happens --
    -- which is exactly how this presented. Register both and let the secure
    -- handler pick the phase; it fires the action for precisely one of them.
    qItemBtn:RegisterForClicks("AnyDown", "AnyUp")

    local function InitSecureAttributes()
        qItemBtn:SetAttribute("type", "item")
    end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("QuestItemInit", function()
            InitSecureAttributes()
            if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
        end)
    else
        InitSecureAttributes()
    end

    EQT.qItemBtn = qItemBtn

    -- The key the override is currently laid down on, or nil for "none".
    -- _bindingDirty is tracked SEPARATELY and deliberately: nil has to mean
    -- "bound to nothing", not "state unknown". Folding the two together meant
    -- that after an external invalidation, losing the quest item compared
    -- nil == nil, skipped ClearOverrideBindings, and left a priority override
    -- sitting on a button with no item -- eating the key for good, which is
    -- the exact failure the want/_boundKey check exists to avoid.
    local _boundKey = nil
    local _bindingDirty = true
    -- Our own binding writes raise UPDATE_BINDINGS. Re-applying from inside
    -- that event is a self-feeding loop, and a plain "did anything change"
    -- test cannot break it because the invalidation arrives after the write.
    -- Ignore the event for a short window after we write instead; a genuine
    -- external clear inside that window is picked up by the next quest event
    -- or by PLAYER_REGEN_ENABLED.
    local _selfWriteUntil = 0

    local function ApplyBinding()
        -- Binding writes are combat-restricted; PLAYER_REGEN_ENABLED replays.
        if InCombatLockdown() then return end
        local key = Cfg("questItemHotkey")
        if key == "" then key = nil end
        -- Bind only while a quest item actually exists. An override outranks
        -- the player's own binding for that key, so holding it while there is
        -- nothing to use would silently eat the key.
        local want = (key and qItemBtn:GetAttribute("item")) and key or nil
        if not _bindingDirty and want == _boundKey then return end
        _bindingDirty = false
        _selfWriteUntil = GetTime() + 0.5
        if ClearOverrideBindings then ClearOverrideBindings(qItemBtn) end
        if want and SetOverrideBindingClick then
            SetOverrideBindingClick(qItemBtn, true, want,
                "EUI_QuestItemHotkeyBtn", "LeftButton")
        end
        _boundKey = want
    end

    local cachedName = nil
    local dirty = true

    local function UpdateQuestItemAttribute()
        if InCombatLockdown() then return end
        -- The gate belongs HERE, on the scan, not only on the quest-event
        -- branch that used to carry it. PLAYER_REGEN_ENABLED reaches this
        -- through the force entry point, so with the gate further out every
        -- combat drop paid a full quest-log walk -- the allocation peak the
        -- coalescer below exists to avoid -- for players who never set a
        -- hotkey. ApplyBinding still runs either way, so unbinding still
        -- clears.
        if not Cfg("questItemHotkey") then return end
        if not dirty then return end
        dirty = false
        local found = ScanForQuestItem()
        if found ~= cachedName then
            cachedName = found
            qItemBtn:SetAttribute("item", found)
            -- Gaining or losing the item flips whether the key should be bound
            -- at all, so the binding has to follow the scan.
            ApplyBinding()
        end
    end
    EQT.UpdateQuestItemAttribute = UpdateQuestItemAttribute

    -- Options entry point. It must force a rescan, not just re-apply: the
    -- event-driven scan is skipped entirely while no hotkey is configured, so
    -- the very first bind would otherwise apply against a stale item.
    local function ApplyQuestItemHotkey()
        if InCombatLockdown() then return end
        dirty = true
        -- Force the binding too, not just the scan. Without this the entry
        -- point cannot re-lay an override something else wiped: the state
        -- would compare equal and take the early-out.
        _bindingDirty = true
        UpdateQuestItemAttribute()
        ApplyBinding()
    end
    EQT.ApplyQuestItemHotkey = ApplyQuestItemHotkey

    -- Loot-storm coalescer (memory pass 2026-08-03): QUEST_LOG_UPDATE fires in bursts
    -- on loot/objective progress, and each fire paid a full quest log scan -- an info
    -- table per log entry, the suite's single-frame allocation peak (~106KB in one
    -- frame). One deferred scan per burst instead; the scan keeps its own dirty/combat
    -- gates, so a burst that ends in combat parks on dirty and the existing
    -- PLAYER_REGEN_ENABLED path picks it up. Prebuilt closure: no per-burst allocation.
    local scanPending = false
    local function FlushQuestItemScan()
        scanPending = false
        UpdateQuestItemAttribute()
    end

    local qItemFrame = CreateFrame("Frame")
    qItemFrame:RegisterEvent("QUEST_LOG_UPDATE")
    qItemFrame:RegisterEvent("QUEST_ACCEPTED")
    qItemFrame:RegisterEvent("QUEST_REMOVED")
    qItemFrame:RegisterEvent("QUEST_TURNED_IN")
    qItemFrame:RegisterEvent("UPDATE_BINDINGS")
    qItemFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Deliberately NOT enrolled in EQT._eventFrames, so the raid/arena/M+
    -- suspension leaves it alone. That suspension exists to stop skin and
    -- layout work while the tracker is hidden; this frame does neither, it
    -- owns a keybind.
    --
    -- Enrolling it was actively harmful. The dominant suspension trigger is
    -- ENCOUNTER_START, which fires IN COMBAT, and binding writes are
    -- combat-restricted -- so the override could not be cleared on the way in,
    -- and unregistering PLAYER_REGEN_ENABLED removed the one event that could
    -- have cleared it on the way out. The result was a priority override
    -- parked on the player's key for the whole encounter, pointing at a
    -- button whose item attribute was frozen where the scan stopped.
    --
    -- The scan it drives is already gated on a hotkey being configured and
    -- coalesced to one pass per burst, so leaving it registered costs nothing
    -- for anyone who has not set a key.
    qItemFrame:SetScript("OnEvent", function(_, event)
        if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Also the recovery path for a /reload taken in combat, where the
            -- init timer bailed before it could run.
            ClearLegacyQuestItemBinding()
            ApplyQuestItemHotkey()
            return
        end
        if event == "UPDATE_BINDINGS" then
            -- Ours, echoing back: ignore, or we re-enter forever.
            if GetTime() < _selfWriteUntil then return end
            -- Someone else rewrote the binding table. LoadBindings, which the
            -- settings panel runs on cancel and on a binding-set switch,
            -- clears every override, so waiting for the tracked item to change
            -- before re-applying could leave the hotkey dead indefinitely.
            _bindingDirty = true
            ApplyBinding()
            return
        end
        if not Cfg("questItemHotkey") then return end
        dirty = true
        if not scanPending then
            scanPending = true
            C_Timer.After(0.3, FlushQuestItemScan)
        end
    end)

    C_Timer.After(1.5, function()
        if InCombatLockdown() then return end
        ClearLegacyQuestItemBinding()
        ApplyQuestItemHotkey()
    end)
end

-------------------------------------------------------------------------------
-- Quest sorting, filtering and zone auto-track. The tracker lists watched
-- quests in watch-index order, so editing the watch list sorts and filters
-- it without touching the tracker. Blizzard's zone-change distance sort is
-- switched off while a custom sort mode is active. Frame is built on first
-- enable and unregistered while everything is off.
-------------------------------------------------------------------------------
local watchFrame
local watchPending = false
local sortStuck = false  -- last rebuild did not take; see ApplySort
local logUpdatePending = false
local sortIDs, sortGroup, sortKey, sortKey2, sortRank = {}, {}, {}, {}, {}
local watched = {}

local function SortMode() return Cfg("questSortMode") or "default" end
local function SortCompleted() return Cfg("questSortCompleted") or "mixed" end
-- Secondary key; ignored when the primary is already unique per quest.
local function SortThenBy()
    local mode = SortMode()
    if mode == "default" or mode == "log" then return "none" end
    return Cfg("questSortThenBy") or "none"
end
local function SortOn() return SortMode() ~= "default" or SortCompleted() ~= "mixed" end

-- A filter counts only while the master toggle is on.
local function FilterCfg(k) return Cfg("filterEnabled") and Cfg(k) end

local function FilterOn()
    return FilterCfg("filterZone") or FilterCfg("filterCompleted") or FilterCfg("filterTrivial")
        or FilterCfg("filterOldExpansion") or FilterCfg("filterRepeatable")
end

-- Per character: watch lists are per character, profiles may be shared.
-- hidden = untracked by a filter, exempt = re-tracked by the player,
-- auto = tracked by zone auto-track, declined = auto-tracked then untracked
-- by the player (left alone until they leave the zone).
local CHAR_SETS = { "hidden", "exempt", "auto", "declined" }
local function CharDB()
    local sv = _G.EllesmereUIQuestTrackerCharDB
    if type(sv) ~= "table" then sv = {}; _G.EllesmereUIQuestTrackerCharDB = sv end
    for _, k in ipairs(CHAR_SETS) do
        if type(sv[k]) ~= "table" then sv[k] = {} end
    end
    return sv
end

local function WatchesActive()
    if SortOn() or FilterOn() or Cfg("autoTrackZone") then return true end
    -- Leftovers from a feature that was turned off still need undoing.
    local sv = _G.EllesmereUIQuestTrackerCharDB
    if type(sv) ~= "table" then return false end
    for _, k in ipairs(CHAR_SETS) do
        if type(sv[k]) == "table" and next(sv[k]) ~= nil then return true end
    end
    return false
end

local function FillWatched()
    wipe(watched)
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then watched[questID] = true end
    end
end

-- "Current area". Retail: Blizzard's isOnMap (campaign quests are filed
-- under campaign headers, and instances have maps). Forever: instances have
-- no maps and isOnMap counts the parent zone's quests inside them, so the
-- quest log header must name the zone the player is in, or the instance.
-- Exact names only: a city is its own zone, so Orgrimmar is not Durotar.
local USE_HEADERS = EllesmereUI.IS_FOREVER == true

local function IsAreaHeader(title)
    if not title then return false end
    if title == GetRealZoneText() then return true end
    return IsInInstance() and title == GetInstanceInfo()
end

local function HeaderTitle(logIndex)
    for i = logIndex - 1, 1, -1 do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then return info.title end
    end
end

local function IsFiltered(questID, superID)
    if questID == superID then return false end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    local info = logIndex and C_QuestLog.GetInfo(logIndex)
    if not info then return false end
    if FilterCfg("filterCompleted") and C_QuestLog.IsComplete(questID) then return true end
    if FilterCfg("filterTrivial") and C_QuestLog.IsQuestTrivial(questID) then return true end
    if FilterCfg("filterOldExpansion") and IsOldExpansionQuest(questID) then return true end
    if FilterCfg("filterRepeatable") and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then return true end
    if FilterCfg("filterZone") then
        local inArea
        if USE_HEADERS then inArea = IsAreaHeader(HeaderTitle(logIndex)) else inArea = info.isOnMap end
        if not inArea then return true end
    end
    return false
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
            C_QuestLog.AddQuestWatch(questID)
        end
    end
    if not on then return end
    for questID in pairs(watched) do
        if not exempt[questID] and IsFiltered(questID, superID) then
            hidden[questID] = true
            db.auto[questID] = nil
            C_QuestLog.RemoveQuestWatch(questID)
        end
    end
end

-- Tracks quests in the current area (see USE_HEADERS) and untracks them
-- again on leaving.
local function ApplyAutoTrack()
    local db = CharDB()
    local hidden, auto, declined = db.hidden, db.auto, db.declined
    local on = Cfg("autoTrackZone")
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
    local inArea = false
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            inArea = USE_HEADERS and IsAreaHeader(info.title)
        elseif info and not info.isHidden and not info.isTask and not info.isBounty then
            local questID = info.questID
            if on and (inArea or (not USE_HEADERS and info.isOnMap)) then
                if free > 0 and not watched[questID] and not declined[questID]
                   and not hidden[questID] and not IsFiltered(questID, superID) then
                    auto[questID] = true
                    free = free - 1
                    C_QuestLog.AddQuestWatch(questID)
                end
            else
                declined[questID] = nil
                if auto[questID] then
                    auto[questID] = nil
                    C_QuestLog.RemoveQuestWatch(questID)
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

local function SortUses(key) return SortMode() == key or SortThenBy() == key end

-- Quest log section (zone / category header) index per quest; rebuilt by
-- the sort pass only while a Zone key is in use.
local zoneOf = {}
local function BuildZoneMap()
    wipe(zoneOf)
    local header = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then header = i
            elseif info.questID then zoneOf[info.questID] = header end
        end
    end
end

-- Lower sorts first. Recurring = dailies / weeklies.
local QC = Enum.QuestClassification
local TYPE_RANK = {
    [QC.Campaign] = 1, [QC.Legendary] = 2, [QC.Important] = 3, [QC.Meta] = 4,
    [QC.Questline] = 5, [QC.Normal] = 6, [QC.Recurring] = 7,
}

local function SortKeyFor(mode, questID, rank)
    if mode == "zone" then
        return zoneOf[questID] or 0
    elseif mode == "progress" then
        -- Most complete first: negated share of all objective counts.
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
        if C_QuestLog.IsComplete(questID) then return -1 end
        return need > 0 and -(have / need) or 0
    elseif mode == "type" then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        local info = logIndex and C_QuestLog.GetInfo(logIndex)
        if not info then return 6 end
        local r = TYPE_RANK[info.questClassification] or 6
        if r == 6 and info.frequency and info.frequency ~= Enum.QuestFrequency.Default then r = 7 end
        return r
    elseif mode == "log" then
        return C_QuestLog.GetLogIndexForQuestID(questID) or 0
    elseif mode == "level" or mode == "name" then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        local info = logIndex and C_QuestLog.GetInfo(logIndex)
        if mode == "level" then
            return info and (info.difficultyLevel or info.level) or 0
        end
        return info and info.title and info.title:lower() or ""
    elseif mode == "none" then
        return 0
    end
    return rank
end

local function ApplySort()
    local mode, completed, thenBy = SortMode(), SortCompleted(), SortThenBy()
    wipe(sortGroup); wipe(sortKey); wipe(sortKey2); wipe(sortRank)
    if mode == "zone" or thenBy == "zone" then BuildZoneMap() end
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
    -- The previous rebuild did not produce its order: skip one pass so our
    -- own watch events cannot loop.
    if sortStuck then sortStuck = false; return end

    -- No super-track restore here: setting it from addon code taints the
    -- world map (see the removed OnClick hook in Skin.lua).
    for i = last, 1, -1 do
        C_QuestLog.RemoveQuestWatch(sortIDs[i])
        C_QuestLog.AddQuestWatch(sortIDs[i])
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

local function ApplyWatches()
    watchPending = false
    if InCombatLockdown() then
        watchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    watchFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    -- Log not loaded yet (loading screens): nothing reliable to act on.
    if C_QuestLog.GetNumQuestLogEntries() == 0 then return end
    ApplyFilter()
    ApplyAutoTrack()
    if SortOn() then ApplySort() end
    -- Last pass after everything was turned off: put the frame to sleep.
    if not WatchesActive() then watchFrame:UnregisterAllEvents() end
end

local function QueueWatches()
    if watchPending then return end
    watchPending = true
    C_Timer.After(0, ApplyWatches)
end

-- QUEST_WATCH_UPDATE fires before the log holds the new counts, so the pass
-- waits for the QUEST_LOG_UPDATE that follows it.
local function OnWatchEvent(_, event)
    if event == "QUEST_WATCH_UPDATE" then
        logUpdatePending = true
    elseif event == "QUEST_LOG_UPDATE" then
        if not logUpdatePending then return end
        logUpdatePending = false
        QueueWatches()
    else
        QueueWatches()
    end
end

-- These two events only drive Blizzard's distance sort on the tracker
-- (ObjectiveTrackerFrameMixin:OnEvent), so a custom sort mode turns them off
-- instead of fighting it. Re-registered when sorting returns to Default.
local blizzSortOff = false
local BLIZZ_SORT_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }
local function ApplyBlizzardSort()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    local off = SortMode() ~= "default"
    if off == blizzSortOff then return end
    blizzSortOff = off
    for _, event in ipairs(BLIZZ_SORT_EVENTS) do
        if off then otf:UnregisterEvent(event) else otf:RegisterEvent(event) end
    end
end

-- Options / profile entry point.
function EQT.ApplyQuestWatches()
    ApplyBlizzardSort()
    local on = WatchesActive()
    if not watchFrame then
        if not on then return end
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", OnWatchEvent)
    end
    watchFrame:UnregisterAllEvents()
    sortStuck, logUpdatePending = false, false
    if not on then return end
    watchFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    -- The current map changes on these; with Default sort mode Blizzard's
    -- distance sort also runs on them and our deferred pass lands after it.
    watchFrame:RegisterEvent("ZONE_CHANGED")
    watchFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    -- Entering or leaving an instance ends on a loading screen.
    if FilterCfg("filterZone") or Cfg("autoTrackZone") then
        watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- Objective progress can flip a quest to complete.
    if SortCompleted() ~= "mixed" or FilterCfg("filterCompleted") or SortUses("progress") then
        watchFrame:RegisterEvent("QUEST_WATCH_UPDATE")
        watchFrame:RegisterEvent("QUEST_LOG_UPDATE")
    end
    -- Quests turn trivial as the player levels.
    if FilterCfg("filterTrivial") then watchFrame:RegisterEvent("PLAYER_LEVEL_UP") end
    -- New quests are not always auto-watched by Blizzard.
    if Cfg("autoTrackZone") then watchFrame:RegisterEvent("QUEST_ACCEPTED") end
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
        -- After the bundled sounds, before SharedMedia's "---" block.
        for i, p in ipairs(PEON_SOUNDS) do
            soundPaths[p[1]], names[p[1]], peonFile[p[1]] = p[3], p[2], p[3]
            table.insert(order, #EllesmereUI.ALERT_SOUND_ORDER + i, p[1])
        end
        EllesmereUI.AppendSharedMediaSounds(soundPaths, names, order)
        EQT.SoundNames, EQT.SoundOrder = names, order
    end
    return soundPaths, EQT.SoundNames, EQT.SoundOrder
end

-- A SharedMedia sound is a file path or a SoundKit id; peon lines are
-- FileDataIDs. Also the options dropdown's preview.
local function PlaySoundKey(key)
    if not key or key == "none" then return end
    local path = EQT.Sounds()[key]
    if peonFile[key] then
        PlaySoundFile(peonFile[key], "Master")
    elseif type(path) == "number" then
        if path ~= 1 then PlaySound(path, "Master") end
    elseif path then
        PlaySoundFile(path, "Master")
    end
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
    SendChatMessage("[EUI] " .. title .. ": " .. text, chatType)
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
    if not on then wipe(progCache); return end
    progFrame:RegisterEvent("QUEST_WATCH_UPDATE")
    progFrame:RegisterEvent("QUEST_LOG_UPDATE")
    progFrame:RegisterEvent("QUEST_ACCEPTED")
    progFrame:RegisterEvent("QUEST_REMOVED")
    SeedAll()
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function EQT.InitQoL()
    InstallSplashFrameFix()
    InstallAutoQuests()
    InstallQuestItemHotkey()
    EQT.ApplyQuestWatches()
    EQT.ApplyQuestProgress()
end
