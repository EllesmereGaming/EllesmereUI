if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local VoterFrame = {}
UI.VoterFrame = VoterFrame

local S, L, P


local frame, ticker
local entries = {}



local view
local laidOutCount, laidOutWidth


local rollLogPending




local dismissedRun, dismissedMax = nil, 0



local suppressDismiss = false


local ENTRY_HEIGHT
local RESPONSE_BUTTON_H = 26


local WISH_ICON, WISH_ICON_GAP, WISH_ICON_INSET = 12, 4, 1

local BUTTON_INSET



local VISIBLE_CARDS, COMPACT_CARDS = 8, 2
local CARDS_PER_PAINT = 4

local SCROLL_CHANNEL

local MIN_WIDTH = 400
local scroll, compactButton
local laidOutVisible

local TAG_OFFSET
local tagShift = 0


local function CompactWidths()
    compactButton:SetLabel(T["Expand"])
    local expand = compactButton:GetWidth()
    compactButton:SetLabel(T["Compact"])
    local compact = compactButton:GetWidth()
    compactButton:SetLabel(addon.db.voterCompact and T["Expand"] or T["Compact"])
    return math.min(expand, compact), math.max(expand, compact)
end



local function PlaceTag()
    local tag = frame.Tag
    if not tag:IsShown() then return end
    local tagRight, compactRight = tag:GetRight(), compactButton:GetRight()
    if not tagRight or not compactRight then return end
    local narrow, wide = CompactWidths()
    local tagBase = tagRight - tagShift
    local gap = compactRight - narrow - tagBase
    local room = compactRight - wide - S.size.GAP - tagBase
    local shift = math.min(gap * 3 / 4, room)
    shift = shift > 0 and P.Snap(shift, frame) or 0
    if shift == tagShift then return end
    tagShift = shift
    tag:ClearAllPoints()
    P.Point(tag, "LEFT", frame.Title, "RIGHT", TAG_OFFSET + shift, 0)
end


local function Clock(seconds)
    seconds = math.max(0, math.ceil(seconds or 0))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end



local CLOCK_EXTRA = 6


local clockWidths = {}
local function ClockTemplateWidth(label, template)
    local width = clockWidths[template]
    if not width then
        label:SetText(template)
        width = label:GetUnboundedStringWidth()
        if width > 0 then clockWidths[template] = width end
    end
    return width
end

local function UpdateNoteButton(e)
    if not e.noteButton then return end
    local hasNote = (e.noteEdit:GetText() or "") ~= ""
    e.noteButton:SetColour(hasNote and S.color.accent or nil,
        hasNote and S.color.accent or nil)
end







local function AnchorEntry(e, index)
    local prev = entries[index - 1]
    e:ClearAllPoints()
    if prev then
        P.Point(e, "TOPLEFT", prev, "BOTTOMLEFT", 0, -S.size.ITEM_GAP)
        P.Point(e, "TOPRIGHT", prev, "BOTTOMRIGHT", 0, -S.size.ITEM_GAP)
    else
        P.Point(e, "TOPLEFT", scroll.Content, "TOPLEFT", 0, 0)
        P.Point(e, "TOPRIGHT", scroll.Content, "TOPRIGHT", 0, 0)
    end
end

local function CreateEntry(parent, index)
    local e = CreateFrame("Frame", nil, parent)
    L.Above(e, parent)
    P.Size(e, nil, ENTRY_HEIGHT)

    S.RoundFill(e, S.color.card, S.radius.CTRL, "BACKGROUND")
    e.border = S.RoundBorder(e, S.color.edge, "BORDER", S.radius.CTRL)

    e.icon = S.ItemIcon(e, S.size.ICON)
    P.Point(e.icon, "TOPLEFT", S.size.ROW_PAD, -S.size.ROW_PAD)



    e.clockBox = CreateFrame("Frame", nil, e)
    P.Point(e.clockBox, "TOPLEFT", e.icon, "BOTTOMLEFT", -CLOCK_EXTRA / 2, -S.size.ITEM_GAP)
    P.Point(e.clockBox, "TOPRIGHT", e.icon, "BOTTOMRIGHT", CLOCK_EXTRA / 2, -S.size.ITEM_GAP)
    P.Point(e.clockBox, "BOTTOM", e, "BOTTOM", 0, S.size.ROW_PAD)
    S.Fill(e.clockBox, S.color.inset)
    S.Border(e.clockBox, S.color.border, "BORDER")


    e.clock = S.Label(e.clockBox, S.fontNumLarge, "LEFT")


    e.timerBar = S.ProgressBar(e, 3)
    e.timerBar:SetPoint("BOTTOMLEFT", 1, 1)
    e.timerBar:SetPoint("BOTTOMRIGHT", -1, 1)


    e.name = S.Label(e, S.fontBody, "LEFT")
    P.Point(e.name, "TOPLEFT", e.icon, "TOPRIGHT", S.size.GAP, 0)
    P.Point(e.name, "TOPRIGHT", e, "TOPRIGHT", -S.size.ROW_PAD, -S.size.ROW_PAD)

    e.detail = S.Label(e, S.fontSmall, "LEFT")
    P.Point(e.detail, "TOPLEFT", e.name, "BOTTOMLEFT", 0, -2)
    P.Point(e.detail, "TOPRIGHT", e.name, "BOTTOMRIGHT", 0, -2)


    e.wish = S.Label(e, S.fontSmall, "LEFT")
    P.Point(e.wish, "TOPLEFT", e.detail, "BOTTOMLEFT", 0, -2)
    P.Point(e.wish, "RIGHT", e.name, "RIGHT", 0, 0)

    e.wishIcon = e:CreateTexture(nil, "ARTWORK")
    P.Size(e.wishIcon, WISH_ICON, WISH_ICON)
    P.Point(e.wishIcon, "LEFT", e.wish, "LEFT", -(WISH_ICON + WISH_ICON_GAP), 0)
    e.wishIcon:Hide()
    e.wishIconShown = false




    e.status = S.Label(e, S.fontSmall, "RIGHT")
    P.Point(e.status, "TOPRIGHT", e.name, "BOTTOMRIGHT", S.size.ROW_PAD - S.size.GAP, -2)
    e.status:SetTextColor(S.Unpack(S.color.bad))
    e.status:Hide()

    e.appearance = S.Label(e, S.fontSmall, "RIGHT")
    P.Point(e.appearance, "TOPRIGHT", e.status, "TOPLEFT", -S.size.GAP, 0)
    e.appearance:SetTextColor(S.Unpack(S.color.accent))
    e.appearance:SetText(T["Appearance available"])
    e.appearance:Hide()
    e.statusShown, e.warned = 0, false

    local bad = S.color.bad
    e.warnFill = S.RoundFill(e, { bad[1], bad[2], bad[3], 0.14 }, S.radius.CTRL, "BACKGROUND", 1)
    e.warnFill:Hide()




    e.buttonRow = CreateFrame("Frame", nil, e)
    P.Point(e.buttonRow, "BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
    P.Size(e.buttonRow, nil, RESPONSE_BUTTON_H)


    e.buttons = {}




    e.noteComposer = CreateFrame("Frame", nil, e)
    P.Point(e.noteComposer, "BOTTOMLEFT", e.clockBox, "BOTTOMRIGHT",
        S.size.ITEM_GAP, 0)
    P.Point(e.noteComposer, "BOTTOMRIGHT", e, "BOTTOMRIGHT",
        -BUTTON_INSET, BUTTON_INSET)
    P.Size(e.noteComposer, nil, S.size.BTN_H_SM)

    e.noteDone = S.Button(e.noteComposer, T["Done"],
        { width = 62, height = S.size.BTN_H_SM, primary = true })
    P.Point(e.noteDone, "RIGHT", 0, 0)

    e.noteBox, e.noteEdit = S.EditBox(e.noteComposer, 10, S.size.BTN_H_SM)
    P.Point(e.noteBox, "TOPLEFT", 0, 0)
    P.Point(e.noteBox, "BOTTOMRIGHT", e.noteDone, "BOTTOMLEFT", -S.size.ITEM_GAP, 0)
    e.noteEdit:SetMaxLetters(addon.Config:NoteMax())



    local hint = S.Label(e.noteEdit, S.fontHint, "LEFT")
    P.Point(hint, "LEFT", 0, 0)
    hint:SetText(T["optional note"])
    e.hint = hint

    local function SaveNote(send)

        if not e.noteSessions or e.auto then return end
        local note = e.noteEdit:GetText() or ""
        for _, session in ipairs(e.noteSessions) do
            addon.Session:SetNote(session, note, send)
        end
    end

    local function FlushNote()
        local note = e.noteEdit:GetText() or ""
        if not e.noteSessions or note == e.sentNote then return end
        e.noteGeneration = (e.noteGeneration or 0) + 1
        e.sentNote = note
        SaveNote(true)
    end
    e.flushNote = FlushNote

    local function SyncHint(self)
        hint:SetShown((self:GetText() or "") == "")
        UpdateNoteButton(e)
        if e.suppressNoteUpdate or not e.noteSessions then return end
        SaveNote(false)
        e.noteGeneration = (e.noteGeneration or 0) + 1
        local generation = e.noteGeneration
        local runId, groupKey = addon.Session:GetRunId(), e.groupKey
        C_Timer.After(0.5, function()
            if e.noteGeneration == generation and e.groupKey == groupKey
                and addon.Session:GetRunId() == runId then
                FlushNote()
            end
        end)
    end
    e.noteEdit:HookScript("OnTextChanged", SyncHint)
    e.noteEdit:HookScript("OnEditFocusGained", function() hint:Hide() end)
    e.noteEdit:HookScript("OnEditFocusLost", function(self)
        SyncHint(self)
        FlushNote()
    end)

    local function CloseComposer()
        FlushNote()
        e.noteComposer:Hide()
        e.buttonRow:Show()
    end
    e.noteDone:SetScript("OnClick", CloseComposer)
    e.noteEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        CloseComposer()
    end)
    e.noteEdit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        CloseComposer()
    end)
    e.noteComposer:Hide()

    entries[index] = e
    AnchorEntry(e, index)
    return e
end



local BUTTON_GAP = 6
local NOTE_BUTTON_WIDTH = 30



local function RemeasureAfterLayout()
    P.AfterLayout(function() addon.Callbacks:Invalidate("voter") end)
end


local function StripWidth(buttons)
    local width = 0
    for i, button in ipairs(buttons) do
        width = width + button:GetWidth() + (i > 1 and BUTTON_GAP or 0)
    end
    return width
end



local NOTE_TOOLTIP_LETTERS = 31

local function EnsureNoteButton(e)
    if e.noteButton then return e.noteButton end

    e.noteButton = S.Button(e.buttonRow, "", {
        width = NOTE_BUTTON_WIDTH, height = S.size.BTN_H_SM, glyph = "chat",
    })
    e.noteButton:SetScript("OnClick", function()
        e.buttonRow:Hide()
        e.noteComposer:Show()
        e.noteEdit:SetFocus()
    end)

    e.noteButton.slcHoverIn = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        S.TooltipSection(GameTooltip, T["Note"])
        local note = e.noteEdit:GetText() or ""
        if note ~= "" then
            for _, line in ipairs(addon.Locale.Wrap(note, NOTE_TOOLTIP_LETTERS)) do
                GameTooltip:AddLine(line, 1, 1, 1, false)
            end
        else
            GameTooltip:AddLine(T["Click to add a note"], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end
    e.noteButton.slcHoverOut = function() GameTooltip:Hide() end
    UpdateNoteButton(e)
    return e.noteButton
end




local function Respond(e, response)
    e.flushNote()
    local note = e.noteEdit:GetText()
    if note == "" then note = nil end
    for _, session in ipairs(e.noteSessions or {}) do
        addon.Session:Respond(session, response, note)
    end
    VoterFrame:Refresh()
end


local function EnsureResponseButtons(e, responses)
    local needed = #responses + 1
    for i = 1, needed do
        if not e.buttons[i] then
            local b = S.Button(e.buttonRow, "", { height = RESPONSE_BUTTON_H })
            b:SetScript("OnClick", function() Respond(e, b.response or nil) end)
            e.buttons[i] = b
        end
    end
    for i = needed + 1, #e.buttons do e.buttons[i]:Hide() end
    local labels = { "labels" }
    for _, response in ipairs(responses) do labels[#labels + 1] = response.text end
    local sig = table.concat(labels, "\n")
    if e.labelSig ~= sig then
        e.labelSig = sig
        for i, response in ipairs(responses) do e.buttons[i]:SetLabel(response.text) end
        e.buttons[needed]:SetLabel(T["Pass"])
        RemeasureAfterLayout()
    end
    local strip = { e.noteButton }
    for i = 1, needed do strip[#strip + 1] = e.buttons[i] end
    return strip, needed
end


local function LayoutRoll(e, group)
    EnsureNoteButton(e)
    if not e.rollButton then
        e.rollButton = S.Button(e.buttonRow, T["Roll"],
            { height = RESPONSE_BUTTON_H, primary = true })


        e.rollButton:SetScript("OnClick", function() addon.Roll:Roll() end)
    end

    local responseStrip = EnsureResponseButtons(e, addon.Config:Responses())
    for _, button in ipairs(e.buttons) do button:Hide() end



    local label = group.rollOwed > 1
        and addon.Locale.Format(T["Roll  (%d left)"], group.rollOwed) or T["Roll"]
    local sig = "roll\n" .. label
    if e.stripSig ~= sig then
        e.stripSig = sig
        e.rollButton:ClearAllPoints()
        e.rollButton:SetPoint("RIGHT", e.buttonRow, "RIGHT", 0, 0)
        e.rollButton:SetLabel(label)


        e.noteButton:ClearAllPoints()
        e.noteButton:SetPoint("RIGHT", e.rollButton, "LEFT", -BUTTON_GAP, 0)
        RemeasureAfterLayout()
    end

    e.buttonRow:SetWidth(math.max(StripWidth({ e.noteButton, e.rollButton }),
        StripWidth(responseStrip)))
    e.rollButton:Show()
    e.noteButton:Show()

    local blocked = addon.Restrictions:IsBlocked()
    e.rollButton:SetDisabledReason(blocked
        and (addon.Restrictions:GetBlockReason()
            or S.RequiresSentence(T["Requires comms to be available."])) or nil)
    e.rollButton:SetEnabled(not blocked)
end


local function LayoutButtons(e, group)
    e.noteSessions = group.sessions
    local responses = addon.Config:Responses()
    local needed = #responses + 1

    EnsureNoteButton(e)

    local autoReason = group.auto
        and addon.Autopass.NoteText(addon.Autopass.AUTO_PREFIX .. group.auto) or nil
    e.noteButton:SetDisabledReason(autoReason)
    e.noteButton:SetEnabled(not group.auto)
    e.auto = group.auto
    if group.auto and e.noteComposer:IsShown() then
        e.noteComposer:Hide()
        e.buttonRow:Show()
    end


    if group.rollOwed > 0 then
        LayoutRoll(e, group)
        return
    end
    if e.rollButton then e.rollButton:Hide() end

    for i = 1, needed do
        if not e.buttons[i] then
            local b = S.Button(e.buttonRow, "", { height = RESPONSE_BUTTON_H })
            b:SetScript("OnClick", function() Respond(e, b.response or nil) end)
            e.buttons[i] = b
        end
    end

    for i = needed + 1, #e.buttons do
        e.buttons[i]:Hide()
    end


    local labels = { "responses" }
    for _, response in ipairs(responses) do labels[#labels + 1] = response.text end
    local sig = table.concat(labels, "\n")
    local relabel = e.stripSig ~= sig
    e.stripSig = sig

    for i, response in ipairs(responses) do
        local b = e.buttons[i]
        b.response = i
        if relabel then b:SetLabel(response.text) end
        b:SetColour({ response.r, response.g, response.b })
        b:SetSelected(group.response == i)
        b:Show()
    end

    local pass = e.buttons[needed]
    pass.response = false
    if relabel then pass:SetLabel(T["Pass"]) end
    pass:SetColour(nil)
    pass:SetSelected(group.passed)
    pass:Show()



    local strip = { e.noteButton }
    for i = 1, needed do strip[#strip + 1] = e.buttons[i] end
    if relabel then
        local nextButton
        for i = #strip, 1, -1 do
            local b = strip[i]
            b:ClearAllPoints()
            if nextButton then
                b:SetPoint("RIGHT", nextButton, "LEFT", -BUTTON_GAP, 0)
            else
                b:SetPoint("RIGHT", e.buttonRow, "RIGHT", 0, 0)
            end
            nextButton = b
        end
        RemeasureAfterLayout()
    end

    e.buttonRow:SetWidth(StripWidth(strip))
    e.noteButton:Show()



    local blocked = addon.Restrictions:IsBlocked()
    local blockReason = blocked
        and (addon.Restrictions:GetBlockReason()
            or S.RequiresSentence(T["Requires comms to be available."]))
        or nil
    for i = 1, needed do
        e.buttons[i]:SetDisabledReason(autoReason or blockReason)
        e.buttons[i]:SetEnabled(not blocked and not group.auto)
    end
    if blocked then
        e.hint:SetText(addon.Restrictions:GetBlockReason() or T["unavailable"])
    else
        e.hint:SetText(T["optional note"])
    end
end







local function DetailText(group, me)
    local parts = {}

    local ilvl = select(4, C_Item.GetItemInfo(group.link))
    if ilvl then
        parts[#parts + 1] = addon.Locale.Format(T["Item Level %s"], ilvl)
    end



    if group.rollOwed > 0 then
        table.insert(parts, 1,
            S.Colorize(S.color.accent, T["The council has asked you to roll"]))
    elseif group.roll then


        table.insert(parts, 1, S.Colorize(S.color.textMuted, T["Rolled"] .. " ")
            .. S.Colorize(S.color.text, tostring(group.roll))
            .. (group.rollBy == "leader"
                and S.Colorize(S.color.textFaint, " " .. T["(assigned)"]) or ""))
    end



    return table.concat(parts, S.Colorize(S.color.textFaint, "  -  "))
end



local function WishText(group, me)
    if not addon.Wishlist then return "" end
    local parts = {}
    local pick = addon.Wishlist:For(me, group.item)

    if pick and pick.label then
        parts[#parts + 1] = S.Colorize(pick.colour or S.color.text, pick.label)
    end

    local sim = addon.Wishlist:SimFor(me, group.item)
    local gain = addon.Wishlist.FormatGain(sim)
    if gain then
        parts[#parts + 1] = S.Colorize(addon.Wishlist.GainColour(sim.pct), gain)
    end
    if #parts == 0 then return "" end
    return table.concat(parts, S.Colorize(S.color.textFaint, "  -  "))
end



local function PlaceWish(e, text)
    local icon = text ~= "" and addon.Wishlist and addon.Wishlist:SourceIcon() or nil
    if icon then e.wishIcon:SetTexture(icon) end
    e.wishIcon:SetShown(icon ~= nil)
    local shown = icon ~= nil
    if e.wishIconShown ~= shown then
        e.wishIconShown = shown
        e.wish:ClearAllPoints()
        P.Point(e.wish, "TOPLEFT", e.detail, "BOTTOMLEFT",
            shown and WISH_ICON_INSET + WISH_ICON + WISH_ICON_GAP or 0, -2)
        P.Point(e.wish, "RIGHT", e.name, "RIGHT", 0, 0)
    end
    e.wish:SetText(text)
end


local function GroupItems()
    local me = addon.Player:GetFullName("player")
    local groups, order = {}, {}




    local decided = {
        RESPONDED = true,
        PASS = true,
        AWARDED = true,
    }

    for _, item in ipairs(addon.Session:GetItems()) do
        local candidate = item.candidates[me]
        local answered = candidate and decided[candidate.status]

        local owesRoll = addon.Roll and addon.Roll.OwedBy(item, me) or false

        local auto = not owesRoll and candidate and candidate.status == "PASS"
            and addon.Autopass and addon.Autopass.AutoCode(candidate.note) or nil

        if not item.awarded and not item.removed and (not answered or owesRoll or auto) then
            local key = (item.link or tostring(item.session)) .. (auto and "\nauto" or "")
            if not groups[key] then


                groups[key] = {
                    link = item.link,
                    item = item,
                    sessions = {},
                    response = candidate and candidate.response or nil,

                    note = not auto and candidate and candidate.note or nil,
                    passed = candidate and candidate.status == "PASS" or false,


                    rollOwed = 0,

                    auto = auto,
                }
                order[#order + 1] = key
            end
            local group = groups[key]
            group.sessions[#group.sessions + 1] = item.session
            if owesRoll then group.rollOwed = group.rollOwed + 1 end
            if candidate and candidate.roll then
                group.roll = candidate.roll
                group.rollBy = candidate.rollBy
            end
        end
    end


    local list = {}
    for _, key in ipairs(order) do
        if not groups[key].auto then list[#list + 1] = groups[key] end
    end
    for _, key in ipairs(order) do
        if groups[key].auto then list[#list + 1] = groups[key] end
    end
    return list
end


local function AskingCount(groups)
    local asking = 0
    for _, group in ipairs(groups) do
        if not group.auto then asking = asking + 1 end
    end
    return asking
end


function VoterFrame:UpdateTimers()
    if not frame or not frame:IsShown() then return end

    local left = addon.Session:GetTimeLeft()
    local duration = addon.Session:GetTimerDuration()

    for _, e in ipairs(entries) do
        if e:IsShown() then
            if left and duration and duration > 0 then
                e.timerBar:Show()
                e.clockBox:Show()
                local fraction = left / duration
                e.timerBar:SetProgress(fraction)


                local text = Clock(left)
                local template = (text:gsub("%d", "0"))
                if e.clockTemplate ~= template then
                    local width = ClockTemplateWidth(e.clock, template)
                    e.clock:ClearAllPoints()
                    P.Point(e.clock, "LEFT", e.clockBox, "CENTER", -width / 2, 0)
                    e.clockTemplate = width > 0 and template or nil
                end
                e.clock:SetText(text)

                e.clock:SetTextColor(S.Unpack(fraction <= 0 and S.color.bad
                    or fraction <= 0.33 and S.color.warn or S.color.accentPale))
            else
                e.timerBar:Hide()
                e.clockBox:Hide()
                e.clock:SetText("")
            end
        end
    end
end



local function OutstandingMax(groups)
    local highest = 0
    for _, group in ipairs(groups) do

        if not group.auto then
            for _, session in ipairs(group.sessions) do
                if session > highest then highest = session end
            end
        end
    end
    return highest
end


local function HideInternally()
    if not frame then return end
    suppressDismiss = true
    frame:Hide()
    suppressDismiss = false
end


local verdictRetry = false





local function PaintStatus(e, group)
    local text, warn, look, pending = nil, false, false, false
    if group.auto then
        text = T["Autopassed"]
    elseif addon.Autopass then
        local _, code, judged, appearance = addon.Autopass:WouldPass(group.link)
        pending = not judged

        if code and (appearance or not addon.db.autopass) then
            text, look, warn = addon.Autopass.CardReason(code), appearance, not appearance
        end
    end
    e.status:SetText(text or "")

    local shown = text and (look and 2 or 1) or 0

    if e.statusShown ~= shown then
        e.statusShown = shown
        e.status:SetShown(shown > 0)
        e.appearance:SetShown(shown == 2)
        e.detail:ClearAllPoints()
        P.Point(e.detail, "TOPLEFT", e.name, "BOTTOMLEFT", 0, -2)
        if shown > 0 then
            P.Point(e.detail, "TOPRIGHT", shown == 2 and e.appearance or e.status,
                "TOPLEFT", -S.size.GAP, 0)
        else
            P.Point(e.detail, "TOPRIGHT", e.name, "BOTTOMRIGHT", 0, -2)
        end
    end
    if e.warned ~= warn then
        e.warned = warn
        e.warnFill:SetShown(warn)
        e.border:SetColor(warn and S.color.bad or S.color.edge)
    end
    return pending
end




local ANYONE = { item = true, award = true, run = true, roll = true }

function VoterFrame.Concerns(kind, candidate)
    if kind == nil or candidate == nil or ANYONE[kind] then return true end
    return candidate == addon.Player:GetFullName("player")
end



local function Build()
    frame = S.Window("SimpleLootCouncilVoterFrame", "voter", 620, 400,
        T["Loot response"], { squareTag = true })
    frame:RestorePosition()



    scroll = S.ScrollRegion(frame.Content, (ENTRY_HEIGHT + S.size.ITEM_GAP) / 2)
    P.Point(scroll, "TOPLEFT", frame.Content, "TOPLEFT", 0, 0)
    P.Point(scroll, "BOTTOMRIGHT", frame.Content, "BOTTOMRIGHT", SCROLL_CHANNEL, 0)



    compactButton = S.Button(frame, "", { height = S.size.CLOSE })
    compactButton:SetFrameLevel(frame.Close:GetFrameLevel())
    P.Point(compactButton, "RIGHT", frame.Close, "LEFT", -S.size.GAP, 0)
    compactButton:SetScript("OnClick", function()
        VoterFrame:SetCompact(not addon.db.voterCompact)
    end)
    frame.Badge:ClearAllPoints()
    P.Point(frame.Badge, "RIGHT", compactButton, "LEFT", -S.size.GAP, 0)
    P.Size(frame.Badge, 1, nil)
    compactButton:SetLabel(addon.db.voterCompact and T["Expand"] or T["Compact"])
    local refreshTitle = frame.RefreshTitle
    frame.RefreshTitle = function() refreshTitle(); P.AfterLayout(PlaceTag) end



    frame:HookScript("OnHide", function()
        if suppressDismiss then return end
        local prevRun, prevMax = dismissedRun, dismissedMax
        local run, highest = addon.Session:GetRunId(), OutstandingMax(GroupItems())
        dismissedRun, dismissedMax = run, highest
        addon.AutoClose:AfterHide(function(swept)
            if not swept then
                addon.Log:D("UI", "voter frame dismissed for run",
                    tostring(run), "above session", highest)
                return
            end

            if dismissedRun == run and dismissedMax == highest then
                dismissedRun, dismissedMax = prevRun, prevMax
            end
            addon.Log:D("UI", "voter frame closed by the game, not the raider - reopening")
            VoterFrame:Refresh()
        end)
    end)

    frame:HookScript("OnShow", function() addon.Callbacks:PaintNow("voter") end)


    ticker:SetParent(frame)
    ticker:Show()
end

local function PaintWindow()


    if not addon.Session:IsRunning() then
        HideInternally()
        return
    end

    local me = addon.Player:GetFullName("player")
    local groups = GroupItems()

    if AskingCount(groups) == 0 then
        HideInternally()
        return
    end




    local owed = 0
    for _, group in ipairs(groups) do owed = owed + group.rollOwed end


    if dismissedRun ~= nil and dismissedRun == addon.Session:GetRunId() then
        if owed > 0 or OutstandingMax(groups) > dismissedMax then
            dismissedRun = nil
        else
            HideInternally()
            return
        end
    end

    if not frame then Build() end


    local reopening = not frame:IsShown()

    local shown = #groups
    local widestStrip = 0
    local pending = false


    local visible = math.min(shown, addon.db.voterCompact and COMPACT_CARDS or VISIBLE_CARDS)
    local built = math.min(shown, math.max(visible, #entries + CARDS_PER_PAINT))

    for i = 1, built do
        local group = groups[i]
        local e = entries[i] or CreateEntry(scroll.Content, i)

        e.icon:SetItem(group.link)

        local name, _, quality = C_Item.GetItemInfo(group.link)
        e.icon:SetQualityBorder(quality)

        local label = name or group.link or "?"
        if #group.sessions > 1 then
            label = addon.Locale.Format(T["%s  |cffffd100x%d|r"], label, #group.sessions)
        end
        e.name:SetText(label)
        if quality then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            if r then e.name:SetTextColor(r, g, b) end
        else
            e.name:SetTextColor(S.Unpack(S.color.text))
        end

        e.detail:SetText(DetailText(group, me))
        PlaceWish(e, WishText(group, me))
        if PaintStatus(e, group) then pending = true end



        local key = group.link or tostring(group.sessions[1])
        local sameItem = e.groupKey == key
        if not sameItem and e.groupKey then e.flushNote() end
        e.groupKey = key
        e.noteSessions = group.sessions
        if not sameItem then
            e.noteGeneration = (e.noteGeneration or 0) + 1
            e.sentNote = group.note or ""
            e.suppressNoteUpdate = true
            e.noteEdit:SetText(e.sentNote)
            e.suppressNoteUpdate = false
            e.noteComposer:Hide()
            e.buttonRow:Show()

            UpdateNoteButton(e)
        end
        LayoutButtons(e, group)
        widestStrip = math.max(widestStrip, e.buttonRow:GetWidth())
        e:Show()
    end


    if pending and not verdictRetry then
        verdictRetry = true
        C_Timer.After(0.5, function()
            verdictRetry = false
            addon.Callbacks:Invalidate("voter")
        end)
    end
    if built < shown then addon.Callbacks:Invalidate("voter") end

    for i = shown + 1, #entries do
        if entries[i].groupKey then entries[i].flushNote() end
        entries[i]:Hide()
        entries[i].groupKey = nil
        entries[i].noteGeneration = (entries[i].noteGeneration or 0) + 1
        entries[i].noteSessions = nil
    end



    if reopening or shown ~= laidOutCount or widestStrip ~= laidOutWidth
        or visible ~= laidOutVisible then
        laidOutCount, laidOutWidth, laidOutVisible = shown, widestStrip, visible



        frame.Title:SetText(T["Loot response"])
        frame:SetTag(addon.Locale.Format(addon.Locale.Plural{ one = "%d ITEM", other = "%d ITEMS" },
            #groups, #groups))


        local entryH, gap = P.Snap(ENTRY_HEIGHT), P.Snap(S.size.ITEM_GAP)
        local function ListHeight(n)
            return n * (entryH + gap) - gap
        end

        local cardWidth = S.size.ROW_PAD + S.size.ICON + CLOCK_EXTRA / 2 + BUTTON_GAP
            + widestStrip + S.size.ROW_PAD
        local windowWidth = math.max(MIN_WIDTH, cardWidth + S.size.PAD * 2)
        P.Size(frame, windowWidth, nil)
        frame.Content.slcWidth = windowWidth - S.size.PAD * 2
        frame:ClampTitle()
        P.AfterLayout(PlaceTag)


        frame:SetHeightFromTop(P.Snap(frame.HeaderHeight + S.size.PAD) + ListHeight(visible)
            + P.Snap(S.size.PAD))
        scroll:SetContentHeight(ListHeight(shown))
    end
    frame:Show()


    if reopening and owed > 0 then
        frame:Raise()
        addon.Log:D("UI", "voter frame reopened for", owed, "owed roll(s)")
    end



    VoterFrame:UpdateTimers()
end



local function Paint()
    local started = debugprofilestop()
    local cards = #entries
    PaintWindow()
    if #entries > cards then
        addon.Log:D("UI", ("voter frame first paint with %d new card(s): %.2f ms")
            :format(#entries - cards, debugprofilestop() - started))
    end

    if rollLogPending then
        addon.Log:D("UI", "roll requested,", rollLogPending, "owed by",
            tostring(addon.Player:GetFullName("player")),
            "- window", frame and frame:IsShown() and "shown" or "still hidden")
        rollLogPending = nil
    end
end


function VoterFrame:Refresh()
    if not view then return end
    addon.Callbacks:Invalidate("voter")
    addon.Callbacks:PaintNow("voter")
end





function VoterFrame:Init()
    S = addon.Style
    L = addon.Layout
    P = addon.Pixel
    SCROLL_CHANNEL = S.size.SCROLLBAR_W + S.size.SCROLLBAR_GAP
    TAG_OFFSET = S.size.TAG_GAP
    BUTTON_INSET = S.size.ROW_PAD - 2


    ENTRY_HEIGHT = S.size.ROW_PAD
        + S.size.ICON + S.size.ITEM_GAP
        + RESPONSE_BUTTON_H + S.size.ROW_PAD



    ticker = CreateFrame("Frame", nil, UIParent)
    ticker:Hide()
    local sinceTick = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        sinceTick = sinceTick + elapsed
        if sinceTick < 1 then return end
        sinceTick = sinceTick % 1
        VoterFrame:UpdateTimers()
    end)




    view = addon.Callbacks:RegisterView("voter", {
        interval = 0.1,
        shown = function()
            return (frame ~= nil and frame:IsShown()) or addon.Session:IsRunning()
        end,
        paint = Paint,
    })
    VoterFrame.view = view

    P.OnRescale(function() if frame then P.AfterLayout(PlaceTag) end end)


    P.OnRescale(function()
        for i, e in ipairs(entries) do
            AnchorEntry(e, i)
            e.stripSig = nil
            e.clockTemplate = nil
        end
        clockWidths = {}
        laidOutCount, laidOutWidth, laidOutVisible = nil, nil, nil
        addon.Callbacks:Invalidate("voter")
    end)

    addon.Callbacks:Register("RunStarted", function()

        dismissedRun, dismissedMax = nil, 0
        if scroll then scroll.ScrollBar:SetValue(0) end
        addon.Callbacks:Invalidate("voter")
    end)

    addon.Callbacks:Register("SessionChanged", function(session, kind, candidate)
        if VoterFrame.Concerns(kind, candidate) then
            addon.Callbacks:Invalidate("voter", session, kind, candidate)
        end
    end)



    addon.Callbacks:Register("RollRequested", function()
        local me = addon.Player:GetFullName("player")
        local owed = 0
        for _, item in ipairs(addon.Session:GetItems()) do
            if not item.removed and addon.Roll.OwedBy(item, me) then owed = owed + 1 end
        end
        if owed > 0 then dismissedRun, dismissedMax = nil, 0 end



        rollLogPending = owed
        addon.Callbacks:Invalidate("voter")
    end)
    addon.Callbacks:Register("RunEnded", function()
        if frame then HideInternally() end
    end)



    addon.Restrictions:OnChange(function() addon.Callbacks:Invalidate("voter") end)

    addon.Log:I("UI", "voter frame ready")
end


function VoterFrame:SetCompact(on)
    addon.db.voterCompact = on and true or false
    if not frame then return end
    compactButton:SetLabel(on and T["Expand"] or T["Compact"])

    P.AfterLayout(frame.ClampTitle)
    VoterFrame:Refresh()
end



function VoterFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return "closed"
    end
    return VoterFrame:Open()
end



function VoterFrame:Open()
    if not view then return false end


    dismissedRun, dismissedMax = nil, 0
    VoterFrame:Refresh()
    if not (frame and frame:IsShown()) then return false end
    frame:Raise()
    return true
end
