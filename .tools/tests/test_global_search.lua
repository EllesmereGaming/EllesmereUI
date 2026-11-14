-- Run from the repository root: lua5.1 .tools/tests/test_global_search.lua [GlobalSearch file]
-- Loads the real EllesmereUI_GlobalSearch.lua over stubs and checks ranking:
-- a multi-word query matches words across the label, tooltip and the
-- entry's path (module, page, Window Skins card, section, cog host and
-- title); a cog popup's rows register with their host row; a bare path
-- does not list every row under it; single-word ranking is unchanged.
local path = arg and arg[1] or "EllesmereUI_GlobalSearch.lua"

EllesmereUI = {
    L = function(s) return s end,
    Lf = function(f, ...) return f:format(...) end,
    GLOBAL_KEY = "_EUIGlobal",
    ADDON_GROUPS = { { members = { "EllesmereUIBlizzardSkin", "EllesmereUIUnitFrames", "EllesmereUIRaidFrames", "EllesmereUIQoL" } } },
    IsDevModeActive = function() return false end,
}
local ns = { modules = {
    EllesmereUIBlizzardSkin = { title = "Blizzard Skins+", pages = { "Window Skins", "Tooltips" } },
    EllesmereUIUnitFrames = { title = "Unit Frames", pages = { "Player", "Target" } },
    EllesmereUIRaidFrames = { title = "Raid & Party Frames", pages = { "General", "Party", "Raid", "Click Casting" } },
    EllesmereUIQoL = { title = "Quality of Life", pages = { "General" } },
    _EUIGlobal = { title = "Global Settings", pages = { "General", "Fonts", "Textures", "Glows" } },
} }
ns.GetTabLabel = function(_, p) return p end

local frames = 0
function CreateFrame()
    frames = frames + 1
    return { Hide = function() end, SetSize = function() end }
end
UIParent = {}
time = os.time
EllesmereUI._SnapshotAndClearWidgetRefreshList = function() return {} end
EllesmereUI._RestoreWidgetRefreshList = function() end

local src = assert(io.open(path)):read("*a")
local SearchIndex, RecordPickForTest, RunPrebuildPass = assert(loadstring(src
    .. "\nreturn SearchIndex, RecordPick, RunPrebuildPass", "GlobalSearch"))("EllesmereUI", ns)
local Register = EllesmereUI._RegisterSearchEntry

local function Row(module, page, section, label, tooltip)
    Register(label, nil, tooltip, module, page, section)
end
local BS, UF = "EllesmereUIBlizzardSkin", "EllesmereUIUnitFrames"
Row(BS, "Window Skins", "STAT DISPLAY", "Secondary/Tertiary Text", "How Secondary and Tertiary stat values are shown.")
Row(BS, "Tooltips", "BLIZZARD TOOLTIP", "Show Spell ID")
Row(UF, "Player", "POWER BAR", "Power Bar Height")
Row(UF, "Player", "POWER BAR", "Mana Bar while Shapeshifted")
Row(UF, "Player", "POWER BAR", "Show Mana Percent")
Row(UF, "Player", "HEALTH BAR", "Bar Texture")
Row(UF, "Player", "HEALTH BAR", "Texture Background")
Row(UF, "Target", "TEXT", "Left Text")
Row(UF, "Target", "TEXT", "Size")
-- Fonts, Glows and Textures each carry a section named for the module.
for _, page in ipairs({ "Fonts", "Glows", "Textures" }) do
    Register("RAID & PARTY FRAMES", nil, nil, "_EUIGlobal", page, "RAID & PARTY FRAMES", nil, nil, true)
end
Row("EllesmereUIQoL", "General", "BLIZZARD UI", "Hide Blizzard Party Frames")
Row("EllesmereUIRaidFrames", "General", "LAYOUT", "Frame Style", "Party Frames or Raid Frames.")
Row("_EUIGlobal", "General", "DISPLAY", "UI Scale")
for i = 1, 200 do Row(UF, "Target", "FILLER", "Filler Option " .. i, "Unrelated tooltip " .. i) end

-- The Stat Sections row and its cog, the way the page registers them: the
-- card title as the search context, the cog through BuildInlineCog's hook.
EllesmereUI._buildingModule, EllesmereUI._buildingPage = BS, "Window Skins"
EllesmereUI._searchContext = "Character Sheet"
Row(BS, "Window Skins", "STAT DISPLAY", "Stat Sections")
local header = { _sectionName = "STAT DISPLAY" }
local row = { _sectionHeader = header }
local rgn = { _widgetCfg = { text = "Stat Sections" }, GetParent = function() return row end }
local statKey = EllesmereUI._RegisterCogSearch(rgn, { title = "Stat Section Settings", rows = {
    { type = "toggle", label = "Show Mana", tooltip = "Adds Mana to the Attributes section." },
    { type = "reordercheck", label = "Crests" },
    { type = "slider", label = "Size" },
} })
-- The same label in another cog on the page stays a separate entry.
local rgn2 = { _widgetCfg = { text = "Left Text" }, GetParent = function() return row end }
EllesmereUI._RegisterCogSearch(rgn2, { title = "Left Text Settings", rows = { { type = "slider", label = "Size" } } })
-- A Blizzard Style hidden row registers nothing.
local hiddenRow = { _searchIgnore = true }
EllesmereUI._RegisterCogSearch({ _widgetCfg = { text = "Gone" }, GetParent = function() return hiddenRow end },
    { title = "Hidden", rows = { { type = "toggle", label = "Never Found" } } })
EllesmereUI._searchContext = nil

-- A closed card on a page built live before the index pass (which then skips
-- the page): the card's builder runs once through the index-only runner.
local liveWidgets = {}
EllesmereUI.Widgets = liveWidgets
EllesmereUI._searchContext = "Merchant"
EllesmereUI._IndexOnlyBuild(function(parent, y)
    local W = EllesmereUI.Widgets
    W:SectionHeader(parent, "MERCHANT FRAME", y)
    local row = W:DualRow(parent, y, { type = "toggle", text = "Mark Owned" }, { type = "toggle", text = "Bulk Buy" })
    -- What BuildInlineCog does first, on the stub row's region
    EllesmereUI._RegisterCogSearch(row._leftRegion, { title = "Owned Settings",
        rows = { { type = "toggle", label = "Hide Known Recipes" } } })
end, -6)
EllesmereUI._searchContext = nil
assert(EllesmereUI.Widgets == liveWidgets and not EllesmereUI._prebuilding,
    "the index-only runner restores the widget factory and _prebuilding")
-- Queued from a live build before any search: nothing is built until the pass.
EllesmereUI._searchContext = "Mailbox"
EllesmereUI._QueueIndexBuild(function(parent, y)
    EllesmereUI.Widgets:Toggle(parent, "Queued Mail Option", y)
end, -6)
EllesmereUI._searchContext = nil
EllesmereUI._buildingModule, EllesmereUI._buildingPage = nil, nil

local fails = 0
local function Results(q)
    local out = {}
    for i, e in ipairs(SearchIndex(q, 12)) do
        out[i] = (e.displayLabel or e.label) .. (e.host and (" <" .. e.host .. ">") or "")
    end
    return out
end
local function Rank(q, want)
    for i, l in ipairs(Results(q)) do if l == want then return i end end
end
local function Expect(q, want, maxRank)
    local r = Rank(q, want)
    if r and r <= maxRank then
        print(("ok    %-26s %s at #%d"):format(q, want, r))
    else
        fails = fails + 1
        print(("FAIL  %-26s wanted %s in top %d, got: %s"):format(q, want, maxRank, table.concat(Results(q), " | ")))
    end
end
local function ExpectNot(q, unwanted)
    if Rank(q, unwanted) then
        fails = fails + 1
        print(("FAIL  %-26s should not list %s"):format(q, unwanted))
    else
        print(("ok    %-26s no %s"):format(q, unwanted))
    end
end

-- The case this was built for, in any word order, and by its host row.
Expect("character sheet mana", "Show Mana <Stat Sections>", 1)
Expect("mana character sheet", "Show Mana <Stat Sections>", 1)
Expect("stat sections mana", "Show Mana <Stat Sections>", 1)
Expect("window skins mana", "Show Mana <Stat Sections>", 1)
Expect("mana", "Show Mana <Stat Sections>", 12)
Expect("crests", "Crests <Stat Sections>", 1)
-- Repeated cog labels stay apart and rank after the page's own row.
Expect("left text size", "Size <Left Text>", 1)
Expect("size", "Size", 1)
-- Words all in the label, any order, outrank a path-only spread.
Expect("texture bar", "Bar Texture", 1)
Expect("player power height", "Power Bar Height", 1)
-- A closed card indexed by the index-only runner, with the card in its path.
Expect("merchant known recipes", "Hide Known Recipes <Mark Owned>", 1)
Expect("merchant bulk", "Bulk Buy", 1)
-- A bare path names no row; hidden rows never index.
ExpectNot("character sheet", "Show Mana <Stat Sections>")
ExpectNot("never found", "Never Found <Gone>")
ExpectNot("queued mail option", "Queued Mail Option")
-- A destination named by the query ranks first: the section, then the page
-- whose own name matches, before options that merely contain the phrase.
Expect("party frames", "RAID & PARTY FRAMES", 1)
Expect("party frames", "Party", 2)
Expect("hide party", "Hide Blizzard Party Frames", 1)
-- Aliases: "home" is Global Settings.
Expect("home", "General", 1)
Expect("home scale", "UI Scale", 1)
-- Single words: an exact label still leads.
Expect("spell id", "Show Spell ID", 1)
Expect("text", "Left Text", 5)

-- The popup scrolls: a broad query returns past one screen of results.
local broad = #SearchIndex("filler", 50)
if broad == 50 then print("ok    filler                     50 results") else
    fails = fails + 1; print("FAIL  filler                     wanted 50 results, got " .. broad) end

-- Merged results: the three module sections read alike, so they show as one
-- row whose members are all three, until a word tells them apart.
local function Find(q, label)
    for _, e in ipairs(SearchIndex(q, 12)) do
        if (e.displayLabel or e.label) == label then return e end
    end
end
local function Check(ok, what)
    if ok then print("ok    " .. what) else fails = fails + 1; print("FAIL  " .. what) end
end
local merged = Find("party frames", "RAID & PARTY FRAMES")
Check(merged and merged.isGroup and #merged.members == 3, "party frames: one merged section row of 3")
local fonts = Find("party frames fonts", "RAID & PARTY FRAMES")
Check(fonts and not fonts.isGroup and fonts.page == "Fonts", "party frames fonts: the Fonts section alone")

-- The key a cog is built with is the one a jump to its row marks.
local mana = Find("character sheet mana", "Show Mana")
Check(mana and statKey == mana.module .. "\1" .. mana.page .. "\1" .. mana.host .. "\1" .. mana.cogTitle,
    "a cog's build key matches its rows' jump key")

-- "home" is whole-word only: typing "ho" or "h" does not put Global Settings first.
local ho = SearchIndex("ho", 12)[1]
Check(ho and ho.kind ~= "page", "ho: an option first, not a Global Settings page")

-- Tooltip words and cog popup rows are always searched.
EllesmereUIDB = {}
Check(Rank("tertiary stat", "Secondary/Tertiary Text") == 1, "label found")
Check(Rank("shown", "Secondary/Tertiary Text") ~= nil, "tooltip word found")
Check(Rank("crests", "Crests <Stat Sections>") ~= nil, "popup row found")

-- Picks: a picked result moves up within its tier.
local function SizeRanks()
    local hosts = {}
    for _, e in ipairs(SearchIndex("size", 12)) do
        if e.isGroup then for k, m in ipairs(e.members) do hosts[k] = m.host or "-" end end
    end
    return hosts
end
local before = SizeRanks()
local leftSize
for _, e in ipairs(SearchIndex("left text size", 12)) do if e.host == "Left Text" then leftSize = e end end
for _ = 1, 3 do RecordPickForTest(leftSize) end
local after = SizeRanks()
Check(before[1] ~= "Left Text" and after[1] == "Left Text", "picks: a picked Size row leads its merged row")
local bg
for _, e in ipairs(SearchIndex("texture background", 12)) do if e.label == "Texture Background" then bg = e end end
for _ = 1, 200 do RecordPickForTest(bg) end
Check(Rank("bar texture", "Bar Texture") == 1, "picks: the boost stays inside its tier")
-- A bare module name still lists its pages in tab order with a page picked.
local raidTab
for _, e in ipairs(SearchIndex("raid & party frames raid", 12)) do if e.kind == "page" and e.page == "Raid" then raidTab = e end end
for _ = 1, 5 do RecordPickForTest(raidTab) end
local tabs = {}
for _, e in ipairs(SearchIndex("raid & party frames", 12)) do if e.kind == "page" then tabs[#tabs + 1] = e.page end end
Check(table.concat(tabs, ",") == "General,Party,Raid,Click Casting", "bare module name: tab order kept with picks (" .. table.concat(tabs, ",") .. ")")
EllesmereUI.ClearSearchPicks()
Check(EllesmereUIDB.searchPicks == nil, "clear: pick history forgotten")
-- Remember Picks off: nothing recorded, the flag the only thing stored; on again stores nothing.
for _ = 1, 3 do RecordPickForTest(leftSize) end
EllesmereUI.SetSearchPicksOn(false)
for _ = 1, 3 do RecordPickForTest(leftSize) end
Check(EllesmereUIDB.searchPicks == nil and EllesmereUIDB.searchPicksOff == true, "picks off: history forgotten, nothing recorded")
Check(SizeRanks()[1] ~= "Left Text", "picks off: no boost")
EllesmereUI.SetSearchPicksOn(true)
Check(next(EllesmereUIDB) == nil, "picks on: nothing stored")
EllesmereUIDB = nil

-- The index pass: a page's queued card builds run as later jobs, one frame
-- each, not inside the page's own job; a build queued before the pass is
-- indexed by it; one queued after the pass runs at once.
local pending, frameNo, clock = {}, 0, 0
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
InCombatLockdown = function() return false end
debugprofilestop = function() clock = clock + 5; return clock end -- one build per frame
local ranAt, pageFrame = {}, nil
ns.modules.TestSkins = { title = "Test Skins", pages = { "Cards" }, buildPage = function(_, _, y)
    pageFrame = frameNo
    for _, card in ipairs({ "Alpha", "Beta" }) do
        EllesmereUI._searchContext = card
        EllesmereUI._QueueIndexBuild(function(parent, cy)
            ranAt[card] = frameNo
            EllesmereUI.Widgets:Toggle(parent, card .. " Card Option", cy)
        end, y)
        EllesmereUI._searchContext = nil
    end
end }
local done = false
RunPrebuildPass(function() done = true end)
while pending[1] do
    frameNo = frameNo + 1
    table.remove(pending, 1)()
end
Check(done and pageFrame and ranAt.Alpha and ranAt.Beta, "pass: page and both queued cards built")
Check(ranAt.Alpha and ranAt.Alpha > pageFrame and ranAt.Beta > ranAt.Alpha,
    "pass: each queued card is its own later job")
Expect("alpha card option", "Alpha Card Option", 1)
Expect("beta card option", "Beta Card Option", 1)
Expect("queued mail option", "Queued Mail Option", 1)
EllesmereUI._buildingModule, EllesmereUI._buildingPage = "TestSkins", "Cards" -- as a live build sets them
EllesmereUI._QueueIndexBuild(function(parent, y) EllesmereUI.Widgets:Toggle(parent, "Late Card Option", y) end, -6)
EllesmereUI._buildingModule, EllesmereUI._buildingPage = nil, nil
Check(not pending[1], "after the pass: nothing scheduled")
Expect("late card option", "Late Card Option", 1)

print(fails == 0 and "all passed" or (fails .. " failed"))
os.exit(fails == 0 and 0 or 1)
