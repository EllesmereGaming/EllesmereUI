local _, ns = ...
if not (EllesmereUI and ns) then return end

local reminder
local pendingReminder
local promptAttemptToken = 0
local testFrame
local StopPromptAttempts
local dismissedPromptKeysBySpell = {}
local lastDismissedSpellID

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function FindPrompt(spellID)
    if not GetSpellConfirmationPromptsInfo then return end
    local prompts = GetSpellConfirmationPromptsInfo()
    if type(prompts) ~= "table" then return end
    for _, prompt in ipairs(prompts) do
        if not IsSecret(prompt.spellID) and prompt.spellID == spellID then return prompt end
    end
end

local function PromptDifficulty(source, prompt)
    if source.kind ~= "raid" then return nil end
    local difficultyID = prompt and prompt.difficultyID
    if IsSecret(difficultyID) then difficultyID = nil end
    difficultyID = tonumber(difficultyID)
    if not difficultyID and GetBonusRollEncounterJournalLinkDifficulty then
        difficultyID = GetBonusRollEncounterJournalLinkDifficulty()
        if IsSecret(difficultyID) then difficultyID = nil end
        difficultyID = tonumber(difficultyID)
    end
    return difficultyID
end

local function PromptKey(spellID, prompt, source, difficultyID)
    local displayItemID = prompt and prompt.displayItemID
    if IsSecret(displayItemID) then displayItemID = nil end
    local sourceKey = ns.GetSourceKey(source, difficultyID)
    return table.concat({ tostring(spellID or 0), tostring(displayItemID or 0), tostring(sourceKey or "unknown") }, ":")
end

local function DismissedPromptStore()
    local state = ns.GetCharacterUIState()
    state.dismissedBonusRollPrompts = state.dismissedBonusRollPrompts or {}
    return state.dismissedBonusRollPrompts
end

local function MarkPromptDismissed(context)
    if not context or context.isTest or not context.promptKey then return end
    local remaining = context.expiresAt and math.max(0, context.expiresAt - GetTime()) or 0
    DismissedPromptStore()[context.promptKey] = time() + math.max(300, remaining + 5)
    dismissedPromptKeysBySpell[context.spellID] = context.promptKey
    lastDismissedSpellID = context.spellID
end

local function ClearDismissedPrompt(spellID)
    spellID = spellID or lastDismissedSpellID
    local key = dismissedPromptKeysBySpell[spellID]
    if not key then return end
    local store = DismissedPromptStore()
    store[key] = nil
    dismissedPromptKeysBySpell[spellID] = nil
    if lastDismissedSpellID == spellID then lastDismissedSpellID = nil end
end

local function ResolvePromptSource(prompt)
    local displayItemID = prompt and prompt.displayItemID
    if not IsSecret(displayItemID) then
        local source = ns.GetSourceByChest(displayItemID)
        if source then return source end
    end

    -- The displayed cache item is not guaranteed to be available on the first
    -- prompt frame. The active challenge map is a stable fallback after a run.
    local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetActiveChallengeMapID()
    if IsSecret(mapID) then mapID = nil end
    mapID = tonumber(mapID)
    local instanceID = GetInstanceInfo and select(8, GetInstanceInfo())
    if IsSecret(instanceID) then instanceID = nil end
    instanceID = tonumber(instanceID)
    if ns.GetSources then
        for _, source in ipairs(ns.GetSources("dungeon") or {}) do
            if source.challengeModeID == mapID then return source end
            if instanceID and instanceID > 0 and source.instanceID == instanceID then return source end
        end
    end
end

ns.ResolveBonusRollPromptSource = ResolvePromptSource

function ns.HasOpenBonusRollGoal(source, specID, difficultyID)
    local sourceKey = ns.GetSourceKey(source, difficultyID)
    if not sourceKey then return false end
    for _, goal in ipairs(ns.GetGoals(specID, false)) do
        if goal.sourceKey == sourceKey and goal.state == "open"
            and not ns.IsPoolItemKnocked(sourceKey, goal.itemID, specID) then
            return true
        end
    end
    return false
end

function ns.GetBonusRollPromptDecision(spellID)
    local profile = ns.GetProfile()
    local mode = profile and profile.bonusRollPromptMode or "show"
    local debug = { time = GetTime(), configuredMode = mode, reason = "evaluating" }
    ns.lastBonusRollDebug = debug
    if not ns.IsSeasonSupported() then debug.reason = "unsupported_season"; return end
    if IsSecret(spellID) then debug.reason = "secret_spell"; return end
    debug.spellID = spellID

    local prompt = FindPrompt(spellID)
    if not prompt then debug.reason = "prompt_not_ready"; return end
    if not IsSecret(prompt.displayItemID) then debug.displayItemID = prompt.displayItemID end
    local source = ResolvePromptSource(prompt)
    if not source or (source.kind ~= "dungeon" and source.kind ~= "raid") then
        debug.reason = "unknown_source"
        return
    end
    debug.sourceKind = source.kind
    debug.sourceID = source.kind == "raid" and source.encounterID or source.challengeModeID
    debug.sourceName = source.name

    local difficultyID = PromptDifficulty(source, prompt)
    if source.kind == "raid" and not difficultyID then debug.reason = "unknown_raid_difficulty"; return end
    debug.difficultyID = difficultyID
    local duration = prompt.duration
    if IsSecret(duration) then duration = nil end
    duration = tonumber(duration)
    local expiresAt = duration and (GetTime() + duration) or nil
    local promptKey = PromptKey(spellID, prompt, source, difficultyID)
    debug.promptKey = promptKey
    local dismissedStore = DismissedPromptStore()
    local dismissedUntil = dismissedStore[promptKey]
    if dismissedUntil and dismissedUntil > time() then
        debug.reason = "dismissed_prompt"
        return "cancel", {
            spellID = spellID, source = source, difficultyID = difficultyID,
            expiresAt = expiresAt, promptKey = promptKey, dismissed = true,
        }
    elseif dismissedUntil then
        dismissedStore[promptKey] = nil
    end
    local specID = ns.ResolveSpecID()
    local policy = ns.GetBonusRollPolicy(source, specID, difficultyID)
    debug.specID = specID
    debug.policy = policy
    if policy == ns.BONUS_ROLL_ALWAYS then debug.reason = "explicit_always"; return end
    if policy == ns.BONUS_ROLL_NEVER then
        -- Explicit per-source Skip works without requiring a second setting.
        -- Minimize keeps a recovery path unless cancellation was requested.
        mode = mode == "cancel" and "cancel" or "minimize"
    else
        if mode ~= "minimize" and mode ~= "cancel" then debug.reason = "auto_show_mode"; return end
        if ns.HasOpenBonusRollGoal(source, specID, difficultyID) then
            debug.reason = "auto_wishlist_goal"
            return
        end
    end

    debug.reason = mode
    return mode, {
        spellID = spellID,
        source = source,
        difficultyID = difficultyID,
        expiresAt = expiresAt,
        promptKey = promptKey,
    }
end

local function ClearReminder()
    pendingReminder = nil
    if reminder then reminder:Hide() end
end

local function RestoreBlizzardPrompt()
    local context = pendingReminder
    ClearReminder()
    if not context then return end
    if not context.isTest and not FindPrompt(context.spellID) then return end
    local frame = context.frame or _G.BonusRollFrame
    if not frame then return end
    if ShowUIPanel then ShowUIPanel(frame) else frame:Show() end
end

local function CancelPendingPrompt()
    local context = pendingReminder
    ClearReminder()
    if context and context.isTest then
        if context.frame then context.frame:Hide() end
        return
    end
    MarkPromptDismissed(context)
    if StopPromptAttempts then StopPromptAttempts() end
    local frame = _G.BonusRollFrame
    if frame and frame.Hide and frame:IsShown() then frame:Hide() end
    if context and CancelSpellConfirmationPrompt then
        pcall(CancelSpellConfirmationPrompt, context.spellID)
    end
end

local function CreateReminder()
    if reminder then return reminder end
    local frame = CreateFrame("Frame", "EULTBonusRollReminder", UIParent, "BackdropTemplate")
    frame:SetSize(390, 58)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 225)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.018, 0.024, 0.033, 0.96)
    if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(frame, 1, 0.05, 0.82, 0.62, EllesmereUI.PP) end

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38); icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_TreasureChest04b")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 11, "")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetTextColor(0.05, 0.82, 0.62, 1)
    frame.title = title
    local detail = frame:CreateFontString(nil, "OVERLAY")
    detail:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 9, "")
    detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 3)
    detail:SetTextColor(0.68, 0.7, 0.75, 1)
    frame.detail = detail

    local show = CreateFrame("Button", nil, frame)
    show:SetSize(66, 28); show:SetPoint("RIGHT", frame, "RIGHT", -82, 0)
    EllesmereUI.MakeStyledButton(show, EllesmereUI.L("Show"), 10, EllesmereUI.RB_COLOURS, RestoreBlizzardPrompt)
    local cancel = CreateFrame("Button", nil, frame)
    cancel:SetSize(66, 28); cancel:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    EllesmereUI.MakeStyledButton(cancel, EllesmereUI.L("Cancel"), 10, EllesmereUI.RB_COLOURS, CancelPendingPrompt)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        local context = pendingReminder
        if not context or (not context.isTest and not FindPrompt(context.spellID)) then
            ClearReminder()
            return
        end
        local seconds = context.expiresAt and math.max(0, math.ceil(context.expiresAt - GetTime()))
        self.detail:SetText(seconds and (EllesmereUI.L("Bonus roll minimized") .. "  -  " .. seconds .. "s")
            or EllesmereUI.L("Bonus roll minimized"))
    end)
    frame:Hide()
    reminder = frame
    return frame
end

local function MinimizePrompt(context)
    local frame = context.frame or _G.BonusRollFrame
    if not frame or not frame.Hide or not frame:IsShown() then return false end
    frame:Hide()
    pendingReminder = context
    local bar = CreateReminder()
    bar.title:SetText(context.source.name or EllesmereUI.L("Bonus Roll"))
    bar.detail:SetText(EllesmereUI.L("Bonus roll minimized"))
    bar:Show()
    return true
end

local function FindExplicitSkipSource()
    local specID = ns.ResolveSpecID()
    for _, source in ipairs(ns.GetSources("dungeon") or {}) do
        if ns.GetBonusRollPolicy(source, specID) == ns.BONUS_ROLL_NEVER then
            return source, specID
        end
    end
    local difficultyID = tonumber(ns.GetProfile().raidDifficulty) or 16
    for _, source in ipairs(ns.GetSources("raid") or {}) do
        if ns.GetBonusRollPolicy(source, specID, difficultyID) == ns.BONUS_ROLL_NEVER then
            return source, specID, difficultyID
        end
    end
end

local function CreateTestFrame()
    if testFrame then return testFrame end
    local frame = CreateFrame("Frame", "EULTBonusRollTestFrame", UIParent, "BackdropTemplate")
    frame:SetSize(330, 120)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 225)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0.035, 0.04, 0.055, 0.98)
    if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(frame, 1, 0.85, 0.68, 0.15, EllesmereUI.PP) end
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 12, "")
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText(EllesmereUI.L("Simulated Blizzard Bonus Roll"))
    frame.title = title
    local detail = frame:CreateFontString(nil, "OVERLAY")
    detail:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 10, "")
    detail:SetPoint("CENTER", frame, "CENTER", 0, 2)
    frame.detail = detail
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(100, 28)
    close:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    EllesmereUI.MakeStyledButton(close, EllesmereUI.L("Close test"), 10, EllesmereUI.RB_COLOURS,
        function() frame:Hide() end)
    frame:Hide()
    testFrame = frame
    return frame
end

function ns.RunBonusRollDebugTest()
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local source, specID, difficultyID = FindExplicitSkipSource()
    if not source then return false, "no_skip_source" end

    StopPromptAttempts()
    ClearReminder()
    local frame = CreateTestFrame()
    frame.detail:SetText(source.name or EllesmereUI.L("Bonus Roll"))
    frame:Hide()
    local context = {
        isTest = true,
        frame = frame,
        spellID = 0,
        source = source,
        difficultyID = difficultyID,
        expiresAt = GetTime() + 10,
    }
    local configuredMode = ns.GetProfile().bonusRollPromptMode
    local cancelTest = configuredMode == "cancel"
    ns.lastBonusRollDebug = {
        time = GetTime(), configuredMode = configuredMode,
        reason = "test_waiting", sourceKind = source.kind,
        sourceID = source.kind == "raid" and source.encounterID or source.challengeModeID,
        sourceName = source.name, specID = specID, policy = ns.BONUS_ROLL_NEVER,
    }

    local attempts = 0
    local function Attempt()
        attempts = attempts + 1
        if cancelTest and frame:IsShown() then
            frame:Hide()
            ClearReminder()
            ns.lastBonusRollDebug.reason = "test_cancelled"
            ns.lastBonusRollDebug.handled = true
            ns.lastBonusRollDebug.attempt = attempts
            print("|cff0cd29fEllesmereUI Loot Tracker|r: "
                .. EllesmereUI.L("Bonus Roll Skip test passed: dialog cancelled."))
            return
        end
        if MinimizePrompt(context) then
            ns.lastBonusRollDebug.reason = "test_minimized"
            ns.lastBonusRollDebug.handled = true
            ns.lastBonusRollDebug.attempt = attempts
            return
        end
        if attempts < 20 then C_Timer.After(0.1, Attempt) end
    end
    -- Deliberately show after the first checks to reproduce Blizzard's timing.
    C_Timer.After(0.35, function() frame:Show() end)
    C_Timer.After(0, Attempt)
    return true, source.name
end

function ns.TryHandleBonusRollPrompt(spellID, cancelAlreadySent)
    local mode, context = ns.GetBonusRollPromptDecision(spellID)
    if not mode then return false end
    if mode == "cancel" then
        MarkPromptDismissed(context)
        local cancelSent = cancelAlreadySent
        if not cancelSent and CancelSpellConfirmationPrompt then
            cancelSent = pcall(CancelSpellConfirmationPrompt, spellID)
        end
        local frame = _G.BonusRollFrame
        if frame and frame.Hide and frame:IsShown() then frame:Hide() end
        if ns.lastBonusRollDebug then
            ns.lastBonusRollDebug.handled = true
            ns.lastBonusRollDebug.cancelSent = not not cancelSent
        end
        -- Keep watching briefly: Blizzard may construct/show the frame after a
        -- successful cancellation call. The API itself is sent only once.
        return true, true, cancelSent
    end
    local handled = MinimizePrompt(context)
    if ns.lastBonusRollDebug then
        ns.lastBonusRollDebug.handled = handled
        if not handled then ns.lastBonusRollDebug.reason = "frame_not_shown" end
    end
    return handled
end

StopPromptAttempts = function()
    promptAttemptToken = promptAttemptToken + 1
end

local function SchedulePromptHandling(spellID)
    StopPromptAttempts()
    local token = promptAttemptToken
    local attempts = 0
    local cancelSent = false
    local function Attempt()
        if token ~= promptAttemptToken then return end
        attempts = attempts + 1
        local handled, keepWatching, sent = ns.TryHandleBonusRollPrompt(spellID, cancelSent)
        cancelSent = cancelSent or sent
        if handled and not keepWatching then
            if ns.lastBonusRollDebug then ns.lastBonusRollDebug.attempt = attempts end
            return
        end
        if ns.lastBonusRollDebug then ns.lastBonusRollDebug.attempt = attempts end
        -- Blizzard and UI-skin handlers can show BonusRollFrame after the event
        -- callback. Retry briefly instead of depending on frame-handler order.
        if attempts < 20 then C_Timer.After(0.1, Attempt) end
    end
    C_Timer.After(0, Attempt)
end

local startHooked
local function HookBonusRollStart()
    if startHooked or type(_G.BonusRollFrame_StartBonusRoll) ~= "function"
        or not hooksecurefunc then return end
    startHooked = true
    hooksecurefunc("BonusRollFrame_StartBonusRoll", function(spellID)
        SchedulePromptHandling(spellID)
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, spellID)
    if event == "ADDON_LOADED" then
        HookBonusRollStart()
    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        ClearReminder()
        SchedulePromptHandling(spellID)
    else
        StopPromptAttempts()
        ClearReminder()
        -- A timeout ends only the matching prompt. Clearing the whole persisted
        -- store allowed an unrelated, already dismissed prompt to reappear on
        -- the next zone/login transition.
        if event == "SPELL_CONFIRMATION_TIMEOUT" then ClearDismissedPrompt(spellID) end
    end
end)

HookBonusRollStart()

SLASH_EULTBONUSTEST1 = "/eulttestbonus"
SlashCmdList.EULTBONUSTEST = function()
    local ok, detail = ns.RunBonusRollDebugTest()
    if ok then
        print("|cff0cd29fEllesmereUI Loot Tracker|r: "
            .. EllesmereUI.Lf("Testing delayed Skip for %s.", detail or "?"))
    elseif detail == "no_skip_source" then
        print("|cff0cd29fEllesmereUI Loot Tracker|r: "
            .. EllesmereUI.L("Mark at least one dungeon or raid boss as Bonus Roll: Skip first."))
    else
        print("|cff0cd29fEllesmereUI Loot Tracker|r: "
            .. EllesmereUI.L("Bonus Roll test is unavailable during combat."))
    end
end
