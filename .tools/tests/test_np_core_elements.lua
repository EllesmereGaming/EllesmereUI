-- Stub harness: loads the real Nameplates defaults (EllesmereUINameplates.lua) and the
-- setting getters (EUI_Nameplates_Layout.lua) outside the game, for WoW Forever and retail,
-- and checks the Core Positions element views: the Quest Objective Text read from the legacy
-- Replace Quest Icon with Objective key until questTextSlot is written, the Quest Indicator
-- reading off under it, NP_MaterializeQuestText, the split Show In Instances keys and their
-- fallback, and every element's size (its own key, its slot's size, the slot's default, the
-- None fallbacks, the faction badge riding the classification slot, the pos override), with
-- the sizes of profiles without the new keys equal to the old getters' formulas.
--   lua .tools/tests/test_np_core_elements.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local MAIN_SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")
local LAYOUT_SRC = ReadSource("EllesmereUINameplates/EUI_Nameplates_Layout.lua")

local NEW_KEYS = {
    "debuffCoreSize", "buffCoreSize", "ccCoreSize", "raidMarkerCoreSize", "rareCoreSize",
    "questCoreSize", "factionCoreSize", "questTextSlot",
    "rareShowInInstances", "questShowInInstances", "questTextShowInInstances",
}
local SLOTS = { "top", "right", "left", "topright", "topleft", "bottom" }

-- Any frame method is a no-op.
local function StubFrame()
    return setmetatable({}, { __index = function() return function() end end })
end

-- The parent's fan-out and internals builder, as EllesmereUI_SharedHelpers.lua builds them.
local function NewFanOut(list)
    local has, cur = false, nil
    setmetatable(list, { __newindex = function(l, i, fn)
        rawset(l, i, fn)
        if has then fn(cur) end
    end })
    return function(v)
        has, cur = true, v
        for i = 1, #list do list[i](v) end
    end
end
local function NewInternals(ns, field, t, setters)
    for setter, listName in pairs(setters or {}) do t[setter] = NewFanOut(t[listName]) end
    t.broken = false
    ns[field] = setmetatable(t, { __index = function(_, k)
        error("ns." .. field .. " has no entry " .. tostring(k), 2)
    end })
    return ns[field]
end

-- Loads the main file and the Layout file for one client. Returns ns, the defaults and the
-- profile setter.
local function Load(forever)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.CreateFrame = StubFrame
    env.EllesmereUI = {
        IS_FOREVER = forever,
        _ModuleNS = {},
        NewInternals = NewInternals,
        NewCombatQueue = function() return {} end,
        _Pool = { CreateFrame = StubFrame },
        Glows = {
            FlatKeys = {}, PANDEMIC_BORDER = 101, STEALABLE_BORDER = 102,
            MakeView = function(list) return { list = list, toShared = {} } end,
        },
        AbbreviateValue = function(v) return tostring(v) end,
        IsZeroValue = function(v) return v == 0 end,
        UnitNameFormat = function(mode) return mode end,
        OwnSurnameHidden = function() return false end,
        ShortName = function(name) return name end,
        -- The font family helpers the stale-parent guard asks for (no text is drawn here).
        ApplyModuleFontFamily = function() end,
        SetFontFamily = function() end,
        SetFontObjectFace = function() end,
        SnapshotFontObject = function() end,
        RestoreFontObject = function() end,
        Lite = { NewAddon = function() return {} end },
        PP = {},
        AuraKit = { OnOffensiveDispelChange = function() end, OffensiveDispelTypes = function() end },
        TextTags = { Bind = function() return {} end, UNIT = { keys = { name = { width = 60 } } } },
    }
    local ns = {}
    local main = assert(loadstring(MAIN_SRC, "=EllesmereUINameplates.lua"))
    setfenv(main, env)
    main("EllesmereUINameplates", ns)
    local layout = assert(loadstring(LAYOUT_SRC, "=EUI_Nameplates_Layout.lua"))
    setfenv(layout, env)
    layout("EllesmereUINameplates", ns)
    local I = ns._npInternals
    assert(I.broken == false, "the Layout file did not load to its end")
    return ns, ns.defaults, I.SetProfile
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
-- A stored profile as the game hands it to the module: the defaults merged under the saved
-- values (Lite's merge), so a key with no defaults entry reads nil while unset.
local function Fresh(D, saved)
    local prof = Copy(D)
    for k, v in pairs(saved or {}) do prof[k] = v end
    return prof
end

local function Eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

for _, forever in ipairs({ true, false }) do
    local tag = forever and "forever" or "retail"
    local ns, D, SetProfile = Load(forever)
    local function W(what) return tag .. ": " .. what end

    ---------------------------------------------------------------------------
    -- 1. defaults: no new key has an entry; the legacy key keeps its per-client default
    ---------------------------------------------------------------------------
    for _, k in ipairs(NEW_KEYS) do Eq(D[k], nil, W("defaults." .. k)) end
    Eq(D.replaceQuestIconWithObjective, forever, W("the Replace default"))
    Eq(D.classificationShowInInstances, forever, W("the Show In Instances default"))
    Eq(D.questObjectiveTextSize, 14, W("the Quest Objective Text Size default"))
    Eq(D.showQuestObjectiveTypeIcon, false, W("quest objective type icon default"))
    Eq(D.questObjectiveTypeIconScale, 100, W("quest objective type icon scale default"))

    -- the key tables, exactly as the options and the preview index them
    local SK = ns.NP_CORE_SIZE_KEY
    Eq(SK.debuffs, "debuffCoreSize"); Eq(SK.buffs, "buffCoreSize"); Eq(SK.ccs, "ccCoreSize")
    Eq(SK.raidmarker, "raidMarkerCoreSize"); Eq(SK.rare, "rareCoreSize")
    Eq(SK.quest, "questCoreSize"); Eq(SK.faction, "factionCoreSize")
    local n = 0
    for _ in pairs(SK) do n = n + 1 end
    Eq(n, 7, W("NP_CORE_SIZE_KEY entries"))
    local IK = ns.NP_SHOW_IN_INSTANCES_KEY
    Eq(IK.rare, "rareShowInInstances"); Eq(IK.quest, "questShowInInstances")
    Eq(IK.questtext, "questTextShowInInstances")

    -- display presets carry every new key, never the legacy key or the text size
    local keys = {}
    ns._appendDisplayPresetKeys(keys)
    local has = {}
    for _, k in ipairs(keys) do has[k] = true end
    for _, k in ipairs(NEW_KEYS) do assert(has[k], W("display presets miss " .. k)) end
    assert(not has.replaceQuestIconWithObjective and not has.questObjectiveTextSize,
        W("display presets must not carry the legacy key or the text size"))

    ---------------------------------------------------------------------------
    -- 2. the Quest Objective Text view on a fresh profile (and with no profile at all)
    ---------------------------------------------------------------------------
    local fp = Fresh(D)
    Eq(ns.NP_LegacyQuestText(fp), forever, W("fresh legacy"))
    Eq(ns.NP_GetQuestTextSlot(fp), forever and "topleft" or "none", W("fresh text slot"))
    Eq(ns.NP_ElementSlot("questtext", fp), forever and "topleft" or "none", W("fresh questtext slot"))
    Eq(ns.NP_QuestIconOn(fp), not forever, W("fresh quest icon"))
    -- no db and no live profile: the defaults
    Eq(ns.NP_GetQuestTextSlot(), forever and "topleft" or "none", W("no profile text slot"))
    Eq(ns.NP_QuestIconOn(), not forever, W("no profile quest icon"))
    Eq(ns.NP_LegacyQuestText({}), forever, W("an unmerged profile reads the defaults"))
    -- the live profile
    SetProfile(fp)
    Eq(ns.NP_GetQuestTextSlot(), forever and "topleft" or "none", W("live text slot"))
    Eq(ns.NP_QuestIconOn(), not forever, W("live quest icon"))
    Eq(ns.NP_LegacyQuestText(), forever, W("live legacy"))

    ---------------------------------------------------------------------------
    -- 3. Replace stored either way
    ---------------------------------------------------------------------------
    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationSlot = "right" })
    Eq(ns.NP_LegacyQuestText(fp), true, W("Replace on"))
    Eq(ns.NP_GetQuestTextSlot(fp), "right", W("Replace on: the indicator's slot"))
    Eq(ns.NP_QuestIconOn(fp), false, W("Replace on: the quest icon reads off"))
    fp = Fresh(D, { replaceQuestIconWithObjective = false })
    Eq(ns.NP_LegacyQuestText(fp), false, W("Replace off"))
    Eq(ns.NP_GetQuestTextSlot(fp), "none", W("Replace off: no text"))
    Eq(ns.NP_QuestIconOn(fp), true, W("Replace off: the quest icon"))

    ---------------------------------------------------------------------------
    -- 4. questTextSlot written: the legacy key is ignored
    ---------------------------------------------------------------------------
    fp = Fresh(D, { replaceQuestIconWithObjective = true, questTextSlot = "bottom" })
    Eq(ns.NP_LegacyQuestText(fp), false, W("own slot: no legacy"))
    Eq(ns.NP_GetQuestTextSlot(fp), "bottom", W("own slot"))
    Eq(ns.NP_QuestIconOn(fp), true, W("own slot: the quest icon on"))
    fp = Fresh(D, { replaceQuestIconWithObjective = true, questTextSlot = "none" })
    Eq(ns.NP_GetQuestTextSlot(fp), "none", W("own slot none"))
    Eq(ns.NP_QuestIconOn(fp), true, W("own slot none: the quest icon on"))
    fp = Fresh(D, { replaceQuestIconWithObjective = false, questTextSlot = "left" })
    Eq(ns.NP_GetQuestTextSlot(fp), "left", W("own slot with Replace off"))

    ---------------------------------------------------------------------------
    -- 5. the Elite/Rare and Quest boxes
    ---------------------------------------------------------------------------
    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationHideQuest = true })
    Eq(ns.NP_LegacyQuestText(fp), false, W("Quest box off: no legacy"))
    Eq(ns.NP_GetQuestTextSlot(fp), "none", W("Quest box off: no text"))
    Eq(ns.NP_QuestIconOn(fp), false, W("Quest box off: no quest icon"))
    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationHideRare = true })
    Eq(ns.NP_LegacyQuestText(fp), true, W("the Elite/Rare box does not touch the view"))
    Eq(ns.NP_GetQuestTextSlot(fp), "topleft", W("Elite/Rare off: the text"))
    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationSlot = "none" })
    Eq(ns.NP_LegacyQuestText(fp), false, W("Rare/Quest slot None: no legacy"))
    Eq(ns.NP_GetQuestTextSlot(fp), "none", W("Rare/Quest slot None: no text"))
    Eq(ns.NP_QuestIconOn(fp), false, W("Rare/Quest slot None: no quest icon"))
    fp = Fresh(D, { replaceQuestIconWithObjective = false, classificationHideQuest = true })
    Eq(ns.NP_QuestIconOn(fp), false, W("Quest box off, Replace off"))

    ---------------------------------------------------------------------------
    -- 6. NP_MaterializeQuestText: writes the view, never the legacy key
    ---------------------------------------------------------------------------
    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationSlot = "left" })
    ns.NP_MaterializeQuestText(fp)
    Eq(fp.questTextSlot, "left", W("materialized legacy: the text takes the slot"))
    Eq(fp.classificationHideQuest, true, W("materialized legacy: the Quest box unchecked"))
    Eq(fp.replaceQuestIconWithObjective, true, W("materialize must not write the legacy key"))
    Eq(ns.NP_LegacyQuestText(fp), false, W("materialized: legacy no longer read"))
    Eq(ns.NP_GetQuestTextSlot(fp), "left", W("materialized: same slot"))
    Eq(ns.NP_QuestIconOn(fp), false, W("materialized: quest icon still off"))
    -- the legacy key is never read again
    fp.replaceQuestIconWithObjective = false
    Eq(ns.NP_GetQuestTextSlot(fp), "left", W("materialized: Replace no longer matters"))
    -- idempotent
    ns.NP_MaterializeQuestText(fp)
    Eq(fp.questTextSlot, "left", W("second materialize"))

    fp = Fresh(D, { replaceQuestIconWithObjective = false })
    ns.NP_MaterializeQuestText(fp)
    Eq(fp.questTextSlot, "none", W("materialized off: text slot none"))
    Eq(fp.classificationHideQuest, false, W("materialized off: Quest box untouched"))
    Eq(ns.NP_QuestIconOn(fp), true, W("materialized off: quest icon on"))

    fp = Fresh(D, { replaceQuestIconWithObjective = true, classificationHideQuest = true })
    ns.NP_MaterializeQuestText(fp)
    Eq(fp.questTextSlot, "none", W("materialized with the Quest box off"))
    Eq(fp.classificationHideQuest, true, W("materialized with the Quest box off: kept"))

    fp = Fresh(D, { replaceQuestIconWithObjective = true, questTextSlot = "right", classificationHideQuest = false })
    ns.NP_MaterializeQuestText(fp)
    Eq(fp.questTextSlot, "right", W("materialize leaves a written slot"))
    Eq(fp.classificationHideQuest, false, W("materialize leaves the Quest box of a written slot"))

    ns.NP_MaterializeQuestText(nil)  -- no profile: nothing to write

    -- every combination: the visible state is the same before and after
    for _, replace in ipairs({ true, false }) do
        for _, hideQuest in ipairs({ true, false, "unset" }) do
            for _, hideRare in ipairs({ true, false }) do
                for _, cls in ipairs({ "topleft", "right", "none" }) do
                    local saved = { replaceQuestIconWithObjective = replace,
                        classificationHideRare = hideRare, classificationSlot = cls }
                    if hideQuest ~= "unset" then saved.classificationHideQuest = hideQuest end
                    local prof = Fresh(D, saved)
                    if hideQuest == "unset" then prof.classificationHideQuest = nil end
                    local slot, icon = ns.NP_GetQuestTextSlot(prof), ns.NP_QuestIconOn(prof)
                    ns.NP_MaterializeQuestText(prof)
                    local what = W(("replace=%s hideQuest=%s hideRare=%s slot=%s"):format(
                        tostring(replace), tostring(hideQuest), tostring(hideRare), cls))
                    Eq(ns.NP_GetQuestTextSlot(prof), slot, what .. ": text slot")
                    Eq(ns.NP_QuestIconOn(prof), icon, what .. ": quest icon")
                    Eq(prof.classificationHideRare, hideRare, what .. ": Elite/Rare box")
                    Eq(prof.replaceQuestIconWithObjective, replace, what .. ": legacy key")
                    assert(prof.questTextSlot ~= nil, what .. ": questTextSlot not written")
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- 7. Show In Instances
    ---------------------------------------------------------------------------
    fp = Fresh(D)
    for _, kind in ipairs({ "rare", "quest", "questtext" }) do
        Eq(ns.NP_ShowInInstances(kind, fp), forever, W("fresh " .. kind))
    end
    Eq(ns.NP_ShowInInstances("quest"), forever, W("live fresh"))
    fp = Fresh(D, { classificationShowInInstances = not forever })
    for _, kind in ipairs({ "rare", "quest", "questtext" }) do
        Eq(ns.NP_ShowInInstances(kind, fp), not forever, W("stored fallback " .. kind))
    end
    fp = Fresh(D, { classificationShowInInstances = true, questShowInInstances = false })
    Eq(ns.NP_ShowInInstances("quest", fp), false, W("split key off"))
    Eq(ns.NP_ShowInInstances("rare", fp), true, W("split key off: rare follows the fallback"))
    Eq(ns.NP_ShowInInstances("questtext", fp), true, W("split key off: text follows the fallback"))
    fp = Fresh(D, { classificationShowInInstances = false, rareShowInInstances = true,
        questTextShowInInstances = true })
    Eq(ns.NP_ShowInInstances("rare", fp), true, W("split key on"))
    Eq(ns.NP_ShowInInstances("questtext", fp), true, W("split text key on"))
    Eq(ns.NP_ShowInInstances("quest", fp), false, W("split key on: quest follows the fallback"))
    local unmerged = {}
    Eq(ns.NP_ShowInInstances("rare", unmerged), forever, W("an unmerged profile reads the default"))

    ---------------------------------------------------------------------------
    -- 8. element slots
    ---------------------------------------------------------------------------
    fp = Fresh(D, { debuffSlot = "top", buffSlot = "left", ccSlot = "bottom", raidMarkerPos = "right",
        classificationSlot = "topright", factionSlot = "topleft" })
    Eq(ns.NP_ElementSlot("debuffs", fp), "top"); Eq(ns.NP_ElementSlot("buffs", fp), "left")
    Eq(ns.NP_ElementSlot("ccs", fp), "bottom"); Eq(ns.NP_ElementSlot("raidmarker", fp), "right")
    Eq(ns.NP_ElementSlot("rare", fp), "topright"); Eq(ns.NP_ElementSlot("quest", fp), "topright")
    Eq(ns.NP_ElementSlot("faction", fp), "topleft")
    fp.classificationIncludeFaction = true
    Eq(ns.NP_ElementSlot("faction", fp), "topright", W("Rare/Quest + Faction: the badge rides"))

    ---------------------------------------------------------------------------
    -- 9. element sizes
    ---------------------------------------------------------------------------
    fp = Fresh(D)
    Eq(ns.NP_ElementSize("debuffs", fp), D.topSlotSize, W("debuffs: Top's size"))
    Eq(ns.NP_ElementSize("buffs", fp), D.leftSlotSize, W("buffs: Left's size"))
    Eq(ns.NP_ElementSize("ccs", fp), D.rightSlotSize, W("ccs: Right's size"))
    Eq(ns.NP_ElementSize("raidmarker", fp), D.toprightSlotSize, W("marker: Top Right's size"))
    Eq(ns.NP_ElementSize("rare", fp), D.topleftSlotSize, W("rare: Top Left's size"))
    Eq(ns.NP_ElementSize("quest", fp), D.topleftSlotSize, W("quest: Top Left's size"))
    Eq(ns.NP_ElementSize("faction", fp), 20, W("faction: slot None"))
    -- a slot's stored size
    fp.topSlotSize, fp.topleftSlotSize = 31, 17
    Eq(ns.NP_ElementSize("debuffs", fp), 31, W("stored slot size"))
    Eq(ns.NP_ElementSize("rare", fp), 17, W("stored slot size, rare"))
    -- the element's own size wins
    fp.debuffCoreSize, fp.questCoreSize = 18, 29
    Eq(ns.NP_ElementSize("debuffs", fp), 18, W("own size"))
    Eq(ns.NP_ElementSize("quest", fp), 29, W("own size, quest"))
    Eq(ns.NP_ElementSize("rare", fp), 17, W("rare keeps the slot's size beside its quest twin"))
    fp.buffCoreSize = "x"
    Eq(ns.NP_ElementSize("buffs", fp), D.leftSlotSize, W("a non-number own size is ignored"))
    -- the slot's default (an unmerged profile)
    unmerged = { buffSlot = "bottom" }
    Eq(ns.NP_ElementSize("buffs", unmerged), D.bottomSlotSize, W("slot default"))
    -- the None fallbacks
    fp = Fresh(D, { debuffSlot = "none", buffSlot = "none", ccSlot = "none", raidMarkerPos = "none",
        classificationSlot = "none", factionSlot = "none" })
    Eq(ns.NP_ElementSize("debuffs", fp), D.debuffIconSize, W("debuffs None"))
    Eq(ns.NP_ElementSize("buffs", fp), D.buffIconSize, W("buffs None"))
    Eq(ns.NP_ElementSize("ccs", fp), D.ccIconSize, W("ccs None"))
    Eq(ns.NP_ElementSize("raidmarker", fp), D.raidMarkerSize, W("marker None"))
    Eq(ns.NP_ElementSize("rare", fp), D.rareEliteIconSize, W("rare None"))
    Eq(ns.NP_ElementSize("quest", fp), D.rareEliteIconSize, W("quest None"))
    Eq(ns.NP_ElementSize("faction", fp), 20, W("faction None"))
    Eq(D.debuffIconSize, 26); Eq(D.buffIconSize, 24); Eq(D.ccIconSize, 24)
    Eq(D.raidMarkerSize, 24); Eq(D.rareEliteIconSize, 20)
    fp.raidMarkerCoreSize = 33
    Eq(ns.NP_ElementSize("raidmarker", fp), 33, W("own size while the slot is None"))
    -- the faction badge riding the classification slot
    fp = Fresh(D, { factionSlot = "none", classificationSlot = "right", rightSlotSize = 33,
        classificationIncludeFaction = true })
    Eq(ns.NP_ElementSize("faction", fp), 33, W("the badge takes the classification slot's size"))
    fp.classificationIncludeFaction = false
    Eq(ns.NP_ElementSize("faction", fp), 20, W("its own slot again"))
    -- the pos override (the quest icon standing in for the text, in the text's slot)
    fp = Fresh(D, { classificationSlot = "topleft", bottomSlotSize = 40 })
    Eq(ns.NP_ElementSize("quest", fp, "bottom"), 40, W("pos override"))
    Eq(ns.NP_ElementSize("quest", fp, "none"), D.rareEliteIconSize, W("pos override None"))
    fp.questCoreSize = 22
    Eq(ns.NP_ElementSize("quest", fp, "bottom"), 22, W("own size beats the pos override"))
    -- the Quest Objective Text's Text Size
    Eq(ns.NP_QuestTextSize(Fresh(D)), 14, W("text size default"))
    Eq(ns.NP_QuestTextSize(Fresh(D, { questObjectiveTextSize = 18 })), 18, W("text size stored"))

    -- the live getters route through it
    fp = Fresh(D, { topSlotSize = 30, debuffCoreSize = 21, rightSlotSize = 19, raidMarkerPos = "right",
        factionSlot = "bottom", bottomSlotSize = 27, ccSlot = "none" })
    SetProfile(fp)
    Eq(ns.GetDebuffIconSize(), 21, W("live debuffs"))
    Eq(ns.GetBuffIconSize(), D.leftSlotSize, W("live buffs"))
    Eq(ns.GetCCIconSize(), D.ccIconSize, W("live ccs None"))
    Eq(ns.GetRaidMarkerSize(), 19, W("live marker"))
    Eq(ns.GetRareEliteIconSize(), D.topleftSlotSize, W("live rare"))
    Eq(ns.NP_GetFactionIconSize(), 27, W("live faction"))
    Eq(ns.NP_ElementSize("quest"), D.topleftSlotSize, W("live quest"))
    Eq(ns.GetSlotSize("top"), 30, W("the slot's own size stays readable"))

    ---------------------------------------------------------------------------
    -- 10. no new key set: every size is the old getters' (the formulas before the split)
    ---------------------------------------------------------------------------
    local function OldSlot(prof, pos, last)
        return prof[pos .. "SlotSize"] or D[pos .. "SlotSize"] or last
    end
    local function Old(prof)
        local o = {}
        local ds = prof.debuffSlot or D.debuffSlot
        o.debuffs = (ds == "none") and (D.debuffIconSize or 26) or OldSlot(prof, ds, 24)
        local bs = prof.buffSlot or D.buffSlot
        o.buffs = (bs == "none") and (D.buffIconSize or 24) or OldSlot(prof, bs, 24)
        local cs = prof.ccSlot or D.ccSlot
        o.ccs = (cs == "none") and (D.ccIconSize or 24) or OldSlot(prof, cs, 24)
        local rm = prof.raidMarkerPos or D.raidMarkerPos
        o.raidmarker = (rm == "none") and (D.raidMarkerSize or 24) or OldSlot(prof, rm, 24)
        local cl = prof.classificationSlot or D.classificationSlot
        o.rare = (cl == "none") and (D.rareEliteIconSize or 20) or OldSlot(prof, cl, 20)
        o.quest = o.rare
        local fs = prof.classificationIncludeFaction and cl or (prof.factionSlot or D.factionSlot)
        o.faction = (fs == "none") and 20 or OldSlot(prof, fs, 20)
        return o
    end
    local all = { "none" }
    for _, s in ipairs(SLOTS) do all[#all + 1] = s end
    local seed = 7
    local function Pick(list)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return list[seed % #list + 1]
    end
    for _ = 1, 400 do
        local saved = {
            debuffSlot = Pick(all), buffSlot = Pick(all), ccSlot = Pick(all), raidMarkerPos = Pick(all),
            classificationSlot = Pick(all), factionSlot = Pick(all),
            classificationIncludeFaction = Pick({ true, false }),
        }
        for _, s in ipairs(SLOTS) do
            local v = Pick({ "default", 12, 20, 26, 38 })
            if v ~= "default" then saved[s .. "SlotSize"] = v end
        end
        local prof = Fresh(D, saved)
        local old = Old(prof)
        SetProfile(prof)
        for elem, size in pairs(old) do
            Eq(ns.NP_ElementSize(elem, prof), size, W("unchanged size of " .. elem))
        end
        Eq(ns.GetDebuffIconSize(), old.debuffs, W("unchanged live debuffs"))
        Eq(ns.GetRaidMarkerSize(), old.raidmarker, W("unchanged live marker"))
        Eq(ns.GetRareEliteIconSize(), old.rare, W("unchanged live rare"))
        Eq(ns.NP_GetFactionIconSize(), old.faction, W("unchanged live faction"))
    end
    SetProfile(nil)
    print(tag .. ": ok")
end

print("nameplates core elements harness: ok")
