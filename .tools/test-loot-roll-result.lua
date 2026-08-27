local eventHandler
local timers = {}

local function Noop() end

EllesmereUI = {
    _ModuleNS = {},
    L = function(value) return value end,
    Lite = {
        NewDB = function(_, defaults) return defaults end,
    },
}
SlashCmdList = {}
function CreateFrame()
    return {
        RegisterEvent = Noop,
        SetScript = function(_, script, callback)
            if script == "OnEvent" then eventHandler = callback end
        end,
    }
end
function GetTime() return 100 end
function time() return 1000 end
function GetLootSpecialization() return 70 end

C_MythicPlus = { GetCurrentSeason = function() return 18 end }
C_SeasonInfo = { GetCurrentDisplaySeasonID = function() return 2 end }
C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}
C_Item = {
    GetItemInfoInstant = function() return 123 end,
    GetDetailedItemLevelInfo = function() return 311 end,
}

local source = { kind = "dungeon", challengeModeID = 7, chestItemID = 99, name = "Test Dungeon" }
local catalogInvalidations = 0
local ns = {
    SUPPORTED_SEASON_ID = 18,
    SUPPORTED_DISPLAY_SEASON_ID = 2,
    SEASON_DATA_REVISION = 1,
    GetMPlusTargetLevel = function() return 311 end,
    DungeonKey = function(id) return "dungeon:" .. id end,
    RaidKey = function(id, difficultyID) return "raid:" .. id .. ":" .. difficultyID end,
    GetSourceByChest = function(itemID) return itemID == 99 and source or nil end,
    GetCatalog = function() return {} end,
    ReadRemainingNames = function() return nil end,
    InvalidateCatalog = function() catalogInvalidations = catalogInvalidations + 1 end,
}

function GetSpellConfirmationPromptsInfo()
    -- Exercise the direct SPELL_CONFIRMATION_PROMPT event fallback.
    return {}
end

local chunk = assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker.lua"))
chunk("EllesmereUILootTracker", ns)
eventHandler(nil, "ADDON_LOADED", "EllesmereUILootTracker")

local sourceKey = ns.GetSourceKey(source)
local specData = ns.GetSpecData(70)
specData.goals[sourceKey .. ":item:123"] = {
    sourceKey = sourceKey,
    itemID = 123,
    priority = ns.PRIORITY_BIS,
    specID = 70,
    state = "open",
    minItemLevel = 311,
}

eventHandler(nil, "SPELL_CONFIRMATION_PROMPT", 42, 0, "Roll", 20, 3149, 1, 0, 99, 0, 10)
assert(ns.lastBonusRollTrackingDebug.state == "prompt_captured", "prompt source was not captured")

-- Blizzard may time out/close the confirmation frame before it reports the
-- item. The context must survive this event long enough to attribute it.
eventHandler(nil, "SPELL_CONFIRMATION_TIMEOUT")
eventHandler(nil, "BONUS_ROLL_RESULT", "item", "|Hitem:123::::::::|h[Test Item]|h", 1, 70)

local pool = ns.GetPool(sourceKey, 70)
assert(pool.knocked[123], "rolled item was not removed from the knockout pool")
assert(pool.rollsUsed == 1, "roll counter was not incremented")
assert(#ns.GetRollHistory() == 1, "roll history entry was not written")
assert(specData.goals[sourceKey .. ":item:123"].state == "archived", "wishlist goal was not archived")
assert(ns.lastBonusRollTrackingDebug.state == "result_tracked", "tracking debug did not report success")

ns.SetManualBonusRollState(sourceKey, 124, true, 70)
assert(pool.knocked[124], "manual historical roll must remove its item from the pool")
assert(pool.rollsUsed == 2, "manual historical roll must increment the roll counter")
assert(#ns.GetRollHistory() == 2 and ns.GetRollHistory()[2].manual,
    "manual historical roll must be distinguishable in history")
ns.SetManualBonusRollState(sourceKey, 124, false, 70)
assert(not pool.knocked[124], "undoing a manual roll must restore the pool item")
assert(pool.rollsUsed == 1 and #ns.GetRollHistory() == 1,
    "undoing a manual roll must restore history and count")

local specChanged
ns.RegisterCallback(function(reason) if reason == "spec" then specChanged = true end end)
eventHandler(nil, "PLAYER_LOOT_SPEC_UPDATED")
assert(catalogInvalidations == 1 and specChanged,
    "loot-specialization changes must invalidate and refresh core tracker state")

print("loot bonus roll result tracking ok")
