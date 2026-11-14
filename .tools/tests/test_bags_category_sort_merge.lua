-- Stub harness: Bags Sort Items in a category view merges partial stacks first
-- (DoPhysicalSort(true): the OneBag stack merge, then the display sort) out of
-- combat and runs the display sort alone in combat. The merge run plays the
-- sort sound on Master (its sound effects mute would cut a click-time sound
-- short) and the bags refresh once, when the run finishes.
--   lua .tools/tests/test_bags_category_sort_merge.lua [EUI_Bags_Header.lua]
local PATH = (arg and arg[1]) or "EllesmereUIBags/EUI_Bags_Header.lua"

local fh = assert(io.open(PATH, "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- 1. The Sort button's click handler, cut from the real file, over stubs.
local s = SRC:find('    sort:SetScript("OnClick", function()', 1, true)
assert(s, "the Sort click handler not found")
local _, e = SRC:find("\n    end)\n", s, true)
local CLICK = SRC:sub(s, e)

local log, inCombat = {}, false
local HANDLER
local env = setmetatable({
    sortLocked = false,
    selectedCategoryIndex = 1,
    EllesmereUIDB = { bagSortWarningDismissed = true, bagMultiSortWarningDismissed = true },
    DoPhysicalSort = function(m) log[#log + 1] = "physical:" .. tostring(m) end,
    DoBlizzardSort = function() log[#log + 1] = "blizzard" end,
    DoVisualSort = function(a) log[#log + 1] = "visual:" .. tostring(a) end,
    PlaySound = function() log[#log + 1] = "sound" end,
    InCombatLockdown = function() return inCombat end,
    SOUNDKIT = { UI_BAG_SORTING_01 = 1 },
    EUI = {},
    sort = { SetScript = function(_, _, fn) HANDLER = fn end },
}, { __index = _G })
env.SortMovesItems = function() return env.selectedCategoryIndex == -1 or env.selectedCategoryIndex == -2 end
local fn = assert(loadstring(CLICK, "@SortClick"))
setfenv(fn, env)
fn()
assert(HANDLER, "the click handler was not set")

local function Click(sel, combat)
    log, inCombat = {}, combat
    env.selectedCategoryIndex = sel
    HANDLER()
    return table.concat(log, ",")
end

check(Click(1, false) == "physical:true", "category view out of combat: " .. Click(1, false))
check(Click(1, true) == "sound,visual:nil", "category view in combat: " .. Click(1, true))
check(Click(-1, false) == "physical:nil", "OneBag: " .. Click(-1, false))
check(Click(-2, false) == "blizzard", "MultiBag: " .. Click(-2, false))
check(Click(-1, true) == "", "OneBag in combat ran a sort")

-- 2. The merge run's sound and refresh, in the source.
local function has(text, msg) check(SRC:find(text, 1, true) ~= nil, msg) end
has('        if sfxWas == "1" and (tonumber(GetCVar("Sound_SFXVolume")) or 0) > 0 then\n'
    .. '            PlaySound(SOUNDKIT.UI_BAG_SORTING_01, "Master")',
    "the merge run does not play the sort sound on Master")
check(SRC:find("not mergeOnly", 1, true) == nil, "the run's sort sound is gated off for a category sort")
has("ConsolidateStacks(mergeOnly and function() DoVisualSort(true); FinishSort() end or RunSort)",
    "a category sort's merge run does not hand the refresh to FinishSort")
has("    DoVisualSort = function(skipRefresh)", "DoVisualSort takes no skipRefresh")
has("        if not skipRefresh then EUI_Bags:RefreshInventory() end", "DoVisualSort refreshes even when told not to")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_bags_category_sort_merge")
