if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME = "EllesmereUILootTracker"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end

local L = EllesmereUI.L
local PAGE_OVERVIEW = "Overview"
local PAGE_PLANNER = "Gear Planner"
local PAGE_DUNGEONS = "Dungeons"
local PAGE_RAIDS = "Raids"
local PAGE_SETTINGS = "Settings"
local ROW_H, ROW_GAP = 46, 3
local pageRebuildQueued
local catalogRetries = {}

StaticPopupDialogs.EULT_SIMC_EXPORT = {
    text = "SimulationCraft gear block — Ctrl+C",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 420,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local editBox = self.EditBox or self.editBox
        if not editBox then return end
        editBox:SetText(data or "")
        editBox:SetFocus()
        editBox:HighlightText()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function QueuePageRebuild()
    if pageRebuildQueued then return end
    pageRebuildQueued = true
    C_Timer.After(0, function()
        pageRebuildQueued = nil
        local activeModule = EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        if activeModule == ADDON_NAME then EllesmereUI:RefreshPage(true) end
    end)
end

local function QueueCatalogRetry(key)
    local state = catalogRetries[key]
    if not state then
        state = { attempts = 0 }
        catalogRetries[key] = state
    end
    if state.pending or state.attempts >= 5 then return end
    state.pending = true
    state.attempts = state.attempts + 1
    C_Timer.After(0.25, function()
        state.pending = nil
        ns.InvalidateCatalog()
        QueuePageRebuild()
    end)
end

local function Profile()
    return ns.GetProfile()
end

local function SelectedSpecID()
    local value = tonumber(Profile().selectedSpecID)
    if value and value > 0 then return value end
    return ns.ResolveSpecID()
end

local function BuildSpecValues()
    local values, order = {}, {}
    for index = 1, GetNumSpecializations() do
        local specID, name = GetSpecializationInfo(index)
        if specID then values[specID], order[#order + 1] = name, specID end
    end
    return values, order
end

local function BuildSourceValues(kind)
    local values, order = {}, {}
    for _, source in ipairs(ns.GetSources(kind)) do
        local id = kind == "raid" and source.encounterID or source.challengeModeID
        values[id], order[#order + 1] = source.name, id
    end
    return values, order
end

local function FindSource(kind, id)
    id = tonumber(id) or id
    for _, source in ipairs(ns.GetSources(kind)) do
        local sourceID = kind == "raid" and source.encounterID or source.challengeModeID
        if sourceID == id then return source end
    end
    return ns.GetSources(kind)[1]
end

local function Font(parent, size, r, g, b, a)
    return EllesmereUI.MakeFont(parent, size, nil, r or 1, g or 1, b or 1, a or 1)
end

local function Card(parent, y, height, isButton)
    local frame = CreateFrame(isButton and "Button" or "Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, y)
    frame:SetHeight(height)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.035, 0.04, 0.055, 0.82)
    EllesmereUI.MakeBorder(frame, 1, 1, 1, 0.08, EllesmereUI.PP)
    return frame
end

local function StyledButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 110, 28)
    button:SetFrameLevel(parent:GetFrameLevel() + 3)
    EllesmereUI.MakeStyledButton(button, text, 11, EllesmereUI.RB_COLOURS, onClick)
    return button
end

local function ReplaceTooltipItemLevel(tooltip, item, targetLevel)
    if not targetLevel or not item.itemLevel or targetLevel == item.itemLevel or not ITEM_LEVEL then return false end
    local pattern = ITEM_LEVEL:gsub("%%d", "(%%d+)")
    local tooltipName = tooltip:GetName()
    if not tooltipName then return false end
    for index = 2, tooltip:NumLines() do
        local line = _G[tooltipName .. "TextLeft" .. index]
        local text = line and line:GetText()
        if text and tonumber(text:match(pattern)) == tonumber(item.itemLevel) then
            line:SetText(EllesmereUI.Lf("Target item level: %d", targetLevel))
            line:SetTextColor(0.05, 0.82, 0.62)
            return true
        end
    end
    return false
end

local function ValidTooltipItemLink(link)
    return type(link) == "string"
        and (link:find("|Hitem:", 1, true) ~= nil or link:match("^item:%d+") ~= nil)
end

local function ShowItemTooltip(frame, item, targetLevel, showActions, targetLink, craftedPreview)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    -- Crafted entries intentionally do not use a synthetic upgrade link: such
    -- links make their base recipe item level look like the finished item
    -- level. Older learned/manual entries may, however, have no cached link at
    -- all, and planner selections persist it as itemLink rather than link.
    -- A minimal item hyperlink is understood by GameTooltip and is more
    -- reliable here than SetItemByID across client versions.
    local tooltipLink
    if ValidTooltipItemLink(targetLink) then tooltipLink = targetLink
    elseif ValidTooltipItemLink(item.link) then tooltipLink = item.link
    elseif ValidTooltipItemLink(item.itemLink) then tooltipLink = item.itemLink end
    if not tooltipLink and item.itemID then
        local _, cachedLink = C_Item.GetItemInfo(item.itemID)
        tooltipLink = cachedLink or ("item:" .. item.itemID)
    end
    local surfaced = false
    if tooltipLink and GameTooltip.SetHyperlink then
        surfaced = pcall(GameTooltip.SetHyperlink, GameTooltip, tooltipLink)
    end
    if not surfaced or GameTooltip:NumLines() == 0 then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(item.name or item.itemName or ("Item " .. tostring(item.itemID)), 1, 1, 1)
        GameTooltip:AddLine(L("Loot data is still loading. This page will refresh automatically."), 0.55, 0.58, 0.64)
        if item.itemID and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(item.itemID)
        end
    end
    if not targetLink or not surfaced then
        local levelReplaced = ReplaceTooltipItemLevel(GameTooltip, item, targetLevel)
        if targetLevel and not levelReplaced and targetLevel ~= item.itemLevel then
            GameTooltip:AddLine(EllesmereUI.Lf("Target item level: %d", targetLevel), 0.05, 0.82, 0.62)
        end
    end
    if craftedPreview then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("Crafted preview at the selected target item level."), 0.05, 0.82, 0.62)
        GameTooltip:AddLine(L("Secondary stats depend on the selected missives."), 0.65, 0.68, 0.74)
    end
    if showActions then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L("Left-click: change priority / Catalyst"), 0.75, 0.75, 0.75)
        GameTooltip:AddLine(L("Right-click: correct Voidcore pool"), 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
end

local function DisplayItemLink(item, targetLink)
    if targetLink then
        local _, cachedLink = C_Item.GetItemInfo(targetLink)
        if cachedLink then return cachedLink end
        -- Seasonal fallback items can still have their original rare-quality
        -- link cached. The target link always carries the modern epic bonus;
        -- build its display hyperlink immediately while Blizzard caches it.
        local itemName = item.name or C_Item.GetItemNameByID(item.itemID) or ("Item " .. item.itemID)
        return "|cffa335ee|H" .. targetLink .. "|h[" .. itemName .. "]|h|r"
    end
    return item.link or item.name or ("Item " .. item.itemID)
end

local function PriorityText(goal)
    if not goal then return L("Not marked"), 0.55, 0.55, 0.55 end
    local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
    local suffix = goal.catalyst and ("  |cffffb347" .. L("Catalyst") .. "|r") or ""
    if goal.state == "archived" then suffix = suffix .. "  |cff55dd88" .. L("Obtained") .. "|r" end
    return L(ns.PRIORITY_NAMES[goal.priority]) .. suffix, color[1], color[2], color[3]
end

local function AddCatalystBadge(parent, anchor, shown)
    if not shown then return end
    local bg = parent:CreateTexture(nil, "OVERLAY")
    bg:SetSize(14, 14); bg:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 3, 3)
    bg:SetColorTexture(0.12, 0.07, 0.02, 0.96)
    local glyph = parent:CreateFontString(nil, "OVERLAY")
    glyph:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    glyph:SetPoint("CENTER", bg, "CENTER", 0, 0)
    glyph:SetText("C"); glyph:SetTextColor(1, 0.7, 0.28, 1)
end

local function BuildItemRow(parent, y, source, item, specID, difficultyID)
    local sourceKey = source.kind == "raid" and ns.RaidKey(source.encounterID, difficultyID) or ns.DungeonKey(source.challengeModeID)
    local frame = Card(parent, y, ROW_H, true)
    frame:SetFrameLevel(parent:GetFrameLevel() + 2)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", frame, "LEFT", 7, 0)
    icon:SetTexture(item.icon or C_Item.GetItemIconByID(item.itemID))
    local name = Font(frame, 11, 0.95, 0.95, 0.95, 1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -2)
    name:SetPoint("RIGHT", frame, "RIGHT", -185, 0)
    name:SetJustifyH("LEFT")
    local slot = Font(frame, 9, 0.55, 0.58, 0.64, 1)
    slot:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 2)
    -- Dungeon links carry the Encounter Journal's base item level, which does
    -- not change when the selected target key changes. Display the calculated
    -- Voidcore reward level for M+ instead; raids retain their difficulty-
    -- specific item level from the journal (with the seasonal fallback).
    local displayItemLevel
    if source.kind == "dungeon" then
        displayItemLevel = ns.GetMPlusTargetLevel(Profile().selectedKeyLevel)
    else
        displayItemLevel = item.itemLevel
            or ns.GetRaidTargetLevel(source, specID, difficultyID, item.itemID)
    end
    local targetLink = ns.GetTargetItemLink(item.itemID, specID, displayItemLevel,
        source.kind, difficultyID, Profile().selectedKeyLevel)
    name:SetText(DisplayItemLink(item, targetLink))
    local slotText = item.slot or ""
    if displayItemLevel then slotText = slotText .. "  |cff777d88• iLvl " .. displayItemLevel .. "|r" end
    slot:SetText(slotText)

    local goal = ns.GetGoal(sourceKey, item.itemID, specID)
    AddCatalystBadge(frame, icon, goal and goal.catalyst)
    local obtained = (goal and goal.state == "archived") or ns.IsItemOwned(item.itemID, displayItemLevel)
    local priorityText, pr, pg, pb = PriorityText(goal)
    local status = Font(frame, 10, pr, pg, pb, 1)
    status:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    status:SetWidth(135)
    status:SetJustifyH("RIGHT")
    status:SetText(priorityText)
    local pool = ns.GetPool(sourceKey, specID)
    local poolState = frame:CreateTexture(nil, "ARTWORK")
    poolState:SetSize(7, 7)
    poolState:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    if pool.knocked[item.itemID] then
        poolState:SetColorTexture(0.05, 0.82, 0.62, 1)
    else
        poolState:SetColorTexture(0.38, 0.4, 0.45, 0.7)
    end

    -- The card itself is the button. Using the normal parent chain keeps the
    -- Spec Overrides frame walk acyclic, while AnyDown avoids a click being
    -- cancelled by the movable window before the mouse button is released.
    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
    frame:RegisterForClicks("AnyDown")
    local check = frame:CreateTexture(nil, "OVERLAY")
    check:SetAtlas("common-icon-checkmark")
    check:SetSize(16, 16)
    check:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    check:SetVertexColor(0.33, 0.87, 0.53, 1)
    check:SetShown(obtained)
    local function HandleItemClick(button)
        local currentGoal = ns.GetGoal(sourceKey, item.itemID, specID)
        local currentPool = ns.GetPool(sourceKey, specID)
        if button == "RightButton" then
            ns.SetPoolItemState(sourceKey, item.itemID, not currentPool.knocked[item.itemID], specID, "manual")
        elseif button == "LeftButton" then
            if currentGoal and currentGoal.state == "archived" then
                ns.ReactivateGoal(sourceKey, item.itemID, specID)
            else
                local target = source.kind == "raid"
                    and displayItemLevel
                    or ns.GetMPlusTargetLevel(Profile().selectedKeyLevel)
                ns.CycleGoal(source, item, specID, difficultyID, target)
            end
        end
    end
    frame:SetScript("OnEnter", function(self)
        frame._hover:SetColorTexture(1, 1, 1, 0.035)
        ShowItemTooltip(self, item, displayItemLevel, true, targetLink)
        if goal and goal.catalyst then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Catalyst planned"), 1, 0.7, 0.28)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        frame._hover:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    local hover = frame:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0); frame._hover = hover
    frame:SetScript("OnClick", function(_, button)
        frame._hover:SetColorTexture(1, 1, 1, 0.075)
        local ok, err = pcall(HandleItemClick, button)
        if not ok then
            print("|cffff5555EllesmereUI Loot Tracker click error:|r " .. tostring(err))
        end
    end)
    return ROW_H + ROW_GAP
end

local function SelectorRows(parent, y, kind)
    local W = EllesmereUI.Widgets
    local specValues, specOrder = BuildSpecValues()
    local sourceValues, sourceOrder = BuildSourceValues(kind)
    local sourceField = kind == "raid" and "selectedRaidEncounterID" or "selectedDungeonID"
    local firstSource = sourceOrder[1]
    local _, h = W:DualRow(parent, y,
        { type="dropdown", text="Loot Specialization", values=specValues, order=specOrder,
          getValue=function() return SelectedSpecID() end,
          setValue=function(v) Profile().selectedSpecID=tonumber(v) or v; ns.InvalidateCatalog(); QueuePageRebuild() end },
        { type="dropdown", text=kind == "raid" and "Raid Boss" or "Dungeon", values=sourceValues, order=sourceOrder,
          getValue=function() return Profile()[sourceField] or firstSource end,
          setValue=function(v) Profile()[sourceField]=tonumber(v) or v; QueuePageRebuild() end })
    y = y - h

    if kind == "raid" then
        local values, order = {}, {}
        for _, id in ipairs(ns.RAID_DIFFICULTIES) do
            values[id], order[#order + 1] = GetDifficultyInfo(id) or tostring(id), id
        end
        _, h = W:Dropdown(parent, "Raid Difficulty", y, values,
            function() return tonumber(Profile().raidDifficulty) or 16 end,
            function(v) Profile().raidDifficulty=tonumber(v) or 16; ns.InvalidateCatalog(); QueuePageRebuild() end, order,
            "Voidcore raid pools are tracked separately for each difficulty.")
    else
        local values, order = {}, {}
        for level = 2, 10 do values[level], order[#order + 1] = "+" .. level, level end
        _, h = W:Dropdown(parent, "Target Keystone Level", y, values,
            function() return tonumber(Profile().selectedKeyLevel) or 10 end,
            function(v) Profile().selectedKeyLevel=tonumber(v) or 10; QueuePageRebuild() end, order,
            "A goal is completed only by this Voidcore reward item level or higher.")
    end
    return y - h
end

local function BuildSearchRow(parent, y)
    local row = Card(parent, y, 50)
    local label = Font(row, 11, 0.9, 0.9, 0.9, 1)
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetText(L("Search"))
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(260, 28)
    box:SetPoint("LEFT", row, "LEFT", 100, 0)
    box:SetAutoFocus(false)
    box:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(0.92, 0.92, 0.92, 1)
    box:SetTextInsets(8, 8, 0, 0)
    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints(); boxBg:SetColorTexture(0.02, 0.025, 0.035, 0.9)
    EllesmereUI.MakeBorder(box, 1, 1, 1, 0.13, EllesmereUI.PP)
    box:SetText(Profile().lootSearch or "")
    box:SetScript("OnEnterPressed", function(self)
        Profile().lootSearch = self:GetText():lower()
        self:ClearFocus()
        QueuePageRebuild()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local clear = StyledButton(row, "Clear", 90, function()
        Profile().lootSearch = ""
        QueuePageRebuild()
    end)
    clear:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    return 56
end

local function BuildCatalogPage(parent, yOffset, kind)
    EllesmereUI:ClearContentHeader()
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h = W:SectionHeader(parent, kind == "raid" and "RAID LOOT" or "MYTHIC+ LOOT", y)
    y = y - h
    if not ns.IsSeasonSupported() then
        local warning = Card(parent, y, 74)
        local text = Font(warning, 11, 1, 0.45, 0.25, 1)
        text:SetPoint("TOPLEFT", warning, "TOPLEFT", 12, -12)
        text:SetPoint("BOTTOMRIGHT", warning, "BOTTOMRIGHT", -12, 12)
        text:SetWordWrap(true)
        text:SetText(L("Loot Tracker data does not support the current season yet. Probabilities are disabled until the source mapping is updated."))
        parent:SetHeight(120)
        return 120
    end
    y = SelectorRows(parent, y, kind)
    local specID = SelectedSpecID()
    local sourceID = kind == "raid" and Profile().selectedRaidEncounterID or Profile().selectedDungeonID
    local source = FindSource(kind, sourceID)
    if not source then parent:SetHeight(math.abs(y)); return math.abs(y) end
    local difficultyID = kind == "raid" and (tonumber(Profile().raidDifficulty) or 16) or nil
    local catalogKey = kind .. ":" .. tostring(sourceID) .. ":" .. tostring(specID) .. ":" .. tostring(difficultyID or 0)
    local summary = ns.GetSourceSummary(source, specID, difficultyID)
    local info = Card(parent, y, 42)
    local title = Font(info, 12, 1, 1, 1, 1)
    title:SetPoint("LEFT", info, "LEFT", 12, 0)
    local difficultyName = kind == "raid" and GetDifficultyInfo(difficultyID)
    title:SetText(difficultyName and (source.name .. "  |cff777d88• " .. difficultyName .. "|r") or source.name)
    local chance = Font(info, 11, 0.05, 0.82, 0.62, 1)
    chance:SetPoint("RIGHT", info, "RIGHT", -12, 0)
    local confidence = summary.confidence == "verified" and "" or (" " .. L("estimated"))
    chance:SetText(string.format("%d/%d  •  %.1f%%%s  •  %d %s", summary.desired, summary.remaining,
        summary.chance * 100, confidence, summary.coreCost, L("Voidcore")))
    y = y - 48
    local items = ns.GetCatalog(source, specID, difficultyID)
    local slotValues, slotOrder = { ALL = L("All Slots") }, { "ALL" }
    local seenSlots = {}
    for _, item in ipairs(items) do
        if item.slot and not seenSlots[item.slot] then
            seenSlots[item.slot] = true
            slotValues[item.slot] = item.slot
            slotOrder[#slotOrder + 1] = item.slot
        end
    end
    table.sort(slotOrder, function(a, b)
        if a == "ALL" then return true end
        if b == "ALL" then return false end
        return a < b
    end)
    if Profile().lootSlotFilter and not slotValues[Profile().lootSlotFilter] then Profile().lootSlotFilter = "ALL" end
    _, h = W:Dropdown(parent, "Item Slot", y, slotValues,
        function() return tostring(Profile().lootSlotFilter or "ALL") end,
        function(v) Profile().lootSlotFilter=tostring(v); QueuePageRebuild() end,
        slotOrder); y = y - h
    y = y - BuildSearchRow(parent, y)
    if #items == 0 then
        QueueCatalogRetry(catalogKey)
        local empty = Font(parent, 11, 0.65, 0.65, 0.65, 1)
        empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, y - 10)
        empty:SetText(L("Loot data is still loading. This page will refresh automatically."))
        y = y - 40
    else
        catalogRetries[catalogKey] = nil
        local shown = 0
        local slotFilter = tostring(Profile().lootSlotFilter or "ALL")
        local search = (Profile().lootSearch or ""):lower()
        for _, item in ipairs(items) do
            local slotMatch = slotFilter == "ALL" or item.slot == slotFilter
            local haystack = ((item.name or "") .. " " .. (item.slot or "")):lower()
            if slotMatch and (search == "" or haystack:find(search, 1, true)) then
                y = y - BuildItemRow(parent, y, source, item, specID, difficultyID)
                shown = shown + 1
            end
        end
        if shown == 0 then
            local empty = Font(parent, 11, 0.65, 0.65, 0.65, 1)
            empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, y - 10)
            empty:SetText(L("No items match the current filters."))
            y = y - 40
        end
    end
    parent:SetHeight(math.abs(y - yOffset) + 30)
    return math.abs(y - yOffset) + 30
end

local function BonusRollCountText(count)
    count = tonumber(count) or 0
    if count == 0 then return L("No bonus rolls used") end
    if count == 1 then return L("1 bonus roll used") end
    return EllesmereUI.Lf("%d bonus rolls used", count)
end

local function BuildBonusRollPriority(parent, y, specID)
    local W = EllesmereUI.Widgets
    local _, h = W:SectionHeader(parent, "BONUS ROLL PRIORITY", y); y = y - h
    local grouped = {}
    for _, goal in ipairs(ns.GetGoals(specID, false)) do
        if goal.state == "open" and (goal.sourceKind == "dungeon" or goal.sourceKind == "raid") then
            local pool = ns.GetPool(goal.sourceKey, specID)
            if not pool.knocked[goal.itemID] then
                local entry = grouped[goal.sourceKey]
                if not entry then
                    entry = {
                        source=ns.GetSourceByKey(goal.sourceKey), goals={}, weightedValue=0,
                        difficultyID=goal.difficultyID,
                    }
                    grouped[goal.sourceKey] = entry
                end
                entry.goals[#entry.goals + 1] = goal
                entry.weightedValue = entry.weightedValue + (goal.priority == ns.PRIORITY_BIS and 100
                    or (goal.priority == ns.PRIORITY_NEED and 25 or 5))
            end
        end
    end
    local entries = {}
    for _, entry in pairs(grouped) do
        if entry.source then
            entry.summary = ns.GetSourceSummary(entry.source, specID, entry.difficultyID)
            if entry.summary.remaining > 0 and entry.summary.desired > 0 then
                entry.score = entry.weightedValue / entry.summary.remaining
                entries[#entries + 1] = entry
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.summary.chance ~= b.summary.chance then return a.summary.chance > b.summary.chance end
        return (a.source.name or "") < (b.source.name or "")
    end)
    if #entries == 0 then
        local empty = Card(parent, y, 58)
        local text = Font(empty, 10, 0.62, 0.64, 0.68, 1)
        text:SetPoint("CENTER"); text:SetText(L("No open bonus-roll wishlist items."))
        return y - 64
    end
    for rank, entry in ipairs(entries) do
        table.sort(entry.goals, function(a, b) return a.priority > b.priority end)
        local row = Card(parent, y, 56)
        local rankText = Font(row, 14, rank == 1 and 0.05 or 0.45, rank == 1 and 0.82 or 0.48,
            rank == 1 and 0.62 or 0.54, 1)
        rankText:SetPoint("LEFT", row, "LEFT", 12, 0); rankText:SetText("#" .. rank)
        local sourceIcon = row:CreateTexture(nil, "ARTWORK")
        sourceIcon:SetSize(32, 32); sourceIcon:SetPoint("LEFT", row, "LEFT", 45, 0)
        sourceIcon:SetTexture(entry.source.texture or "Interface\\Icons\\INV_Misc_Dice_02")
        sourceIcon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        local name = Font(row, 11, 0.92, 0.94, 0.97, 1)
        name:SetPoint("TOPLEFT", row, "TOPLEFT", 87, -10)
        name:SetPoint("RIGHT", row, "RIGHT", -430, 0); name:SetWordWrap(false)
        local sourceName = entry.source.name
        if entry.source.kind == "raid" then
            sourceName = ((entry.source.instanceName and (entry.source.instanceName .. "  •  ")) or "") .. sourceName
            local difficultyName = GetDifficultyInfo(entry.difficultyID)
            if difficultyName then sourceName = sourceName .. "  (" .. difficultyName .. ")" end
        end
        name:SetText(sourceName)
        local detail = Font(row, 9, 0.55, 0.58, 0.64, 1)
        detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 87, 10)
        local chanceText = string.format("%.1f%%", entry.summary.chance * 100)
        if entry.summary.confidence ~= "verified" then
            chanceText = chanceText .. " " .. L("estimated")
        end
        detail:SetText(EllesmereUI.Lf("%1$s next roll • %2$d of %3$d in pool • %4$s",
            chanceText, entry.summary.remaining,
            entry.summary.total, BonusRollCountText(entry.summary.rollsUsed)))
        if rank == 1 then
            local nextBadge = Font(row, 8, 0.05, 0.82, 0.62, 1)
            nextBadge:SetPoint("LEFT", name, "RIGHT", 10, 0); nextBadge:SetText(L("NEXT ROLL"))
        end
        local function OpenSource()
            if entry.source.kind == "raid" then
                Profile().selectedRaidEncounterID = entry.source.encounterID
                Profile().raidDifficulty = entry.difficultyID or Profile().raidDifficulty
                EllesmereUI:SelectPage(PAGE_RAIDS)
            else
                Profile().selectedDungeonID = entry.source.challengeModeID
                EllesmereUI:SelectPage(PAGE_DUNGEONS)
            end
        end
        local openButton = CreateFrame("Button", nil, row)
        openButton:SetAllPoints(); openButton:RegisterForClicks("AnyDown")
        openButton:SetFrameLevel(row:GetFrameLevel() + 1)
        openButton:SetScript("OnClick", OpenSource)
        local iconX = -12
        for index = math.min(#entry.goals, 10), 1, -1 do
            local goal = entry.goals[index]
            local button = CreateFrame("Button", nil, row)
            button:SetSize(34, 34); button:SetPoint("RIGHT", row, "RIGHT", iconX, 0)
            button:SetFrameLevel(row:GetFrameLevel() + 2)
            local texture = button:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints(); texture:SetTexture(goal.itemIcon or C_Item.GetItemIconByID(goal.itemID))
            texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            AddCatalystBadge(button, texture, goal.catalyst)
            local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
            local strip = button:CreateTexture(nil, "OVERLAY")
            strip:SetPoint("BOTTOMLEFT"); strip:SetPoint("BOTTOMRIGHT"); strip:SetHeight(3)
            strip:SetColorTexture(color[1], color[2], color[3], 1)
            button:SetScript("OnEnter", function(self)
                local item = { itemID=goal.itemID, name=goal.itemName, link=goal.itemLink,
                    icon=goal.itemIcon, itemLevel=goal.itemLevel }
                local targetLink = ns.GetTargetItemLink(goal.itemID, goal.specID, goal.minItemLevel,
                    goal.linkKind or goal.sourceKind, goal.difficultyID, goal.keyLevel)
                ShowItemTooltip(self, item, goal.minItemLevel, false, targetLink)
                if goal.catalyst then
                    GameTooltip:AddLine(" "); GameTooltip:AddLine(L("Catalyst planned"), 1, 0.7, 0.28); GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:SetScript("OnClick", OpenSource)
            iconX = iconX - 39
        end
        y = y - 62
    end
    return y
end

local function BuildFarmPriority(parent, y, specID)
    local W = EllesmereUI.Widgets
    local _, h = W:SectionHeader(parent, "DUNGEON FARM PRIORITY", y); y = y - h
    local grouped = {}
    for _, goal in ipairs(ns.GetGoals(specID, false)) do
        if goal.sourceKind == "dungeon" and goal.state == "open" then
            local entry = grouped[goal.sourceKey]
            if not entry then
                entry = { source=ns.GetSourceByKey(goal.sourceKey), goals={}, score=0, bis=0 }
                grouped[goal.sourceKey] = entry
            end
            entry.goals[#entry.goals + 1] = goal
            entry.score = entry.score + (goal.priority == ns.PRIORITY_BIS and 100
                or (goal.priority == ns.PRIORITY_NEED and 25 or 5))
            if goal.priority == ns.PRIORITY_BIS then entry.bis = entry.bis + 1 end
        end
    end
    local entries = {}
    for _, entry in pairs(grouped) do if entry.source then entries[#entries + 1] = entry end end
    table.sort(entries, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if #a.goals ~= #b.goals then return #a.goals > #b.goals end
        return (a.source.name or "") < (b.source.name or "")
    end)
    if #entries == 0 then
        local empty = Card(parent, y, 58)
        local text = Font(empty, 10, 0.62, 0.64, 0.68, 1)
        text:SetPoint("CENTER"); text:SetText(L("No open dungeon wishlist items."))
        return y - 64
    end
    for rank, entry in ipairs(entries) do
        table.sort(entry.goals, function(a, b) return a.priority > b.priority end)
        local row = Card(parent, y, 56)
        local rankText = Font(row, 14, rank == 1 and 0.05 or 0.45, rank == 1 and 0.82 or 0.48,
            rank == 1 and 0.62 or 0.54, 1)
        rankText:SetPoint("LEFT", row, "LEFT", 12, 0); rankText:SetText("#" .. rank)
        local teleportButton = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        teleportButton:SetSize(32, 32); teleportButton:SetPoint("LEFT", row, "LEFT", 45, 0)
        teleportButton:RegisterForClicks("AnyUp")
        teleportButton:SetFrameLevel(row:GetFrameLevel() + 2)
        local dungeonIcon = teleportButton:CreateTexture(nil, "ARTWORK")
        dungeonIcon:SetAllPoints()
        dungeonIcon:SetTexture(entry.source.texture or "Interface\\Icons\\INV_Misc_Map_01")
        dungeonIcon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        local teleportSpellID = entry.source.teleportSpellID
        local function TeleportKnown()
            if not teleportSpellID then return false end
            if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
                return C_SpellBook.IsSpellInSpellBook(teleportSpellID)
            end
            return IsSpellKnown and IsSpellKnown(teleportSpellID)
        end
        local function ConfigureTeleport()
            if not teleportSpellID then return end
            if InCombatLockdown() then
                teleportButton:RegisterEvent("PLAYER_REGEN_ENABLED")
                return
            end
            teleportButton:UnregisterEvent("PLAYER_REGEN_ENABLED")
            teleportButton:SetAttribute("type", "spell")
            teleportButton:SetAttribute("spell", teleportSpellID)
        end
        teleportButton:SetScript("OnEvent", ConfigureTeleport)
        teleportButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if TeleportKnown() and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(teleportSpellID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("Click to teleport"), 0.05, 0.82, 0.62)
                if InCombatLockdown() then GameTooltip:AddLine(ERR_NOT_IN_COMBAT, 1, 0.2, 0.2) end
            else
                GameTooltip:SetText(entry.source.name, 1, 1, 1)
                GameTooltip:AddLine(L("Dungeon teleport not unlocked."), 0.8, 0.3, 0.3)
            end
            GameTooltip:Show()
        end)
        teleportButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dungeonIcon:SetDesaturated(not TeleportKnown())
        ConfigureTeleport()
        local name = Font(row, 11, 0.92, 0.94, 0.97, 1)
        name:SetPoint("TOPLEFT", row, "TOPLEFT", 87, -10)
        name:SetPoint("RIGHT", row, "RIGHT", -430, 0); name:SetWordWrap(false); name:SetText(entry.source.name)
        local summary = ns.GetSourceSummary(entry.source, specID)
        local detail = Font(row, 9, 0.55, 0.58, 0.64, 1)
        detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 87, 10)
        detail:SetText(EllesmereUI.Lf("%1$d upgrades • %2$d BiS • %3$s next roll",
            #entry.goals, entry.bis, string.format("%.1f%%", summary.chance * 100)))
        if rank == 1 then
            local nextBadge = Font(row, 8, 0.05, 0.82, 0.62, 1)
            nextBadge:SetPoint("LEFT", name, "RIGHT", 10, 0); nextBadge:SetText(L("NEXT"))
        end
        local function OpenDungeon()
            Profile().selectedDungeonID = entry.source.challengeModeID
            EllesmereUI:SelectPage(PAGE_DUNGEONS)
        end
        local openButton = CreateFrame("Button", nil, row)
        openButton:SetAllPoints(); openButton:RegisterForClicks("AnyDown")
        openButton:SetFrameLevel(row:GetFrameLevel() + 1)
        openButton:SetScript("OnClick", OpenDungeon)
        local iconX = -12
        for index = math.min(#entry.goals, 10), 1, -1 do
            local goal = entry.goals[index]
            local button = CreateFrame("Button", nil, row)
            button:SetSize(34, 34); button:SetPoint("RIGHT", row, "RIGHT", iconX, 0)
            button:SetFrameLevel(row:GetFrameLevel() + 2)
            local texture = button:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints(); texture:SetTexture(goal.itemIcon or C_Item.GetItemIconByID(goal.itemID))
            texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            AddCatalystBadge(button, texture, goal.catalyst)
            local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
            local strip = button:CreateTexture(nil, "OVERLAY")
            strip:SetPoint("BOTTOMLEFT"); strip:SetPoint("BOTTOMRIGHT"); strip:SetHeight(3)
            strip:SetColorTexture(color[1], color[2], color[3], 1)
            button:SetScript("OnEnter", function(self)
                local item = { itemID=goal.itemID, name=goal.itemName, link=goal.itemLink,
                    icon=goal.itemIcon, itemLevel=goal.itemLevel }
                local targetLink = ns.GetTargetItemLink(goal.itemID, goal.specID, goal.minItemLevel,
                    goal.linkKind or goal.sourceKind, goal.difficultyID, goal.keyLevel)
                ShowItemTooltip(self, item, goal.minItemLevel, false, targetLink)
                if goal.catalyst then
                    GameTooltip:AddLine(" "); GameTooltip:AddLine(L("Catalyst planned"), 1, 0.7, 0.28); GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:SetScript("OnClick", OpenDungeon)
            iconX = iconX - 39
        end
        y = y - 62
    end
    return y
end

local function BuildOverview(parent, yOffset)
    EllesmereUI:ClearContentHeader()
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h = W:SectionHeader(parent, "GEARING OVERVIEW", y); y = y - h
    local specValues, specOrder = BuildSpecValues()
    _, h = W:Dropdown(parent, "Loot Specialization", y, specValues,
        function() return SelectedSpecID() end,
        function(v) Profile().selectedSpecID=tonumber(v) or v; QueuePageRebuild() end,
        specOrder); y = y - h
    y = BuildBonusRollPriority(parent, y, SelectedSpecID())
    y = BuildFarmPriority(parent, y, SelectedSpecID())
    _, h = W:SectionHeader(parent, "SOURCE DETAILS", y); y = y - h
    local goals = ns.GetGoals(SelectedSpecID(), Profile().showArchived)
    local grouped, keys = {}, {}
    for _, goal in ipairs(goals) do
        if not grouped[goal.sourceKey] then grouped[goal.sourceKey] = {}; keys[#keys + 1] = goal.sourceKey end
        grouped[goal.sourceKey][#grouped[goal.sourceKey] + 1] = goal
    end
    table.sort(keys)
    if #keys == 0 then
        local empty = Card(parent, y, 74)
        local text = Font(empty, 11, 0.7, 0.72, 0.76, 1)
        text:SetPoint("CENTER")
        text:SetText(L("Mark items on the Dungeons or Raids page to build your gearing plan."))
        y = y - 80
    end
    for _, sourceKey in ipairs(keys) do
        local source = ns.GetSourceByKey(sourceKey)
        if source then
            local difficultyID = grouped[sourceKey][1].difficultyID
            local summary = ns.GetSourceSummary(source, SelectedSpecID(), difficultyID)
            local parentWidth = parent:GetWidth()
            if not parentWidth or parentWidth < 500 then parentWidth = 900 end
            local columns = math.max(6, math.floor((parentWidth - 64) / 44))
            local rows = math.ceil(#grouped[sourceKey] / columns)
            local card = Card(parent, y, 58 + rows * 44)
            local name = Font(card, 12, 1, 1, 1, 1)
            name:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
            local sourceName = source.kind == "raid" and source.instanceName
                and (source.instanceName .. "  •  " .. source.name) or L(source.name)
            if source.kind == "raid" then
                local difficultyName = GetDifficultyInfo(difficultyID)
                if difficultyName then sourceName = sourceName .. "  (" .. difficultyName .. ")" end
            elseif source.kind == "dungeon" then
                local keyLevel = grouped[sourceKey][1].keyLevel
                if keyLevel then sourceName = sourceName .. "  (+" .. keyLevel .. ")" end
            end
            name:SetText(sourceName)
            local chance = Font(card, 10, 0.05, 0.82, 0.62, 1)
            chance:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -11)
            if source.kind == "raid" or source.kind == "dungeon" then
                chance:SetText(string.format("%.1f%%  •  %s", summary.chance * 100,
                    BonusRollCountText(summary.rollsUsed)))
            else
                chance:SetText(source.kind == "catalyst" and L("Catalyst conversion") or L("Crafting"))
            end
            local pool = Font(card, 9, 0.55, 0.58, 0.64, 1)
            pool:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
            if source.kind == "raid" or source.kind == "dungeon" then
                pool:SetText(EllesmereUI.Lf("%1$d desired • %2$d of %3$d remaining", summary.desired, summary.remaining, summary.total))
            else
                pool:SetText(EllesmereUI.Lf("%d selected for this plan", #grouped[sourceKey]))
            end
            for index, goal in ipairs(grouped[sourceKey]) do
                local priorityID = goal.priority
                local color = ns.PRIORITY_COLORS[priorityID] or { 1, 1, 1 }
                local obtained = goal.state == "archived" or ns.IsItemOwned(goal.itemID, goal.minItemLevel)
                local tooltipItem = {
                    itemID = goal.itemID,
                    name = goal.itemName,
                    link = goal.itemLink,
                    icon = goal.itemIcon,
                    itemLevel = goal.itemLevel,
                }
                local targetLevel = goal.minItemLevel
                local targetLink = ns.GetTargetItemLink(goal.itemID, goal.specID, targetLevel,
                    goal.linkKind or goal.sourceKind, goal.difficultyID, goal.keyLevel)
                local itemHitbox = CreateFrame("Button", nil, card)
                itemHitbox:SetSize(38, 38)
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                itemHitbox:SetPoint("TOPLEFT", card, "TOPLEFT", 14 + column * 44, -47 - row * 44)
                itemHitbox:SetFrameLevel(card:GetFrameLevel() + 2)
                itemHitbox:EnableMouse(true)
                local itemIcon = itemHitbox:CreateTexture(nil, "ARTWORK")
                itemIcon:SetAllPoints()
                itemIcon:SetTexture(goal.itemIcon or C_Item.GetItemIconByID(goal.itemID))
                itemIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                itemIcon:SetDesaturated(obtained)
                itemIcon:SetAlpha(obtained and 0.55 or 1)
                AddCatalystBadge(itemHitbox, itemIcon, goal.catalyst)
                local priority = itemHitbox:CreateTexture(nil, "OVERLAY")
                priority:SetPoint("BOTTOMLEFT", itemHitbox, "BOTTOMLEFT", 0, 0)
                priority:SetPoint("BOTTOMRIGHT", itemHitbox, "BOTTOMRIGHT", 0, 0)
                priority:SetHeight(3)
                priority:SetColorTexture(color[1], color[2], color[3], 1)
                if obtained then
                    local check = itemHitbox:CreateTexture(nil, "OVERLAY")
                    check:SetAtlas("common-icon-checkmark")
                    check:SetSize(17, 17)
                    check:SetPoint("BOTTOMRIGHT", itemHitbox, "BOTTOMRIGHT", 3, -3)
                    check:SetVertexColor(0.33, 0.87, 0.53, 1)
                end
                itemHitbox:SetScript("OnEnter", function(self)
                    ShowItemTooltip(self, tooltipItem, targetLevel, false, targetLink,
                        goal.sourceKind == "crafted")
                    local priorityName = L(ns.PRIORITY_NAMES[priorityID] or "Nice to have")
                    local state = obtained and L("Obtained") or L("Open")
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine(priorityName, state,
                        color[1], color[2], color[3], obtained and 0.33 or 0.8, obtained and 0.87 or 0.8, obtained and 0.53 or 0.8)
                    if goal.catalyst then GameTooltip:AddLine(L("Catalyst planned"), 1, 0.7, 0.28) end
                    GameTooltip:Show()
                end)
                itemHitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            y = y - card:GetHeight() - 6
        end
    end
    parent:SetHeight(math.abs(y - yOffset) + 30)
    return math.abs(y - yOffset) + 30
end

local function PlannerSlotCard(parent, y, slot, selection, selected, right, onSelect)
    local frame = CreateFrame("Button", nil, parent)
    if right then
        frame:SetPoint("TOPLEFT", parent, "TOP", 4, y)
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, y)
    else
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
        frame:SetPoint("TOPRIGHT", parent, "TOP", -4, y)
    end
    frame:SetHeight(48)
    frame:RegisterForClicks("AnyDown")
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(selected and 0.025 or 0.035, selected and 0.12 or 0.04, selected and 0.105 or 0.055, 0.9)
    EllesmereUI.MakeBorder(frame, selected and 0.05 or 1, selected and 0.82 or 1,
        selected and 0.62 or 1, selected and 0.65 or 0.08, EllesmereUI.PP)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36); icon:SetPoint("LEFT", frame, "LEFT", 7, 0)
    icon:SetTexture(selection and (selection.itemIcon or C_Item.GetItemIconByID(selection.itemID))
        or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetDesaturated(not selection)
    AddCatalystBadge(frame, icon, selection and selection.catalyst)
    local slotName = Font(frame, 9, 0.55, 0.58, 0.64, 1)
    slotName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -4)
    slotName:SetText(slot.name or slot.key)
    local itemName = Font(frame, 10, selection and 0.78 or 0.68, selection and 0.35 or 0.7,
        selection and 1 or 0.74, 1)
    itemName:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 4)
    itemName:SetPoint("RIGHT", frame, "RIGHT", -28, 0)
    itemName:SetJustifyH("LEFT")
    local selectedName = selection and selection.itemName
    if selectedName and selection.targetLevel then
        selectedName = selectedName .. "  |cff777d88• iLvl " .. selection.targetLevel .. "|r"
    end
    if selectedName and selection.catalyst then
        selectedName = selectedName .. "  |cffffb347" .. L("Catalyst") .. "|r"
    end
    itemName:SetText(selectedName or L("Click to choose an item"))
    if selection then
        local clear = Font(frame, 15, 0.65, 0.67, 0.72, 1)
        clear:SetPoint("RIGHT", frame, "RIGHT", -9, 0); clear:SetText("×")
    end
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" and selection then
            onSelect(true)
        elseif selection and selected and (selection.sourceKind == "dungeon" or selection.sourceKind == "raid") then
            onSelect(false, true)
        else
            onSelect(false)
        end
    end)
    frame:SetScript("OnEnter", function(self)
        if selection then
            local targetLink = ns.GetTargetItemLink(selection.itemID, SelectedSpecID(), selection.targetLevel,
                selection.linkKind or selection.sourceKind, selection.difficultyID, selection.keyLevel)
            ShowItemTooltip(self, selection, selection.targetLevel, false, targetLink,
                selection.sourceKind == "crafted")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Right-click to clear this slot"), 0.75, 0.75, 0.75)
            if selection.sourceKind == "dungeon" or selection.sourceKind == "raid" then
                GameTooltip:AddLine(L("Left-click again to toggle Catalyst"), 1, 0.7, 0.28)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildPlannerCandidate(parent, y, candidate, selected, onClick)
    local source, item = candidate.source, candidate.item
    local selectedGoal = selected and ns.GetGoal(candidate.sourceKey, item.itemID, SelectedSpecID())
    local catalyst = selectedGoal and selectedGoal.catalyst
    local frame = Card(parent, y, 43, true)
    frame:RegisterForClicks("AnyDown")
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32); icon:SetPoint("LEFT", frame, "LEFT", 7, 0)
    icon:SetTexture(item.icon or C_Item.GetItemIconByID(item.itemID)); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    AddCatalystBadge(frame, icon, catalyst)
    local name = Font(frame, 10, 0.78, 0.35, 1, 1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -4); name:SetText(item.name or ("Item " .. item.itemID))
    local sourceText = source.kind == "raid" and ((source.instanceName or "Raid") .. " • " .. source.name)
        or L(source.name)
    local sub = Font(frame, 9, 0.55, 0.58, 0.64, 1)
    sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 4)
    sub:SetText(sourceText .. (candidate.targetLevel and ("  •  iLvl " .. candidate.targetLevel) or ""))
    local state = Font(frame, 10, selected and 0.05 or 0.55, selected and 0.82 or 0.58,
        selected and 0.62 or 0.64, 1)
    state:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    state:SetText(selected and (L("Selected BiS") .. (catalyst and ("  |cffffb347" .. L("Catalyst") .. "|r") or "")) or L("Set as BiS"))
    frame:SetScript("OnClick", onClick)
    frame:SetScript("OnEnter", function(self)
        local targetLink = ns.GetTargetItemLink(item.itemID, SelectedSpecID(), candidate.targetLevel,
            candidate.linkKind or source.kind, candidate.difficultyID, candidate.keyLevel)
        ShowItemTooltip(self, item, candidate.targetLevel, false, targetLink, source.kind == "crafted")
        if selected and (source.kind == "dungeon" or source.kind == "raid") then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("Click selected item again to toggle Catalyst"), 1, 0.7, 0.28)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return 47
end

local function BuildCraftedItemInput(parent, y)
    local row = Card(parent, y, 52)
    local label = Font(row, 10, 0.78, 0.8, 0.84, 1)
    label:SetPoint("LEFT", row, "LEFT", 12, 0)
    label:SetText(L("Add craftable by item link or ID"))
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(285, 28); box:SetPoint("RIGHT", row, "RIGHT", -116, 0)
    box:SetAutoFocus(false)
    box:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 10, "")
    box:SetTextColor(0.92, 0.92, 0.92, 1); box:SetTextInsets(7, 7, 0, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.02, 0.025, 0.035, 0.9)
    EllesmereUI.MakeBorder(box, 1, 1, 1, 0.13, EllesmereUI.PP)
    local function AddItem()
        local value = box:GetText()
        if ns.AddCraftedItemLink(value) then
            box:SetText(""); box:ClearFocus(); QueuePageRebuild()
        else
            print("|cffff5555EllesmereUI Loot Tracker:|r " .. L("This is not an equippable item link or item ID."))
        end
    end
    box:SetScript("OnEnterPressed", AddItem)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local add = StyledButton(row, L("Add"), 94, AddItem)
    add:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    return 58
end

local function BuildPlanner(parent, yOffset)
    EllesmereUI:ClearContentHeader()
    local W, y = EllesmereUI.Widgets, yOffset
    local _, h = W:SectionHeader(parent, "GEAR PLANNER", y); y = y - h
    local modeValues, modeOrder = {}, {}
    for _, mode in ipairs(ns.PLAN_MODES) do modeValues[mode], modeOrder[#modeOrder + 1] = L(ns.PLAN_MODE_NAMES[mode]), mode end
    local specValues, specOrder = BuildSpecValues()
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Plan", values=modeValues, order=modeOrder,
          getValue=function() return Profile().plannerMode or "overall" end,
          setValue=function(v) Profile().plannerMode=v; QueuePageRebuild() end },
        { type="dropdown", text="Loot Specialization", values=specValues, order=specOrder,
          getValue=function() return SelectedSpecID() end,
          setValue=function(v) Profile().selectedSpecID=tonumber(v) or v; ns.InvalidateCatalog(); QueuePageRebuild() end }); y = y - h
    local keyValues, keyOrder = {}, {}
    for level = 2, 10 do keyValues[level], keyOrder[#keyOrder + 1] = "+" .. level, level end
    local raidValues, raidOrder = {}, {}
    for _, id in ipairs(ns.RAID_DIFFICULTIES) do raidValues[id], raidOrder[#raidOrder + 1] = GetDifficultyInfo(id) or tostring(id), id end
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="M+ Target Level", values=keyValues, order=keyOrder,
          getValue=function() return tonumber(Profile().selectedKeyLevel) or 10 end,
          setValue=function(v) Profile().selectedKeyLevel=tonumber(v) or 10; QueuePageRebuild() end },
        { type="dropdown", text="Raid Difficulty", values=raidValues, order=raidOrder,
          getValue=function() return tonumber(Profile().raidDifficulty) or 16 end,
          setValue=function(v) Profile().raidDifficulty=tonumber(v) or 16; ns.InvalidateCatalog(); QueuePageRebuild() end }); y = y - h
    local craftedValues, craftedOrder = {}, {}
    for _, level in ipairs({ 279, 282, 285, 289, 292, 295, 298, 302, 305, 308, 311, 315, 318, 321, 324, 328, 331, 334 }) do
        craftedValues[level], craftedOrder[#craftedOrder + 1] = "iLvl " .. level, level
    end
    _, h = W:Dropdown(parent, "Crafted Target Item Level", y, craftedValues,
        function() return tonumber(Profile().craftedTargetLevel) or 318 end,
        function(v) Profile().craftedTargetLevel=tonumber(v) or 318; QueuePageRebuild() end,
        craftedOrder, "Crafted secondary stats are customizable and therefore only estimated."); y = y - h
    local mode, specID = Profile().plannerMode or "overall", SelectedSpecID()
    local difficultyID = tonumber(Profile().raidDifficulty) or 16
    local keyLevel = tonumber(Profile().selectedKeyLevel) or 10
    local planKey = mode == "raid" and (mode .. ":" .. difficultyID) or mode
    ns.RefreshPlanTargets(planKey, specID, keyLevel, difficultyID, Profile().craftedTargetLevel)
    local plan = ns.GetPlan(planKey, specID)
    local selectedSlot = Profile().plannerSlot or "HEAD"
    for index, slot in ipairs(ns.PLAN_SLOTS) do
        local row = math.floor((index - 1) / 2)
        PlannerSlotCard(parent, y - row * 54, slot, plan.slots[slot.key], selectedSlot == slot.key,
            index % 2 == 0, function(clear, toggleCatalyst)
                if clear then ns.SetPlannedItem(planKey, slot.key, nil, specID)
                elseif toggleCatalyst then ns.ToggleGoalCatalyst(plan.slots[slot.key].sourceKey, plan.slots[slot.key].itemID, specID)
                else Profile().plannerSlot = slot.key; QueuePageRebuild() end
            end)
    end
    y = y - math.ceil(#ns.PLAN_SLOTS / 2) * 54 - 4
    _, h = W:WideButton(parent, "Copy SimC Gear Set", y, function()
        StaticPopup_Show("EULT_SIMC_EXPORT", nil, nil, ns.GetSimCPlan(planKey, specID))
    end, 280); y = y - h
    _, h = W:SectionHeader(parent, string.upper(L("Available items for %s"):format((ns.GetPlanSlot(selectedSlot) or {}).name or selectedSlot)), y); y = y - h
    y = y - BuildCraftedItemInput(parent, y)
    local candidates = ns.GetPlannerCandidates(mode, selectedSlot, specID, difficultyID, keyLevel)
    if #candidates == 0 then
        QueueCatalogRetry("planner:" .. mode .. ":" .. selectedSlot .. ":" .. specID)
        local empty = Card(parent, y, 58)
        local text = Font(empty, 10, 0.62, 0.64, 0.68, 1); text:SetPoint("CENTER")
        text:SetText(L("Loot data is still loading. This page will refresh automatically.")); y = y - 64
    else
        for _, candidate in ipairs(candidates) do
            local selected = plan.slots[selectedSlot]
            local isSelected = selected and selected.sourceKey == candidate.sourceKey and selected.itemID == candidate.item.itemID
            y = y - BuildPlannerCandidate(parent, y, candidate, isSelected, function()
                ns.SetPlannedItem(planKey, selectedSlot, candidate, specID)
            end)
        end
    end
    parent:SetHeight(math.abs(y - yOffset) + 30)
    return math.abs(y - yOffset) + 30
end

local function BuildSettings(parent, yOffset)
    EllesmereUI:ClearContentHeader()
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h = W:SectionHeader(parent, "TRACKING", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Item Tooltip Status",
          getValue=function() return Profile().showItemTooltips end,
          setValue=function(v) Profile().showItemTooltips=v end },
        { type="toggle", text="Wishlist Icon Markers",
          getValue=function() return Profile().showWishlistMarkers ~= false end,
          setValue=function(v) Profile().showWishlistMarkers=v; ns.RefreshWishlistMarkers() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Automatically Archive Items",
          getValue=function() return Profile().autoArchive end,
          setValue=function(v) Profile().autoArchive=v; if v then ns.QueueInventoryScan() end end },
        nil); y = y - h
    _, h = W:Toggle(parent, "Show Archived Goals", y,
        function() return Profile().showArchived end,
        function(v) Profile().showArchived=v; QueuePageRebuild() end,
        "Shows completed goals in the gearing overview."); y = y - h
    _, h = W:SectionHeader(parent, "LOOT ALERTS", y); y = y - h
    _, h = W:Toggle(parent, "Wishlist Loot Popup", y,
        function() return Profile().lootWhisperPopup ~= false end,
        function(v) Profile().lootWhisperPopup=v end,
        "Shows a trade whisper popup when another group member loots an open wishlist item."); y = y - h
    local whisper = Card(parent, y, 82)
    local whisperLabel = Font(whisper, 10, 0.85, 0.87, 0.9, 1)
    whisperLabel:SetPoint("TOPLEFT", whisper, "TOPLEFT", 12, -10)
    whisperLabel:SetText(L("Whisper Template"))
    local whisperHint = Font(whisper, 8, 0.5, 0.53, 0.58, 1)
    whisperHint:SetPoint("BOTTOMLEFT", whisper, "BOTTOMLEFT", 12, 8)
    whisperHint:SetText(L("Available placeholders: {player}, {item}"))
    local whisperBox = CreateFrame("EditBox", nil, whisper)
    whisperBox:SetPoint("TOPLEFT", whisper, "TOPLEFT", 145, -8)
    whisperBox:SetPoint("TOPRIGHT", whisper, "TOPRIGHT", -108, -8)
    whisperBox:SetHeight(28); whisperBox:SetAutoFocus(false)
    whisperBox:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 9, "")
    whisperBox:SetTextColor(0.9, 0.92, 0.95, 1); whisperBox:SetTextInsets(7, 7, 0, 0)
    whisperBox:SetText(Profile().whisperTemplate or "")
    local whisperBG = whisperBox:CreateTexture(nil, "BACKGROUND")
    whisperBG:SetAllPoints(); whisperBG:SetColorTexture(0.01, 0.014, 0.02, 0.96)
    EllesmereUI.MakeBorder(whisperBox, 1, 1, 1, 0.13, EllesmereUI.PP)
    local function SaveWhisper()
        local value = whisperBox:GetText()
        if value ~= "" then Profile().whisperTemplate = value end
        whisperBox:ClearFocus()
    end
    whisperBox:SetScript("OnEnterPressed", SaveWhisper)
    whisperBox:SetScript("OnEscapePressed", function(self) self:SetText(Profile().whisperTemplate or ""); self:ClearFocus() end)
    local saveWhisper = StyledButton(whisper, L("Save"), 84, SaveWhisper)
    saveWhisper:SetPoint("TOPRIGHT", whisper, "TOPRIGHT", -12, -8)
    y = y - 88
    _, h = W:SectionHeader(parent, "VOIDCORE POOLS", y); y = y - h
    _, h = W:WideButton(parent, "Rescan Voidcore Pools", y, function()
        print("|cff0cd29fEllesmereUI Loot Tracker|r: " .. L("Scanning Voidcore pools..."))
        ns.RescanVoidcorePools(function()
            print("|cff0cd29fEllesmereUI Loot Tracker|r: " .. L("Voidcore pool scan complete."))
            QueuePageRebuild()
        end)
    end, 360); y = y - h
    local note = Card(parent, y, 84)
    local text = Font(note, 10, 0.68, 0.7, 0.75, 1)
    text:SetPoint("TOPLEFT", note, "TOPLEFT", 12, -12)
    text:SetPoint("BOTTOMRIGHT", note, "BOTTOMRIGHT", -12, 12)
    text:SetJustifyH("LEFT"); text:SetJustifyV("TOP"); text:SetWordWrap(true)
    text:SetText(L("Right-click an item in a loot page to manually correct whether it has already been removed from its Voidcore pool. Only Voidcore rewards change this pool automatically; normal loot can still complete a wishlist goal."))
    y = y - 90
    parent:SetHeight(math.abs(y - yOffset) + 30)
    return math.abs(y - yOffset) + 30
end

local function Contains(list, value)
    for _, entry in ipairs(list or {}) do
        if entry == value or (type(entry) == "table" and entry.folder == value) then return true end
    end
    return false
end

local function InstallMenuEntry()
    -- Register through the public roster tables exported by EllesmereUI. Keeping
    -- every integration change inside this companion addon means suite updates
    -- can replace EllesmereUI.lua and EllesmereUIOptions without removing us.
    local info = {
        folder = ADDON_NAME,
        display = "Loot Tracker",
        search_name = "EllesmereUI Loot Tracker Gear Wishlist Voidcore",
    }
    local roster = EllesmereUI.ADDON_ROSTER
    if roster and not Contains(roster, ADDON_NAME) then roster[#roster + 1] = info end
    if EllesmereUI._addonInfoByFolder then EllesmereUI._addonInfoByFolder[ADDON_NAME] = info end

    local groups = EllesmereUI.ADDON_GROUPS
    if groups then
        local target
        for _, group in ipairs(groups) do
            if group.key == "qol" then target = group break end
        end
        if not target then
            target = { key = "loottracker", label = "QoL Addons", members = {} }
            groups[#groups + 1] = target
        end
        if not Contains(target.members, ADDON_NAME) then
            local insertAt = #target.members + 1
            for index, folder in ipairs(target.members) do
                if folder == "EllesmereUIQoL" then insertAt = index + 1 break end
            end
            table.insert(target.members, insertAt, ADDON_NAME)
        end
    end

    local profileMap = EllesmereUI._ADDON_DB_MAP
    if profileMap and not Contains(profileMap, ADDON_NAME) then
        profileMap[#profileMap + 1] = {
            folder = ADDON_NAME,
            display = "Loot Tracker",
            svName = "EllesmereUILootTrackerDB",
            suffix = "LootTracker",
        }
    end
end

local moduleConfig = {
    title = "Loot Tracker",
    description = "Plan dungeon and raid upgrades, track acquired gear, and calculate Voidcore odds.",
    pages = { PAGE_OVERVIEW, PAGE_PLANNER, PAGE_DUNGEONS, PAGE_RAIDS, PAGE_SETTINGS },
    _euiCore = false,
    buildPage = function(pageName, parent, yOffset)
        if pageName == PAGE_OVERVIEW then return BuildOverview(parent, yOffset) end
        if pageName == PAGE_PLANNER then return BuildPlanner(parent, yOffset) end
        if pageName == PAGE_DUNGEONS then return BuildCatalogPage(parent, yOffset, "dungeon") end
        if pageName == PAGE_RAIDS then return BuildCatalogPage(parent, yOffset, "raid") end
        return BuildSettings(parent, yOffset)
    end,
    onReset = function()
        local db = _G._EULT_DB and _G._EULT_DB()
        if db and db.ResetProfile then db:ResetProfile() end
        EllesmereUI:InvalidatePageCache()
    end,
}

InstallMenuEntry()
if EllesmereUI._modules then
    EllesmereUI._modules[ADDON_NAME] = moduleConfig
elseif EllesmereUI.RegisterModule then
    -- Compatibility fallback for older suite versions which did not expose the
    -- module table yet and still accepted companion registration directly.
    EllesmereUI:RegisterModule(ADDON_NAME, moduleConfig)
end

ns.RegisterCallback(function() QueuePageRebuild() end)
