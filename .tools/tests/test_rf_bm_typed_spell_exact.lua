-- Stub harness: Raid & Party Frames Buff Manager, a spell ID typed through
-- Custom Spell ID tracks that exact ID alone, and presets are left as they are.
-- Runs the real code: the curated catalogue (EllesmereUI_BuffPresets.lua), the
-- Buff Manager v2 store, resolution and menu action
-- (EUI_RaidFrames_BuffManager2.lua), the Assigned Buffs rows whose Extra Spells
-- menu writes the indicator (EUI_RaidFrames_ManagerPages.lua), the New
-- Indicator popup's Extra Spells menu and its Create step with the legacy alias
-- table (EUI_RaidFrames_BuffManager.lua), and the include maps and container
-- signature the engine containers are built from
-- (EUI_RaidFrames_AuraContainers.lua).
--   a typed Soothing Mist (115175) matches the Mistweaver's own channel only,
--     not Spiritfont's (1260617) or the Jade Serpent Statue's (198533), which
--     share its name and its curated family
--   presets are untouched: a pick from the Presets list keeps the family, on
--     the same indicator as a typed ID and on any other; an assigned filter
--     keeps it even for an ID that is also typed; the seeded preset groups
--     build the same include maps and signature whatever is typed elsewhere
--   typing an ID already picked from Presets narrows it, once; typing a typed
--     ID again changes nothing; unchecking drops the mark, so a later Presets
--     pick keeps the family again
--   the menu carries the one Custom Spell ID action, with its popup's text
--     unchanged and no hover text; rows read the spell's plain name
--   the mark is part of the container signature (slots take their include maps
--     at creation)
--   the Earth Shield / Ebon Might aliases still follow a typed ID
--   the New Indicator popup types the same way, names a typed spell at once
--     and hands the marks to the indicator it creates
--   filters: a spell ID typed into a filter (Edit Filters > Add Spell ID) is
--     marked on the filter and tracks that aura alone from now on; a Search
--     Spells pick, a preset's curated spell and an ID saved before keep their
--     families; one source that keeps the family wins; typing a held ID
--     narrows it; removing it drops the mark; Player Aura Bars' one-time copy
--     of the library brings a typed ID over alone
--   WoW Forever writes no mark and reads none: a typed rank keeps every rank
-- The widgets and the input popup are stubs that hand back the callbacks the
-- page gives them; the engine's own match is includeSpellIDs[aura.spellId]
-- (Blizzard_AuraContainerUtil.lua, DoesAuraPassCandidateFilters).
--   lua .tools/tests/test_rf_bm_typed_spell_exact.lua   (from the repository root)
local PRESETS = BMX_PRESETS or "EllesmereUI_BuffPresets.lua"
local BM2 = BMX_BM2 or "EllesmereUIRaidFrames/EUI_RaidFrames_BuffManager2.lua"
local PAGES = BMX_PAGES or "EllesmereUIOptions/EUI_RaidFrames_ManagerPages.lua"
local AURA = BMX_AURA or "EllesmereUIRaidFrames/EUI_RaidFrames_AuraContainers.lua"
local LEGACY = BMX_LEGACY or "EllesmereUIRaidFrames/EUI_RaidFrames_BuffManager.lua"
local PABF = BMX_PABF or "EllesmereUIUnitFrames/EUI_PlayerAuraBars_Filters.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    -- The client skips a leading byte order mark; loadstring does not.
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
    return s
end

-- The text from `from` to the first `to` after it, both included.
local function Cut(src, what, from, to)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b, e = src:find(to, a, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
end

local SOOM, SPIRITFONT, STATUE = 115175, 1260617, 198533
local CUSTOM = "Custom Spell ID"

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local Noop = function() end
local dropdowns, popupOpts, refreshes, reloads

function GetSpecialization() return 2 end
function GetSpecializationInfo() return 270 end -- Mistweaver
function UnitClass() return "Monk", "MONK" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Spell = {
    GetSpellName = function(id) return "Spell " .. id end,
    GetSpellTexture = function(id) return id end,
}

local LegacyFile = Read(LEGACY)
local PageSrc = Cut(Read(PAGES), "assigned buffs rows",
    "function ns.BMP_BuildAssignedFilters(parent, sy, ind, fontPath)", "\n    return sy\nend\n")
local AuraSrc = Cut(Read(AURA), "include maps and signature",
    "local function BmIncludeMap(", "    return { includeSpellIDs = include }\nend\n")
local LegacySrc = Cut(LegacyFile, "legacy aliases", "local PRIMARY_BY_ALT = {", "\n}\n")
-- The New Indicator popup: its two dropdowns, and what Create does with the
-- extra spells picked in it.
local PopupSrc = Cut(LegacyFile, "new indicator dropdowns",
    "                local function BuildV2DDs()\n",
    "                    popup._exDD, popup._exRefresh = exDD, exRefresh\n                end\n")
local CreateSrc = Cut(LegacyFile, "new indicator extras",
    "                        local exList = {}\n",
    "                                ns.BM2_SetSpellExact(newInd, exList[i], true)\n"
    .. "                            end\n                        end\n")

-- Player Aura Bars' one-time copy of the Buff Manager library into its own.
local PabCopySrc = Cut(Read(PABF), "the library copy",
    "local function NameToId(list)\n",
    "    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end\n    return true\nend\n")

local function Region()
    return { _control = { Hide = Noop }, GetFrameLevel = function() return 1 end }
end

local function NewWorld(forever)
    local EUI = { IS_FOREVER = forever or nil }
    _G.EllesmereUI = EUI
    assert(loadstring(Read(PRESETS), "=BuffPresets"))()
    local ns = {
        db = { profile = {} },
        BM_HEALER_SPECS = { { key = "MONK_MISTWEAVER", specID = 270, classToken = "MONK" } },
        BM_SpecKeyForSpecID = function(id) if id == 270 then return "MONK_MISTWEAVER" end end,
        BM_RoleBucketForSpecID = function() return nil end,
        ReloadFrames = function() reloads = reloads + 1 end,
    }
    ns.BM_PrimaryByAlt = assert(loadstring(LegacySrc .. "return PRIMARY_BY_ALT\n", "=Legacy"))()
    EUI.L = function(s) return s end
    assert(loadstring(Read(BM2), "=BuffManager2"))("EllesmereUIRaidFrames", ns)
    -- Options widgets: every dropdown hands back what the page gave it, and
    -- its refresh function counts the calls that ask for a new read.
    EUI.Widgets = {
        SectionHeader = function() return {}, 20 end,
        DualRow = function() return { _leftRegion = Region(), _rightRegion = Region() }, 30 end,
    }
    EUI.PP = {}
    EUI.PanelPP = { Point = Noop }
    EUI.RegisterWidgetRefresh = Noop
    EUI.BuildInlineCog = Noop
    EUI.BuildVisOptsCBDropdown = function(_, _, _, items, getter, setter)
        local dd = { items = items, getter = getter, setter = setter, rereads = 0, SetSize = Noop, SetPoint = Noop }
        dropdowns[#dropdowns + 1] = dd
        return dd, function(reread) if reread == true then dd.rereads = dd.rereads + 1 end end
    end
    function EUI:ShowInputPopup(opts) popupOpts = opts end
    function EUI:RefreshPage() refreshes = refreshes + 1 end
    assert(loadstring("local ns, EllesmereUI = ...\n" .. PageSrc, "=AssignedBuffs"))(ns, EUI)
    local A = assert(loadstring("local ns, EllesmereUI = ...\n"
        .. "local function CK(c) return tostring(c) end\n" .. AuraSrc
        .. "return { Signature = BmSignature, Cand = BuildBmCand }\n", "=AuraContainers"))(ns, EUI)
    dropdowns, popupOpts, refreshes, reloads = {}, nil, 0, 0
    return EUI, ns, A
end

-- A menu's pinned top actions, in order.
local function Actions(items)
    local list = {}
    for i = 1, #items do
        if items[i].isTopAction then list[#list + 1] = items[i] end
    end
    return list
end

-- A menu's rows under one of its headers, in menu order.
local function RowsUnder(items, header)
    local rows, on = {}, false
    for i = 1, #items do
        local it = items[i]
        if it.isHeader then
            on = it.label == header
        elseif on and not it.isTopAction then
            rows[#rows + 1] = it
        end
    end
    return rows
end

-- The indicator's Assigned Buffs rows, as its settings page builds them: the
-- Extra Spells dropdown is the one whose menu carries Custom Spell ID.
local function ExtraSpells(ns, ind)
    dropdowns = {}
    ns.BMP_BuildAssignedFilters({}, 0, ind, "font")
    for i = 1, #dropdowns do
        local list = Actions(dropdowns[i].items())
        for j = 1, #list do
            if list[j].label == CUSTOM then return dropdowns[i], list end
        end
    end
    error("no Extra Spells dropdown")
end

-- Clicks a top action and confirms its input popup with `text`.
local function Confirm(action, text)
    assert(action, "the action is offered")
    popupOpts = nil
    action.onClick()
    assert(popupOpts and popupOpts.onConfirm, "the action opens the input popup")
    local opts = popupOpts
    opts.onConfirm(text)
    return opts
end
local function Type(ns, ind, text)
    local _, list = ExtraSpells(ns, ind)
    return Confirm(list[1], text)
end
local function Pick(ns, ind, id) (ExtraSpells(ns, ind)).setter(id, true) end
local function Uncheck(ns, ind, id) (ExtraSpells(ns, ind)).setter(id, false) end
local function Rows(ns, ind, header) return RowsUnder((ExtraSpells(ns, ind)).items(), header or "Selected") end

local function Has(list, id)
    for i = 1, #(list or {}) do if list[i] == id then return true end end
    return false
end
local function HasRow(rows, id)
    for i = 1, #rows do if rows[i].key == id then return rows[i] end end
    return nil
end

-- The live view of one stored indicator and the include map its container takes.
local function Include(ns, A, ind)
    local views = ns.BM2_SpecIndicators("raid")
    for i = 1, #views do
        if views[i].id == ind.id then
            return A.Cand(views[i], views[i].spells).includeSpellIDs, views
        end
    end
    error("indicator not rendered")
end

local function Keys(map)
    local t = {}
    for k in pairs(map) do t[#t + 1] = k end
    table.sort(t)
    return table.concat(t, ",")
end

-- Every seeded preset group's include map, by name: what presets build.
local function PresetMaps(ns, A, skip)
    local out, views = {}, ns.BM2_SpecIndicators("raid")
    for i = 1, #views do
        local v = views[i]
        if not skip[v.id] then
            out[#out + 1] = tostring(v.name) .. "=" .. Keys(A.Cand(v, v.spells).includeSpellIDs)
        end
    end
    table.sort(out)
    return table.concat(out, ";")
end

-- The New Indicator popup's Extra Spells dropdown and its Create step.
local function NewPopup(ns, EUI)
    local popup = {
        _v2Filters = {}, _v2NegFilters = {}, _v2Extras = {}, _v2Exact = {},
        GetFrameLevel = function() return 1 end,
    }
    local names = setmetatable({}, { __index = function(_, id) return "Spell " .. id end })
    local Create = assert(loadstring("local ns, EllesmereUI, popup, SPELL_NAME_BY_ID = ...\n"
        .. "local ddW, ROW_H, POPUP_PAD, fltDDY, exDDY = 200, 30, 10, 0, 0\n"
        .. PopupSrc .. "BuildV2DDs()\n"
        .. "return function(newInd)\n" .. CreateSrc .. "end\n", "=NewIndicator"))(ns, EUI, popup, names)
    assert(popup._exDD and popup._exRefresh, "the popup builds its Extra Spells dropdown")
    return popup, popup._exDD, Create
end

-------------------------------------------------------------------------------
--  Retail
-------------------------------------------------------------------------------
do
    local EUI, ns, A = NewWorld(false)
    local KEY = "MONK_MISTWEAVER"
    local function Sig() return A.Signature(ns.BM2_SpecIndicators("raid"), KEY, "custom") end
    -- The preset filters exist before the page adds anything (its first read).
    ns.BM2_Filters()
    local sig0 = Sig()
    check(not sig0:find(":x", 1, true), "a set with no typed ID carries no typed tag")
    local presets0 = PresetMaps(ns, A, {})

    -- The menu: the one Custom Spell ID action, its popup's text as it was.
    local border = ns.BM2_AddIndicator("border", KEY)
    local icon = ns.BM2_AddIndicator("icon", KEY)
    local picked = ns.BM2_AddIndicator("icon", KEY)
    local mine = { [border.id] = true, [icon.id] = true, [picked.id] = true }
    local _, list = ExtraSpells(ns, border)
    check(#list == 1 and list[1].label == CUSTOM, "the menu offers the one Custom Spell ID action")
    check(list[1].tooltip == nil and list[1].lockedFn == nil, "with no hover text and no lock")
    popupOpts = nil
    list[1].onClick()
    local pop = popupOpts or {}
    check(pop.title == "Add Spell ID" and pop.message == "Enter the spell ID to track on this indicator.",
        "its popup keeps its title and message")
    check(pop.placeholder == "Spell ID", "and its input reads Spell ID while empty")

    -- The reported setup: a frame border with Soothing Mist typed in, and an
    -- icon indicator with Spiritfont's Soothing Mist typed in.
    Type(ns, border, tostring(SOOM))
    Type(ns, icon, tostring(SPIRITFONT))
    check(Has(border.spells, SOOM) and #border.spells == 1, "the typed ID is stored once on the border")
    check(border.exactSpells ~= nil and border.exactSpells[SOOM] == true, "and carries the typed mark")
    local inc = Include(ns, A, border)
    check(inc[SOOM] == true, "the border matches the typed Soothing Mist")
    check(not inc[SPIRITFONT], "the border does not match Spiritfont's Soothing Mist (has " .. Keys(inc) .. ")")
    check(not inc[STATUE], "the border does not match the Jade Serpent Statue's Soothing Mist")
    inc = Include(ns, A, icon)
    check(Keys(inc) == tostring(SPIRITFONT), "the icon indicator matches Spiritfont's Soothing Mist alone")
    local rows = Rows(ns, border)
    check(#rows == 1 and rows[1].key == SOOM and rows[1].label == "Spell " .. SOOM and rows[1].tooltip == rows[1].label,
        "a typed row reads the spell's plain name")
    local sigTyped = Sig()
    check(sigTyped:find(":x" .. SOOM, 1, true) ~= nil, "the typed mark is part of the container signature")

    -- Presets are untouched. The seeded groups build what they built before
    -- anything was typed, and every Soothing Mist still shows in its group.
    check(PresetMaps(ns, A, mine) == presets0, "the seeded preset groups changed with a typed ID elsewhere")
    local _, views = Include(ns, A, border)
    local lesser
    for i = 1, #views do if views[i].name == "Lesser Healing Buffs" then lesser = views[i] end end
    check(lesser ~= nil, "the seeded Lesser Healing Buffs group renders")
    if lesser then
        local m = A.Cand(lesser, lesser.spells).includeSpellIDs
        check(m[SOOM] and m[SPIRITFONT] and m[STATUE], "a preset filter keeps the whole Soothing Mist family")
    end
    -- A pick from the Presets list on another indicator keeps the family while
    -- the border holds the same ID typed.
    check(HasRow(Rows(ns, picked, "Presets"), SOOM) ~= nil, "the Presets list still offers Soothing Mist to another indicator")
    Pick(ns, picked, SOOM)
    check(picked.exactSpells == nil, "a pick from Presets writes no mark")
    inc = Include(ns, A, picked)
    check(inc[SOOM] and inc[SPIRITFONT] and inc[STATUE], "a pick from Presets keeps the family beside a typed twin (has " .. Keys(inc) .. ")")
    check(not Sig():find(tostring(picked.id) .. ":icon:" .. SOOM .. ":x", 1, true), "a Presets pick carries no typed tag in the signature")
    -- On one indicator, a typed ID beside a Presets pick: each matches its own way.
    Type(ns, picked, "974")
    inc = Include(ns, A, picked)
    check(inc[SOOM] and inc[SPIRITFONT] and inc[STATUE] and inc[974], "a typed ID beside a Presets pick narrowed the pick")
    check(picked.exactSpells ~= nil and picked.exactSpells[974] == true and picked.exactSpells[SOOM] == nil,
        "the mark went on the typed ID alone")
    rows = Rows(ns, picked)
    check(#rows == 2 and rows[1].label == "Spell " .. SOOM and rows[2].label == "Spell 974", "the rows stay in name order with plain names")

    -- Typing the same ID again changes nothing and builds no page; neither does junk.
    local r0, n0, l0 = refreshes, #border.spells, reloads
    Type(ns, border, tostring(SOOM))
    check(#border.spells == n0 and refreshes == r0 and reloads == l0, "typing a typed ID again changes nothing")
    Type(ns, border, "abc")
    Type(ns, border, "0")
    Type(ns, border, "-4")
    check(#border.spells == n0 and refreshes == r0, "a non-number, 0 and a negative are ignored")

    -- Unchecking drops the mark with the entry: a later pick from Presets
    -- keeps the family.
    Uncheck(ns, border, SOOM)
    check(not Has(border.spells, SOOM), "unchecking removes the typed ID")
    check(border.exactSpells == nil, "unchecking drops its mark")
    Pick(ns, border, SOOM)
    inc = Include(ns, A, border)
    check(inc[SOOM] and inc[SPIRITFONT] and inc[STATUE], "a pick from Presets keeps the family")
    local sigPicked = Sig()
    check(not sigPicked:find(tostring(border.id) .. ":border:" .. SOOM .. ":x", 1, true), "a Presets pick carries no typed tag")

    -- Typing an ID the indicator already picked from Presets narrows it.
    r0, l0 = refreshes, reloads
    Type(ns, border, tostring(SOOM))
    inc = Include(ns, A, border)
    check(Keys(inc) == tostring(SOOM), "typing a picked ID narrows it to that aura (has " .. Keys(inc) .. ")")
    check(#border.spells == 1, "and does not list it twice")
    check(refreshes == r0 + 1 and reloads == l0 + 1, "and reloads the frames and repaints the page once")
    check(Sig() ~= sigPicked, "the narrowed set builds another container than the picked one")

    -- A filter on the same indicator that holds the ID keeps the family.
    local lesserFid
    for _, f in ipairs(ns.BM2_Filters()) do if f.preset == "lesserheals" then lesserFid = f.id end end
    border.filters[lesserFid] = true
    inc = Include(ns, A, border)
    check(inc[SPIRITFONT] and inc[STATUE], "an assigned filter holding the typed ID keeps its family")
    border.filters[lesserFid] = nil
    inc = Include(ns, A, border)
    check(Keys(inc) == tostring(SOOM), "the typed ID narrows again once that filter is off")

    -- The list-only resolver is unchanged.
    local resolved = ns.BM2_ResolveSpells(border)
    check(#resolved == 1 and resolved[1] == SOOM, "BM2_ResolveSpells still returns the plain list")

    -- The game's own Earth Shield alias still follows a typed ID.
    local es = ns.BM2_AddIndicator("icon", KEY)
    mine[es.id] = true
    r0 = refreshes
    Type(ns, es, "974")
    check(Has(es.spells, 974) and es.exactSpells ~= nil and es.exactSpells[974] == true and refreshes == r0 + 1,
        "a new typed ID is added and marked in one step")
    inc = Include(ns, A, es)
    check(inc[974] and inc[383648], "a typed Earth Shield 974 still matches 383648 (has " .. Keys(inc) .. ")")

    -- Filters. A spell ID typed into a filter tracks that aura alone from now
    -- on; a Search Spells pick and an ID saved before keep their families.
    local fPick, fType, fOld = ns.BM2_AddFilter("Picked"), ns.BM2_AddFilter("Typed"), ns.BM2_AddFilter("Saved before")
    check(ns.BM2_AddCustomSpell(fPick.id, SOOM) == true and fPick.exact == nil, "a Search Spells pick adds the spell with no mark")
    check(ns.BM2_AddCustomSpell(fType.id, SOOM, true) == true and fType.exact ~= nil and fType.exact[SOOM] == true,
        "a spell ID typed into a filter is marked on it")
    fOld.custom[SOOM], fOld.spells[SOOM] = true, true -- as a build before this one saved it
    local function With(filter, more)
        local ind = ns.BM2_AddIndicator("icon", KEY)
        mine[ind.id] = true
        ind.filters[filter.id] = true
        if more then more(ind) end
        return ind
    end
    local function Family(ind)
        local m = Include(ns, A, ind)
        return m[SOOM] and m[SPIRITFONT] and m[STATUE] and true or false
    end
    local function Alone(ind) return Keys((Include(ns, A, ind))) == tostring(SOOM) end
    local iPick, iType, iOld = With(fPick), With(fType), With(fOld)
    check(Family(iPick), "a Search Spells pick keeps the family")
    check(Alone(iType), "a typed filter ID matches that aura alone (has " .. Keys((Include(ns, A, iType))) .. ")")
    check(Family(iOld), "an ID saved in a filter before this keeps its family")
    local sigF = Sig()
    check(sigF:find(tostring(iType.id) .. ":icon:" .. SOOM .. ":x" .. SOOM, 1, true) ~= nil,
        "a filter's typed ID is part of the container signature")
    check(not sigF:find(tostring(iPick.id) .. ":icon:" .. SOOM .. ":x", 1, true), "a picked one is not")
    -- One source that keeps the family wins; two typed sources stay exact.
    check(Family(With(fType, function(ind) ind.filters[fPick.id] = true end)),
        "a typed filter ID beside a filter that picked the spell: the family wins")
    check(Family(With(fType, function(ind) ind.filters[lesserFid] = true end)),
        "a typed filter ID beside the preset filter that curates the spell: the family wins")
    check(Family(With(fType, function(ind) ind.spells[1] = SOOM end)),
        "a typed filter ID beside a Presets pick on the indicator: the family wins")
    check(Alone(With(fType, function(ind) ind.spells[1] = SOOM; ns.BM2_SetSpellExact(ind, SOOM, true) end)),
        "a typed filter ID beside the same ID typed on the indicator stays exact")
    local fOff = ns.BM2_AddFilter("Switched off")
    ns.BM2_AddCustomSpell(fOff.id, SOOM)
    ns.BM2_SetSpellState(fOff.id, SOOM, false)
    check(Alone(With(fType, function(ind) ind.filters[fOff.id] = true end)),
        "a filter that holds the spell switched off does not bring its family back")
    -- Typing or picking a held spell again changes nothing; typing one the
    -- filter holds as the user's own narrows it, once.
    check(ns.BM2_AddCustomSpell(fType.id, SOOM, true) == false, "typing a typed filter ID again changes nothing")
    check(ns.BM2_AddCustomSpell(fPick.id, SOOM) == false and fPick.exact == nil, "picking a held spell again changes nothing")
    check(ns.BM2_AddCustomSpell(fOld.id, SOOM, true) == true and fOld.exact ~= nil and fOld.exact[SOOM] == true,
        "typing an ID the filter already holds narrows it")
    check(Alone(iOld), "and its indicator matches that aura alone")
    -- A spell a preset curates cannot be narrowed, and a mark on one is void
    -- (an ID the user typed that the catalogue curated later).
    local lesserF = ns.BM2_GetFilter(lesserFid)
    check(ns.BM2_AddCustomSpell(lesserFid, SOOM, true) == false and lesserF.exact == nil,
        "typing a spell a preset filter curates changes nothing")
    lesserF.custom[SOOM] = true
    check(ns.BM2_AddCustomSpell(lesserFid, SOOM, true) == false and lesserF.exact == nil,
        "typing a spell the user once added and its preset curates now changes nothing")
    lesserF.exact = { [SOOM] = true }
    check(Family(With(lesserF)), "a mark on a spell its preset curates is void")
    check(EUI._BM2FilterBridge.SpellExact(lesserF, SOOM) == false, "and the bridge reads it as not typed")
    lesserF.custom[SOOM], lesserF.exact = nil, nil
    -- Switching a typed ID off keeps its mark; removing it drops the mark.
    ns.BM2_SetSpellState(fType.id, SOOM, false)
    check(fType.exact ~= nil and fType.exact[SOOM] == true, "switching a typed filter ID off keeps its mark")
    ns.BM2_SetSpellState(fType.id, SOOM, true)
    check(Alone(iType), "a typed filter ID switched back on matches that aura alone")
    local fGone = ns.BM2_AddFilter("Removed")
    ns.BM2_AddCustomSpell(fGone.id, SOOM, true)
    ns.BM2_SetSpellState(fGone.id, SOOM, nil)
    check(fGone.exact == nil and fGone.spells[SOOM] == nil and fGone.custom[SOOM] == nil,
        "removing a typed filter ID drops its mark")
    check(ns.BM2_AddCustomSpell(fGone.id, SOOM) == true and fGone.exact == nil, "a spell picked after that carries no mark")
    -- The Filter Editor: only its typed Add Spell ID asks for the mark.
    local pages = Read(PAGES)
    check(pages:find("ns.BM2_AddCustomSpell(sel.id, id, true)", 1, true) ~= nil, "the Filter Editor's Add Spell ID asks for the typed mark")
    check(pages:find("ns.BM2_AddCustomSpell(sel.id, k) then", 1, true) ~= nil, "its Search Spells pick asks for none")
    -- Copies between the libraries: an ID a copy brings in carries no mark,
    -- and Player Aura Bars takes a typed ID over alone, a picked one with
    -- its alternates.
    local br = EUI._BM2FilterBridge
    check(br.SpellExact(fType, SOOM) == true and br.SpellExact(fPick, SOOM) == false, "the bridge tells a typed filter ID from a picked one")
    local fCopy = ns.BM2_AddFilter("Copied")
    check(br.AddCustomSpell(fCopy.id, SOOM) == true and fCopy.exact == nil, "an ID a copy brings in carries no mark")
    local pabList, nextPab = {}, 1
    local pabNs = {
        PAB_GetFilter = function(id) for i = 1, #pabList do if pabList[i].id == id then return pabList[i] end end end,
        PAB_AddFilter = function(name)
            local f = { id = nextPab, name = name, spells = {} }
            nextPab = nextPab + 1
            pabList[#pabList + 1] = f
            return f
        end,
        PAB_OtherClientSpell = function() return false end,
    }
    local pabStore = { list = pabList }
    assert(loadstring("local ns, EllesmereUI, PABEnsure, FilterStore = ...\n" .. PabCopySrc, "=PabCopy"))(
        pabNs, EUI, function() return pabStore end, function(s) return s end)
    check(pabNs.PAB_CopyBM2FiltersIn() == true, "Player Aura Bars' copy of the library runs")
    local function Pab(name) for i = 1, #pabList do if pabList[i].name == name then return pabList[i].spells end end return {} end
    check(Pab("Typed")[SOOM] == true and Pab("Typed")[SPIRITFONT] == nil and Pab("Typed")[STATUE] == nil,
        "Player Aura Bars' copy brings a typed filter ID over alone")
    check(Pab("Picked")[SOOM] == true and Pab("Picked")[SPIRITFONT] == true and Pab("Picked")[STATUE] == true,
        "and a picked spell with its alternates")
    -- A library with no such answer (an older one): every spell fans out.
    local keepExact = br.SpellExact
    br.SpellExact = nil
    pabNs.PAB_CopyBM2FiltersIn()
    check(Pab("Typed")[SPIRITFONT] == true, "a library that tells no typed IDs: every spell fans out")
    br.SpellExact = keepExact

    -- After all of it the preset groups are still what they were.
    check(PresetMaps(ns, A, mine) == presets0, "the seeded preset groups changed after the typed IDs")

    -- The New Indicator popup types the same way on its own picks.
    local popup, dd, Create = NewPopup(ns, EUI)
    local plist = Actions(dd.items())
    check(#plist == 1 and plist[1].label == CUSTOM and plist[1].tooltip == nil,
        "the New Indicator popup offers the one Custom Spell ID action")
    Confirm(plist[1], tostring(SOOM))
    check(popup._v2Extras[SOOM] == true and popup._v2Exact[SOOM] == true, "popup: a typed ID is picked and marked")
    check(dd.rereads == 1, "popup: the dropdown reads its list again, so it names the typed spell at once")
    local prow = RowsUnder(dd.items(), "Selected")
    check(#prow == 1 and prow[1].label == "Spell " .. SOOM, "popup: its row reads the plain name")
    dd.setter(SOOM, false)
    check(popup._v2Extras[SOOM] == nil and popup._v2Exact[SOOM] == nil, "popup: unchecking a typed ID drops its mark")
    dd.setter(SOOM, true)
    check(popup._v2Extras[SOOM] == true and popup._v2Exact[SOOM] == nil, "popup: a pick from Presets carries no mark")
    Confirm(plist[1], tostring(SPIRITFONT))
    Confirm(plist[1], "x")
    local made = { spells = {} }
    Create(made)
    check(#made.spells == 2 and made.spells[1] == SOOM and made.spells[2] == SPIRITFONT,
        "popup: Create hands the picked IDs to the new indicator")
    check(made.exactSpells ~= nil and made.exactSpells[SPIRITFONT] == true and made.exactSpells[SOOM] == nil,
        "popup: and marks only the typed one")
    -- Typing an ID the popup already holds from Presets narrows it there too.
    Confirm(plist[1], tostring(SOOM))
    check(popup._v2Exact[SOOM] == true, "popup: typing a picked ID marks it")
end

-------------------------------------------------------------------------------
--  WoW Forever: ranks stay one spell
-------------------------------------------------------------------------------
do
    local EUI, ns, A = NewWorld(true)
    local ap = ns.BM2_ForeverAltPrimary
    local rank1 = 139 -- Renew rank 1, an alternate of the family primary
    local prim = ap and ap[rank1]
    check(prim ~= nil, "Forever: Renew rank 1 is a curated alternate")
    local ind = ns.BM2_AddIndicator("icon", "allspecs")
    local _, list = ExtraSpells(ns, ind)
    check(#list == 1 and list[1].label == CUSTOM and list[1].tooltip == nil, "Forever: the menu offers Custom Spell ID alone")
    Type(ns, ind, tostring(rank1))
    check(Has(ind.spells, rank1), "Forever: the typed rank is stored")
    check(ind.exactSpells == nil, "Forever: no mark is written")
    local out, _, exact = ns.BM2_ResolveSpellsOwn(ind)
    local inc = A.Cand({ spells = out, exactSpells = exact }, out).includeSpellIDs
    check(prim and inc[prim] and inc[rank1] and inc[25315], "Forever: a typed rank matches every rank")
    -- A mark that arrives with a profile from the other client is not read,
    -- on a rank or on the family's primary, and typing the ID again leaves it.
    ind.exactSpells = { [rank1] = true }
    out, _, exact = ns.BM2_ResolveSpellsOwn(ind)
    check(exact == nil, "Forever: a stored mark on a rank is ignored")
    local r0 = refreshes
    Type(ns, ind, tostring(rank1))
    check(ind.exactSpells ~= nil and ind.exactSpells[rank1] == true and refreshes == r0,
        "Forever: typing a held ID leaves a mark from the other client alone")
    Uncheck(ns, ind, rank1)
    check(ind.exactSpells == nil and not Has(ind.spells, rank1), "Forever: unchecking removes the entry and its mark")
    local onPrim = ns.BM2_AddIndicator("icon", "allspecs")
    onPrim.spells = { prim }
    onPrim.exactSpells = { [prim] = true }
    out, _, exact = ns.BM2_ResolveSpellsOwn(onPrim)
    check(exact == nil, "Forever: a stored mark on the primary is ignored")
    inc = A.Cand({ spells = out, exactSpells = exact }, out).includeSpellIDs
    check(prim and inc[prim] and inc[rank1] and inc[25315], "Forever: and the family stays whole")
    -- Filters there: a typed ID carries no mark, and one that came with a
    -- profile is not read.
    local fF = ns.BM2_AddFilter("Typed there")
    check(ns.BM2_AddCustomSpell(fF.id, rank1, true) == true and fF.exact == nil, "Forever: a typed filter ID carries no mark")
    fF.exact = { [rank1] = true }
    local iF = ns.BM2_AddIndicator("icon", "allspecs")
    iF.filters[fF.id] = true
    out, _, exact = ns.BM2_ResolveSpellsOwn(iF)
    check(exact == nil, "Forever: a filter's stored mark is ignored")
    inc = A.Cand({ spells = out, exactSpells = exact }, out).includeSpellIDs
    check(prim and inc[prim] and inc[rank1] and inc[25315], "Forever: and its rank matches every rank")
    check(EUI._BM2FilterBridge.SpellExact(fF, rank1) == false, "Forever: the bridge reads none either")
    -- A mark on the family's primary in a filter is not read either.
    fF.custom[prim], fF.spells[prim], fF.exact[prim] = true, true, true
    out, _, exact = ns.BM2_ResolveSpellsOwn(iF)
    check(exact == nil, "Forever: a filter's stored mark on the primary is ignored")
    fF.custom[prim], fF.spells[prim], fF.exact[prim] = nil, nil, nil
    check(ns.BM2_AddCustomSpell(fF.id, rank1, true) == false, "Forever: typing a held ID again changes nothing")
    -- The New Indicator popup there: typed, created, no mark.
    local popup, dd, Create = NewPopup(ns, EUI)
    local plist = Actions(dd.items())
    check(#plist == 1 and plist[1].label == CUSTOM, "Forever: the New Indicator popup offers Custom Spell ID alone")
    Confirm(plist[1], tostring(rank1))
    local made = { spells = {} }
    Create(made)
    check(#made.spells == 1 and made.spells[1] == rank1 and made.exactSpells == nil,
        "Forever: and creates the indicator with no mark")
end

print(string.format("%d checks, %d failed", count, fails))
if fails > 0 then error(fails .. " check(s) failed") end
