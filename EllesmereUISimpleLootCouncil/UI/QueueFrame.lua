if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local QueueFrame = {}
UI.QueueFrame = QueueFrame

local S, L, P
local frame, itemHost, itemScroll, itemContent
local councilText, lootMasterText, startButton, emptyText
local clearButton, fromBags
local rows = {}

local bagPanel, bagHost, bagEmpty, bagTitle, bagHint
local bagScroll, bagContent
local bagRows, bagHeaders = {}, {}
local bagCache, bagCacheAt


local ownScan
local autoOpenPanel, autoOpenBox, autoPopulateBox

local ROW_HEIGHT = 32
local BAG_ROW_HEIGHT = 28
local BAG_HEADER_HEIGHT = 24





local function GetRow(index)
    local row = rows[index]
    if row then return row end

    row = L.Row(itemContent, 0, L.WidthOf(itemContent), -(index - 1) * ROW_HEIGHT,
        ROW_HEIGHT)
    row:SetStripe(index)


    row.remove = S.Button(row, "", {
        width = S.size.BTN_W_SM, compact = true, glyph = "close",
    })
    P.Point(row.remove, "RIGHT", row, "RIGHT", -2, 0)
    row:AdoptHover(row.remove)


    row.ordinal = S.Label(row, S.fontNum, "RIGHT")
    row.ordinal:SetTextColor(S.Unpack(S.color.textMuted))
    P.Point(row.ordinal, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
    P.Size(row.ordinal, 22, ROW_HEIGHT)

    row.icon = S.ItemIcon(row, 28)
    P.Point(row.icon, "LEFT", row.ordinal, "RIGHT", S.size.ITEM_GAP, 0)
    row:AdoptHover(row.icon)

    row.ilvl = S.Label(row, S.fontNum, "RIGHT")
    row.ilvl:SetTextColor(S.Unpack(S.color.textMuted))
    P.Point(row.ilvl, "RIGHT", row.remove, "LEFT", -S.size.GAP, 0)
    P.Size(row.ilvl, 38, ROW_HEIGHT)



    row.label = S.Label(row, S.fontBody, "LEFT")
    P.Point(row.label, "LEFT", row.icon, "RIGHT", S.size.GAP, 0)
    P.Point(row.label, "RIGHT", row.ilvl, "LEFT", -S.size.GAP, 0)

    rows[index] = row
    return row
end










local function GetBagRow(index)
    local row = bagRows[index]
    if row then return row end

    row = CreateFrame("Button", nil, bagContent)
    P.Size(row, nil, BAG_ROW_HEIGHT)



    row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.stripe:SetAllPoints()
    P.Crisp(row.stripe)

    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(S.Unpack(S.color.rowHover))
    P.Crisp(hover)
    hover:Hide()

    row:SetScript("OnEnter", function(self)
        hover:Show()
        if self.link then
            S.SideTooltip(self, bagPanel)
            S.SetTooltipItem(self.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)

    row.icon = S.ItemIcon(row, S.size.ICON_SM)
    P.Point(row.icon, "LEFT", row, "LEFT", 2, 0)


    row.icon:EnableMouse(false)

    row.ilvl = S.Label(row, S.fontNum, "RIGHT")
    row.ilvl:SetTextColor(S.Unpack(S.color.textMuted))
    P.Point(row.ilvl, "RIGHT", row, "RIGHT", -4, 0)
    P.Size(row.ilvl, 38, BAG_ROW_HEIGHT)


    row.note = S.Label(row, S.fontSmall, "RIGHT")
    row.note:SetTextColor(S.Unpack(S.color.warn))
    P.Point(row.note, "RIGHT", row.ilvl, "LEFT", -S.size.ITEM_GAP, 0)


    row.label = S.Label(row, S.fontBody, "LEFT")
    P.Point(row.label, "LEFT", row.icon, "RIGHT", S.size.ITEM_GAP, 0)
    P.Point(row.label, "RIGHT", row.note, "LEFT", -S.size.ITEM_GAP, 0)

    bagRows[index] = row
    return row
end


local function GetBagHeader(index)
    local header = bagHeaders[index]
    if header then return header end

    header = CreateFrame("Frame", nil, bagContent)
    P.Size(header, nil, BAG_HEADER_HEIGHT)

    header.label = S.Label(header, S.fontSmall, "LEFT")
    P.Point(header.label, "BOTTOMLEFT", header, "BOTTOMLEFT", 2, 5)

    header.note = S.Label(header, S.fontHint, "RIGHT")
    header.note:SetTextColor(S.Unpack(S.color.textFaint))
    P.Point(header.note, "BOTTOMRIGHT", header, "BOTTOMRIGHT", -4, 5)
    P.Point(header.note, "LEFT", header.label, "RIGHT", S.size.GAP, 0)

    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(S.Unpack(S.color.border))
    P.Point(rule, "BOTTOMLEFT", header, "BOTTOMLEFT", 0, 1)
    P.Point(rule, "BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 1)
    P.Size(rule, nil, 1)
    P.Crisp(rule)

    bagHeaders[index] = header
    return header
end

local function PlayerLabel(fullName)
    if not fullName then return T["unknown"] end
    local record = addon.Player:Get(fullName)
    local colour = record and record.classFile
        and C_ClassColor.GetClassColor(record.classFile)
    local short = Ambiguate(fullName, "short")
    if colour then
        return S.Colorize({ colour.r, colour.g, colour.b }, short)
    end
    return S.Colorize(S.color.text, short)
end


local function OwnItems()
    if not ownScan then
        ownScan = { items = addon.Storage:GetTradeableItems(), at = GetTime() }
    end
    local elapsed = GetTime() - ownScan.at
    local items = {}
    for _, entry in ipairs(ownScan.items) do
        local remaining = entry.secondsLeft and entry.secondsLeft - elapsed
        if not remaining or remaining > 0 then
            items[#items + 1] = { link = entry.link, secondsLeft = remaining,
                eligible = entry.eligible, owed = entry.owed, owedTo = entry.owedTo }
        end
    end
    return items
end

function QueueFrame:RefreshBags()
    if not bagPanel or not bagPanel:IsShown() then return end

    if not bagCache then
        bagCache = addon.BagShare:Holders(OwnItems)
        bagCacheAt = GetTime()
    end
    local elapsed = GetTime() - bagCacheAt



    local sections = {}
    for index, holder in ipairs(bagCache) do
        local available = {}
        for _, entry in ipairs(holder.items) do
            local remaining = entry.secondsLeft and entry.secondsLeft - elapsed
            if not remaining or remaining > 0 then
                available[#available + 1] = {
                    link = entry.link, secondsLeft = remaining, eligible = entry.eligible,
                    owed = entry.owed, owedTo = entry.owedTo,
                }
            end
        end

        local items = addon.BagShare.Unstaged(available, holder.owner)
        if index == 1 or #items > 0 then
            sections[#sections + 1] = {
                owner = holder.owner, mine = holder.mine,
                lootMaster = holder.lootMaster, items = items,
            }
        end
    end

    local first = sections[1]
    local mine = first and first.mine
    local grouped = #sections > 1


    local ownerLabel
    if grouped then
        ownerLabel = T["Council bags"]
    elseif mine then
        ownerLabel = T["Your bags"]
    elseif first and first.owner then
        ownerLabel = addon.Locale.Format(T["%s's bags"], Ambiguate(first.owner, "short"))
    else
        ownerLabel = T["Loot Master's bags"]
    end
    if grouped or mine or not first or not first.owner then
        ownerLabel = addon.Locale.Upper(ownerLabel)
    end
    bagTitle.Text:SetText(ownerLabel)



    local running = addon.Session:IsRunning()
    bagHint:SetText(not running and T["Click an item to queue it"]
        or mine and T["Click an item to add it to the run"]
        or T["Only the Loot Master can add mid-run"])



    local shown, headers, y = 0, 0, 0
    for _, section in ipairs(sections) do
        if grouped then
            headers = headers + 1
            local header = GetBagHeader(headers)
            header:ClearAllPoints()
            P.Point(header, "TOPLEFT", 0, -y)
            P.Point(header, "TOPRIGHT", 0, -y)
            header.label:SetText(section.mine and T["Your bags"]
                or addon.Locale.Format(T["%s's bags"], PlayerLabel(section.owner)))
            header.note:SetText(#section.items == 0 and T["nothing tradeable"]
                or section.lootMaster and T["Loot Master"] or "")
            header:Show()
            y = y + BAG_HEADER_HEIGHT
        end

        for position, entry in ipairs(section.items) do
            shown = shown + 1
            local row = GetBagRow(shown)
            row:ClearAllPoints()
            P.Point(row, "TOPLEFT", 0, -y)
            P.Point(row, "TOPRIGHT", 0, -y)
            row.stripe:SetColorTexture(S.Unpack(position % 2 == 0
                and S.color.rowEven or S.color.rowOdd))
            y = y + BAG_ROW_HEIGHT

            row.link = entry.link
            row.icon:SetItem(entry.link)
            local name, _, quality, ilvl = C_Item.GetItemInfo(entry.link)
            row.icon:SetQualityBorder(quality)



            row.label:SetText((entry.eligible ~= false and not entry.owed)
                and (name or entry.link or "?")
                or S.Colorize(S.color.textFaint, name or entry.link or "?"))
            row.note:SetText(not entry.owed and ""
                or entry.owedTo and addon.Locale.Format(T["owed to %s"],
                    Ambiguate(entry.owedTo, "short"))
                or T["owed"])
            row.ilvl:SetText(ilvl or "")

            local link, owner = entry.link, section.owner
            row:SetScript("OnClick", function()
                local index, why = addon.BagShare:AddToQueue(link, owner)
                if index and addon.Session:IsRunning() then


                    addon.Chat.Print(addon.Locale.Format(
                        T["added %s to the running run as session %d."], link, index))
                elseif not index then


                    local sentence = why == "active"
                        and T["could not queue %s - a run is in progress, and only the Loot Master can add to it."]
                        or why == "queued" and T["could not queue %s - every copy is already queued."]
                        or T["could not queue %s - it is no longer in the holder's bags with an active trade timer."]
                    addon.Chat.Print(addon.Locale.Format(sentence, link))
                end
                QueueFrame:Refresh()
            end)
            row:EnableMouse(true)
            row:Show()
        end
    end

    for i = shown + 1, #bagRows do bagRows[i]:Hide() end
    for i = headers + 1, #bagHeaders do bagHeaders[i]:Hide() end

    if shown == 0 then
        bagEmpty.Body:SetText(mine
            and T["Nothing in your bags is inside its trade window."]
            or T["Nothing shared yet. The Loot Master's list arrives when they pick something up."])
        bagEmpty:Show()
    else
        bagEmpty:Hide()
    end



    bagScroll:SetContentHeight(y)
end







local function PaintQueue()
    if not frame or not frame:IsShown() then return end

    local items = addon.Session:GetItems()
    local running = addon.Session:IsRunning()
    local shown = #items

    for i = 1, shown do
        local item = items[i]
        local row = GetRow(i)

        row.icon:SetItem(item.link)
        local name, _, quality, ilvl = C_Item.GetItemInfo(item.link)
        row.icon:SetQualityBorder(quality)

        row.ordinal:SetText(addon.Locale.Format(T["%d."], i))
        row.label:SetText(name or item.link or "?")
        row.ilvl:SetText(ilvl or "")
        if quality then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            if r then row.label:SetTextColor(r, g, b) end
        else
            row.label:SetTextColor(S.Unpack(S.color.text))
        end


        row.remove:SetDisabledReason(running
            and S.RequiresSentence(T["Items cannot be removed once the run has started."])
            or nil)
        row.remove:SetEnabled(not running)
        row.remove:SetScript("OnClick", function()
            addon.Session:RemoveQueued(i)
            QueueFrame:Refresh()
        end)
        row:Show()
    end

    for i = shown + 1, #rows do rows[i]:Hide() end


    emptyText:ClearAllPoints()


    local function PlaceEmpty(y)
        emptyText:SetPoint("TOPLEFT", itemHost, "TOPLEFT", 30, y)
        emptyText:SetPoint("TOPRIGHT", itemHost, "TOPRIGHT", -10, y)
    end

    if #items == 0 then
        PlaceEmpty(-20)
        emptyText:SetText(T["Nothing queued.\n\n|cff73716CShift-click items into /slc additem, or click something in the bags panel|r"])
        emptyText:Show()
    else
        PlaceEmpty(-20)
        emptyText:Hide()
    end

    itemScroll:SetContentHeight(shown * ROW_HEIGHT)



    local ml = addon.GetMasterLooter()
    if addon.IsLootDelegated() then
        lootMasterText:SetText(addon.Locale.Format(
            T["Loot Master: %s |cff73716C(delegated)|r"], PlayerLabel(ml)))
    else
        lootMasterText:SetText(addon.Locale.Format(T["Loot Master: %s"], PlayerLabel(ml)))
    end


    local names = {}
    for fullName in pairs(addon.Council:GetActive()) do
        names[#names + 1] = { full = fullName, short = Ambiguate(fullName, "short") }
    end
    table.sort(names, function(a, b) return a.short < b.short end)

    if #names == 0 then
        councilText:SetText(S.Colorize(S.color.bad,
            T["Council: nobody resolved yet - a run cannot start"]))
    else


        local labels = {}
        for _, name in ipairs(names) do labels[#labels + 1] = PlayerLabel(name.full) end
        councilText:SetText(addon.Locale.Format(T["Council, %d: %s"], #names,
            table.concat(labels, S.Colorize(S.color.textMuted, ", "))))
    end



    local mine = addon.PlayerIsMasterLooter()
    local mayRequest = not mine and addon.Config:StartRequestsAllowed()
    local ready = not running and #items > 0 and #names > 0

    if running then
        startButton:SetLabel(T["Run in progress"])
    elseif mayRequest then
        startButton:SetLabel(T["Request start"])
    else
        startButton:SetLabel(T["Start run"])
    end



    local footerWidth = fromBags:GetWidth() + clearButton:GetWidth()
        + startButton:GetWidth() + S.size.GAP * 2
    local windowWidth = math.max(600, footerWidth + S.size.PAD * 2)
    P.Size(frame, windowWidth, nil)
    frame.Content.slcWidth = windowWidth - S.size.PAD * 2
    itemHost.slcWidth = frame.Content.slcWidth
    itemContent.slcWidth = itemHost.slcWidth - 9
    frame:ClampTitle()


    local startReason
    if running then
        startReason = S.RequiresSentence(T["The current run must finish first."])
    elseif not mine and not mayRequest then
        startReason = S.RequiresSentence(T["Requires you to be the Loot Master."])
    elseif #items == 0 then
        startReason = S.RequiresSentence(T["Requires at least one item in the queue."])
    elseif #names == 0 then
        startReason = S.RequiresSentence(T["Requires at least one council member who is here."])
    end
    startButton:SetDisabledReason(startReason)
    startButton:SetEnabled((mine or mayRequest) and ready)

    clearButton:SetDisabledReason(running
        and S.RequiresSentence(T["The current run must finish first."])
        or nil)
    clearButton:SetEnabled(not running)
end


function QueueFrame:Refresh()
    if not frame then return end
    addon.Callbacks:Invalidate("queue")
    addon.Callbacks:Invalidate("queueBags")
    addon.Callbacks:PaintNow("queue")
    addon.Callbacks:PaintNow("queueBags")
end


function QueueFrame:AddAllFromBags(auto)
    local me = addon.Player:GetFullName("player")


    local picks, skipped = addon.BagShare.FreeToStage(
        addon.Storage:GetTradeableItems(), me)
    local links, bosses, encounterIDs = {}, {}, {}
    for i, entry in ipairs(picks) do
        links[i] = entry.link

        bosses[i], encounterIDs[i] = addon.Encounter:ForTradeableItem(entry.secondsLeft)
    end
    if auto and #links == 0 then return 0 end


    local added = #addon.Session:AddItems(links, me, bosses, encounterIDs)
    if not auto or added > 0 then
        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "added %d item from bags",
            other = "added %d items from bags",
        }, added, added))
    end
    if skipped > 0 and not auto then
        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "skipped %d copy already owed to a winner in Loot to Trade - click it in the bags panel to queue it anyway.",
            other = "skipped %d copies already owed to winners in Loot to Trade - click one in the bags panel to queue it anyway.",
        }, skipped, skipped))
    end
    QueueFrame:Refresh()
    return added
end


local killOpened
local function AutoAddFromBags()
    if not addon.db.autoAddBags or addon.Session:IsRunning() then return end
    QueueFrame:AddAllFromBags(true)
end






local bagWatcher, bagTicker

local function StartWatch()
    if bagTicker then return end
    bagWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
    bagTicker = C_Timer.NewTicker(15, function()
        addon.Callbacks:Invalidate("queueBags")
    end)
end

local function StopWatch()
    if not bagTicker then return end
    bagWatcher:UnregisterEvent("BAG_UPDATE_DELAYED")
    bagTicker:Cancel()
    bagTicker = nil
end


local function Build()
    frame = S.Window("SimpleLootCouncilQueueFrame", "queue", 600, 470, T["Loot queue"])
    frame:RestorePosition()


    local content = frame.Content
    local cursor = L.Cursor(content)

    local function StatusLine(parent, x, width, y)
        local fs = S.Label(parent, S.fontSmall, "LEFT")
        P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(fs, "TOPRIGHT", parent, "TOPRIGHT", 0, y)
        return fs, 16
    end

    lootMasterText = cursor:Add(StatusLine)
    councilText = cursor:Add(StatusLine)

    cursor:Gap(S.size.SECTION)
    cursor:Add(L.Section, T["Queued items"])

    local FOOTER = S.size.BTN_H + S.size.SECTION

    itemHost = cursor:Add(function(parent, x, width, y)
        local host = CreateFrame("Frame", nil, parent)
        L.Above(host, parent)
        P.Point(host, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(host, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, FOOTER)

        host.slcWidth = width
        return host, 0
    end)

    itemScroll = S.ScrollRegion(itemHost, ROW_HEIGHT)
    itemScroll:SetAllPoints(itemHost)
    itemContent = itemScroll.Content
    itemContent.slcWidth = L.WidthOf(itemHost) - 9

    emptyText = S.Label(itemHost, S.fontHint, "LEFT", "wrap")
    P.Point(emptyText, "TOPLEFT", itemHost, "TOPLEFT", S.size.SECTION, -S.size.SECTION)
    P.Point(emptyText, "TOPRIGHT", itemHost, "TOPRIGHT", -S.size.ROW_PAD, -S.size.SECTION)

    startButton = S.Button(content, T["Start run"], { width = 150, primary = true })
    P.Point(startButton, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    startButton:SetScript("OnClick", function()
        if addon.PlayerIsMasterLooter() then
            if addon.Session:Start() then
                QueueFrame:Refresh()
            end
            return
        end



        if not addon.Config:StartRequestsAllowed() then return end
        local proposal = {}
        for _, item in ipairs(addon.Session:GetItems()) do
            if item.link and not item.simulated then
                proposal[#proposal + 1] = { l = item.link, o = item.owner, b = item.boss,
                    e = item.encounterID }
            end
        end
        addon.Comms:Send("start_request", { items = proposal })
        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "asking the Loot Master to start the run with %d proposed item...",
            other = "asking the Loot Master to start the run with %d proposed items...",
        }, #proposal, #proposal))
    end)


    fromBags = S.Button(content, T["Add all items from bags"], { width = 255 })
    P.Point(fromBags, "BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    fromBags:SetScript("OnClick", function()


        if addon.Session:IsRunning() and not addon.PlayerIsMasterLooter() then
            addon.Chat.Print(T["nothing added from bags - a run is in progress, and only the Loot Master can add to it."])
            return
        end
        QueueFrame:AddAllFromBags(false)
    end)

    clearButton = S.Button(content, T["Clear"], { width = 105 })
    P.Point(clearButton, "LEFT", fromBags, "RIGHT", S.size.GAP, 0)
    clearButton:SetScript("OnClick", function()
        if addon.Session:IsRunning() then return end
        addon.Session:Clear()
        QueueFrame:Refresh()
    end)



    bagPanel = CreateFrame("Frame", nil, frame)
    P.Point(bagPanel, "TOPRIGHT", frame, "TOPLEFT", -S.size.ITEM_GAP, 0)
    P.Size(bagPanel, 280, 470)


    S.CanvasFill(bagPanel, S.color.canvas, 0.96)
    S.RoundBorder(bagPanel, S.color.border, "OVERLAY")


    local bagCursor = L.Cursor(bagPanel, { x = S.size.PAD, top = S.size.PAD })
    bagTitle = bagCursor:Add(L.Section, T["Your bags"], { font = S.fontHeading })

    bagHint = bagCursor:Add(L.Paragraph, T["Click an item to queue it"], S.fontSmall)
    bagCursor:Gap()

    bagHost = bagCursor:Add(function(parent, x, width, y)
        local host = CreateFrame("Frame", nil, parent)
        L.Above(host, parent)
        P.Point(host, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(host, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -S.size.PAD, S.size.PAD)
        return host, 0
    end)


    bagScroll = S.ScrollRegion(bagHost, BAG_ROW_HEIGHT)
    bagScroll:SetAllPoints(bagHost)
    bagContent = bagScroll.Content

    bagEmpty = S.EmptyState(bagHost, T["No tradeable items"],
        T["Nothing in your bags is inside its trade window."],
        L.WidthOf(bagPanel) - S.size.PAD * 2)
    P.Point(bagEmpty, "TOPLEFT", 0, 0)
    P.Point(bagEmpty, "TOPRIGHT", 0, 0)


    autoOpenPanel = CreateFrame("Frame", nil, frame)
    P.Point(autoOpenPanel, "BOTTOMLEFT", frame, "TOPLEFT", 0, S.size.ITEM_GAP)
    P.Point(autoOpenPanel, "BOTTOMRIGHT", frame, "TOPRIGHT", 0, S.size.ITEM_GAP)
    S.CanvasFill(autoOpenPanel, S.color.canvas, 0.96)
    S.RoundBorder(autoOpenPanel, S.color.border, "OVERLAY")
    local autoCursor = L.Cursor(autoOpenPanel, { x = S.size.PAD, top = S.size.PAD,
        width = L.WidthOf(frame) - S.size.PAD * 2 })
    autoCursor:Add(L.Section, T["Auto open"], { font = S.fontHeading })


    local function QuestionRow(text, onToggle)
        local row = autoCursor:Add(function(parent, x, width, y)
            local host = CreateFrame("Frame", nil, parent)
            P.Point(host, "TOPLEFT", parent, "TOPLEFT", x, y)
            P.Size(host, width, S.size.CTRL_H)
            local question = S.Label(host, S.fontBody, "LEFT", "wrap")
            question:SetWidth(P.Snap(width - S.size.CTRL_H - S.size.GAP))
            P.Point(question, "LEFT", host, "LEFT", 0, 0)
            question:SetText(text)
            local h = question:GetStringHeight()
            if type(h) ~= "number" or (issecretvalue and issecretvalue(h)) then h = 0 end
            local height = math.max(S.size.CTRL_H, math.ceil(h))
            P.Size(host, width, height)
            return host, height
        end)
        local box = S.Checkbox(autoOpenPanel, nil, onToggle)
        P.Point(box, "RIGHT", row, "RIGHT", 0, 0)
        return box
    end
    autoOpenBox = QuestionRow(T["Disable automatically opening the loot queue on boss kill?"], function(on)
        if not on then return end
        addon.db.autoOpenQueue = false
        addon.Log:I("UI", "auto-open loot queue switched off from the queue window")
        addon.Callbacks:Fire("AutoOpenQueueChanged")
    end)
    autoCursor:Gap()

    autoPopulateBox = QuestionRow(T["Auto populate loot queue?"], function(on)
        addon.db.autoAddBags = on
        addon.Log:I("UI", "auto-populate loot queue", on and "on" or "off", "from the queue window")
        addon.Callbacks:Fire("AutoAddBagsChanged")
        if on then
            killOpened = true
            AutoAddFromBags()
        end
    end)
    P.Size(autoOpenPanel, nil, autoCursor:Height(S.size.PAD))
    autoOpenPanel:Hide()

    QueueFrame.view = addon.Callbacks:RegisterView("queue", {
        frame = frame,
        paint = PaintQueue,
    })
    QueueFrame.bagsView = addon.Callbacks:RegisterView("queueBags", {
        frame = frame,
        paint = function() QueueFrame:RefreshBags() end,
    })


    bagWatcher = CreateFrame("Frame")
    bagWatcher:SetScript("OnEvent", function()
        bagCache, bagCacheAt, ownScan = nil, nil, nil
        addon.Callbacks:Invalidate("queueBags")
        if killOpened and frame:IsShown() then AutoAddFromBags() end
    end)
    frame:HookScript("OnShow", StartWatch)
    frame:HookScript("OnHide", function()
        killOpened = false
        StopWatch()
    end)

    addon.Log:D("UI", "queue frame built")
end



local building
local function WhenBuilt(fn)
    if frame then
        fn()
    elseif not building then
        building = true
        S.BuildOnDriver(function()
            building = false
            Build()
            fn()
        end)
    end
end

function QueueFrame:Init()
    S = addon.Style
    L, P = addon.Layout, addon.Pixel


    addon.Callbacks:Register("AutoOpenQueueChanged", function()
        if autoOpenPanel and not addon.db.autoOpenQueue then autoOpenPanel:Hide() end
    end)
    addon.Callbacks:Register("AutoAddBagsChanged", function()
        if autoPopulateBox then
            autoPopulateBox:SetChecked(addon.db.autoAddBags and true or false)
        end
    end)

    local function QueueChanged()
        addon.Callbacks:Invalidate("queue")

        addon.Callbacks:Invalidate("queueBags")
    end
    local function BagsChanged()
        bagCache, bagCacheAt, ownScan = nil, nil, nil
        addon.Callbacks:Invalidate("queueBags")
    end

    local function SharedChanged()
        bagCache, bagCacheAt = nil, nil
        addon.Callbacks:Invalidate("queueBags")
    end



    addon.Callbacks:Register("SessionChanged", function(_, kind)
        if kind == nil or kind == "item" or kind == "run" then QueueChanged() end
    end)
    addon.Callbacks:Register("RunStarted", function()
        BagsChanged()
        QueueChanged()
    end)
    addon.Callbacks:Register("RunEnded", function()
        BagsChanged()
        QueueChanged()
    end)
    addon.Callbacks:Register("BagShareChanged", SharedChanged)
    addon.Callbacks:Register("StorageChanged", BagsChanged)

    local function HeaderChanged() addon.Callbacks:Invalidate("queue") end

    local function HoldersChanged()
        HeaderChanged()
        if frame and frame:IsShown() then addon.BagShare:AskMissing() end
    end
    addon.Callbacks:Register("CouncilChanged", HoldersChanged)
    addon.Callbacks:Register("LootMasterChanged", HoldersChanged)
    addon.Callbacks:Register("RosterChanged", HeaderChanged)


    addon.Callbacks:Register("EncounterEnded", function(entry)
        if not (entry and entry.success and addon.db.autoOpenQueue) then return end
        if not IsInGroup() or not addon.PlayerIsMasterLooter() or not addon.Loot.handling then return end
        if frame and frame:IsShown() then return end
        addon.Log:I("UI", "boss kill - opening the loot queue", tostring(entry.name))
        WhenBuilt(function()
            if frame:IsShown() then return end
            QueueFrame:Toggle()
            autoOpenBox:SetChecked(false)
            autoPopulateBox:SetChecked(addon.db.autoAddBags and true or false)
            autoOpenPanel:Show()

            killOpened = true
        end)
    end)

    addon.Log:I("UI", "queue frame ready")
end

function QueueFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end

    WhenBuilt(function() addon.Storage:ShareLiveScan(function()

        autoOpenPanel:Hide()
        killOpened = false
        bagCache, bagCacheAt, ownScan = nil, nil, nil

        if not addon.PlayerIsMasterLooter() or addon.Config:CouncilBagsShared() then
            addon.BagShare:Request()
        end

        addon.Callbacks:Invalidate("queue")
        addon.Callbacks:Invalidate("queueBags")
        frame:Show()
        AutoAddFromBags()
    end) end)
end