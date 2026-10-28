if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local MLFrame = {}
UI.MLFrame = MLFrame

local S, Tbl, L, P
local frame, sessionStrip, runScroll, table_, itemIcon, itemName, voteStatus
local itemBoss




local CM = {
    active = false,
    table = nil,
    button = nil,
    apply = nil,
    dismissedRun = nil,
    BAR_GAP = 7,



    PAINT_INTERVAL = 0.15,


    AWARD_GUARD = 0.6,
    awardedAt = -math.huge,

    rowsFor = setmetatable({}, { __mode = "k" }),


    votedOn = setmetatable({}, { __mode = "k" }),
}
local endButton, timerText, menuHint
local rollButton, footer
local timerLabel
local answeredBar, answeredText, answeredCount, runCount
local againstName, againstDetail, againstDelta, againstIcon


local againstFor
local selectedSession = 1
local paintedSession
local selectedSet


local TIMER_WARN_AT = 0.33


local COMPARE_H       = 86
local STRIP_WASH_A    = 0.13

local STRIP_WASH_BASE = { 1, 1, 1, 1 }




local function ConfirmedItem(session, runId, identity)
    if addon.Session:GetRunId() ~= runId then return nil end
    local item = addon.Session:GetItem(session)
    if not item then return nil end
    local currentIdentity = item.id or item.link
    if currentIdentity ~= identity then return nil end
    return item
end


local function ItemText(link)
    if link and link ~= "" then return link end
    return T["this item"]
end



local function CannotAwardText(item)
    if item.removed then
        return addon.Locale.Format(
            T["%s was removed from this run.\n\nRight-click it in the list to restore it first."],
            ItemText(item.link))
    elseif item.gone == "pending" then
        return addon.Locale.Format(
            T["%s has not been looted yet.\n\nIt can be awarded once it reaches the Loot Master's bags."],
            ItemText(item.link))
    elseif item.gone == "lost" then
        return addon.Locale.Format(
            T["%s went to another player in the loot roll, so it cannot be traded from here.\n\nRight-click it in the list to remove it from the run."],
            ItemText(item.link))
    elseif item.gone == "equipped" then
        return addon.Locale.Format(
            T["%s can no longer be traded.\n\nIts holder equipped it. Right-click it in the list to remove it from the run."],
            ItemText(item.link))
    elseif item.gone == "bound" then
        return addon.Locale.Format(
            T["%s can no longer be traded.\n\nIts trade window has ended. Right-click it in the list to remove it from the run."],
            ItemText(item.link))
    end
    return addon.Locale.Format(
        T["%s can no longer be traded.\n\nIts holder no longer has it in their bags. Right-click it in the list to remove it from the run."],
        ItemText(item.link))
end



function CM.AwardClickAllowed(session, runId)
    if session ~= selectedSession or runId ~= addon.Session:GetRunId() then
        addon.Log:D("UI", "award click for an item no longer shown ignored", tostring(session))
        return false
    end
    local now = GetTime()
    if now - CM.awardedAt < CM.AWARD_GUARD then
        addon.Log:D("UI", "second award click inside the guard ignored", tostring(session))
        return false
    end
    CM.awardedAt = now
    return true
end



function MLFrame:Award(session, winner, reason)
    local runId = addon.Session:GetRunId()
    local item = addon.Session:GetItem(session)
    if not runId or not item or not winner then return false end


    if not addon.Session:IsAwardable(item) then
        addon.Chat.Print((CannotAwardText(item):gsub("\n\n", " ")))
        return false
    end
    return addon.Session:Award(session, winner, reason, runId)
end


function MLFrame:Unaward(session)
    local item = addon.Session:GetItem(session)
    if not item or not item.awarded then return false end
    return addon.Session:Unaward(session, addon.Session:GetRunId())
end



function MLFrame:ConfirmUnaward(session, expectedRunId, expectedLink, offerRemove)
    local runId = expectedRunId or addon.Session:GetRunId()

    local item = addon.Session:GetItem(session)
    if not item or addon.Session:GetRunId() ~= runId then return false end
    if not item.awarded then return false end
    if expectedLink and item.link ~= expectedLink then return false end

    local identity = item.id or item.link
    local previous = item.awarded
    local itemText = ItemText(item.link)
    local short = Ambiguate(previous, "short")
    local live = addon.Session:IsRunning() and not addon.Session:HasEnded()
        and addon.Session:GetItems()[session] == item
    local removable = live and (offerRemove or item.gone) and true or false

    local function Current()
        local current = ConfirmedItem(session, runId, identity)
        if not current or current.awarded ~= previous then
            addon.Log:WLogOnly("UI", "stale unaward confirmation ignored", session)
            return nil
        end
        return current
    end

    local body = addon.Locale.Format(removable
        and T["Undo the award of %s to %s?\n\nThis removes it from the trade queue and from history. It can no longer be traded, so it can also come out of the run."]
        or T["Undo the award of %s to %s?\n\nThis removes it from the trade queue and from history."],
        itemText, short)
    if item.delivered then
        body = body .. "\n\n" .. addon.Locale.Format(
            T["%s was already traded to %s. This changes the history record."],
            itemText, short)
    end

    S.Confirm({
        title = T["Undo award?"],
        body = body,
        accept = T["Undo award"],
        onAccept = function()
            if Current() then addon.Session:Unaward(session, runId) end
        end,
        alternate = removable and T["Undo award and remove from run"] or nil,
        onAlternate = removable and function()
            if Current() then addon.Session:UnawardAndRemove(session, runId) end
        end or nil,
    })
    return true
end



function MLFrame:ConfirmRemove(session)
    local runId = addon.Session:GetRunId()
    local item = addon.Session:GetItems()[session]
    if not runId or not item or addon.Session:HasEnded() then return false end
    if item.awarded then
        return MLFrame:ConfirmUnaward(session, runId, item.link, true)
    end

    local identity = item.id or item.link
    local itemText = ItemText(item.link)
    local restoring = item.removed and true or false
    local body
    if restoring then
        body = addon.Locale.Format(
            T["Put %s back into the run?\n\nRaiders see it again and the council can award it."],
            itemText)
    elseif item.gone == "pending" then
        body = addon.Locale.Format(
            T["Remove %s from the run? It has not been looted yet.\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    elseif item.gone == "lost" then
        body = addon.Locale.Format(
            T["Remove %s from the run? It went to another player in the loot roll.\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    elseif item.gone == "equipped" then
        body = addon.Locale.Format(
            T["Remove %s from the run? Its holder equipped it.\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    elseif item.gone == "bound" then
        body = addon.Locale.Format(
            T["Remove %s from the run? Its trade window has ended.\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    elseif item.gone then
        body = addon.Locale.Format(
            T["Remove %s from the run? Its holder no longer has it in their bags.\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    else
        body = addon.Locale.Format(
            T["Remove %s from the run?\n\nIt stays in this list, marked Removed, and leaves every raider's window. Right-click it again to restore it."],
            itemText)
    end

    S.Confirm({
        title = restoring and T["Restore to run?"] or T["Remove from run?"],
        body = body,
        accept = restoring and T["Restore"] or T["Remove"],
        onAccept = function()
            if not ConfirmedItem(session, runId, identity) then
                addon.Log:WLogOnly("UI", "stale remove confirmation ignored", session)
                return
            end
            addon.Session:RemoveItem(session, not restoring, runId)
        end,
    })
    return true
end




function MLFrame:ConfirmRetract(entryId)
    if not entryId or not addon.PlayerIsMasterLooter() then return false end

    local function Find()
        for _, candidate in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
            if candidate.id == entryId then return candidate end
        end
    end
    local entry = Find()
    local args = entry and entry.args
    if not args or not args.runId or not args.session or not args.recipient then
        return false
    end

    local itemText = ItemText(entry.link)
    local short = Ambiguate(args.recipient, "short")
    S.Confirm({
        title = T["Undo award?"],
        body = addon.Locale.Format(T["Undo the award of %s to %s?\n\nThis removes it from Loot to Trade and from history, for everyone."], itemText, short),
        accept = T["Undo award"],
        onAccept = function()

            local current = Find()
            if not current then
                addon.Log:WLogOnly("UI", "obligation already gone", tostring(entryId))
                return
            end
            if not addon.Session:RetractAward(args.runId, args.session, args.recipient) then
                addon.Chat.Print(addon.Locale.Format(
                    T["could not undo the award of %s - see /slc log."], entry.link or "?"))
            end
        end,


        alternate = T["Drop only, keep history"],
        onAlternate = function()
            if Find() then
                addon.Storage:Remove(entryId)
                addon.Log:I("UI", "obligation dropped by hand", entry.link)
            end
        end,
    })
    return true
end



function MLFrame:ConfirmRetractOthers(key)
    if not key or not addon.PlayerIsMasterLooter() then return false end
    local record = addon.Trade:GetOwedByOthers(key)
    if not record or not record.runId or not record.session or not record.winner then
        return false
    end

    local itemText = ItemText(record.link)
    local short = Ambiguate(record.winner, "short")
    S.Confirm({
        title = T["Undo award?"],
        body = addon.Locale.Format(T["Undo the award of %s to %s?\n\nThis removes it from Loot to Trade and from history, for everyone."], itemText, short),
        accept = T["Undo award"],
        onAccept = function()

            if not addon.Trade:GetOwedByOthers(key) then
                addon.Log:WLogOnly("UI", "award held by someone else already settled", tostring(key))
                return
            end
            if not addon.Session:RetractAward(record.runId, record.session, record.winner) then
                addon.Chat.Print(addon.Locale.Format(
                    T["could not undo the award of %s - see /slc log."], record.link or "?"))
            end
        end,
        alternate = T["Drop only, keep history"],
        onAlternate = function() addon.Trade:ForgetOwedByOthers(key) end,
    })
    return true
end



function MLFrame:ConfirmDropObligation(entryId)
    if not entryId then return false end

    local entry
    for _, candidate in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        if candidate.id == entryId then entry = candidate break end
    end
    if not entry then return false end

    local itemText = ItemText(entry.link)
    local owed = entry.args and entry.args.recipient
    local short = owed and Ambiguate(owed, "short") or T["someone"]


    local body = entry.untradeable
        and addon.Locale.Format(
            T["Stop tracking %s as owed to %s?\n\nIt can no longer be traded. History is left alone - this only removes it from Loot to Trade."],
            itemText, short)
        or addon.Locale.Format(
            T["Stop tracking %s as owed to %s?\n\nThe item stays in your bags and history is left alone - this only removes it from Loot to Trade."],
            itemText, short)
    S.Confirm({
        title = T["Drop this obligation?"],
        body = body,
        accept = T["Drop"],
        onAccept = function()

            for _, candidate in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
                if candidate.id == entryId then
                    addon.Storage:Remove(entryId)
                    addon.Log:I("UI", "obligation dropped by hand", candidate.link)
                    return
                end
            end
            addon.Log:WLogOnly("UI", "obligation already gone", tostring(entryId))
        end,
    })
    return true
end




local RAIL_BOSS_H         = 12 + 7
local RAIL_ANSWERED       = 69 + RAIL_BOSS_H
local RAIL_ANSWERED_RULE  = RAIL_ANSWERED + 32
local RAIL_COMPARE_TITLE  = RAIL_ANSWERED_RULE + 14
local RAIL_COMPARE        = RAIL_COMPARE_TITLE + 20
local RAIL_RUN_RULE       = RAIL_COMPARE + COMPARE_H + 14
local RAIL_RUN_TITLE      = RAIL_RUN_RULE + 14


CM.RUN_TOP                = 7
CM.RUN_TITLE_GAP          = 8


local function Clock(seconds)
    seconds = math.max(0, math.ceil(seconds or 0))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end



local WISHLIST_W = 100
local SIM_W = 72


local UPGRADE_W = 96



local ROLL_W = 62



local VOTES_W = 50
local NOTE_W  = 44

local NOTE_TOOLTIP_LETTERS = 31


local NAME_W     = 150
local RESPONSE_W = 109
local ACTIONS_W  = 151


local RAIL_W   = 298
local RAIL_GAP = 16



local RAIL_EDGE = 29


local STRIP_STATE_PAD = 6
CM.STRIP_STATE_W = 72



local FRAME_RIGHT_GAP = 5



local TABLE_W = NAME_W + RESPONSE_W + UPGRADE_W + VOTES_W + ROLL_W + NOTE_W
    + ACTIONS_W + WISHLIST_W + SIM_W



CM.DROPPED_W = UPGRADE_W + WISHLIST_W + SIM_W


CM.RAIL_GAP_V = 10



local FULL_RAIL_H = 564
CM.FULL_H = 640
local WINDOW_OPTIONS = { tabs = true, tabHeader = true, logo = true, logoFit = true }
CM.FULL_ROWS = 7


CM.ROWS = 3


local function TableWidth(forCompact, allColumns)
    local t
    if forCompact then t = CM.table else t = table_ end
    if t and t.shownWidth and not allColumns then return t.shownWidth end
    return forCompact and (TABLE_W - CM.DROPPED_W) or TABLE_W
end

local function WindowWidth(forCompact, allColumns)
    return S.size.PAD + RAIL_W + RAIL_GAP + TableWidth(forCompact, allColumns)
        + CM.BAR_GAP + S.size.SCROLLBAR_W + FRAME_RIGHT_GAP
end



local function QueueWindowWidth()
    return math.max(WindowWidth(CM.active), math.ceil(UI.VoterFrame:MinWidth()))
end

CM.AnchorTableScrollbar = function(t)
    local bar = t.ScrollBar
    local tableTop = frame.HeaderHeight + S.size.PAD - (t.slcLift or 0)
    bar:ClearAllPoints()
    P.Point(bar, "TOPRIGHT", frame, "TOPRIGHT", -FRAME_RIGHT_GAP,
        -tableTop - t.headerHeight - 1)
    P.Point(bar, "BOTTOMRIGHT", frame, "TOPRIGHT", -FRAME_RIGHT_GAP,
        -tableTop - t:GetHeight())
end



function MLFrame:FitTextWidths()

    local probe = CM.itemInfo:CreateFontString(nil, "ARTWORK")

    local function Widest(text, floor, pad)
        probe:SetText(text)
        local width = probe:GetUnboundedStringWidth()
        if issecretvalue and issecretvalue(width) then return floor end
        if type(width) ~= "number" or width <= 0 then return floor end
        return math.max(floor, math.ceil(width) + (pad or 0))
    end

    probe:SetFontObject(S.fontMicro)
    NAME_W     = Widest(addon.Locale.Upper(T["Name"]),     NAME_W,     10)
    RESPONSE_W = Widest(addon.Locale.Upper(T["Response"]), RESPONSE_W, 10)
    UPGRADE_W  = Widest(addon.Locale.Upper(T["Upgrade"]),  UPGRADE_W,  10)
    VOTES_W    = Widest(addon.Locale.Upper(T["Votes"]),    VOTES_W,    10)
    ROLL_W     = Widest(addon.Locale.Upper(T["Roll"]),     ROLL_W,     10)
    NOTE_W     = Widest(addon.Locale.Upper(T["Note"]),     NOTE_W,     10)
    ACTIONS_W  = Widest(addon.Locale.Upper(T["Actions"]),  ACTIONS_W,  10)
    WISHLIST_W = Widest(addon.Locale.Upper(T["Wishlist"]), WISHLIST_W, 10)
    SIM_W      = Widest(addon.Locale.Upper(T["Sim"]),      SIM_W,      10)

    probe:SetFontObject(S.fontBody)
    local buttonPad = S.size.BTN_PAD * 2
    local voteWidth = math.max(Widest(T["Vote"], 0, buttonPad),
        Widest(T["Unvote"], 0, buttonPad))
    local awardWidth = math.max(Widest(T["Award"], 0, buttonPad),
        Widest(T["Re-award"], 0, buttonPad), Widest(T["Undo"], 0, buttonPad))
    ACTIONS_W = math.max(ACTIONS_W, 2 + voteWidth + 6 + awardWidth + 5)

    probe:SetFontObject(S.fontHint)
    for _, state in ipairs({ T["AWARDED"], T["REMOVED"], T["LOOTING"], T["MISSING"], T["OWED"],
        T["QUEUED"] }) do
        CM.STRIP_STATE_W = Widest(state, CM.STRIP_STATE_W, 2)
    end

    probe:SetText("")
    probe:Hide()

    TABLE_W = NAME_W + RESPONSE_W + UPGRADE_W + VOTES_W + ROLL_W + NOTE_W
        + ACTIONS_W + WISHLIST_W + SIM_W
    CM.DROPPED_W = UPGRADE_W + WISHLIST_W + SIM_W
end


function CM.RowHeight(forCompact)
    if not forCompact then return S.size.ROW_H * 2 end
    local spare = CM.RailHeight() + CM.HeaderLift() - S.size.ROW_H_SM
    return math.max(S.size.ROW_H, math.floor(spare / CM.ROWS))
end



function CM.HeaderLift()
    local _, microH = S.fontMicro:GetFont()
    return math.max(0, math.floor((S.size.ROW_H_SM - (microH or 0)) / 2))
end


function CM.Height(forCompact)
    if not forCompact or not CM.table then return CM.FULL_H end
    local body = math.max(CM.RailHeight(), CM.table:GetHeight() - CM.HeaderLift())
    return frame.HeaderHeight + S.size.PAD + body + CM.RAIL_GAP_V + S.size.FOOTER_H
end



CM.DEFAULT_SORT = "response"
CM.sortKey, CM.sortAscending = CM.DEFAULT_SORT, true

function CM.RecordSort(t)
    CM.sortKey = t.columns[t.sortColumn].key
    CM.sortAscending = t.sortAscending
end

function CM.ApplySort(t)
    local fallback
    for index, column in ipairs(t.columns) do
        if column.key == CM.sortKey then
            t.sortColumn, t.sortAscending = index, CM.sortAscending
            return
        end
        if column.key == CM.DEFAULT_SORT then fallback = index end
    end
    t.sortColumn, t.sortAscending = fallback, true
end


function CM.VotesHidden()
    return addon.Config:Vote().hideVotes
        and not addon.Session:HasVoted(selectedSession,
            addon.Player:GetFullName("player")) or false
end



local function ActiveTable()
    return CM.active and CM.table or table_
end



local hasWishlist = false


local STRIP_ICON = 28
local STRIP_STEP = 42
local STRIP_ROW_H = 38



local STRIP_ROW_W = RAIL_W - 14 - (RAIL_EDGE - STRIP_STATE_PAD)




function CM.RunScrollTop()
    local _, headingH = S.fontHeading:GetFont()
    return CM.RUN_TOP + math.ceil(headingH or 12) + CM.RUN_TITLE_GAP
end

function CM.RunScrollBottom()
    return CM.RUN_TOP - (STRIP_STEP - STRIP_ROW_H)
end

function CM.RailHeight()
    return CM.RunScrollTop() + CM.ROWS * STRIP_STEP + CM.RunScrollBottom()
end


local ShowRowMenu


local function CellMouseUp(self, button)
    local row = self:GetParent()
    local data = row and row.rowData
    if not data then return end
    if button == "RightButton" then
        ShowRowMenu(row, data)
    elseif button == "LeftButton" and data.name then
        CM.TogglePick(data.name)
    end
end







local function ResolveResponse(candidate, sortOnly)
    if not candidate then
        return "-", S.color.textFaint, 999
    end

    if candidate.status == "RESPONDED" and candidate.response then
        local response = addon.Config:Responses()[candidate.response]
        if response then
            if sortOnly then return nil, nil, response.sort end
            return response.text, { response.r, response.g, response.b }, response.sort
        end


        return T["Unknown"], S.color.bad, 900
    end

    local status = addon.Session.STATUS[candidate.status]
    if status then
        local colour = S.color.textMuted
        if candidate.status == "AWARDED" then colour = S.color.good end
        if candidate.status == "NOTHING" then colour = S.color.textFaint end
        return status.text, colour, status.sort
    end

    return candidate.status or "-", S.color.textMuted, 998
end







local function ResolveSortChain(columns)
    local index = {}
    for i, column in ipairs(columns) do index[column.key] = i end
    for _, column in ipairs(columns) do
        if type(column.sortNext) == "string" then
            column.sortNext = index[column.sortNext]
        end
    end
    return columns
end


local function InsertAfter(columns, key, column)
    for i, existing in ipairs(columns) do
        if existing.key == key then
            table.insert(columns, i + 1, column)
            return
        end
    end

    addon.Log:W("UI", "no column to place", column.key, "after", key)
end



local SHORT_TIER = addon.Locale.Texts{
    ["best in slot"] = T["BiS"],
}

local function ShortTier(label)
    if not label then return nil end
    return SHORT_TIER[addon.Locale.Fold(label)] or label
end

local function BuildColumns(forCompact)
    local columns = {
        {


            key = "name", title = T["Name"],
            width = (forCompact or hasWishlist) and NAME_W
                or (NAME_W + WISHLIST_W + SIM_W),
            sub = true, over = true, overGap = 3,
            value = function(row) return row.name end,
            render = function(cell, row)
                local record = addon.Player:Get(row.name)

                cell.Text:SetText(Ambiguate(row.name, "short"))

                local r, g, b = S.ClassColor(record.classFile)
                if r then
                    cell.Text:SetTextColor(r, g, b)
                else
                    cell.Text:SetTextColor(S.Unpack(S.color.text))
                end




                local parts = {}
                if not forCompact and addon.Specs and record.guid then
                    local info = addon.Specs:Info(addon.Specs:Get(record.guid))
                    if info and info.name then parts[#parts + 1] = info.name end
                end
                local ilvl = not forCompact and row.candidate and row.candidate.ilvl
                if ilvl then parts[#parts + 1] = ("%d"):format(ilvl) end


                if not forCompact and row.candidate and row.candidate.viaWhisper then
                    parts[#parts + 1] = T["whispered"]
                end




                local item = addon.Session:GetItem(selectedSession)
                local coinText = ""
                if item and addon.BonusRoll then
                    local coin, spent = addon.BonusRoll:StatusFor(row.name, item)
                    spent = spent + (coin and 1 or 0)
                    if spent > 0 then

                        local possible = addon.BonusRoll:PossibleFor(row.name, item)
                        coinText = S.Colorize(S.color.accent, possible
                            and addon.Locale.Format(T["Bonus rolls: %d of %d"], spent, possible)
                            or addon.Locale.Format(T["Bonus rolls: %d"], spent))
                    end
                end

                cell.Over:SetText(coinText)
                cell.Sub:SetText(table.concat(parts, "  \194\183  "))
            end,
        },
        {
            key = "response", title = T["Response"], width = RESPONSE_W,


            font = S.fontHint,



            compare = function(a, b)
                local _, _, sa = ResolveResponse(a.candidate, true)
                local _, _, sb = ResolveResponse(b.candidate, true)
                if sa == sb then return 0 end
                return sa < sb and -1 or 1
            end,
            render = function(cell, row)
                local text, colour = ResolveResponse(row.candidate)
                local candidate = row.candidate
                local isResponse = candidate and candidate.status == "RESPONDED"
                    and candidate.response and addon.Config:Responses()[candidate.response]

                if isResponse then
                    if not cell.Chip then

                        cell.Chip = S.Chip(cell, "", colour, {
                            height = S.size.BTN_H_SM, padding = 8, maxWidth = 88,
                            font = S.fontSmall,

                            textColor = S.color.text,
                            square = true,
                        })


                        P.Point(cell.Chip, "LEFT", cell, "LEFT", 4, 0)
                    end
                    cell.Text:SetText("")

                    if cell.chipR ~= colour[1] or cell.chipG ~= colour[2]
                        or cell.chipB ~= colour[3] then
                        cell.chipR, cell.chipG, cell.chipB = colour[1], colour[2], colour[3]
                        cell.Chip:SetChipColor(colour)
                    end
                    if cell.chipText ~= text then
                        cell.chipText = text
                        cell.Chip:SetText(text)
                    end
                    if not cell.chipShown then
                        cell.chipShown = true
                        cell.Chip:Show()
                    end
                else
                    if cell.chipShown then
                        cell.chipShown = false
                        cell.Chip:Hide()
                    end
                    cell.Text:SetText(text)
                    cell.Text:SetTextColor(S.Unpack(colour))
                end
            end,
        },
        {
            key = "upgrade", title = T["Upgrade"], width = UPGRADE_W, justify = "CENTER",

            sub = true, font = S.fontNumLarge, subFont = S.fontNumHint,

            compare = function(a, b)
                local da = a.candidate and a.candidate.diff
                local db_ = b.candidate and b.candidate.diff
                if da == db_ then return 0 end
                if da == nil then return 1 end
                if db_ == nil then return -1 end
                return da > db_ and -1 or 1
            end,
            render = function(cell, row)
                local c = row.candidate
                local diff = c and c.diff


                local setMatch = c and selectedSet and (
                    (selectedSet.isToken and c.setID ~= nil)
                    or (selectedSet.setID ~= nil and c.setID == selectedSet.setID))

                local setText, reachesBonus
                if setMatch then
                    setText, reachesBonus = addon.Gear.SetProgress(c.setCount, c.setReplaces)
                end
                local replaced

                if not diff then

                    cell.Text:SetText("")
                else
                    for _, item in ipairs({ c.gear1, c.gear2 }) do
                        local ilvl = addon.Gear:ItemLevel(item)
                        if ilvl and (not replaced or ilvl < replaced) then
                            replaced = ilvl
                        end
                    end

                    local sign = diff > 0 and "+" or ""
                    cell.Text:SetText(addon.Locale.Format(T["%s%d"], sign, diff))


                    if diff > 0 then
                        cell.Text:SetTextColor(S.Unpack(S.color.good))
                    elseif diff < 0 then
                        cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                    else
                        cell.Text:SetTextColor(S.Unpack(S.color.textMuted))
                    end
                end

                if setText then

                    cell.Sub:SetText(setText)
                    cell.Sub:SetTextColor(S.Unpack(reachesBonus
                        and S.color.accent or S.color.textFaint))
                elseif diff then

                    cell.Sub:SetText(replaced
                        and addon.Locale.Format(T["%d -> %d"], replaced, replaced + diff) or "")
                    cell.Sub:SetTextColor(S.Unpack(S.color.textFaint))
                else
                    cell.Sub:SetText("")
                end


                if not cell.hooked then
                    cell.hooked = true
                    cell:EnableMouse(true)
                    cell:SetScript("OnEnter", function(self)
                        Tbl.HoverRow(self:GetParent())
                        local data = self.gear
                        if not data then return end
                        local lines = { S.Colorize(S.color.accent,
                            addon.Locale.SectionTitle(T["Currently Equipped"])) }
                        local any = false
                        local slots = {
                            { link = data.gear1, sockets = data.sockets1 },
                            { link = data.gear2, sockets = data.sockets2 },
                        }
                        for _, slot in ipairs(slots) do
                            if slot.link then
                                local name, link = C_Item.GetItemInfo(slot.link)
                                local ilvl = addon.Gear:ItemLevel(slot.link)
                                local label = "  " .. (link or name or slot.link)
                                if slot.sockets then
                                    label = label .. addon.Locale.Format(addon.Locale.Plural{
                                        one = " (%d socket)", other = " (%d sockets)",
                                    }, slot.sockets, slot.sockets)
                                end
                                lines[#lines + 1] = label .. "  " .. (ilvl and tostring(ilvl) or "?")
                                any = true
                            end
                        end
                        if not any then
                            lines[#lines + 1] = S.Colorize(S.color.textMuted, T["  Nothing in that slot"])
                        end
                        if data.ilvl then
                            lines[#lines + 1] = addon.Locale.SectionTitle(T["Average equipped"])
                                .. " " .. tostring(data.ilvl)
                        end

                        local ctx = self.setCtx
                        if ctx and ctx.match and data.setCount then
                            local setName = ctx.setID
                                and C_Item.GetItemSetInfo(ctx.setID)
                            lines[#lines + 1] = S.Colorize(S.color.accent,
                                addon.Locale.SectionTitle(T["Tier Set"]))
                            if setName then lines[#lines + 1] = setName end
                            lines[#lines + 1] = addon.Locale.SectionTitle(T["  Pieces equipped"])
                                .. " " .. tostring(data.setCount)
                        end
                        S.TextTooltip(self, table.concat(lines, "\n"), self:GetParent(), true)
                    end)
                    cell:SetScript("OnLeave", function(self)
                        S.HideTextTooltip()
                        Tbl.LeaveRow(self:GetParent())
                    end)

                    cell:SetScript("OnMouseUp", CellMouseUp)
                end
                cell.gear = c
                local ctx = cell.setCtx
                if not ctx then
                    ctx = {}
                    cell.setCtx = ctx
                end
                ctx.match = setMatch and true or false
                ctx.setID = c and c.setID or nil
            end,
        },
        {
            key = "votes", title = T["Votes"], width = VOTES_W, justify = "CENTER",
            font = S.fontNumHint,
            prepare = function()
                CM.votesSortHidden = CM.VotesHidden()
            end,
            value = function(row)
                if CM.votesSortHidden then return 0 end
                return row.votes
            end,
            render = function(cell, row)

                if not cell.hooked then
                    cell.hooked = true
                    cell:EnableMouse(true)
                    cell:SetScript("OnEnter", function(self)
                        Tbl.HoverRow(self:GetParent())
                        local voters = not self.votesHidden and self.voters
                        if not voters or not next(voters) then return end
                        local names = {}
                        for name in pairs(voters) do names[#names + 1] = name end
                        table.sort(names, function(a, b)
                            return Ambiguate(a, "short") < Ambiguate(b, "short")
                        end)
                        local lines = { S.Colorize(S.color.accent,
                            addon.Locale.SectionTitle(T["Votes"])) }
                        for _, name in ipairs(names) do
                            local r, g, b = S.ClassColor(addon.Player:Get(name).classFile)
                            lines[#lines + 1] = r and S.Colorize({ r, g, b }, Ambiguate(name, "short"))
                                or Ambiguate(name, "short")
                        end
                        S.TextTooltip(self, table.concat(lines, "\n"), self:GetParent(), true)
                    end)
                    cell:SetScript("OnLeave", function(self)
                        S.HideTextTooltip()
                        Tbl.LeaveRow(self:GetParent())
                    end)

                    cell:SetScript("OnMouseUp", CellMouseUp)
                end
                cell.voters = row.candidate and row.candidate.voters

                cell.votesHidden = CM.VotesHidden()
                if cell.votesHidden then
                    cell.Text:SetText("?")
                    cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                    return
                end
                cell.Text:SetText(tostring(row.votes))
                cell.Text:SetTextColor(S.Unpack(
                    row.votes > 0 and S.color.text or S.color.textFaint))
            end,
        },
        {
            key = "roll", title = T["Roll"], width = ROLL_W, justify = "CENTER",

            sub = true, font = S.fontNumHint, subFont = S.fontNumHint,

            compare = function(a, b)
                local ra = a.candidate and tonumber(a.candidate.roll)
                local rb = b.candidate and tonumber(b.candidate.roll)
                if ra == rb then return 0 end
                if ra == nil then return -1 end
                if rb == nil then return 1 end
                return ra < rb and -1 or 1
            end,
            sortNext = "upgrade",
            render = function(cell, row)
                local item = addon.Session:GetItem(selectedSession)
                local value = row.candidate and row.candidate.roll


                if value and item and addon.Roll.OwedBy(item, row.name) then
                    cell.Text:SetText(tostring(value))
                    cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                    cell.Sub:SetText(T["asked"])
                    cell.Sub:SetTextColor(S.Unpack(S.color.accent))
                elseif value then
                    cell.Text:SetText(tostring(value))
                    cell.Text:SetTextColor(S.Unpack(S.color.text))
                    local assigned = row.candidate.rollBy == "leader"
                    cell.Sub:SetText(assigned and T["assign"] or "")
                    cell.Sub:SetTextColor(S.Unpack(S.color.textFaint))
                elseif item and addon.Roll.IsAsked(item, row.name) then

                    cell.Text:SetText("-")
                    cell.Text:SetTextColor(S.Unpack(S.color.accent))
                    cell.Sub:SetText(T["asked"])
                    cell.Sub:SetTextColor(S.Unpack(S.color.accentPale))
                else
                    cell.Text:SetText("")
                    cell.Sub:SetText("")
                end
            end,
        },
        {
            key = "note", title = T["Note"], width = NOTE_W, justify = "CENTER",
            render = function(cell, row)
                local note = row.candidate and row.candidate.note
                cell.Text:SetText(note and "[+]" or "")
                cell.Text:SetTextColor(S.Unpack(S.color.accent))


                if not cell.hooked then
                    cell.hooked = true
                    cell:EnableMouse(true)
                    cell:SetScript("OnEnter", function(self)
                        Tbl.HoverRow(self:GetParent())

                        local text = self.note and addon.Autopass
                            and addon.Autopass.NoteText(self.note) or self.note
                        if not text then return end
                        S.TextTooltip(self, S.Colorize(S.color.accent,
                            addon.Locale.SectionTitle(T["Note"])) .. "\n"
                            .. table.concat(addon.Locale.Wrap(text, NOTE_TOOLTIP_LETTERS), "\n"),
                            self:GetParent(), true)
                    end)
                    cell:SetScript("OnLeave", function(self)
                        S.HideTextTooltip()
                        Tbl.LeaveRow(self:GetParent())
                    end)

                    cell:SetScript("OnMouseUp", CellMouseUp)
                end
                cell.note = note
            end,
        },
        {
            key = "actions", title = T["Actions"], width = ACTIONS_W,
            justify = "CENTER", headerOffset = -2,
            render = function(cell, row)
                if not cell.voteButton then
                    cell.voteButton = S.Button(cell, T["Vote"], { compact = true })
                    cell.awardButton = S.Button(cell, T["Award"], {
                        compact = true, primary = true,
                    })
                    cell.awardButton:SetPoint("RIGHT", cell, "RIGHT", -5, 0)
                    cell.voteButton:SetPoint("RIGHT", cell.awardButton, "LEFT", -6, 0)
                    Tbl.AdoptHover(cell:GetParent(), cell.voteButton)
                    Tbl.AdoptHover(cell:GetParent(), cell.awardButton)
                    cell.voteButton.slcTipUnder = cell:GetParent()
                    cell.awardButton.slcTipUnder = cell:GetParent()



                    cell.voteButton:SetScript("OnClick", function()
                        if cell.row then
                            addon.Session:Vote(selectedSession, cell.row.name, cell.voteIntent)
                        end
                    end)

                    cell.awardButton:SetScript("OnClick", function()
                        local row = cell.row
                        if not row or not CM.AwardClickAllowed(cell.session, cell.runId) then return end
                        local item = addon.Session:GetItem(cell.session)
                        if not item then return end
                        if cell.awardIntent == "undo" then
                            if item.awarded == row.name then MLFrame:Unaward(cell.session) end
                        elseif item.awarded ~= row.name then
                            MLFrame:Award(cell.session, row.name)
                        end
                    end)
                    cell.voteButton:Show()
                    cell.awardButton:Show()
                end
                cell.row = row


                local me = addon.Player:GetFullName("player")
                local voted = row.candidate and row.candidate.voters[me] and true or false
                cell.voteIntent = not voted
                local voteLabel = voted and T["Unvote"] or T["Vote"]
                if cell.voteLabel ~= voteLabel then
                    cell.voteLabel = voteLabel
                    cell.voteButton:SetLabel(voteLabel)
                end
                local voteReason = addon.Restrictions:IsBlocked()
                    and (addon.Restrictions:GetBlockReason()
                        or S.RequiresSentence(T["Requires comms to be available."]))
                    or S.RequiresSentence(T["Requires you to be on the council."])
                if cell.voteReason ~= voteReason then
                    cell.voteReason = voteReason
                    cell.voteButton:SetDisabledReason(voteReason)
                end
                local voteEnabled = addon.Council:Contains(me)
                    and not addon.Restrictions:IsBlocked() and true or false
                if cell.voteEnabled ~= voteEnabled then
                    cell.voteEnabled = voteEnabled
                    cell.voteButton:SetEnabled(voteEnabled)
                end


                local item = addon.Session:GetItem(selectedSession)
                local awardedTo = item and item.awarded
                local isWinner = awardedTo and awardedTo == row.name

                cell.session, cell.runId = selectedSession, addon.Session:GetRunId()
                cell.awardIntent = isWinner and "undo" or "award"
                local awardLabel = isWinner and T["Undo"]
                    or awardedTo and T["Re-award"] or T["Award"]
                if cell.awardLabel ~= awardLabel then
                    cell.awardLabel = awardLabel
                    cell.awardButton:SetLabel(awardLabel)
                    if isWinner then
                        cell.awardButton:SetColour(S.color.bad, S.color.bad)
                    else
                        cell.awardButton:SetColour(nil)
                    end
                end



                local awardReason
                if addon.Restrictions:IsBlocked() then
                    awardReason = addon.Restrictions:GetBlockReason()
                        or S.RequiresSentence(T["Requires comms to be available."])
                elseif not addon.PlayerIsMasterLooter() then
                    awardReason = S.RequiresSentence(T["Requires you to be the Loot Master."])
                end

                if not cell.awardSet or cell.awardReason ~= awardReason then
                    cell.awardSet, cell.awardReason = true, awardReason
                    cell.awardButton:SetDisabledReason(awardReason)
                    cell.awardButton:SetEnabled(awardReason == nil)
                end
            end,
        },
    }




    if forCompact then
        for i = #columns, 1, -1 do
            if columns[i].key == "upgrade" then table.remove(columns, i) end
        end
        return ResolveSortChain(columns)
    end

    if not hasWishlist then
        return ResolveSortChain(columns)
    end

    InsertAfter(columns, "upgrade", {
        key = "wishlist", title = T["Wishlist"], width = WISHLIST_W, justify = "CENTER",

        font = S.fontHint,


        prepare = function(rows)
            local item = addon.Session:GetItem(selectedSession)
            for _, row in ipairs(rows) do
                local pick = addon.Wishlist:For(row.name, item)
                row.wishlistKey = pick and pick.priorityId or math.huge
            end
        end,
        compare = function(a, b)
            local ka, kb = a.wishlistKey or math.huge, b.wishlistKey or math.huge
            if ka == kb then return 0 end
            return ka < kb and -1 or 1
        end,
        sortNext = "upgrade",
        render = function(cell, row)
            local pick = addon.Wishlist:For(row.name, addon.Session:GetItem(selectedSession))
            cell.Text:SetText(pick and ShortTier(pick.label) or "")
            cell.Text:SetTextColor(S.Unpack(
                pick and (pick.colour or S.color.text) or S.color.textFaint))
        end,
    })

    InsertAfter(columns, "wishlist", {
        key = "sim", title = T["Sim"], width = SIM_W, justify = "CENTER",


        sub = true, font = S.fontNumLarge, subFont = S.fontNumHint,

        prepare = function(rows)
            local item = addon.Session:GetItem(selectedSession)
            for _, row in ipairs(rows) do
                local sim = addon.Wishlist:SimFor(row.name, item)
                row.simKey = sim and sim.pct or -math.huge
            end
        end,
        compare = function(a, b)
            local ka, kb = a.simKey or -math.huge, b.simKey or -math.huge
            if ka == kb then return 0 end
            return ka < kb and -1 or 1
        end,
        sortNext = "upgrade",
        render = function(cell, row)
            local sim = addon.Wishlist:SimFor(row.name, addon.Session:GetItem(selectedSession))
            cell.Text:SetText(addon.Wishlist.FormatPct(sim) or "")
            cell.Text:SetTextColor(S.Unpack(addon.Wishlist.GainColour(sim and sim.pct)))

            cell.Sub:SetText(addon.Wishlist.FormatAbs(sim) or "")
            cell.Sub:SetTextColor(S.Unpack(S.color.textFaint))
        end,
    })

    return ResolveSortChain(columns)
end







local function RoleName(role)
    if role == "TANK" then return T["Tank"] end
    if role == "HEALER" then return T["Healer"] end
    if role == "DAMAGER" then return T["DPS"] end
end

local function ShowMoreInfo(anchor, name)
    local qualified = addon.Player:Qualify(name)
    local main = addon.Player:Main(name)
    local isAlt = qualified and addon.Player:NameKey(main)
        ~= addon.Player:NameKey(qualified)
    local stats = addon.History:GetStats(isAlt and main or name)
    local item = addon.Session:GetItem(selectedSession)
    local previous = item and addon.History:GetWinnersOfItem(item.link) or {}
    local notes = addon.RaidTeam and addon.RaidTeam:NoteFor(name)
    local shift = IsShiftKeyDown()
    local hasNotes = notes and (notes.note or (shift and notes.officerNote))



    local coin, spentAtBoss = nil, 0
    if item and addon.BonusRoll then
        coin, spentAtBoss = addon.BonusRoll:StatusFor(name, item)
    end


    if not stats and #previous == 0 and not (notes and notes.officerNote)
        and not hasNotes and not coin and spentAtBoss == 0 then
        return
    end

    S.SideTooltip(anchor, nil, true)
    S.TooltipSection(GameTooltip, T["Candidate"])
    GameTooltip:AddLine(Ambiguate(name, "short"), 1, 1, 1)


    local record = addon.Player:Get(name)
    if addon.Specs and record.guid then
        local info = addon.Specs:Info(addon.Specs:Get(record.guid))
        if info and info.name then
            GameTooltip:AddLine(
                RoleName(info.role) and addon.Locale.Format(T["%s - %s"], info.name, RoleName(info.role))
                    or info.name,
                0.55, 0.55, 0.55)
        end
    end


    if isAlt then
        S.TooltipSection(GameTooltip, T["Alt / Main"])
        GameTooltip:AddLine(addon.Locale.Format(T["Alt of %s"],
            Ambiguate(main, "short")), 0.8, 0.8, 0.8)
    end


    if hasNotes then
        S.TooltipSection(GameTooltip, T["Guild Notes"])
        if notes.note then
            GameTooltip:AddLine(addon.Locale.Format(T["Note: %s"], notes.note),
                0.55, 0.55, 0.55, true)
        end
        if shift and notes.officerNote then
            GameTooltip:AddLine(addon.Locale.Format(T["Officer: %s"], notes.officerNote),
                0.55, 0.55, 0.55, true)
        end
    end

    if stats then
        S.TooltipSection(GameTooltip, T["Most Recent Loot"])
        for i = 1, math.min(5, #stats.recent) do
            local entry = stats.recent[i]
            local days = math.floor((GetServerTime() - (entry.epoch or 0)) / 86400)
            local when = days == 0 and T["today"] or addon.Locale.Format(T["%dd ago"], days)
            local label = entry.link and (C_Item.GetItemInfo(entry.link) or entry.link)
                or "?"
            if entry.source then when = addon.Locale.Format(T["%s *"], when) end
            GameTooltip:AddDoubleLine(
                addon.Locale.Format(T["  %s (%s)"], label,
                    addon.History.ResponseText(entry) or "?"), when,
                entry.r or 0.8, entry.g or 0.8, entry.b or 0.8, 0.6, 0.6, 0.6)
        end
    end

    if #previous > 0 then
        S.TooltipSection(GameTooltip, T["This Item Has Gone To"])
        for i = 1, math.min(5, #previous) do
            local entry = previous[i]
            GameTooltip:AddDoubleLine(addon.Locale.Format(T["  %s"],
                    Ambiguate(entry.winner or "?", "short")),
                addon.History.ResponseText(entry) or "?",
                0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
        end
    end

    if coin then
        S.TooltipSection(GameTooltip, T["Bonus Roll"])


        local coinBoss = addon.Encounter:DisplayName(coin.boss, coin.encounterID)
        GameTooltip:AddLine(
            coinBoss and addon.Locale.Format(T["  From %s"], coinBoss)
                or addon.Locale.Format(T["  Boss unknown"]),
            0.8, 0.8, 0.8)
        local ago = math.max(0, GetServerTime() - (coin.epoch or GetServerTime()))
        local minutes = math.floor(ago / 60)
        GameTooltip:AddLine(minutes <= 0
            and addon.Locale.Format(T["  Just now"])
            or addon.Locale.Format(addon.Locale.Plural{
                one = "  %d minute ago", other = "  %d minutes ago",
            }, minutes, minutes),
            0.8, 0.8, 0.8)
    elseif spentAtBoss > 0 then
        S.TooltipSection(GameTooltip, T["Bonus Roll"])
        GameTooltip:AddLine(addon.Locale.Format(addon.Locale.Plural{
            one = "  Spent %d coin at %s (not this item)",
            other = "  Spent %d coins at %s (not this item)",
        }, spentAtBoss, spentAtBoss,
            addon.Encounter:DisplayName(item.boss, item.encounterID) or T["this boss"]),
            0.8, 0.8, 0.8)
        local possible, bySpec = addon.BonusRoll:PossibleFor(name, item)
        if possible then
            GameTooltip:AddLine(addon.Locale.Format(bySpec and addon.Locale.Plural{
                one = "  %d item there for their spec", other = "  %d items there for their spec",
            } or addon.Locale.Plural{
                one = "  %d item there for their class", other = "  %d items there for their class",
            }, possible, possible), 0.8, 0.8, 0.8)
        end
    end

    GameTooltip:Show()

    S.WatchTooltipModifiers(anchor)
end







function ShowRowMenu(row, data)
    if not data or not data.name then return end
    if not addon.PlayerIsMasterLooter() then return end


    local session, runId = selectedSession, addon.Session:GetRunId()
    local item = addon.Session:GetItem(session)
    if not item then return end
    local function Same() return addon.Session:GetRunId() == runId end

    local shortName = Ambiguate(data.name, "short")
    local items = { { title = shortName } }


    if item.awarded == data.name then
        items[#items + 1] = { text = T["Undo award"], onClick = function()
            if Same() then MLFrame:Unaward(session) end
        end }
    else
        items[#items + 1] = {
            text = item.awarded and T["Re-award to this player"] or T["Award"],
            onClick = function() if Same() then MLFrame:Award(session, data.name) end end,
        }
    end


    if not item.awarded and addon.db.awardReasons
        and #addon.db.awardReasons > 0 then
        local reasons = {}
        for index, reason in ipairs(addon.db.awardReasons) do
            local reasonIndex = index
            reasons[#reasons + 1] = { text = reason.text, onClick = function()
                if Same() then MLFrame:Award(session, data.name, reasonIndex) end
            end }
        end
        items[#items + 1] = { text = T["Award for"], children = reasons }
    end

    items[#items + 1] = "-"


    local responses = {}
    for index, response in ipairs(addon.Config:Responses()) do
        local responseIndex = index
        responses[#responses + 1] = { text = response.text, onClick = function()
            addon.Session:SetResponse(session, data.name, responseIndex)
        end }
    end
    responses[#responses + 1] = { text = T["Pass"], onClick = function()
        addon.Session:SetResponse(session, data.name, nil)
    end }
    items[#items + 1] = { text = T["Set response"], children = responses }

    items[#items + 1] = { text = T["Clear rolls"], children = {
        { text = T["Clear roll on this player"], onClick = function()
            addon.Roll:SetOne(session, data.name, false)
        end },
        { text = T["Clear rolls on this item"], onClick = function()
            addon.Roll:Clear({ session })
        end },
    } }

    items[#items + 1] = { text = T["Generate roll for this player"], onClick = function()
        addon.Roll:SetOne(session, data.name, true)
    end }

    items[#items + 1] = "-"




    local candidate = data.candidate
    local responseIndex = candidate
        and (candidate.realResponse or candidate.response)
    local responseName = responseIndex
        and addon.Config:Responses()[responseIndex]
        and addon.Config:Responses()[responseIndex].text
    local rolled = candidate and candidate.roll

    local function Targets(sessions)
        local targets = {
            { text = T["This player"], onClick = function()
                addon.Roll:Ask(sessions, { data.name })
            end },
        }

        if responseName then
            targets[#targets + 1] = {
                text = addon.Locale.Format(T["Everyone on %q"], responseName),
                onClick = function()
                    addon.Roll:Ask(sessions, addon.Roll.WithResponse(item, responseIndex))
                end,
            }
        end


        if rolled then
            targets[#targets + 1] = {
                text = addon.Locale.Format(T["Everyone rolling %d"], rolled),
                onClick = function()
                    addon.Roll:Ask(sessions, addon.Roll.WithRoll(item, rolled))
                end,
            }
        end


        targets[#targets + 1] = { text = T["Everyone"], onClick = function()
            addon.Roll:Ask(sessions, nil)
        end }
        return targets
    end

    items[#items + 1] = { text = T["Ask to roll"], children = Targets({ selectedSession }) }

    local unawarded = addon.Roll.UnawardedSessions()
    if #unawarded > 1 then
        items[#items + 1] = {
            text = addon.Locale.Format(T["Ask to roll on all %d unawarded"], #unawarded),
            children = Targets(unawarded),
        }
    end


    S.ContextMenu(row, items)
end







local function SyncRows(item)
    local cache = CM.rowsFor[item]
    local membership = false
    if not cache then
        cache = { list = {}, byName = {} }
        CM.rowsFor[item] = cache
        membership = true
    end
    local list, byName, count = cache.list, cache.byName, 0
    for name, candidate in pairs(item.candidates) do
        count = count + 1
        local row = byName[name]
        if row then
            row.candidate = candidate
        else
            row = { name = name, sortKey = name, candidate = candidate, votes = 0 }
            byName[name] = row
            list[#list + 1] = row
            membership = true
        end
    end


    if count < #list then
        local kept = {}
        for _, row in ipairs(list) do
            if item.candidates[row.name] then
                kept[#kept + 1] = row
            else
                byName[row.name] = nil
            end
        end
        cache.list = kept
        membership = true
    end
    return cache, membership
end







local function HaveVotedOn(item)
    local me = addon.Player:GetFullName("player")
    if not me then return false end
    for _, candidate in pairs(item.candidates) do
        if candidate.voters[me] then return true end
    end
    return false
end




CM.NO_ITEMS = {}

function CM.RunItems()
    return addon.Session:IsRunning() and addon.Session:GetItems() or CM.NO_ITEMS
end


function CM.HasWork()
    local master = addon.PlayerIsMasterLooter()
    for _, item in ipairs(addon.Session:GetItems()) do
        if not item.awarded and not item.removed
            and (master or not HaveVotedOn(item)) then
            return true
        end
    end
    return false
end


local warnedRun
function CM.CheckOpened()
    if frame and frame:IsShown() then return end
    local runId = addon.Session:GetRunId()
    if warnedRun == runId then return end
    warnedRun = runId
    addon.Log:W("UI", "run started - the council window did not open; /slc vote opens it")
end



function CM.SetPick(name)
    CM.pick = name
    if table_ then Tbl.SetPicked(table_, name) end
    if CM.table then Tbl.SetPicked(CM.table, name) end
    if CM.fullTables then
        for _, t in pairs(CM.fullTables) do Tbl.SetPicked(t, name) end
    end
end

function CM.TogglePick(name)
    CM.SetPick(CM.pick ~= name and name or nil)
    if not CM.hovered then
        againstFor = CM.pick
        addon.Callbacks:Invalidate("councilAgainst")
    end
end



function CM.NextOpen(from)
    local items = CM.RunItems()
    local count = #items
    for step = 1, count - 1 do
        local index = (from - 1 + step) % count + 1
        local item = items[index]
        if item and not item.awarded and not item.removed then return index end
    end
    return nil
end

function CM.RevealStrip(index)
    local bar = runScroll and runScroll.ScrollBar
    local viewport = runScroll and runScroll.Viewport
    if not bar or not viewport then return end
    local top = (index - 1) * STRIP_STEP
    local height = viewport:GetHeight() or 0
    local _, maximum = bar:GetMinMaxValues()
    local current = bar:GetValue() or 0
    local target
    if top < current then
        target = top
    elseif top + STRIP_ROW_H > current + height then
        target = top + STRIP_ROW_H - height
    end
    if target then bar:SetValue(math.max(0, math.min(maximum or 0, target))) end
end



local TOAST_HOLD = 1
local TOAST_FADE = 5
local TOAST_ICON = 34
local TOAST_PAD_X = 16
local TOAST_PAD_Y = 12
local TOAST_GAP = 12
local TOAST_LINE = 4
local TOAST_MIN_W = 200

function CM.BuildToast()
    local toast = CreateFrame("Frame", nil, frame)
    toast:SetFrameLevel(frame:GetFrameLevel() + 20)
    toast:SetClampedToScreen(true)
    toast:EnableMouse(false)
    toast:Hide()
    toast:SetPoint("CENTER", frame, "TOP", 0, 0)
    S.Fill(toast, S.color.canvas, 0.97)
    toast.Edge = S.Border(toast, S.color.accent, "OVERLAY")

    local icon = S.ItemIcon(toast, TOAST_ICON)
    icon:EnableMouse(false)
    icon:SetPoint("LEFT", toast, "LEFT", TOAST_PAD_X, 0)
    toast.Icon = icon

    local name = S.Label(toast, S.fontBody, "LEFT")
    name:SetPoint("LEFT", icon, "RIGHT", TOAST_GAP, 0)
    toast.Name = name

    local title = S.Label(toast, S.fontHeading, "LEFT")
    title:SetPoint("BOTTOMLEFT", name, "TOPLEFT", 0, TOAST_LINE)
    title:SetTextColor(S.Unpack(S.color.text))
    title:SetText(addon.Locale.Upper(T["Loot Awarded"]))
    toast.Title = title

    local who = S.Label(toast, S.fontSmall, "LEFT")
    who:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -TOAST_LINE)
    who:SetTextColor(S.Unpack(S.color.textMuted))
    toast.Who = who

    local fade = toast:CreateAnimationGroup()
    local out = fade:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0)
    out:SetStartDelay(TOAST_HOLD)
    out:SetDuration(TOAST_FADE)
    fade:SetScript("OnFinished", function() toast:Hide() end)
    toast.Fade = fade

    CM.toast = toast
end

function CM.ShowToast(item, winner)
    local toast = CM.toast
    if not toast or not frame:IsShown() or not item or not item.link or not winner then return end
    local name, _, quality = C_Item.GetItemInfo(item.link)
    toast.Icon:SetItem(item.link)
    toast.Icon:SetQualityBorder(quality)
    toast.Name:SetText(S.Colorize(S.color.accent, name or item.link))
    toast.Who:SetText(addon.Locale.Format(T["Awarded to %s"],
        S.Colorize(S.color.accent, Ambiguate(winner, "short"))))
    toast.Edge:SetColor(S.color.accent)
    local width = math.max(toast.Title:GetStringWidth() or 0, toast.Name:GetStringWidth() or 0,
        toast.Who:GetStringWidth() or 0)
    local height = (toast.Title:GetStringHeight() or 0) + (toast.Name:GetStringHeight() or 0)
        + (toast.Who:GetStringHeight() or 0) + 2 * TOAST_LINE
    P.Size(toast, math.max(TOAST_MIN_W, TOAST_PAD_X + TOAST_ICON + TOAST_GAP + math.ceil(width) + TOAST_PAD_X),
        math.max(TOAST_ICON, math.ceil(height)) + 2 * TOAST_PAD_Y)
    toast.Fade:Stop()
    toast:Show()
    toast.Fade:Play()
end

function CM.HideToast()
    local toast = CM.toast
    if not toast then return end
    toast.Fade:Stop()
    toast:Hide()
end



local function PaintStripButton(button, index, item)
    if button.slcItem ~= item or button.slcLink ~= item.link then
        button.slcItem, button.slcLink, button.slcName = item, item.link, nil
        button.Icon:SetItem(item.link)
    end
    local voted = CM.votedOn[item]
    if voted == nil then
        voted = HaveVotedOn(item)
        CM.votedOn[item] = voted
    end
    if button.slcVoted ~= voted then
        button.slcVoted = voted
        button.Icon.Texture:SetDesaturated(voted)
    end
    if not button.slcName then
        local name = C_Item.GetItemInfo(item.link)
        button.slcNameMissing = name == nil
        button.slcName = name
        button.Name:SetText(name or item.link or T["Unknown item"])
    end

    local removed = item.removed and not item.awarded
    local looting = not removed and item.gone == "pending" and not item.awarded
    local missing = not removed and not looting and item.gone and not item.awarded


    local owed = not removed and not looting and not missing and item.owed and not item.awarded
    button.State:SetText(item.awarded and T["AWARDED"] or removed and T["REMOVED"]
        or looting and T["LOOTING"] or missing and T["MISSING"] or owed and T["OWED"]
        or T["QUEUED"])
    button.State:SetTextColor(S.Unpack(item.awarded and S.color.good
        or (removed or missing) and S.color.dangerText
        or (looting or owed) and S.color.warn
        or index == selectedSession and S.color.accentPale or S.color.textFaint))
    button.slcSelected = index == selectedSession
    button.RemovedWash:SetShown(removed)
    local washed = button.slcSelected and not removed
    local a = S.color.accent
    if washed and (button.slcWashR ~= a[1] or button.slcWashG ~= a[2]
        or button.slcWashB ~= a[3]) then
        button.slcWashR, button.slcWashG, button.slcWashB = a[1], a[2], a[3]
        button.Fill:SetVertexColor(a[1], a[2], a[3], STRIP_WASH_A)
    end
    button.Fill:SetShown(washed)
    button.Mark:SetColorTexture(S.Unpack(removed and S.color.danger or S.color.accent))
    button.Mark:SetShown(button.slcSelected or removed)
    if button.slcSelected then button.Hover:Hide() end
    button.Name:SetTextColor(S.Unpack(button.slcSelected
        and S.color.accentPale or S.color.textMuted))
    button:Show()
end



local function RefreshStrip(scope)
    local items = CM.RunItems()
    sessionStrip.buttons = sessionStrip.buttons or {}
    local painted = CM.stripCount or 0
    local missing = false

    for index, item in ipairs(items) do
        local button = sessionStrip.buttons[index]
        local fresh = not button
        if fresh then
            button = CreateFrame("Button", nil, sessionStrip)
            button:SetSize(STRIP_ROW_W, STRIP_ROW_H)
            button:SetPoint("TOPLEFT", 0, -(index - 1) * STRIP_STEP)


            button.Fill = S.RoundFill(button, STRIP_WASH_BASE, S.radius.SM,
                "BACKGROUND", 0)
            button.Fill:Hide()

            button.Mark = button:CreateTexture(nil, "ARTWORK")
            P.Size(button.Mark, 2, nil)
            button.Mark:SetPoint("TOPLEFT")
            button.Mark:SetPoint("BOTTOMLEFT")
            button.Mark:SetColorTexture(S.Unpack(S.color.accent))
            P.Crisp(button.Mark)
            button.Mark:Hide()


            local d = S.color.danger
            button.RemovedWash = S.RoundFill(button, { d[1], d[2], d[3], 0.16 },
                S.radius.SM, "BACKGROUND", 0)
            button.RemovedWash:Hide()

            button.Hover = S.RoundFill(button, S.color.rowHover, S.radius.SM,
                "BACKGROUND", 1)
            button.Hover:Hide()
            button:HookScript("OnEnter", function(self)
                if not self.slcSelected then self.Hover:Show() end
            end)
            button:HookScript("OnLeave", function(self) self.Hover:Hide() end)

            button.Icon = S.ItemIcon(button, STRIP_ICON)
            button.Icon:SetPoint("LEFT", 5, 0)
            button.Name = S.Label(button, S.fontSmall, "LEFT")
            button.Name:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
            button.State = S.Label(button, S.fontHint, "RIGHT")
            button.State:SetPoint("RIGHT", button, "RIGHT", -STRIP_STATE_PAD, 0)
            button.State:SetSize(CM.STRIP_STATE_W, 38)
            button.Name:SetPoint("RIGHT", button.State, "LEFT", -6, 0)



            local buttonIndex = index
            local function Click(_, mouse)
                if mouse == "RightButton" then
                    if addon.PlayerIsMasterLooter() then MLFrame:ConfirmRemove(buttonIndex) end
                    return
                end
                local buttonItem = addon.Session:GetItems()[buttonIndex]
                if buttonItem and S.ItemModifiedClick(buttonItem.link) then return end
                selectedSession = buttonIndex
                MLFrame:Refresh()
            end
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:SetScript("OnClick", Click)
            button.Icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button.Icon:SetScript("OnClick", Click)

            sessionStrip.buttons[index] = button
        end
        if not scope or fresh or index > painted or scope.sessions[index]
            or button.slcItem ~= item or button.slcNameMissing then
            PaintStripButton(button, index, item)
        end
        missing = missing or button.slcNameMissing or false
    end

    if not scope or #items ~= painted then
        for index = #items + 1, #sessionStrip.buttons do
            sessionStrip.buttons[index]:Hide()
        end
        if runScroll then runScroll:SetContentHeight(math.max(1, #items * STRIP_STEP)) end
        CM.stripCount = #items
    end
    return missing
end







local function RefreshEndButton()


    local label = addon.PlayerIsMasterLooter() and addon.Session:IsRunning() and T["End run"] or T["Close"]
    if CM.endLabel ~= label then
        CM.endLabel = label
        endButton:SetLabel(label)
    end
end



function MLFrame:ConfirmEndRun()
    if not addon.PlayerIsMasterLooter() or not addon.Session:IsRunning() then return end
    S = S or addon.Style
    local runId = addon.Session:GetRunId()
    local unawarded = 0
    for _, item in ipairs(addon.Session:GetItems()) do
        if not item.awarded and not item.removed then
            unawarded = unawarded + 1
        end
    end
    local function EndRun()
        if addon.Session:GetRunId() ~= runId or not addon.PlayerIsMasterLooter()
            or not addon.Session:IsRunning() then return end
        addon.Session:End()
        if frame then frame:Hide() end
    end
    if unawarded == 0 then
        EndRun()
        return
    end
    S.Confirm({
        title = T["End run?"],
        body = addon.Locale.Format(addon.Locale.Plural{
            one = "End this run for everyone? %d item is still unawarded.",
            other = "End this run for everyone? %d items are still unawarded.",
        }, unawarded, unawarded),
        accept = T["End run"],
        onAccept = EndRun,
    })
end



local function LowerEquipped(candidate)
    local best, bestName, bestQuality, bestLevel
    for _, itemString in ipairs({ candidate.gear1, candidate.gear2 }) do
        if itemString then
            local name, _, quality = C_Item.GetItemInfo(itemString)
            local ilvl = addon.Gear:ItemLevel(itemString)
            if not best
                or (ilvl and (not bestLevel or ilvl < bestLevel)) then
                best, bestName, bestQuality, bestLevel =
                    itemString, name, quality, ilvl
            end
        end
    end
    return best, bestName, bestQuality, bestLevel
end

local function PaintAgainst(name)
    if not againstName or not againstDetail then return end
    againstFor = name
    CM.againstLoading = false

    local item = addon.Session:GetItem(selectedSession)
    local candidate = item and name and item.candidates[name]
    if not candidate then


        if CM.againstBlank then return end
        CM.againstBlank = true
        againstIcon:SetItem(nil)
        againstIcon:SetQualityBorder(nil)
        againstIcon:Hide()
        againstName:SetText(T["Hover or click a candidate"])
        againstName:SetTextColor(S.Unpack(S.color.textMuted))
        againstDetail:SetText(T["Their equipped item and upgrade will appear here."])
        againstDetail:SetTextColor(S.Unpack(S.color.textFaint))
        againstDelta:SetText("\226\128\148")
        againstDelta:SetTextColor(S.Unpack(S.color.textMuted))
        return
    end
    CM.againstBlank = false

    local itemString, equipped, quality, equippedLevel = LowerEquipped(candidate)

    local diff = candidate.diff
    againstDelta:SetText(diff and ((diff > 0 and "+" or "") .. diff) or "\226\128\148")
    againstDelta:SetTextColor(S.Unpack(diff and diff > 0 and S.color.good
        or diff and diff < 0 and S.color.bad or S.color.textMuted))

    if not itemString then


        againstIcon:SetItem(nil)
        againstIcon:SetQualityBorder(nil)
        againstIcon:Hide()
        againstName:SetText(Ambiguate(name, "short"))
        againstName:SetTextColor(S.Unpack(S.color.text))
        againstDetail:SetText(T["nothing equipped in this slot"])
        againstDetail:SetTextColor(S.Unpack(S.color.textFaint))
        return
    end



    againstIcon:SetItem(itemString)
    againstIcon:SetQualityBorder(quality)
    againstIcon:Show()

    if equipped then
        againstName:SetText(equipped)


        local r, g, b
        if quality then r, g, b = C_Item.GetItemQualityColor(quality) end
        if r then
            againstName:SetTextColor(r, g, b)
        else
            againstName:SetTextColor(S.Unpack(S.color.text))
        end
        againstDetail:SetText(equippedLevel
            and addon.Locale.Format(T["equipped  \194\183  ilvl %d"], equippedLevel) or T["equipped"])
        againstDetail:SetTextColor(S.Unpack(S.color.textFaint))
    else

        CM.againstLoading = true
        againstName:SetText(T["Loading item..."])
        againstName:SetTextColor(S.Unpack(S.color.textMuted))
        againstDetail:SetText(T["equipped"])
        againstDetail:SetTextColor(S.Unpack(S.color.textFaint))
    end
end


local function RefreshAgainst(name)
    PaintAgainst(name)
    CM.WatchItemInfo()
end



local function BossLineText(item)
    if not item then return "" end
    local parts = {}


    local boss = addon.Encounter:DisplayName(item.boss, item.encounterID)
    if type(boss) == "string" and boss ~= "" then
        parts[#parts + 1] = S.Colorize(S.color.accent, boss)
    end
    local id = tonumber(item.difficultyID)
        or addon.Encounter:DifficultyFor(item.boss, item.encounterID)
    if id and id > 0 then
        local name = GetDifficultyInfo(id)
        if type(name) == "string" and name ~= "" then
            local quality = id == 16 and Enum.ItemQuality.Legendary
                or id == 15 and Enum.ItemQuality.Epic
                or id == 14 and Enum.ItemQuality.Rare
                or id == 17 and Enum.ItemQuality.Uncommon
            if quality then
                local r, g, b = C_Item.GetItemQualityColor(quality)
                name = S.Colorize({ r, g, b }, name)
            end
            parts[#parts + 1] = name
        end
    end
    return table.concat(parts, "  \194\183  ")
end




local function PaintFeatured(item)
    selectedSet = nil
    if item then
        local itemID = addon.Storage.ItemID(item.link)
        if itemID then
            local isToken = addon.Loot and addon.Loot:IsTierToken(itemID) or false
            selectedSet = {
                itemID = itemID,
                isToken = isToken,
                setID = not isToken and select(16, C_Item.GetItemInfo(item.link)) or nil,
            }
        end
    end

    local removed = item and item.removed and not item.awarded
    local looting = item and not removed and item.gone == "pending" and not item.awarded
    local missing = item and not removed and not looting and item.gone and not item.awarded
    local owed = item and not removed and not looting and not missing and item.owed
        and not item.awarded


    local detail = not CM.active
    itemIcon.Halo:SetShown(detail and removed and true or false)
    voteStatus.RemovedTag:SetShown(detail and (removed or looting or missing or owed) and true
        or false)
    voteStatus.RemovedTag:SetText(removed and T["Removed"] or looting and T["Not looted yet"]
        or missing and T["Missing"]
        or owed and addon.Locale.Format(T["Owed to %s"], Ambiguate(item.owed.w, "short")) or "")
    voteStatus.RemovedTag:SetTextColor(S.Unpack((looting or owed) and S.color.warn
        or S.color.dangerText))

    CM.featuredMissing = false
    itemIcon:SetShown(item ~= nil and detail)
    if item then
        itemIcon:SetItem(item.link)
        local name, _, quality = C_Item.GetItemInfo(item.link)
        local ilvl = addon.Gear:ItemLevel(item.link)
        CM.featuredMissing = name == nil
        itemIcon:SetQualityBorder(quality)
        if removed or missing then itemIcon:SetBorderColor(S.color.danger) end
        itemName:SetText(name or item.link or "?")
        itemBoss:SetText(BossLineText(item))

        local answered, totalCandidates = 0, 0
        for _, candidate in pairs(item.candidates) do
            totalCandidates = totalCandidates + 1
            local status = candidate.status
            if status == "AWARDED" then status = candidate.realStatus end
            if status == "RESPONDED" or status == "PASS" then answered = answered + 1 end
        end
        answeredCount:SetText(addon.Locale.Format(T["%d of %d"], answered, totalCandidates))
        answeredBar:SetProgress(totalCandidates > 0 and answered / totalCandidates or 0,
            true)

        if item.awarded then

            local who = Ambiguate(item.awarded, "short")
            voteStatus:SetTextColor(S.Unpack(S.color.text))
            if item.delivered then
                voteStatus:SetText(S.Colorize(S.color.good,
                    addon.Locale.Format(T["Delivered to %s"], who)))
            else
                voteStatus:SetText(S.Colorize(S.color.accent,
                    addon.Locale.Format(T["Awarded to %s - awaiting trade"], who)))
            end
        else


            voteStatus:SetText(ilvl and addon.Locale.Format(T["ilvl %d"], ilvl) or "")
            voteStatus:SetTextColor(S.Unpack(S.color.textFaint))
        end
    else
        itemIcon:SetItem(nil)
        itemName:SetText(addon.Session:IsRunning() and T["No items"]
            or T["No loot session running"])
        itemBoss:SetText("")
        voteStatus:SetText("")
        answeredCount:SetText(T["0 of 0"])
        answeredBar:SetProgress(0, true)
    end
end


function CM.PaintLive()
    local state = addon.Session:HasEnded() and "ended"
        or addon.Session:IsRunning() and "live" or "idle"
    if CM.liveKey == state then return end
    CM.liveKey = state
    local text = state ~= "idle" and (state == "ended" and T["ENDED"] or T["LIVE"]) or nil
    frame:SetTag(text, state == "ended" and S.color.textMuted or S.color.good)
end




function CM.ShowCount()
    local chip = CM.countChip
    if not chip then return end
    local text = CM.counts and CM.counts[CM.tab]
    if text == "" then text = nil end
    if CM.countText == text then return end
    CM.countText = text
    if text then chip:SetText(addon.Locale.Upper(text)) end
    chip:SetShown(text ~= nil)
    P.Size(frame.Badge, math.max(CM.countSlot, text and math.ceil(chip:GetWidth()) or 0), nil)
    if frame.ClampTitle then P.AfterLayout(frame.ClampTitle) end
end

function CM.SetCount(key, text)
    CM.counts = CM.counts or {}
    CM.counts[key] = text
    if CM.tab == key then CM.ShowCount() end
end



local function PaintTallies(items, item, full)
    CM.SetCount("council", #items > 0 and addon.Locale.Format(T["%d of %d"],
        math.min(selectedSession, #items), #items) or nil)
    CM.PaintLive()



    local total = 0
    local decided = 0
    for _, entry in ipairs(items) do

        if not entry.removed or entry.awarded then
            total = total + 1
            if entry.awarded then decided = decided + 1 end
        end
    end


    local count = addon.Locale.Format(T["%d of %d awarded"], decided, total)
    if CM.runCount ~= count then
        CM.runCount = count
        runCount:SetText(count)
    end

    RefreshEndButton()
    local isML = addon.PlayerIsMasterLooter() and true or false
    menuHint:SetShown(isML)

    rollButton:SetShown(isML)

    local footerKey = isML and 1 or 0
    if full or CM.footerKey ~= footerKey then
        CM.footerKey = footerKey
        footer:Reflow()
    end
end




local function PaintRows(scope, item)
    local active = ActiveTable()
    if not item then
        Tbl.SetData(active, {}, paintedSession == selectedSession)
        paintedSession = selectedSession
        return
    end

    local cache, membership = SyncRows(item)
    local rows = cache.list
    if not scope or membership or active.data ~= rows then
        for _, row in ipairs(rows) do
            row.votes = addon.Session:GetVoteCount(selectedSession, row.name)
        end
        Tbl.SetData(active, rows, paintedSession == selectedSession)
    else
        local kinds = scope.kinds
        local every = scope.allCandidates or scope.allKinds
            or kinds.award or kinds.item or kinds.run or kinds.status
            or (kinds.vote and addon.Config:Vote().hideVotes)
        local changed = {}
        for _, row in ipairs(rows) do
            if every or scope.candidates[row.name] then
                row.votes = addon.Session:GetVoteCount(selectedSession, row.name)
                changed[#changed + 1] = row
            end
        end
        Tbl.UpdateRows(active, changed)
    end
    paintedSession = selectedSession
end



function MLFrame:Paint(scope)
    if not frame or not frame:IsShown() or CM.tab ~= "council" then return end


    if CM.SyncWishlist() then scope = nil end

    local items = CM.RunItems()
    if selectedSession > #items then selectedSession = 1 end

    if scope and (paintedSession ~= selectedSession or scope.kinds.coin) then
        scope = nil
    end


    local votedOn = CM.votedOn
    if not scope then
        for entry in pairs(votedOn) do votedOn[entry] = nil end
    elseif scope.allKinds or scope.kinds.vote then
        for session in pairs(scope.sessions) do
            local entry = items[session]
            if entry then votedOn[entry] = nil end
        end
    end
    local stripMissing = RefreshStrip(scope)

    local item = items[selectedSession]
    if CM.pick and paintedSession ~= selectedSession then CM.SetPick(nil) end


    local retry = CM.featuredMissing
    local touched = not scope or scope.sessions[selectedSession] or retry
    if touched then PaintFeatured(item) end

    PaintTallies(items, item, not scope)

    if touched then
        PaintRows(not retry and scope or nil, item)

        local hovered
        for _, row in ipairs(ActiveTable().rows) do
            if row.rowData and row:IsMouseOver() then
                hovered = row.rowData.name
                break
            end
        end
        RefreshAgainst(hovered or CM.pick)
    end
    CM.namesMissing = stripMissing or CM.featuredMissing
    CM.WatchItemInfo()

    if not scope then MLFrame:UpdateTimer() end
end


function MLFrame:Refresh()
    addon.Callbacks:Invalidate("council")
    addon.Callbacks:PaintNow("council")
end



function MLFrame:Present()
    if not CM.Ensure() then return end
    CM.ShowTab("council")
    addon.Callbacks:Invalidate("council")
    frame:Show()
    addon.Callbacks:PaintNow("council")
end


function MLFrame:ShowQueue()
    if not CM.ready or not CM.Ensure() or not CM.QueueAllowed() then return false end
    CM.ShowTab("queue")
    frame:Show()
    return true
end



function MLFrame:ShowResponse(forced)
    if not CM.ready or not CM.Ensure() or not (CM.responseOn and CM.ResponseSeat()) then
        return false
    end
    if forced and CM.tab ~= "response" then addon.Style.PlayNotification("responseFrame") end
    CM.ShowTab("response")
    frame:Show()
    return true
end


function MLFrame:ResponseHost()
    if not CM.ResponseSeat() or not CM.Ensure() then return nil end
    return CM.responseHost
end

function MLFrame:ResponseSeat()
    return CM.ResponseSeat()
end


function MLFrame:SetResponseAvailable(on)
    local was = CM.responseOn
    CM.responseOn = on and true or false
    if not CM.responseOn then
        CM.leftResponseAt, CM.wantResponse = nil, nil
    elseif not was and CM.tab ~= "response" then
        CM.ArmPulse()
    end
    CM.SyncResponseTab()
    CM.SyncPulse()
end

function MLFrame:QueueShown()
    return frame ~= nil and frame:IsShown() and CM.tab == "queue"
end


function MLFrame:Close()
    if frame then frame:Hide() end
end


function MLFrame:UpdateTimer()
    if not frame or not frame:IsShown() then return end
    CM.PaintLive()

    local left = addon.Session:GetTimeLeft()
    local duration = addon.Session:GetTimerDuration()

    if not left or not duration or duration <= 0 then
        timerText:SetText("")
        timerLabel:SetText("")
        return
    end

    local fraction = left / duration


    if fraction <= 0 then

        timerLabel:SetText(T["TIME UP"])
        timerLabel:SetTextColor(S.Unpack(S.color.bad))
        timerText:SetFontObject(S.fontNum)
        S.PinClockWidth(timerText)
        timerText:SetText(Clock(0))
        timerText:SetTextColor(S.Unpack(S.color.bad))
        return
    end

    local closing = fraction <= TIMER_WARN_AT
    timerLabel:SetText(closing and T["CLOSING"] or T["TIME TO RESPOND"])
    timerLabel:SetTextColor(S.Unpack(closing and S.color.warn
        or S.color.textFaint))

    timerText:SetFontObject(S.fontNum)
    S.PinClockWidth(timerText)
    timerText:SetText(Clock(left))
    timerText:SetTextColor(S.Unpack(closing and S.color.warn
        or S.color.accentPale))
end








function CM.Build()
    local T = addon.Locale.Text
    MLFrame:FitTextWidths()


    hasWishlist = (addon.Wishlist and addon.Wishlist:IsAvailable()) or false


    CM.active = addon.db.mlCompact and true or false
    frame = S.Window("SimpleLootCouncilMLFrame", "ml", WindowWidth(false),
        FULL_RAIL_H, T["Simple Loot Council"], WINDOW_OPTIONS)
    CM.FULL_H = FULL_RAIL_H + frame.HeaderHeight
    P.Size(frame, nil, CM.FULL_H)
    frame:RestorePosition()
    CM.BuildToast()
    local content = frame.Content

    CM.councilPane = CreateFrame("Frame", nil, content)
    CM.councilPane:SetAllPoints(content)
    CM.queuePane = CreateFrame("Frame", nil, content)
    CM.queuePane:SetAllPoints(content)
    CM.queuePane:Hide()
    CM.tab = "council"



    local strip = frame.Badge:GetParent()
    timerText = S.Label(strip, S.fontNum, "RIGHT")
    timerText:SetPoint("RIGHT", frame.Badge, "LEFT", -S.size.GAP, -1)
    timerLabel = S.Label(strip, S.fontHeading, "RIGHT")
    timerLabel:SetPoint("RIGHT", timerText, "LEFT", -6, 0)

    CM.countChip = S.Chip(frame.Tag:GetParent(), "", S.color.textMuted,
        { height = frame.Tag:GetHeight(), font = S.fontTag,
            padding = frame.TagPadding or 9, square = true })
    CM.countChip:SetPoint("RIGHT", frame.Close, "LEFT", -S.size.GAP, 0)
    CM.countChip:Hide()
    CM.countSlot = frame.Badge:GetWidth()

    footer = S.FooterBar(frame)


    local rail = CreateFrame("Frame", nil, CM.councilPane)
    rail:SetPoint("TOPLEFT", content, "TOPLEFT")
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", S.size.PAD,
        S.size.FOOTER_H + CM.RAIL_GAP_V)
    rail:SetWidth(RAIL_W)

    S.Panel(rail, S.color.rail, nil, S.radius.MD, S.color.rule)


    itemIcon = S.ItemIcon(rail, 44)
    itemIcon:SetPoint("TOPLEFT", 14, -13)
    itemName = S.Label(rail, S.fontBody, "LEFT")
    itemName:SetPoint("TOPLEFT", itemIcon, "TOPRIGHT", 10, -2)
    itemName:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)
    voteStatus = S.Label(rail, S.fontSmall, "LEFT")
    voteStatus:SetPoint("TOPLEFT", itemName, "BOTTOMLEFT", 0, -6)
    voteStatus:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)


    voteStatus.RemovedTag = S.Label(rail, S.fontSmall, "RIGHT")
    voteStatus.RemovedTag:SetPoint("TOPRIGHT", voteStatus, "TOPRIGHT", 0, 0)
    voteStatus.RemovedTag:SetTextColor(S.Unpack(S.color.dangerText))
    voteStatus.RemovedTag:Hide()
    local d = S.color.danger
    itemIcon.Halo = S.RoundFill(rail, { d[1], d[2], d[3], 0.45 }, S.radius.SM, "ARTWORK", 0)
    itemIcon.Halo:ClearAllPoints()
    itemIcon.Halo:SetPoint("TOPLEFT", itemIcon, "TOPLEFT", -3, 3)
    itemIcon.Halo:SetPoint("BOTTOMRIGHT", itemIcon, "BOTTOMRIGHT", 3, -3)
    itemIcon.Halo:Hide()


    itemBoss = S.Label(rail, S.fontSmall, "LEFT")
    itemBoss:SetPoint("TOPLEFT", itemIcon, "BOTTOMLEFT", 0, -6)
    itemBoss:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)


    answeredCount = S.Label(rail, S.fontNum, "RIGHT")
    answeredCount:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -RAIL_EDGE, -RAIL_ANSWERED)

    answeredText = S.Label(rail, S.fontHeading, "LEFT")
    answeredText:SetPoint("TOPLEFT", 14, -RAIL_ANSWERED)


    answeredText:SetPoint("RIGHT", answeredCount, "LEFT", -S.size.GAP, 0)
    answeredText:SetText(T["ANSWERED"])

    answeredBar = S.ProgressBar(rail, 3)
    answeredBar:SetPoint("TOPLEFT", answeredText, "BOTTOMLEFT", 0, -7)
    answeredBar:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)


    local answeredRule = S.FadeRule(rail)
    answeredRule:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -RAIL_ANSWERED_RULE)
    answeredRule:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)


    local compareTitle = S.Label(rail, S.fontHeading, "LEFT")
    compareTitle:SetPoint("TOPLEFT", 14, -RAIL_COMPARE_TITLE)
    compareTitle:SetText(T["AGAINST EQUIPPED"])

    local compare = CreateFrame("Frame", nil, rail)
    compare:SetPoint("TOPLEFT", 14, -RAIL_COMPARE)
    compare:SetPoint("TOPRIGHT", -RAIL_EDGE, -RAIL_COMPARE)
    compare:SetHeight(COMPARE_H)

    S.Panel(compare, S.color.cardLift, nil, S.radius.MD, S.color.rule)

    againstIcon = S.ItemIcon(compare, 24)
    againstIcon:SetPoint("TOPLEFT", compare, "TOPLEFT", 10, -10)
    againstIcon:Hide()


    againstName = S.Label(compare, S.fontBody, "LEFT")
    againstName:SetPoint("TOPLEFT", againstIcon, "TOPRIGHT", 9, 1)
    againstName:SetPoint("RIGHT", compare, "RIGHT", -10, 0)
    againstDetail = S.Label(compare, S.fontSmall, "LEFT")
    againstDetail:SetPoint("TOPLEFT", againstName, "BOTTOMLEFT", 0, -3)
    againstDetail:SetPoint("RIGHT", compare, "RIGHT", -10, 0)


    againstDelta = S.Label(compare, S.fontNumHuge, "LEFT")
    againstDelta:SetPoint("TOPLEFT", againstDetail, "BOTTOMLEFT", 0, -4)
    againstDelta:SetPoint("RIGHT", compare, "RIGHT", -10, 0)
    againstDelta:SetHeight(22)


    local runRule = S.FadeRule(rail)
    runRule:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -RAIL_RUN_RULE)
    runRule:SetPoint("RIGHT", rail, "RIGHT", -RAIL_EDGE, 0)


    runCount = S.Label(rail, S.fontSmall, "RIGHT")
    runCount:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -RAIL_EDGE, -RAIL_RUN_TITLE)

    local runTitle = S.Label(rail, S.fontHeading, "LEFT")
    runTitle:SetPoint("TOPLEFT", 14, -RAIL_RUN_TITLE)
    runTitle:SetPoint("RIGHT", runCount, "LEFT", -S.size.GAP, 0)
    runTitle:SetText(T["CURRENT SESSION"])

    runScroll = S.ScrollRegion(rail, STRIP_STEP)
    sessionStrip = runScroll.Content
    sessionStrip.slcWidth = STRIP_ROW_W




    local function WireTable(t)
        CM.ApplySort(t)
        t.onSort = CM.RecordSort
        t:SetPoint("TOPLEFT", rail, "TOPRIGHT", RAIL_GAP, t.slcLift or 0)

        CM.AnchorTableScrollbar(t)
        t.hoverParts = true
        t.onEnter = function(row, data)
            if data and data.name then
                CM.hovered = data.name
                RefreshAgainst(data.name)
                ShowMoreInfo(row, data.name)
            end
        end

        t.onLeave = function(row)
            CM.hovered = nil
            if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
            againstFor = CM.pick
            addon.Callbacks:Invalidate("councilAgainst")
        end
        t.onClick = function(row, data, button)
            if button == "RightButton" then
                ShowRowMenu(row, data)
            elseif button == "LeftButton" and data.name then
                CM.TogglePick(data.name)
            end
        end
        t.onHeaderMenu = function() CM.ShowColumnMenu(t.header, t) end
        Tbl.SetHidden(t, CM.HiddenColumns())
        Tbl.SetPicked(t, CM.pick)
        return t
    end

    local function BuildFullTable()
        return WireTable(Tbl.Create(CM.councilPane, BuildColumns(false), CM.FULL_ROWS,
            CM.RowHeight(false)))
    end

    table_ = BuildFullTable()
    CM.table = Tbl.Create(CM.councilPane, BuildColumns(true), CM.ROWS, CM.RowHeight(true))
    CM.table.slcLift = CM.HeaderLift()

    Tbl.SetFilter(CM.table, function(row)
        return not (row.candidate and row.candidate.status == "PASS")
    end)
    WireTable(CM.table)




    CM.fullTables = { [hasWishlist] = table_ }
    function CM.SyncWishlist()
        local want = (addon.Wishlist and addon.Wishlist:IsAvailable()) or false
        if want == hasWishlist then return false end
        hasWishlist = want
        table_:Hide()
        table_ = CM.fullTables[want] or BuildFullTable()
        CM.fullTables[want] = table_
        CM.ApplySort(table_)
        table_:SetShown(not CM.active)

        if not CM.active then CM.FitWindow() end
        addon.Log:D("UI", "council table rebuilt, wishlist columns", want and "shown" or "hidden")
        return true
    end

    endButton = S.Button(footer, T["End run"], {
        width = 135, primary = true, labelPad = S.size.BTN_PAD_FOOTER,
    })
    footer:Add(endButton, true)
    endButton:SetScript("OnClick", function()

        if not addon.PlayerIsMasterLooter() or not addon.Session:IsRunning() then
            frame:Hide()
            return
        end
        MLFrame:ConfirmEndRun()
    end)


    rollButton = S.Button(footer, T["Rolls"], { width = 100, labelPad = S.size.BTN_PAD_FOOTER })
    footer:Add(rollButton, true)
    rollButton:SetScript("OnClick", function(self)
        local unawarded = addon.Roll.UnawardedSessions()

        local items = {
            { title = T["Rolls"] },
            { text = T["Ask everyone to roll"], onClick = function()
                addon.Roll:Ask({ selectedSession }, nil)
            end },

            { text = T["Generate rolls for this item"], onClick = function()
                addon.Roll:Random({ selectedSession })
            end },
            { text = T["Clear rolls on this item"], onClick = function()
                addon.Roll:Clear({ selectedSession })
            end },
        }

        if #unawarded > 1 then
            items[#items + 1] = "-"
            items[#items + 1] = {
                text = addon.Locale.Format(T["All %d unawarded items"], #unawarded),
                children = {
                    { text = T["Ask everyone to roll"], onClick = function()
                        addon.Roll:Ask(unawarded, nil)
                    end },
                    { text = T["Generate rolls"], onClick = function()
                        addon.Roll:Random(unawarded)
                    end },
                    { text = T["Clear rolls"], onClick = function()
                        addon.Roll:Clear(unawarded)
                    end },
                },
            }
        end

        S.ContextMenu(self, items)
    end)


    CM.button = S.Button(footer, T["Compact"], { width = 100, labelPad = S.size.BTN_PAD_FOOTER })
    footer:Add(CM.button, true)
    CM.button:SetScript("OnClick", function()
        MLFrame:SetCompact(not CM.active)
    end)



    menuHint = footer:AddText(S.fontHint)
    menuHint:SetText(T["Right-click a row to award, set a response, or ask for a roll"])
    menuHint:Hide()


    local railDetail = {
        itemIcon, itemName, voteStatus, itemBoss,
        answeredText, answeredCount, answeredBar, answeredRule,
        compareTitle, compare, runRule,
    }

    CM.apply = function()
        for _, widget in ipairs(railDetail) do widget:SetShown(not CM.active) end


        local top = CM.active and CM.RUN_TOP or RAIL_RUN_TITLE
        runTitle:ClearAllPoints()
        runTitle:SetPoint("TOPLEFT", 14, -top)
        runTitle:SetPoint("RIGHT", runCount, "LEFT", -S.size.GAP, 0)
        runCount:ClearAllPoints()
        runCount:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -RAIL_EDGE, -top)
        runScroll:ClearAllPoints()
        if CM.active then
            runScroll:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -CM.RunScrollTop())
            runScroll:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -14,
                CM.RunScrollBottom())
        else
            runScroll:SetPoint("TOPLEFT", runTitle, "BOTTOMLEFT", 0, -CM.RUN_TITLE_GAP)
            runScroll:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -14, 12)
        end

        CM.ApplySort(CM.active and CM.table or table_)
        table_:SetShown(not CM.active)
        CM.table:SetShown(CM.active)

        if CM.tab == "council" or CM.tab == "queue" then CM.FitWindow() end

        CM.button:SetLabel(CM.active and T["Expand"] or T["Compact"])
        if CM.responseButton then
            CM.responseButton:SetLabel(CM.active and T["Expand"] or T["Compact"])
            if CM.tab == "response" then addon.Callbacks:Invalidate("voter") end
        end
        MLFrame:Refresh()
    end


    function CM.FitWindow()
        local width = CM.tab == "queue" and QueueWindowWidth() or WindowWidth(CM.active)


        if CM.tabSwitch and frame.SetSizeFromTopLeft then
            frame:SetSizeFromTopLeft(width, CM.Height(CM.active))
        else
            frame:SetSizeFromBottomRight(width, CM.Height(CM.active))
        end

        content.slcWidth = width - S.size.PAD * 2
        if frame.ClampTitle then P.AfterLayout(frame.ClampTitle) end

        if CM.tab == "queue" then footer:Reflow() end
    end



    frame:HookScript("OnShow", function()
        CM.SyncPulse()
        addon.Callbacks:PaintNow("council")
        addon.Callbacks:PaintNow("councilAgainst")
    end)



    frame:HookScript("OnHide", function()
        CM.HideToast()
        CM.WatchItemInfo()
        local hiddenRun = addon.Session:IsRunning()
            and addon.Session:GetRunId() or nil
        if hiddenRun then CM.dismissedRun = hiddenRun end
        addon.AutoClose:AfterHide(function(swept)
            if not addon.Session:IsRunning() or addon.Session:HasEnded() then return end
            if not swept then return end
            if CM.dismissedRun == hiddenRun then CM.dismissedRun = nil end
            if frame:IsShown() then return end
            local me = addon.Player:GetFullName("player")
            if addon.PlayerIsMasterLooter() or addon.Council:Contains(me) then
                addon.Log:D("UI", "council frame closed by the game - reopening")
                MLFrame:Open()
            end
        end)
    end)


    CM.queueButtons = {}
    CM.queueHost = {
        window = frame, pane = CM.queuePane, footer = footer,
        railWidth = RAIL_W, railGap = RAIL_GAP, railInset = 14,
        railBottom = S.size.FOOTER_H + CM.RAIL_GAP_V,
        mainWidth = WindowWidth(CM.active) - S.size.PAD * 2 - RAIL_W - RAIL_GAP,
        SetCount = function(text) CM.SetCount("queue", text) end,
        AddButton = function(button, rightAlign, atEdge)
            footer:Add(button, rightAlign, atEdge)
            CM.queueButtons[#CM.queueButtons + 1] = button
            button:SetShown(CM.tab == "queue")
        end,
    }

    CM.BuildResponse(content)
    frame.Tabs:AddTab("council", CM.TabText("council"))
    frame.Tabs:AddTab("queue", CM.TabText("queue"))
    frame.Tabs:AddTab("response", CM.TabText("response"))

    local refreshTitle = frame.RefreshTitle
    frame.RefreshTitle = function()
        refreshTitle()
        for _, key in ipairs({ "council", "queue", "response" }) do
            if frame.Tabs.SetTabText then frame.Tabs:SetTabText(key, CM.TabText(key)) end
        end
    end
    frame.Tabs:Select("council")
    frame.Tabs.onSelect = function(key)
        if key == "queue" then MLFrame:ShowQueue()
        elseif key == "response" then MLFrame:ShowResponse()
        else MLFrame:Present() end
    end
    CM.SyncQueueTab()


    CM.ticker:SetParent(frame)
    CM.ticker:Show()

    CM.apply()
    return frame
end



function CM.WatchItemInfo()
    local want = (CM.againstLoading or CM.namesMissing)
        and frame ~= nil and frame:IsShown() and CM.tab == "council" and true or false
    if want == CM.itemInfoOn then return end
    CM.itemInfoOn = want
    if want then
        CM.itemInfo:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        CM.itemInfo:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end


function CM.TabText(key)
    local text = key == "queue" and T["Loot queue"]
        or key == "response" and T["Loot response"]
        or T["Loot council"]
    return S.PrideActive() and S.PrideText(text) or text
end


function CM.Ensure()
    if not frame and CM.ready then CM.Build() end
    return frame
end





function CM.QueueAllowed()
    return addon.PlayerIsMasterLooter() and true or addon.Session:MayStage()
end

function CM.SyncQueueTab()
    if not frame then return end
    local allowed = CM.QueueAllowed()
    frame.Tabs:SetTabShown("queue", allowed)
    if not allowed and CM.tab == "queue" then CM.ShowTab("council") end
    CM.SyncResponseTab()
end



function CM.ResponseSeat()
    if not CM.ready or addon.db.responseTab == false then return false end
    return (addon.PlayerIsMasterLooter()
        or addon.Council:Contains(addon.Player:GetFullName("player"))) and true or false
end

function CM.SyncResponseTab()
    if not frame then return end
    local on = CM.responseOn and CM.ResponseSeat() or false
    frame.Tabs:SetTabShown("response", on)
    if not on and CM.tab == "response" then CM.ShowTab("council") end
    if on and CM.wantResponse then

        CM.wantResponse = nil
        C_Timer.After(0, function() MLFrame:ShowResponse(true) end)
    end
end

CM.PULSE_AFTER = 10



function CM.ArmPulse()
    if CM.leftResponseAt or not CM.responseOn then return end
    local at = GetTime()
    CM.leftResponseAt = at
    C_Timer.After(CM.PULSE_AFTER, function()
        if CM.leftResponseAt == at then CM.SyncPulse() end
    end)
end

function CM.SyncPulse()
    if not frame or not frame.Tabs.SetTabPulse then return end
    local due = CM.responseOn and CM.ResponseSeat() and CM.tab ~= "response"
        and CM.leftResponseAt ~= nil and GetTime() - CM.leftResponseAt >= CM.PULSE_AFTER
    frame.Tabs:SetTabPulse("response", due and true or false)
end

function CM.PlaceTimer(response)
    timerLabel:ClearAllPoints()
    timerText:ClearAllPoints()

    timerText:SetPoint("RIGHT", frame.Badge, "LEFT", -S.size.GAP, -1)
    timerLabel:SetPoint("RIGHT", timerText, "LEFT", -6, 0)
end

function CM.BuildResponse(content)

    CM.responsePane = CreateFrame("Frame", nil, content)
    CM.responsePane:SetPoint("TOPLEFT", content, "TOPLEFT")
    CM.responsePane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -S.size.PAD,
        S.size.FOOTER_H)
    CM.responsePane:Hide()
    CM.responseButton = S.Button(footer, CM.active and T["Expand"] or T["Compact"],
        { width = 100, labelPad = S.size.BTN_PAD_FOOTER })
    footer:Add(CM.responseButton, true)
    CM.responseButton:Hide()
    CM.responseButton:SetScript("OnClick", function()
        MLFrame:SetCompact(not CM.active)
    end)
    CM.responseHost = {
        pane = CM.responsePane,
        IsActive = function() return frame:IsShown() and CM.tab == "response" end,
        IsCompact = function() return CM.active and true or false end,
        SetCount = function(text) CM.SetCount("response", text) end,



        Fit = function(width, listHeight)
            local inset = S.size.PAD
            local fitted = frame.HeaderHeight + inset + listHeight + S.size.FOOTER_H
            local compact = CM.active or fitted <= CM.Height(true)

            local w = math.max(WindowWidth(CM.active), width + S.size.PAD * 2)

            local h = compact and CM.Height(true) or math.min(fitted, CM.FULL_H)
            local sig = CM.responseHost.Signature()
            if CM.tabSwitch and frame.SetSizeFromTopLeft then
                CM.responseSig = sig
                frame:SetSizeFromTopLeft(w, h)
            elseif sig ~= CM.responseSig then


                CM.responseSig = sig
                frame:SetSizeFromBottomRight(w, h)
            else
                frame:SetSizeFromBottomRight(w, frame:GetHeight())
                frame:SetHeightFromTop(h)
            end
            content.slcWidth = w - S.size.PAD * 2
            CM.responsePane.slcWidth = w - inset - S.size.PAD
            if frame.ClampTitle then P.AfterLayout(frame.ClampTitle) end

            return h - frame.HeaderHeight - inset - S.size.FOOTER_H
        end,

        Signature = function() return WindowWidth(CM.active) .. (CM.active and "c" or "e") end,
    }
end

function CM.ShowTab(key)
    if key == "queue" and not CM.QueueAllowed() then key = "council" end
    if key == "response" and not (CM.responseOn and CM.ResponseSeat()) then key = "council" end
    if key ~= "queue" and key ~= "response" then key = "council" end
    local council, queue, response = key == "council", key == "queue", key == "response"
    frame.Tabs:Select(key)
    if CM.tab == key then return end
    CM.tab = key
    if response then CM.leftResponseAt = nil else CM.ArmPulse() end
    CM.SyncPulse()

    if queue then
        CM.queueHost.mainWidth = QueueWindowWidth() - S.size.PAD * 2 - RAIL_W - RAIL_GAP
        UI.QueueFrame:Attach(CM.queueHost)
    end
    CM.councilPane:SetShown(council)
    CM.queuePane:SetShown(queue)
    CM.responsePane:SetShown(response)

    endButton:SetShown(council)
    CM.button:SetShown(not response)
    if not council then
        rollButton:Hide()
        menuHint:Hide()
    end
    CM.liveKey, CM.countText = nil, nil
    CM.PaintLive()
    CM.ShowCount()
    for _, button in ipairs(CM.queueButtons) do button:SetShown(queue) end
    CM.responseButton:SetShown(response)

    footer:Reflow()


    CM.PlaceTimer(response)
    timerLabel:SetShown(true)
    timerText:SetShown(true)
    frame.Badge:SetShown(council)
    CM.ticker:SetShown(true)
    MLFrame:UpdateTimer()
    CM.WatchItemInfo()
    CM.footerKey = nil


    CM.tabSwitch = true
    if council then
        CM.apply()
    elseif queue then

        CM.FitWindow()
    else
        MLFrame:UpdateTimer()
        UI.VoterFrame:ForgetLayout()
        addon.Callbacks:Invalidate("voter")
        addon.Callbacks:PaintNow("voter")
    end
    CM.tabSwitch = nil
end



function CM.HiddenColumns()
    local hidden = addon.db.councilHiddenColumns
    if type(hidden) ~= "table" then
        hidden = {}
        addon.db.councilHiddenColumns = hidden
    end
    return hidden
end


local FIXED_COLUMNS = { name = true, actions = true }

function CM.ShowColumnMenu(anchor, t)
    local hidden = CM.HiddenColumns()
    local items = { { title = T["Columns"] } }
    for _, column in ipairs(t.columns) do
        local key = column.key
        if not FIXED_COLUMNS[key] then
            items[#items + 1] = {
                text = column.title, checkbox = true,
                checked = function() return not hidden[key] end,
                onClick = function()
                    hidden[key] = not hidden[key] or nil
                    CM.ColumnsChanged()
                end,
            }
        end
    end
    items[#items + 1] = "-"
    items[#items + 1] = {
        text = T["Reset Columns"], disabled = function() return next(hidden) == nil end,
        onClick = function()
            wipe(hidden)
            CM.ColumnsChanged()
        end,
    }
    S.ContextMenu(anchor, items)
end

function CM.ColumnsChanged()
    addon.Callbacks:Invalidate("voter")
    local hidden = CM.HiddenColumns()
    for _, t in pairs(CM.fullTables) do Tbl.SetHidden(t, hidden) end
    Tbl.SetHidden(CM.table, hidden)
    CM.apply()
end

function MLFrame:Init()
    S, Tbl = addon.Style, UI.Table
    L, P = addon.Layout, addon.Pixel




    CM.ticker = CreateFrame("Frame", nil, UIParent)
    CM.ticker:Hide()
    CM.ticker:SetScript("OnUpdate", function(_, elapsed)
        CM.sinceTick = (CM.sinceTick or 0) + elapsed
        if CM.sinceTick < 1 then return end
        CM.sinceTick = CM.sinceTick % 1
        MLFrame:UpdateTimer()
    end)
    CM.itemInfo = CreateFrame("Frame", nil, UIParent)
    CM.itemInfo:SetScript("OnEvent", function()
        if CM.againstLoading then
            addon.Callbacks:Invalidate("councilAgainst")
        end
        if CM.namesMissing then
            addon.Callbacks:Invalidate("council", selectedSession)
        end
    end)


    local function Shown() return frame ~= nil and frame:IsShown() and CM.tab == "council" end
    addon.Callbacks:RegisterView("council", {
        shown = Shown,
        interval = CM.PAINT_INTERVAL,
        paint = function(scope) MLFrame:Paint(scope) end,
    })

    addon.Callbacks:RegisterView("councilAgainst", {
        shown = Shown,
        interval = CM.PAINT_INTERVAL,
        paint = function() RefreshAgainst(againstFor) end,
    })

    addon.Callbacks:Register("RunStarted", function()
        selectedSession = 1
        paintedSession = nil
        CM.dismissedRun = nil


        local me = addon.Player:GetFullName("player")
        local seated = addon.PlayerIsMasterLooter() or addon.Council:Contains(me)
        if seated and CM.HasWork() then

            CM.wantResponse = CM.ResponseSeat() or nil
            MLFrame:Present()
            CM.CheckOpened()
        else
            addon.Log:I("UI", "run started - council window not opened:",
                seated and "nothing left to vote on" or "not on the council here")
        end
    end)

    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if session ~= selectedSession then return end
        local nextSession = CM.NextOpen(session)
        if nextSession then
            selectedSession = nextSession
            CM.RevealStrip(nextSession)
        end
        CM.ShowToast(item, winner)
    end)

    addon.Callbacks:Register("SessionChanged", function(session, kind, candidate)
        addon.Callbacks:Invalidate("council", session, kind, candidate)
    end)
    addon.Callbacks:Register("RunEnded", function()
        CM.wantResponse = nil
        if frame and CM.tab ~= "queue" then frame:Hide() end
    end)


    addon.Callbacks:Register("CouncilChanged", function()
        addon.Callbacks:Invalidate("council")
        if not addon.Session:IsRunning() or (frame and frame:IsShown())
            or CM.dismissedRun == addon.Session:GetRunId() then return end
        local me = addon.Player:GetFullName("player")
        if (addon.PlayerIsMasterLooter() or addon.Council:Contains(me)) and CM.HasWork() then
            MLFrame:Open()
            CM.CheckOpened()
        end
    end)
    addon.Callbacks:Register("LootMasterChanged", function()
        addon.Callbacks:Invalidate("council")
    end)

    local function SyncQueueTab() CM.SyncQueueTab() end
    addon.Callbacks:Register("LootMasterChanged", SyncQueueTab)
    addon.Callbacks:Register("CouncilChanged", SyncQueueTab)
    addon.Callbacks:Register("SharedConfigChanged", SyncQueueTab)
    addon.Callbacks:Register("RosterChanged", SyncQueueTab)


    addon.Callbacks:Register("ItemsAdded", function(indices, runId)
        if not addon.Session:IsRunning() or addon.Session:HasEnded()
            or (frame and frame:IsShown()) or type(indices) ~= "table"
            or (runId and runId ~= addon.Session:GetRunId()) then return end
        local me = addon.Player:GetFullName("player")
        local master = addon.PlayerIsMasterLooter()
        if not master and not addon.Council:Contains(me) then return end
        local items = addon.Session:GetItems()
        for _, index in ipairs(indices) do
            local item = items[index]
            if item and not item.awarded and not item.removed
                and (master or not HaveVotedOn(item)) then
                MLFrame:Open()
                return
            end
        end
    end)
    addon.Restrictions:OnChange(function() addon.Callbacks:Invalidate("council") end)

    CM.ready = true
    addon.Log:I("UI", "council frame ready")
end



function MLFrame:SetCompact(on)
    on = on and true or false
    if not CM.apply or CM.active == on then return end
    CM.active = on
    addon.db.mlCompact = on
    CM.apply()
end



function MLFrame:OpenForKill()

    if not CM.ready or not addon.PlayerIsMasterLooter() or not CM.Ensure() then return end
    if frame:IsShown() then return end
    if not CM.killOpened then
        CM.killOpened = true

        if not CM.ResponseSeat() then MLFrame:SetCompact(true) end
    end
    if addon.Session:IsRunning() and not addon.Session:HasEnded() and CM.HasWork() then
        CM.dismissedRun = nil
        MLFrame:Present()
    else
        MLFrame:ShowQueue()
    end
end



function MLFrame:SelectSession(session)
    if not CM.ready or not session then return end

    if not addon.Session:IsRunning() then return end
    if not addon.Session:GetItems()[session] then return end

    selectedSession = session
    CM.dismissedRun = nil
    MLFrame:Present()
end


function MLFrame:Open()
    if not CM.ready then return end
    CM.dismissedRun = nil
    MLFrame:Present()
end

function MLFrame:Toggle()
    if not CM.ready then return end
    if frame and frame:IsShown() and CM.tab ~= "queue" then
        CM.dismissedRun = addon.Session:GetRunId()
        frame:Hide()
    else
        CM.dismissedRun = nil
        MLFrame:Present()
    end
end
