if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local Panel = {}
UI.ConfigShareFrame = Panel

local S, L, P
local sendFrame, councilBox, responsesBox, councilCount, responsesCount, nameEdit
local buttons = {}
local offerFrame, offerPrompt, offerHint, offerAccept, shownOffer
local offerLines = {}

local SEND_W = 460
local OFFER_W = 440
local LINE_H, LINE2_H = 18, 34

local function Print(text)
    print(addon.Log.CHAT_PREFIX.accent .. text)
end





local function TypedName()
    return nameEdit and nameEdit:GetText():trim() or ""
end


local function SendReason(audience)
    if not addon.ConfigShare:MaySend() then
        return S.RequiresSentence(T["Requires you to be the group leader or the Loot Master."])
    end
    if not councilBox:GetChecked() and not responsesBox:GetChecked() then
        return S.RequiresSentence(T["Requires loot council or response buttons to be ticked."])
    end
    if audience == "council" then
        if not IsInGroup() then
            return S.RequiresSentence(T["Requires you to be in a group."])
        end
        if #addon.ConfigShare:CouncilRecipients() == 0 then
            return S.RequiresSentence(T["Requires another loot council member in your group."])
        end
    elseif audience == "raid" then
        if not IsInGroup() then
            return S.RequiresSentence(T["Requires you to be in a group."])
        end
    elseif audience == "player" then
        local name = TypedName()
        if name == "" then
            return S.RequiresSentence(T["Requires a player name in the box above."])
        end
        if addon.Player:IsSelf(addon.Player:Qualify(name)) then
            return S.RequiresSentence(T["Requires a player other than you."])
        end
    end
    return nil
end

function Panel:RefreshSend()
    if not sendFrame or not sendFrame:IsShown() then return end
    local members = #(addon.db.council or {})
    local ranks = #addon.Council:GetConfiguredRanks()
    councilCount:SetText(ranks > 0
        and addon.Locale.Format(addon.Locale.Plural{
            one = "%d player, %d guild rank(s)", other = "%d players, %d guild rank(s)",
        }, members, members, ranks)
        or addon.Locale.Format(addon.Locale.Plural{
            one = "%d player", other = "%d players",
        }, members, members))
    local count = #(addon.db.responses or {})
    responsesCount:SetText(addon.Locale.Format(addon.Locale.Plural{
        one = "%d button", other = "%d buttons",
    }, count, count))
    for audience, b in pairs(buttons) do
        local reason = SendReason(audience)
        b:SetEnabled(reason == nil)
        b:SetDisabledReason(reason)
    end
end

local function Sent(audience, count, target)
    if audience == "council" then
        Print(addon.Locale.Format(addon.Locale.Plural{
            one = "config sent to %d loot council member - they are asked to accept it.",
            other = "config sent to %d loot council members - they are asked to accept it.",
        }, count, count))
    elseif audience == "raid" then
        Print(addon.Locale.Format(addon.Locale.Plural{
            one = "config sent to %d player in your group - they are asked to accept it.",
            other = "config sent to %d players in your group - they are asked to accept it.",
        }, count, count))
    else
        Print(addon.Locale.Format(T["config sent to %s - they are asked to accept it."],
            tostring(target)))
    end
end

local function DoSend(audience)

    local reason = SendReason(audience)
    if reason then
        Print(addon.Locale.Format(T["not sent. %s"], reason))
        Panel:RefreshSend()
        return
    end
    local count, _, target = addon.ConfigShare:Send(audience, councilBox:GetChecked(),
        responsesBox:GetChecked(), TypedName())
    if not count then
        Print(T["not sent - see /slc log."])
        return
    end
    Sent(audience, count, target)
    sendFrame:Hide()
end

local function CheckRow(cursor, label, onToggle)
    local box, count
    cursor:Add(function(parent, x, width, y)
        local row = L.Row(parent, x, width, y)
        box = S.Checkbox(row, S.size.CTRL_H, onToggle)
        P.Point(box, "LEFT", row, "LEFT", S.size.ROW_PAD, 0)
        row:AdoptHover(box)
        count = S.Label(row, S.fontSmall, "RIGHT")
        P.Point(count, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
        local text = S.Label(row, S.fontSetting, "LEFT")
        text:SetText(label)
        P.Point(text, "LEFT", box, "RIGHT", S.size.GAP, 0)
        P.Point(text, "RIGHT", count, "LEFT", -S.size.GAP, 0)

        row:SetScript("OnMouseUp", function() box:Click() end)
        return row, S.size.ROW_H
    end)
    box:SetChecked(true)
    return box, count
end

local function BuildSend()
    sendFrame = S.Window("SimpleLootCouncilSendConfigFrame", "sendConfig", SEND_W, 300,
        T["Send config"])
    sendFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    local cursor = L.Cursor(sendFrame.Content)
    cursor:Add(L.Paragraph,
        T["Sends your own loot council and response buttons. Each player is asked before anything of theirs is replaced."],
        S.fontHint)
    cursor:Gap(S.size.SECTION)

    local function Changed() Panel:RefreshSend() end
    councilBox, councilCount = CheckRow(cursor, T["Loot council"], Changed)
    responsesBox, responsesCount = CheckRow(cursor, T["Response buttons"], Changed)
    cursor:Gap()

    cursor:Add(function(parent, x, width, y)
        local row = L.Row(parent, x, width, y)
        local holder, edit = S.EditBox(row, 260)
        P.Point(holder, "RIGHT", row, "RIGHT", -S.size.ROW_PAD, 0)
        row:AdoptHover(edit)
        nameEdit = edit
        L.BoundedLabel(row, holder, T["Player"], S.fontSetting)
        edit:SetScript("OnTextChanged", Changed)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if not SendReason("player") then DoSend("player") end
        end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return row, S.size.ROW_H
    end)
    cursor:Add(L.Paragraph, addon.IsForever
        and T["A character name, for Player. Council and Raid need no name."]
        or T["Name-Realm, for Player. Council and Raid need no name."],
        S.fontHint)
    cursor:Gap(S.size.SECTION)

    local row = cursor:Add(L.ButtonRow, {
        { key = "cancel", text = T["Cancel"], onClick = function() sendFrame:Hide() end },
        { key = "player", text = T["Player"], onClick = function() DoSend("player") end },
        { key = "raid", text = T["Raid"], onClick = function() DoSend("raid") end },
        { key = "council", text = T["Council"], opts = { primary = true },
            onClick = function() DoSend("council") end },
    })
    buttons.council, buttons.raid, buttons.player = row.council, row.raid, row.player

    sendFrame:SetHeight(P.Snap(sendFrame.HeaderHeight + S.size.PAD * 2 + cursor:Consumed()))
    sendFrame:HookScript("OnShow", function() Panel:RefreshSend() end)
    sendFrame:HookScript("OnHide", function() S.HideTextTooltip() end)
end



local building

function Panel:ToggleSend()
    if sendFrame and sendFrame:IsShown() then
        sendFrame:Hide()
        return
    end
    if sendFrame then
        sendFrame:RestorePosition()
        sendFrame:Show()
    elseif not building then
        building = true
        S.BuildOnDriver(function()
            building = false
            BuildSend()
            sendFrame:RestorePosition()
            sendFrame:Show()
        end)
    end
end





local function OfferPrompt(offer)
    if offer.council and offer.responses then
        return addon.Locale.Format(T["%s sent you their loot council and response buttons."], offer.from)
    elseif offer.council then
        return addon.Locale.Format(T["%s sent you their loot council."], offer.from)
    end
    return addon.Locale.Format(T["%s sent you their response buttons."], offer.from)
end


local function OfferDetail(offer)
    local out = {}
    if offer.council then
        local n = #offer.council.members
        local names = {}
        for i, member in ipairs(offer.council.members) do
            if i > 8 then break end
            names[#names + 1] = Ambiguate(member.name, "none")
        end
        out[#out + 1] = { addon.Locale.Format(addon.Locale.Plural{
            one = "Loot council: %d player - %s", other = "Loot council: %d players - %s",
        }, n, n, n > 0 and table.concat(names, ", ") or T["nobody"]), LINE2_H }
        local ranks = offer.council.ranks
        if #ranks > 0 then
            local guild = addon.RaidTeam and addon.RaidTeam:GetGuildName()
            if guild and guild == offer.council.guild then
                out[#out + 1] = { addon.Locale.Format(T["Guild ranks: %s"],
                    table.concat(ranks, ", ")), LINE2_H }
            else
                out[#out + 1] = { T["Their guild ranks are left out: they belong to another guild."], LINE_H }
            end
        end
    end
    if offer.responses then
        local names = {}
        for _, entry in ipairs(offer.responses) do names[#names + 1] = entry.text end
        out[#out + 1] = { addon.Locale.Format(T["Response buttons: %s"],
            table.concat(names, ", ")), LINE2_H }
    end
    return out
end

local function BuildOffer()
    offerFrame = S.Window("SimpleLootCouncilConfigOfferFrame", "configOffer", OFFER_W, 240,
        T["Config received"])
    offerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    local content = offerFrame.Content
    offerPrompt = S.Label(content, S.fontBody, "LEFT", 2)
    offerHint = S.Label(content, S.fontHint, "LEFT", 2)
    offerHint:SetText(T["Accept replaces your own. Decline leaves yours as they are."])

    local decline = S.Button(content, T["Decline"])
    P.Point(decline, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    decline:SetScript("OnClick", function()
        addon.ConfigShare:Decline()
    end)
    offerAccept = S.Button(content, T["Accept"], { primary = true })
    P.Point(offerAccept, "RIGHT", decline, "LEFT", -S.size.GAP, 0)
    offerAccept:SetScript("OnClick", function()
        local ok, members, ranksApplied, buttonCount, offer = addon.ConfigShare:Accept()
        if not ok then return end
        if offer.council then
            Print(addon.Locale.Format(addon.Locale.Plural{
                one = "loot council replaced: %d player from %s.",
                other = "loot council replaced: %d players from %s.",
            }, members, members, offer.from))
            if ranksApplied then Print(T["guild ranks replaced too."]) end
        end
        if offer.responses then
            Print(addon.Locale.Format(addon.Locale.Plural{
                one = "response buttons replaced: %d button from %s.",
                other = "response buttons replaced: %d buttons from %s.",
            }, buttonCount, buttonCount, offer.from))
        end
    end)

    offerFrame:HookScript("OnHide", function()
        local offer = shownOffer
        shownOffer = nil
        if not offer or addon.ConfigShare:GetPending() ~= offer then return end

        addon.AutoClose:AfterHide(function(swept)
            if addon.ConfigShare:GetPending() ~= offer then return end
            if swept then
                Panel:RefreshOffer()
            else
                addon.ConfigShare:Decline()
            end
        end)
    end)
end

local function OfferLine(index)
    local line = offerLines[index]
    if not line then
        line = S.Label(offerFrame.Content, S.fontSmall, "LEFT", 2)
        line:SetJustifyV("TOP")
        offerLines[index] = line
    end
    return line
end

function Panel:RefreshOffer()
    local offer = addon.ConfigShare:GetPending()
    if not offer then
        shownOffer = nil
        if offerFrame then offerFrame:Hide() end
        return
    end
    if not offerFrame then BuildOffer() end
    local content = offerFrame.Content
    local width = OFFER_W - S.size.PAD * 2
    local y = 0
    offerPrompt:SetText(OfferPrompt(offer))
    P.Point(offerPrompt, "TOPLEFT", content, "TOPLEFT", 0, -y)
    P.Size(offerPrompt, width, LINE2_H)
    y = y + LINE2_H + S.size.GAP

    local detail = OfferDetail(offer)
    for index, entry in ipairs(detail) do
        local line = OfferLine(index)
        line:SetText(entry[1])
        line:ClearAllPoints()
        P.Point(line, "TOPLEFT", content, "TOPLEFT", 0, -y)
        P.Size(line, width, entry[2])
        line:Show()
        y = y + entry[2] + S.size.ITEM_GAP
    end
    for index = #detail + 1, #offerLines do offerLines[index]:Hide() end

    y = y + S.size.GAP
    offerHint:ClearAllPoints()
    P.Point(offerHint, "TOPLEFT", content, "TOPLEFT", 0, -y)
    P.Size(offerHint, width, LINE2_H)
    y = y + LINE2_H + S.size.SECTION + S.size.BTN_H

    local blocked = addon.ConfigShare:AcceptBlocker(offer)
    offerAccept:SetEnabled(blocked == nil)
    offerAccept:SetDisabledReason(blocked
        and S.RequiresSentence(T["Requires no loot run in progress."]) or nil)

    local fresh = shownOffer ~= offer
    shownOffer = offer
    offerFrame:SetHeightFromTop(offerFrame.HeaderHeight + S.size.PAD * 2 + y)
    if fresh and not offerFrame:IsShown() then offerFrame:RestorePosition() end
    offerFrame:Show()
end

function Panel:Init()
    S, L, P = addon.Style, addon.Layout, addon.Pixel
    addon.Callbacks:Register("ConfigOfferChanged", function() Panel:RefreshOffer() end)
    for _, event in ipairs({ "RosterChanged", "CouncilChanged", "LootMasterChanged",
        "SharedConfigChanged" }) do
        addon.Callbacks:Register(event, function() Panel:RefreshSend() end)
    end
end
