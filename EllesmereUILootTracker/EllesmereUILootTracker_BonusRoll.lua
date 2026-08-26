if EUI_CLIENT_BLOCKED then return end
local ADDON_NAME, ns = ...
if not (EllesmereUI and ns) then return end

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

function ns.ShouldAutoDismissBonusRollPrompt(spellID)
    local profile = ns.GetProfile()
    if not (profile and profile.autoDismissEmptyBonusRoll) then return false end
    if not CancelSpellConfirmationPrompt or not ns.IsSeasonSupported() then return false end
    if IsSecret(spellID) then return false end

    local prompt = FindPrompt(spellID)
    if not prompt or IsSecret(prompt.displayItemID) then return false end
    local source = ns.GetSourceByChest(prompt.displayItemID)
    if not source or (source.kind ~= "dungeon" and source.kind ~= "raid") then return false end

    local difficultyID = PromptDifficulty(source, prompt)
    if source.kind == "raid" and not difficultyID then return false end
    local specID = ns.ResolveSpecID()
    return not ns.HasOpenBonusRollGoal(source, specID, difficultyID)
end

function ns.TryAutoDismissBonusRoll(spellID)
    if not ns.ShouldAutoDismissBonusRollPrompt(spellID) then return false end
    local ok = pcall(CancelSpellConfirmationPrompt, spellID)
    return ok
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:SetScript("OnEvent", function(_, _, spellID)
    -- Let Blizzard create its standard frame first, then re-check that this
    -- exact prompt is still active before cancelling it through the game API.
    C_Timer.After(0, function() ns.TryAutoDismissBonusRoll(spellID) end)
end)
