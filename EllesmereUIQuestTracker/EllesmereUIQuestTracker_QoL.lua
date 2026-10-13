if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_QoL.lua
--
-- QoL layer: auto-accept, auto-turn-in, quest-item hotkey, SplashFrame
-- taint-free OnHide clone, current-zone filter. Everything here is combat-gated.
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

local function InstallAutoQuests()
    local autoFrame = CreateFrame("Frame")
    local autoPreventNPCGUID = nil
    autoFrame:RegisterEvent("QUEST_DETAIL")
    autoFrame:RegisterEvent("QUEST_COMPLETE")
    autoFrame:RegisterEvent("GOSSIP_SHOW")
    -- Deliberately NOT enrolled in EQT._eventFrames, so the raid/arena/M+
    -- suspension leaves it alone. That suspension exists to stop skin and
    -- layout work while the tracker is hidden; this frame does neither, it
    -- answers quest NPC dialogs, so Auto Accept / Auto Turn In keep working
    -- while the tracker is hidden.
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
-- Current-zone filter (opt-in: zoneFilterButton). Works through the watch
-- lists (the same API as the quest log's track checkbox), so the tracker
-- frames are never touched. Every quest it unwatches is kept in the DB
-- (survives /reload) and re-watched when the filter is turned off.
-------------------------------------------------------------------------------
-- Inert until the filter is on: no events registered while it is off.
local zoneEventFrame = CreateFrame("Frame")

local function ZoneFilterOn()
    return Cfg("zoneFilterButton") and Cfg("zoneFilter")
end

-- Dungeon / micro maps roll up to the zone that contains them.
local function ZoneOf(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID ~= 0 do
        mapID = info.parentMapID
        info = C_Map.GetMapInfo(mapID)
    end
    return info and mapID
end

local function IsInZone(questID, zone, onMap, isWorldQuest)
    if onMap[questID] then return true end
    local mapID = isWorldQuest and C_TaskQuest.GetQuestZoneID(questID) or GetQuestUiMapID(questID)
    return mapID ~= nil and mapID ~= 0 and ZoneOf(mapID) == zone
end

local WATCH_LISTS = {
    { key = "zoneFilterRemoved", isWorldQuest = false,
      num = C_QuestLog.GetNumQuestWatches, get = C_QuestLog.GetQuestIDForQuestWatchIndex,
      add = C_QuestLog.AddQuestWatch, remove = C_QuestLog.RemoveQuestWatch,
      valid = C_QuestLog.GetLogIndexForQuestID },
}
-- WoW Forever has no world quests.
if not EllesmereUI.IS_FOREVER then
    WATCH_LISTS[2] = { key = "zoneFilterRemovedWQ", isWorldQuest = true,
      num = C_QuestLog.GetNumWorldQuestWatches, get = C_QuestLog.GetQuestIDForWorldQuestWatchIndex,
      add = C_QuestLog.AddWorldQuestWatch, remove = C_QuestLog.RemoveWorldQuestWatch,
      valid = C_TaskQuest.IsActive }
end

local function HasRemovedQuests()
    local db = EQT.DB()
    return db.zoneFilterRemoved ~= nil or db.zoneFilterRemovedWQ ~= nil
end

local function ApplyZoneFilter()
    local zone = ZoneOf(C_Map.GetBestMapForUnit("player"))
    if not zone then return end
    local onMap = {}
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(zone) or {}) do onMap[q.questID] = true end

    local db = EQT.DB()
    for _, list in ipairs(WATCH_LISTS) do
        local removed = db[list.key] or {}
        db[list.key] = removed
        -- Snapshot first: removing a watch shifts the indices.
        local watched = {}
        for i = 1, list.num() do watched[i] = list.get(i) end
        for _, id in ipairs(watched) do
            if not IsInZone(id, zone, onMap, list.isWorldQuest) then
                list.remove(id)
                removed[id] = true
            end
        end
        -- Only bring back quests the filter itself hid.
        for id in pairs(removed) do
            if not list.valid(id) then
                removed[id] = nil
            elseif IsInZone(id, zone, onMap, list.isWorldQuest) then
                removed[id] = nil
                list.add(id)
            end
        end
    end
end

local function RestoreZoneFilter()
    local db = EQT.DB()
    for _, list in ipairs(WATCH_LISTS) do
        local removed = db[list.key]
        db[list.key] = nil
        for id in pairs(removed or {}) do
            if list.valid(id) then list.add(id) end
        end
    end
end

-- Watch changes relayout the tracker; keep them out of combat.
local function SyncZoneFilter()
    if InCombatLockdown() then
        ns.CombatQueue.Defer("ZoneFilterSync", SyncZoneFilter)
        return
    end
    if ZoneFilterOn() then ApplyZoneFilter() else RestoreZoneFilter() end
end

-- One pass per burst of zone events.
local syncQueued = false
local function QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0.5, function()
        syncQueued = false
        SyncZoneFilter()
    end)
end

zoneEventFrame:SetScript("OnEvent", function(self, event)
    -- The quest log is only readable after the first update following login.
    if event == "QUEST_LOG_UPDATE" then self:UnregisterEvent(event) end
    QueueSync()
end)

local function UpdateZoneLook()
    local btn, line = EQT.zoneToggle, EQT.zoneStandIn._line
    local eg = EllesmereUI.ELLESMERE_GREEN
    local on = Cfg("zoneFilter")
    btn._fill:SetColorTexture(eg.r, eg.g, eg.b, 1)
    btn._fill:SetShown(on)
    if on then btn._text:SetTextColor(eg.r, eg.g, eg.b) else btn._text:SetTextColor(0.6, 0.6, 0.6) end
    if line then line:SetColorTexture(eg.r, eg.g, eg.b, 1) end
end

local function SetStandInCollapsed(standIn, collapsed)
    standIn._collapsed = collapsed
    local atlas = "ui-questtrackerbutton-secondary-" .. (collapsed and "expand" or "collapse")
    local btn = standIn._header.MinimizeButton
    btn:SetNormalAtlas(atlas)
    btn:SetPushedAtlas(atlas .. "-pressed")
    standIn._msg:SetShown(not collapsed)
    standIn:SetHeight(collapsed and 26 or 46)
end

-- Font and colors come from the live Quests header (skinned or stock).
local function MatchQuestsHeader(standIn, qt)
    local src, title = qt.Header.Text, standIn._title
    local font, size, flags = src:GetFont()
    if font then
        title:SetFont(font, size, flags)
        standIn._msg:SetFont(font, Cfg("objectiveFontSize") or 10, flags)
    end
    title:SetTextColor(src:GetTextColor())
    title:SetText(src:GetText() or TRACKER_HEADER_QUESTS)
    local from = qt.Header.MinimizeButton:GetNormalTexture()
    local btn = standIn._header.MinimizeButton
    local normal, pushed = btn:GetNormalTexture(), btn:GetPushedTexture()
    normal:SetDesaturated(from:IsDesaturated())
    normal:SetVertexColor(from:GetVertexColor())
    pushed:SetDesaturated(from:IsDesaturated())
    pushed:SetVertexColor(from:GetVertexColor())
end

-- Toggle and stand-in are our own UIParent frames (never tracker children):
-- re-host the toggle and mirror the tracker's visibility onto both.
function EQT.RefreshZoneUI()
    local btn, standIn = EQT.zoneToggle, EQT.zoneStandIn
    if not Cfg("zoneFilterButton") then
        btn:Hide()
        standIn:Hide()
        btn._host = nil
        EQT.QueueResize()
        return
    end
    local otf, qt = _G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker
    local a = EQT._trackerHardHidden and 0 or otf:GetAlpha()

    -- Blizzard hides an empty section (and an empty tracker), so the stand-in
    -- keeps a Quests header up while the filter has emptied it.
    local wantStandIn = Cfg("zoneFilter") and not EQT._trackerHardHidden and not qt:IsShown()
        and not otf:IsCollapsed() and not C_ChallengeMode.IsChallengeModeActive()
    if wantStandIn then
        local lowest = EQT.GetLowestContentFrame()
        standIn:ClearAllPoints()
        -- Same placement ObjectiveTrackerContainerMixin:Update gives a module.
        if lowest then
            standIn:SetPoint("TOP", lowest, "BOTTOM", 0, -otf.moduleSpacing)
        else
            standIn:SetPoint("TOP", otf, "TOP", 0, -otf.topModulePadding)
        end
        standIn:SetPoint("LEFT", otf, "LEFT", qt.leftMargin or 0, 0)
        standIn:SetPoint("RIGHT", otf, "RIGHT")
        MatchQuestsHeader(standIn, qt)
    end
    standIn:SetShown(wantStandIn)
    standIn:SetAlpha(a)

    local host = (wantStandIn and standIn._header) or (qt:IsShown() and qt.Header) or nil
    if host and host ~= btn._host then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", host.MinimizeButton, "LEFT", -4, 0)
        btn:SetFrameLevel(host:GetFrameLevel() + 10)
    end
    btn._host = host
    btn:SetShown(host ~= nil)
    btn:SetAlpha(a)
    btn:EnableMouse(a > 0)
    EQT.QueueResize()
end

-- Built on first enable; never at all for players who leave the option off.
local function BuildZoneUI()
    if EQT.zoneToggle then return end
    local otf, qt = _G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker
    local strata = otf:GetFrameStrata()

    -- Stand-in header, laid out like ObjectiveTrackerModuleHeaderTemplate.
    local standIn = CreateFrame("Frame", nil, UIParent)
    standIn:SetFrameStrata(strata)
    standIn:SetFrameLevel(otf:GetFrameLevel() + 5)
    standIn:Hide()
    local header = CreateFrame("Frame", nil, standIn)
    header:SetPoint("TOPLEFT")
    header:SetSize(260, 26)
    standIn._header = header
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    title:SetPoint("LEFT", 7, 0)
    standIn._title = title
    local minBtn = CreateFrame("Button", nil, header)
    minBtn:SetSize(16, 16)
    minBtn:SetPoint("RIGHT", 1, 0)
    minBtn:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
    minBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        SetStandInCollapsed(standIn, not standIn._collapsed)
        EQT.RefreshZoneUI()
    end)
    header.MinimizeButton = minBtn
    if not EQT.Blizz() then
        local line = header:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(1)
        standIn._line = line
    end
    local msg = standIn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -6)
    msg:SetTextColor(0.6, 0.6, 0.6)
    msg:SetText(EllesmereUI.L("No quests in this zone"))
    standIn._msg = msg
    SetStandInCollapsed(standIn, false)
    EQT.zoneStandIn = standIn

    -- "Current Zone" toggle: accent checkbox + label.
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetFrameStrata(strata)
    btn:SetHeight(16)
    btn:Hide()
    local box = btn:CreateTexture(nil, "ARTWORK")
    box:SetSize(9, 9)
    box:SetPoint("LEFT")
    box:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    local fill = btn:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", box, 2, -2)
    fill:SetPoint("BOTTOMRIGHT", box, -2, 2)
    btn._fill = fill
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if not EQT.Blizz() then
        pcall(text.SetFont, text, EllesmereUI.GetFontPath("questTracker"), 10,
            EllesmereUI.GetFontOutlineFlag("questTracker"))
    end
    text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    text:SetText(EllesmereUI.L("Current Zone"))
    btn._text = text
    btn:SetWidth(13 + text:GetStringWidth())
    btn:SetScript("OnClick", function()
        EQT.Set("zoneFilter", not Cfg("zoneFilter"))
        EQT.ApplyZoneFilterSetting()
    end)
    btn:SetScript("OnEnter", function(self)
        EllesmereUI.ShowWidgetTooltip(self, "Untracks quests outside your current zone. Turning it off re-tracks them.")
    end)
    btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    EQT.zoneToggle = btn

    if not EQT.Blizz() then
        EllesmereUI.RegAccent({ type = "callback", fn = UpdateZoneLook })
    end

    -- Section show/hide happens inside Blizzard's layout pass: react a frame later.
    local refreshQueued = false
    local function QueueRefresh()
        if refreshQueued or not Cfg("zoneFilterButton") then return end
        refreshQueued = true
        C_Timer.After(0, function()
            refreshQueued = false
            EQT.RefreshZoneUI()
        end)
    end
    hooksecurefunc(qt, "Update", QueueRefresh)
    hooksecurefunc(otf, "SetCollapsed", QueueRefresh)
    EQT.QueueZoneUIRefresh = QueueRefresh
end

-- Options toggle, the in-tracker toggle and profile swaps all land here.
function EQT.ApplyZoneFilterSetting(waitForQuestLog)
    if Cfg("zoneFilterButton") then BuildZoneUI() end
    if EQT.zoneToggle then
        UpdateZoneLook()
        EQT.RefreshZoneUI()
    end
    zoneEventFrame:UnregisterAllEvents()
    if ZoneFilterOn() then
        zoneEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        zoneEventFrame:RegisterEvent("ZONE_CHANGED")
        zoneEventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    elseif not HasRemovedQuests() then
        return
    end
    if waitForQuestLog then
        zoneEventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    else
        SyncZoneFilter()
    end
end

local function InstallZoneFilter()
    if Cfg("zoneFilterButton") or HasRemovedQuests() then
        EQT.ApplyZoneFilterSetting(true)
    end
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function EQT.InitQoL()
    InstallSplashFrameFix()
    InstallAutoQuests()
    InstallQuestItemHotkey()
    InstallZoneFilter()
end
