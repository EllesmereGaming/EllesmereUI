-- Stub harness: the Action Bars Bar Display page's Appearance, Effects, Behavior
-- & Paging and Text sections (BarAppearance_Options.lua). Loads the real builder
-- under stubs, checks each bar kind's rows in order and drives the views over the
-- stored keys (Paging Options, Paging Arrows, Item Information, Charge Numbers,
-- Keybind / Macro Text), the placeholder reads, the group pin, the search entries
-- and the TEXT rows' right halves, which grey out while their left control turns
-- the text off.
--   lua .tools/tests/test_ab_bar_display_page.lua        (from the repository root)
local TARGET = B2_TARGET or "EllesmereUIOptions/ActionBars_Options/BarAppearance_Options.lua"

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end
local function eq(a, b, msg)
    check(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- generic stub frame
local frameMeta
frameMeta = { __index = function(t, k)
    if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
    if k == "GetFrameLevel" then return function() return 1 end end
    if k == "GetScript" then return function() return nil end end
    return function() end
end }
local function Frame() return setmetatable({}, frameMeta) end

-- state the stubs record
local rows, headers, cbdds, cogs, syncs, searches, refreshes, countRefresh, rebuildPaging, swatchSets
local function Reset()
    rows, headers, cbdds, cogs, syncs, searches, refreshes = {}, {}, {}, {}, {}, {}, {}
    countRefresh, rebuildPaging, swatchSets = {}, {}, {}
end

local blizzOn, foreverLook = false, false
local cdNumbers = true   -- the game's cooldown numbers setting
EUI_CLIENT_BLOCKED = nil
EllesmereUI = {
    _Pool = { CreateFrame = function() return Frame() end },
    L = function(s) return s end,
    IS_FOREVER = false,
    _prebuilding = false,
    _buildingModule = "EllesmereUIActionBars", _buildingPage = "Bar Display",
    BlizzStyle = {
        Note = function(_, y) return y end,
        Get = function() return blizzOn end,
        Label = function() return "Blizzard Style" end,
        Gate = function(_, c) return c end,
        Forever = function() return foreverLook end,
        Active = function() return blizzOn and "blizzard" or nil end,
    },
    GetBorderTextureDropdown = function() return { solid = "Solid" }, { "solid" } end,
    BorderPxSliderCfg = function(spec) return { type = "slider", text = spec.text } end,
    BorderOffsetRowCfgs = function() return { type = "slider", text = "Border Width Offset" },
        { type = "slider", text = "Border Height Offset" } end,
    BuildSyncIcon = function(o) syncs[#syncs + 1] = o end,
    BuildInlineCog = function(rgn, o) cogs[o.title or "?"] = o; return Frame() end,
    BuildColorSwatch = function() return Frame(), function() end end,
    BuildInlineSwatches = function(rgn, swatches, opts)
        swatchSets[#swatchSets + 1] = { rgn = rgn, swatches = swatches, opts = opts or {} }
    end,
    RegisterWidgetRefresh = function() end,
    BuildVisOptsCBDropdown = function(rgn, w, lvl, items, get, set, onChanged, maxVis, searchable, closeBtn, onMenuClosed, opts)
        cbdds[#cbdds + 1] = { rgn = rgn, items = items, get = get, set = set, closed = onMenuClosed, opts = opts }
        return Frame(), function() end
    end,
    SectionToggleSetValue = function(fn) return function(v) fn(v); EllesmereUI:RefreshPage(true) end end,
    BlankRowCfg = function() return { type = "label", text = "" } end,
    DisabledTooltip = function(r) return "requires " .. tostring(r) end,
    ShowWidgetTooltip = function() end, HideWidgetTooltip = function() end,
    SetCVar = function() end,
    _RegisterSearchEntry = function(label, loc, tip, mod, page, section, setter, key)
        searches[#searches + 1] = { label = label, tip = tip, section = section, setter = setter, key = key }
    end,
    _setActionBarKey = function() end,
}
function EllesmereUI:RefreshPage(force) refreshes[#refreshes + 1] = force and true or false end
UnitClass = function() return "Druid", "DRUID" end
GetCVarBool = function() return cdNumbers end
RAID_CLASS_COLORS = {}

-- the module namespace and the options env
local ns = {
    EAB_VTABLE = {
        BAR_KEY_TO_PAGE = { MainBar = 1, Bar2 = 6, Bar3 = 5, Bar4 = 3, Bar5 = 4, Bar6 = 13, Bar7 = 14, Bar8 = 15, Bar9 = 7, Bar10 = 10 },
        MOD_TARGET_PAGING = { shift = true, ctrl = true, alt = true, help = true, harm = true },
        PAGING_STATES = { class = { DRUID = { { id = "cat", label = "Cat Form" } } } },
    },
    BORDER_THICKNESS = { none = { regular = 0, shape = 0 }, thin = { regular = 1, shape = 7 } },
    AB_ForeverBg = function() return true end,
    AB_CapsSpanApply = function() end,
    RebuildBarPaging = function(k) rebuildPaging[#rebuildPaging + 1] = k end,
    LayoutPagingFrame = function() end,
    RefreshPagingCycleMacros = function() end,
}
EllesmereUI._ModuleNS = { EllesmereUIActionBars = ns }

local bars = {}
local selected = "MainBar"
local EAB = { db = { profile = { bars = bars, showEquippedBorder = false } } }
setmetatable(EAB, { __index = function(_, k)
    if k == "RefreshCountVisibility" then
        return function(_, key) countRefresh[#countRefresh + 1] = key end
    end
    return function() end
end })
local function NewBar()
    return { hideKeybind = false, hideMacroText = false, showPagingArrows = false,
        pagingArrowsWhilePaged = true, skipVisiblePagingBars = true, paging = {},
        disableFormPaging = false, disableSkyridingPaging = false, bgEnabled = false,
        bgBorderTexture = "solid", borderTexture = "solid", buttonShape = "none" }
end
for _, k in ipairs({ "MainBar", "Bar2", "StanceBar" }) do bars[k] = NewBar() end
local function SB() return bars[selected] end

local CAPS_STUB = {}
ns._ABO_OptEnv = {
    EAB = EAB, GROUP_BAR_ORDER = { "MainBar", "Bar2", "StanceBar" }, InCombatLockdown = function() return false end,
    PP = { Point = function() end }, SB = SB, SECTION_TEXT = "TEXT", SECTION_ICON_APPEARANCE = "APPEARANCE", SelectedKey = function() return selected end,
    SHORT_LABELS = {}, ShownBorderDefaults = function() return 0, 0, 0, 0 end,
    TEXT_ANCHOR_DROPDOWN_ORDER = {}, TEXT_ANCHOR_LABELS = {},
    EndCapsCtl = function(o)
        local C = { forever = foreverLook }
        function C.Cfg() return { type = "dropdown", text = o.label } end
        function C.Build() end
        return C
    end,
}

local fn = assert(loadfile(TARGET))
fn()
local Build = assert(ns.ABO_BuildBarAppearance, "builder not exported")

local function SGet(k) return SB()[k] end
local function SSet(k, v, apply) SB()[k] = v; if apply then apply(selected) end; EllesmereUI:RefreshPage() end
local function SVal(k, d) local v = SB()[k]; if v ~= nil then return v end; return d end
local W = {}
function W:SectionHeader(parent, text, y)
    headers[#headers + 1] = text
    local f = Frame(); f._sectionName = text
    parent._currentSection = f
    return f, 10
end
function W:DualRow(parent, y, l, r)
    local row = Frame()
    row._leftRegion = Frame(); row._leftRegion._control = Frame(); row._leftRegion._cfg = l
    row._rightRegion = Frame(); row._rightRegion._control = Frame(); row._rightRegion._cfg = r
    rows[#rows + 1] = { (l and l.text) or "-", (r and r.text) or "-", l = l, r = r, section = headers[#headers] }
    return row, 10
end
function W:Spacer() return Frame(), 10 end
local ctx = {
    BgDisabled = function() return not SB().bgEnabled end, SDB = SB, SGet = SGet,
    SSeedTextOffsets = function() end, SSet = SSet,
    SSetColor = function(k, r, g, b, a, apply) SB()[k] = { r = r, g = g, b = b, a = a } end,
    SUpdatePreview = function() end, SUpdatePreviewAndResize = function() end, SVal = SVal,
    visOnly = false, W = W,
}

local function Run(key)
    selected = key
    Reset()
    local parent = Frame()
    local rets = { Build(parent, 0, ctx) }
    return rets
end
local function Layout()
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r[1] .. " | " .. (r[2] == "" and "blank" or r[2]) end
    return out
end
local function FindCfg(text)
    for _, r in ipairs(rows) do
        if r.l and r.l.text == text then return r.l end
        if r.r and r.r.text == text then return r.r end
    end
end
local function FindDD(firstLabel)
    for _, d in ipairs(cbdds) do
        for _, it in ipairs(d.items) do if it.label == firstLabel then return d end end
    end
end
local function Expect(name, want)
    local got = Layout()
    local ok = #got == #want
    for i = 1, math.max(#got, #want) do if got[i] ~= want[i] then ok = false end end
    if not ok then
        fails = fails + 1
        print("  FAIL: layout " .. name)
        for i = 1, math.max(#got, #want) do
            print(string.format("    %-2d got  %-55s want %s", i, tostring(got[i]), tostring(want[i])))
        end
    end
end

-------------------------------------------------------------------------------
-- 1. Action Bar 1, EllesmereUI look, Bar Background off, modifier/target off
-------------------------------------------------------------------------------
local rets = Run("MainBar")
eq(#rets, 6, "return count")
eq(headers[1], "APPEARANCE", "first header")
eq(table.concat(headers, ","), "APPEARANCE,EFFECTS,BEHAVIOR & PAGING,TEXT", "headers MainBar")
Expect("MainBar default", {
    "Border Style | Border Size",
    "Custom Button Shape | Icon Zoom",
    "Icon Background | Blizzard Icon Background",
    "End Caps | Bar Background",
    "Desaturate on Cooldown | Alpha on Cooldown",
    "Out of Range Coloring | Cooldown Swipe Opacity",
    "Hide Charge Count at 0 | Item Information",
    "One Button Assist Icon | blank",
    "Click Through | Disable Tooltips",
    "Paging Options | Paging Arrows",
    "Cat Form | blank",
    "Cooldown Numbers | Cooldown Text Size",
    "Charge Numbers | Charge Text Size",
    "Keybind Text | Keybind Text Size",
    "Macro Text | Macro Text Size",
})
eq(FindCfg("Cooldown Swipe Opacity").trackWidth, 120, "swipe trackWidth")
check(cogs["Paging Arrow Settings"] ~= nil, "paging arrow cog built")
check(cogs["Cooldown Numbers"] ~= nil, "cooldown numbers cog built")
check(cogs["Icon Background"] ~= nil, "blizzard icon background cog built")
check(cogs["One Button Assist Icon"] ~= nil, "oba cog built")

-- Keybind Text / Macro Text views
do
    local kb = FindCfg("Keybind Text")
    eq(kb.getValue(), true, "keybind shown by default")
    kb.setValue(false); eq(SB().hideKeybind, true, "keybind off writes hide true")
    eq(kb.getValue(), false, "keybind reads hidden")
    kb.setValue(true); eq(SB().hideKeybind, false, "keybind on writes hide false")
    SB().hideKeybind = nil; eq(kb.getValue(), true, "unset hideKeybind reads shown")
    local mc = FindCfg("Macro Text")
    mc.setValue(false); eq(SB().hideMacroText, true, "macro off writes hide true")
    mc.setValue(true); eq(SB().hideMacroText, false, "macro on writes hide false")
end

-- Paging Arrows view
do
    local pa = FindCfg("Paging Arrows")
    eq(pa.getValue(), "paged", "arrows default While Paged")
    pa.setValue("never")
    eq(SB().showPagingArrows, false, "never: show false"); eq(SB().pagingArrowsWhilePaged, false, "never: whilePaged false")
    eq(pa.getValue(), "never", "reads never")
    pa.setValue("always")
    eq(SB().showPagingArrows, true, "always: show true"); eq(SB().pagingArrowsWhilePaged, false, "always leaves whilePaged")
    eq(pa.getValue(), "always", "reads always")
    pa.setValue("paged")
    eq(SB().showPagingArrows, false, "paged: show false"); eq(SB().pagingArrowsWhilePaged, true, "paged: whilePaged true")
    SB().pagingArrowsWhilePaged = nil; eq(pa.getValue(), "paged", "unset reads While Paged")
    local cog = cogs["Paging Arrow Settings"]
    eq(#cog.rows, 2, "arrow cog rows")
    eq(cog.rows[1].label, "Show Arrows on Right", "cog row 1")
    eq(cog.rows[2].label, "Skip Visible Bars When Paging", "cog row 2")
    eq(cog.rows[2].disabled, nil, "skip never greyed")
    SB().showPagingArrows = false; SB().pagingArrowsWhilePaged = false
    eq(cog.rows[1].disabled(), true, "right greyed while Never")
    SB().pagingArrowsWhilePaged = true
    eq(cog.rows[1].disabled(), false, "right live while paged")
end

-- Paging Options view (modifier / target unset, no pages: both off)
do
    local dd = FindDD("Form Paging")
    check(dd ~= nil, "paging options checklist")
    local labels = {}
    for _, it in ipairs(dd.items) do labels[#labels + 1] = it.label end
    eq(table.concat(labels, ","), "Form Paging,Skyriding Paging,Modifier Paging,Target Paging", "paging items MainBar")
    eq(dd.opts and dd.opts.notifyWrites, true, "paging notifyWrites")
    eq(dd.get("form"), true, "form checked by default")
    dd.set("form", false); eq(SB().disableFormPaging, true, "form off writes disable true")
    dd.set("form", true); eq(SB().disableFormPaging, false, "form on writes disable false")
    dd.set("skyriding", false); eq(SB().disableSkyridingPaging, true, "sky off writes disable true")
    eq(dd.get("modifier"), false, "modifier off with no pages")
    local before = #refreshes
    dd.closed()
    local forced = false
    for i = before + 1, #refreshes do if refreshes[i] then forced = true end end
    eq(forced, false, "no rebuild when groups unchanged")
    dd.set("modifier", true); eq(SB().modifierPaging, true, "modifier on writes true")
    eq(rebuildPaging[#rebuildPaging], "MainBar", "rebuild paging on modifier write")
    before = #refreshes
    dd.closed()
    forced = false
    for i = before + 1, #refreshes do if refreshes[i] then forced = true end end
    eq(forced, true, "rebuild once the menu closed")
end

-- Charge Numbers view
do
    local dd = FindDD("Charges")
    check(dd ~= nil, "charge numbers checklist")
    eq(dd.get("hideStackCount"), true, "stacks shown by default")
    dd.set("hideStackCount", false)
    eq(SB().hideStackCount, true, "stacks off writes hide true")
    eq(countRefresh[#countRefresh], "MainBar", "count refresh after write")
    eq(dd.get("hideStackCount"), false, "stacks reads hidden")
    dd.set("hideStackCount", true)
    eq(SB().hideStackCount, nil, "stacks on writes nil")
end

-- Item Information view
do
    local dd = FindDD("Item Rank")
    check(dd ~= nil, "item information checklist")
    eq(dd.get("rank"), false, "rank off by default")
    dd.set("rank", true); eq(SB().showRankIcon, true, "rank on")
    dd.set("equipped", true); eq(EAB.db.profile.showEquippedBorder, true, "equipped on")
    dd.set("equipped", false); eq(EAB.db.profile.showEquippedBorder, false, "equipped off saves false")
    eq(dd.items[2].lockedFn(), false, "equipped unlocked on EUI style")
end

-- search entries registered before their rows
do
    local seen = {}
    for _, s in ipairs(searches) do seen[s.label] = s end
    check(seen["Paging Options"] and seen["Paging Options"].tip:find("Disable Form Paging", 1, true), "paging search words")
    check(seen["Paging Arrows"] and seen["Paging Arrows"].tip:find("Skip Visible Bars When Paging", 1, true), "arrows search words")
    check(seen["Item Information"] and seen["Item Information"].tip:find("Show Item Rank", 1, true), "item search words")
    check(seen["Charge Numbers"] and seen["Charge Numbers"].tip:find("Item Count", 1, true), "charge search words")
    eq(seen["Item Information"] and seen["Item Information"].section, "EFFECTS", "item search section")
end

-------------------------------------------------------------------------------
-- 2. Action Bar 1 with Modifier/Target Paging on (old switch, a shift page)
-------------------------------------------------------------------------------
bars.MainBar = NewBar()
bars.MainBar.paging = { shift = 6 }
Run("MainBar")
do
    local dd = FindDD("Form Paging")
    eq(dd.get("modifier"), true, "old pages: modifier checked")
    eq(dd.get("target"), true, "old pages: target checked")
end
Expect("MainBar mod+target", {
    "Border Style | Border Size",
    "Custom Button Shape | Icon Zoom",
    "Icon Background | Blizzard Icon Background",
    "End Caps | Bar Background",
    "Desaturate on Cooldown | Alpha on Cooldown",
    "Out of Range Coloring | Cooldown Swipe Opacity",
    "Hide Charge Count at 0 | Item Information",
    "One Button Assist Icon | blank",
    "Click Through | Disable Tooltips",
    "Paging Options | Paging Arrows",
    "Shift Modifier | Ctrl Modifier",
    "Alt Modifier | Friendly Target",
    "Hostile Target | Cat Form",
    "Cooldown Numbers | Cooldown Text Size",
    "Charge Numbers | Charge Text Size",
    "Keybind Text | Keybind Text Size",
    "Macro Text | Macro Text Size",
})
-- modTargetPaging false holds both off, whatever a group's own key says
bars.MainBar.modTargetPaging = false
bars.MainBar.targetPaging = true
Run("MainBar")
do
    local dd = FindDD("Form Paging")
    eq(dd.get("modifier"), false, "switch off: modifier unchecked")
    eq(dd.get("target"), false, "switch off: target unchecked though its own key says on")
    -- Ticking a group under it lifts it; the other group keeps the off it showed.
    dd.set("modifier", true)
    eq(SB().modTargetPaging, nil, "the old switch is cleared")
    eq(SB().modifierPaging, true, "modifier on")
    eq(SB().targetPaging, false, "target keeps its off")
    eq(dd.get("modifier"), true, "modifier now checked")
    eq(dd.get("target"), false, "target still unchecked")
end
bars.MainBar.modTargetPaging, bars.MainBar.targetPaging, bars.MainBar.modifierPaging = nil, nil, nil

-------------------------------------------------------------------------------
-- 3. Action Bar 2: no Form / Skyriding items, no Paging Arrows
-------------------------------------------------------------------------------
Run("Bar2")
do
    local dd = FindDD("Modifier Paging")
    local labels = {}
    for _, it in ipairs(dd.items) do labels[#labels + 1] = it.label end
    eq(table.concat(labels, ","), "Modifier Paging,Target Paging", "paging items Bar2")
    check(cogs["Paging Arrow Settings"] == nil, "no arrow cog on Bar2")
end
Expect("Bar2", {
    "Border Style | Border Size",
    "Custom Button Shape | Icon Zoom",
    "Icon Background | Blizzard Icon Background",
    "End Caps | Bar Background",
    "Desaturate on Cooldown | Alpha on Cooldown",
    "Out of Range Coloring | Cooldown Swipe Opacity",
    "Hide Charge Count at 0 | Item Information",
    "One Button Assist Icon | blank",
    "Click Through | Disable Tooltips",
    "Paging Options | Cat Form",
    "Cooldown Numbers | Cooldown Text Size",
    "Charge Numbers | Charge Text Size",
    "Keybind Text | Keybind Text Size",
    "Macro Text | Macro Text Size",
})

-------------------------------------------------------------------------------
-- 4. Stance Bar: BEHAVIOR only, no paging rows
-------------------------------------------------------------------------------
Run("StanceBar")
eq(table.concat(headers, ","), "APPEARANCE,EFFECTS,BEHAVIOR,TEXT", "headers StanceBar")
check(FindCfg("Paging Options") == nil, "no paging on Stance Bar")

-------------------------------------------------------------------------------
-- 5. Bar Background on (EllesmereUI look): dependent rows, Spacing last
-------------------------------------------------------------------------------
bars.Bar2.bgEnabled = true
Run("Bar2")
Expect("Bar2 bg on", {
    "Border Style | Border Size",
    "Custom Button Shape | Icon Zoom",
    "Icon Background | Blizzard Icon Background",
    "End Caps | Bar Background",
    "Background Color | Background Opacity",
    "Background Border Style | Background Border Size",
    "Multiplier X | Multiplier Y",
    "Spacing | blank",
    "Desaturate on Cooldown | Alpha on Cooldown",
    "Out of Range Coloring | Cooldown Swipe Opacity",
    "Hide Charge Count at 0 | Item Information",
    "One Button Assist Icon | blank",
    "Click Through | Disable Tooltips",
    "Paging Options | Cat Form",
    "Cooldown Numbers | Cooldown Text Size",
    "Charge Numbers | Charge Text Size",
    "Keybind Text | Keybind Text Size",
    "Macro Text | Macro Text Size",
})
-- textured bar background border: renamed offsets row
bars.Bar2.bgBorderTexture = "fancy"
Run("Bar2")
check(FindCfg("Background Border Width Offset") ~= nil, "bg offsets renamed")

-------------------------------------------------------------------------------
-- 6. WoW Forever look + client: Bar Frame, Bar Background | Spacing, no skyriding
-------------------------------------------------------------------------------
foreverLook = true
EllesmereUI.IS_FOREVER = true
bars.Bar2.bgBorderTexture = "solid"
Run("Bar2")
Expect("Bar2 forever bg on", {
    "Border Style | Border Size",
    "Custom Button Shape | Icon Zoom",
    "Icon Background | Blizzard Icon Background",
    "End Caps | Bar Frame",
    "Bar Background | Spacing",
    "Background Color | Background Opacity",
    "Background Border Style | Background Border Size",
    "Multiplier X | Multiplier Y",
    "Desaturate on Cooldown | Alpha on Cooldown",
    "Out of Range Coloring | Cooldown Swipe Opacity",
    "Hide Charge Count at 0 | Item Information",
    "One Button Assist Icon | blank",
    "Click Through | Disable Tooltips",
    "Paging Options | Cat Form",
    "Cooldown Numbers | Cooldown Text Size",
    "Charge Numbers | Charge Text Size",
    "Keybind Text | Keybind Text Size",
    "Macro Text | Macro Text Size",
})
bars.Bar2.bgEnabled = false
Run("Bar2")
check(Layout()[5] == "Bar Background | blank", "forever bg off: Bar Background | blank (got " .. tostring(Layout()[5]) .. ")")
bars.MainBar = NewBar()
Run("MainBar")
do
    local dd = FindDD("Form Paging")
    local labels = {}
    for _, it in ipairs(dd.items) do labels[#labels + 1] = it.label end
    eq(table.concat(labels, ","), "Form Paging,Modifier Paging,Target Paging", "no skyriding on Forever")
end

-------------------------------------------------------------------------------
-- 7. Stock style: Equipped Item Color locks
-------------------------------------------------------------------------------
foreverLook, EllesmereUI.IS_FOREVER, blizzOn = false, false, true
Run("MainBar")
eq(FindDD("Item Rank").items[2].lockedFn(), true, "equipped locked under a stock style")
blizzOn = false

-------------------------------------------------------------------------------
-- 8. Fixer: placeholder reads, the group pin, search selectors, dimLocked
-------------------------------------------------------------------------------
local function ReadsOf(label)
    local cfg = FindCfg(label)
    local real = bars[selected]
    local readsBar, readsProf = {}, {}
    bars[selected] = setmetatable({}, { __index = function(_, k) readsBar[k] = true; return real[k] end })
    local prof = EAB.db.profile
    EAB.db.profile = setmetatable({}, { __index = function(_, k) readsProf[k] = true; return prof[k] end })
    cfg.getValue()
    bars[selected] = real
    EAB.db.profile = prof
    return readsBar, readsProf
end
bars.MainBar = NewBar()
Run("MainBar")
do
    local rb, rp = ReadsOf("Paging Options")
    for _, k in ipairs({ "disableFormPaging", "disableSkyridingPaging", "modifierPaging", "targetPaging", "modTargetPaging" }) do
        check(rb[k], "paging options reads " .. k)
    end
    rb, rp = ReadsOf("Item Information")
    check(rb.showRankIcon and rp.showEquippedBorder, "item information reads its keys")
    rb = ReadsOf("Charge Numbers")
    check(rb.hideChargeCount and rb.hideStackCount and rb.hideItemCount, "charge numbers reads its keys")
    for _, d in ipairs(cbdds) do
        if d.items[1].label ~= "Show When Spellbook Is Open" then
            eq(d.opts and d.opts.dimLocked, true, "dimLocked on " .. d.items[1].label)
        end
    end
end
-- P2: Target Paging then a Friendly Target page leaves Modifier unchecked.
do
    local dd = FindDD("Form Paging")
    dd.set("target", true)
    eq(SB().targetPaging, true, "target written")
    eq(SB().modifierPaging, false, "modifier pinned to what it showed")
    SB().paging.help = 6
    eq(dd.get("modifier"), false, "a target page leaves modifier unchecked")
    eq(dd.get("target"), true, "target still checked")
    dd.set("target", false)
    eq(dd.get("modifier"), false, "unchecking target keeps modifier off")
end
-- The pin takes what the other group shows: a shift page shows both checked.
bars.MainBar = NewBar()
bars.MainBar.paging = { shift = 6 }
Run("MainBar")
do
    local dd = FindDD("Form Paging")
    dd.set("modifier", false)
    eq(SB().targetPaging, true, "target pinned on (it showed checked)")
    eq(SB().modifierPaging, false, "modifier off")
    -- A pinned key is never written over by the other group's next write.
    dd.set("modifier", true)
    eq(SB().targetPaging, true, "pin kept")
end
-- No pin while modTargetPaging is set (the fallback cannot flip then).
bars.MainBar = NewBar()
bars.MainBar.modTargetPaging = true
Run("MainBar")
do
    local dd = FindDD("Form Paging")
    dd.set("modifier", false)
    eq(SB().targetPaging, nil, "no pin under a set modTargetPaging")
    eq(dd.get("target"), true, "target still follows modTargetPaging")
end
-- P3: search entries open Action Bar 1 whichever bar is built first.
do
    bars.MainBar = NewBar()
    Run("Bar2")
    local seen = {}
    for _, s in ipairs(searches) do seen[s.label] = s end
    local po, pa = seen["Paging Options"], seen["Paging Arrows"]
    check(po and po.key == "MainBar" and po.setter == EllesmereUI._setActionBarKey, "paging options opens Action Bar 1")
    check(po and po.tip:find("Form Paging", 1, true) and po.tip:find("Skyriding Paging", 1, true), "paging options words on Bar2")
    check(pa and pa.key == "MainBar" and pa.tip:find("Show While Paged", 1, true), "paging arrows entry on Bar2")
    eq(pa and pa.section, "BEHAVIOR & PAGING", "paging arrows section")
    for _, l in ipairs({ "Keybind Text", "Macro Text", "Charge Text Size", "Alpha on Cooldown", "Cooldown Swipe Opacity", "Bar Background" }) do
        check(seen[l] ~= nil, "renamed row search entry " .. l)
    end
    check(seen["Keybind Text"] and seen["Keybind Text"].tip:find("Hide Keybind Text", 1, true), "old keybind label")
    EllesmereUI.IS_FOREVER = true
    Run("Bar2")
    seen = {}
    for _, s in ipairs(searches) do seen[s.label] = s end
    check(seen["Paging Options"] and not seen["Paging Options"].tip:find("Skyriding", 1, true), "no skyriding words on Forever")
    EllesmereUI.IS_FOREVER = false
end

-------------------------------------------------------------------------------
-- 9. TEXT: a row's right half (size slider, offsets cog, colour swatch) is off
--    while its left control turns the text off
-------------------------------------------------------------------------------
bars.MainBar = NewBar()
Run("MainBar")
do
    local function Half(sizeLabel, cogTitle)
        local sw
        for _, s in ipairs(swatchSets) do
            if s.rgn._cfg and s.rgn._cfg.text == sizeLabel then sw = s end
        end
        return FindCfg(sizeLabel), cogs[cogTitle], sw
    end
    local function Off(sizeLabel, cogTitle, want, why)
        local cfg, cog, sw = Half(sizeLabel, cogTitle)
        eq(cfg.disabled(), want, sizeLabel .. " slider " .. why)
        eq(cog.disabled(), want, cogTitle .. " cog " .. why)
        eq(sw.opts.disabled(), want, sizeLabel .. " swatch " .. why)
    end
    -- size slider, its cog's title, the left control it names, its colour key
    local ROWS = {
        { "Cooldown Text Size", "Cooldown Text", "Cooldown Numbers", "cooldownTextColor" },
        { "Charge Text Size", "Charges Text Offsets", "Charge Numbers", "countFontColor" },
        { "Keybind Text Size", "Keybind Text Offsets", "Keybind Text", "keybindFontColor" },
        { "Macro Text Size", "Macro Text Offsets", "Macro Text", "macroFontColor" },
    }
    eq(#swatchSets, 4, "one inline swatch set per TEXT row")
    for _, r in ipairs(ROWS) do
        local cfg, cog, sw = Half(r[1], r[2])
        check(cfg and type(cfg.disabled) == "function", r[1] .. " slider has a disabled function")
        check(cog and type(cog.disabled) == "function", r[2] .. " cog has a disabled function")
        check(sw and #sw.swatches == 1 and type(sw.opts.disabled) == "function",
            r[1] .. " has one inline swatch with a disabled function")
        eq(cfg and cfg.disabledTooltip, r[3], r[1] .. " slider names its left control")
        eq(cog and cog.disabledTooltip, r[3], r[2] .. " cog names its left control")
        eq(sw and sw.opts.disabledTooltip, r[3], r[1] .. " swatch names its left control")
        Off(r[1], r[2], false, "live by default")
        -- the swatch still reads and writes its row's colour
        local a, b, c = sw.swatches[1].getValue()
        check(a == 1 and b == 1 and c == 1, r[1] .. " swatch reads white while unset")
        sw.swatches[1].setValue(0.1, 0.2, 0.3)
        local col = SB()[r[4]]
        check(col and col.r == 0.1 and col.g == 0.2 and col.b == 0.3, r[1] .. " swatch writes " .. r[4])
        a, b, c = sw.swatches[1].getValue()
        check(a == 0.1 and b == 0.2 and c == 0.3, r[1] .. " swatch reads its colour back")
    end
    -- Keybind Text and Macro Text: each greys its own row, at once (a page refresh).
    local before = #refreshes
    FindCfg("Keybind Text").setValue(false)
    check(#refreshes > before, "Keybind Text refreshes the page")
    Off("Keybind Text Size", "Keybind Text Offsets", true, "off with Keybind Text")
    Off("Macro Text Size", "Macro Text Offsets", false, "untouched by Keybind Text")
    FindCfg("Keybind Text").setValue(true)
    Off("Keybind Text Size", "Keybind Text Offsets", false, "back with Keybind Text")
    before = #refreshes
    FindCfg("Macro Text").setValue(false)
    check(#refreshes > before, "Macro Text refreshes the page")
    Off("Macro Text Size", "Macro Text Offsets", true, "off with Macro Text")
    Off("Keybind Text Size", "Keybind Text Offsets", false, "untouched by Macro Text")
    FindCfg("Macro Text").setValue(true)
    Off("Macro Text Size", "Macro Text Offsets", false, "back with Macro Text")
    -- Cooldown Numbers is the game's own setting: the right half and the left cog follow it.
    cdNumbers = false
    Off("Cooldown Text Size", "Cooldown Text", true, "off with Cooldown Numbers")
    eq(cogs["Cooldown Numbers"].disabled(), true, "left cog off with Cooldown Numbers")
    Off("Keybind Text Size", "Keybind Text Offsets", false, "untouched by Cooldown Numbers")
    cdNumbers = true
    Off("Cooldown Text Size", "Cooldown Text", false, "back with Cooldown Numbers")
    eq(cogs["Cooldown Numbers"].disabled(), false, "left cog back with Cooldown Numbers")
    -- Charge Numbers: off only while nothing is ticked.
    local dd = FindDD("Charges")
    dd.set("hideChargeCount", false)
    dd.set("hideStackCount", false)
    Off("Charge Text Size", "Charges Text Offsets", false, "live while one count is ticked")
    before = #refreshes
    dd.set("hideItemCount", false)
    check(#refreshes > before, "Charge Numbers refreshes the page")
    Off("Charge Text Size", "Charges Text Offsets", true, "off with nothing ticked")
    dd.set("hideStackCount", true)
    Off("Charge Text Size", "Charges Text Offsets", false, "back with one count ticked")
    -- another bar's own settings decide its rows
    bars.Bar2.hideMacroText = true
    Run("Bar2")
    Off("Macro Text Size", "Macro Text Offsets", true, "Bar2 off by its own Macro Text")
    Off("Keybind Text Size", "Keybind Text Offsets", false, "Bar2 keybind row live")
    bars.Bar2.hideMacroText = false
end

if fails > 0 then error(fails .. " check(s) failed") end
print("  all checks passed")
