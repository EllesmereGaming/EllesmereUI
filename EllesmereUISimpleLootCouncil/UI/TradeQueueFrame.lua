if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end





SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local TradeQueueFrame = {}
UI.TradeQueueFrame = TradeQueueFrame

local S, L, P
local frame, host, heading, othersHeading, empty
local rows = {}
local rowSet = {}
local rangeTicker, clockTicker
local visibleGroups

local clockRows = {}



local WINDOW_W = 440



local ITEM_INDENT = 12



local GROUP_GAP = 11



local URGENT_BELOW = 15 * 60




local UNTRADEABLE_WHY = addon.Locale.Texts{
    equipped = T["It was equipped, which ends its trade window."],
    bound = T["It is still in your bags, but its trade window has ended."],
    left = T["It left your bags without a trade to %s - sold, destroyed or traded to someone else."],
    missing = T["It was not in your bags when it was awarded to %s."],
    wrong = T["It was awarded to %s, but the trade handed it to %s."],
}


local OTHERS_WHY = addon.Locale.Texts{
    equipped = T["%s equipped it, which ends its trade window."],
    bound = T["It is still in %s's bags, but its trade window has ended."],
    left = T["It left %s's bags without a trade to %s."],
    missing = T["It was not in %s's bags when it was awarded to %s."],
    wrong = T["It was awarded to %s, but %s traded it to %s."],
}

local function OthersWhy(record)
    local Format = addon.Locale.Format
    local holder = Ambiguate(record.holder or "?", "short")
    local winner = Ambiguate(record.winner or "?", "short")
    local why = record.untradeable
    if why == "wrong" then
        return Format(OTHERS_WHY.wrong, winner, holder,
            Ambiguate(record.untradeableTo or "?", "short"))
    elseif why == "equipped" or why == "bound" then
        return Format(OTHERS_WHY[why], holder)
    end
    return Format(OTHERS_WHY[why] or OTHERS_WHY.left, holder, winner)
end



local SESSION_START = time()


local function Section(title)
    return S.Colorize(S.color.accent, addon.Locale.SectionTitle(title))
end

local function TooltipText(row)
    if row.kind == "item" then
        local entry = row.entry
        local why = entry and entry.untradeable
        if not why then return nil end
        local isML = addon.PlayerIsMasterLooter()
        return Section(T["Loot no longer tradeable"]) .. "\n"
            .. addon.Locale.Format(UNTRADEABLE_WHY[why] or UNTRADEABLE_WHY.left,
                Ambiguate(row.recipient or "?", "short"),
                Ambiguate(entry.untradeableTo or "?", "short")) .. "\n"
            .. (isML and T["Re-award it, or undo the award, to clear it."]
                or T["The Loot Master has been told. This clears when they re-award or undo it."])
            .. "\n\n" .. Section(T["Actions"]) .. "\n"
            .. (isML and T["Right-click: undo award"] or T["Right-click: stop tracking"])
    elseif row.kind == "othersItem" then
        if not row.untradeable or not row.record then return nil end
        return Section(T["Loot no longer tradeable"]) .. "\n"
            .. OthersWhy(row.record) .. "\n"
            .. T["Re-award it, or undo the award, to clear it."]
            .. "\n\n" .. Section(T["Actions"]) .. "\n"
            .. T["Right-click: undo award"]
    end
    return nil
end

local function RowEnter(self)
    self.Hover:Show()
    local text = TooltipText(self)
    if text then
        self.tipShown = true
        S.TextTooltip(self, text)
    end
end

local function RowLeave(self)
    self.Hover:Hide()
    if self.tipShown then
        self.tipShown = nil
        S.HideTextTooltip()
    end
end

local function RowClick(self, button)
    local kind = self.kind
    if kind == "group" then
        if button == "LeftButton" and self.canTrade and self.recipient then
            addon.Trade:Initiate(self.recipient)
        end
    elseif kind == "item" then
        local MLFrame = addon.UI.MLFrame
        if button == "RightButton" then



            if addon.PlayerIsMasterLooter() and self.session and self.runId
                and MLFrame:ConfirmUnaward(self.session, self.runId, self.link,
                    self.untradeable)
            then
                return
            end


            if MLFrame:ConfirmRetract(self.entryId) then return end
            MLFrame:ConfirmDropObligation(self.entryId)
        elseif self.session and self.runId == addon.Session:GetRunId() then
            MLFrame:SelectSession(self.session)
        end
    elseif kind == "othersItem" then
        if button == "RightButton" then


            if addon.PlayerIsMasterLooter() then
                addon.UI.MLFrame:ConfirmRetractOthers(self.key)
            end
        elseif self.session and self.runId == addon.Session:GetRunId() then
            addon.UI.MLFrame:SelectSession(self.session)
        end
    end
end


local function ResetRow(row)
    if row.tipShown then
        row.tipShown = nil
        S.HideTextTooltip()
    end
    row.Hover:Hide()
    row.kind, row.recipient, row.canTrade = nil, nil, nil
    row.entry, row.record, row.key, row.link = nil, nil, nil, nil
    row.session, row.runId, row.entryId, row.untradeable = nil, nil, nil, nil
end




local function GetRow(index)
    local row = rows[index]
    if row then return row end


    row = CreateFrame("Button", nil, host)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)

    row.Stripe = S.RoundFill(row, S.color.rowStripe, S.radius.CTRL,
        "BACKGROUND", -1)
    row.Stripe:Hide()

    row.Hover = S.RoundFill(row, S.color.rowHover, S.radius.CTRL, "BACKGROUND")
    row.Hover:Hide()


    row.Urgent = row:CreateTexture(nil, "ARTWORK")
    P.Size(row.Urgent, 2, nil)
    row.Urgent:SetColorTexture(S.Unpack(S.color.danger))
    P.Crisp(row.Urgent)
    row.Urgent:SetPoint("TOPLEFT")
    row.Urgent:SetPoint("BOTTOMLEFT")
    row.Urgent:Hide()


    local danger = S.color.danger
    row.Untradeable = S.RoundFill(row, { danger[1], danger[2], danger[3], 0.16 },
        S.radius.CTRL, "BACKGROUND")
    row.Untradeable:Hide()

    row.icon = S.ItemIcon(row, S.size.ICON_SM)

    row.icon:EnableMouse(false)

    row.right = S.Label(row, S.fontNum, "RIGHT")

    row.count = S.Label(row, S.fontSmall, "RIGHT")

    row.trade = S.Button(row, T["Trade"],
        { height = S.size.BTN_H_SM, primary = true, font = S.fontSmall })
    row.trade:SetScript("OnClick", function()
        if row.kind == "group" and row.recipient then addon.Trade:Initiate(row.recipient) end
    end)


    row.label = S.Label(row, S.fontBody, "LEFT")

    rows[index] = row
    rowSet[row] = true
    return row
end


local function ShapeRow(row, kind)
    row.label:ClearAllPoints()
    row.right:ClearAllPoints()

    if kind == "group" then
        P.Size(row, nil, S.size.GROUP_ROW)
        row.icon:Hide()
        row.trade:Show()
        row.count:Show()

        P.Point(row.trade, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
        P.Point(row.count, "RIGHT", row.trade, "LEFT", -S.size.GAP, 0)
        P.Point(row.label, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
        P.Point(row.label, "RIGHT", row.count, "LEFT", -S.size.GAP, 0)
        row.label:SetFontObject(S.fontButton)
        row.right:Hide()
    else
        P.Size(row, nil, S.size.LIST_ROW)
        row.icon:Show()
        row.trade:Hide()
        row.count:Hide()
        row.right:Show()

        P.Point(row.icon, "LEFT", row, "LEFT", ITEM_INDENT + S.size.ROW_PAD, 0)
        P.Point(row.right, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
        P.Point(row.label, "LEFT", row.icon, "RIGHT", S.size.GAP, 0)
        P.Point(row.label, "RIGHT", row.right, "LEFT", -S.size.GAP, 0)
        row.label:SetFontObject(S.fontSmall)
    end
end

local function ClockText(seconds)
    if not seconds then return "?", S.color.textFaint end
    local minutes = math.floor(seconds / 60)
    local text = minutes >= 60
        and addon.Locale.Format(T["%dh%02dm"], math.floor(minutes / 60), minutes % 60)
        or addon.Locale.Format(T["%dm"], minutes)


    if seconds < URGENT_BELOW then return text, S.color.bad end
    return text, S.color.textMuted
end

local function PaintRange(group)


    if group.tradeable == 0 then
        group.row.count:SetText(T["Loot no longer tradeable"])
        group.row.count:SetTextColor(S.Unpack(S.color.dangerText))
        return
    end
    local text, colourKey = addon.Trade:RangeLabel(group.rangeState, group.dead,
        group.tradeable)
    group.row.count:SetText(text)
    group.row.count:SetTextColor(S.Unpack(S.color[colourKey]))
end






local function BuildGroups()
    local byRecipient, order = {}, {}

    local owed = addon.Storage:GetAll(addon.Storage.TO_TRADE)


    local clocks = addon.Storage:Clocks(owed)
    for _, entry in ipairs(owed) do
        local who = entry.args and entry.args.recipient
        if who then
            local group = byRecipient[who]
            if not group then
                group = { recipient = who, items = {}, soonest = math.huge,
                    tradeable = 0 }
                byRecipient[who] = group
                order[#order + 1] = group
            end


            local untradeable = entry.untradeable ~= nil
            local remaining = not untradeable and clocks[entry] or nil
            group.items[#group.items + 1] =
                { entry = entry, remaining = remaining, untradeable = untradeable }
            if not untradeable then group.tradeable = group.tradeable + 1 end
            if remaining and remaining < group.soonest then
                group.soonest = remaining
            end
        end
    end

    for _, group in ipairs(order) do

        table.sort(group.items, function(a, b)
            if a.untradeable ~= b.untradeable then return b.untradeable end
            return (a.remaining or math.huge) < (b.remaining or math.huge)
        end)
        group.rangeState, group.dead = addon.Trade:RangeState(group.recipient)
    end
    table.sort(order, function(a, b)
        if a.soonest ~= b.soonest then return a.soonest < b.soonest end
        return a.recipient < b.recipient
    end)
    addon.Trade:SortByRange(order)

    return order
end



local function BuildOthers()
    local byWinner, order = {}, {}
    local now = GetServerTime()
    for _, record in ipairs(addon.Trade:OwedByOthers()) do
        local group = byWinner[record.winner]
        if not group then
            group = { recipient = record.winner, items = {} }
            byWinner[record.winner] = group
            order[#order + 1] = group
        end
        local untradeable = record.untradeable ~= nil
        group.items[#group.items + 1] = {
            record = record, untradeable = untradeable,

            remaining = not untradeable and record.expiresAt
                and math.max(0, record.expiresAt - now) or nil,
        }
    end
    for _, group in ipairs(order) do


        local position = {}
        for i, item in ipairs(group.items) do position[item] = i end
        table.sort(group.items, function(a, b)
            if a.untradeable ~= b.untradeable then return b.untradeable end
            return position[a] < position[b]
        end)
    end
    return order
end



local function NameColour(fullName)
    local record = addon.Player:Get(fullName)
    local colour = record and record.classFile
        and C_ClassColor.GetClassColor(record.classFile)
    if colour then return { colour.r, colour.g, colour.b } end
    return S.color.text
end


local function PaintItem(item, link, holder)
    item.icon:Show()
    item.icon:SetItem(link)
    local name, _, quality = C_Item.GetItemInfo(link)
    item.icon:SetQualityBorder(quality)

    local label = name or link or "?"
    if holder then label = addon.Locale.Format(T["%s (%s)"], label, holder) end
    item.label:SetText(label)


    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then item.label:SetTextColor(r, g, b) end
    else
        item.label:SetTextColor(S.Unpack(S.color.text))
    end
end

function TradeQueueFrame:Refresh()
    if not frame or not frame:IsShown() then return end

    local groups = BuildGroups()
    local others = BuildOthers()
    visibleGroups = groups
    clockRows = {}
    local index, owed, urgent, othersOwed = 0, 0, 0, 0
    local y = 0


    local function NextRow(kind)
        index = index + 1
        local row = GetRow(index)
        ResetRow(row)
        ShapeRow(row, kind)
        P.Point(row, "TOPLEFT", host, "TOPLEFT", 0, -y)
        P.Point(row, "TOPRIGHT", host, "TOPRIGHT", 0, -y)
        y = y + (kind == "group" and S.size.GROUP_ROW or S.size.LIST_ROW) + S.size.ITEM_GAP
        return row
    end

    for _, group in ipairs(groups) do
        local groupUrgent = group.soonest < URGENT_BELOW

        local row = NextRow("group")

        row.Stripe:SetShown(not groupUrgent)
        row.Urgent:SetShown(groupUrgent)

        row.Untradeable:Hide()
        if groupUrgent then urgent = urgent + 1 end

        row.label:SetText(Ambiguate(group.recipient, "short"))
        row.label:SetTextColor(S.Unpack(NameColour(group.recipient)))
        group.row = row
        PaintRange(group)


        local canTrade = group.tradeable > 0
        row.kind, row.recipient, row.canTrade = "group", group.recipient, canTrade
        row.trade:SetShown(canTrade)
        row:EnableMouse(true)
        row:Show()

        for i, record in ipairs(group.items) do
            owed = owed + 1
            local item = NextRow("item")

            local untradeable = record.untradeable
            item.Urgent:SetShown(untradeable)
            item.Untradeable:SetShown(untradeable)
            item.Stripe:SetShown(not untradeable and i % 2 == 0)

            local link = record.entry.link
            PaintItem(item, link)

            if untradeable then
                item.right:SetText(T["Loot no longer tradeable"])
                item.right:SetTextColor(S.Unpack(S.color.dangerText))
            else
                local text, colour = ClockText(record.remaining)
                item.right:SetText(text)
                item.right:SetTextColor(S.Unpack(colour))
                clockRows[#clockRows + 1] = { row = item, entry = record.entry,
                    remaining = record.remaining }
            end


            local args = record.entry.args
            item.kind, item.recipient, item.entry = "item", group.recipient, record.entry
            item.link, item.untradeable, item.entryId = link, untradeable, record.entry.id
            item.session = args and args.session
            item.runId = args and args.runId
            item:EnableMouse(true)
            item:Show()
        end

        y = y - S.size.ITEM_GAP + GROUP_GAP
    end



    local othersHere = #others > 0 and #groups > 0
    othersHeading:SetShown(othersHere)
    if othersHere then
        othersHeading:ClearAllPoints()
        P.Point(othersHeading, "TOPLEFT", host, "TOPLEFT", 0, -y)
        P.Point(othersHeading, "TOPRIGHT", host, "TOPRIGHT", 0, -y)
        y = y + othersHeading:GetHeight() + S.size.SECTION
    end

    for _, group in ipairs(others) do
        local row = NextRow("group")
        row.Stripe:Show()
        row.Urgent:Hide()
        row.Untradeable:Hide()
        row.trade:Hide()
        row.label:SetText(Ambiguate(group.recipient, "short"))
        row.label:SetTextColor(S.Unpack(NameColour(group.recipient)))
        row.count:SetText(addon.Locale.Format(addon.Locale.Plural{
            one = "%d item", other = "%d items" }, #group.items, #group.items))
        row.count:SetTextColor(S.Unpack(S.color.textMuted))
        row.kind, row.recipient = "othersGroup", group.recipient
        row:EnableMouse(true)
        row:Show()

        for i, entry in ipairs(group.items) do
            othersOwed = othersOwed + 1
            local record = entry.record
            local item = NextRow("item")
            local untradeable = entry.untradeable
            item.Urgent:SetShown(untradeable)
            item.Untradeable:SetShown(untradeable)
            item.Stripe:SetShown(not untradeable and i % 2 == 0)

            local holder = S.Colorize(NameColour(record.holder),
                Ambiguate(record.holder or "?", "short"))
            PaintItem(item, record.link, holder)

            if untradeable then
                item.right:SetText(T["Loot no longer tradeable"])
                item.right:SetTextColor(S.Unpack(S.color.dangerText))
            elseif entry.remaining then
                local text, colour = ClockText(entry.remaining)
                item.right:SetText(text)
                item.right:SetTextColor(S.Unpack(colour))
                if record.expiresAt then
                    clockRows[#clockRows + 1] = { row = item, record = record,
                        remaining = entry.remaining }
                end
            else


                item.right:SetText("")
            end

            item.kind, item.recipient, item.record = "othersItem", group.recipient, record
            item.key, item.session, item.runId = record.key, record.session, record.runId
            item.link, item.untradeable = record.link, untradeable
            item:EnableMouse(true)
            item:Show()
        end

        y = y - S.size.ITEM_GAP + GROUP_GAP
    end

    for i = index + 1, #rows do
        ResetRow(rows[i])
        rows[i]:Hide()
    end
    if #groups == 0 then visibleGroups = nil end


    if #groups + #others > 0 then y = y - GROUP_GAP end

    heading.Text:SetText(addon.Locale.Upper(
        (#groups == 0 and #others > 0) and T["Owed by others"] or T["Owed"]))
    local othersCount = addon.Locale.Format(addon.Locale.Plural{
        one = "%d item", other = "%d items" }, othersOwed, othersOwed)
    othersHeading:SetRight(othersCount)

    if owed + othersOwed == 0 then
        empty:Show()
        heading:SetRight("0")
        frame:SetTag(nil)
        y = empty:GetHeight()
    elseif owed == 0 then
        empty:Hide()
        heading:SetRight(othersCount)
        frame:SetTag(nil)
    else
        empty:Hide()
        local items = addon.Locale.Format(addon.Locale.Plural{ one = "%d item", other = "%d items" },
            owed, owed)
        local players = addon.Locale.Format(addon.Locale.Plural{
            one = "%d player", other = "%d players",
        }, #groups, #groups)
        heading:SetRight(addon.Locale.Format(T["%s to %s"], items, players))
        frame:SetTag(urgent > 0 and addon.Locale.Format(T["%d URGENT"], urgent) or nil,
            S.color.dangerText)
    end


    P.Size(host, nil, y)
    P.Size(frame, nil, frame.HeaderHeight + S.size.PAD + heading:GetHeight()
        + S.size.SECTION + y + S.size.PAD)


    local foci = GetMouseFoci and GetMouseFoci()
    for _, focus in ipairs(foci or {}) do
        if rowSet[focus] and focus:IsShown() then RowEnter(focus) end
    end
end



local function UpdateClocks()
    if not frame or not frame:IsShown() or #clockRows == 0 then return end

    local clocks = addon.Storage:Clocks(addon.Storage:GetAll(addon.Storage.TO_TRADE))
    local now = GetServerTime()
    local fresh = {}
    for i, clock in ipairs(clockRows) do
        local remaining
        if clock.entry then
            if clock.entry.untradeable ~= nil then return TradeQueueFrame:Refresh() end
            remaining = clocks[clock.entry]
        else
            if clock.record.untradeable ~= nil then return TradeQueueFrame:Refresh() end
            remaining = math.max(0, clock.record.expiresAt - now)
            if remaining <= 0 then return TradeQueueFrame:Refresh() end
        end
        local was = clock.remaining and clock.remaining < URGENT_BELOW
        local urgent = remaining and remaining < URGENT_BELOW
        if (was and true or false) ~= (urgent and true or false) then
            return TradeQueueFrame:Refresh()
        end
        fresh[i] = remaining
    end
    for i, clock in ipairs(clockRows) do
        clock.remaining = fresh[i]
        local text, colour = ClockText(fresh[i])
        clock.row.right:SetText(text)
        clock.row.right:SetTextColor(S.Unpack(colour))
    end
end





local function StopTickers()
    if rangeTicker then rangeTicker:Cancel(); rangeTicker = nil end
    if clockTicker then clockTicker:Cancel(); clockTicker = nil end
    visibleGroups = nil
end



local function Build()
    frame = S.Window("SimpleLootCouncilTradeQueueFrame", "tradeQueue",
        WINDOW_W, 420, T["Loot to trade"])
    frame:RestorePosition()



    local content = frame.Content
    local width = L.WidthOf(content)

    heading = S.Heading(content, 0, width, 0, T["Owed"],
        { right = "0", rightFont = S.fontSmall })

    host = CreateFrame("Frame", nil, content)
    P.Point(host, "TOPLEFT", heading, "BOTTOMLEFT", 0, -S.size.SECTION)
    P.Point(host, "TOPRIGHT", heading, "BOTTOMRIGHT", 0, -S.size.SECTION)
    P.Size(host, nil, 1)
    host.slcWidth = width

    empty = S.EmptyState(host, T["Nothing owed"],
        T["Items appear here when you are holding something that was awarded to someone else."], width)
    P.Point(empty, "TOPLEFT", host, "TOPLEFT", 0, 0)
    P.Point(empty, "TOPRIGHT", host, "TOPRIGHT", 0, 0)



    othersHeading = S.Heading(host, 0, width, 0, T["Owed by others"],
        { right = "", rightFont = S.fontSmall })
    othersHeading:Hide()


    frame:HookScript("OnShow", function()
        StopTickers()
        rangeTicker = C_Timer.NewTicker(2, function()
            if not visibleGroups then return end
            for _, group in ipairs(visibleGroups) do
                local state, dead = addon.Trade:RangeState(group.recipient)
                if addon.Trade:RangeBand(state) ~= addon.Trade:RangeBand(group.rangeState) then
                    TradeQueueFrame:Refresh()
                    return
                end
                group.rangeState, group.dead = state, dead
                PaintRange(group)
            end
        end)

        clockTicker = C_Timer.NewTicker(30, UpdateClocks)
    end)
    frame:HookScript("OnHide", function()
        StopTickers()
        for _, row in ipairs(rows) do
            if row.tipShown then RowLeave(row) end
        end
    end)



    frame:HookScript("OnHide", function()
        addon.AutoClose:AfterHide(function(swept)
            if swept then TradeQueueFrame:SyncVisibility() end
        end)
    end)

    addon.Log:D("UI", "trade queue frame built")
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



local function OwedCount()
    return #addon.Storage:GetAll(addon.Storage.TO_TRADE) + #addon.Trade:OwedByOthers()
end



local function MarkedThisSession(at)
    return type(at) == "number" and at >= SESSION_START
end

local function WorthShowing()
    for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        if not entry.untradeable or MarkedThisSession(entry.untradeableAt) then return true end
    end
    for _, record in ipairs(addon.Trade:OwedByOthers()) do
        if not record.untradeable or MarkedThisSession(record.untradeableAt) then return true end
    end
    return false
end

function TradeQueueFrame:SyncVisibility()
    if WorthShowing() then
        WhenBuilt(function()

            if OwedCount() == 0 then return end
            if not frame:IsShown() then frame:Show() end
            TradeQueueFrame:Refresh()
        end)
    elseif OwedCount() == 0 then
        if frame and frame:IsShown() then frame:Hide() end
    elseif frame and frame:IsShown() then
        TradeQueueFrame:Refresh()
    end
end

function TradeQueueFrame:Init()
    S = addon.Style
    L, P = addon.Layout, addon.Pixel

    local function SyncVisibility() TradeQueueFrame:SyncVisibility() end
    addon.Callbacks:Register("StorageChanged", SyncVisibility)
    addon.Callbacks:Register("OwedByOthersChanged", SyncVisibility)


    SyncVisibility()

    addon.Log:I("UI", "trade queue frame ready")
end

function TradeQueueFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    WhenBuilt(function()
        frame:Show()
        TradeQueueFrame:Refresh()
    end)
end