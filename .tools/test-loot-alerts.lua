EUI_CLIENT_BLOCKED = false
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
EllesmereUI = {
    L = function(value) return value end,
    Lf = function(value, ...) return string.format(value, ...) end,
}
local detailedLevel = 311
local itemLoadCallback
C_Item = {
    GetItemInfoInstant = function() return 123 end,
    GetDetailedItemLevelInfo = function() return detailedLevel end,
    GetItemNameByID = function() return "Test Item" end,
    GetItemIconByID = function() return 1 end,
}
Item = {
    CreateFromItemLink = function()
        return {
            ContinueOnItemLoad = function(_, callback) itemLoadCallback = callback end,
        }
    end,
}
function IsInGroup() return true end
function UnitName() return "Me" end
function UnitGUID() return "Player-Me" end
function Ambiguate(name) return name end
function GetTime() return 10 end

local eventFrame
function CreateFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript(_, callback) self.callback = callback end
    eventFrame = frame
    return frame
end

local ns = {}
function ns.GetProfile() return { lootWhisperPopup = true } end
function ns.GetGoals() return { { itemID=123, state="open", minItemLevel=300, priority=3 } } end

assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_LootAlerts.lua"))(
    "EllesmereUILootTracker", ns)

local whisper = ns.BuildLootWhisper(
    "Hi {player}, do you need {item}? |cffff0000Thanks|r\n", {
        player = "Other",
        itemID = 123,
        itemName = "Test Item",
        itemLink = "|cffa335ee|Hitem:123|h[Test Item]|h|r",
    })
assert(whisper == "Hi Other, do you need [Test Item]? Thanks",
    "trade whispers must contain a plain item name and no chat escape codes")
assert(not whisper:find("|", 1, true) and not whisper:find("\n", 1, true),
    "trade whispers must be safe for SendChatMessage")

local alert
ns.QueueLootAlert = function(value) alert = value end
eventFrame.callback(eventFrame, "CHAT_MSG_LOOT",
    "Other receives loot: |Hitem:123|h[Test Item]|h.", "",
    "", "", "Other", "", 0, 0, "", "", 42, "Player-Other")

assert(alert and alert.player == "Other" and alert.itemID == 123,
    "wishlist loot from another player must queue a trade alert")

alert = nil
eventFrame.callback(eventFrame, "CHAT_MSG_LOOT",
    "Me receives loot: |Hitem:123|h[Test Item]|h.", "",
    "", "", "Me", "", 0, 0, "", "", 43, "Player-Me")
assert(not alert, "the player's own loot must never queue a trade alert")

alert, detailedLevel = nil, 295
eventFrame.callback(eventFrame, "CHAT_MSG_LOOT",
    "Other receives loot: |Hitem:123|h[Test Item]|h.", "",
    "", "", "Other", "", 0, 0, "", "", 44, "Player-Other")
assert(not alert, "a drop below the wishlist target level must not queue a trade alert")

alert, detailedLevel, itemLoadCallback = nil, nil, nil
eventFrame.callback(eventFrame, "CHAT_MSG_LOOT",
    "Other receives loot: |Hitem:123|h[Test Item]|h.", "",
    "", "", "Other", "", 0, 0, "", "", 45, "Player-Other")
assert(not alert and itemLoadCallback,
    "an uncached item level must wait instead of matching the wishlist")
detailedLevel = 295
itemLoadCallback()
assert(not alert,
    "a deferred lower-difficulty item must still be rejected after loading")

alert, detailedLevel, itemLoadCallback = nil, nil, nil
eventFrame.callback(eventFrame, "CHAT_MSG_LOOT",
    "Other receives loot: |Hitem:123|h[Test Item]|h.", "",
    "", "", "Other", "", 0, 0, "", "", 46, "Player-Other")
detailedLevel = 311
itemLoadCallback()
assert(alert and alert.player == "Other",
    "an eligible cached item must queue after its item data loads")

print("loot alert parsing ok")
