if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TalentPlanner.lua  (WoW Forever only)
--  Talent Planner: plan the talents to come, point by point, on the game's
--  talent tree; each level up then learns the next planned points.
--
--  Plan Talents (under the talent page) turns plan mode on: a click on a
--  talent plans its next rank, a right-click takes its last planned rank
--  back, and each talent shows the levels its planned ranks come at. The
--  plan is kept per character and per talent group (dual spec), in order;
--  the n-th planned point is the n-th talent point (level 9 + n).
--
--  The marks are frames of our own over the game's talent buttons (read
--  through EnumerateAllTalentButtons, never written); they take clicks only
--  in plan mode. Learning goes through C_Traits.PurchaseRank and one
--  C_Traits.CommitConfig, out of combat, at level up, at login and when plan
--  mode closes, only while there are unspent points. A planned talent the
--  game will not take stops the run with a chat line rather than a guess.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.talentPlanner; unset keys read these.
-- chars: player GUID = { [talent group] = { nodeID, ... } }, the plan in order
local F = module.Feature("talentPlanner", { enabled = false })

local FIRST_LEVEL = 10   -- the level of the first talent point
local LEVEL_UP_SETTLE = 1 -- seconds for the new point to reach the tree

local events, waiter, hooked, layer, planMode, refreshing
local marks = {}          -- talent button -> our mark (weak: buttons are pooled)
setmetatable(marks, { __mode = "k" })
local queue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

local function Brand(msg)
    local CC = EllesmereUI.COLOR_CODES
    EllesmereUI.Print(CC.BRAND .. "EllesmereUI:|r " .. msg)
end

-------------------------------------------------------------------------------
--  The plan
-------------------------------------------------------------------------------
local function Group()
    return C_SpecializationInfo.GetActiveSpecGroup() or 1
end

local function ConfigID()
    return C_SpecializationInfo.GetCombatConfigIDForSpecGroup(Group())
end

-- The plan of this character's active talent group; create: make it.
local function Plan(create)
    local guid = UnitGUID("player")
    if not guid then return nil end
    local cfg = create and F.Cfg() or F.Read()
    if create then
        cfg.chars = cfg.chars or {}
        cfg.chars[guid] = cfg.chars[guid] or {}
        cfg.chars[guid][Group()] = cfg.chars[guid][Group()] or {}
    end
    local mine = cfg.chars and cfg.chars[guid]
    return mine and mine[Group()]
end

local function Unspent(configID)
    local info = C_Traits.GetConfigInfo(configID)
    local treeID = info and info.treeIDs and info.treeIDs[1]
    if not treeID then return 0 end
    local n = 0
    for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {}) do
        n = n + (c.quantity or 0)
    end
    return n
end

-- The planned points not learned yet, in order: the k-th time a node comes
-- in the plan is its rank k.
local function Pending(plan, configID)
    local out, seen = {}, {}
    for i, nodeID in ipairs(plan) do
        seen[nodeID] = (seen[nodeID] or 0) + 1
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and (info.ranksPurchased or 0) < seen[nodeID] then
            out[#out + 1] = { index = i, nodeID = nodeID, rank = seen[nodeID] }
        end
    end
    return out
end

local function NodeSpell(configID, nodeID)
    local info = C_Traits.GetNodeInfo(configID, nodeID)
    local entryID = info and (info.activeEntry and info.activeEntry.entryID or info.entryIDs and info.entryIDs[1])
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    return def and def.spellID
end

local function NodeLink(configID, nodeID)
    local spellID = NodeSpell(configID, nodeID)
    return spellID and C_Spell.GetSpellLink(spellID) or ("#" .. nodeID)
end

-------------------------------------------------------------------------------
--  Learning
-------------------------------------------------------------------------------
-- The next planned points, as many as there are unspent points, in one
-- commit. Waits out combat.
local function Learn()
    if not F.Enabled() then return end
    if InCombatLockdown() then
        queue.Defer("TalentPlanner", Learn)
        return
    end
    local plan = Plan()
    local configID = ConfigID()
    if not (plan and #plan > 0 and configID) then return end
    local points = Unspent(configID)
    if points <= 0 or not C_Traits.CanEditConfig(configID) or not C_Traits.IsReadyForCommit() then return end
    local learned = {}
    for _, step in ipairs(Pending(plan, configID)) do
        if points <= 0 then break end
        local info = C_Traits.GetNodeInfo(configID, step.nodeID)
        if not (info and info.canPurchaseRank and C_Traits.PurchaseRank(configID, step.nodeID)) then
            Brand(EllesmereUI.Lf("Talent Planner: %1$s (planned for level %2$d) cannot be learned yet; check your plan.",
                NodeLink(configID, step.nodeID), FIRST_LEVEL - 1 + step.index))
            break
        end
        points = points - 1
        learned[#learned + 1] = NodeLink(configID, step.nodeID)
    end
    if #learned == 0 then return end
    if C_Traits.CommitConfig(configID) then
        Brand(EllesmereUI.Lf("Talents learned: %s", table.concat(learned, " ")))
    else
        C_Traits.RollbackConfig(configID)
    end
end

-------------------------------------------------------------------------------
--  The marks on the talent tree
-------------------------------------------------------------------------------
local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

-- The levels a node's planned ranks come at: "10", "10, 11" or "10-14".
local function LevelsText(plan, nodeID)
    local levels = {}
    for i, id in ipairs(plan) do
        if id == nodeID then levels[#levels + 1] = FIRST_LEVEL - 1 + i end
    end
    if #levels == 0 then return nil end
    if #levels <= 2 then return table.concat(levels, ", ") end
    return levels[1] .. "-" .. levels[#levels]
end

local Refresh

local function MarkEnter(mark)
    local configID = ConfigID()
    local spellID = configID and NodeSpell(configID, mark.nodeID)
    GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
    if spellID then GameTooltip:SetSpellByID(spellID) end
    local plan = Plan()
    local levels = plan and LevelsText(plan, mark.nodeID)
    if levels then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(EllesmereUI.Lf("Planned for level %s", levels), Accent())
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(EllesmereUI.L("Left-click: plan its next rank. Right-click: take its last planned rank back."),
        0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function MarkLeave(mark)
    if GameTooltip:IsOwned(mark) then GameTooltip:Hide() end
end

local function MarkClick(mark, button)
    local configID = ConfigID()
    local info = configID and C_Traits.GetNodeInfo(configID, mark.nodeID)
    if not info then return end
    local plan = Plan(true)
    if not plan then return end
    local count = 0
    for _, id in ipairs(plan) do
        if id == mark.nodeID then count = count + 1 end
    end
    if button == "RightButton" then
        for i = #plan, 1, -1 do
            if plan[i] == mark.nodeID then
                table.remove(plan, i)
                break
            end
        end
    elseif count < (info.maxRanks or 1) then
        local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
        if #plan < maxLevel - FIRST_LEVEL + 1 then plan[#plan + 1] = mark.nodeID end
    end
    Refresh()
    MarkEnter(mark)
end

local function Mark(talentButton)
    local mark = marks[talentButton]
    if mark then return mark end
    mark = CreateFrame("Button", nil, layer)
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
    EllesmereUI.ApplyModuleFont(mark.text, nil, 12, "essentials")
    mark.text:SetShadowOffset(1, -1)
    mark.text:SetPoint("BOTTOM", mark, "BOTTOM", 0, -6)
    marks[talentButton] = mark
    return mark
end

-- Every talent button gets its mark: the planned levels always, the clicks in
-- plan mode only.
function Refresh()
    refreshing = false
    local talents = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not (layer and talents and talents:IsVisible()) then return end
    local plan = Plan() or {}
    local r, g, b = Accent()
    for _, mark in pairs(marks) do mark:Hide() end
    for talentButton in talents:EnumerateAllTalentButtons() do
        local nodeID = talentButton.GetNodeID and talentButton:GetNodeID()
        if nodeID and talentButton:IsShown() then
            local mark = Mark(talentButton)
            mark.nodeID = nodeID
            mark:ClearAllPoints()
            mark:SetAllPoints(talentButton)
            mark:SetFrameLevel(talentButton:GetFrameLevel() + 20)
            mark.text:SetTextColor(r, g, b)
            mark.text:SetText(LevelsText(plan, nodeID) or "")
            mark:EnableMouse(planMode)
            mark:SetShown(planMode or mark.text:GetText() ~= "")
        end
    end
    layer.plan:SetText(planMode and EllesmereUI.L("Done") or EllesmereUI.L("Plan Talents"))
    layer.clear:SetShown(planMode)
end

-- Tree changes come in bursts: one refresh on the next frame.
local function SoonRefresh()
    if refreshing then return end
    refreshing = true
    C_Timer.After(0, Refresh)
end

-- An empty plan starts from the talents already learned (top rows first),
-- so the planned points that follow fall on the right levels.
local function Seed()
    local plan = Plan(true)
    if not plan then return end
    local configID = ConfigID()
    if #plan > 0 or not configID then return end
    local taken = {}
    for talentButton in PlayerSpellsFrame.TalentsFrame:EnumerateAllTalentButtons() do
        local info = talentButton.GetNodeID and C_Traits.GetNodeInfo(configID, talentButton:GetNodeID())
        if info and (info.ranksPurchased or 0) > 0 then taken[#taken + 1] = info end
    end
    table.sort(taken, function(a, b)
        if a.posY ~= b.posY then return a.posY < b.posY end
        return a.posX < b.posX
    end)
    for _, info in ipairs(taken) do
        for _ = 1, info.ranksPurchased do plan[#plan + 1] = info.ID end
    end
end

local function SetPlanMode(on)
    planMode = on
    if on then Seed() end
    Refresh()
    if not on then Learn() end
end

local function TextButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetText(text)
    return b
end

local function Build()
    local talents = PlayerSpellsFrame.TalentsFrame
    layer = CreateFrame("Frame", nil, talents)
    layer:SetAllPoints()
    layer:SetFrameLevel(talents:GetFrameLevel() + 5)
    -- Plan Talents and Clear Plan sit under the window, out of the tree's way.
    layer.plan = TextButton(layer, EllesmereUI.L("Plan Talents"))
    layer.plan:SetPoint("TOPRIGHT", PlayerSpellsFrame, "BOTTOMRIGHT", -8, -2)
    layer.plan:SetScript("OnClick", function() SetPlanMode(not planMode) end)
    layer.clear = TextButton(layer, EllesmereUI.L("Clear Plan"))
    layer.clear:SetPoint("RIGHT", layer.plan, "LEFT", -6, 0)
    layer.clear:SetScript("OnClick", function()
        local plan = Plan(true)
        for i = #plan, 1, -1 do plan[i] = nil end
        Refresh()
    end)
    layer:SetScript("OnShow", function(self)
        self:RegisterEvent("TRAIT_CONFIG_UPDATED")
        self:RegisterEvent("TRAIT_TREE_CHANGED")
        self:RegisterEvent("TRAIT_NODE_CHANGED")
        self:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
        SoonRefresh()
    end)
    layer:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        if planMode then SetPlanMode(false) end
    end)
    layer:SetScript("OnEvent", SoonRefresh)
end

local function Hook()
    hooked = true
    if not layer then Build() end
    layer:SetShown(F.Enabled())
    if layer:IsVisible() then SoonRefresh() end
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
local function OnEvent(_, event)
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(LEVEL_UP_SETTLE, Learn)
    else
        Learn()
    end
end

-- Off: no events, no marks. The talent page loads on demand, so the marks
-- may wait for it.
local function Apply()
    if not F.Enabled() then
        if events then events:UnregisterAllEvents() end
        if waiter then waiter:UnregisterAllEvents() end
        planMode = false
        if layer then layer:Hide() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if hooked then
        layer:Show()
        return
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then Hook() return end
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

-- Options-page entry points.
EllesmereUI._TalentPlanner = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
