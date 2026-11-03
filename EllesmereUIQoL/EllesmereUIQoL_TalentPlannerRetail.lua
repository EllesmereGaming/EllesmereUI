if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI.IS_FOREVER then return end -- Forever Essentials has its own planner
-------------------------------------------------------------------------------
--  EllesmereUIQoL_TalentPlannerRetail.lua
--  Talent Planner: plan the order in which to learn talents on the game's
--  class, specialization and hero trees; a level up then learns the next
--  planned talent it can pay for.
--
--  Plan Talents (under the talent window) turns plan mode on: a click on a
--  talent plans its next rank (a choice node asks which choice), a
--  right-click takes its last planned rank back, and the planned talents that
--  depended on it with it. A talent can be planned only once what unlocks it
--  (the talents before it, the points-spent gate, the active hero tree) is
--  learned or planned earlier. Each planned talent shows its place in the
--  order, 1 being the next to learn. The plan is kept per specialization, in
--  order, as node ids: there is no level formula.
--
--  Learning: at level up (once the new point reaches the tree), at login and
--  when plan mode ends, the first planned talent that is open and paid for is
--  staged with C_Traits (a choice node with SetSelection, any other with
--  PurchaseRank), again for every point left, and the lot is applied with one
--  C_ClassTalents.CommitConfig, as the Apply Changes button does. Only out of
--  combat, and never over talent changes the player has not applied yet, the
--  Starter Build, or a commit that is still running: the planner says so in
--  chat and waits. Leaving plan mode with Done always says why when it learns
--  nothing; /euitp prints the planner's state.
--
--  The marks are frames of our own, children of the game's talent buttons
--  (read through EnumerateAllTalentButtons, never written); they take clicks
--  only in plan mode.
-------------------------------------------------------------------------------
-- Settings live in EllesmereUIDB.talentPlannerRetail; unset keys read these.
--   plans   [specID] = { { n = nodeID, r = rank, e = entryID (choice nodes) }, ... }
local F = EllesmereUI.NewFeature("talentPlannerRetail", { enabled = false }, nil,
    { group = "Quality of Life", folder = "EllesmereUIQoL" })

local queue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
local marks = setmetatable({}, { __mode = "k" }) -- talent button -> our mark (buttons are pooled)
local events, waiter, layer, planMode
local scheduled, learning
local wantManual -- Done was pressed: the next run says why when it learns nothing
local manualRun  -- the run in progress is such a run
local awaiting   -- a level up whose point has not reached the tree yet
local waitData   -- login: the talent data is not loaded yet
local waiting    -- held back by talent changes the player has not applied
local committing -- the links of the commit we started, until it lands or fails
local told = {}  -- hold-back reasons already said in chat
local lastRefusal -- the last reason nothing was learned, for /euitp
local edgeCache  -- treeID -> node id -> its incoming edges, read once per plan mode

local function Say(msg)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
end

local function SayOnce(reason, msg)
    if told[reason] or not msg then return end
    told[reason] = true
    Say(msg)
end

-------------------------------------------------------------------------------
--  The plan
-------------------------------------------------------------------------------
local function SpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    local id = index and index > 0 and C_SpecializationInfo.GetSpecializationInfo(index)
    return id and id > 0 and id or nil
end

-- The active specialization's plan; create: make it.
local function Plan(create)
    local specID = SpecID()
    if not specID then return nil end
    local cfg = create and F.Cfg() or F.Read()
    if create then
        cfg.plans = cfg.plans or {}
        cfg.plans[specID] = cfg.plans[specID] or {}
    end
    return cfg.plans and cfg.plans[specID]
end

-- The active combat config and its tree, as the talent window reads them; nil
-- until the talent data is loaded.
local function Active()
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetConfigInfo(configID)
    return configID, info and info.treeIDs and info.treeIDs[1]
end

local function Context()
    local specID = SpecID()
    local configID, treeID = Active()
    if specID and configID and treeID then return specID, configID, treeID end
end

local function EntrySpell(configID, entryID)
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    return def and def.spellID, def and def.overrideName
end

-- The entry a node shows: the planned choice, the chosen one, else its first.
local function ShownEntry(info, item)
    return (item and item.e) or (info.activeEntry and info.activeEntry.entryID)
        or (info.entryIDs and info.entryIDs[1])
end

local function EntryName(configID, entryID)
    local spellID, name = EntrySpell(configID, entryID)
    if name and name ~= "" then return name end
    return spellID and C_Spell.GetSpellName(spellID) or ("#" .. tostring(entryID))
end

local function NodeLink(configID, item)
    local info = C_Traits.GetNodeInfo(configID, item.n)
    local spellID = info and EntrySpell(configID, ShownEntry(info, item))
    return spellID and C_Spell.GetSpellLink(spellID) or ("#" .. item.n)
end

local function IsChoice(info)
    return info.type == Enum.TraitNodeType.Selection
end

-- A node of a hero tree the player has not picked: kept in the plan, never
-- numbered or learned.
local function IsDormant(info)
    return info.subTreeID ~= nil and info.subTreeActive == false
end

-- The planned items not learned yet become numbers, 1 being the next:
-- node id -> { its numbers }.
local function Numbers(plan, configID)
    local out, n = {}, 0
    for _, item in ipairs(plan) do
        local info = C_Traits.GetNodeInfo(configID, item.n)
        if info and not IsDormant(info) and (info.ranksPurchased or 0) < item.r then
            n = n + 1
            local list = out[item.n]
            if not list then
                list = {}
                out[item.n] = list
            end
            list[#list + 1] = n
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  What can be planned: the tree simulated with the owned ranks plus the
--  ranks planned before
-------------------------------------------------------------------------------
-- Every incoming edge of the tree's nodes, read once while plan mode is on.
local function Incoming(configID, treeID)
    edgeCache = edgeCache or {}
    local map = edgeCache[treeID]
    if map then return map end
    map = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        for _, edge in ipairs(info and info.visibleEdges or {}) do
            local list = map[edge.targetNode]
            if not list then
                list = {}
                map[edge.targetNode] = list
            end
            list[#list + 1] = { from = nodeID, type = edge.type }
        end
    end
    edgeCache[treeID] = map
    return map
end

local function NewSim(configID, treeID)
    local sim = { configID = configID, ranks = {}, infos = {}, spent = {}, incoming = Incoming(configID, treeID) }
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
        sim.spent[c.traitCurrencyID] = c.spent or 0
    end
    return sim
end

local function SimInfo(sim, nodeID)
    local info = sim.infos[nodeID]
    if info == nil then
        info = C_Traits.GetNodeInfo(sim.configID, nodeID) or false
        sim.infos[nodeID] = info
    end
    return info or nil
end

local function SimRanks(sim, nodeID)
    local r = sim.ranks[nodeID]
    if r == nil then
        local info = SimInfo(sim, nodeID)
        r = info and info.ranksPurchased or 0
        sim.ranks[nodeID] = r
    end
    return r
end

-- Required edges all need their talent; sufficient edges need one of theirs.
local function EdgesMet(sim, nodeID)
    local sufficient, sufficientMet
    for _, edge in ipairs(sim.incoming[nodeID] or {}) do
        if edge.type == Enum.TraitEdgeType.RequiredForAvailability then
            if SimRanks(sim, edge.from) == 0 then return false end
        elseif edge.type == Enum.TraitEdgeType.SufficientForAvailability then
            sufficient = true
            if SimRanks(sim, edge.from) > 0 then sufficientMet = true end
        end
    end
    return not sufficient or sufficientMet == true
end

-- The Available conditions: a points-spent gate counts the planned costs too.
local function GatesMet(sim, info)
    for _, condID in ipairs(info.conditionIDs or {}) do
        local c = C_Traits.GetConditionInfo(sim.configID, condID)
        if c and c.type == Enum.TraitConditionType.Available and not (c.isMet or c.isAlwaysMet or c.isSufficient) then
            if not (c.isGate and c.traitCurrencyID and c.spentAmountRequired) then return false, "condition" end
            if (sim.spent[c.traitCurrencyID] or 0) < c.spentAmountRequired then return false, "gate" end
        end
    end
    return true
end

-- true (or true, "done" when learned already), else false and why: unknown,
-- order, max, hero, choice, edges, gate or condition.
local function CanOpen(sim, item)
    local info = SimInfo(sim, item.n)
    if not info then return false, "unknown" end
    local owned = SimRanks(sim, item.n)
    if owned >= item.r then return true, "done" end
    if item.r > (info.maxRanks or 1) then return false, "max" end
    if IsDormant(info) then return false, "hero" end
    if owned + 1 < item.r then return false, "order" end
    local choice = IsChoice(info)
    if choice then
        local entry = item.e and C_Traits.GetEntryInfo(sim.configID, item.e)
        if not (entry and entry.isAvailable) then return false, "choice" end
    end
    -- Open now in the game's own eyes: nothing to simulate.
    if choice and info.isAvailable and info.meetsEdgeRequirements then return true end
    if not choice and info.canPurchaseRank then return true end
    if not (info.meetsEdgeRequirements or EdgesMet(sim, item.n)) then return false, "edges" end
    return GatesMet(sim, info)
end

local function SimCommit(sim, item)
    sim.ranks[item.n] = item.r
    for _, cost in ipairs(C_Traits.GetNodeCost(sim.configID, item.n) or {}) do
        sim.spent[cost.ID] = (sim.spent[cost.ID] or 0) + cost.amount
    end
end

-- The plan in the first order the tree allows (what cannot wait for a later
-- item keeps its place), what can never open (dropped), and the simulation
-- after the plan. Items of a hero tree that is not active stay as they are.
local function Resolve(plan, configID, treeID)
    local sim = NewSim(configID, treeID)
    local rest, ordered = {}, {}
    for i, item in ipairs(plan) do rest[i] = item end
    local progress = true
    while #rest > 0 and progress do
        progress = false
        for i, item in ipairs(rest) do
            local ok, why = CanOpen(sim, item)
            if ok or why == "hero" then
                if ok and why ~= "done" then SimCommit(sim, item) end
                ordered[#ordered + 1] = item
                table.remove(rest, i)
                progress = true
                break
            end
        end
    end
    return ordered, rest, sim
end

-- Rewrites the plan as Resolve orders it; returns how many items went.
local function Repair(plan, configID, treeID)
    local ordered, dropped, sim = Resolve(plan, configID, treeID)
    local changed = #dropped > 0
    for i, item in ipairs(ordered) do
        if plan[i] ~= item then changed = true end
    end
    if changed then
        for i = #plan, 1, -1 do plan[i] = nil end
        for i, item in ipairs(ordered) do plan[i] = item end
    end
    return #dropped, sim
end

local function WhyText(why)
    if why == "edges" then return EllesmereUI.L("a talent before it is not learned or planned yet") end
    if why == "gate" then return EllesmereUI.L("more points must be spent in the tree first") end
    if why == "condition" then return EllesmereUI.L("it is locked by a requirement") end
    if why == "hero" then return EllesmereUI.L("its hero tree is not the active one") end
    if why == "choice" then return EllesmereUI.L("that choice is not available") end
    if why == "max" then return EllesmereUI.L("it cannot take more ranks") end
    if why == "cost" then return EllesmereUI.L("it costs more points than you have") end
    if why == "unknown" then return EllesmereUI.L("it is not on this tree") end
    return EllesmereUI.L("the game would not take it")
end

-------------------------------------------------------------------------------
--  Learning
-------------------------------------------------------------------------------
local function Currencies(configID, treeID)
    local money, any = {}, false
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
        money[c.traitCurrencyID] = c.quantity
        if c.quantity > 0 then any = true end
    end
    return money, any
end

local function CanPay(configID, nodeID, money)
    for _, cost in ipairs(C_Traits.GetNodeCost(configID, nodeID) or {}) do
        if (money[cost.ID] or 0) < cost.amount then return false end
    end
    return true
end

-- "done" (learned already), "ready" (the game takes it now) or nil.
local function Check(configID, item, money)
    local info = C_Traits.GetNodeInfo(configID, item.n)
    if not info then return nil end
    if (info.ranksPurchased or 0) >= item.r then return "done" end
    if IsDormant(info) or not info.meetsEdgeRequirements then return nil end
    if IsChoice(info) then
        local entry = item.e and C_Traits.GetEntryInfo(configID, item.e)
        if not (entry and entry.isAvailable and info.isAvailable) then return nil end
    elseif not info.canPurchaseRank then
        return nil
    end
    return CanPay(configID, item.n, money) and "ready" or nil
end

-- Why a planned item is not ready: the code WhyText turns into words.
local function Diagnose(configID, item, money)
    local info = C_Traits.GetNodeInfo(configID, item.n)
    if not info then return "unknown" end
    if IsDormant(info) then return "hero" end
    if not info.meetsEdgeRequirements then return "edges" end
    if IsChoice(info) then
        local entry = item.e and C_Traits.GetEntryInfo(configID, item.e)
        if not (entry and entry.isAvailable) then return "choice" end
    end
    if not CanPay(configID, item.n, money) then return "cost" end
    if IsChoice(info) and not info.isAvailable then return "condition" end
    if not IsChoice(info) and not info.canPurchaseRank then return "condition" end
    return "other"
end

local function Buy(configID, item)
    local info = C_Traits.GetNodeInfo(configID, item.n)
    if info and IsChoice(info) then
        return C_Traits.SetSelection(configID, item.n, item.e)
    end
    return C_Traits.PurchaseRank(configID, item.n)
end

-- Stages the first ready planned item, again while a currency has points,
-- each pass reading the tree afresh: a learned talent opens the next ones. An
-- item the game refuses is set aside (failed) and the others go on.
local function Stage(configID, treeID, plan, out, failed)
    local skip = {}
    for _ = 1, #plan * 2 do
        local money, any = Currencies(configID, treeID)
        if not any then return end
        local pick
        for _, item in ipairs(plan) do
            if not skip[item] and Check(configID, item, money) == "ready" then
                pick = item
                break
            end
        end
        if not pick then return end
        if Buy(configID, pick) then
            out[#out + 1] = pick
        else
            skip[pick] = true
            failed[#failed + 1] = pick
        end
    end
end

-- The first planned item not learned yet that is not dormant.
local function FirstPending(configID, plan)
    for _, item in ipairs(plan) do
        local info = C_Traits.GetNodeInfo(configID, item.n)
        if info and not IsDormant(info) and (info.ranksPurchased or 0) < item.r then return item end
    end
end

-- A talent commit is a cast; the game refuses another change until it ends.
local function CommitCastRunning()
    local spellID = select(9, UnitCastingInfo("player"))
    if spellID == nil or issecretvalue(spellID) then return false end
    return spellID == Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID
end

-- The events each flag waits on.
local function Sync()
    if not events then return end
    local function Set(event, on)
        if on then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    Set("TRAIT_TREE_CURRENCY_INFO_UPDATED", awaiting)
    Set("PLAYER_TALENT_UPDATE", waitData)
    Set("TRAIT_CONFIG_UPDATED", waiting or committing)
    Set("CONFIG_COMMIT_FAILED", committing)
end

local function Rollback(configID)
    if InCombatLockdown() then
        queue.Defer("TalentPlannerRollback", function() C_Traits.RollbackConfig(configID) end)
    else
        C_Traits.RollbackConfig(configID)
    end
end

-- Nothing learned for this reason: kept for /euitp, said at once after Done
-- and otherwise once. quiet: only after Done (it is normal otherwise).
local function Refuse(reason, msg, quiet)
    lastRefusal = msg
    if manualRun then Say(msg) elseif not quiet then SayOnce(reason, msg) end
end

local function Hold(reason, msg, wait)
    waiting = wait
    Sync()
    Refuse(reason, msg)
end

-- Learns the planned talents the points allow. Waits out combat.
local function Learn()
    if not F.Enabled() or learning then return end
    if InCombatLockdown() then
        queue.Defer("TalentPlanner", Learn)
        return
    end
    manualRun, wantManual = wantManual, nil
    local specID = SpecID()
    local configID, treeID = Active()
    waitData = not (specID and configID and treeID)
    Sync()
    if waitData then return Refuse("data", EllesmereUI.L("Talent Planner: the talent data is not loaded yet."), true) end
    if committing then
        -- The commit landed without us hearing of it: nothing is staged any more.
        if C_Traits.ConfigHasStagedChanges(configID) ~= false or CommitCastRunning() then
            return Refuse("busy", EllesmereUI.L("Talent Planner: a talent change is still being applied."), true)
        end
        committing = nil
        Sync()
    end
    local plan = Plan()
    if not (plan and #plan > 0) then
        return Refuse("empty", EllesmereUI.L("Talent Planner: nothing is planned for this specialization."), true)
    end
    local _, any = Currencies(configID, treeID)
    if not any then return Refuse("points", EllesmereUI.L("Talent Planner: you have no unspent talent points."), true) end
    awaiting = false
    waiting = false
    Sync()

    if C_ClassTalents.GetStarterBuildActive() then
        return Hold("starter", EllesmereUI.L("Talent Planner: the Starter Build is active. Pick a loadout of your own and the plan continues."), true)
    end
    if C_Traits.ConfigHasStagedChanges(configID) ~= false then
        return Hold("staged", EllesmereUI.L("Talent Planner: you have talent changes that are not applied. Apply them and the plan continues."), true)
    end
    if CommitCastRunning() then
        return Hold("cast", EllesmereUI.L("Talent Planner: a talent change is still being applied."), true)
    end
    local canEdit, why = C_ClassTalents.CanEditTalents()
    if not canEdit then
        return Hold("edit", EllesmereUI.Lf("Talent Planner: talents cannot be changed right now. %s", why or ""), false)
    end

    local learned, failed = {}, {}
    learning = true
    local ok, err = pcall(Stage, configID, treeID, plan, learned, failed)
    learning = false
    if not ok then
        Rollback(configID)
        geterrorhandler()(err)
        return
    end
    if #learned == 0 then
        if #failed > 0 then
            return Refuse("refused", EllesmereUI.Lf("Talent Planner: the game did not take %s.", NodeLink(configID, failed[1])))
        end
        local item = FirstPending(configID, plan)
        if not item then
            return Refuse("done", EllesmereUI.L("Talent Planner: everything planned is already learned."), true)
        end
        local money = Currencies(configID, treeID)
        return Refuse("blocked", EllesmereUI.Lf("Talent Planner: %1$s cannot be learned yet: %2$s.",
            NodeLink(configID, item), WhyText(Diagnose(configID, item, money))))
    end
    local canChange, canAdd, changeError = C_ClassTalents.CanChangeTalents()
    local loadoutID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    if not tContains(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}, loadoutID) then loadoutID = nil end
    if (canChange or canAdd) and C_ClassTalents.CommitConfig(loadoutID) then
        local links = {}
        for i, item in ipairs(learned) do links[i] = NodeLink(configID, item) end
        committing = links
        lastRefusal = nil
        told = {}
        Sync()
    else
        Rollback(configID)
        Refuse("commit", EllesmereUI.Lf("Talent Planner: talents cannot be changed right now. %s", changeError or ""))
    end
end

-- Changes come in bursts, and some arrive inside the game's own talent code:
-- act on the next frame, once.
local function Soon()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        Learn()
    end)
end

local function Landed(configID)
    if issecretvalue(configID) or configID ~= C_ClassTalents.GetActiveConfigID() then return end
    Say(EllesmereUI.Lf("Talents learned: %s", table.concat(committing, " ")))
    committing = nil
    Sync()
end

local function Failed(configID)
    if issecretvalue(configID) then return end
    local activeID = C_ClassTalents.GetActiveConfigID()
    if activeID then Rollback(activeID) end
    committing = nil
    Sync()
    Say(EllesmereUI.L("Talent Planner: the talent change was interrupted. It is tried again at your next level up, at login or when you leave plan mode."))
end

local function OnEvent(_, event, a, b)
    if event == "PLAYER_LEVEL_UP" then
        awaiting = true
        Sync()
        Soon()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Login and reload only: a point may have come while the addon was off.
        if a or b then
            committing = nil
            Sync()
            Soon()
        end
    elseif event == "TRAIT_CONFIG_UPDATED" then
        if committing then Landed(a) else Soon() end
    elseif event == "CONFIG_COMMIT_FAILED" then
        if committing then Failed(a) end
    else
        Soon()
    end
end

-------------------------------------------------------------------------------
--  /euitp: the planner's state, to say why it learns nothing
-------------------------------------------------------------------------------
local function Report()
    local function P(msg) Say("|cffaaaaaaTalent Planner:|r " .. msg) end
    if not F.Enabled() then P("off (Quality of Life > Talent Planner).") return end
    local specID = SpecID()
    local configID, treeID = Active()
    P(("spec %s, config %s, tree %s, combat %s, window %s"):format(tostring(specID), tostring(configID),
        tostring(treeID), tostring(InCombatLockdown()), tostring(layer ~= nil and layer:IsVisible() or false)))
    if not (specID and configID and treeID) then P("talent data not loaded.") return end
    local plan = Plan() or {}
    local pending = 0
    for _, item in ipairs(plan) do
        local info = C_Traits.GetNodeInfo(configID, item.n)
        if info and (info.ranksPurchased or 0) < item.r then pending = pending + 1 end
    end
    P(("plan: %d items, %d not learned yet."):format(#plan, pending))
    local money = {}
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
        money[c.traitCurrencyID] = c.quantity
        P(("currency %s: %s unspent, %s spent."):format(tostring(c.traitCurrencyID), tostring(c.quantity), tostring(c.spent)))
    end
    local hero = C_ClassTalents.GetActiveHeroTalentSpec()
    P(("hero tree (sub tree id): %s."):format(tostring(hero)))
    P(("staged changes: %s, starter build: %s, commit cast: %s, committing: %s."):format(
        tostring(C_Traits.ConfigHasStagedChanges(configID)), tostring(C_ClassTalents.GetStarterBuildActive()),
        tostring(CommitCastRunning()), tostring(committing ~= nil)))
    local canEdit, why = C_ClassTalents.CanEditTalents()
    P(("can edit talents: %s %s"):format(tostring(canEdit), tostring(why or "")))
    local item = FirstPending(configID, plan)
    if item then
        local info = C_Traits.GetNodeInfo(configID, item.n)
        P(("next: node %d rank %d entry %s, ranksPurchased %s, canPurchaseRank %s, meetsEdgeRequirements %s, isAvailable %s, subTree %s (active %s)."):format(
            item.n, item.r, tostring(item.e), tostring(info.ranksPurchased), tostring(info.canPurchaseRank),
            tostring(info.meetsEdgeRequirements), tostring(info.isAvailable), tostring(info.subTreeID),
            tostring(info.subTreeActive)))
        for _, cost in ipairs(C_Traits.GetNodeCost(configID, item.n) or {}) do
            P(("next costs %s of currency %s (you have %s)."):format(tostring(cost.amount), tostring(cost.ID),
                tostring(money[cost.ID])))
        end
        P("next, in words: " .. WhyText(Diagnose(configID, item, money)))
    end
    P("last refusal: " .. tostring(lastRefusal))
end

SLASH_EUITP1 = "/euitp"
SlashCmdList["EUITP"] = Report

-------------------------------------------------------------------------------
--  The marks on the talent tree
-------------------------------------------------------------------------------
local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

local function NumbersText(list, full)
    if not list or #list == 0 then return nil end
    if full or #list <= 3 then return table.concat(list, ", ") end
    return list[1] .. "-" .. list[#list]
end

local Refresh

-- The planned items of a node, in plan order.
local function NodeItems(plan, nodeID)
    local out = {}
    for i, item in ipairs(plan) do
        if item.n == nodeID then out[#out + 1] = i end
    end
    return out
end

-- Why the node's next rank cannot be planned now, or nil.
local function PlanBlocked(nodeID)
    local _, configID, treeID = Context()
    local plan = configID and Plan()
    local info = plan and C_Traits.GetNodeInfo(configID, nodeID)
    if not info then return nil end
    local _, _, sim = Resolve(plan, configID, treeID)
    local at = NodeItems(plan, nodeID)
    local item = { n = nodeID, r = math.max(#at > 0 and plan[at[#at]].r or 0, info.ranksPurchased or 0) + 1 }
    if IsChoice(info) then item.e = info.entryIDs[1] end
    local ok, why = CanOpen(sim, item)
    if ok or why == "choice" then return nil end
    return why
end

local function MarkEnter(mark)
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetNodeInfo(configID, mark.nodeID)
    if not info then return end
    local plan = Plan() or {}
    local planned
    for _, item in ipairs(plan) do
        if item.n == mark.nodeID then planned = item end
    end
    GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
    if IsChoice(info) and not (planned or info.activeEntry) then
        local names = {}
        for i, entryID in ipairs(info.entryIDs) do names[i] = EntryName(configID, entryID) end
        GameTooltip:SetText(table.concat(names, " / "))
    else
        local spellID = EntrySpell(configID, ShownEntry(info, planned))
        if spellID then GameTooltip:SetSpellByID(spellID) end
    end
    local text = NumbersText(Numbers(plan, configID)[mark.nodeID], true)
    if text then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(EllesmereUI.Lf("Planned: %s", text), Accent())
    end
    local why = planMode and PlanBlocked(mark.nodeID)
    if why then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(EllesmereUI.Lf("Cannot be planned yet: %s", WhyText(why)), 1, 0.35, 0.35, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(EllesmereUI.L("Left-click: plan the next rank, or pick the choice. Right-click: take the last planned rank back."),
        0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function MarkLeave(mark)
    if GameTooltip:IsOwned(mark) then GameTooltip:Hide() end
end

-- Adds an item to the plan if the tree allows it; else says why, once.
local function TryPlan(plan, item, configID, treeID)
    Repair(plan, configID, treeID)
    local _, _, sim = Resolve(plan, configID, treeID)
    local ok, why = CanOpen(sim, item)
    if not ok then
        SayOnce("plan" .. item.n .. why, EllesmereUI.Lf("Talent Planner: %1$s cannot be planned yet: %2$s.",
            NodeLink(configID, item), WhyText(why)))
        return false
    end
    plan[#plan + 1] = item
    return true
end

local function PlanChoice(mark, info, configID, treeID)
    MenuUtil.CreateContextMenu(mark, function(_, root)
        for _, entryID in ipairs(info.entryIDs) do
            root:CreateButton(EntryName(configID, entryID), function()
                local plan = Plan(true)
                if not plan then return end
                local at = NodeItems(plan, mark.nodeID)[1]
                local entry = C_Traits.GetEntryInfo(configID, entryID)
                if not (entry and entry.isAvailable) then
                    SayOnce("choice" .. entryID, EllesmereUI.Lf("Talent Planner: %1$s cannot be planned yet: %2$s.",
                        EntryName(configID, entryID), WhyText("choice")))
                elseif at then
                    plan[at].e = entryID
                else
                    TryPlan(plan, { n = mark.nodeID, r = 1, e = entryID }, configID, treeID)
                end
                Refresh()
            end)
        end
    end)
end

local function MarkClick(mark, button)
    local _, configID, treeID = Context()
    local info = configID and C_Traits.GetNodeInfo(configID, mark.nodeID)
    local plan = info and Plan(true)
    if not plan then return end
    local at = NodeItems(plan, mark.nodeID)
    if button == "RightButton" then
        if #at == 0 then return end
        table.remove(plan, at[#at])
        local dropped = Repair(plan, configID, treeID)
        if dropped > 0 then
            Say(EllesmereUI.Lf("Talent Planner: %d planned talents depended on it and were removed too.", dropped))
        end
    else
        local rank = math.max(#at > 0 and plan[at[#at]].r or 0, info.ranksPurchased or 0) + 1
        if rank > (info.maxRanks or 1) then
            SayOnce("max" .. mark.nodeID, EllesmereUI.Lf("Talent Planner: %1$s cannot be planned yet: %2$s.",
                NodeLink(configID, { n = mark.nodeID }), WhyText("max")))
            return
        end
        if IsChoice(info) then
            PlanChoice(mark, info, configID, treeID)
            return
        end
        TryPlan(plan, { n = mark.nodeID, r = rank }, configID, treeID)
    end
    Refresh()
    MarkEnter(mark)
end

local function Mark(talentButton)
    local mark = marks[talentButton]
    if mark then return mark end
    mark = CreateFrame("Button", nil, talentButton)
    mark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mark:SetScript("OnClick", MarkClick)
    mark:SetScript("OnEnter", MarkEnter)
    mark:SetScript("OnLeave", MarkLeave)
    mark.hover = mark:CreateTexture(nil, "OVERLAY")
    mark.hover:SetAllPoints()
    mark.hover:SetColorTexture(1, 1, 1, 0.15)
    mark.hover:SetBlendMode("ADD")
    mark:SetHighlightTexture(mark.hover)
    mark.text = mark:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyModuleFont(mark.text, nil, 12, "extras", "OUTLINE")
    mark.text:SetPoint("BOTTOM", mark, "BOTTOM", 0, -6)
    marks[talentButton] = mark
    return mark
end

local function HideMarks()
    for _, mark in pairs(marks) do mark:Hide() end
end

-- Every talent button gets its mark: the numbers always, the clicks in plan
-- mode only.
function Refresh()
    local talents = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not (layer and talents and talents:IsVisible()) then return end
    local configID = C_ClassTalents.GetActiveConfigID()
    local inspecting = talents:IsInspecting()
    if inspecting and planMode then planMode = false end
    layer.plan:SetShown(not inspecting and configID ~= nil)
    layer.plan:SetText(planMode and EllesmereUI.L("Done") or EllesmereUI.L("Plan Talents"))
    layer.clear:SetShown(planMode)
    if inspecting or not configID then
        HideMarks()
        return
    end
    local numbers = Numbers(Plan() or {}, configID)
    local r, g, b = Accent()
    for talentButton in talents:EnumerateAllTalentButtons() do
        local nodeID = talentButton:GetNodeID()
        local info = nodeID and talentButton:GetNodeInfo()
        if not (info and (info.maxRanks or 0) > 0) then
            if marks[talentButton] then marks[talentButton]:Hide() end
        else
            local mark = Mark(talentButton)
            mark.nodeID = nodeID
            mark:SetAllPoints(talentButton)
            mark.text:SetTextColor(r, g, b)
            local text = NumbersText(numbers[nodeID])
            mark.text:SetText(text or "")
            mark:EnableMouse(planMode)
            mark:SetShown(planMode or text ~= nil)
        end
    end
end

-- Entering plan mode puts a plan from an earlier version in a valid order.
-- Done: learn now, and say why when nothing is learned.
local function SetPlanMode(on, done)
    planMode = on
    edgeCache = nil
    if on then
        local _, configID, treeID = Context()
        local plan = configID and Plan()
        local dropped = plan and Repair(plan, configID, treeID) or 0
        if dropped > 0 then
            Say(EllesmereUI.Lf("Talent Planner: %d planned talents could not be reached and were removed.", dropped))
        end
    elseif done then
        wantManual = true
    end
    Refresh()
    if not on then Soon() end
end

local function TextButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetText(text)
    return b
end

local function OnButtonsUpdated(_, treeID)
    local talents = PlayerSpellsFrame.TalentsFrame
    if treeID == talents:GetTalentTreeID() then Refresh() end
end

local function Build()
    local talents = PlayerSpellsFrame.TalentsFrame
    layer = CreateFrame("Frame", nil, talents)
    layer:SetAllPoints()
    layer:SetFrameLevel(talents:GetFrameLevel() + 5)
    -- Plan Talents and Clear Plan sit under the window, out of the tree's way.
    layer.plan = TextButton(layer, EllesmereUI.L("Plan Talents"))
    layer.plan:SetPoint("TOPRIGHT", PlayerSpellsFrame, "BOTTOMRIGHT", -8, -2)
    layer.plan:SetScript("OnClick", function() SetPlanMode(not planMode, planMode) end)
    layer.clear = TextButton(layer, EllesmereUI.L("Clear Plan"))
    layer.clear:SetPoint("RIGHT", layer.plan, "LEFT", -6, 0)
    layer.clear:SetScript("OnClick", function()
        EllesmereUI:ShowConfirmPopup({
            title = "Clear Plan",
            message = "Clear the talent plan of this specialization?",
            confirmText = "Clear",
            cancelText = "Cancel",
            onConfirm = function()
                local plan = Plan(true)
                if not plan then return end
                for i = #plan, 1, -1 do plan[i] = nil end
                Refresh()
            end,
        })
    end)
    layer:SetScript("OnShow", function(self)
        EventRegistry:RegisterCallback("TalentFrameBase.ButtonsUpdated", OnButtonsUpdated, self)
        Refresh()
    end)
    layer:SetScript("OnHide", function(self)
        EventRegistry:UnregisterCallback("TalentFrameBase.ButtonsUpdated", self)
        HideMarks()
        if planMode then SetPlanMode(false) end
    end)
end

local function Hook()
    if not layer then Build() end
    layer:SetShown(F.Enabled())
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
-- Off: no events, no marks. The talent window loads on demand, so the marks
-- may wait for it.
local function Apply()
    if not F.Enabled() then
        if events then events:UnregisterAllEvents() end
        if waiter then waiter:UnregisterAllEvents() end
        awaiting, waitData, waiting, committing, planMode, edgeCache = nil, nil, nil, nil, nil, nil
        if layer then layer:Hide() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if layer then
        layer:Show()
    elseif C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        Hook()
    else
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:SetScript("OnEvent", function(self, _, name)
                if name ~= "Blizzard_PlayerSpells" then return end
                self:UnregisterAllEvents()
                Hook()
            end)
        end
        waiter:RegisterEvent("ADDON_LOADED")
    end
end

-- Options-page entry points.
EllesmereUI._TalentPlannerRetail = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
