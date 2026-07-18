-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_QoL.lua
--
-- QoL layer: auto-accept, auto-turn-in, quest-item hotkey, SplashFrame
-- taint-free OnHide clone. Everything here is combat-gated.
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
local function InstallAutoQuests()
    local autoFrame = CreateFrame("Frame")
    local autoPreventNPCGUID = nil
    autoFrame:RegisterEvent("QUEST_DETAIL")
    autoFrame:RegisterEvent("QUEST_COMPLETE")
    autoFrame:RegisterEvent("QUEST_AUTOCOMPLETE")
    autoFrame:RegisterEvent("GOSSIP_SHOW")
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local aidx = #EQT._eventFrames + 1
    EQT._eventFrames[aidx] = autoFrame
    EQT._eventRegistrations[aidx] = {"QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_AUTOCOMPLETE", "GOSSIP_SHOW"}
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
                    local available = C_GossipInfo.GetAvailableQuests()
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

        if event == "QUEST_AUTOCOMPLETE" then
            local qID = ...
            if qID and ShowQuestComplete and type(ShowQuestComplete) == "function" then
                pcall(ShowQuestComplete, qID)
            end
            return
        end

        if event == "QUEST_DETAIL" then
            if not Cfg("autoAccept") then return end
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
-- Quest-item hotkey. SecureActionButton bound to the player's current
-- quest item. Uses SecureHandlerAttributeTemplate so the binding flip is
-- performed entirely in the restricted environment (no taint).
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

local function InstallQuestItemHotkey()
    local qItemBtn = CreateFrame("Button", "EUI_QuestItemHotkeyBtn", UIParent,
        "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    qItemBtn:SetSize(32, 32)
    qItemBtn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    qItemBtn:SetAlpha(0)
    qItemBtn:EnableMouse(false)
    qItemBtn:RegisterForClicks("LeftButtonUp")

    local function InitSecureAttributes()
        qItemBtn:SetAttribute("type", "item")
        qItemBtn:SetAttribute("_onattributechanged", [[
            if name == 'item' then
                self:ClearBindings()
                if value then
                    local key1, key2 = GetBindingKey('EUI_QUESTITEM')
                    if key1 then self:SetBindingClick(false, key1, self, 'LeftButton') end
                    if key2 then self:SetBindingClick(false, key2, self, 'LeftButton') end
                end
            end
        ]])
    end
    if InCombatLockdown() then
        local initFrame = CreateFrame("Frame")
        initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        initFrame:SetScript("OnEvent", function(f)
            f:UnregisterAllEvents()
            InitSecureAttributes()
            if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
            if EQT.UpdateQuestItemAttribute then EQT.UpdateQuestItemAttribute() end
        end)
    else
        InitSecureAttributes()
    end

    EQT.qItemBtn = qItemBtn

    local _applyingQuestItemHotkey = false
    local function ApplyQuestItemHotkey()
        if InCombatLockdown() then return end
        if _applyingQuestItemHotkey then return end
        _applyingQuestItemHotkey = true

        local ok, err = pcall(function()
            local key = Cfg("questItemHotkey")
            local old1, old2 = GetBindingKey("EUI_QUESTITEM")
            local hasOld = old1 or old2
            local hasNew = key and key ~= ""
            if not hasOld and not hasNew then return end

            local changed = false
            if hasOld then
                if old1 and old1 ~= key then SetBinding(old1); changed = true end
                if old2 and old2 ~= key then SetBinding(old2); changed = true end
            end
            if hasNew then
                local alreadyBound = (old1 == key or old2 == key)
                if not alreadyBound then
                    SetBinding(key, "EUI_QUESTITEM")
                    changed = true
                end
            end
            if changed then
                local bindingSet = GetCurrentBindingSet()
                if bindingSet and bindingSet >= 1 and bindingSet <= 2 then
                    SaveBindings(bindingSet)
                end
            end

            local cur = qItemBtn:GetAttribute("item")
            qItemBtn:SetAttribute("item", nil)
            qItemBtn:SetAttribute("item", cur)
        end)

        _applyingQuestItemHotkey = false
        if not ok and err then geterrorhandler()(err) end
    end
    EQT.ApplyQuestItemHotkey = ApplyQuestItemHotkey

    _G["BINDING_NAME_EUI_QUESTITEM"] = "Use Quest Item"

    local cachedName = nil
    local dirty = true

    local function UpdateQuestItemAttribute()
        if InCombatLockdown() then return end
        if not dirty then return end
        dirty = false
        local found = ScanForQuestItem()
        if found ~= cachedName then
            cachedName = found
            qItemBtn:SetAttribute("item", found)
        end
    end
    EQT.UpdateQuestItemAttribute = UpdateQuestItemAttribute

    local qItemFrame = CreateFrame("Frame")
    qItemFrame:RegisterEvent("QUEST_LOG_UPDATE")
    qItemFrame:RegisterEvent("QUEST_ACCEPTED")
    qItemFrame:RegisterEvent("QUEST_REMOVED")
    qItemFrame:RegisterEvent("QUEST_TURNED_IN")
    qItemFrame:RegisterEvent("UPDATE_BINDINGS")
    qItemFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local idx = #EQT._eventFrames + 1
    EQT._eventFrames[idx] = qItemFrame
    EQT._eventRegistrations[idx] = {"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED"}
    qItemFrame:SetScript("OnEvent", function(_, event)
        if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            ApplyQuestItemHotkey()
            dirty = true
            UpdateQuestItemAttribute()
            return
        end
        if event == "UPDATE_BINDINGS" then
            local cur = qItemBtn:GetAttribute("item")
            qItemBtn:SetAttribute("item", nil)
            qItemBtn:SetAttribute("item", cur)
            return
        end
        if not Cfg("questItemHotkey") then return end
        dirty = true
        UpdateQuestItemAttribute()
    end)

    C_Timer.After(1.5, function()
        if InCombatLockdown() then return end
        ApplyQuestItemHotkey()
        UpdateQuestItemAttribute()
    end)
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function EQT.InitQoL()
    InstallSplashFrameFix()
    InstallAutoQuests()
    InstallQuestItemHotkey()
end
