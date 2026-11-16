-- Stub harness: the red "unusable" tint of bag and bank items and what clears its
-- cache. The answer is kept per item link; a level-up clears it, and so does a
-- skill change (a recipe or an item that asks for a skill rank). A skill change
-- that arrives in combat forgets only the unusable answers.
-- Runs the real code, cut from the files: the usability test with its cache and
-- its event frame (EllesmereUIBags.lua), the bags' handling of the skill event and
-- of the end of combat (EUI_Bags_Start.lua) and the bank's (EllesmereUIBags_Bank.lua).
--   lua .tools/tests/test_bags_unusable_skill_cache.lua        (from the repository root)

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what, keepLast)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b, e = src:find(last, a + #first, true)
    assert(b, what .. ": last line not found")
    return src:sub(a, keepLast and e or b - 1)
end

local count, fails = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local MAIN = ReadSource("EllesmereUIBags/EllesmereUIBags.lua")
local START = ReadSource("EllesmereUIBags/EUI_Bags_Start.lua")
local BANK = ReadSource("EllesmereUIBags/EllesmereUIBags_Bank.lua")

-------------------------------------------------------------------------------
--  The world the usability test reads
-------------------------------------------------------------------------------
local RECIPE = 9
local items = {}          -- link -> { recipe = bool, gear = bool, red = bool, usable = bool }
local tipReads, usableAsks, combat = 0, 0, false
local cacheFrame

local function Tip(item)
    tipReads = tipReads + 1
    local it = items[item]
    if not it then return nil end
    return { lines = {
        { leftText = "Item name", leftColor = { r = 1, g = 1, b = 1 } },
        { leftText = "Requires Engineering (225)", leftColor = it.red and { r = 1, g = 0.125, b = 0.125 } or { r = 1, g = 1, b = 1 } },
    } }
end
local slots = {}          -- "bag:slot" -> link
local env = setmetatable({
    C_Item = {
        GetItemInfoInstant = function(item)
            local it = items[item]
            return 1, "type", "sub", "", 134400, it and it.recipe and RECIPE or 4
        end,
        IsEquippableItem = function(item) return items[item] ~= nil and items[item].gear == true end,
        GetItemSpell = function() return nil end,
        IsUsableItem = function(item) usableAsks = usableAsks + 1; return items[item].usable end,
    },
    C_TooltipInfo = {
        GetBagItem = function(bag, slot) return Tip(slots[bag .. ":" .. slot]) end,
        GetHyperlink = function(link) return Tip(link) end,
    },
    Enum = { ItemClass = { Recipe = RECIPE } },
    ITEM_SCRAPABLE_NOT = "Cannot be scrapped", CANNOT_UNEQUIP_COMBAT = "Cannot unequip in combat",
    ITEM_DISENCHANT_NOT_DISENCHANTABLE = "Cannot be disenchanted",
    EllesmereUI = {},
    InCombatLockdown = function() return combat end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
    CreateFrame = function()
        cacheFrame = { events = {}, plain = {} }
        function cacheFrame:RegisterEvent(e) self.events[e] = true end
        function cacheFrame:SetScript(kind, fn) if kind == "OnEvent" then self.onEvent = fn end end
        return cacheFrame
    end,
}, { __index = _G })

local Unusable = assert(loadstring(Cut(MAIN, "local GetItemInfoInstant = C_Item.GetItemInfoInstant",
    "-- WoW Forever: the player's bags (1-4)", "the usability test") .. "\nreturn BagsItemUnusable", "=EllesmereUIBags.lua"))
setfenv(Unusable, env)
Unusable = Unusable()
local function Fire(event) cacheFrame.onEvent(cacheFrame, event) end
local function Reset()
    Fire("PLAYER_LEVEL_UP")
    tipReads, usableAsks, combat = 0, 0, false
end

-------------------------------------------------------------------------------
--  1. the cache and its events
-------------------------------------------------------------------------------
check(type(Unusable) == "function" and cacheFrame and cacheFrame.onEvent, "the usability test and its event frame were not cut from the file")
check(env.EllesmereUI._BagsItemUnusable == Unusable, "the bank does not get the same test")
check(cacheFrame.events.PLAYER_LEVEL_UP and cacheFrame.events.PLAYER_LEVEL_CHANGED and cacheFrame.events.SKILL_LINES_CHANGED,
    "the cache does not listen for a level-up and a skill change")

items = { sword = { gear = true, red = true }, shield = { gear = true, red = false }, plans = { recipe = true, usable = false },
    learned = { recipe = true, usable = true }, cloth = {} }
slots = { ["0:1"] = "sword", ["0:2"] = "shield" }
check(Unusable(0, 1, "sword") == true and Unusable(0, 2, "shield") == false, "a red requirement line does not make an item unusable")
check(Unusable(nil, nil, "plans") == true and Unusable(nil, nil, "learned") == false, "a recipe does not follow the game's usable answer")
check(Unusable(nil, nil, "cloth") == false, "an item that is neither gear, usable nor a recipe is unusable")
check(tipReads == 2 and usableAsks == 2, "gear is not read from its tooltip once each, or a recipe is not asked once each")
Unusable(0, 1, "sword"); Unusable(0, 2, "shield"); Unusable(nil, nil, "plans"); Unusable(nil, nil, "learned"); Unusable(nil, nil, "cloth")
check(tipReads == 2 and usableAsks == 2, "a second look reads a tooltip or asks the game again")

-- a level-up clears every answer
Fire("PLAYER_LEVEL_UP")
Unusable(0, 1, "sword"); Unusable(0, 2, "shield"); Unusable(nil, nil, "plans"); Unusable(nil, nil, "learned")
check(tipReads == 4 and usableAsks == 4, "a level-up does not clear every answer")
Fire("PLAYER_LEVEL_CHANGED")
Unusable(0, 2, "shield")
check(tipReads == 5, "a level change does not clear the answers")

-------------------------------------------------------------------------------
--  2. a skill change out of combat clears every answer
-------------------------------------------------------------------------------
Reset()
Unusable(0, 1, "sword"); Unusable(0, 2, "shield"); Unusable(nil, nil, "plans"); Unusable(nil, nil, "learned")
local tips, asks = tipReads, usableAsks
items.plans.usable = true          -- the profession reached the recipe's rank
items.sword.red = false
Fire("SKILL_LINES_CHANGED")
check(Unusable(nil, nil, "plans") == false, "a recipe that became learnable stays unusable after a skill change")
check(Unusable(0, 1, "sword") == false, "an item whose skill requirement is met stays unusable after a skill change")
Unusable(0, 2, "shield"); Unusable(nil, nil, "learned")
check(tipReads == tips + 2 and usableAsks == asks + 2, "a skill change out of combat does not clear every answer")
-- out of combat the usable answers go too: a profession that was dropped
items.learned.usable = false
Fire("SKILL_LINES_CHANGED")
check(Unusable(nil, nil, "learned") == true, "a recipe of a dropped profession stays usable after a skill change out of combat")

-------------------------------------------------------------------------------
--  3. a skill change in combat forgets the unusable answers alone
-------------------------------------------------------------------------------
items = { sword = { gear = true, red = true }, shield = { gear = true, red = false }, plans = { recipe = true, usable = false },
    learned = { recipe = true, usable = true }, bandage = { gear = true, red = true } }
slots = { ["0:1"] = "sword", ["0:2"] = "shield", ["0:3"] = "bandage" }
Reset()
Unusable(0, 1, "sword"); Unusable(0, 2, "shield"); Unusable(0, 3, "bandage"); Unusable(nil, nil, "plans"); Unusable(nil, nil, "learned")
tips, asks = tipReads, usableAsks
combat = true
items.bandage.red = false          -- First Aid reached the bandage's rank mid-fight
Fire("SKILL_LINES_CHANGED")
check(Unusable(0, 3, "bandage") == false, "an item that became usable in combat stays unusable")
check(Unusable(0, 1, "sword") == true and Unusable(nil, nil, "plans") == true, "an item that is still unusable changed its answer")
check(tipReads == tips + 2 and usableAsks == asks + 1, "the unusable answers were not looked at again after a skill change in combat")
tips, asks = tipReads, usableAsks
check(Unusable(0, 2, "shield") == false and Unusable(nil, nil, "learned") == false, "a usable answer changed")
check(tipReads == tips and usableAsks == asks, "a skill change in combat cleared the usable answers too")
-- many skill-ups in one fight: nothing more is read while nothing asks
for _ = 1, 30 do Fire("SKILL_LINES_CHANGED") end
check(tipReads == tips and usableAsks == asks, "a skill change reads tooltips by itself")
-- a level-up in combat still clears everything
Fire("PLAYER_LEVEL_UP")
Unusable(0, 2, "shield")
check(tipReads == tips + 1, "a level-up in combat does not clear every answer")
combat = false

-------------------------------------------------------------------------------
--  4. an answer with no bag slot and no link is not kept
-------------------------------------------------------------------------------
Reset()
items = { [501] = { gear = true, red = true } }
check(Unusable(nil, nil, nil, 501) == false and Unusable(nil, nil, nil, 501) == false, "an item known by its ID alone is judged")
-- the same item once its bag slot is known: read for real, the guess was not kept
slots = { ["0:9"] = 501 }
check(Unusable(0, 9, nil, 501) == true, "a guess made without a bag slot or a link was kept")
check(Unusable(nil, nil, nil, nil) == false, "no item at all is unusable")

-------------------------------------------------------------------------------
--  5. the bags: a repaint out of combat, one after a fight
-------------------------------------------------------------------------------
do
    local visible, scheduled = true, 0
    local bags = {}
    function bags:IsVisible() return visible end
    local branch = assert(loadstring("local event, EUI_Bags, ScheduleRefresh, InCombatLockdown = ...\n"
        .. Cut(START, '        if event == "SKILL_LINES_CHANGED" then', "\n        end\n", "the bags' skill branch", true)
        .. "\nreturn 'not handled'", "=EUI_Bags_Start.lua"))
    local function Skill(inCombat)
        return branch("SKILL_LINES_CHANGED", bags, function() scheduled = scheduled + 1 end, function() return inCombat end)
    end
    check(Skill(false) == nil and scheduled == 1 and bags._refreshPendingCombat == nil, "a skill change out of combat does not schedule one repaint of open bags")
    visible = false
    Skill(false)
    check(scheduled == 1, "closed bags were repainted for a skill change")
    visible = true
    Skill(true); Skill(true); Skill(true)
    check(scheduled == 1 and bags._refreshPendingCombat == true, "a skill change in combat repaints at once, or does not mark the end-of-combat refresh")
    check(branch("BAG_UPDATE", bags, function() scheduled = scheduled + 1 end, function() return false end) == "not handled",
        "the skill branch takes another event")
    check(START:find('    EUI_Bags:RegisterEvent("SKILL_LINES_CHANGED")\n', 1, true) ~= nil, "the bags do not register the skill event")

    -- the end of combat replays the marked refresh once, for bags that are open
    local refreshed, reagentRefreshed = 0, 0
    function bags:RefreshInventory() refreshed = refreshed + 1 end
    local reagent = {}
    function reagent:IsVisible() return false end
    function reagent:RefreshInventory() reagentRefreshed = reagentRefreshed + 1 end
    local regen = assert(loadstring("local event, EUI_Bags, EUI_BagsReagent = ...\n"
        .. Cut(START, '        if event == "PLAYER_REGEN_ENABLED" then', "\n            return\n        end\n", "the end of combat", true),
        "=EUI_Bags_Start.lua"))
    regen("PLAYER_REGEN_ENABLED", bags, reagent)
    check(refreshed == 1 and bags._refreshPendingCombat == nil, "the end of combat does not repaint open bags once and clear the mark")
    regen("PLAYER_REGEN_ENABLED", bags, reagent)
    check(refreshed == 1, "the end of combat repaints with nothing marked")
    bags._refreshPendingCombat = true
    visible = false
    regen("PLAYER_REGEN_ENABLED", bags, reagent)
    check(refreshed == 1 and reagentRefreshed == 0 and bags._refreshPendingCombat == nil, "the end of combat repaints closed bags")
end

-------------------------------------------------------------------------------
--  6. the bank draws the same tint: an open bank repaints too
-------------------------------------------------------------------------------
do
    check(BANK:find('\neventFrame:RegisterEvent("SKILL_LINES_CHANGED")\n', 1, true) ~= nil, "the bank does not register the skill event")
    local body = Cut(BANK, '    elseif event == "BAG_UPDATE" or event == "PLAYERBANKSLOTS_CHANGED"', "\n        end\n", "the bank's refresh branch", true)
    local branch = assert(loadstring("local event, EUI_Bank, ScheduleBankRefresh = ...\n" .. body:gsub("^%s*elseif", "if") .. "    end\n", "=EllesmereUIBags_Bank.lua"))
    local visible, scheduled = true, 0
    local bank = {}
    function bank:IsVisible() return visible end
    local function Event(e) branch(e, bank, function() scheduled = scheduled + 1 end) end
    Event("SKILL_LINES_CHANGED")
    check(scheduled == 1, "an open bank is not repainted for a skill change")
    Event("BAG_UPDATE"); Event("PLAYERBANKSLOTS_CHANGED"); Event("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
    check(scheduled == 4, "the bank's other refresh events no longer schedule a repaint")
    Event("BANK_TABS_CHANGED")
    check(scheduled == 4, "the refresh branch takes another event")
    visible = false
    Event("SKILL_LINES_CHANGED")
    check(scheduled == 4, "a closed bank is repainted for a skill change")
end

-------------------------------------------------------------------------------
--  7. the event exists on both clients: it is registered plainly
-------------------------------------------------------------------------------
for name, src in pairs({ ["EllesmereUIBags.lua"] = MAIN, ["EUI_Bags_Start.lua"] = START, ["EllesmereUIBags_Bank.lua"] = BANK }) do
    for line in src:gmatch("[^\n]+") do
        if line:find("SKILL_LINES_CHANGED", 1, true) and line:find("pcall", 1, true) then
            check(false, name .. " registers the skill event through pcall: " .. line:gsub("^%s+", ""))
        end
    end
end
check(true, "scan done")

if fails > 0 then error(fails .. " of " .. count .. " checks failed") end
print("PASS test_bags_unusable_skill_cache (" .. count .. " checks)")
