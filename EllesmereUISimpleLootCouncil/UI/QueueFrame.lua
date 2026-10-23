if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end


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
local FitEmpty
local bagScroll, bagContent
local bagRows, bagHeaders = {}, {}
local bagCache, bagCacheAt


local ownScan

local ROW_HEIGHT = 32
local BAG_ROW_HEIGHT = 28
local BAG_HEADER_HEIGHT = 24





local function GetRow(index)
    local row = rows[index]
    if row then return row end

    row = L.Row(itemContent, 0, L.WidthOf(itemContent), -(index - 1) * ROW_HEIGHT,
        ROW_HEIGHT)

    P.Point(row, "TOPRIGHT", itemContent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
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
                eligible = entry.eligible, owed = entry.owed, owedTo = entry.owedTo,
                kept = entry.kept, won = entry.won }
        end
    end
    return items
end

function QueueFrame:RefreshBags()
    if not bagPanel or not bagPanel:IsVisible() then return end

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
                    owed = entry.owed, owedTo = entry.owedTo, kept = entry.kept,
                    won = entry.won,
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
    bagHint:SetText(not running and (addon.Session:MayStage() and T["Click an item to queue it"]
            or T["Only the Loot Master and council can queue"])
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
            local name, _, quality = C_Item.GetItemInfo(entry.link)
            local ilvl = addon.Gear:ItemLevel(entry.link)
            row.icon:SetQualityBorder(quality)



            row.label:SetText((entry.eligible ~= false and not entry.owed and not entry.won)
                and (name or entry.link or "?")
                or S.Colorize(S.color.textFaint, name or entry.link or "?"))
            row.note:SetTextColor(S.Unpack(entry.owed and not entry.kept
                and S.color.warn or S.color.accentPale))
            row.note:SetText(entry.kept and T["(Awarded to you)"]
                or entry.owed and (entry.owedTo and addon.Locale.Format(T["(Owed to %s)"],
                        Ambiguate(entry.owedTo, "short"))
                    or T["(Owed)"])
                or entry.won and T["(Awarded to you)"]
                or "")
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
                        or why == "council" and T["could not queue %s - only the Loot Master and council members can queue items."]
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
        if FitEmpty then FitEmpty() end
    else
        bagEmpty:Hide()
    end



    bagScroll:SetContentHeight(y)
end







local function PaintQueue()
    if not frame or not frame:IsVisible() then return end

    local items = addon.Session:GetItems()
    local running = addon.Session:IsRunning()
    local shown = #items

    for i = 1, shown do
        local item = items[i]
        local row = GetRow(i)

        row.icon:SetItem(item.link)
        local name, _, quality = C_Item.GetItemInfo(item.link)
        local ilvl = addon.Gear:ItemLevel(item.link)
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
    local mayStage = addon.Session:MayStage()
    local ready = not running and #items > 0 and #names > 0

    startButton:SetLabel(running and T["Run in progress"] or T["Start run"])


    local blocked = addon.Restrictions:IsBlocked()
    local startReason
    if running then
        startReason = S.RequiresSentence(T["The current run must finish first."])
    elseif blocked then
        startReason = addon.Restrictions:GetBlockReason() or T["unavailable"]
    elseif not mine then
        startReason = S.RequiresSentence(T["Requires you to be the Loot Master."])
    elseif #items == 0 then
        startReason = S.RequiresSentence(T["Requires at least one item in the queue."])
    elseif #names == 0 then
        startReason = S.RequiresSentence(T["Requires at least one council member who is here."])
    end
    startButton:SetDisabledReason(startReason)
    startButton:SetEnabled(mine and ready and not blocked)

    clearButton:SetDisabledReason(running
        and S.RequiresSentence(T["The current run must finish first."])
        or nil)
    clearButton:SetEnabled(not running)


    fromBags:SetDisabledReason(not running and not mayStage
        and S.RequiresSentence(T["Requires you to be the Loot Master or on the council."])
        or nil)
    fromBags:SetEnabled(running or mayStage)
end


function QueueFrame:Refresh()
    if not frame then return end
    addon.Callbacks:Invalidate("queue")
    addon.Callbacks:Invalidate("queueBags")
    addon.Callbacks:PaintNow("queue")
    addon.Callbacks:PaintNow("queueBags")
end


function QueueFrame:AddAllFromBags()
    local me = addon.Player:GetFullName("player")

    if not addon.Session:MayStage() then
        addon.Chat.Print(T["nothing added from bags - only the Loot Master and council members can queue items."])
        return 0
    end


    local picks, skipped, won = addon.BagShare.FreeToStage(
        addon.Storage:GetTradeableItems(), me)
    local links, bosses, encounterIDs = {}, {}, {}
    for i, entry in ipairs(picks) do
        links[i] = entry.link

        bosses[i], encounterIDs[i] = addon.Encounter:ForTradeableItem(entry.secondsLeft)
    end


    local added = #addon.Session:AddItems(links, me, bosses, encounterIDs)
    addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
        one = "added %d item from bags",
        other = "added %d items from bags",
    }, added, added))
    if skipped > 0 then
        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "skipped %d copy already owed to a winner in Loot to Trade - click it in the bags panel to queue it anyway.",
            other = "skipped %d copies already owed to winners in Loot to Trade - click one in the bags panel to queue it anyway.",
        }, skipped, skipped))
    end
    if won > 0 then
        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "skipped %d item awarded to you - click it in the bags panel to queue it anyway.",
            other = "skipped %d items awarded to you - click one in the bags panel to queue it anyway.",
        }, won, won))
    end
    QueueFrame:Refresh()
    return added
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


local function Opened()
    addon.Storage:ShareLiveScan(function()
        bagCache, bagCacheAt, ownScan = nil, nil, nil


        if not addon.PlayerIsMasterLooter() or addon.Config:CouncilBagsShared() then
            addon.BagShare:Request()
        end

        StartWatch()
        QueueFrame:Refresh()
    end)
end


local function Build(host)
    frame = host.pane
    local inset = host.railInset




    bagPanel = CreateFrame("Frame", nil, frame)
    P.Point(bagPanel, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    P.Point(bagPanel, "BOTTOMLEFT", host.window, "BOTTOMLEFT", S.size.PAD, host.railBottom)
    P.Size(bagPanel, host.railWidth, nil)
    bagPanel.slcWidth = host.railWidth
    S.Panel(bagPanel, S.color.rail, nil, S.radius.MD, S.color.rule)

    local bagCursor = L.Cursor(bagPanel, { x = inset, top = inset })
    bagTitle = bagCursor:Add(L.Section, T["Your bags"], { font = S.fontHeading })


    bagHint = bagCursor:Add(L.Paragraph, T["Click an item to queue it"], S.fontSmall)
    bagCursor:Gap()

    bagHost = bagCursor:Add(function(parent, x, width, y)
        local holder = CreateFrame("Frame", nil, parent)
        L.Above(holder, parent)
        P.Point(holder, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(holder, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
        return holder, 0
    end)



    bagScroll = S.ScrollRegion(bagHost, BAG_ROW_HEIGHT)
    bagScroll:SetAllPoints(bagHost)
    bagContent = bagScroll.Content

    bagEmpty = S.EmptyState(bagHost, T["No tradeable items"],
        T["Nothing in your bags is inside its trade window."],
        host.railWidth - inset * 2)


    P.Point(bagEmpty, "TOPLEFT", bagHost, "TOPLEFT", 0, 0)
    P.Point(bagEmpty, "BOTTOMRIGHT", bagHost, "BOTTOMRIGHT", 0, 0)
    FitEmpty = function()
        local h, w = bagEmpty:GetHeight(), bagEmpty:GetWidth()
        if type(h) ~= "number" or h <= 0 or type(w) ~= "number" or w <= 0 then return end
        local body = bagEmpty.Body
        P.Size(body, math.min(250, w - 44), 0)
        local text = 18 + 6 + math.ceil(body:GetStringHeight())
        local withBox = text + 38 + 9
        local showBox = h >= withBox + 16
        local total = showBox and withBox or text
        local top = math.max(0, (h - total) / 2)
        bagEmpty.Box:SetShown(showBox)
        bagEmpty.Box:ClearAllPoints()
        bagEmpty.Title:ClearAllPoints()
        if showBox then
            P.Point(bagEmpty.Box, "TOP", bagEmpty, "TOP", 0, -top)
            P.Point(bagEmpty.Title, "TOP", bagEmpty.Box, "BOTTOM", 0, -9)
        else
            P.Point(bagEmpty.Title, "TOP", bagEmpty, "TOP", 0, -top)
        end
    end
    bagEmpty:SetScript("OnSizeChanged", FitEmpty)
    P.AfterLayout(FitEmpty)


    local main = CreateFrame("Frame", nil, frame)
    P.Point(main, "TOPLEFT", bagPanel, "TOPRIGHT", host.railGap, 0)
    P.Point(main, "BOTTOMLEFT", bagPanel, "BOTTOMRIGHT", host.railGap, 0)
    P.Point(main, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    P.Point(main, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    main.slcWidth = host.mainWidth

    local cursor = L.Cursor(main)

    local function StatusLine(parent, x, width, y)
        local fs = S.Label(parent, S.fontSmall, "LEFT")
        P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(fs, "TOPRIGHT", parent, "TOPRIGHT", 0, y)
        return fs, 16
    end

    lootMasterText = cursor:Add(StatusLine)
    councilText = cursor:Add(StatusLine)

    cursor:Gap(S.size.SECTION)
    local queuedHeading = cursor:Add(L.Section, T["Queued items"])
    queuedHeading:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, select(5, queuedHeading:GetPoint(1)))

    itemHost = cursor:Add(function(parent, x, width, y)
        local holder = CreateFrame("Frame", nil, parent)
        L.Above(holder, parent)
        P.Point(holder, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(holder, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

        holder.slcWidth = width
        return holder, 0
    end)

    itemScroll = S.ScrollRegion(itemHost, ROW_HEIGHT)
    itemScroll:SetAllPoints(itemHost)
    itemContent = itemScroll.Content
    itemContent.slcWidth = L.WidthOf(itemHost) - 9

    emptyText = S.Label(itemHost, S.fontHint, "LEFT", "wrap")
    P.Point(emptyText, "TOPLEFT", itemHost, "TOPLEFT", S.size.SECTION, -S.size.SECTION)
    P.Point(emptyText, "TOPRIGHT", itemHost, "TOPRIGHT", -S.size.ROW_PAD, -S.size.SECTION)


    fromBags = S.Button(host.footer, T["Add all items from bags"], {
        width = 255, labelPad = S.size.BTN_PAD_FOOTER,
    })
    host.AddButton(fromBags)
    clearButton = S.Button(host.footer, T["Clear"], {
        width = 105, labelPad = S.size.BTN_PAD_FOOTER,
    })
    host.AddButton(clearButton)
    startButton = S.Button(host.footer, T["Start run"], {
        width = 150, primary = true, labelPad = S.size.BTN_PAD_FOOTER,
    })
    host.AddButton(startButton, true, true)

    startButton:SetScript("OnClick", function()
        if not addon.PlayerIsMasterLooter() then return end
        if addon.Session:Start() then
            QueueFrame:Refresh()
        end
    end)


    fromBags:SetScript("OnClick", function()


        if addon.Session:IsRunning() and not addon.PlayerIsMasterLooter() then
            addon.Chat.Print(T["nothing added from bags - a run is in progress, and only the Loot Master can add to it."])
            return
        end
        QueueFrame:AddAllFromBags()
    end)

    clearButton:SetScript("OnClick", function()
        if addon.Session:IsRunning() then return end
        addon.Session:Clear()
        QueueFrame:Refresh()
    end)

    local function Visible() return frame:IsVisible() end

    QueueFrame.view = addon.Callbacks:RegisterView("queue", {
        shown = Visible,
        paint = PaintQueue,
    })
    QueueFrame.bagsView = addon.Callbacks:RegisterView("queueBags", {
        shown = Visible,
        paint = function() QueueFrame:RefreshBags() end,
    })


    bagWatcher = CreateFrame("Frame")
    bagWatcher:SetScript("OnEvent", function()
        bagCache, bagCacheAt, ownScan = nil, nil, nil
        addon.Callbacks:Invalidate("queueBags")
    end)
    frame:SetScript("OnShow", Opened)
    frame:SetScript("OnHide", StopWatch)

    addon.Log:D("UI", "queue frame built")
end



function QueueFrame:Attach(host)
    if frame or not host then return end
    Build(host)
end

function QueueFrame:Init()
    S = addon.Style
    L, P = addon.Layout, addon.Pixel

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

        addon.Callbacks:Invalidate("queueBags")
        if frame and frame:IsVisible() then addon.BagShare:AskMissing() end
    end
    addon.Callbacks:Register("CouncilChanged", HoldersChanged)
    addon.Callbacks:Register("LootMasterChanged", HoldersChanged)
    addon.Callbacks:Register("RosterChanged", HeaderChanged)
    addon.Restrictions:OnChange(HeaderChanged)

    addon.Log:I("UI", "queue frame ready")
end

function QueueFrame:Toggle()
    local council = UI.MLFrame
    if council:QueueShown() then
        council:Close()
        return
    end
    if not council:ShowQueue() then
        addon.Chat.Print(T["only the Loot Master can use the loot queue."])
    end
end