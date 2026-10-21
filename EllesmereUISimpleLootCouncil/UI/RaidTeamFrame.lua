if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end





SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local RaidTeamFrame = {}
UI.RaidTeamFrame = RaidTeamFrame

local S, Tbl, L, P
local frame, table_, summaryText, searchBox, sortButton, offlineCheck, ranksButton
local seasonButton, originButton
local rankFrame


local expanded = {}

local filter = {
    search = "",
    offline = true,

    seasonOnly = true,
}


local SORT_ORDER = { "rank", "name", "recent", "loot" }
local SORT_LABEL = addon.Locale.Texts{
    rank       = T["Sort: guild rank"],
    name       = T["Sort: name"],
    recent     = T["Sort: most recent win"],
    loot       = T["Sort: most loot"],
}
local sortMode = "rank"







local CHEVRON_CLOSED = "Options_ListExpand_Right"
local CHEVRON_OPEN = "Options_ListExpand_Right_Expanded"
local haveChevron

local function ChevronAvailable()
    if haveChevron == nil then
        haveChevron = (C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo(CHEVRON_CLOSED)) and true or false
        if not haveChevron then
            addon.Log:D("UI", "raid team: chevron atlas missing, using text markers")
        end
    end
    return haveChevron
end







local CLASS_ICON_SHEET = "Interface/TargetingFrame/UI-Classes-Circles"






local function SlotName(link)
    if not link then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipLoc or equipLoc == "" then return nil end
    local localised = _G[equipLoc]
    if type(localised) == "string" and localised ~= "" then return localised end
    return nil
end

local function ItemLevel(link)
    if not link then return nil end

    local level = C_Item.GetDetailedItemLevelInfo(link)
    if type(level) ~= "number" or level <= 0 then return nil end
    return level
end




local function DifficultyName(entry)
    if type(entry.difficultyName) == "string" and entry.difficultyName ~= "" then
        return entry.difficultyName
    end
    local id = tonumber(entry.difficultyID)
    if not id or id <= 0 then return nil end
    local name = GetDifficultyInfo(id)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function ShortDate(entry)
    if entry.date and entry.date ~= "" then
        return addon.StoredDateText(entry.date, true)
    end
    if entry.epoch then return addon.DateText(entry.epoch, true, true) end
    return "?"
end










local function SeasonCutoff()
    if not filter.seasonOnly then return nil end
    return addon.RaidTeam:GetSeasonStart()
end



local snapshot
local memberFolds = setmetatable({}, { __mode = "k" })

local function Folded(member)
    local folds = memberFolds[member]
    if not folds then
        local Fold = addon.Locale.Fold
        folds = { Fold(member.name or ""), Fold(member.rank or ""), Fold(member.className or "") }
        memberFolds[member] = folds
    end
    return folds
end

local function Flatten(reuse)
    if not (reuse and snapshot) then
        snapshot = { members = addon.RaidTeam:GetMembers(), index = addon.RaidTeam:BuildLootIndex() }
    end
    local members, index = snapshot.members, snapshot.index

    local cutoff = SeasonCutoff()
    local needle = filter.search
    local prepared = {}

    for _, member in ipairs(members) do
        if filter.offline or member.online then
            local folds = needle ~= "" and Folded(member)
            local matches = needle == ""
                or folds[1]:find(needle, 1, true) ~= nil
                or folds[2]:find(needle, 1, true) ~= nil
                or folds[3]:find(needle, 1, true) ~= nil

            if matches then
                local loot = addon.RaidTeam:LootFor(index, member)



                if #loot > 0 then
                    local kept = {}
                    for _, entry in ipairs(loot) do
                        if (not cutoff or (entry.epoch or 0) >= cutoff)
                            and addon.History.PassesOrigin(entry) then
                            kept[#kept + 1] = entry
                        end
                    end
                    loot = kept
                end


                local count, latest, reasons = 0, 0, 0
                for _, entry in ipairs(loot) do

                    if addon.History.IsReasonAward(entry) then
                        reasons = reasons + 1
                    else
                        count = count + 1


                        if latest == 0 then latest = entry.epoch or 0 end
                    end
                end


                prepared[#prepared + 1] = {
                    kind = "player",
                    member = member,
                    loot = loot,
                    count = count,
                    reasons = reasons,
                    latest = latest,
                }
            end
        end
    end

    table.sort(prepared, function(a, b)
        if sortMode == "name" then
            return a.member.name < b.member.name
        elseif sortMode == "recent" then
            if a.latest ~= b.latest then return a.latest > b.latest end
        elseif sortMode == "loot" then
            if a.count ~= b.count then return a.count > b.count end
        else
            local ra, rb = a.member.rankOrder or 99, b.member.rankOrder or 99
            if ra ~= rb then return ra < rb end
        end


        return a.member.fullName < b.member.fullName
    end)

    local rows = {}
    local rankCounts = {}
    for _, record in ipairs(prepared) do
        local rank = record.member.rank or T["Unranked"]
        rankCounts[rank] = (rankCounts[rank] or 0) + 1
    end
    local lastRank
    for _, record in ipairs(prepared) do
        local member = record.member
        local rank = member.rank or T["Unranked"]
        if sortMode == "rank" and rank ~= lastRank then
            rows[#rows + 1] = {
                kind = "rank",
                rank = rank,
                count = rankCounts[rank],
            }
            lastRank = rank
        end
        rows[#rows + 1] = record

        if expanded[member.fullName] then


            if #record.loot == 0 then
                rows[#rows + 1] = { kind = "empty", member = member }
            else
                for _, entry in ipairs(record.loot) do
                    rows[#rows + 1] = { kind = "item", member = member, entry = entry }
                end
            end
        end
    end

    return rows, #prepared
end







local function BuildColumns()
    return {
        {
            key = "who", title = T["Raider / Item"], width = 409,
            render = function(cell, row)

                if not cell.Chevron then
                    cell.Chevron = cell:CreateTexture(nil, "ARTWORK")
                    cell.Chevron:SetSize(12, 12)
                    cell.Chevron:SetPoint("LEFT", 4, 0)

                    cell.Marker = S.Label(cell, S.fontBody, "CENTER")
                    cell.Marker:SetPoint("LEFT", 4, 0)
                    cell.Marker:SetWidth(12)

                    cell.Icon = cell:CreateTexture(nil, "ARTWORK")
                    cell.Icon:SetSize(14, 14)
                    cell.Icon:SetPoint("LEFT", 20, 0)
                    cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                    cell.Text:SetPoint("LEFT", 40, 0)
                end

                if row.kind == "rank" then
                    cell.Chevron:Hide()
                    cell.Marker:Hide()
                    cell.Icon:Hide()
                    cell.Text:SetPoint("LEFT", 4, 0)
                    cell.Text:SetText(addon.Locale.Upper(row.rank))
                    cell.Text:SetTextColor(S.Unpack(S.color.accentPale))
                    cell.Text:SetAlpha(1)
                elseif row.kind == "player" then
                    cell.Text:SetPoint("LEFT", 40, 0)
                    local open = expanded[row.member.fullName] and true or false
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


                    local dim = row.member.online and 1 or 0.55


                    local coords = row.member.classFile
                        and CLASS_ICON_TCOORDS[row.member.classFile]
                    if coords then
                        cell.Icon:SetTexture(CLASS_ICON_SHEET)
                        cell.Icon:SetTexCoord(unpack(coords))
                        cell.Icon:SetAlpha(dim)
                    else

                        cell.Icon:SetTexture(134400)
                        cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        cell.Icon:SetAlpha(0.35 * dim)
                    end
                    cell.Icon:Show()



                    local name = row.member.name
                    if not row.member.online then
                        name = addon.Locale.Format(T["%s%s  offline|r"], name,
                            S.ColorStart(S.color.textFaint))
                    end
                    cell.Text:SetText(name)
                    local colour = row.member.classFile
                        and C_ClassColor.GetClassColor(row.member.classFile)
                    if colour then
                        cell.Text:SetTextColor(colour:GetRGB())
                    else
                        cell.Text:SetTextColor(S.Unpack(S.color.text))
                    end
                    cell.Text:SetAlpha(dim)

                elseif row.kind == "item" then
                    cell.Text:SetPoint("LEFT", 40, 0)
                    cell.Chevron:Hide()
                    cell.Marker:Hide()
                    local _, _, _, _, icon = C_Item.GetItemInfoInstant(row.entry.link or "")
                    cell.Icon:SetTexture(icon or 134400)

                    cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    cell.Icon:SetAlpha(1)
                    cell.Icon:Show()


                    local _, canonical = C_Item.GetItemInfo(row.entry.link or "")
                    local itemName = canonical or row.entry.name or row.entry.link or "?"


                    local winnerQualified = row.entry.winner
                        and addon.Player:Qualify(row.entry.winner)
                    if winnerQualified and row.member.fullName
                        and addon.Player:NameKey(winnerQualified)
                            ~= addon.Player:NameKey(row.member.fullName) then
                        local altName = addon.Player:Get(winnerQualified).name
                            or winnerQualified
                        itemName = addon.Locale.Format(T["%s%s  on %s|r"], itemName,
                            S.ColorStart(S.color.textFaint), altName)
                    end

                    cell.Text:SetText(itemName)
                    cell.Text:SetTextColor(S.Unpack(S.color.text))
                    cell.Text:SetAlpha(1)

                else
                    cell.Text:SetPoint("LEFT", 40, 0)
                    cell.Chevron:Hide()
                    cell.Marker:Hide()
                    cell.Icon:Hide()
                    cell.Text:SetText(S.Colorize(S.color.textFaint, T["no loot recorded"]))
                    cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                    cell.Text:SetAlpha(1)
                end
            end,
        },
        {
            key = "count", title = T["Items"], width = 82,
            text = function(row)
                if row.kind == "rank" then
                    return S.Colorize(S.color.textMuted, tostring(row.count))
                end
                if row.kind ~= "player" then return "" end
                if row.count == 0 then return S.Colorize(S.color.textFaint, "-") end
                return S.Colorize(S.color.accent, tostring(row.count))
            end,
        },
        {
            key = "detail", title = T["Guild Rank"], width = 148,
            text = function(row)
                if row.kind == "player" then
                    return S.Colorize(S.color.textMuted, row.member.rank or "-")
                elseif row.kind == "item" then
                    return S.Colorize(S.color.textMuted, SlotName(row.entry.link) or "-")
                end
                return ""
            end,
        },
        {
            key = "ilvl", title = T["Ilvl"], width = 50,
            text = function(row)
                if row.kind ~= "item" then return "" end
                local level = ItemLevel(row.entry.link)
                if not level then return S.Colorize(S.color.textFaint, "-") end
                return tostring(level)
            end,
        },
        {
            key = "boss", title = T["Boss"], width = 137,
            text = function(row)
                if row.kind ~= "item" then return "" end
                return S.Colorize(S.color.textMuted, row.entry.boss or "-")
            end,
        },
        {

            key = "difficulty", title = T["Difficulty"], width = 130,
            text = function(row)
                if row.kind ~= "item" then return "" end
                local name = DifficultyName(row.entry)
                if not name then

                    return S.Colorize(S.color.textFaint, "-")
                end
                return S.Colorize(S.color.textMuted, name)
            end,
        },
        {
            key = "response", title = T["Response"], width = 170,
            text = function(row)
                if row.kind ~= "item" then return "" end

                if addon.History.IsReasonAward(row.entry) then
                    return S.Colorize(S.color.textFaint, row.entry.reason)
                end
                local text = addon.History.ResponseText(row.entry) or "-"


                if addon.History.IsCoinLoot(row.entry) then
                    return S.Colorize(S.color.accent, text)
                end
                if row.entry.r then
                    return ("|cff%02x%02x%02x%s|r"):format(
                        row.entry.r * 255, row.entry.g * 255, row.entry.b * 255, text)
                end
                return S.Colorize(S.color.textMuted, text)
            end,
        },
        {
            key = "when", title = T["When"], width = 104,
            text = function(row)
                if row.kind == "item" then
                    return S.Colorize(S.color.textMuted, ShortDate(row.entry))
                elseif row.kind == "player" and row.latest > 0 then
                    return S.Colorize(S.color.textFaint, addon.Locale.Format(
                        T["last %s"], addon.DateText(row.latest, true, true)))
                end
                return ""
            end,
        },
    }
end





local function ShowRowTooltip(row, data)
    if not data then return end
    S.SideTooltip(row)

    if data.kind == "player" then
        S.TooltipSection(GameTooltip, T["Raider"])
        GameTooltip:AddLine(data.member.fullName, 1, 1, 1)
        if data.member.className then
            GameTooltip:AddDoubleLine(T["Class"], data.member.className,
                0.64, 0.63, 0.60, 1, 1, 1)
        end

        GameTooltip:AddDoubleLine(T["Rank"], data.member.rank or "?",
            0.64, 0.63, 0.60, 1, 1, 1)
        if data.member.level then
            GameTooltip:AddDoubleLine(T["Level"], tostring(data.member.level),
                0.64, 0.63, 0.60, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine(T["Status"],
            data.member.online and (data.member.mobile and T["mobile"] or T["online"]) or T["offline"],
            0.64, 0.63, 0.60, 1, 1, 1)



        if data.member.note then
            S.TooltipSection(GameTooltip, T["Guild Notes"])
        end
        if data.member.note then
            GameTooltip:AddDoubleLine(T["Note"], data.member.note,
                0.64, 0.63, 0.60, 1, 1, 1)
        end
        S.TooltipSection(GameTooltip, T["Actions"])
        GameTooltip:AddLine(expanded[data.member.fullName]
            and addon.Locale.Format(T["Click to collapse"])
            or addon.Locale.Format(T["Click to expand"]), 0.45, 0.44, 0.42)

    elseif data.kind == "item" then
        local entry = data.entry
        S.SetTooltipItem(entry.link, entry.name)

        if entry.winner then
            local qualified = addon.Player:Qualify(entry.winner)
            local main = addon.Player:Main(entry.winner)
            if qualified and addon.Player:NameKey(main) ~= addon.Player:NameKey(qualified) then
                S.TooltipSection(GameTooltip, T["Alt / Main"])
                GameTooltip:AddDoubleLine(T["Main"], main, 0.64, 0.63, 0.60, 1, 1, 1)
            end
        end

        addon.Snapshot:AddTooltipLines(GameTooltip, entry, IsShiftKeyDown())

        S.TooltipSection(GameTooltip, T["Actions"])
        GameTooltip:AddLine(T["Shift-click to link"], 0.45, 0.44, 0.42)
    else
        return
    end

    GameTooltip:Show()

    if data.kind == "item" then S.WatchTooltipModifiers(row) end
end





local SUMMARY_SENTENCES = addon.Locale.Texts{
    season = {
        one = {
            one = T["%d raider from %d rank  -  this season, from %s"],
            other = T["%d raider from %d ranks  -  this season, from %s"],
        },
        other = {
            one = T["%d raiders from %d rank  -  this season, from %s"],
            other = T["%d raiders from %d ranks  -  this season, from %s"],
        },
    },
    unknown = {
        one = {
            one = T["%d raider from %d rank  -  season start unknown, so everything is counted  (/slc team season <date>)"],
            other = T["%d raider from %d ranks  -  season start unknown, so everything is counted  (/slc team season <date>)"],
        },
        other = {
            one = T["%d raiders from %d rank  -  season start unknown, so everything is counted  (/slc team season <date>)"],
            other = T["%d raiders from %d ranks  -  season start unknown, so everything is counted  (/slc team season <date>)"],
        },
    },
    all = {
        one = {
            one = T["%d raider from %d rank  -  all time"],
            other = T["%d raider from %d ranks  -  all time"],
        },
        other = {
            one = T["%d raiders from %d rank  -  all time"],
            other = T["%d raiders from %d ranks  -  all time"],
        },
    },
}

local function SummarySentence(kind, shown, ranks, start)
    local sentences = SUMMARY_SENTENCES[kind]
    local raiderForms = sentences[addon.Locale.PluralForm(shown)] or sentences.other
    local sentence = raiderForms[addon.Locale.PluralForm(ranks)] or raiderForms.other
    if start then return addon.Locale.Format(sentence, shown, ranks, start) end
    return addon.Locale.Format(sentence, shown, ranks)
end

local function UpdateSummary(shown)
    if not addon.RaidTeam:GetGuildName() then
        summaryText:SetText(S.Colorize(S.color.textFaint,
            T["You are not in a guild, so there is no roster to read."]))
        return
    end

    if not addon.RaidTeam:HasSelection() then

        summaryText:SetText(S.Colorize(S.color.accent,
            T["No ranks are marked as raiders yet - choose them under Ranks."]))
        return
    end

    local ranks = addon.RaidTeam:CountSelectedRanks()

    if filter.seasonOnly then
        local start = addon.RaidTeam:GetSeasonStart()
        if start then
            summaryText:SetText(S.Colorize(S.color.textMuted,
                SummarySentence("season", shown, ranks, addon.DateText(start, true))))
        else

            summaryText:SetText(S.Colorize(S.color.accent,
                SummarySentence("unknown", shown, ranks)))
        end
    else
        summaryText:SetText(S.Colorize(S.color.textMuted,
            SummarySentence("all", shown, ranks)))
    end
end



local function Paint(keepScroll, reuse)
    local rows, shown = Flatten(reuse)
    Tbl.SetData(table_, rows, keepScroll)
    UpdateSummary(shown)
    if originButton then originButton:Sync() end
end


function RaidTeamFrame:Refresh(keepScroll)
    if not frame then return end
    Paint(keepScroll, false)
end


local function Repaint(keepScroll)
    if not frame then return end
    Paint(keepScroll, true)
end






local rankRows = {}

local function EnsureRankRows(needed, parent, top)
    for i = #rankRows + 1, needed do
        local row = L.Row(parent, 0, L.WidthOf(parent), top - (i - 1) * S.size.ROW_H)
        row:SetStripe(i)

        local box = S.Checkbox(row, S.size.CTRL_H)
        P.Point(box, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
        row:AdoptHover(box)
        row.Box = box

        row.LabelText = L.BoundedLabel(row, box, "")

        local function toggle()
            if not row.rankName then return end
            local value = not box:GetChecked()
            box:SetChecked(value)

            addon.RaidTeam:SetRaiderRank(row.rankName, value)
        end
        box:SetScript("OnClick", toggle)
        row:SetScript("OnMouseUp", toggle)

        rankRows[i] = row
    end
end

local function RefreshRankFrame()
    if not rankFrame then return end

    local ranks = addon.RaidTeam:GetRanks()
    EnsureRankRows(#ranks, rankFrame.List, 0)

    for i, row in ipairs(rankRows) do
        local rank = ranks[i]
        if rank then
            row.rankName = rank.name
            row.LabelText:SetText(rank.name)
            row.Box:SetChecked(addon.RaidTeam:IsRaiderRank(rank.name))
            row:Show()
        else
            row.rankName = nil
            row:Hide()
        end
    end



    local listHeight = #ranks * S.size.ROW_H
    rankFrame.List:SetHeight(math.max(listHeight, S.size.ROW_H))
    rankFrame:SetHeight(P.Snap(rankFrame.chromeHeight + math.max(listHeight, S.size.ROW_H)))

    if #ranks == 0 then
        rankFrame.Empty:SetText(S.Colorize(S.color.textFaint,
            addon.RaidTeam:GetGuildName()
                and T["No ranks could be read yet - try Refresh."]
                or T["You are not in a guild."]))
        rankFrame.Empty:Show()
    else
        rankFrame.Empty:Hide()
    end
end

local function ShowRankFrame()
    if not rankFrame then
        local f = S.Window("SimpleLootCouncilRaidTeamRanksFrame", "raidteamranks",
            360, 200, T["Raid team ranks"])

        local content = f.Content
        local cursor = L.Cursor(content)

        local _, introHeight = cursor:Add(L.Paragraph,
            T["Tick the guild ranks whose members are on your raid team. The choice is remembered per guild."], S.fontSmall)
        cursor:Gap(S.size.SECTION)

        local listTop = cursor:Y()


        local list = CreateFrame("Frame", nil, content)
        list:SetFrameLevel(content:GetFrameLevel() + 1)
        P.Point(list, "TOPLEFT", content, "TOPLEFT", 0, listTop)
        P.Point(list, "TOPRIGHT", content, "TOPRIGHT", 0, listTop)
        list.slcWidth = content.slcWidth
        f.List = list


        f.Empty = S.Label(list, S.fontSmall, "LEFT")
        P.Point(f.Empty, "TOPLEFT", list, "TOPLEFT", S.size.ROW_PAD, -4)
        P.Point(f.Empty, "TOPRIGHT", list, "TOPRIGHT", -S.size.ROW_PAD, -4)
        f.Empty:Hide()

        local close = S.Button(content, T["Done"], { width = 120, primary = true })
        P.Point(close, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)


        f.chromeHeight = f.HeaderHeight + S.size.PAD + introHeight + S.size.SECTION
            + S.size.GAP + S.size.BTN_H + S.size.PAD

        rankFrame = f
    end

    addon.RaidTeam:Request()
    RefreshRankFrame()
    rankFrame:RestorePosition()
    rankFrame:Show()
end






local SEARCH_DELAY = 0.2


local function Build()


    frame = S.Window("SimpleLootCouncilRaidTeamFrame", "raidteam", 1263, 640,
        T["Raid team loot"])
    frame:RestorePosition()

    local content = frame.Content
    local cursor = L.Cursor(content)

    local filterRow = cursor:Add(L.Row, S.size.BTN_H)


    filterRow:EnableMouse(false)

    local searchHolder, edit = S.EditBox(filterRow, 266, S.size.BTN_H)
    P.Point(searchHolder, "LEFT", filterRow, "LEFT", 0, 0)
    searchBox = edit

    local typed = 0
    edit:SetScript("OnTextChanged", function(self)
        typed = typed + 1
        local mine = typed
        C_Timer.After(SEARCH_DELAY, function()
            if mine ~= typed then return end
            filter.search = addon.Locale.Fold(self:GetText() or "")
            Repaint()
        end)
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)


    local searchHint = S.Label(edit, S.fontHint, "LEFT")
    P.Point(searchHint, "LEFT", 0, 0)
    searchHint:SetText(T["name, rank, or class"])
    edit:HookScript("OnTextChanged", function(self)
        searchHint:SetShown((self:GetText() or "") == "")
    end)
    edit:HookScript("OnEditFocusGained", function() searchHint:Hide() end)
    edit:HookScript("OnEditFocusLost", function(self)
        searchHint:SetShown((self:GetText() or "") == "")
    end)

    sortButton = S.Button(filterRow, SORT_LABEL[sortMode])
    P.Point(sortButton, "LEFT", searchHolder, "RIGHT", S.size.GAP, 0)
    sortButton:SetScript("OnClick", function(self)
        local index = 1
        for i, key in ipairs(SORT_ORDER) do
            if key == sortMode then index = i end
        end
        sortMode = SORT_ORDER[(index % #SORT_ORDER) + 1]
        self:SetLabel(SORT_LABEL[sortMode])
        Repaint()
    end)


    seasonButton = S.Button(filterRow, T["This season"], { width = 145 })
    P.Point(seasonButton, "LEFT", sortButton, "RIGHT", S.size.GAP, 0)
    seasonButton:SetScript("OnClick", function(self)
        filter.seasonOnly = not filter.seasonOnly
        self:SetLabel(filter.seasonOnly and T["This season"] or T["All time"])
        Repaint()
    end)
    seasonButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        S.TooltipSection(GameTooltip, T["Timescale"])

        local start = addon.RaidTeam:GetSeasonStart()
        if start then
            GameTooltip:AddDoubleLine(T["Season started"], addon.DateText(start, true),
                0.64, 0.63, 0.60, 1, 1, 1)
        else

            GameTooltip:AddLine(T["The season start date is not known yet."],
                0.90, 0.45, 0.45, true)
            GameTooltip:AddLine(T["Nothing reports when a season began, so it is recorded at the next rollover - or set it now with /slc team season 2026-08-01."], 0.64, 0.63, 0.60, true)
        end

        S.TooltipSection(GameTooltip, T["What Is Counted"])
        GameTooltip:AddLine(T["Bank and disenchant awards are listed but never counted, whichever timescale is chosen."], 0.45, 0.44, 0.42, true)
        GameTooltip:Show()
    end)
    seasonButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    ranksButton = S.Button(filterRow, T["Ranks"], { width = 120 })
    P.Point(ranksButton, "LEFT", seasonButton, "RIGHT", S.size.GAP, 0)
    ranksButton:SetScript("OnClick", ShowRankFrame)
    ranksButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        S.TooltipSection(GameTooltip, T["Raid team ranks"])
        GameTooltip:AddLine(T["Choose which guild ranks count as raiders. Remembered per guild."], 0.64, 0.63, 0.60, true)
        GameTooltip:Show()
    end)
    ranksButton:HookScript("OnLeave", function() GameTooltip:Hide() end)


    originButton = addon.UI.HistoryFrame.OriginFilterButton(filterRow)
    P.Point(originButton, "LEFT", ranksButton, "RIGHT", S.size.GAP, 0)

    offlineCheck = S.Switch(filterRow, function(value)
        filter.offline = value
        Repaint()
    end)
    P.Point(offlineCheck, "RIGHT", filterRow, "RIGHT", 0, 0)
    offlineCheck:SetChecked(filter.offline)

    local offlineLabel = S.Label(filterRow, S.fontBody, "RIGHT")
    P.Point(offlineLabel, "RIGHT", offlineCheck, "LEFT", -S.size.GAP, 0)
    offlineLabel:SetText(T["Show offline"])

    cursor:Gap(S.size.SECTION)

    table_ = cursor:Add(function(parent, x, width, y)
        local t = Tbl.Create(parent, BuildColumns(), 14, S.size.ROW_H,
            S.fontRaidTeamHeader)
        P.Point(t, "TOPLEFT", parent, "TOPLEFT", x, y)
        return t, t:GetHeight()
    end)

    local bar = table_.ScrollBar
    bar:ClearAllPoints()
    P.Point(bar, "TOPRIGHT", frame, "TOPRIGHT", -5,
        -(frame.HeaderHeight + S.size.PAD + S.size.BTN_H + S.size.SECTION
            + table_.headerHeight + 1))
    P.Point(bar, "BOTTOMRIGHT", frame, "TOPRIGHT", -5,
        -(frame.HeaderHeight + S.size.PAD + S.size.BTN_H + S.size.SECTION
            + table_:GetHeight()))

    table_.onEnter = function(row, data) ShowRowTooltip(row, data) end
    table_.onLeave = function() GameTooltip:Hide() end
    table_.onClick = function(_, data)
        if not data then return end

        if data.kind == "player" then
            local key = data.member.fullName
            expanded[key] = (not expanded[key]) or nil
            Repaint(true)
            return
        end

        if data.kind == "item" and IsShiftKeyDown() and data.entry.link then

            local _, canonical = C_Item.GetItemInfo(data.entry.link)
            ChatFrameUtil.InsertLink(canonical or data.entry.link)
        end
    end

    local footer = S.FooterBar(frame)
    footer:Add(addon.UI.HistoryFrame.DeleteButton(footer))
    summaryText = footer:AddText(S.fontSmall)

    local exportButton = S.Button(footer, T["Export CSV"], { width = 150 })
    exportButton:SetScript("OnClick", function()
        addon.ShowHistoryCSV()
    end)
    exportButton:HookScript("OnEnter", function(self)
        S.AboveTooltip(self)
        S.TooltipSection(GameTooltip, T["Export CSV"])
        GameTooltip:AddLine(T["Exports the combined award history for analysis."],
            0.64, 0.63, 0.60, true)
        addon.UI.HistoryFrame.AddExportOriginLine(GameTooltip)
        GameTooltip:Show()
    end)
    exportButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local refreshButton = S.Button(footer, T["Refresh roster"], {
        width = 165, primary = true,
    })
    refreshButton:SetScript("OnClick", function()
        addon.RaidTeam:Request()
        addon.RaidTeam:Invalidate()
        RaidTeamFrame:Refresh(true)
    end)

    footer:Add(refreshButton, true)
    footer:Add(exportButton, true)

    frame:SetHeight(P.Snap(640))



    frame:HookScript("OnHide", function()
        snapshot = nil
        Tbl.Release(table_)
        addon.History:DropArchive("team")
    end)

    frame:HookScript("OnShow", function() addon.History:HoldArchive("team") end)

    addon.Log:D("UI", "raid team frame built")
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

function RaidTeamFrame:Init()
    S, Tbl = addon.Style, UI.Table
    L, P = addon.Layout, addon.Pixel



    local function RepaintIfShown()
        if frame and frame:IsShown() then RaidTeamFrame:Refresh(true) end
    end
    addon.Callbacks:Register("ItemAwarded", RepaintIfShown)
    addon.Callbacks:Register("HistoryChanged", RepaintIfShown)

    addon.Callbacks:Register("HistoryFilterChanged", function()
        if frame and frame:IsShown() then RaidTeamFrame:Refresh() end
    end)
    addon.Callbacks:Register("RaidTeamChanged", function()
        if rankFrame and rankFrame:IsShown() then RefreshRankFrame() end
        RepaintIfShown()
    end)

    addon.Callbacks:Register("MainsChanged", RepaintIfShown)

    addon.Callbacks:Register("TeamShowAltsChanged", RepaintIfShown)

    addon.Log:I("UI", "raid team frame ready")
end

function RaidTeamFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    WhenBuilt(function()

        addon.RaidTeam:Request()
        frame:Show()
        RaidTeamFrame:Refresh()
    end)
end
