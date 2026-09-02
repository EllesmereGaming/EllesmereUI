local profile = { bonusRollPromptMode = "cancel" }
local goals = {}
local pool = { knocked = {} }
local prompt = { spellID = 42, displayItemID = 99, duration = 20 }
local policy = "auto"
local cancelled
local eventHandler
local styledButtons = {}
local bonusRollStartHook
local characterUIState = {}
local capturedPrompt

local function Noop() end
local function Region()
    return setmetatable({}, { __index = function() return Noop end })
end

EllesmereUI = {
    L = function(value) return value end,
    MakeBorder = Noop,
    MakeStyledButton = function(button, label, _, _, callback)
        button.click = callback
        styledButtons[label] = button
    end,
    RB_COLOURS = {},
}
UIParent = {}
SlashCmdList = {}
C_Timer = { After = function(_, callback) callback() end }
function GetTime() return 100 end
function time() return 1000 end
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, 0 end
function GetSpellConfirmationPromptsInfo() return { prompt } end
function CancelSpellConfirmationPrompt(spellID) cancelled = spellID end
function BonusRollFrame_StartBonusRoll() end
function hooksecurefunc(name, callback)
    if name == "BonusRollFrame_StartBonusRoll" then bonusRollStartHook = callback end
end
function CreateFrame(_, name)
    local frame = {
        shown = true,
        RegisterEvent = Noop,
        SetSize = Noop, SetPoint = Noop, SetFrameStrata = Noop, SetClampedToScreen = Noop,
        SetBackdrop = Noop, SetBackdropColor = Noop,
        CreateTexture = Region, CreateFontString = Region,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        IsShown = function(self) return self.shown end,
        SetScript = function(self, script, callback)
            if script == "OnEvent" then eventHandler = callback end
            self[script] = callback
        end,
    }
    if name then _G[name] = frame end
    return frame
end

local dungeon = { kind = "dungeon", challengeModeID = 7, instanceID = 70, name = "Test Dungeon" }
local dungeon2 = { kind = "dungeon", challengeModeID = 9, instanceID = 90, name = "New Dungeon" }
local raid = { kind = "raid", encounterID = 8, name = "Test Boss" }
local source = dungeon
local ns = {
    BONUS_ROLL_AUTO = "auto",
    BONUS_ROLL_ALWAYS = "always",
    BONUS_ROLL_NEVER = "never",
    GetProfile = function() return profile end,
    GetCharacterUIState = function() return characterUIState end,
    IsSeasonSupported = function() return true end,
    GetSourceByChest = function(itemID)
        if itemID == 99 then return source end
        if itemID == 101 then return dungeon2 end
    end,
    GetSources = function(kind) return kind == "dungeon" and { dungeon, dungeon2 } or { raid } end,
    ResolveSpecID = function() return 70 end,
    GetBonusRollPolicy = function() return policy end,
    GetSourceKey = function(value, difficultyID)
        if value.kind == "raid" then return "raid:" .. value.encounterID .. ":" .. difficultyID end
        return "dungeon:" .. value.challengeModeID
    end,
    GetPool = function() return pool end,
    IsPoolItemKnocked = function(_, itemID) return pool.knocked[itemID] end,
    GetGoals = function() return goals end,
    CaptureBonusRollPrompt = function(spellID, readyPrompt, readySource, difficultyID)
        capturedPrompt = { spellID, readyPrompt, readySource, difficultyID }
    end,
}

local chunk = assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_BonusRoll.lua"))
chunk("EllesmereUILootTracker", ns)
assert(SLASH_EULTBONUSTEST1 == "/eulttestbonus" and type(SlashCmdList.EULTBONUSTEST) == "function",
    "bonus-roll debug slash command was not registered")

local mode = ns.GetBonusRollPromptDecision(42)
assert(mode == "cancel", "empty Auto source should follow the configured prompt mode")
assert(capturedPrompt and capturedPrompt[1] == 42 and capturedPrompt[2] == prompt
    and capturedPrompt[3] == dungeon,
    "ready prompt was not handed back to core roll tracking")
eventHandler(nil, "SPELL_CONFIRMATION_PROMPT", 42)
assert(cancelled == 42, "cancel mode must use Blizzard's cancellation API")
eventHandler(nil, "SPELL_CONFIRMATION_TIMEOUT")

cancelled = nil
goals = { { sourceKey = "dungeon:7", itemID = 123, state = "open" } }
assert(not ns.GetBonusRollPromptDecision(42), "Auto must preserve a prompt with an open wishlist goal")
assert(not ns.TryHandleBonusRollPrompt(42) and not cancelled, "wanted prompt was cancelled")

policy = "never"
assert(ns.GetBonusRollPromptDecision(42) == "cancel", "Skip must override an open wishlist goal")
policy = "always"
goals = {}
assert(not ns.GetBonusRollPromptDecision(42), "Bonus Roll must preserve the prompt without wishlist goals")

policy = "auto"
goals = { { sourceKey = "dungeon:7", itemID = 123, state = "open" } }
pool.knocked[123] = true
assert(ns.GetBonusRollPromptDecision(42) == "cancel", "knocked-out wishlist item is not an available target")

profile.bonusRollPromptMode = "show"
policy = "auto"
assert(not ns.GetBonusRollPromptDecision(42), "show mode must preserve Auto prompts")
policy = "never"
assert(ns.GetBonusRollPromptDecision(42) == "minimize",
    "explicit Skip must minimize even when Auto prompts use Blizzard's frame")
profile.bonusRollPromptMode = "minimize"
assert(ns.GetBonusRollPromptDecision(42) == "minimize", "minimize mode decision is incorrect")

goals = { { sourceKey = "dungeon:7", itemID = 123, state = "open" } }
pool.knocked = {}
policy = "auto"
profile.bonusRollPromptMode = "explicit_minimize"
assert(ns.GetBonusRollPromptDecision(42) == "minimize",
    "explicit minimize must ignore wishlist and planner goals")
assert(ns.lastBonusRollDebug.reason == "auto_not_explicit",
    "explicit minimize did not report its policy reason")
policy = "always"
assert(not ns.GetBonusRollPromptDecision(42),
    "explicit Bonus Roll: Yes must preserve the prompt in explicit mode")
policy = "auto"
profile.bonusRollPromptMode = "explicit_cancel"
assert(ns.GetBonusRollPromptDecision(42) == "cancel",
    "explicit cancel must suppress unmarked Auto sources")

profile.bonusRollPromptMode = "minimize"
source = dungeon
policy = "never"
goals = {}
pool.knocked = {}
BonusRollFrame = CreateFrame("Frame", "BonusRollFrame")
assert(ns.TryHandleBonusRollPrompt(42), "minimize mode did not handle the prompt")
assert(not BonusRollFrame:IsShown() and EULTBonusRollReminder:IsShown(), "minimize mode did not swap frames")
assert(styledButtons.Show and styledButtons.Cancel, "reminder recovery controls are missing")
styledButtons.Show.click()
assert(BonusRollFrame:IsShown() and not EULTBonusRollReminder:IsShown(), "Show did not restore Blizzard's frame")

BonusRollFrame.shown = true
assert(bonusRollStartHook, "Blizzard bonus-roll start hook was not installed")
bonusRollStartHook(42)
assert(not BonusRollFrame:IsShown(), "late Blizzard frame show was not minimized by the start hook")
assert(EULTBonusRollReminder:IsShown(), "late minimized prompt did not show its reminder")
styledButtons.Cancel.click()
assert(not EULTBonusRollReminder:IsShown(), "dismissing a minimized prompt left its reminder visible")
assert(next(characterUIState.dismissedBonusRollPrompts or {}),
    "dismissed prompt was not persisted in per-character data")
eventHandler(nil, "PLAYER_ENTERING_WORLD")
BonusRollFrame.shown = true
bonusRollStartHook(42)
assert(not BonusRollFrame:IsShown() and not EULTBonusRollReminder:IsShown(),
    "a dismissed prompt resurfaced after changing instances")
assert(ns.lastBonusRollDebug.reason == "dismissed_prompt",
    "resurfaced prompt was not recognized as the dismissed source prompt")
policy = "always"
assert(not ns.GetBonusRollPromptDecision(42),
    "Bonus Roll: Yes must immediately override an earlier dismissal")
assert(not next(characterUIState.dismissedBonusRollPrompts or {}),
    "explicit opt-in did not clear the stale dismissed-prompt entry")
policy = "never"
prompt.displayItemID = 101
assert(ns.GetBonusRollPromptDecision(42) == "minimize",
    "dismissing one source must not suppress a new source prompt")
prompt.displayItemID = 99
eventHandler(nil, "BONUS_ROLL_RESULT")

prompt.displayItemID = 100
C_ChallengeMode = { GetActiveChallengeMapID = function() return 7 end }
assert(ns.ResolveBonusRollPromptSource(prompt) == dungeon,
    "active challenge map must recover a dungeon when the cache item is unknown")
C_ChallengeMode = nil
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, 70 end
assert(ns.ResolveBonusRollPromptSource(prompt) == dungeon,
    "instance ID must recover a dungeon after the active challenge map resets")
function GetInstanceInfo() return nil, nil, nil, nil, nil, nil, nil, 0 end
prompt.displayItemID = 99

local testStarted, testSource = ns.RunBonusRollDebugTest()
assert(testStarted and testSource == dungeon.name, "debug test did not use an explicit Skip source")
assert(ns.lastBonusRollDebug.reason == "test_minimized" and ns.lastBonusRollDebug.handled,
    "debug test did not minimize its delayed simulated frame")
assert(not EULTBonusRollTestFrame:IsShown() and EULTBonusRollReminder:IsShown(),
    "debug test did not replace its simulated frame with the reminder")
styledButtons.Show.click()
assert(EULTBonusRollTestFrame:IsShown(), "debug test reminder did not restore the simulated frame")

profile.bonusRollPromptMode = "cancel"
local cancelTestStarted = ns.RunBonusRollDebugTest()
assert(cancelTestStarted and ns.lastBonusRollDebug.reason == "test_cancelled",
    "cancel debug test did not cancel its delayed simulated frame")
assert(not EULTBonusRollTestFrame:IsShown() and not EULTBonusRollReminder:IsShown(),
    "cancel debug test left a dialog or minimized reminder visible")

BonusRollFrame.shown = true
cancelled = nil
eventHandler(nil, "SPELL_CONFIRMATION_PROMPT", 42)
assert(cancelled == 42 and not BonusRollFrame:IsShown(),
    "real cancel path did not send cancellation and suppress its frame")
profile.bonusRollPromptMode = "minimize"

source = raid
policy = "auto"
prompt.difficultyID = nil
GetBonusRollEncounterJournalLinkDifficulty = nil
assert(not ns.GetBonusRollPromptDecision(42), "unknown raid difficulty must be preserved")
prompt.difficultyID = 16
goals = {}
pool.knocked = {}
assert(ns.GetBonusRollPromptDecision(42) == "minimize", "known empty raid source should be minimized")

prompt.displayItemID = 100
assert(not ns.GetBonusRollPromptDecision(42), "unknown source must be preserved")

print("loot bonus roll policy ok")
