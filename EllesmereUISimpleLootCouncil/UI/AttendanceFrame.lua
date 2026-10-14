if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local AttendanceFrame = {}
UI.AttendanceFrame = AttendanceFrame

local S, Tbl, L, P
local frame, table_, summaryText
local clearFrame


local expandedWeeks, expandedNights = {}, {}

local INDENT = 18






local function Weekday(epoch)
    local names = { WEEKDAY_SUNDAY, WEEKDAY_MONDAY, WEEKDAY_TUESDAY, WEEKDAY_WEDNESDAY,
        WEEKDAY_THURSDAY, WEEKDAY_FRIDAY, WEEKDAY_SATURDAY }
    return names[(tonumber(date("%w", epoch)) or 0) + 1] or ""
end


local function WeekLabel(week)
    return addon.Locale.Format(T["%s - %s"],
        date("%Y/%m/%d", week.start), date("%Y/%m/%d", week.finish - 1))
end

local function NightLabel(night)
    local started, ended = night.startedAt or 0, night.endedAt or night.startedAt or 0
    return addon.Locale.Format(T["%s %s  %s-%s"], Weekday(started),
        date("%Y/%m/%d", started), date("%H:%M", started), date("%H:%M", ended))
end

local function CountMembers(night)
    local n = 0
    for _ in pairs(night.members or {}) do n = n + 1 end
    return n
end


local function ClassIndex()
    local index = {}
    if not addon.RaidTeam then return index end
    for _, member in ipairs(addon.RaidTeam:GetRoster()) do
        local key = addon.Player:NameKey(member.fullName)
        if key and member.classFile then index[key] = member.classFile end
    end
    return index
end







local function Flatten()
    local rows = {}
    local weeks = addon.Attendance:GetWeeks()
    local classes

    for _, week in ipairs(weeks) do
        rows[#rows + 1] = { kind = "week", week = week }
        if expandedWeeks[week.start] then
            for _, night in ipairs(week.nights) do
                rows[#rows + 1] = { kind = "night", week = week, night = night }
                if expandedNights[night] then
                    classes = classes or ClassIndex()
                    local players = {}
                    for name in pairs(night.members or {}) do
                        players[#players + 1] = name
                    end

                    table.sort(players, function(a, b)
                        local pa, pb = night.members[a] or 0, night.members[b] or 0
                        if pa ~= pb then return pa > pb end
                        return a < b
                    end)
                    if #players == 0 then
                        rows[#rows + 1] = { kind = "empty" }
                    end
                    for _, name in ipairs(players) do
                        rows[#rows + 1] = {
                            kind = "player", week = week, night = night, name = name,
                            classFile = classes[addon.Player:NameKey(name) or ""],
                        }
                    end
                end
            end
        end
    end

    return rows, weeks
end





local CHEVRON_CLOSED = "Options_ListExpand_Right"
local CHEVRON_OPEN = "Options_ListExpand_Right_Expanded"
local haveChevron


local function ChevronAvailable()
    if haveChevron == nil then
        haveChevron = (C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo(CHEVRON_CLOSED)) and true or false
    end
    return haveChevron
end

local function RenderWho(cell, row)
    if not cell.Chevron then
        cell.Chevron = cell:CreateTexture(nil, "ARTWORK")
        cell.Chevron:SetSize(12, 12)
        cell.Marker = S.Label(cell, S.fontBody, "CENTER")
        cell.Marker:SetWidth(12)
    end

    local depth = row.kind == "week" and 0 or row.kind == "night" and 1 or 2
    local x = 4 + depth * INDENT
    cell.Text:ClearAllPoints()
    P.Point(cell.Text, "LEFT", cell, "LEFT", x + 18, 0)
    P.Point(cell.Text, "RIGHT", cell, "RIGHT", -4, 0)

    if row.kind == "week" or row.kind == "night" then
        local open = row.kind == "week" and expandedWeeks[row.week.start]
            or row.kind == "night" and expandedNights[row.night]
        cell.Chevron:ClearAllPoints()
        cell.Chevron:SetPoint("LEFT", x, 0)
        cell.Marker:ClearAllPoints()
        cell.Marker:SetPoint("LEFT", x, 0)
        if ChevronAvailable() then
            cell.Chevron:SetAtlas(open and CHEVRON_OPEN or CHEVRON_CLOSED)
            cell.Chevron:SetDesaturated(true)
            cell.Chevron:SetVertexColor(S.Unpack(S.color.textMuted))
            cell.Chevron:Show()
            cell.Marker:Hide()
        else
            cell.Chevron:Hide()
            cell.Marker:SetText(S.Colorize(S.color.textMuted, open and "-" or "+"))
            cell.Marker:Show()
        end
    else
        cell.Chevron:Hide()
        cell.Marker:Hide()
    end

    if row.kind == "week" then
        local nights = #row.week.nights
        cell.Text:SetText(WeekLabel(row.week) .. S.Colorize(S.color.textFaint,
            addon.Locale.Format(addon.Locale.Plural{
                one = "  %d night", other = "  %d nights",
            }, nights, nights)))
        cell.Text:SetTextColor(S.Unpack(S.color.accentPale))
    elseif row.kind == "night" then
        local players = CountMembers(row.night)
        cell.Text:SetText(NightLabel(row.night) .. S.Colorize(S.color.textFaint,
            addon.Locale.Format(addon.Locale.Plural{
                one = "  %d player", other = "  %d players",
            }, players, players)))
        cell.Text:SetTextColor(S.Unpack(S.color.text))
    elseif row.kind == "player" then
        cell.Text:SetText(Ambiguate(row.name, "short"))
        local colour = row.classFile and C_ClassColor.GetClassColor(row.classFile)
        if colour then
            cell.Text:SetTextColor(colour:GetRGB())
        else
            cell.Text:SetTextColor(S.Unpack(S.color.text))
        end
    else
        cell.Text:SetText(T["no players recorded"])
        cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
    end
end

local function Pulls(row)
    if row.kind == "week" then return row.week.pulls end
    if row.kind == "night" then return row.night.pulls or 0 end
    if row.kind == "player" then return row.night.members[row.name] or 0 end
end


local function Kills(row)
    if row.kind == "week" then return row.week.kills end
    if row.kind == "night" then return row.night.kills or 0 end
    if row.kind == "player" then
        local kills = row.night.memberKills
        return kills and (kills[row.name] or 0) or nil
    end
end

local function Count(value, colour)
    if value == nil then return S.Colorize(S.color.textFaint, "-") end
    return S.Colorize(colour, tostring(value))
end

local function BuildColumns()
    return {

        { key = "who", title = T["Week / Night / Player"], width = 421, render = RenderWho },
        {
            key = "pulls", title = T["Pulls"], width = 80, justify = "RIGHT",
            text = function(row)
                if row.kind == "empty" then return "" end
                return Count(Pulls(row), row.kind == "player" and S.color.textMuted or S.color.text)
            end,
        },
        {
            key = "kills", title = T["Kills"], width = 80, justify = "RIGHT",
            text = function(row)
                if row.kind == "empty" then return "" end
                return Count(Kills(row), S.color.accent)
            end,
        },
    }
end

local function ShowRowTooltip(row, data)
    if data.kind == "empty" then return end
    S.SideTooltip(row)
    if data.kind == "player" then
        S.TooltipSection(GameTooltip, T["Player"])
        GameTooltip:AddLine(data.name, 1, 1, 1)
        if not data.night.memberKills then
            GameTooltip:AddLine(T["Kills were not counted per player when this night was recorded."],
                0.45, 0.44, 0.42, true)
        end
        S.TooltipSection(GameTooltip, T["Actions"])
        GameTooltip:AddLine(T["Right-click to delete this player from this night"], 0.45, 0.44, 0.42)
    else
        S.TooltipSection(GameTooltip, data.kind == "week" and T["Week"] or T["Night"])
        GameTooltip:AddLine(data.kind == "week" and WeekLabel(data.week)
            or NightLabel(data.night), 1, 1, 1)
        S.TooltipSection(GameTooltip, T["Actions"])
        local open = data.kind == "week" and expandedWeeks[data.week.start]
            or data.kind == "night" and expandedNights[data.night]
        GameTooltip:AddLine(open and T["Click to collapse"] or T["Click to expand"],
            0.45, 0.44, 0.42)
        GameTooltip:AddLine(data.kind == "week" and T["Right-click to delete this week"]
            or T["Right-click to delete this night"], 0.45, 0.44, 0.42)
    end
    GameTooltip:Show()
end





local function Counted(kind, n)
    local plural
    if kind == "night" then
        plural = addon.Locale.Plural{ one = "%d night", other = "%d nights" }
    elseif kind == "pull" then
        plural = addon.Locale.Plural{ one = "%d pull", other = "%d pulls" }
    elseif kind == "kill" then
        plural = addon.Locale.Plural{ one = "%d kill", other = "%d kills" }
    else
        plural = addon.Locale.Plural{ one = "%d player", other = "%d players" }
    end
    return addon.Locale.Format(plural, n, n)
end


local function EntrySummary(data)
    local week = WeekLabel(data.week)
    if data.kind == "week" then
        local players = {}
        for _, night in ipairs(data.week.nights) do
            for name in pairs(night.members or {}) do players[name] = true end
        end
        local count = 0
        for _ in pairs(players) do count = count + 1 end
        return addon.Locale.Format(T["Week %s: %s, %s, %s, %s."], week,
            Counted("night", #data.week.nights),
            Counted("pull", data.week.pulls or 0),
            Counted("kill", data.week.kills or 0),
            Counted("player", count))
    elseif data.kind == "night" then
        return addon.Locale.Format(T["%s, in the week of %s: %s, %s, %s."],
            NightLabel(data.night), week,
            Counted("pull", data.night.pulls or 0),
            Counted("kill", data.night.kills or 0),
            Counted("player", CountMembers(data.night)))
    end
    local kills = Kills(data)
    return addon.Locale.Format(T["%s on %s, in the week of %s: %s, %s."],
        Ambiguate(data.name, "short"), NightLabel(data.night), week,
        Counted("pull", Pulls(data) or 0),
        kills and Counted("kill", kills) or T["kills not counted"])
end


local function DeleteEntry(data)
    local nights, match
    if data.kind == "week" then
        nights = data.week.nights
    elseif data.kind == "night" then
        nights = { data.night }
    elseif data.kind == "player" then
        local name = data.name
        nights = { data.night }
        match = function(member) return member == name end
    else
        return
    end
    S.Confirm({
        title = T["Delete entry?"],
        body = addon.Locale.Format(T["%s\n\n%s"],
            T["Delete this attendance entry permanently?"], EntrySummary(data)),
        detailFont = S.fontSmall,
        accept = T["Delete"],
        onAccept = function()
            local removedNights, removedEntries = addon.Attendance:ClearNights(nights, match)
            print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(
                T["attendance cleared: %d night(s), %d player entries."],
                removedNights, removedEntries))
        end,
    })
end





function AttendanceFrame:Refresh(keepScroll)
    if not frame then return end
    local rows, weeks = Flatten()
    Tbl.SetData(table_, rows, keepScroll)

    local nights = #addon.Attendance:GetNights()
    if nights == 0 then
        summaryText:SetText(S.Colorize(S.color.textFaint, T["No raid nights recorded."]))
    else
        summaryText:SetText(S.Colorize(S.color.textMuted, addon.Locale.Format(
            addon.Locale.Plural{
                one = "%d night over %d week(s)", other = "%d nights over %d week(s)",
            }, nights, nights, #weeks)))
    end
end






local choice = { week = nil, night = nil, ranks = {}, players = {} }

local function ChosenPlayerCount()
    local n = 0
    for _ in pairs(choice.players) do n = n + 1 end
    return n
end


local function Reconcile()
    local weeks = addon.Attendance:GetWeeks()
    local week
    for _, w in ipairs(weeks) do
        if choice.week and w.start == choice.week.start then week = w end
    end
    choice.week = week
    if choice.night then
        local found
        for _, night in ipairs(week and week.nights or {}) do
            if night == choice.night then found = true end
        end
        if not found then choice.night = nil end
    end
    return weeks
end

local function ScopeNights()
    if choice.night then return { choice.night } end
    if choice.week then return choice.week.nights end
    return nil
end


local function Matcher()
    local roster = next(choice.ranks) and addon.RaidTeam and addon.RaidTeam:GetRoster() or {}
    return addon.Attendance.Matcher(roster, choice.ranks, choice.players)
end

local function Filtered()
    return next(choice.ranks) ~= nil or next(choice.players) ~= nil
end


local function NamesInScope()
    local seen, names = {}, {}
    for _, night in ipairs(ScopeNights() or addon.Attendance:GetNights()) do
        for name in pairs(night.members or {}) do
            if not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names, function(a, b)
        return addon.Locale.Fold(a) < addon.Locale.Fold(b)
    end)
    return names
end

local function WhoLabel()
    local rankCount, rankName = 0, nil
    for name in pairs(choice.ranks) do rankCount, rankName = rankCount + 1, name end
    local rankPart
    if rankCount == 1 then
        rankPart = addon.Locale.Format(T["Rank: %s"], rankName)
    elseif rankCount > 1 then
        rankPart = addon.Locale.Format(addon.Locale.Plural{
            one = "%d rank", other = "%d ranks",
        }, rankCount, rankCount)
    end

    local playerPart
    local n = ChosenPlayerCount()
    if n == 1 then
        playerPart = Ambiguate(next(choice.players), "short")
    elseif n > 1 then
        playerPart = addon.Locale.Format(addon.Locale.Plural{
            one = "%d player", other = "%d players",
        }, n, n)
    end

    if rankPart and playerPart then
        return addon.Locale.Format(T["%s and %s"], rankPart, playerPart)
    end
    return rankPart or playerPart or T["Everyone"]
end

local function ScopeSentence()
    local nights = ScopeNights()
    local count = nights and #nights or #addon.Attendance:GetNights()
    local where = addon.Locale.Format(addon.Locale.Plural{
        one = "%d night", other = "%d nights",
    }, count, count)
    if Filtered() then
        return addon.Locale.Format(T["Removes %s from %s."], WhoLabel(), where)
    end
    return addon.Locale.Format(T["Removes %s for everyone."], where)
end

local function ClearReason()
    if #addon.Attendance:GetNights() == 0 then
        return S.RequiresSentence(T["Requires recorded attendance."])
    end
    if not choice.week and not Filtered() then
        return S.RequiresSentence(T["Requires a week or a player to be chosen. Clear all empties everything."])
    end
end



local LIST_W, LIST_MAX_H, BOX = 300, 360, 16
local listPanel, listKey, listOwner
local listRows = {}
local RefreshClear

local function CloseList()
    if listPanel then listPanel:Hide() end
    if listOwner then listOwner:SetSelected(false) end
    listKey, listOwner = nil, nil
end


local function WeekEntries()
    local entries = { { heading = T["Week"] } }
    entries[#entries + 1] = {
        label = T["Every week"], closes = true,
        checked = function() return choice.week == nil end,
        pick = function() choice.week, choice.night = nil, nil end,
    }
    for _, week in ipairs(addon.Attendance:GetWeeks()) do
        entries[#entries + 1] = {
            label = WeekLabel(week), closes = true,
            checked = function() return choice.week ~= nil and choice.week.start == week.start end,
            pick = function() choice.week, choice.night = week, nil end,
        }
    end
    return entries
end

local function NightEntries()
    local entries = { { heading = T["Night"] } }
    entries[#entries + 1] = {
        label = T["Whole week"], closes = true,
        checked = function() return choice.night == nil end,
        pick = function() choice.night = nil end,
    }
    for _, night in ipairs(choice.week and choice.week.nights or {}) do
        entries[#entries + 1] = {
            label = NightLabel(night), closes = true,
            checked = function() return choice.night == night end,
            pick = function() choice.night = night end,
        }
    end
    return entries
end


local function WhoEntries()
    local entries = {}
    entries[#entries + 1] = {
        label = T["Everyone"],
        checked = function() return not Filtered() end,
        pick = function() choice.ranks, choice.players = {}, {} end,
    }

    entries[#entries + 1] = { heading = T["Guild rank"] }
    local ranks = addon.RaidTeam and addon.RaidTeam:GetRanks() or {}
    if #ranks == 0 then entries[#entries + 1] = { note = T["(not in a guild)"] } end
    for _, rank in ipairs(ranks) do
        local rankName = rank.name
        entries[#entries + 1] = {
            label = rankName,
            checked = function() return choice.ranks[rankName] == true end,
            pick = function()
                choice.ranks[rankName] = (not choice.ranks[rankName]) or nil
            end,
        }
    end

    entries[#entries + 1] = { heading = T["Players"] }
    local names = NamesInScope()
    if #names == 0 then entries[#entries + 1] = { note = T["no players recorded"] } end
    local classes = ClassIndex()
    for _, name in ipairs(names) do
        local classFile = classes[addon.Player:NameKey(name) or ""]
        entries[#entries + 1] = {
            label = Ambiguate(name, "short"),
            colour = classFile and C_ClassColor.GetClassColor(classFile),
            checked = function() return choice.players[name] == true end,
            pick = function()
                choice.players[name] = (not choice.players[name]) or nil
            end,
        }
    end
    return entries
end

local ENTRIES = { week = WeekEntries, night = NightEntries, who = WhoEntries }

local function ListRow(i)
    if listRows[i] then return listRows[i] end
    local row = L.Row(listPanel.Scroll.Content, 0, LIST_W, 0, S.size.ROW_H_SM)

    row.Box = S.Checkbox(row, BOX)
    P.Point(row.Box, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
    row:AdoptHover(row.Box)

    row.Text = S.Label(row, S.fontBody, "LEFT")
    P.Point(row.Text, "LEFT", row.Box, "RIGHT", S.size.GAP, 0)
    P.Point(row.Text, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)

    row.Heading = S.Label(row, S.fontMicro, "LEFT")
    P.Point(row.Heading, "BOTTOMLEFT", row, "BOTTOMLEFT", S.size.ROW_PAD, 4)
    P.Point(row.Heading, "BOTTOMRIGHT", row, "BOTTOMRIGHT", -S.size.ROW_PAD, 4)

    local function click()
        local entry = row.entry
        if not entry or not entry.pick then return end
        entry.pick()
        if entry.closes then CloseList() end
        RefreshClear()
    end
    row.Box:SetScript("OnClick", click)
    row:SetScript("OnMouseUp", click)

    listRows[i] = row
    return row
end

local function RefreshList()
    if not listPanel or not listKey then return end
    local entries = ENTRIES[listKey]()
    local y = 0
    for i, entry in ipairs(entries) do
        local row = ListRow(i)
        local option = entry.pick ~= nil
        row.entry = entry
        row:ClearAllPoints()
        P.Point(row, "TOPLEFT", listPanel.Scroll.Content, "TOPLEFT", 0, -y)
        row:EnableMouse(option)
        row.Box:SetShown(option)
        row.Text:SetShown(option or entry.note ~= nil)
        row.Heading:SetShown(entry.heading ~= nil)
        if option then
            row.Box:SetChecked(entry.checked())
            row.Text:SetText(entry.label)
            if entry.colour then
                row.Text:SetTextColor(entry.colour:GetRGB())
            else
                row.Text:SetTextColor(S.Unpack(S.color.text))
            end
        elseif entry.note then
            row.Text:SetText(S.Colorize(S.color.textFaint, entry.note))
        else
            row.Heading:SetText(entry.heading)
        end
        row:Show()
        y = y + S.size.ROW_H_SM
    end
    for i = #entries + 1, #listRows do
        listRows[i].entry = nil
        listRows[i]:Hide()
    end
    listPanel:SetHeight(P.Snap(math.min(y, LIST_MAX_H) + S.size.PAD * 2))
    listPanel.Scroll:SetContentHeight(y)


    if y <= LIST_MAX_H then
        local bar = listPanel.Scroll.ScrollBar
        local function fit()
            bar:SetMinMaxValues(0, 0)
            bar:SetValue(0)
            bar:Hide()
        end
        fit()
        P.AfterLayout(fit)
    end
end

local function BuildList(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 20)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    P.Size(f, LIST_W + S.size.SCROLLBAR_W + S.size.SCROLLBAR_GAP + S.size.PAD * 2, 100)
    S.CanvasFill(f, S.color.canvas, 0.96)
    S.RoundBorder(f, S.color.border, "OVERLAY")

    local scroll = S.ScrollRegion(f, S.size.ROW_H_SM)
    P.Point(scroll, "TOPLEFT", f, "TOPLEFT", S.size.PAD, -S.size.PAD)
    P.Point(scroll, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.size.PAD, S.size.PAD)
    f.Scroll = scroll
    f:Hide()
    return f
end


local function ToggleList(key, owner)
    if listKey == key then
        CloseList()
        return
    end
    CloseList()
    listKey, listOwner = key, owner
    owner:SetSelected(true)


    listPanel:ClearAllPoints()
    local top = (owner:GetTop() or clearFrame:GetTop()) - clearFrame:GetTop()
    listPanel:SetPoint("TOPLEFT", clearFrame, "TOPRIGHT", 2 * P.Hairline(listPanel), top)
    RefreshList()
    listPanel:Show()
end

function RefreshClear()
    if not clearFrame or not clearFrame:IsShown() then return end
    Reconcile()

    clearFrame.WeekPicker:SetLabel(choice.week and WeekLabel(choice.week) or T["Every week"])
    clearFrame.NightPicker:SetLabel(choice.night and NightLabel(choice.night)
        or (choice.week and T["Whole week"] or T["Every night"]))
    clearFrame.NightPicker:SetEnabled(choice.week ~= nil)
    clearFrame.WhoPicker:SetLabel(WhoLabel())

    local reason = ClearReason()
    clearFrame.Clear:SetDisabledReason(reason)
    clearFrame.Clear:SetEnabled(reason == nil)
    clearFrame.ClearAll:SetEnabled(#addon.Attendance:GetNights() > 0)
    clearFrame.Summary:SetText(reason and "" or ScopeSentence())

    if listKey == "night" and not choice.week then CloseList() end
    RefreshList()
end

local function PickerRow(cursor, label, onClick)
    local picker
    cursor:Add(function(parent, x, width, y)
        local row = L.Row(parent, x, width, y)
        picker = S.Button(row, "", { width = 250, height = S.size.CTRL_H, fixedWidth = true })
        P.Point(picker, "RIGHT", row, "RIGHT", 0, 0)
        row:AdoptHover(picker)
        L.BoundedLabel(row, picker, label, S.fontSetting)
        picker:SetScript("OnClick", onClick)
        return row, S.size.ROW_H
    end)
    return picker
end

local function DoClear()
    local nights, match = ScopeNights(), Matcher()
    S.Confirm({
        title = T["Clear attendance"],
        body = addon.Locale.Format(T["%s\n\n%s"], ScopeSentence(), S.Colorize(S.color.bad,
            T["Cleared attendance cannot be recovered. It is cleared on this client only."])),
        accept = T["Clear"],
        onAccept = function()
            local removedNights, removedEntries = addon.Attendance:ClearNights(nights, match)
            print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(
                T["attendance cleared: %d night(s), %d player entries."],
                removedNights, removedEntries))
            choice.week, choice.night = nil, nil
            RefreshClear()
        end,
    })
end

local function DoClearAll()
    local count = #addon.Attendance:GetNights()
    S.Confirm({
        title = T["Clear all attendance"],
        body = addon.Locale.Format(T["%s\n\n%s"], addon.Locale.Format(addon.Locale.Plural{
            one = "This deletes %d recorded raid night.",
            other = "This deletes all %d recorded raid nights.",
        }, count, count), S.Colorize(S.color.bad,
            T["Cleared attendance cannot be recovered. It is cleared on this client only."])),
        accept = T["Clear all"],
        onAccept = function()
            local removed = addon.Attendance:ClearAll()
            print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(
                T["attendance cleared: all %d night(s)."], removed))
            choice.week, choice.night, choice.ranks, choice.players = nil, nil, {}, {}
            RefreshClear()
        end,
    })
end

local function BuildClearFrame()
    local f = S.Window("SimpleLootCouncilAttendanceClearFrame", "attendanceClear", 470, 300,
        T["Clear attendance"])
    f:SetFrameStrata("FULLSCREEN_DIALOG")

    local cursor = L.Cursor(f.Content)
    cursor:Add(L.Paragraph,
        T["Choose a week, then a night to narrow it. Choose players or a guild rank to remove only them; Everyone removes the nights themselves."],
        S.fontHint)
    cursor:Gap(S.size.SECTION)

    f.WeekPicker = PickerRow(cursor, T["Week"], function(self) ToggleList("week", self) end)
    f.NightPicker = PickerRow(cursor, T["Night"], function(self) ToggleList("night", self) end)
    f.NightPicker:SetDisabledReason(S.RequiresSentence(T["Requires a week to be chosen."]))
    f.WhoPicker = PickerRow(cursor, T["Players"], function(self) ToggleList("who", self) end)
    cursor:Gap(S.size.SECTION)


    f.Summary = cursor:Add(function(parent, x, width, y)
        local fs = S.Label(parent, S.fontSmall, "LEFT", "wrap")
        fs:SetWidth(P.Snap(width))
        fs:SetJustifyV("TOP")
        P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
        return fs, 30
    end)

    local footer = S.FooterBar(f)
    f.Clear = S.Button(footer, T["Clear"], { labelPad = S.size.BTN_PAD_FOOTER })
    footer:Add(f.Clear, true)
    f.Clear:SetScript("OnClick", DoClear)
    f.ClearAll = S.Button(footer, T["Clear all"], {
        danger = true, labelPad = S.size.BTN_PAD_FOOTER,
    })
    footer:Add(f.ClearAll, true)
    f.ClearAll:SetScript("OnClick", DoClearAll)

    f:SetHeight(P.Snap(f.HeaderHeight + S.size.PAD * 2 + cursor:Consumed()
        + S.size.FOOTER_H))
    listPanel = BuildList(f)
    f:HookScript("OnShow", RefreshClear)
    f:HookScript("OnHide", function()
        GameTooltip:Hide()
        CloseList()
    end)
    return f
end

function AttendanceFrame:ToggleClear()
    if clearFrame:IsShown() then
        clearFrame:Hide()
        return
    end
    clearFrame:RestorePosition()
    clearFrame:Show()
end





function AttendanceFrame:Init()
    S, Tbl = addon.Style, UI.Table
    L, P = addon.Layout, addon.Pixel

    frame = S.Window("SimpleLootCouncilAttendanceFrame", "attendance", 620, 560,
        T["Attendance"])
    frame:RestorePosition()

    local cursor = L.Cursor(frame.Content)
    table_ = cursor:Add(function(parent, x, _, y)
        local t = Tbl.Create(parent, BuildColumns(), 16)
        P.Point(t, "TOPLEFT", parent, "TOPLEFT", x, y)
        return t, t:GetHeight()
    end)

    table_.onEnter = function(row, data) ShowRowTooltip(row, data) end
    table_.onLeave = function() GameTooltip:Hide() end
    table_.onClick = function(_, data, button)
        if button == "RightButton" then
            DeleteEntry(data)
            return
        end
        if data.kind == "week" then
            expandedWeeks[data.week.start] = (not expandedWeeks[data.week.start]) or nil
        elseif data.kind == "night" then
            expandedNights[data.night] = (not expandedNights[data.night]) or nil
        else
            return
        end
        AttendanceFrame:Refresh(true)
    end

    local footer = S.FooterBar(frame)
    summaryText = footer:AddText(S.fontSmall)
    local clear = S.Button(footer, T["Clear attendance"], { labelPad = S.size.BTN_PAD_FOOTER })
    footer:Add(clear, true)
    clear:SetScript("OnClick", function() AttendanceFrame:ToggleClear() end)

    frame:SetHeight(P.Snap(frame.HeaderHeight + S.size.PAD * 2 + cursor:Consumed()
        + S.size.FOOTER_H))
    frame:HookScript("OnHide", function()
        GameTooltip:Hide()
        if clearFrame then clearFrame:Hide() end
    end)

    clearFrame = BuildClearFrame()

    addon.Callbacks:Register("AttendanceChanged", function()
        if frame:IsShown() then AttendanceFrame:Refresh(true) end
        RefreshClear()
    end)

    addon.Log:I("UI", "attendance frame ready")
end

function AttendanceFrame:Toggle()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:RestorePosition()
    AttendanceFrame:Refresh()
    frame:Show()
end
