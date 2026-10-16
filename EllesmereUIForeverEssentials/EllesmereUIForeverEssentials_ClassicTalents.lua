if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ClassicTalents.lua  (WoW Forever only)
--  The vanilla talent window, drawn with the client's own art: one tree a
--  tab, talents on a grid with their ranks and prerequisite arrows. Points
--  are staged with a click and spent with Learn, as the game's own window
--  does. The talents key opens it in place of the Talents & Spellbook window,
--  which the micro menu still opens. Active spec only.
-------------------------------------------------------------------------------
local _, module = ...

local SIZE = 32           -- talent button
local STEP = 63           -- between talents on the grid
local LEFT, TOP = 35, 20  -- first talent, inside the tree area
local VIEW_W, VIEW_H = 296, 332
local BESIDE = 392        -- clears the spellbook and the tabs on its right side
local ART = "Interface\\TalentFrame\\"
local QUEUE_KEY = "ClassicTalentsBind"
local TOGGLE_NAME = "EUI_ClassicTalentsToggle"

-- Tree backgrounds by class, in tree order.
local BACKGROUNDS = {
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
}

-- Pieces of the branch and arrow sheets: left, right, top of the lit row. The
-- unlit row sits half a sheet lower.
local BRANCH_DOWN = { 0, 0.125, 0 }
local BRANCH_RIGHT = { 0.2578125, 0.3828125, 0 }
local ARROW_TOP = { 0, 0.5, 0 }
local ARROW_RIGHT = { 1, 0.5, 0 }
local ARROW_LEFT = { 0.5, 1, 0 }

-- Settings live in EllesmereUIDB.classicTalents; unset keys read these.
local F = module.Feature("classicTalents", { enabled = false })

local win, toggle
local trees = {}  -- { groupID, name, nodes = { nodeID, ... } } in tree order
local tree = 1    -- the selected tree
local staged = {} -- [nodeID] = points staged here and not yet learned
local configID, treeID
local unspent = 0 -- talent points left to stage
local boundKeys   -- the keys the toggle holds, space separated
local queued      -- a repaint is due next frame

-------------------------------------------------------------------------------
--  Talent data
-------------------------------------------------------------------------------
local function ByOrder(a, b) return a.orderIndex < b.orderIndex end

-- The trees whose own name is too long for a tab, by trait group ID.
local function ShortName(groupID)
    if groupID == 11326 then return EllesmereUI.L("Elemental") end -- Elemental Combat
    if groupID == 11347 then return EllesmereUI.L("Feral") end     -- Feral Combat
    if groupID == 11622 then return EllesmereUI.L("Shadow") end    -- Shadow Magic
end

local function ReadTrees()
    wipe(trees)
    configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    treeID = config and config.treeIDs[1]
    if not treeID then return end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    table.sort(groups, ByOrder)
    local byGroup = {}
    for i, g in ipairs(groups) do
        trees[i] = { groupID = g.groupID, name = ShortName(g.groupID) or g.displayName, nodes = {} }
        byGroup[g.groupID] = trees[i]
    end
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.isVisible and info.entryIDs[1] then
            for _, groupID in ipairs(info.groupIDs) do
                local t = byGroup[groupID]
                if t then
                    t.nodes[#t.nodes + 1] = nodeID
                    break
                end
            end
        end
    end
    if tree > #trees then tree = 1 end
end

-- The smallest gap between two different values: one grid step.
local function GridStep(values)
    table.sort(values)
    local step
    for i = 2, #values do
        local d = values[i] - values[i - 1]
        if d > 0 and (not step or d < step) then step = d end
    end
    return values[1] or 0, step or 1
end

-- Each talent's column and row (from 0) in its tree, from the node positions.
local function Grid(nodes)
    local xs, ys, infos = {}, {}, {}
    for i, nodeID in ipairs(nodes) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        infos[nodeID] = info
        xs[i], ys[i] = info.posX, info.posY
    end
    local x0, dx = GridStep(xs)
    local y0, dy = GridStep(ys)
    local cells, rows = {}, 0
    for _, nodeID in ipairs(nodes) do
        local info = infos[nodeID]
        local col = math.floor((info.posX - x0) / dx + 0.5)
        local row = math.floor((info.posY - y0) / dy + 0.5)
        cells[nodeID] = { col = col, row = row, info = info }
        rows = math.max(rows, row)
    end
    return cells, rows + 1
end

local function SpellOf(info)
    local entryID = info.activeEntry and info.activeEntry.entryID or info.entryIDs[1]
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    if not def then return end
    local icon = def.overrideIcon
    if not icon or icon == 0 then icon = def.spellID and C_Spell.GetSpellTexture(def.spellID) end
    return def.spellID, icon
end

-------------------------------------------------------------------------------
--  Talent buttons
-------------------------------------------------------------------------------
local Paint, QueuePaint

local function TalentEnter(b)
    if not b.spellID then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(b.spellID)
    GameTooltip:Show()
end

local function TalentLeave()
    GameTooltip:Hide()
end

-- Left click stages a point; right click takes back one staged here.
local function TalentClick(b, button)
    local nodeID = b.nodeID
    if not nodeID then return end
    if button == "RightButton" then
        if (staged[nodeID] or 0) > 0 and C_Traits.RefundRank(configID, nodeID) then
            staged[nodeID] = staged[nodeID] - 1
        end
    elseif C_Traits.PurchaseRank(configID, nodeID) then
        staged[nodeID] = (staged[nodeID] or 0) + 1
    end
    QueuePaint()
end

local function NewTalent(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's own frame
    b.slot = b:CreateTexture(nil, "BACKGROUND")
    b.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot-White")
    b.slot:SetSize(64, 64)
    b.slot:SetPoint("CENTER")
    b.rankBorder = b:CreateTexture(nil, "OVERLAY")
    b.rankBorder:SetTexture(ART .. "TalentFrame-RankBorder")
    b.rankBorder:SetSize(32, 32)
    b.rankBorder:SetPoint("CENTER", b, "BOTTOMRIGHT")
    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.rank:SetPoint("CENTER", b.rankBorder)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", TalentEnter)
    b:SetScript("OnLeave", TalentLeave)
    b:SetScript("OnClick", TalentClick)
    return b
end

-- Gold when full, green while it holds points or can take the first one, else
-- grey with no rank.
local function FillTalent(b, nodeID, cell)
    local info = cell.info
    local spellID, icon = SpellOf(info)
    b.nodeID, b.spellID = nodeID, spellID
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", LEFT + cell.col * STEP, -(TOP + cell.row * STEP))
    b.icon:SetTexture(icon)
    local rank = info.activeRank
    local open = rank > 0 or (unspent > 0 and info.canPurchaseRank)
    b.icon:SetDesaturated(not open)
    if rank >= info.maxRanks then
        b.slot:SetVertexColor(1, 0.82, 0)
        b.rank:SetTextColor(1, 0.82, 0)
    elseif open then
        b.slot:SetVertexColor(0.1, 1, 0.1)
        b.rank:SetTextColor(0.1, 1, 0.1)
    else
        b.slot:SetVertexColor(0.5, 0.5, 0.5)
    end
    b.rank:SetText(rank)
    b.rank:SetShown(open)
    b.rankBorder:SetShown(open)
    b:Show()
end

-- One piece of a sheet: its lit row, or the unlit one half a sheet lower.
local function Piece(pool, n, parent, sheet, coords, lit)
    local tex = pool[n]
    if not tex then
        tex = parent:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(ART .. sheet)
        pool[n] = tex
    end
    local top = coords[3] + (lit and 0 or 0.5)
    tex:SetTexCoord(coords[1], coords[2], top, top + 0.5)
    tex:ClearAllPoints()
    tex:Show()
    return tex
end

-- A line and an arrow from a talent to the one it unlocks, when the two share
-- a column or a row.
local function Link(n, from, to, lit)
    local x, y = LEFT + from.col * STEP, -(TOP + from.row * STEP)
    if from.col == to.col and to.row > from.row then
        local line = Piece(win.lines, n, win.canvas, "UI-TalentBranches", BRANCH_DOWN, lit)
        line:SetSize(SIZE, (to.row - from.row) * STEP - SIZE)
        line:SetPoint("TOPLEFT", x, y - SIZE)
        local arrow = Piece(win.arrows, n, win.above, "UI-TalentArrows", ARROW_TOP, lit)
        arrow:SetSize(SIZE, SIZE)
        arrow:SetPoint("TOPLEFT", x, y - (to.row - from.row) * STEP + SIZE / 2)
    elseif from.row == to.row and to.col ~= from.col then
        local right = to.col > from.col
        local span = math.abs(to.col - from.col) * STEP - SIZE
        local line = Piece(win.lines, n, win.canvas, "UI-TalentBranches", BRANCH_RIGHT, lit)
        line:SetSize(span, SIZE)
        line:SetPoint("TOPLEFT", right and x + SIZE or x - span, y)
        local arrow = Piece(win.arrows, n, win.above, "UI-TalentArrows", right and ARROW_RIGHT or ARROW_LEFT, lit)
        arrow:SetSize(SIZE, SIZE)
        arrow:SetPoint("TOPLEFT", right and x + span + SIZE / 2 or x - span - SIZE / 2, y)
    else
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function HasStaged()
    return next(staged) ~= nil
end

local function PaintBackground()
    local _, class = UnitClass("player")
    local name = BACKGROUNDS[class] and BACKGROUNDS[class][tree]
    for corner, tex in pairs(win.bg) do
        tex:SetTexture(name and ART .. name .. "-" .. corner or nil)
    end
end

Paint = function()
    local t = trees[tree]
    local currency = treeID and C_Traits.GetTreeCurrencyInfo(configID, treeID, false)[1]
    unspent = currency and currency.quantity or 0
    local cells, rows = Grid(t and t.nodes or {})
    local used = 0
    for nodeID, cell in pairs(cells) do
        used = used + 1
        local b = win.talents[used]
        if not b then
            b = NewTalent(win.canvas)
            win.talents[used] = b
        end
        FillTalent(b, nodeID, cell)
    end
    for i = used + 1, #win.talents do win.talents[i]:Hide() end

    local links = 0
    for _, cell in pairs(cells) do
        for _, edge in ipairs(cell.info.visibleEdges) do
            local to = cells[edge.targetNode]
            if to and Link(links + 1, cell, to, edge.isActive) then links = links + 1 end
        end
    end
    for i = links + 1, #win.lines do win.lines[i]:Hide() end
    for i = links + 1, #win.arrows do win.arrows[i]:Hide() end
    win.canvas:SetSize(VIEW_W, math.max(VIEW_H, TOP * 2 + (rows - 1) * STEP + SIZE))

    for i, tab in ipairs(win.tabs) do
        local data = trees[i]
        tab:SetShown(data ~= nil)
        if data then
            tab.text:SetText(data.name)
            local on = i == tree
            for _, tex in ipairs(tab.active) do tex:SetShown(on) end
            for _, tex in ipairs(tab.inactive) do tex:SetShown(not on) end
            local c = on and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
            tab.text:SetTextColor(c.r, c.g, c.b)
            tab.text:SetPoint("CENTER", 0, on and 4 or 2)
        end
    end
    local group = t and C_Traits.GetGroupCurrencyInfo(configID, { t.groupID })[1]
    local spent = group and group.currencyInfos[1] and group.currencyInfos[1].spent or 0
    -- The numbers are white beside their gold labels.
    local white = HIGHLIGHT_FONT_COLOR
    win.spent:SetText(t and EllesmereUI.Lf("Points spent in %1$s Talents: %2$s", t.name,
        white:WrapTextInColorCode(spent)) or "")
    win.points:SetText(EllesmereUI.Lf("Talent Points: %s", white:WrapTextInColorCode(unspent)))
    win.learn:SetEnabled(HasStaged())
    PaintBackground()
end

local function Refresh()
    ReadTrees()
    Paint()
end

-- One repaint for a click and the burst of events it sets off.
local function Repaint()
    queued = nil
    if win:IsShown() then Refresh() end
end

QueuePaint = function()
    if queued then return end
    queued = true
    C_Timer.After(0, Repaint)
end

local function Rollback()
    if HasStaged() and configID then C_Traits.RollbackConfig(configID) end
    wipe(staged)
end

local function Learn()
    if not HasStaged() then return end
    wipe(staged)
    C_ClassTalents.CommitConfig(configID)
end

local EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
                 "ACTIVE_COMBAT_CONFIG_CHANGED" }

-- Listens only while open. Closing drops the points staged here.
local function WinShown(f)
    for _, event in ipairs(EVENTS) do f:RegisterEvent(event) end
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Refresh()
end

local function WinHidden(f)
    f:UnregisterAllEvents()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    Rollback()
end

-- A tab's art in three pieces (20 px ends, a stretched middle). The selected
-- tab's art is 3 px taller and starts 5 px higher, so it joins the window.
local TAB_ENDS = 0.15625
local function TabArt(tab, file, height, rise, bottom)
    local left = tab:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    left:SetTexCoord(0, TAB_ENDS, 0, bottom)
    left:SetSize(20, height)
    left:SetPoint("TOPLEFT", 0, rise)
    local right = tab:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    right:SetTexCoord(1 - TAB_ENDS, 1, 0, bottom)
    right:SetSize(20, height)
    right:SetPoint("TOPRIGHT", 0, rise)
    local middle = tab:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    middle:SetTexCoord(TAB_ENDS, 1 - TAB_ENDS, 0, bottom)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return { left, middle, right }
end

local function NewTab(i)
    local tab = CreateFrame("Button", nil, win)
    tab:SetSize(108, 32)
    tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12 + (i - 1) * 104, 78)
    tab.inactive = TabArt(tab, "UI-Character-InActiveTab", 32, 0, 1)
    tab.active = TabArt(tab, "UI-Character-ActiveTab", 35, 5, 0.546875)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", 0, 2)
    tab.text:SetWidth(92)
    tab.text:SetWordWrap(false)
    tab:SetScript("OnClick", function()
        if i == tree then return end
        tree = i
        win.scroll:SetVerticalScroll(0)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        Paint()
    end)
    return tab
end

local function Build()
    if win then return end
    win = CreateFrame("Frame", "EUI_ClassicTalents", UIParent)
    win:Hide()
    win:SetSize(384, 512)
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetHitRectInsets(0, 30, 0, 70)

    local portrait = win:CreateTexture(nil, "BACKGROUND")
    portrait:SetSize(60, 60)
    portrait:SetPoint("TOPLEFT", 7, -6)
    win.portrait = portrait
    for _, part in ipairs({
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft", "TOPLEFT", 256 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight", "TOPRIGHT", 128 },
        { ART .. "UI-TalentFrame-BotLeft", "BOTTOMLEFT", 256 },
        { ART .. "UI-TalentFrame-BotRight", "BOTTOMRIGHT", 128 },
    }) do
        local tex = win:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(part[1])
        tex:SetSize(part[3], 256)
        tex:SetPoint(part[2])
    end
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", 6, 230)
    title:SetText(TALENTS)

    -- The tree's background, over the frame art and behind the scrolling
    -- talents: 320 x 331 in four pieces.
    win.bg = {}
    for _, part in ipairs({ { "TopLeft", 0, 0, 256, 256 }, { "TopRight", 256, 0, 64, 256 },
                            { "BottomLeft", 0, -256, 256, 75 }, { "BottomRight", 256, -256, 64, 75 } }) do
        local tex = win:CreateTexture(nil, "ARTWORK", nil, 1)
        tex:SetSize(part[4], part[5])
        tex:SetPoint("TOPLEFT", 23 + part[2], -77 + part[3])
        if part[5] < 256 then tex:SetTexCoord(0, 1, 0, part[5] / 128) end
        win.bg[part[1]] = tex
    end

    win.scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    win.scroll:SetSize(VIEW_W, VIEW_H)
    win.scroll:SetPoint("TOPRIGHT", -65, -77)
    win.canvas = CreateFrame("Frame", nil, win.scroll)
    win.canvas:SetSize(VIEW_W, VIEW_H)
    win.scroll:SetScrollChild(win.canvas)
    -- Arrowheads lie over the talent they point at.
    win.above = CreateFrame("Frame", nil, win.canvas)
    win.above:SetAllPoints()
    win.above:SetFrameLevel(win.canvas:GetFrameLevel() + 5)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("CENTER", win, "TOPRIGHT", -44, -25)

    -- The bordered bar the points-spent line sits in: the input box border,
    -- two 8 px ends and a stretched middle.
    local bar = {}
    for i, part in ipairs({ { 0, 0.0625 }, { 0.0625, 0.9375 }, { 0.9375, 1 } }) do
        bar[i] = win:CreateTexture(nil, "ARTWORK", nil, 2)
        bar[i]:SetTexture("Interface\\Common\\Common-Input-Border")
        bar[i]:SetTexCoord(part[1], part[2], 0, 0.625)
    end
    bar[1]:SetSize(8, 20)
    bar[1]:SetPoint("TOPLEFT", win, "TOP", -117, -48)
    bar[3]:SetSize(8, 20)
    bar[3]:SetPoint("TOPRIGHT", win, "TOP", 129, -48)
    bar[2]:SetPoint("TOPLEFT", bar[1], "TOPRIGHT")
    bar[2]:SetPoint("BOTTOMRIGHT", bar[3], "BOTTOMLEFT")
    win.spent = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.spent:SetPoint("CENTER", bar[2])
    win.points = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.learn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.learn:SetSize(86, 20)
    win.learn:SetPoint("BOTTOMRIGHT", -40, 81)
    win.learn:SetText(LEARN)
    win.learn:SetScript("OnClick", Learn)
    win.points:SetPoint("RIGHT", win.learn, "LEFT", -10, 0)

    win.tabs, win.talents, win.lines, win.arrows = {}, {}, {}, {}
    for i = 1, 3 do win.tabs[i] = NewTab(i) end

    win:SetScript("OnShow", WinShown)
    win:SetScript("OnHide", WinHidden)
    win:SetScript("OnEvent", function(_, event)
        -- A learn or a change made elsewhere: what was staged here is gone.
        if event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then wipe(staged) end
        QueuePaint()
    end)
    if EllesmereUI.RegisterEscapeClose then EllesmereUI.RegisterEscapeClose(win, { cursor = true }) end
end

-- At the left of the screen, or beside the Classic Spellbook while that is open.
local function Place()
    if not win then return end
    local book = EUI_ClassicSpellbook
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", book and book:IsShown() and BESIDE or 0, -104)
end

local function Close()
    if win then win:Hide() end
end

local function Toggle()
    Build()
    if win:IsShown() then
        win:Hide()
    else
        SetPortraitTexture(win.portrait, "player")
        Place()
        win:Show()
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
-- The talents key clicks the toggle while the feature is on. Setting an
-- override fires UPDATE_BINDINGS itself, so unchanged keys are left alone.
local function Bind()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer(QUEUE_KEY, Bind)
        return
    end
    if not toggle then
        if not F.Enabled() then return end
        toggle = CreateFrame("Button", TOGGLE_NAME, UIParent)
        toggle:SetScript("OnClick", Toggle)
        toggle:SetScript("OnEvent", Bind)
    end
    local on = F.Enabled()
    if on then
        toggle:RegisterEvent("UPDATE_BINDINGS")
    else
        toggle:UnregisterAllEvents()
        if win then win:Hide() end
    end
    local keys = on and table.concat({ GetBindingKey("TOGGLETALENTS") }, " ") or ""
    if keys == boundKeys then return end
    boundKeys = keys
    ClearOverrideBindings(toggle)
    for key in keys:gmatch("%S+") do
        SetOverrideBindingClick(toggle, true, key, TOGGLE_NAME)
    end
end

-- Options-page entry points.
EllesmereUI._ClassicTalents = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Bind,
    Place = Place,
    Close = Close,
}

F.Start(Bind)
