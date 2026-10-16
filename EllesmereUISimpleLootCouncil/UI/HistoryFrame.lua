if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local HistoryFrame = {}
UI.HistoryFrame = HistoryFrame

local S, Tbl, L, P
local frame, table_, summaryText, searchBox, pasteFrame, pickerFrame
local sourceButton, windowButton, mineCheck, originButton

local refilter = false



local filter = {
    search = "",
    source = "all",
    days = 0,
    mineOnly = false,
}



local SOURCE_ORDER = { "all", "slc", "other" }
local SOURCE_LABEL = addon.Locale.Texts{
    all = T["All sources"],
    slc = "SimpleLootCouncil",
    other = T["Others"],
}

local WINDOW_ORDER = { 0, 30, 90, 365 }
local WINDOW_LABEL = addon.Locale.Texts{ [0] = T["All time"], [30] = T["Last 30 days"], [90] = T["Last 90 days"],
    [365] = T["Last year"] }







local function EntrySource(entry)
    return entry.source or "slc"
end



local function SourceFilterKey(entry)
    local source = EntrySource(entry)
    if source == "slc" or source == "slc-csv" then return "slc" end
    return "other"
end



local function SourceAbbrev(entry)
    local source = EntrySource(entry)
    if source == "slc" then return "SLC" end
    if source == "slc-csv" then return "CSV" end
    local registry = SimpleLootCouncil and SimpleLootCouncil.HistoryImport
    return registry and registry:Abbrev(source) or "??"
end


local function SourceColor(source)
    if source == "slc" then return S.color.accent end
    local registry = SimpleLootCouncil and SimpleLootCouncil.HistoryImport
    local tint = registry and registry:Tint(source)
    return (tint and S.color[tint]) or S.color.textFaint
end



local function DateNeedle(needle)
    local digits = needle:gsub("[/%-%.%s]", "")
    if digits == "" or #digits < 3 then return nil end
    if digits:find("%D") then return nil end
    return digits
end


local function DateKey(entry)
    if entry.date and entry.date ~= "" then
        local key = entry.date:gsub("%D", "")
        if #key >= 6 then return key end
    end
    if entry.epoch then return date("!%Y%m%d", entry.epoch) end
    return ""
end


local function NoteText(note)
    if note and addon.Autopass then return addon.Autopass.NoteText(note) end
    return note
end



local foldCache = setmetatable({}, { __mode = "k" })

local function ResetFolds()
    foldCache = setmetatable({}, { __mode = "k" })
end




local function Matches(entry, needle)
    if needle == "" then return true end

    local dateQuery = DateNeedle(needle)
    if dateQuery then
        return DateKey(entry):find(dateQuery, 1, true) ~= nil
    end

    local haystack = foldCache[entry]
    if not haystack then
        haystack = addon.Locale.Fold(table.concat({
            tostring(entry.winner or ""),

            tostring(entry.link or ""), tostring(entry.name or ""),
            tostring(entry.boss or ""),

            tostring(entry.instance or ""), tostring(addon.History.ResponseText(entry) or ""),
            tostring(NoteText(entry.note) or ""),
        }, " "))
        foldCache[entry] = haystack
    end


    return haystack:find(needle, 1, true) ~= nil
end


local resolved = { cutoff = nil, me = nil }

local function ResolveFilter()
    resolved.cutoff = filter.days > 0
        and (GetServerTime() - (filter.days * 24 * 60 * 60)) or nil
    resolved.me = filter.mineOnly and addon.Player:GetFullName("player") or nil
end

local function Passes(entry)
    if filter.source ~= "all"
        and SourceFilterKey(entry) ~= filter.source then
        return false
    end

    if resolved.cutoff and (entry.epoch or 0) < resolved.cutoff then
        return false
    end

    if filter.mineOnly and entry.winner ~= resolved.me then
        return false
    end

    if not addon.History.PassesOrigin(entry) then return false end

    return Matches(entry, filter.search)
end





local function ShortDate(entry)
    if entry.date and entry.date ~= "" then


        return (entry.date:gsub("^20", "")) .. " " .. tostring(entry.time or ""):sub(1, 5)
    end
    if entry.epoch then return date("!%y/%m/%d %H:%M", entry.epoch) end
    return "?"
end

local function BuildColumns()
    return {
        {
            key = "when", title = T["When"], width = 124,
            value = function(e) return e.epoch or 0 end,
            text = function(e) return S.Colorize(S.color.textMuted, ShortDate(e)) end,
        },
        {
            key = "source", title = T["Src"], width = 42,
            value = function(e) return EntrySource(e) end,
            text = function(e)
                return S.Colorize(SourceColor(EntrySource(e)), SourceAbbrev(e))
            end,
        },
        {
            key = "item", title = T["Item"], width = 248,
            value = function(e) return tostring(e.link or "") end,

            render = function(cell, e)
                if not cell.Icon then
                    cell.Icon = cell:CreateTexture(nil, "ARTWORK")
                    cell.Icon:SetSize(14, 14)
                    cell.Icon:SetPoint("LEFT", 4, 0)
                    cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    cell.Text:SetPoint("LEFT", 22, 0)
                end
                local _, _, _, _, icon = C_Item.GetItemInfoInstant(e.link or "")
                cell.Icon:SetTexture(icon or 134400)


                local _, canonical = C_Item.GetItemInfo(e.link or "")
                cell.Text:SetText(canonical or e.name or e.link or "?")
            end,
        },
        {
            key = "winner", title = T["Winner"], width = 96,
            value = function(e) return tostring(e.winner or "") end,
            text = function(e)
                local name = tostring(e.winner or "?"):match("^([^-]+)") or "?"
                return name
            end,
        },
        {
            key = "response", title = T["Response"], width = 100,

            value = function(e)
                return tostring(e.reason or addon.History.ResponseText(e) or "")
            end,
            text = function(e)
                if addon.History.IsReasonAward(e) then

                    return S.Colorize(S.color.textFaint, e.reason)
                end
                local text = addon.History.ResponseText(e) or "?"


                if addon.History.IsCoinLoot(e) then
                    return S.Colorize(S.color.accent, text)
                end
                if e.r then return ("|cff%02x%02x%02x%s|r")
                    :format(e.r * 255, e.g * 255, e.b * 255, text) end
                return text
            end,
        },
        {
            key = "votes", title = T["Votes"], width = 66, justify = "LEFT",
            value = function(e) return e.votes or -1 end,
            text = function(e)
                if not e.votes then return S.Colorize(S.color.textFaint, "-") end
                return tostring(e.votes)
            end,
        },
        {
            key = "boss", title = T["Boss"], width = 178,
            value = function(e) return tostring(e.boss or "") end,
            text = function(e) return S.Colorize(S.color.textMuted, e.boss or "-") end,
        },
        {
            key = "instance", title = T["Instance"], width = 282,
            value = function(e) return tostring(e.instance or "") end,
            text = function(e) return S.Colorize(S.color.textMuted, e.instance or "-") end,
        },
    }
end





local function ShowRowTooltip(row, entry)
    if not entry then return end
    S.SideTooltip(row)

    S.SetTooltipItem(entry.link, entry.name)

    S.TooltipSection(GameTooltip, T["Loot history"])
    GameTooltip:AddDoubleLine(T["Winner"], entry.winner or "?", 0.64, 0.63, 0.60, 1, 1, 1)
    if entry.owner then


        GameTooltip:AddDoubleLine(T["Held by"], entry.owner, 0.64, 0.63, 0.60, 1, 1, 1)
    end
    if entry.note and entry.note ~= "" then
        GameTooltip:AddDoubleLine(T["Note"], NoteText(entry.note), 0.64, 0.63, 0.60, 1, 1, 1)
    end
    if entry.groupSize then
        GameTooltip:AddDoubleLine(T["Group size"], tostring(entry.groupSize),
            0.64, 0.63, 0.60, 1, 1, 1)
    end

    if entry.guild then
        GameTooltip:AddDoubleLine(T["Guild"], entry.guild, 0.64, 0.63, 0.60, 1, 1, 1)
    end
    if entry.recorder then
        GameTooltip:AddDoubleLine(T["Recorded by"], entry.recorder, 0.64, 0.63, 0.60, 1, 1, 1)
    end

    if entry.delivered == nil then
        GameTooltip:AddDoubleLine(T["Delivered"], T["not recorded"], 0.64, 0.63, 0.60,
            0.45, 0.44, 0.42)
    else
        GameTooltip:AddDoubleLine(T["Delivered"], entry.delivered and T["yes"] or T["no"],
            0.64, 0.63, 0.60, 1, 1, 1)
    end

    if SourceFilterKey(entry) == "other" then
        GameTooltip:AddLine(addon.Locale.Format(T["Imported from %s"],
            addon.HistoryImport:Label(EntrySource(entry))),
            0.45, 0.44, 0.42)
    end

    if entry.editedAt then
        GameTooltip:AddLine(entry.editedBy
            and addon.Locale.Format(T["Edited locally by %s"], entry.editedBy)
            or addon.Locale.Format(T["Edited locally"]), 0.45, 0.44, 0.42)
    end


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
    GameTooltip:AddLine(T["Right-click to edit this local copy"], 0.45, 0.44, 0.42)
    GameTooltip:Show()


    S.WatchTooltipModifiers(row)
end

local function ShowRowMenu(row, entry)
    if not entry or not entry.id then return end

    local names = {}
    local snapshot = addon.Snapshot and addon.Snapshot:For(entry)
    for name in pairs(snapshot and snapshot.candidates or {}) do
        names[name] = true
    end
    for name in pairs(addon.GetCandidates()) do
        names[name] = true
    end
    if entry.winner then names[entry.winner] = true end
    local choices = {}
    for name in pairs(names) do choices[#choices + 1] = name end
    table.sort(choices)
    local winners = {}
    for _, name in ipairs(choices) do
        local winner = name
        winners[#winners + 1] = { text = winner, onClick = function()
            addon.History:SetWinner(entry.id, winner)
        end }
    end

    local responses = {}
    for index, response in ipairs(addon.Config:Responses()) do
        local responseID = index
        responses[#responses + 1] = { text = response.text, onClick = function()
            addon.History:SetResponse(entry.id, responseID)
        end }
    end

    local reasons = {}
    for index, reason in ipairs(addon.db.awardReasons or {}) do
        if reason.log then
            local reasonIndex = index
            reasons[#reasons + 1] = { text = reason.text, onClick = function()
                addon.History:SetReason(entry.id, reasonIndex)
            end }
        end
    end

    local items = {
        { title = entry.name or entry.link or T["History entry"] },
        { text = T["Set winner"], children = winners },
        { text = T["Set response"], children = responses },
    }
    if #reasons > 0 then
        items[#items + 1] = { text = T["Set award reason"], children = reasons }
    end
    items[#items + 1] = "-"
    items[#items + 1] = { text = T["Delete entry"], onClick = function()
        S.Confirm({
            title = T["Delete history entry"],
            body = addon.Locale.Format(T["Delete %s awarded to %s?\n\nThis only changes your local history and cannot be undone."],


                    entry.link or entry.name or T["this item"],
                    entry.winner or "?"),
            accept = T["Delete entry"],
            onAccept = function()
                addon.History:DeleteEntry(entry.id)
            end,
        })
    end }
    S.ContextMenu(row, items)
end





local function UpdateSummary()
    local native, imported = addon.History:Count(), addon.HistoryImport:Count()
    local shown, total = #table_.filtered, #table_.data

    local text


    if not addon.db.recordHistory then
        text = S.Colorize(S.color.accent, addon.Locale.Format(
            T["%d shown of %d  (%d recorded, %d imported)  - Record award history is off"],
            shown, total, native, imported))
    elseif shown < total then
        text = S.Colorize(S.color.accent, addon.Locale.Format(
            T["%d shown of %d  (%d recorded, %d imported)  - filtered"],
            shown, total, native, imported))
    else
        text = S.Colorize(S.color.textMuted, addon.Locale.Format(
            T["%d shown of %d  (%d recorded, %d imported)"],
            shown, total, native, imported))
    end
    summaryText:SetText(text)
end


function HistoryFrame:Refresh()
    if not frame then return end
    ResolveFilter()
    Tbl.Refresh(table_)
    UpdateSummary()
end



function HistoryFrame:Reload()
    if not frame then return end
    ResetFolds()
    ResolveFilter()
    Tbl.SetData(table_, addon.History:GetAll(), not refilter)
    refilter = false
    UpdateSummary()
    if originButton then originButton:Sync() end
end


function HistoryFrame.DeleteButton(parent)

    local S = addon.Style
    local wipe = S.Button(parent, T["Delete history"], {
        danger = true, labelPad = S.size.BTN_PAD_FOOTER,
    })
    wipe:SetScript("OnClick", function()
        local recorded = addon.History:Count()
        local imported = addon.HistoryImport:Count()
        if recorded + imported == 0 then
            print(addon.Log.CHAT_PREFIX.accent .. T["there is no history to delete."])
            return
        end
        local awards = addon.Locale.Format(addon.Locale.Plural{
            one = "%d recorded award", other = "%d recorded awards",
        }, recorded, recorded)
        local rows = addon.Locale.Format(addon.Locale.Plural{
            one = "%d imported row", other = "%d imported rows",
        }, imported, imported)
        S.Confirm({
            title = T["Delete loot history"],
            body = addon.Locale.Format(T["This deletes %s and %s.\n\n"], awards, rows)
                .. HistoryFrame.HiddenByOriginSentence()
                .. S.Colorize(S.color.bad,
                    T["Recorded awards cannot be recovered. Export a CSV first if needed."]),
            accept = T["Delete all"],
            onAccept = function()
                local r, i = addon.History:Clear(), addon.HistoryImport:Clear()
                print(addon.Log.CHAT_PREFIX.accent ..
                    addon.Locale.Format(T["deleted %d recorded and %d imported entries."], r, i))
                HistoryFrame:Reload()
            end,
            alternate = imported > 0 and T["Imports only"] or nil,
            onAlternate = imported > 0 and function()
                addon.HistoryImport:Clear()
                HistoryFrame:Reload()
            end or nil,
        })
    end)
    return wipe
end



function HistoryFrame.HiddenByOriginSentence()
    local hidden = addon.History:OriginChoices().hidden.total
    if hidden == 0 then return "" end
    return addon.Locale.Format(addon.Locale.Plural{
        one = "%d of them is hidden by the guild filter and is deleted too.\n\n",
        other = "%d of them are hidden by the guild filter and are deleted too.\n\n",
    }, hidden, hidden)
end


function HistoryFrame.AddExportOriginLine(tooltip)
    if addon.History:OriginChoices().hidden.total == 0 then return end
    tooltip:AddLine(T["The guild filter does not apply here: the rows it hides are exported too."],
        0.45, 0.44, 0.42, true)
end







local ORIGIN_MENU_W = 300
local ORIGIN_MENU_ROWS = 10
local ORIGIN_PAD = 6
local CHEVRON = "Options_ListExpand_Right"

local function OriginLabel(kind, key, label)
    if key == addon.History.UNTAGGED then
        return kind == "guild" and T["No guild"] or T["No character recorded"]
    end
    label = label or key

    if kind == "recorder" and addon.IsForever then
        label = label:match("^(.-)%-") or label
    end
    return label
end



local function OriginMenu(window)
    local S, L, P = addon.Style, addon.Layout, addon.Pixel
    local size = S.size

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:Hide()
    S.Fill(menu, S.color.card)
    S.Border(menu, S.color.windowEdge)
    window:HookScript("OnHide", function() menu:Hide() end)

    local region = S.ScrollRegion(menu)
    P.Point(region, "TOPLEFT", menu, "TOPLEFT", ORIGIN_PAD, -ORIGIN_PAD)
    P.Point(region, "BOTTOMRIGHT", menu, "BOTTOMRIGHT", -ORIGIN_PAD, ORIGIN_PAD)
    menu.region = region

    local rowW = ORIGIN_MENU_W - 2 * ORIGIN_PAD - size.SCROLLBAR_W - size.SCROLLBAR_GAP
    local rows = {}

    function menu:Row(i)
        if rows[i] then return rows[i] end
        local row = L.Row(region.Content, 0, rowW, -(i - 1) * size.ROW_H, size.ROW_H)

        local box = S.Checkbox(row, size.CTRL_H)
        P.Point(box, "LEFT", row, "LEFT", size.ROW_PAD, 0)
        row:AdoptHover(box)
        row.Box = box

        local chevron = row:CreateTexture(nil, "ARTWORK")
        P.Size(chevron, 12, 12)
        P.Point(chevron, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
        local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo(CHEVRON)
        if hasAtlas then chevron:SetAtlas(CHEVRON) end
        chevron:Hide()
        row.Chevron, row.hasAtlas = chevron, hasAtlas and true or false

        row.Count = S.Label(row, S.fontSmall, "RIGHT")
        row.Label = S.Label(row, S.fontBody, "LEFT")

        local function click()
            if row.onClick then row.onClick(row) end
        end
        row:SetScript("OnMouseUp", click)
        box:SetScript("OnClick", click)

        rows[i] = row
        return row
    end


    function menu:Finish(used)
        for i = used + 1, #rows do rows[i]:Hide() end
        local visible = math.max(1, math.min(used, ORIGIN_MENU_ROWS))
        P.Size(menu, ORIGIN_MENU_W, visible * size.ROW_H + 2 * ORIGIN_PAD)
        region:SetContentHeight(used * size.ROW_H)
    end

    return menu
end


local function PaintOriginRow(row, text, countText, checked, chevron)
    local S, P = addon.Style, addon.Pixel
    row.Label:SetText(text)
    row.Box:SetShown(not chevron)
    row.Box:SetChecked(checked)
    row.Count:ClearAllPoints()
    P.Point(row.Count, "RIGHT", row, "RIGHT",
        -(S.size.ROW_PAD + ((chevron and row.hasAtlas) and 16 or 0)), 0)
    row.Count:SetText(countText ~= "" and countText
        or ((chevron and not row.hasAtlas) and ">" or ""))
    row.Chevron:SetShown(chevron and row.hasAtlas or false)
    row.Label:ClearAllPoints()
    if chevron then
        P.Point(row.Label, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
    else
        P.Point(row.Label, "LEFT", row.Box, "RIGHT", S.size.GAP, 0)
    end
    P.Point(row.Label, "RIGHT", row.Count, "LEFT", -S.size.GAP, 0)
    row:Show()
end

local function OriginCount(choice)
    local S = addon.Style
    return S.Colorize(S.color.textFaint, tostring(choice.count))
end



local function PanelOrigin(button, window, Choose)
    local S = addon.Style
    local History = addon.History
    local guildMenu = OriginMenu(window)
    local characterMenu = OriginMenu(window)
    guildMenu:HookScript("OnHide", function() characterMenu:Hide() end)

    local function PaintCharacters(choices)
        for i, choice in ipairs(choices.recorders) do
            local row = characterMenu:Row(i)
            PaintOriginRow(row, OriginLabel("recorder", choice.key, choice.label),
                OriginCount(choice), choice.selected)
            local key = choice.key
            row.onClick = function() Choose("recorder", key) end
        end
        characterMenu:Finish(#choices.recorders)
    end

    local function PaintGuilds(choices)
        local row = guildMenu:Row(1)
        PaintOriginRow(row, T["Clear filter"], "", choices.kind == nil)
        row.onClick = function() Choose(nil) end
        for i, choice in ipairs(choices.guilds) do
            row = guildMenu:Row(i + 1)
            PaintOriginRow(row, OriginLabel("guild", choice.key, choice.label),
                OriginCount(choice), choice.selected)
            local key = choice.key
            row.onClick = function() Choose("guild", key) end
        end

        local n = #choices.guilds + 2
        row = guildMenu:Row(n)
        PaintOriginRow(row, T["Character"], choices.kind == "recorder"
            and S.Colorize(S.color.accent, OriginLabel("recorder", choices.key, choices.label))
            or "", false, true)
        row.onClick = function()
            if characterMenu:IsShown() then
                characterMenu:Hide()
            else
                PaintCharacters(History:OriginChoices())
                characterMenu:ClearAllPoints()
                characterMenu:SetPoint("TOPLEFT", guildMenu, "TOPRIGHT", 2, 0)
                characterMenu:Show()
            end
        end
        guildMenu:Finish(n)
    end


    guildMenu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    guildMenu:HookScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    guildMenu:SetScript("OnEvent", function(self)
        if self:IsMouseOver() or button:IsMouseOver()
            or (characterMenu:IsShown() and characterMenu:IsMouseOver()) then
            return
        end
        self:Hide()
    end)

    local function repaint(choices, usable)
        if not usable then
            guildMenu:Hide()
            return
        end
        if guildMenu:IsShown() then PaintGuilds(choices) end
        if characterMenu:IsShown() then PaintCharacters(choices) end
    end

    local function open(self)
        if guildMenu:IsShown() then
            guildMenu:Hide()
            return
        end
        PaintGuilds(History:OriginChoices())
        guildMenu:ClearAllPoints()
        guildMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        guildMenu:Show()
    end

    return repaint, open
end



local function DropdownOrigin(button, Choose)
    local S = addon.Style
    local History = addon.History

    local function Entry(kind, choice)
        local key = choice.key
        return {
            text = OriginLabel(kind, key, choice.label) .. "  " .. OriginCount(choice),
            checked = choice.selected and true or false,
            onClick = function() Choose(kind, key) end,
        }
    end

    local function open(self)
        local choices = History:OriginChoices()
        local items = { {
            text = T["Clear filter"], checked = choices.kind == nil,
            onClick = function() Choose(nil) end,
        } }
        for _, choice in ipairs(choices.guilds) do
            items[#items + 1] = Entry("guild", choice)
        end
        local characters = {}
        for _, choice in ipairs(choices.recorders) do
            characters[#characters + 1] = Entry("recorder", choice)
        end
        items[#items + 1] = {
            text = T["Character"], children = characters,
            disabled = #characters == 0,
        }
        S.ContextMenu(self, items, { below = true, minWidth = self:GetWidth() })
    end

    return function() end, open
end




function HistoryFrame.OriginFilterButton(parent, onChange)
    local S = addon.Style
    local History = addon.History
    local button = S.Button(parent, T["All guilds"])

    local function Choose(kind, key)
        History:SetOriginFilter(kind, key)
        if onChange then onChange() end
    end


    local repaint, open
    if addon.EDITION == "eui" then
        repaint, open = DropdownOrigin(button, Choose)
    else
        repaint, open = PanelOrigin(button, S.WindowOf(parent), Choose)
    end



    function button:Sync()
        local choices = History:OriginChoices()
        if choices.kind then
            button:SetLabel(OriginLabel(choices.kind, choices.key, choices.label))
            button:SetColour(S.color.accent, S.color.accent)
        else
            button:SetLabel(T["All guilds"])
            button:SetColour(nil)
        end
        local usable = #choices.guilds > 1 or #choices.recorders > 1 or choices.kind ~= nil
        button:SetEnabled(usable)
        button.slcUsable = usable
        repaint(choices, usable)
    end
    button:SetDisabledReason(S.RequiresSentence(
        T["Requires history stored in more than one guild or by more than one character."]))

    button:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        open(self)
    end)
    button:HookScript("OnEnter", function(self)
        if self.slcUsable == false then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        S.TooltipSection(GameTooltip, T["Guild"])
        GameTooltip:AddLine(T["Show only the awards stored while you were in one guild, or by one of your characters. Older rows, rows imported from other addons and rows stored outside a guild are under No guild."], 0.64, 0.63, 0.60, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)

    return button
end











local CAPTURE_BOX_BYTES = 2048


local SETTLE_SECONDS = 0.35



local pasteBuffer, pasteN, pasteCancel = {}, 0, nil
local pasteTicker, pasteQuiet, pasteSeen

local pasteActive = false



local function PasteText()
    if pasteN > 1 then
        local whole = table.concat(pasteBuffer)
        pasteBuffer, pasteN = { whole }, 1
    end
    return pasteBuffer[1] or ""
end

local function PasteReset()
    pasteBuffer, pasteN = {}, 0
    pasteQuiet, pasteSeen = 0, 0
    pasteActive = false
    if pasteTicker then pasteTicker:Hide() end
end

local function ShowPasteWindow()
    if not pasteFrame then
        local f = S.Window("SimpleLootCouncilHistoryImportFrame", "historyImport",
            660, 420, T["Import loot history CSV"])


        local content = f.Content
        local cursor = L.Cursor(content)



        cursor:Add(L.Paragraph,
            T["Paste a CSV export from a supported loot addon, or from this addon's own export - the header says which, and the whole file goes in at once. The box only shows the start of it. A very large paste freezes the client for a few seconds while it arrives. Commas and semicolons both work; tab-separated text does not, because a paste into the game loses its tabs."], S.fontHint)
        cursor:Gap(S.size.SECTION)



        local FOOTER = S.size.BTN_H + S.size.SECTION + 16

        local inset = cursor:Add(function(parent, x, width, y)
            local box = S.Inset(parent, true)
            L.Above(box, parent)
            P.Point(box, "TOPLEFT", parent, "TOPLEFT", x, y)
            P.Point(box, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, FOOTER)
            return box, 0
        end)

        local scroll = CreateFrame("ScrollFrame", "SimpleLootCouncilHistoryImportScroll", inset)
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -(6 + S.size.SCROLLBAR_W + S.size.SCROLLBAR_GAP), 6)
        local bar = S.AttachScrollBar(scroll, inset, 20)
        P.Point(bar, "TOPRIGHT", inset, "TOPRIGHT", -6, -6)
        P.Point(bar, "BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(560)
        edit:SetAutoFocus(false)


        edit:SetMaxBytes(CAPTURE_BOX_BYTES)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit



        local function FocusCapture() edit:SetFocus() end
        for _, area in ipairs({ scroll, inset }) do
            area:EnableMouse(true)
            area:SetScript("OnMouseDown", FocusCapture)
        end

        local status = S.Label(content, S.fontSmall, "LEFT")
        P.Point(status, "BOTTOMLEFT", content, "BOTTOMLEFT", 0, S.size.BTN_H + S.size.GAP)
        P.Point(status, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, S.size.BTN_H + S.size.GAP)
        f.status = status


        local function ReportSize()
            local text = PasteText()
            if #text == 0 then
                status:SetText("")
                return
            end
            local rows = 0
            for _ in text:gmatch("\n") do rows = rows + 1 end
            status:SetText(S.Colorize(S.color.textMuted,
                addon.Locale.Format(addon.Locale.Plural{
                    one = "%d characters captured, about %d row",
                    other = "%d characters captured, about %d rows",
                }, rows, #text, rows)))
        end


        edit:SetScript("OnChar", function(_, char)
            if not pasteActive then
                pasteActive = true
                pasteQuiet, pasteSeen = 0, pasteN
                pasteTicker:Show()
            end
            pasteN = pasteN + 1
            pasteBuffer[pasteN] = char
        end)


        pasteTicker = CreateFrame("Frame", nil, f)
        pasteTicker:Hide()
        pasteTicker:SetScript("OnUpdate", function(_, elapsed)
            if pasteN ~= pasteSeen then
                pasteSeen, pasteQuiet = pasteN, 0
                return
            end
            pasteQuiet = pasteQuiet + elapsed
            if pasteQuiet < SETTLE_SECONDS then return end

            pasteActive = false
            pasteTicker:Hide()


            local text = PasteText()


            if #text > 0 and text:sub(-1) ~= "\n" then
                pasteBuffer[1] = text .. "\n"
            end
            ReportSize()
        end)

        local importButton = S.Button(content, T["Import"], { primary = true })
        P.Point(importButton, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)


        local clearButton = S.Button(content, T["Clear"], { width = 105 })
        P.Point(clearButton, "RIGHT", importButton, "LEFT", -S.size.GAP, 0)
        clearButton:SetScript("OnClick", function()
            if pasteCancel then pasteCancel() pasteCancel = nil end
            PasteReset()
            edit:SetText("")
            status:SetText("")
        end)

        importButton:SetScript("OnClick", function()

            if pasteCancel then pasteCancel() pasteCancel = nil end


            local whole = PasteText()
            if whole == "" then
                status:SetText(S.Colorize(S.color.bad, T["nothing to import"]))
                return
            end

            local started = GetTimePreciseSec()
            importButton:SetEnabled(false)
            clearButton:SetEnabled(false)

            local cancel, err = addon.HistoryImport:BeginCSV(whole,
                function(done, total)
                    status:SetText(S.Colorize(S.color.textMuted,
                        addon.Locale.Format(T["Reading %d of %d rows..."], done, total)))
                end,
                function(stats)
                    pasteCancel = nil
                    PasteReset()
                    edit:SetText("")
                    importButton:SetEnabled(true)
                    clearButton:SetEnabled(true)

                    status:SetText(S.Colorize(S.color.good,
                        addon.Locale.Format(T["%s: %s"],
                            addon.HistoryImport:Label(stats.format),
                            addon.HistoryImport:Describe(stats))))

                    addon.Log:I("Import", "CSV paste:", #whole, "bytes,",
                        ("%.0fms"):format((GetTimePreciseSec() - started) * 1000),
                        "for", stats.scanned, "rows")
                    HistoryFrame:Reload()
                end)

            if not cancel then
                importButton:SetEnabled(true)
                clearButton:SetEnabled(true)

                status:SetText(S.Colorize(S.color.bad, err or T["import failed"]))


                local _, tabs = whole:gsub("\t", "")
                local head = (whole:match("^[^\n]*") or ""):sub(1, 80)
                addon.Log:I("Import", "CSV paste rejected:", err or "?",
                    "- tabs:", tabs, "- header:", (head:gsub("|", "||")
                        :gsub("%c", function(c) return ("<%d>"):format(c:byte()) end)))
                return
            end
            pasteCancel = cancel
        end)

        pasteFrame = f
    end


    if pasteCancel then pasteCancel() pasteCancel = nil end
    PasteReset()

    pasteFrame.status:SetText("")
    pasteFrame.edit:SetText("")
    pasteFrame:RestorePosition()
    pasteFrame:Show()
    pasteFrame.edit:SetFocus()
end








local PICKER_W = 520

local function PickerRow(parent, x, width, y, source)
    local row = L.Row(parent, x, width, y, S.size.SET_ROW_H)
    row.sourceKey = source.key

    local box = S.Checkbox(row, S.size.CTRL_H)
    P.Point(box, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
    row:AdoptHover(box)
    row.Box = box



    local label = S.Label(row, S.fontBody, "LEFT")
    label:SetText(source.label)
    P.Point(label, "TOPLEFT", box, "TOPRIGHT", S.size.GAP, 4)
    P.Point(label, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
    row.LabelText = label

    local count = S.Label(row, S.fontSmall, "LEFT")
    P.Point(count, "TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    P.Point(count, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
    row.CountText = count


    local function toggle()
        box:SetChecked(not box:GetChecked())
        if row.onToggle then row.onToggle() end
    end
    row:SetScript("OnMouseUp", toggle)
    box:SetScript("OnClick", toggle)


    local function show(self)
        local detail = row.detail
        if not detail or #detail == 0 then return end
        S.SideTooltip(self)
        S.TooltipSection(GameTooltip, source.label)
        for _, pair in ipairs(detail) do
            GameTooltip:AddDoubleLine(tostring(pair[1]), tostring(pair[2]),
                0.64, 0.63, 0.60, 1, 1, 1)
        end
        GameTooltip:Show()
    end
    row:HookScript("OnEnter", show)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    box:HookScript("OnEnter", function() show(row) end)
    box:HookScript("OnLeave", function() GameTooltip:Hide() end)

    return row, S.size.SET_ROW_H
end

local function BuildPicker()
    local f = S.Window("SimpleLootCouncilHistoryPickerFrame", "historyPicker",
        PICKER_W, 300, T["Import Other History"])

    local content = f.Content
    local cursor = L.Cursor(content)

    f.Hint = cursor:Add(L.Paragraph, "", S.fontHint)
    cursor:Gap(S.size.SECTION)


    f.Rows = {}
    f.rowsTop = cursor.y
    for _, source in ipairs(addon.HistoryImport.SOURCES) do
        local row = cursor:Add(PickerRow, source)
        cursor:Gap(S.size.ITEM_GAP)
        f.Rows[#f.Rows + 1] = row
    end

    f.Empty = cursor:Add(L.Paragraph, "", S.fontSmall)
    cursor:Gap(S.size.SECTION)
    f.Note = cursor:Add(L.Paragraph, "", S.fontSmall)
    cursor:Gap(S.size.SECTION)
    f.Buttons = cursor:Add(L.ButtonRow, {
        { key = "Import", text = T["Import"], opts = { primary = true, width = 130 } },
    })
    f.Import = f.Buttons.Import


    f.Import:SetDisabledReason(S.RequiresSentence(
        T["Requires at least one source to be ticked."]))
    function f:UpdateImport()
        local any = false
        for _, row in ipairs(f.Rows) do
            if row:IsShown() and row.Box:GetChecked() then any = true end
        end
        f.Import:SetEnabled(any)
    end
    for _, row in ipairs(f.Rows) do row.onToggle = f.UpdateImport end

    f.Import:SetScript("OnClick", function()
        local selected = {}
        for _, row in ipairs(f.Rows) do
            if row:IsShown() and row.Box:GetChecked() then
                selected[#selected + 1] = row.sourceKey
            end
        end
        if #selected == 0 then return end

        local results = addon.HistoryImport:FromSources(selected)
        local lines, failed = {}, false
        for _, result in ipairs(results) do
            if result.stats then
                lines[#lines + 1] = addon.Locale.Format(T["%s: %s"], result.label,
                    addon.HistoryImport:Describe(result.stats))
            else
                failed = true
                lines[#lines + 1] = addon.Locale.Format(T["%s: %s"], result.label,
                    result.error or T["import failed"])
            end
        end

        HistoryFrame:Reload()

        summaryText:SetText(S.Colorize(failed and S.color.bad or S.color.good,
            table.concat(lines, "; ")))
        f:Hide()
    end)


    function f:Relayout(visible)
        local rowBlock = visible * (S.size.SET_ROW_H + S.size.ITEM_GAP)
        local y = f.rowsTop - rowBlock

        local emptyH = 0
        if f.Empty:IsShown() then
            emptyH = math.ceil(f.Empty:GetStringHeight() or 14) + S.size.SECTION
        end
        P.Point(f.Empty, "TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - emptyH

        P.Point(f.Note, "TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - math.ceil(f.Note:GetStringHeight() or 14) - S.size.SECTION

        P.Point(f.Buttons, "TOPLEFT", content, "TOPLEFT", 0, y)
        y = y - S.size.BTN_H

        f:SetHeight(P.Snap(f.HeaderHeight + S.size.PAD - y + S.size.PAD))
    end

    return f
end

local function ShowImportPicker()
    if not pickerFrame then pickerFrame = BuildPicker() end
    local f = pickerFrame

    local sources = addon.HistoryImport:GetAvailableSources()
    local byKey = {}
    for _, source in ipairs(sources) do byKey[source.key] = source end

    f.Hint:SetText(#sources > 0
        and T["Tick the histories to bring in. Rows already held, or older than the age limit, are skipped - so importing twice is safe. Closing this window imports nothing."]
        or T["Another addon's history is read straight out of its saved data, so that addon has to be installed and enabled on this client. Enable it, /reload, and come back."])



    local visible, previous = 0, nil
    for _, row in ipairs(f.Rows) do
        local source = byKey[row.sourceKey]
        if source then
            visible = visible + 1
            row.detail = source.detail
            local detail
            if source.duplicate > 0 and source.tooOld > 0 then
                detail = addon.Locale.Format(
                    T["%d entries, %d to import, %d already held, %d too old"],
                    source.entries, source.importable, source.duplicate, source.tooOld)
            elseif source.duplicate > 0 then
                detail = addon.Locale.Format(T["%d entries, %d to import, %d already held"],
                    source.entries, source.importable, source.duplicate)
            elseif source.tooOld > 0 then
                detail = addon.Locale.Format(T["%d entries, %d to import, %d too old"],
                    source.entries, source.importable, source.tooOld)
            else
                detail = addon.Locale.Format(T["%d entries, %d to import"],
                    source.entries, source.importable)
            end
            row.CountText:SetText(S.Colorize(S.color.textMuted, detail))
            row.Box:SetChecked(source.importable > 0)
            row:ClearAllPoints()
            if previous then
                P.Point(row, "TOPLEFT", previous, "BOTTOMLEFT", 0, -S.size.ITEM_GAP)
            else
                P.Point(row, "TOPLEFT", f.Content, "TOPLEFT", 0, f.rowsTop)
            end
            previous = row
            row:Show()
        else
            row:Hide()
        end
    end

    if visible == 0 then
        local names = {}
        for _, source in ipairs(addon.HistoryImport.SOURCES) do
            names[#names + 1] = source.label
        end
        f.Empty:SetText(S.Colorize(S.color.accent,
            addon.Locale.Format(
                T["No supported loot addon's history is loaded. Supported: %s."],
                table.concat(names, ", "))))
        f.Empty:Show()
    else
        f.Empty:SetText("")
        f.Empty:Hide()
    end

    local days = addon.db.importMaxDays or 0
    f.Note:SetText(S.Colorize(S.color.textFaint, days > 0
        and addon.Locale.Format(T["Entries older than %d days are skipped."], days)
        or T["No age limit is set."]))

    f:Relayout(visible)
    f:UpdateImport()
    f:RestorePosition()
    f:Show()
end






local SEARCH_DELAY = 0.2


local function Build()
    frame = S.Window("SimpleLootCouncilHistoryFrame", "history", 1170, 470, T["Loot history"])
    frame:RestorePosition()


    local content = frame.Content
    local cursor = L.Cursor(content)

    local filterRow = cursor:Add(L.Row, S.size.BTN_H)


    filterRow:EnableMouse(false)

    local searchHolder, edit = S.EditBox(filterRow, 300, S.size.BTN_H)
    P.Point(searchHolder, "LEFT", filterRow, "LEFT", 0, 0)
    searchBox = edit

    local typed = 0
    edit:SetScript("OnTextChanged", function(self)
        typed = typed + 1
        local mine = typed
        C_Timer.After(SEARCH_DELAY, function()
            if mine ~= typed then return end
            filter.search = addon.Locale.Fold(self:GetText() or "")
            HistoryFrame:Refresh()
        end)
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)


    local searchHint = S.Label(edit, S.fontHint, "LEFT")
    P.Point(searchHint, "LEFT", 0, 0)
    searchHint:SetText(T["name, item, boss, or a date"])


    edit:HookScript("OnTextChanged", function(self)
        searchHint:SetShown((self:GetText() or "") == "")
    end)
    edit:HookScript("OnEditFocusGained", function() searchHint:Hide() end)
    edit:HookScript("OnEditFocusLost", function(self)
        searchHint:SetShown((self:GetText() or "") == "")
    end)


    sourceButton = S.Button(filterRow, SOURCE_LABEL[filter.source])
    P.Point(sourceButton, "LEFT", searchHolder, "RIGHT", S.size.GAP, 0)
    sourceButton:SetScript("OnClick", function(self)
        local index = 1
        for i, key in ipairs(SOURCE_ORDER) do
            if key == filter.source then index = i end
        end
        filter.source = SOURCE_ORDER[(index % #SOURCE_ORDER) + 1]
        self:SetLabel(SOURCE_LABEL[filter.source])
        HistoryFrame:Refresh()
    end)

    windowButton = S.Button(filterRow, WINDOW_LABEL[filter.days])
    P.Point(windowButton, "LEFT", sourceButton, "RIGHT", S.size.GAP, 0)
    windowButton:SetScript("OnClick", function(self)
        local index = 1
        for i, days in ipairs(WINDOW_ORDER) do
            if days == filter.days then index = i end
        end
        filter.days = WINDOW_ORDER[(index % #WINDOW_ORDER) + 1]
        self:SetLabel(WINDOW_LABEL[filter.days])
        HistoryFrame:Refresh()
    end)

    mineCheck = S.Checkbox(filterRow, S.size.CTRL_H)
    P.Point(mineCheck, "LEFT", windowButton, "RIGHT", S.size.ROW_PAD, 0)
    mineCheck:SetScript("OnClick", function(self)
        filter.mineOnly = not filter.mineOnly
        self:SetChecked(filter.mineOnly)
        HistoryFrame:Refresh()
    end)

    local mineLabel = S.Label(filterRow, S.fontBody, "LEFT")
    P.Point(mineLabel, "LEFT", mineCheck, "RIGHT", S.size.ITEM_GAP, 0)
    mineLabel:SetText(T["Mine only"])


    originButton = HistoryFrame.OriginFilterButton(filterRow, function()
        addon.Callbacks:PaintNow("history")
    end)
    P.Point(originButton, "LEFT", mineLabel, "RIGHT", S.size.SECTION, 0)

    cursor:Gap(S.size.SECTION)

    table_ = cursor:Add(function(parent, x, width, y)
        local t = Tbl.Create(parent, BuildColumns(), 15)
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


    table_.sortColumn, table_.sortAscending = 1, false
    table_.filter = Passes

    table_.onEnter = function(row, data) ShowRowTooltip(row, data) end
    table_.onLeave = function() GameTooltip:Hide() end
    table_.onClick = function(row, data, button)
        if button == "RightButton" then
            ShowRowMenu(row, data)
            return
        end
        if IsShiftKeyDown() and data and data.link then

            local _, canonical = C_Item.GetItemInfo(data.link)
            ChatFrameUtil.InsertLink(canonical or data.link)
        end
    end

    cursor:Gap(S.size.SECTION)

    local footer = cursor:Add(L.Row, S.size.BTN_H)
    footer:EnableMouse(false)

    local wipeButton = HistoryFrame.DeleteButton(footer)
    P.Point(wipeButton, "LEFT", footer, "LEFT", 0, 0)

    summaryText = S.Label(footer, S.fontSmall, "LEFT")
    P.Point(summaryText, "LEFT", wipeButton, "RIGHT", S.size.GAP, 0)




    local exportButton = S.Button(footer, T["Export CSV"])
    P.Point(exportButton, "RIGHT", footer, "RIGHT", 0, 0)

    local SEPARATORS = {
        { key = "comma", label = T["Comma (,)"] },
        { key = "semicolon", label = T["Semicolon (;) - Excel in German, French and more"] },
    }

    local SEPARATOR_HINT = {
        [","] = T["Fields are separated by commas. Right-click to choose another separator."],
        [";"] = T["Fields are separated by semicolons. Right-click to choose another separator."],
    }
    exportButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    exportButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            local items = { { title = T["CSV separator"] } }
            for _, choice in ipairs(SEPARATORS) do
                local key = choice.key
                items[#items + 1] = {
                    text = choice.label,
                    checked = function()
                        return addon.History:Delimiter() == addon.History.DELIMITERS[key]
                    end,
                    onClick = function() addon.db.csvDelimiter = key end,
                }
            end
            S.ContextMenu(self, items)
            return
        end
        addon.ShowHistoryCSV(filter.source == "slc" and "slc" or nil)
    end)
    exportButton:HookScript("OnEnter", function(self)
        local scope = filter.source == "slc" and "slc" or nil
        S.AboveTooltip(self)
        S.TooltipSection(GameTooltip, T["Export CSV"])
        local count = addon.History:CountForScope(scope)
        GameTooltip:AddLine(scope and addon.Locale.Format(addon.Locale.Plural{
            one = "%d row from this addon, imported rows excluded.",
            other = "%d rows from this addon, imported rows excluded.",
        }, count, count) or addon.Locale.Format(addon.Locale.Plural{
            one = "%d row, every source together.",
            other = "%d rows, every source together.",
        }, count, count), 0.64, 0.63, 0.60, true)
        GameTooltip:AddLine(T["Follows the Source filter - set it to \"SimpleLootCouncil\" to leave out rows imported from other addons."],
            0.45, 0.44, 0.42, true)
        GameTooltip:AddLine(SEPARATOR_HINT[addon.History:Delimiter()]
            or SEPARATOR_HINT[","], 0.45, 0.44, 0.42, true)
        HistoryFrame.AddExportOriginLine(GameTooltip)
        GameTooltip:Show()
    end)
    exportButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local pasteButton = S.Button(footer, T["Import CSV"])
    P.Point(pasteButton, "RIGHT", exportButton, "LEFT", -S.size.GAP, 0)
    pasteButton:SetScript("OnClick", ShowPasteWindow)

    local importButton = S.Button(footer, T["Import Other History"])
    P.Point(importButton, "RIGHT", pasteButton, "LEFT", -S.size.GAP, 0)


    local teamButton = S.Button(footer, T["Raid team"])
    P.Point(teamButton, "RIGHT", importButton, "LEFT", -S.size.GAP, 0)


    P.Point(summaryText, "RIGHT", teamButton, "LEFT", -S.size.GAP, 0)
    teamButton:SetScript("OnClick", function()
        addon.UI.RaidTeamFrame:Toggle()
    end)
    teamButton:HookScript("OnEnter", function(self)
        S.AboveTooltip(self)
        S.TooltipSection(GameTooltip, T["Raid team loot"])
        GameTooltip:AddLine(T["The same awards grouped by raider, for the guild ranks you mark as your raid team."], 0.64, 0.63, 0.60, true)
        GameTooltip:Show()
    end)
    teamButton:HookScript("OnLeave", function() GameTooltip:Hide() end)


    frame:SetHeight(P.Snap(
        frame.HeaderHeight + S.size.PAD + cursor:Consumed() + S.size.PAD))
    importButton:SetScript("OnClick", ShowImportPicker)


    importButton:HookScript("OnEnter", function(self)
        S.AboveTooltip(self)
        S.TooltipSection(GameTooltip, T["Import Other History"])
        GameTooltip:AddLine(T["Bring in award history recorded by another loot addon on this client. Opens a window to choose which."],
            0.64, 0.63, 0.60, true)
        S.TooltipSection(GameTooltip, T["Supported Addons"])
        for _, source in ipairs(addon.HistoryImport.SOURCES) do
            local loaded = source.IsAvailable()
            GameTooltip:AddDoubleLine(source.label, loaded and T["loaded"] or T["not loaded"],
                0.64, 0.63, 0.60, loaded and 1 or 0.45, loaded and 1 or 0.44,
                loaded and 1 or 0.42)
        end
        GameTooltip:Show()
    end)
    importButton:HookScript("OnLeave", function() GameTooltip:Hide() end)


    addon.Callbacks:RegisterView("history", {
        paint = function() HistoryFrame:Reload() end,
        frame = frame,
    })

    addon.Log:D("UI", "history frame built")
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

function HistoryFrame:Init()
    S, Tbl = addon.Style, UI.Table
    L, P = addon.Layout, addon.Pixel

    local function Invalidate() addon.Callbacks:Invalidate("history") end
    addon.Callbacks:Register("ItemAwarded", Invalidate)
    addon.Callbacks:Register("HistoryChanged", Invalidate)
    addon.Callbacks:Register("HistoryFilterChanged", function()
        refilter = true
        Invalidate()
    end)

    addon.Log:I("UI", "history frame ready")
end

function HistoryFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    WhenBuilt(function()

        addon.Callbacks:Invalidate("history")
        frame:Show()
    end)
end
