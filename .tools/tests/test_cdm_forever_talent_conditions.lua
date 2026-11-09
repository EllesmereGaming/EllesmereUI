-- Run from the repository root: lua .tools/tests/test_cdm_forever_talent_conditions.lua
-- Cooldown Manager Talent Conditions on WoW Forever: the shared talent tree
-- helpers in EllesmereUI_SharedHelpers.lua (the class's vanilla trees from the
-- one trait tree, each talent's column and row from the game's positions) and
-- the Talent Conditions popup drawing those trees side by side. The retail
-- popup (class tree and spec tree) is driven too, so it is shown unchanged.
-- The check and the picker are shared (EllesmereUI.TalentConditionsHold in the
-- shared helpers, EllesmereUI.ShowTalentConditionsPopup in the options): the
-- Cooldown Manager keeps no copy of either, and a second caller (the swing
-- timer's shape) gets its own texts, font and list.
EUI_CLIENT_BLOCKED = false

-------------------------------------------------------------------------------
-- Fake widgets: every method is a no-op unless listed; scripts, text, shown
-- state, size and the last point are kept for the checks.
-------------------------------------------------------------------------------
local NewFake
local METHODS = {
    CreateTexture = function(self) return NewFake() end,
    CreateFontString = function(self) return NewFake() end,
    CreateLine = function(self) return NewFake() end,
    SetScript = function(self, name, fn) self._scripts[name] = fn end,
    HookScript = function(self, name, fn) self._scripts[name] = fn end,
    SetText = function(self, s) self._text = s end,
    GetText = function(self) return self._text end,
    SetFont = function(self, path) self._font = path end,
    Show = function(self) self._shown = true end,
    Hide = function(self) self._shown = false end,
    SetShown = function(self, v) self._shown = v and true or false end,
    IsShown = function(self) return self._shown == true end,
    GetFrameLevel = function() return 1 end,
    SetSize = function(self, w, h) self._w, self._h = w, h end,
    GetWidth = function(self) return self._w or 0 end,
    SetPoint = function(self, ...) self._point = { ... } end,
}
local FAKE_MT = { __index = function(_, k) return METHODS[k] or function() end end }
local ALL = {}      -- every fake made, in order
NewFake = function()
    local f = setmetatable({ _scripts = {} }, FAKE_MT)
    ALL[#ALL + 1] = f
    return f
end
-- The texts shown, in the order their font strings were made.
local function Shown(names)
    local out = {}
    for _, f in ipairs(ALL) do
        local text = rawget(f, "_text")
        if text and names[text] then out[#out + 1] = text end
    end
    return out
end

local buttons = {}  -- action buttons by label
local fontCalls = {} -- module font key -> ApplyModuleFont calls
local padOpens = 0   -- EllesmereUI.PadPopupOpen calls
local function Stubs(forever)
    EllesmereUI = {
        IS_FOREVER = forever, _ModuleNS = {}, _popupFrames = {}, PP = {},
        _Pool = { CreateFrame = function() return NewFake() end },
        L = function(s) return s end,
        Lf = function(s, ...)
            local args = { ... }
            return (s:gsub("%%(%d)%$[sd]", function(i) return tostring(args[tonumber(i)]) end))
        end,
        ApplyModuleFont = function(_, _, _, key)
            key = key or "global"
            fontCalls[key] = (fontCalls[key] or 0) + 1
        end,
        GetFontPath = function(key) return "font:" .. tostring(key) end,
        GetFontOutlineFlag = function() return "" end,
        PadInUse = function() return false end,
        PadPopupOpen = function() padOpens = padOpens + 1 end,
        GetAccentColor = function() return 1, 1, 1 end,
        MakeBorder = function() return NewFake() end,
        PopupBump = function() return 1 end,
        ClampPopupToScreen = function() end,
        ShowWidgetTooltip = function() end,
        HideWidgetTooltip = function() end,
        BuildPopupShell = function() return NewFake(), NewFake() end,
        MakeActionButton = function(_, _, label)
            local b = NewFake()
            b._label = NewFake()   -- the button's label, as MakeActionButton exposes it
            buttons[label] = b
            return b
        end,
    }
    local PP = EllesmereUI.PP
    PP.CreateBorder = function() end
    PP.SetBorderColor = function(f, r, g, b) f._border = { r, g, b } end
    PP.SetBorderSize = function() end
    GameTooltip = NewFake()
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    UnitClass = function() return "Warlock", "WARLOCK" end
end

-------------------------------------------------------------------------------
-- Talent data. WoW Forever: one trait tree (1000), its trees as trait groups,
-- given out of order. Positions as the game gives them, with one node a few
-- units off its column and one with an extra zero on its row.
-------------------------------------------------------------------------------
local NODES, TREE_NODES = {}, {}
local function Node(id, group, x, y, spell, committed, edges)
    NODES[id] = {
        isVisible = true, entryIDs = { id * 10 }, groupIDs = { group },
        posX = x, posY = y, type = 0, visibleEdges = edges or {},
        entryIDsWithCommittedRanks = committed and { id * 10 } or {},
        activeRank = committed and 1 or 0, ranksPurchased = committed and 1 or 0,
        _spell = spell,
    }
    TREE_NODES[#TREE_NODES + 1] = id
end
-- Affliction (group 9): columns at 1000 / 1600 / 2200 / 2800, rows at 500 / 1100 / 1700.
Node(101, 9, 1000, 500, 18174, true, { { targetNode = 102 } })
Node(105, 9, 1600, 500, 18175, false)
Node(106, 9, 2200, 500, 18176, false)
Node(102, 9, 1000, 1100, 18179, false)
Node(103, 9, 1603, 1100, 18213, false)   -- 3 units off column 1
Node(104, 9, 2800, 11000, 18265, false)  -- row 1, with an extra zero
Node(109, 9, 1000, 1700, 18177, false)
Node(107, 9, 2200, 1700, 18178, false)
Node(108, 9, 2800, 1700, 18180, false)
-- Demonology (group 10) and Destruction (group 11), each on the same spacing.
Node(201, 10, 1000, 500, 18692, false)
Node(202, 10, 1600, 1100, 18694, true)
Node(301, 11, 1000, 500, 17793, false)
Node(302, 11, 1600, 500, 17794, false)
-- A node with no talent: never drawn.
NODES[400] = { isVisible = true, entryIDs = {}, groupIDs = { 11 }, posX = 0, posY = 0 }
TREE_NODES[#TREE_NODES + 1] = 400

local GROUPS = {
    { groupID = 11, displayName = "Destruction", orderIndex = 3 },
    { groupID = 9, displayName = "Affliction", orderIndex = 1 },
    { groupID = 10, displayName = "Demonology", orderIndex = 2 },
}

C_ClassTalents = {
    GetActiveConfigID = function() return 1 end,
    GetTraitTreeForSpec = function() return 1000 end,
}
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 1000 } } end,
    GetGroupDisplayInfoByTreeID = function()
        local out = {}
        for i, g in ipairs(GROUPS) do out[i] = g end
        return out
    end,
    GetTreeNodes = function() return TREE_NODES end,
    GetNodeInfo = function(_, id) return NODES[id] end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
    GetDefinitionInfo = function(def)
        local node = NODES[def / 10]
        return node and { spellID = node._spell }
    end,
    GetTreeCurrencyInfo = function() return { { traitCurrencyID = 1 }, { traitCurrencyID = 2 } } end,
    GetNodeCost = function(_, id) return { { ID = NODES[id].groupIDs[1] == 9 and 1 or 2 } } end,
}
C_Spell = {
    GetSpellTexture = function(id) return id end,
    GetSpellName = function(id) return "Spell " .. id end,
}
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 265, "Affliction" end,
}
Enum = { TraitNodeType = { Selection = 2, SubTreeSelection = 3 } }

-------------------------------------------------------------------------------
-- 1. The shared helpers (the blocks at the end of EllesmereUI_SharedHelpers.lua:
-- the talent trees, then the Talent Conditions check).
-------------------------------------------------------------------------------
local function LoadShared()
    local src = assert(io.open("EllesmereUI_SharedHelpers.lua", "rb")):read("*a")
    local at = assert(src:find("%-%-  WoW Forever talent trees"), "the talent tree block is in the shared helpers")
    assert(src:find("%-%-  Talent Conditions: a list of", at), "the Talent Conditions check follows it")
    local block = src:sub((src:find("\ndo\r?\n", at)))
    assert((loadstring or load)(block, "=talent trees"))()
end
Stubs(true)
LoadShared()
local configID, treeID, trees = EllesmereUI.ForeverTalentTrees()
assert(configID == 1 and treeID == 1000, "the active config and its tree")
assert(#trees == 3 and trees[1].name == "Affliction" and trees[2].name == "Demonology"
    and trees[3].name == "Destruction", "the trees in their order, with the game's names")
assert(#trees[1].nodes == 9 and #trees[2].nodes == 2 and #trees[3].nodes == 2,
    "each tree holds its talents, a node with no talent left out")

local cells, rows = EllesmereUI.TalentTreeGrid(1, trees[1].nodes)
assert(cells[101].col == 0 and cells[101].row == 0, "the first talent")
assert(cells[103].col == 1 and cells[103].row == 1, "a node a few units off its column keeps its column")
assert(cells[104].col == 3 and cells[104].row == 1, "a row with an extra zero is read on the grid")
assert(cells[108].col == 3 and cells[108].row == 2, "the last talent")
assert(rows == 3, "three rows")

-- Classic Talents reads its trees through the shared helpers, never a copy.
do
    local ct = assert(io.open("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_ClassicTalents.lua", "rb")):read("*a")
    assert(ct:find("EllesmereUI.ForeverTalentTrees()", 1, true) and ct:find("EllesmereUI.TalentTreeGrid(", 1, true),
        "Classic Talents uses the shared helpers")
    assert(not ct:find("local function GridAxis", 1, true), "Classic Talents keeps no copy of the grid")
end

-------------------------------------------------------------------------------
-- 2. The popup on WoW Forever: the three trees side by side.
-------------------------------------------------------------------------------
local function LoadPopup()
    local ns = {
        IsEmptySlotMarker = function() return false end,
    }
    EllesmereUI._ModuleNS.EllesmereUICooldownManager = ns
    assert(loadfile("EllesmereUICooldownManager/EllesmereUICdmTalentConditions.lua"))("EllesmereUICooldownManager", ns)
    -- The options TOC order: the shared picker, then the Cooldown Manager's file.
    assert(loadfile("EllesmereUIOptions/EllesmereUI_TalentConditionsPopup.lua"))("EllesmereUIOptions", {})
    assert(loadfile("EllesmereUIOptions/EUI_CooldownManager_TalentConditions.lua"))("EllesmereUIOptions", {})
    assert(EllesmereUI.ShowTalentConditionsPopup, "the shared picker loaded")
    assert(ns.ShowCDMTalentConditionsPopup, "the popup loaded")
    return ns
end

-- The drawn talent buttons, by node ID, read from the panels the popup made.
-- The panels are the frames CreateFrame gave out with a label; their buttons
-- carry .node, set by the layout.
local made = {}
local function TrackFrames()
    local base = EllesmereUI._Pool.CreateFrame
    EllesmereUI._Pool.CreateFrame = function(...)
        local f = base(...)
        made[#made + 1] = f
        return f
    end
end
local function Drawn()
    local byNode, count = {}, 0
    for _, f in ipairs(made) do
        local node = rawget(f, "node")
        if node and rawget(f, "_shown") then
            byNode[node.nodeID] = f
            count = count + 1
        end
    end
    return byNode, count
end

TrackFrames()
local ns = LoadPopup()
local saved
ns.ShowCDMTalentConditionsPopup(686, {
    { nodeID = 101, entryID = nil, spellID = 18174, taken = true },
    { nodeID = 999, spellID = 1234, taken = false },   -- a talent no tree shows
}, function(list) saved = list or false end)

local byNode, count = Drawn()
assert(count == 13, "every talent of the three trees is drawn: " .. count)
assert(byNode[400] == nil, "a node with no talent is not drawn")
-- The panels' labels are the trees' names, in order.
local labels = Shown({ Affliction = true, Demonology = true, Destruction = true })
assert(#labels == 3 and labels[1] == "Affliction" and labels[2] == "Demonology"
    and labels[3] == "Destruction", "one panel per tree, in order: " .. table.concat(labels, ", "))
-- Talents sit on their grid: same column, same x; a row lower, lower.
local function X(f) return f._point[4] end
local function Y(f) return f._point[5] end
assert(X(byNode[101]) == X(byNode[102]) and Y(byNode[102]) < Y(byNode[101]),
    "a talent under another one is drawn under it")
assert(Y(byNode[103]) == Y(byNode[102]) and X(byNode[103]) > X(byNode[102]),
    "a talent off its column is drawn on its row, in the next column")
assert(Y(byNode[104]) == Y(byNode[103]) and X(byNode[104]) > X(byNode[103]),
    "the extra-zero talent is drawn on its row")
assert(Y(byNode[108]) < Y(byNode[104]) and X(byNode[108]) == X(byNode[104]), "a row lower, same column")
-- The trees share one grid: a smaller tree's rows and columns line up with the others'.
assert(Y(byNode[201]) == Y(byNode[101]) and X(byNode[201]) == X(byNode[101]),
    "row 0, column 0 sits at the same spot in every tree")
assert(Y(byNode[202]) == Y(byNode[102]) and X(byNode[202]) == X(byNode[105]),
    "Demonology's second row and second column match Affliction's")
assert(Y(byNode[302]) == Y(byNode[105]) and X(byNode[302]) == X(byNode[105]),
    "Destruction's match too")
-- Taken talents show in full colour, the rest dimmed (the committed build).
assert(byNode[101].node.taken and not byNode[102].node.taken, "the build reads from the committed ranks")

-- A click cycles the condition, Save hands over the drawn ones and the one no
-- tree shows.
byNode[102]._scripts.OnClick(byNode[102])
assert(buttons["Save"], "the Save button")
buttons["Save"]._scripts.OnClick()
assert(type(saved) == "table" and #saved == 3, "three conditions saved")
assert(saved[1].nodeID == 101 and saved[1].taken == true, "the first condition kept")
assert(saved[2].nodeID == 102 and saved[2].taken == true, "a click requires the talent")
assert(saved[3].nodeID == 999 and saved[3].taken == false, "a condition no tree shows is kept")

-- The condition check reads any committed rank as taken.
assert(ns.TalentCondIsTaken(101) == true and ns.TalentCondIsTaken(102) == false, "taken means a rank committed")
assert(ns.TalentConditionsHold({ { nodeID = 202, taken = true }, { nodeID = 301, taken = false } }),
    "conditions across trees hold")

-- The Cooldown Manager reads the shared check and opens the shared picker,
-- keeping no copy of either.
assert(ns.TalentCondIsTaken == EllesmereUI.TalentCondIsTaken
    and ns.TalentCondInvalidate == EllesmereUI.TalentCondInvalidate, "the CDM uses the shared check")
do
    local rt = assert(io.open("EllesmereUICooldownManager/EllesmereUICdmTalentConditions.lua", "rb")):read("*a")
    assert(not rt:find("local function NodeState", 1, true), "the CDM keeps no copy of the node cache")
    local op = assert(io.open("EllesmereUIOptions/EUI_CooldownManager_TalentConditions.lua", "rb")):read("*a")
    assert(not op:find("local function LayoutPanel", 1, true), "the CDM keeps no copy of the picker")
    -- The picker joins the controller cursor through the shared helper, no copy.
    local pk = assert(io.open("EllesmereUIOptions/EllesmereUI_TalentConditionsPopup.lua", "rb")):read("*a")
    assert(not pk:find("_padReg", 1, true), "the picker keeps no copy of the controller cursor hookup")
end
assert(padOpens > 0, "the picker opens through EllesmereUI.PadPopupOpen")
-- The open showed the CDM's own words and font: its title, hint and status.
local cdmTexts = Shown({
    ["Talent Conditions: Spell 686"] = true,
    ["Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the icon to show."] = true,
    ["3 condition(s), not met by your current talents: the icon is hidden."] = true,
})
assert(#cdmTexts == 3, "the CDM's title, hint and status: " .. table.concat(cdmTexts, " | "))
assert((fontCalls.cdm or 0) > 0, "the CDM opens the picker in its own font")

-- A second caller (the swing timer's shape): its own title, words, font and list.
local before = fontCalls.resourceBars or 0
local mine
EllesmereUI.ShowTalentConditionsPopup({
    title = "Talent Conditions: Swing Timer",
    conds = { { nodeID = 202, spellID = 18694, taken = true } },
    texts = {
        hint = "swing hint",
        none = "swing none",
        met = function(n) return "swing met " .. n end,
        notMet = function(n) return "swing not met " .. n end,
    },
    fontKey = "resourceBars",
    onConfirm = function(list) mine = list or false end,
})
assert((fontCalls.resourceBars or 0) > before, "the picker's texts take the second caller's font")
assert(buttons["Save"]._label._font == "font:resourceBars" and buttons["Clear All"]._label._font == "font:resourceBars",
    "and so do its footer buttons' labels")
local swing = Shown({ ["Talent Conditions: Swing Timer"] = true, ["swing hint"] = true, ["swing met 1"] = true })
assert(#swing == 3, "the second caller's title, hint and status: " .. table.concat(swing, " | "))
-- Clear All, then Save: nothing is kept, and the caller hears none.
buttons["Clear All"]._scripts.OnClick()
assert(#Shown({ ["swing none"] = true }) == 1, "an empty list says so in the caller's words")
buttons["Save"]._scripts.OnClick()
assert(mine == false, "an emptied list saves as none")

-------------------------------------------------------------------------------
-- 3. Retail: the class tree and the spec tree, as before.
-------------------------------------------------------------------------------
Stubs(false)
LoadShared()
made = {}
ALL = {}
TrackFrames()
ns = LoadPopup()
ns.ShowCDMTalentConditionsPopup(686, nil, function() end)
byNode, count = Drawn()
assert(count == 13, "retail draws every talent of the tree: " .. count)
labels = Shown({ Warlock = true, Affliction = true, Demonology = true, Destruction = true })
assert(#labels == 2 and labels[1] == "Warlock" and labels[2] == "Affliction",
    "retail: the class tree and the spec tree: " .. table.concat(labels, ", "))
print("test_cdm_forever_talent_conditions: all checks passed")
