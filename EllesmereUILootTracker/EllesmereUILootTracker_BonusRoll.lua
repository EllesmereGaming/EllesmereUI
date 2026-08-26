if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
if not (EllesmereUI and ns) then return end

local reminder
local pendingReminder

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
    local pool = ns.GetPool(sourceKey, specID)
    for _, goal in ipairs(ns.GetGoals(specID, false)) do
        if goal.sourceKey == sourceKey and goal.state == "open"
            and not (pool.knocked and pool.knocked[goal.itemID]) then
            return true
        end
    end
    return false
end

function ns.GetBonusRollPromptDecision(spellID)
    local profile = ns.GetProfile()
    local mode = profile and profile.bonusRollPromptMode or "show"
    if not ns.IsSeasonSupported() or IsSecret(spellID) then return end

    local prompt = FindPrompt(spellID)
    if not prompt then return end
    local source = ResolvePromptSource(prompt)
    if not source or (source.kind ~= "dungeon" and source.kind ~= "raid") then return end

    local difficultyID = PromptDifficulty(source, prompt)
    if source.kind == "raid" and not difficultyID then return end
    local specID = ns.ResolveSpecID()
    local policy = ns.GetBonusRollPolicy(source, specID, difficultyID)
    if policy == ns.BONUS_ROLL_ALWAYS then return end
    if policy == ns.BONUS_ROLL_NEVER then
        -- Explicit per-source Skip works without requiring a second setting.
        -- Minimize keeps a recovery path unless cancellation was requested.
        mode = mode == "cancel" and "cancel" or "minimize"
    else
        if mode ~= "minimize" and mode ~= "cancel" then return end
        if ns.HasOpenBonusRollGoal(source, specID, difficultyID) then return end
    end

    local duration = prompt.duration
    if IsSecret(duration) then duration = nil end
    duration = tonumber(duration)
    return mode, {
        spellID = spellID,
        source = source,
        difficultyID = difficultyID,
        expiresAt = duration and (GetTime() + duration) or nil,
    }
end

local function ClearReminder()
    pendingReminder = nil
    if reminder then reminder:Hide() end
end

local function RestoreBlizzardPrompt()
    local context = pendingReminder
    ClearReminder()
    if not context or not FindPrompt(context.spellID) then return end
    local frame = _G.BonusRollFrame
    if not frame then return end
    if ShowUIPanel then ShowUIPanel(frame) else frame:Show() end
end

local function CancelPendingPrompt()
    local context = pendingReminder
    ClearReminder()
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
        if not context or not FindPrompt(context.spellID) then ClearReminder(); return end
        local seconds = context.expiresAt and math.max(0, math.ceil(context.expiresAt - GetTime()))
        self.detail:SetText(seconds and (EllesmereUI.L("Bonus roll minimized") .. "  •  " .. seconds .. "s")
            or EllesmereUI.L("Bonus roll minimized"))
    end)
    frame:Hide()
    reminder = frame
    return frame
end

local function MinimizePrompt(context)
    local frame = _G.BonusRollFrame
    if not frame or not frame.Hide or not frame:IsShown() then return false end
    frame:Hide()
    pendingReminder = context
    local bar = CreateReminder()
    bar.title:SetText(context.source.name or EllesmereUI.L("Bonus Roll"))
    bar.detail:SetText(EllesmereUI.L("Bonus roll minimized"))
    bar:Show()
    return true
end

function ns.TryHandleBonusRollPrompt(spellID)
    local mode, context = ns.GetBonusRollPromptDecision(spellID)
    if not mode then return false end
    if mode == "cancel" then
        if not CancelSpellConfirmationPrompt then return false end
        return pcall(CancelSpellConfirmationPrompt, spellID)
    end
    return MinimizePrompt(context)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, spellID)
    if event == "SPELL_CONFIRMATION_PROMPT" then
        ClearReminder()
        -- Blizzard owns the underlying prompt. We only collapse its frame after
        -- it has been built, and keep a way back to the still-active prompt.
        C_Timer.After(0, function() ns.TryHandleBonusRollPrompt(spellID) end)
    else
        ClearReminder()
    end
end)
