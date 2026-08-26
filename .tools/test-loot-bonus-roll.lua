local profile = { autoDismissEmptyBonusRoll = true }
local goals = {}
local pool = { knocked = {} }
local prompt = { spellID = 42, displayItemID = 99 }
local cancelled
local eventHandler

EllesmereUI = {}
C_Timer = { After = function(_, callback) callback() end }
function GetSpellConfirmationPromptsInfo() return { prompt } end
function CancelSpellConfirmationPrompt(spellID) cancelled = spellID end
function CreateFrame()
    return {
        RegisterEvent = function(_, event) assert(event == "SPELL_CONFIRMATION_PROMPT") end,
        SetScript = function(_, _, callback) eventHandler = callback end,
    }
end

local dungeon = { kind = "dungeon", challengeModeID = 7 }
local raid = { kind = "raid", encounterID = 8 }
local source = dungeon
local ns = {
    GetProfile = function() return profile end,
    IsSeasonSupported = function() return true end,
    GetSourceByChest = function(itemID) return itemID == 99 and source or nil end,
    ResolveSpecID = function() return 70 end,
    GetSourceKey = function(value, difficultyID)
        if value.kind == "raid" then return "raid:" .. value.encounterID .. ":" .. difficultyID end
        return "dungeon:" .. value.challengeModeID
    end,
    GetPool = function() return pool end,
    GetGoals = function() return goals end,
}

local chunk = assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_BonusRoll.lua"))
chunk("EllesmereUILootTracker", ns)

assert(ns.ShouldAutoDismissBonusRollPrompt(42), "empty recognized source should be dismissed")
eventHandler(nil, "SPELL_CONFIRMATION_PROMPT", 42)
assert(cancelled == 42, "dismissal must use Blizzard's cancellation API")

cancelled = nil
goals = { { sourceKey = "dungeon:7", itemID = 123, state = "open" } }
assert(not ns.ShouldAutoDismissBonusRollPrompt(42), "open wishlist goal must preserve the prompt")
assert(not ns.TryAutoDismissBonusRoll(42) and not cancelled, "wanted prompt was cancelled")

pool.knocked[123] = true
assert(ns.ShouldAutoDismissBonusRollPrompt(42), "knocked-out wishlist item is not an available roll target")

profile.autoDismissEmptyBonusRoll = false
assert(not ns.ShouldAutoDismissBonusRollPrompt(42), "disabled option must never dismiss")
profile.autoDismissEmptyBonusRoll = true

source = raid
prompt.difficultyID = nil
GetBonusRollEncounterJournalLinkDifficulty = nil
assert(not ns.ShouldAutoDismissBonusRollPrompt(42), "unknown raid difficulty must be preserved")
prompt.difficultyID = 16
goals = {}
pool.knocked = {}
assert(ns.ShouldAutoDismissBonusRollPrompt(42), "known empty raid source should be dismissed")

prompt.displayItemID = 100
assert(not ns.ShouldAutoDismissBonusRollPrompt(42), "unknown source must be preserved")

print("loot bonus roll dismissal ok")
