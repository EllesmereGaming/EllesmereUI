if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME = "EllesmereUILootTracker"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end

local L = EllesmereUI.L
local PAGE_OVERVIEW = "Overview"
local PAGE_DUNGEONS = "Dungeons"
local PAGE_RAIDS = "Raids"
local PAGE_SETTINGS = "Settings"
local ROW_H, ROW_GAP = 46, 3

local function Profile()
    return ns.GetProfile()
end

local function SelectedSpecID()
    local value = Profile().selectedSpecID
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

local function ShowItemTooltip(frame, item)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    if item.link then GameTooltip:SetHyperlink(item.link) else GameTooltip:SetItemByID(item.itemID) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L("Left-click: change priority"), 0.75, 0.75, 0.75)
    GameTooltip:AddLine(L("Right-click: correct Voidcore pool"), 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

local function PriorityText(goal)
    if not goal then return L("Not marked"), 0.55, 0.55, 0.55 end
    local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
    local suffix = goal.state == "archived" and ("  |cff55dd88" .. L("Obtained") .. "|r") or ""
    return L(ns.PRIORITY_NAMES[goal.priority]) .. suffix, color[1], color[2], color[3]
end

local function BuildItemRow(parent, y, source, item, specID, difficultyID)
    local sourceKey = source.kind == "raid" and ns.RaidKey(source.encounterID, difficultyID) or ns.DungeonKey(source.challengeModeID)
    local frame = Card(parent, y, ROW_H, true)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("LEFT", frame, "LEFT", 7, 0)
    icon:SetTexture(item.icon or C_Item.GetItemIconByID(item.itemID))
    local name = Font(frame, 11, 0.95, 0.95, 0.95, 1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 9, -2)
    name:SetPoint("RIGHT", frame, "RIGHT", -185, 0)
    name:SetJustifyH("LEFT")
    name:SetText(item.link or item.name or ("Item " .. item.itemID))
    local slot = Font(frame, 9, 0.55, 0.58, 0.64, 1)
    slot:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 9, 2)
    slot:SetText(item.slot or "")

    local goal = ns.GetGoal(sourceKey, item.itemID, specID)
    local priorityText, pr, pg, pb = PriorityText(goal)
    local status = Font(frame, 10, pr, pg, pb, 1)
    status:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
    status:SetWidth(135)
    status:SetJustifyH("RIGHT")
    status:SetText(priorityText)
    local pool = ns.GetPool(sourceKey, specID)
    local die = Font(frame, 14, 0.55, 0.55, 0.55, 1)
    die:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    die:SetText(pool.knocked[item.itemID] and "|cff0cd29f●|r" or "○")

    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnEnter", function(self)
        frame._hover:SetColorTexture(1, 1, 1, 0.035)
        ShowItemTooltip(self, item)
    end)
    frame:SetScript("OnLeave", function()
        frame._hover:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    local hover = frame:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0); frame._hover = hover
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.SetPoolItemState(sourceKey, item.itemID, not pool.knocked[item.itemID], specID, "manual")
        elseif goal and goal.state == "archived" then
            ns.ReactivateGoal(sourceKey, item.itemID, specID)
        else
            local target = source.kind == "raid"
                and (item.itemLevel or ns.GetRaidTargetLevel(source, specID, difficultyID, item.itemID))
                or ns.GetMPlusTargetLevel(Profile().selectedKeyLevel)
            ns.CycleGoal(source, item, specID, difficultyID, target)
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
          setValue=function(v) Profile().selectedSpecID=v; EllesmereUI:RefreshPage() end },
        { type="dropdown", text=kind == "raid" and "Raid Boss" or "Dungeon", values=sourceValues, order=sourceOrder,
          getValue=function() return Profile()[sourceField] or firstSource end,
          setValue=function(v) Profile()[sourceField]=v; EllesmereUI:RefreshPage() end })
    y = y - h

    if kind == "raid" then
        local values, order = {}, {}
        for _, id in ipairs(ns.RAID_DIFFICULTIES) do
            values[id], order[#order + 1] = GetDifficultyInfo(id) or tostring(id), id
        end
        _, h = W:Dropdown(parent, "Raid Difficulty", y, values,
            function() return Profile().raidDifficulty or 16 end,
            function(v) Profile().raidDifficulty=v; EllesmereUI:RefreshPage() end, order,
            "Voidcore raid pools are tracked separately for each difficulty.")
    else
        local values, order = {}, {}
        for level = 2, 10 do values[level], order[#order + 1] = "+" .. level, level end
        _, h = W:Dropdown(parent, "Target Keystone Level", y, values,
            function() return Profile().selectedKeyLevel or 10 end,
            function(v) Profile().selectedKeyLevel=v; EllesmereUI:RefreshPage() end, order,
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
        EllesmereUI:RefreshPage()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local clear = StyledButton(row, "Clear", 90, function()
        Profile().lootSearch = ""
        EllesmereUI:RefreshPage()
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
    local difficultyID = kind == "raid" and (Profile().raidDifficulty or 16) or nil
    local summary = ns.GetSourceSummary(source, specID, difficultyID)
    local info = Card(parent, y, 42)
    local title = Font(info, 12, 1, 1, 1, 1)
    title:SetPoint("LEFT", info, "LEFT", 12, 0)
    title:SetText(source.name)
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
        function() return Profile().lootSlotFilter or "ALL" end,
        function(v) Profile().lootSlotFilter=v; EllesmereUI:RefreshPage() end,
        slotOrder); y = y - h
    y = y - BuildSearchRow(parent, y)
    if #items == 0 then
        local empty = Font(parent, 11, 0.65, 0.65, 0.65, 1)
        empty:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, y - 10)
        empty:SetText(L("Loot data is still loading. Reopen this page in a moment."))
        y = y - 40
    else
        local shown = 0
        local slotFilter = Profile().lootSlotFilter or "ALL"
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

local function BuildOverview(parent, yOffset)
    EllesmereUI:ClearContentHeader()
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h = W:SectionHeader(parent, "GEARING OVERVIEW", y); y = y - h
    local specValues, specOrder = BuildSpecValues()
    _, h = W:Dropdown(parent, "Loot Specialization", y, specValues,
        function() return SelectedSpecID() end,
        function(v) Profile().selectedSpecID=v; EllesmereUI:RefreshPage() end,
        specOrder); y = y - h
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
            local card = Card(parent, y, 66 + #grouped[sourceKey] * 22)
            local name = Font(card, 12, 1, 1, 1, 1)
            name:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
            name:SetText(source.name)
            local chance = Font(card, 10, 0.05, 0.82, 0.62, 1)
            chance:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -11)
            chance:SetText(string.format("%.1f%%  •  %d %s", summary.chance * 100, summary.coreCost, L("Voidcore")))
            local pool = Font(card, 9, 0.55, 0.58, 0.64, 1)
            pool:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
            pool:SetText(EllesmereUI.Lf("%1$d desired • %2$d of %3$d remaining", summary.desired, summary.remaining, summary.total))
            local offset = -48
            for _, goal in ipairs(grouped[sourceKey]) do
                local color = ns.PRIORITY_COLORS[goal.priority] or { 1, 1, 1 }
                local line = Font(card, 10, color[1], color[2], color[3], 1)
                line:SetPoint("TOPLEFT", card, "TOPLEFT", 18, offset)
                line:SetPoint("RIGHT", card, "RIGHT", -12, 0)
                line:SetJustifyH("LEFT")
                local target = goal.minItemLevel and ("  |cff777d88(" .. goal.minItemLevel .. "+)|r") or ""
                local done = goal.state == "archived" and ("  |cff55dd88✓ " .. L("Obtained") .. "|r") or ""
                line:SetText((goal.itemLink or goal.itemName or goal.itemID) .. target .. done)
                offset = offset - 22
            end
            y = y - card:GetHeight() - 6
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
        { type="toggle", text="Automatically Archive Items",
          getValue=function() return Profile().autoArchive end,
          setValue=function(v) Profile().autoArchive=v; if v then ns.QueueInventoryScan() end end }); y = y - h
    _, h = W:Toggle(parent, "Show Archived Goals", y,
        function() return Profile().showArchived end,
        function(v) Profile().showArchived=v; EllesmereUI:RefreshPage() end,
        "Shows completed goals in the gearing overview."); y = y - h
    _, h = W:SectionHeader(parent, "VOIDCORE POOLS", y); y = y - h
    _, h = W:WideButton(parent, "Rescan Voidcore Pools", y, function()
        print("|cff0cd29fEllesmereUI Loot Tracker|r: " .. L("Scanning Voidcore pools..."))
        ns.RescanVoidcorePools(function()
            print("|cff0cd29fEllesmereUI Loot Tracker|r: " .. L("Voidcore pool scan complete."))
            EllesmereUI:RefreshPage()
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

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local refreshQueued
    ns.RegisterCallback(function()
        if refreshQueued then return end
        refreshQueued = true
        C_Timer.After(0, function()
            refreshQueued = nil
            if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then EllesmereUI:RefreshPage() end
        end)
    end)
    EllesmereUI:RegisterModule(ADDON_NAME, {
        title = "Loot Tracker",
        description = "Plan dungeon and raid upgrades, track acquired gear, and calculate Voidcore odds.",
        pages = { PAGE_OVERVIEW, PAGE_DUNGEONS, PAGE_RAIDS, PAGE_SETTINGS },
        buildPage = function(pageName, parent, yOffset)
            if pageName == PAGE_OVERVIEW then return BuildOverview(parent, yOffset) end
            if pageName == PAGE_DUNGEONS then return BuildCatalogPage(parent, yOffset, "dungeon") end
            if pageName == PAGE_RAIDS then return BuildCatalogPage(parent, yOffset, "raid") end
            return BuildSettings(parent, yOffset)
        end,
        onReset = function()
            local db = _G._EULT_DB and _G._EULT_DB()
            if db and db.ResetProfile then db:ResetProfile() end
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
