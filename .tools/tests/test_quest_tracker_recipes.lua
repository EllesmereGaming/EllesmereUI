-- Stub harness: tracked recipes in the WoW Forever Custom Quest Tracker.
-- Loads the Quest Tracker loader and EllesmereUIQuestTracker_Custom.lua over
-- game stubs and checks that
--   the tracker listens for recipe tracking changes, and nothing for reagent
--     counts while no recipe is tracked
--   a tracked recipe shows after the quests under a Professions header, with
--     its required reagents as "have/need name", coloured as objectives
--   a bag change repaints the counts; a recraft is written as Blizzard writes
--     it and keyed negative, as Blizzard keys its block
--   a reagent name not loaded yet is asked for once and shows when it loads;
--     another item's load renders nothing; one that never loads is not asked
--     for again
--   the header collapses the section
--   hovering a recipe puts the secure overlay over it with every left and
--     right click going to that recipe's block in Blizzard's tracker, and a
--     quest hovered after it gets its own attributes back (no right click)
--   a recipe click never untracks a quest or opens our menu, in or out of
--     combat
--   untracking the last recipe drops the section and its events
-- The target file is QT_CUSTOM when set (a patched copy), else the live one.
--   lua .tools/tests/test_quest_tracker_recipes.lua   (from the repository root)
local LOADER = "EllesmereUIQuestTracker/EllesmereUIQuestTracker.lua"
local CUSTOM = QT_CUSTOM or "EllesmereUIQuestTracker/EllesmereUIQuestTracker_Custom.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
    return cond
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local LOADER_SRC, CUSTOM_SRC = Read(LOADER), Read(CUSTOM)

local METHODS = {}
for _, src in ipairs({ LOADER_SRC, CUSTOM_SRC }) do
    for name in src:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local frames, timers = {}, {}

local function MakeObj(kind, parent)
    local o = { _kind = kind, _parent = parent, _scripts = {}, _events = {}, _attr = {}, _shown = true,
                _w = 0, _h = 0 }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
        if k == "SetScript" then return function(self, name, fn) self._scripts[name] = fn end end
        if k == "GetScript" then return function(self, name) return self._scripts[name] end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
            return function(self) return MakeObj(k, self) end
        end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
        if k == "SetWidth" then return function(self, w) self._w = w end end
        if k == "SetHeight" then return function(self, h) self._h = h end end
        if k == "SetSize" then return function(self, w, h) self._w, self._h = w, h end end
        if k == "GetWidth" then return function(self) return self._w end end
        if k == "GetHeight" then return function(self) return self._h end end
        if k == "GetEffectiveScale" then return function() return 1 end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "GetStringHeight" then return function() return 12 end end
        if k == "GetStringWidth" then return function() return 50 end end
        if k == "GetAlpha" then return function() return 1 end end
        if k == "GetTop" then return function() return 100 end end
        if k == "GetBottom" then return function() return 50 end end
        if k == "GetLeft" then return function() return 10 end end
        if k == "GetVerticalScroll" then return function() return 0 end end
        if k == "SetText" then return function(self, t) self._text = t end end
        if k == "SetTextColor" then return function(self, r, g, b) self._color = { r, g, b } end end
        if k == "SetAttribute" then return function(self, name, v) self._attr[name] = v end end
        if k == "GetAttribute" then return function(self, name) return self._attr[name] end end
        if k == "SetPoint" then return function(self, ...) self._point = { ... } end end
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "UnregisterEvent" then return function(self, e) self._events[e] = nil end end
        if METHODS[k] then return function() end end
        return nil
    end })
    frames[#frames + 1] = o
    return o
end

function CreateFrame(kind, name, parent)
    local o = MakeObj(kind, parent)
    if name then _G[name] = o end
    return o
end
UIParent = MakeObj("Frame")
UIParent._w, UIParent._h = 1000, 800

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function hooksecurefunc() end
local inCombat = false
function InCombatLockdown() return inCombat end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function UnitGUID() return "Player-1" end
function GetTime() return 0 end
local modPrefix = ""
function SecureButton_GetModifierPrefix() return modPrefix end
function GetModifiedClick() return "SHIFT" end
function IsModifiedClick() return false end
function IsModifierKeyDown() return modPrefix ~= "" end
function GetQuestLink() return nil end
GameTooltip = MakeObj("GameTooltip")
TRACKER_HEADER_QUESTS = "Quests"
OBJECTIVE_TRACKER_COLOR = { Normal = { r = 0.8, g = 0.8, b = 0.8 }, Complete = { r = 0.6, g = 0.6, b = 0.6 } }
PROFESSIONS_TRACKER_HEADER_PROFESSION = "Professions"
PROFESSIONS_TRACKER_REAGENT_FORMAT = "%s %s"
PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT = "%d/%d"
PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT = "%d-%d"
PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER = "Recrafting: %s"
SlashCmdList = {}
C_AddOns = { IsAddOnLoaded = function() return true end }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    for _ = 1, 5 do
        local run = timers
        timers = {}
        for _, fn in ipairs(run) do fn() end
    end
end

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v) or v end
    return c
end

EllesmereUIDB = {}
local menus = 0
EllesmereUI = {
    IS_FOREVER = true,
    ELLESMERE_GREEN = { r = 0.1, g = 0.8, b = 0.6 },
    ReapplyOwnAnchor = function() end,
    _ModuleNS = {},
    Lite = { NewDB = function(_, defaults) return { profile = DeepCopy(defaults.profile) } end },
    NewCombatQueue = function() return { Defer = function() end } end,
    IsSecret = function() return false end,
    PrimeFontShadow = function() end,
    GetFontUseShadow = function() return false end,
    GetFontOutlineFlag = function() return "" end,
    RegisterVisibilityUpdater = function() end,
    RegisterMouseoverTarget = function() end,
    RegAccent = function() end,
    EvalVisibility = function() return true end,
    MakeUnlockElement = function(t) return t end,
    ShowContextMenu = function() menus = menus + 1 end,
    L = function(s) return s end,
}
function EllesmereUI:RegisterUnlockElements() end
function EllesmereUI:RegisterUnlockModeListener() end

ObjectiveTrackerFrame = {
    IsInitialized = function() return false end,
}

-- Quests: one watched quest.
C_QuestLog = {
    GetQuestTimers = function() return nil end,
    GetNumQuestWatches = function() return 1 end,
    GetQuestIDForQuestWatchIndex = function() return 101 end,
    IsComplete = function() return false end,
    IsFailed = function() return false end,
    GetTitleForQuestID = function(id) return "Quest " .. id end,
    GetQuestDifficultyLevel = function() return 1 end,
    GetQuestObjectives = function() return { { text = "0/8 Kobold", finished = false } } end,
    GetNumQuestLogEntries = function() return 0, 1 end,
    GetMaxNumQuestsCanAccept = function() return 25 end,
    GetQuestWatchType = function() return nil end,
    IsPushableQuest = function() return false end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end }
QuestUtilsOverrides = { GetQuestTitlePrefix = function() end, GetQuestTagText = function() end }

-- Recipes: what the game tracks, their reagents, the bags.
local tracked = { [false] = {}, [true] = {} }
local recipes = {
    [3915] = { name = "Bolt of Linen Cloth", slots = {
        { itemID = 2589, need = 2 },                       -- Linen Cloth
        { itemID = 2320, need = 1 },                       -- Coarse Thread
        { itemID = 4000, need = 1, required = false },     -- an optional reagent: not listed
    } },
    [3916] = { name = "Linen Bag", slots = { { itemID = 9999, need = 3 } } },
    [3917] = { name = "Brown Linen Robe", slots = { { itemID = 8888, need = 1 } } },
}
local itemNames = { [2589] = "Linen Cloth", [2320] = "Coarse Thread", [4000] = "Optional Thing" }
local bags = { [2589] = 1, [2320] = 3 }
local requested = {}

C_TradeSkillUI = {
    GetRecipesTracked = function(isRecraft)
        local out = {}
        for i, id in ipairs(tracked[isRecraft]) do out[i] = id end
        return out
    end,
}
C_Item = {
    GetItemNameByID = function(id) return itemNames[id] end,
    RequestLoadItemDataByID = function(id) requested[id] = (requested[id] or 0) + 1 end,
}
C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
Enum = { CraftingReagentType = { Basic = 1, Modifying = 2 } }

-- As Forever's ProfessionsUtil: the schematic, its slots' methods and the
-- slot predicates.
local function QuantityRequired(slot) return slot.quantityRequired end
local function NoVariable() return false end
local schematicReads = 0
ProfessionsUtil = {
    GetRecipeSchematic = function(recipeID)
        schematicReads = schematicReads + 1
        local r = recipes[recipeID]
        local s = { name = r.name, reagentSlotSchematics = {} }
        for i, d in ipairs(r.slots) do
            s.reagentSlotSchematics[i] = {
                reagents = { { itemID = d.itemID } }, reagentType = Enum.CraftingReagentType.Basic,
                quantityRequired = d.need, required = d.required ~= false, variableQuantities = {},
                GetQuantityRequired = QuantityRequired, IsVariableQuantityReagent = NoVariable,
            }
        end
        return s
    end,
    IsReagentSlotRequired = function(s) return s.required end,
    IsReagentSlotBasicRequired = function(s) return s.reagentType == Enum.CraftingReagentType.Basic and s.required end,
    IsReagentSlotModifyingRequired = function(s) return s.reagentType == Enum.CraftingReagentType.Modifying and s.required end,
    AccumulateReagentsInPossession = function(reagents)
        local n = 0
        for _, r in ipairs(reagents) do n = n + (bags[r.itemID] or 0) end
        return n
    end,
}

-- Blizzard's tracker: a block per tracked recipe, keyed as Blizzard keys them.
local recipeBlocks = {}
ProfessionsRecipeTracker = { GetExistingBlock = function(_, id) return recipeBlocks[id] end }
local questHeader = MakeObj("Button")
QuestObjectiveTracker = { GetExistingBlock = function(_, id) return id == 101 and { HeaderButton = questHeader } or nil end }

-------------------------------------------------------------------------------
--  The files under test
-------------------------------------------------------------------------------
local ns = {}
assert(loadstring(LOADER_SRC, "=EllesmereUIQuestTracker.lua"))("EllesmereUIQuestTracker", ns)
local firstCustomFrame = #frames + 1
assert(loadstring(CUSTOM_SRC, "=EllesmereUIQuestTracker_Custom.lua"))("EllesmereUIQuestTracker", ns)
local EQT = ns.EQT
local evt = frames[firstCustomFrame]
EQT.MuteBlizzardTracker = function() end
EQT.GetLineRGB = function() return 1, 1, 1, 1 end
EQT.GetHeaderRGB = function() return 1, 1, 1 end
EQT.GetFont = function() return "font" end
EQT.ShouldHideMasterHeader = function() return false end
EQT.QuestLogSnapshot = function() return {}, { [101] = "Elwynn" } end
EQT.AutoTrackOn = function() return false end
EQT.IsQuestFiltered = function() return false end
EQT.SortQuestList = function() end
EQT.GetTitleRGB = function() return 1, 0.9, 0.5 end
EQT.GetCompletedRGB = function() return 0.25, 1, 0.35 end
EQT.TitleDifficultyOn = function() return false end
EQT.WowheadQuestOK = function() return false end
EQT.QuestRewards = function() return nil end
EQT.Blizz = function() return false end

local cfg = EQT.DB()
cfg.customFocusClick, cfg.customGroupByZone = false, false
EQT.InitCustom()
RunTimers()
local frame = EUI_CustomQuestTracker
assert(frame and frame._shown, "the tracker did not show")

local function Fire(event, ...)
    evt._scripts.OnEvent(evt, event, ...)
end

-- The shown lines, top to bottom.
local function Lines()
    local out = {}
    for i, f in ipairs(frames) do
        if rawget(f, "kind") and f._shown and f._parent and f._parent ~= UIParent then
            out[#out + 1] = { f = f, i = i }
        end
    end
    table.sort(out, function(a, b)
        local ya, yb = a.f.lastY or 0, b.f.lastY or 0
        if ya ~= yb then return ya < yb end
        return a.i < b.i
    end)
    for i, e in ipairs(out) do out[i] = e.f end
    return out
end
local function Find(text)
    for _, l in ipairs(Lines()) do
        if l.text._text == text then return l end
    end
end
local function Texts()
    local t = {}
    for i, l in ipairs(Lines()) do t[i] = l.text._text end
    return table.concat(t, " | ")
end
local function Overlay()
    for _, f in ipairs(frames) do
        if f._attr and f._scripts.PostClick then return f end
    end
end

-------------------------------------------------------------------------------
--  1. Listening: recipe tracking always, reagent counts only with a recipe
-------------------------------------------------------------------------------
check(evt._events.TRACKED_RECIPE_UPDATE, "TRACKED_RECIPE_UPDATE is not registered")
check(not evt._events.BAG_UPDATE_DELAYED and not evt._events.CURRENCY_DISPLAY_UPDATE,
    "reagent count events registered with no recipe tracked")
check(not Find("Professions"), "a Professions header with no recipe tracked")

-------------------------------------------------------------------------------
--  2. A tracked recipe: after the quest, under a Professions header
-------------------------------------------------------------------------------
tracked[false] = { 3915 }
Fire("TRACKED_RECIPE_UPDATE", 3915, true)
RunTimers()
local hdr, rec = Find("Professions"), Find("Bolt of Linen Cloth")
local cloth, thread = Find("- 1/2 Linen Cloth"), Find("- 3/1 Coarse Thread")
check(hdr and hdr.kind == "zone", "no Professions header: " .. Texts())
check(rec and rec.kind == "recipe" and rec.id == 3915, "no recipe line: " .. Texts())
check(cloth and thread, "the reagents are not listed: " .. Texts())
check(not Find("- 0/1 Optional Thing"), "an optional reagent was listed")
local quest = Find("Quest 101")
check(quest and hdr and quest.lastY < hdr.lastY, "the recipes are not after the quests")
if hdr and rec and cloth and thread then
    check(hdr.lastY < rec.lastY and rec.lastY < cloth.lastY and cloth.lastY < thread.lastY, "order: " .. Texts())
    check(rec.text._color[1] == 1 and rec.text._color[2] == 0.9, "the recipe is not in the title colour")
    check(cloth.text._color[1] == 0.8, "a reagent still missing is not in the objective colour")
    check(thread.text._color[1] == 0.6, "a reagent you have is not in the completed objective colour")
end
check(evt._events.BAG_UPDATE_DELAYED and evt._events.CURRENCY_DISPLAY_UPDATE, "reagent count events not registered")
check(schematicReads == 1, "the recipe's schematic was read " .. schematicReads .. " times for one render")

-------------------------------------------------------------------------------
--  3. A bag change repaints the count
-------------------------------------------------------------------------------
bags[2589] = 2
Fire("BAG_UPDATE_DELAYED")
RunTimers()
local cloth2 = Find("- 2/2 Linen Cloth")
check(cloth2 and cloth2.text._color[1] == 0.6, "the count did not follow the bags: " .. Texts())
-- the schematic is game data: a bag change and a quest update read the bags, not the schematic
Fire("QUEST_LOG_UPDATE")
RunTimers()
check(schematicReads == 1, "a later render read the schematic again (" .. schematicReads .. " reads)")

-------------------------------------------------------------------------------
--  4. A recraft, keyed negative as Blizzard's block
-------------------------------------------------------------------------------
tracked[true] = { 3915 }
Fire("TRACKED_RECIPE_UPDATE", 3915, true)
RunTimers()
local recraft = Find("Recrafting: Bolt of Linen Cloth")
check(recraft and recraft.id == -3915, "no recraft line: " .. Texts())
check(schematicReads == 3, "a change of the tracked recipes did not read the schematics again (" .. schematicReads .. " reads)")
tracked[true] = {}

-------------------------------------------------------------------------------
--  5. Reagent names: asked for once, shown when loaded; a failed load is not
--     asked for again
-------------------------------------------------------------------------------
tracked[false] = { 3915, 3916, 3917 }
Fire("TRACKED_RECIPE_UPDATE", 3916, true)
RunTimers()
check(Find("Linen Bag") and Find("Brown Linen Robe"), "a recipe whose reagent name is loading is not listed")
check(requested[9999] == 1 and requested[8888] == 1, "the missing names were not asked for once")
check(evt._events.ITEM_DATA_LOAD_RESULT, "not listening for the names")
Fire("QUEST_LOG_UPDATE")
RunTimers()
check(requested[9999] == 1, "a name was asked for again while loading")
-- another item's load renders nothing
Fire("ITEM_DATA_LOAD_RESULT", 1234, true)
check(#timers == 0, "another item's load queued a render")
-- ours loads
itemNames[9999] = "Wool Cloth"
Fire("ITEM_DATA_LOAD_RESULT", 9999, true)
check(#timers > 0, "our item's load did not queue a render")
RunTimers()
check(Find("- 0/3 Wool Cloth"), "the loaded name is not shown: " .. Texts())
check(evt._events.ITEM_DATA_LOAD_RESULT, "stopped listening while a name is still loading")
-- the other never loads
Fire("ITEM_DATA_LOAD_RESULT", 8888, false)
RunTimers()
check(not evt._events.ITEM_DATA_LOAD_RESULT, "still listening after the last load ended")
Fire("QUEST_LOG_UPDATE")
RunTimers()
check(requested[8888] == 1, "an item that never loads was asked for again")
tracked[false] = { 3915 }
Fire("TRACKED_RECIPE_UPDATE", 3916, false)
RunTimers()

-------------------------------------------------------------------------------
--  6. The header collapses the section
-------------------------------------------------------------------------------
hdr = Find("Professions")
if check(hdr, "no Professions header to click") then
    hdr._scripts.OnClick(hdr, "LeftButton")
    RunTimers()
    check(Find("+ Professions") and not Find("Bolt of Linen Cloth"), "the section did not collapse: " .. Texts())
    check(Find("Quest 101"), "the quests collapsed with it")
    hdr = Find("+ Professions")
    if hdr then hdr._scripts.OnClick(hdr, "LeftButton") end
    RunTimers()
    check(Find("Bolt of Linen Cloth"), "the section did not open again: " .. Texts())
end

-------------------------------------------------------------------------------
--  7. The overlay: every left and right click on a recipe goes to its block
-------------------------------------------------------------------------------
local recipeHeader = MakeObj("Button")
recipeBlocks[3915] = { HeaderButton = recipeHeader }
rec = Find("Bolt of Linen Cloth")
local o
if check(rec, "no recipe line to hover") then
    rec._scripts.OnEnter(rec)
    o = Overlay()
    if check(o and o._shown, "no overlay over a recipe") then
        local a = o._attr
        check(a.type1 == "click" and a.clickbutton1 == recipeHeader, "a plain left click does not reach the recipe's block")
        check(a["shift-type1"] == "click" and a["shift-clickbutton1"] == recipeHeader, "shift click")
        check(a["ctrl-type1"] == "click" and a["ctrl-clickbutton1"] == recipeHeader, "ctrl click")
        check(a["alt-type1"] == "click" and a["alt-clickbutton1"] == recipeHeader, "alt click")
        check(a.type2 == "click" and a.clickbutton2 == recipeHeader, "a right click does not reach the recipe's block")
        check(o.line == rec, "the overlay is not over the recipe")
        -- after the secure click, our own path does nothing
        local before = menus
        modPrefix = "shift-"
        o._scripts.PostClick(o, "LeftButton")
        modPrefix = ""
        o._scripts.PostClick(o, "RightButton")
        local db = EllesmereUIDB.questTrackerChars and EllesmereUIDB.questTrackerChars["Player-1"]
        check(not (db and db.ctUntracked[3915]), "a recipe click untracked a quest of its id")
        check(menus == before, "a recipe click opened our quest menu")
    end
end

-- a quest hovered after it: its own attributes, no right click
quest = Find("Quest 101")
if quest and o then
    quest._scripts.OnEnter(quest)
    local a = o._attr
    check(a.type1 == nil and a.clickbutton1 == nil, "a quest's plain click kept the recipe's route")
    check(a["shift-type1"] == "click" and a["shift-clickbutton1"] == questHeader, "a quest's untrack click")
    check(a["ctrl-type1"] == nil and a["alt-type1"] == nil, "a quest kept the recipe's other modifiers")
    check(a.type2 == nil and a.clickbutton2 == nil, "a quest kept the recipe's right click")
    local before = menus
    o._scripts.PostClick(o, "RightButton")
    check(menus == before + 1, "a quest's right click lost our menu")
end

-- a recipe Blizzard's tracker does not list: no overlay
if o then
    o._shown = false
    recipeBlocks[3915] = nil
    rec._scripts.OnEnter(rec)
    check(not o._shown, "an overlay with no block to click")
    recipeBlocks[3915] = { HeaderButton = recipeHeader }
end

-------------------------------------------------------------------------------
--  8. In combat a click on the recipe itself does nothing
-------------------------------------------------------------------------------
if rec then
    inCombat = true
    local before = menus
    rec._scripts.OnClick(rec, "LeftButton")
    rec._scripts.OnClick(rec, "RightButton")
    RunTimers()
    check(menus == before, "a recipe click in combat opened our quest menu")
    check(Find("Bolt of Linen Cloth"), "a recipe click in combat changed the list")
    inCombat = false
end

-------------------------------------------------------------------------------
--  9. The last recipe untracked: no section, no reagent events
-------------------------------------------------------------------------------
tracked[false] = {}
Fire("TRACKED_RECIPE_UPDATE", 3915, false)
RunTimers()
check(not Find("Professions") and not Find("Bolt of Linen Cloth"), "the section stayed: " .. Texts())
check(not evt._events.BAG_UPDATE_DELAYED and not evt._events.CURRENCY_DISPLAY_UPDATE, "reagent events stayed registered")
check(Find("Quest 101"), "the quest went with them")

print(("quest tracker recipes harness: %d checks, %d failed"):format(count, fails))
if fails > 0 then error(("%d of %d checks failed"):format(fails, count)) end
