if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local Table = {}
UI.Table = Table


local ROW_HEIGHT = addon.Style and addon.Style.size.ROW_H_SM or 20


local GAP = 2




local issecret = issecretvalue

local function SetTextOnChange(fs)
    local raw = fs.SetText
    local last, known = nil, false
    fs.SetText = function(self, text)
        if issecret and issecret(text) then
            known = false
            return raw(self, text)
        end
        if known and text == last then return end
        last, known = text, true
        return raw(self, text)
    end
end


local function HasText(fs)
    local text = fs:GetText()
    if text == nil then return false end
    if issecret and issecret(text) then return true end
    return text ~= ""
end








function Table.Create(parent, columns, visibleRows, rowHeight, headerFont)
    local t = CreateFrame("Frame", nil, parent)
    local S = addon.Style
    local P = addon.Pixel
    rowHeight = rowHeight or ROW_HEIGHT

    t.columns = columns
    t.rows = {}
    t.data = {}
    t.filtered = {}
    t.sortColumn = nil
    t.sortAscending = true
    t.rowHeight = rowHeight

    t.versions = setmetatable({}, { __mode = "k" })


    t.anchorGen = 0


    local headerHeight = math.min(rowHeight, ROW_HEIGHT)
    t.headerHeight = headerHeight

    local totalWidth = 0
    for _, column in ipairs(columns) do totalWidth = totalWidth + column.width end
    P.Size(t, totalWidth, headerHeight + visibleRows * rowHeight)


    local header = CreateFrame("Frame", nil, t)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    P.Size(header, nil, headerHeight)
    t.header = header

    local x = 0
    for index, column in ipairs(columns) do
        local button = CreateFrame("Button", nil, header)
        P.Size(button, column.width, headerHeight)
        P.Point(button, "LEFT", x, 0)


        local label = S.Label(button, headerFont or S.fontMicro,
            column.justify or "LEFT")
        P.Point(label, "LEFT", 4 + (column.headerOffset or 0), 0)
        P.Point(label, "RIGHT", -4 + (column.headerOffset or 0), 0)
        label:SetText(column.title and addon.Locale.Upper(column.title) or "")
        button.Label = label



        if column.compare or column.value then
            button:SetScript("OnClick", function()
                if t.sortColumn == index then
                    t.sortAscending = not t.sortAscending
                else
                    t.sortColumn, t.sortAscending = index, true
                end
                if t.onSort then t.onSort(t) end
                Table.Refresh(t)
            end)
            button:SetScript("OnEnter", function() label:SetTextColor(S.Unpack(S.color.text)) end)
            button:SetScript("OnLeave", function() label:SetTextColor(S.Unpack(S.color.textMuted)) end)
        end

        x = x + column.width
    end

    local rule = t:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(S.Unpack(S.color.border))
    P.Crisp(rule)
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    local function ruleThickness() rule:SetHeight(P.Hairline()) end
    ruleThickness()
    P.OnRescale(ruleThickness)
    P.OnRescale(function() t.anchorGen = t.anchorGen + 1 end)


    for i = 1, visibleRows do
        local row = CreateFrame("Button", nil, t)
        P.Size(row, nil, rowHeight)
        P.Point(row, "TOPLEFT", 0, -(headerHeight + (i - 1) * rowHeight) - 1)
        P.Point(row, "TOPRIGHT", 0, -(headerHeight + (i - 1) * rowHeight) - 1)


        local stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        stripe:SetAllPoints()
        P.Crisp(stripe)
        row.Stripe = stripe

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(S.Unpack(S.color.rowHover))
        P.Crisp(highlight)
        highlight:Hide()
        row.Highlight = highlight

        row.cells = {}
        local cx = 0
        for index, column in ipairs(columns) do
            local cell = CreateFrame("Frame", nil, row)
            P.Size(cell, column.width, rowHeight)
            P.Point(cell, "LEFT", cx, 0)


            local text = S.Label(cell, column.font or S.fontBody,
                column.justify or "LEFT")
            SetTextOnChange(text)
            cell.Text = text


            if column.sub then
                local sub = S.Label(cell, column.subFont or S.fontHint,
                    column.justify or "LEFT")
                SetTextOnChange(sub)
                P.Point(text, "BOTTOMLEFT", cell, "LEFT", 4, 1)
                P.Point(text, "BOTTOMRIGHT", cell, "RIGHT", -4, 1)
                P.Point(sub, "TOPLEFT", cell, "LEFT", 4, -1)
                P.Point(sub, "TOPRIGHT", cell, "RIGHT", -4, -1)
                cell.Sub = sub
                if column.over then
                    local over = S.Label(cell, column.overFont or S.fontHint,
                        column.justify or "LEFT")
                    SetTextOnChange(over)
                    P.Point(over, "TOPLEFT", cell, "LEFT", 4, 0)
                    P.Point(over, "TOPRIGHT", cell, "RIGHT", -4, 0)
                    cell.Over = over
                end
            else
                P.Point(text, "LEFT", 4, 0)
                P.Point(text, "RIGHT", -4, 0)
            end

            row.cells[index] = cell
            cx = cx + column.width
        end

        row:SetScript("OnEnter", function(self)
            highlight:Show()
            if t.onEnter and self.rowData then t.onEnter(self, self.rowData) end
        end)
        row:SetScript("OnLeave", function(self)
            highlight:Hide()
            if t.onLeave then t.onLeave(self, self.rowData) end
        end)
        row:SetScript("OnClick", function(self, button)
            if t.onClick and self.rowData then t.onClick(self, self.rowData, button) end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row:Hide()
        row.slcShown = false
        t.rows[i] = row
    end



    t.offset = 0
    local bar = S.ScrollBar(t)
    P.Point(bar, "TOPLEFT", t, "TOPRIGHT", S.size.SCROLLBAR_GAP, -headerHeight - 1)
    P.Point(bar, "BOTTOMLEFT", t, "BOTTOMRIGHT", S.size.SCROLLBAR_GAP, 0)
    bar:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + 0.5)
        if offset == t.offset then return end
        t.offset = offset
        Table.Draw(t)
    end)
    local Wheel = S.ScrollWheel(bar, 1)
    t:SetScript("OnMouseWheel", Wheel)
    bar:SetScript("OnMouseWheel", Wheel)
    t.ScrollBar = bar

    t.visibleRows = visibleRows
    return t
end







local Rebuild




function Table.SetData(t, data, keepScroll)
    t.data = data or {}

    if keepScroll then
        Rebuild(t)
        Table.Draw(t)
        return
    end

    Table.Refresh(t)
end

function Table.SetFilter(t, predicate)
    t.filter = predicate
    Table.Refresh(t)
end


function Table.IsFiltering(t)
    return #t.filtered < #t.data
end







local function CompareChain(t, columnIndex, a, b, depth)
    if not columnIndex or depth > 4 then return nil end

    local column = t.columns[columnIndex]
    if not column then return nil end

    local result
    if column.compare then
        result = column.compare(a, b)
    elseif column.value then
        local va, vb = column.value(a), column.value(b)
        if va == vb then
            result = 0
        elseif va == nil then
            result = 1
        elseif vb == nil then
            result = -1
        else
            result = (va < vb) and -1 or 1
        end
    end

    if result == nil then return nil end
    if result ~= 0 then return result end

    return CompareChain(t, column.sortNext, a, b, depth + 1)
end



local function Less(t, a, b)
    local result = CompareChain(t, t.sortColumn, a, b, 1) or 0
    if result == 0 then

        local ka = tostring(a.sortKey or a.name or "")
        local kb = tostring(b.sortKey or b.name or "")
        return ka < kb
    end
    if t.sortAscending then return result < 0 end
    return result > 0
end



local function PrepareSort(t, rows)
    local index, depth = t.sortColumn, 1
    while index and depth <= 4 do
        local column = t.columns[index]
        if not column then return end
        if column.prepare then column.prepare(rows) end
        index, depth = column.sortNext, depth + 1
    end
end

local function SortFiltered(t)
    if not t.sortColumn then return end
    PrepareSort(t, t.filtered)
    table.sort(t.filtered, function(a, b) return Less(t, a, b) end)

    t.sorts = (t.sorts or 0) + 1
end

Rebuild = function(t)
    t.filtered = {}
    for _, row in ipairs(t.data) do
        if not t.filter or t.filter(row) then
            t.filtered[#t.filtered + 1] = row
        end
    end
    SortFiltered(t)
end





function Table.Refresh(t)
    Rebuild(t)


    t.offset = 0
    Table.Draw(t)
end




local function RepositionSub(cell, column, gen)
    local P, S = addon.Pixel, addon.Style
    local hasText, hasSub = HasText(cell.Text), HasText(cell.Sub)
    local hasOver = cell.Over and HasText(cell.Over) or false
    local shape = (hasText and 1 or 0) + (hasSub and 2 or 0) + (hasOver and 4 or 0)
    if cell.slcShape == shape and cell.slcShapeGen == gen then return end
    cell.slcShape, cell.slcShapeGen = shape, gen

    local _, textFontH = (column.font or S.fontBody):GetFont()
    local _, subFontH = (column.subFont or S.fontHint):GetFont()
    local textH = hasText and (textFontH or 0) or 0
    local subH = hasSub and (subFontH or 0) or 0


    cell.Text:ClearAllPoints()
    cell.Sub:ClearAllPoints()
    if hasOver then
        local _, overFontH = (column.overFont or S.fontHint):GetFont()
        local overH = overFontH or 0
        local overGap = column.overGap or GAP
        local top = (overH + textH + subH + overGap
            + (subH > 0 and GAP or 0)) / 2
        P.Point(cell.Over, "TOPLEFT", cell, "LEFT", 4, top)
        P.Point(cell.Over, "TOPRIGHT", cell, "RIGHT", -4, top)
        P.Point(cell.Text, "TOPLEFT", cell, "LEFT", 4, top - overH - overGap)
        P.Point(cell.Text, "TOPRIGHT", cell, "RIGHT", -4, top - overH - overGap)
        if subH > 0 then
            local subTop = top - overH - overGap - textH - GAP
            P.Point(cell.Sub, "TOPLEFT", cell, "LEFT", 4, subTop)
            P.Point(cell.Sub, "TOPRIGHT", cell, "RIGHT", -4, subTop)
        end
        return
    end

    local gap = (textH > 0 and subH > 0) and GAP or 0
    local textOffset = (subH - textH + gap) / 2
    local subOffset = (subH - textH - gap) / 2
    P.Point(cell.Text, "BOTTOMLEFT", cell, "LEFT", 4, textOffset)
    P.Point(cell.Text, "BOTTOMRIGHT", cell, "RIGHT", -4, textOffset)
    P.Point(cell.Sub, "TOPLEFT", cell, "LEFT", 4, subOffset)
    P.Point(cell.Sub, "TOPRIGHT", cell, "RIGHT", -4, subOffset)
end



local function DrawRows(t, offset, force)
    local S = addon.Style
    local versions = t.versions
    for i = 1, t.visibleRows do
        local row = t.rows[i]
        local data = t.filtered[i + offset]

        if data then
            local version = versions[data] or 0
            if force or row.rowData ~= data or row.slcVersion ~= version then
                row.rowData, row.slcVersion = data, version


                local parity = (i + offset) % 2
                if force or row.slcParity ~= parity then
                    row.slcParity = parity
                    row.Stripe:SetColorTexture(S.Unpack(
                        parity == 0 and S.color.rowEven or S.color.rowOdd))
                end
                for index, column in ipairs(t.columns) do
                    local cell = row.cells[index]
                    if column.render then
                        column.render(cell, data)
                    else
                        cell.Text:SetText(column.text and column.text(data) or "")
                        cell.Text:SetTextColor(S.Unpack(S.color.text))
                    end
                    if column.sub then RepositionSub(cell, column, t.anchorGen) end
                end
            end
            if not row.slcShown then
                row:Show()
                row.slcShown = true
            end
        elseif row.rowData ~= nil or row.slcShown then
            row.rowData = nil
            row:Hide()
            row.slcShown = false
        end
    end
end


function Table.Draw(t)


    local maxOffset = math.max(0, #t.filtered - t.visibleRows)
    local offset = math.min(t.offset, maxOffset)
    t.offset = offset
    local bar = t.ScrollBar
    bar:SetMinMaxValues(0, maxOffset)
    bar:SetValue(offset)
    bar:SetShown(maxOffset > 0)

    t:EnableMouseWheel(maxOffset > 0)

    DrawRows(t, offset, true)
end





function Table.UpdateRows(t, rows)
    if not rows or #rows == 0 then return end
    local versions = t.versions
    for _, row in ipairs(rows) do versions[row] = (versions[row] or 0) + 1 end

    local filtered = t.filtered
    local position = {}
    for i, row in ipairs(filtered) do position[row] = i end

    if t.filter then
        for _, row in ipairs(rows) do
            if (position[row] ~= nil) ~= (t.filter(row) and true or false) then
                Table.SetData(t, t.data, true)
                return
            end
        end
    end

    if t.sortColumn then
        PrepareSort(t, filtered)
        for _, row in ipairs(rows) do
            local i = position[row]
            if i then
                local before, after = filtered[i - 1], filtered[i + 1]
                if (before and Less(t, row, before)) or (after and Less(t, after, row)) then
                    SortFiltered(t)
                    break
                end
            end
        end
    end

    DrawRows(t, t.offset, false)
end
