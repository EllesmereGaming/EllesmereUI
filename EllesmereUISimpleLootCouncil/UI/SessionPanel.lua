if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local SessionPanel = {}
UI.SessionPanel = SessionPanel

local S, L, P
local panel, host, scroll, summary
local rows = {}


local floating = false



local suppressDismiss = false


local PANEL_W = 400


local RESPONSE_W = 74
local ROLL_W     = 38
local WINNER_W   = 76
local CELL_GAP   = 8


local NAME_MIN = 130


local RESPONSE_BTN_H = 22


local HEADER_SIZE




local SCROLL_CHANNEL

local ROW_H = 34


local HEADING_SCALE = 2


local FLOAT_ROWS = 8
local PANEL_H






local function Answer(candidate)
    if not candidate then return nil, nil, nil end
    local status   = candidate.realStatus   or candidate.status
    local response = candidate.realResponse or candidate.response
    return status, response, candidate.note
end


local function Collect()
    if not addon.Session or not addon.Session:IsRunning() then return nil end

    local me = addon.Player:GetFullName("player")
    if not me then return nil end

    local list, mine = {}, false
    for _, item in ipairs(addon.Session:GetItems()) do


        if not item.removed then
            local candidate = item.candidates and item.candidates[me]
            if candidate then mine = true end
            list[#list + 1] = { item = item, candidate = candidate }
        end
    end


    if not mine then return nil end

    table.sort(list, function(a, b)
        return (a.item.session or 0) < (b.item.session or 0)
    end)
    return list
end





local function CreateRow(parent, index)
    local r = CreateFrame("Frame", nil, parent)
    L.Above(r, parent)
    P.Size(r, nil, ROW_H)



    if index % 2 == 0 then S.Fill(r, S.color.rowStripe) end

    r.icon = S.ItemIcon(r, S.size.ICON_SM)
    P.Point(r.icon, "LEFT", r, "LEFT", 0, 0)


    r.winner = S.Label(r, S.fontSmall, "CENTER")
    P.Point(r.winner, "RIGHT", r, "RIGHT", 0, 0)
    r.winner:SetWidth(WINNER_W)


    r.roll = S.Label(r, S.fontNumSmall, "CENTER")
    P.Point(r.roll, "RIGHT", r.winner, "LEFT", -CELL_GAP, 0)
    r.roll:SetWidth(ROLL_W)



    r.response = S.Button(r, "", {
        width = RESPONSE_W,
        height = RESPONSE_BTN_H,
        font = S.fontSmall,
        fixedWidth = true,
    })
    r.response:EnableMouse(false)
    P.Point(r.response, "RIGHT", r.roll, "LEFT", -CELL_GAP, 0)


    r.name = S.Label(r, S.fontBody, "LEFT")
    P.Point(r.name, "LEFT", r.icon, "RIGHT", 6, 0)
    P.Point(r.name, "RIGHT", r.response, "LEFT", -CELL_GAP, 0)

    return r
end


local function DrawRow(r, entry)
    local item = entry.item
    local candidate = entry.candidate
    local status, response, note = Answer(candidate)

    r.icon:SetItem(item.link)


    local name, _, quality = C_Item.GetItemInfo(item.link or "")
    r.icon:SetQualityBorder(quality)

    r.name:SetText(name or item.link or "?")
    if quality then
        local qr, qg, qb = C_Item.GetItemQualityColor(quality)
        if qr then r.name:SetTextColor(qr, qg, qb) end
    else
        r.name:SetTextColor(S.Unpack(S.color.text))
    end

    local auto = status == "PASS" and addon.Autopass
        and addon.Autopass.IsAutoNote(note)


    if auto then

        r.response:SetLabel(T["Auto-pass"])
        r.response:SetColour(nil)
    elseif status == "RESPONDED" and candidate and type(candidate.boe) == "table" then

        r.response:SetLabel(candidate.boe.t)
        r.response:SetColour({ candidate.boe.r, candidate.boe.g, candidate.boe.b })
    elseif status == "RESPONDED" and response then
        local def = addon.Config:Responses()[response]
        if def then
            r.response:SetLabel(def.text)
            r.response:SetColour({ def.r, def.g, def.b })
        else


            r.response:SetLabel(T["Unknown"])
            r.response:SetColour(S.color.bad)
        end
    else

        local def = addon.Session.STATUS[status or ""]
        r.response:SetLabel(def and def.text or "-")
        r.response:SetColour(nil)
    end
    r.response:Show()


    local roll = candidate and candidate.roll
    local me = addon.Player:GetFullName("player")
    local asked = addon.Roll and addon.Roll.OwedBy
        and addon.Roll.OwedBy(item, me)
    if roll then
        r.roll:SetText(tostring(roll))
        r.roll:SetTextColor(S.Unpack(candidate.rollBy == "leader"
            and S.color.textFaint or S.color.text))
    elseif asked then

        r.roll:SetText("-")
        r.roll:SetTextColor(S.Unpack(S.color.accent))
    else
        r.roll:SetText("")
    end


    local winner = item.awarded
    if winner then
        r.winner:SetText(Ambiguate(winner, "short"))


        r.winner:SetTextColor(S.Unpack(
            addon.Player:IsSelf(winner) and S.color.good or S.color.textMuted))
    else
        r.winner:SetText("")
    end

    r:SetAlpha(auto and 0.55 or 1)
    r:Show()
end








local function FitColumns(parent)
    SCROLL_CHANNEL = S.size.SCROLLBAR_W + S.size.SCROLLBAR_GAP
    local face, headerSize, flags = (S.fontColumnHeader or S.fontMicro):GetFont()
    HEADER_SIZE = headerSize or 14.75

    local probe = parent:CreateFontString(nil, "ARTWORK")
    probe:SetFontObject(S.fontMicro)
    if face then probe:SetFont(face, HEADER_SIZE, flags) end



    local function Widest(text, floor, pad)
        if type(text) ~= "string" or text == "" then return floor end
        probe:SetText(text)
        local w = probe:GetStringWidth()
        if issecretvalue and issecretvalue(w) then return floor end
        if type(w) ~= "number" or w <= 0 then return floor end
        return math.max(floor, math.ceil(w) + (pad or 2))
    end



    local responseHead = Widest(T["RESPONSE"], 0)
    if responseHead > 0 then RESPONSE_W = responseHead end
    WINNER_W   = Widest(T["AWARDED"],  WINNER_W)



    local rollHead = Widest(T["ROLL"], 0)
    probe:SetFontObject(S.fontNumSmall)
    local rollBody = Widest("100", 0, 6)
    if rollHead > 0 and rollBody > 0 then ROLL_W = math.max(rollHead, rollBody) end

    probe:SetText("")
    probe:Hide()



    PANEL_W = S.size.PAD * 2 + SCROLL_CHANNEL
        + S.size.ICON_SM + 6 + NAME_MIN
        + CELL_GAP * 3 + RESPONSE_W + ROLL_W + WINNER_W
end





local function Anchor()
    panel:ClearAllPoints()
    P.Size(panel, PANEL_W, PANEL_H)


    local pos = addon.db and addon.db.windows and addon.db.windows.sessionFrame
    if pos and pos.point then
        panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
    end
end


local function HidePanel()
    suppressDismiss = true
    panel:Hide()
    suppressDismiss = false
end







local function Paint()
    if not panel then return end

    local list = floating and Collect() or nil
    if not list then
        HidePanel()
        return
    end
    Anchor()
    panel:Show()

    local content = scroll.Content
    for index, entry in ipairs(list) do
        local r = rows[index]
        if not r then
            r = CreateRow(content, index)
            rows[index] = r
            if index == 1 then
                P.Point(r, "TOPLEFT", content, "TOPLEFT", 0, 0)
                P.Point(r, "TOPRIGHT", content, "TOPRIGHT", 0, 0)
            else
                P.Point(r, "TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, 0)
                P.Point(r, "TOPRIGHT", rows[index - 1], "BOTTOMRIGHT", 0, 0)
            end
        end
        DrawRow(r, entry)
    end

    for index = #list + 1, #rows do rows[index]:Hide() end

    scroll:SetContentHeight(math.max(1, #list * ROW_H))

    local awarded = 0
    for _, entry in ipairs(list) do
        if entry.item.awarded then awarded = awarded + 1 end
    end
    summary:SetText(addon.Locale.Format(addon.Locale.Plural{
        one = "%d item, %d awarded", other = "%d items, %d awarded",
    }, #list, #list, awarded))
end


function SessionPanel:Refresh()
    if not panel then return end
    addon.Callbacks:Invalidate("session")
    addon.Callbacks:PaintNow("session")
end


local function Build()
    S = S or addon.Style
    L = L or addon.Layout
    P = P or addon.Pixel

    if panel then return panel end



    panel = CreateFrame("Frame", "SimpleLootCouncilSessionFrame", UIParent)
    FitColumns(panel)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:Hide()

    panel:SetWidth(PANEL_W)
    panel.slcWidth = PANEL_W

    S.FollowWindowAlpha(panel)


    panel:HookScript("OnHide", function()
        if suppressDismiss then return end
        local wasFloating = floating
        floating = false

        addon.AutoClose:AfterHide(function(swept)
            if not swept then return end
            if floating then return end
            floating = wasFloating
            SessionPanel:Refresh()
        end)
    end)


    if S.RegisterEscape then S.RegisterEscape(panel)
    else tinsert(UISpecialFrames, "SimpleLootCouncilSessionFrame") end



    S.CanvasFill(panel, S.color.canvas, 0.96)

    local edge = CreateFrame("Frame", nil, panel)
    edge:EnableMouse(false)
    edge:SetAllPoints()
    edge:SetFrameLevel(panel:GetFrameLevel() + 6)
    S.RoundBorder(edge, S.color.windowEdge, "OVERLAY", S.radius.WINDOW)

    local _, base = S.fontHeading:GetFont()
    local titleSize = math.floor((base or 11.5) * HEADING_SCALE + 0.5)


    local headingH = math.ceil(titleSize * 1.7)
    local titleTop = math.max(0, math.floor((S.HeaderHeight() - headingH) / 2))

    local cursor = L.Cursor(panel, { x = S.size.PAD, top = titleTop,
                                     width = PANEL_W - S.size.PAD * 2 })



    cursor:Add(function(parent, x, width, y)
        local closeW = S.size.CLOSE


        local heading, headingH = S.Heading(parent, x,
            width - closeW - S.size.GAP, y, T["This session"],
            { font = S.fontHeading, fontSize = titleSize,
              color = S.color.text })

        local close = S.Button(parent, "", { width = closeW, height = closeW,
                                             glyph = "close" })
        close:SetFrameLevel(parent:GetFrameLevel() + 5)
        P.Point(close, "LEFT", heading, "RIGHT", S.size.GAP, 0)
        close:SetScript("OnClick", function() panel:Hide() end)


        heading:EnableMouse(true)
        heading:RegisterForDrag("LeftButton")
        heading:SetScript("OnDragStart", function()
            P.StartDrag(panel)
        end)
        heading:SetScript("OnDragStop", function()
            P.StopDrag(panel)
            local point, _, relPoint, px, py = panel:GetPoint()
            addon.db.windows.sessionFrame =
                { point = point, relPoint = relPoint, x = px, y = py }
        end)

        return heading, headingH
    end)

    summary = cursor:Add(L.Paragraph, "", S.fontSmall)
    cursor:Gap()


    cursor:Add(function(parent, x, width, y)
        local h = CreateFrame("Frame", nil, parent)
        L.Above(h, parent)
        P.Point(h, "TOPLEFT", parent, "TOPLEFT", x, y)


        local face, _, flags = S.fontMicro:GetFont()
        local headerSize = HEADER_SIZE


        local headerH = math.ceil(headerSize * 1.4)
        P.Size(h, width - SCROLL_CHANNEL, headerH)



        local function Head(justify)
            local fs = S.Label(h, S.fontMicro, justify)
            if face then fs:SetFont(face, headerSize, flags) end
            fs:SetTextColor(S.Unpack(S.color.textFaint))
            return fs
        end

        local winner = Head("CENTER")
        P.Point(winner, "RIGHT", h, "RIGHT", 0, 0)
        winner:SetWidth(WINNER_W)
        winner:SetText(T["AWARDED"])

        local roll = Head("CENTER")
        P.Point(roll, "RIGHT", winner, "LEFT", -CELL_GAP, 0)
        roll:SetWidth(ROLL_W)
        roll:SetText(T["ROLL"])

        local response = Head("CENTER")
        P.Point(response, "RIGHT", roll, "LEFT", -CELL_GAP, 0)
        response:SetWidth(RESPONSE_W)
        response:SetText(T["RESPONSE"])

        local itemLabel = Head("CENTER")
        P.Point(itemLabel, "LEFT", h, "LEFT", 0, 0)
        P.Point(itemLabel, "RIGHT", response, "LEFT", -CELL_GAP, 0)
        itemLabel:SetText(T["ITEM"])

        return h, headerH
    end)
    cursor:Add(L.Spacer, 4)


    PANEL_H = cursor:Height(S.size.PAD) + FLOAT_ROWS * ROW_H

    host = cursor:Add(function(parent, x, width, y)
        local h = CreateFrame("Frame", nil, parent)
        L.Above(h, parent)
        P.Point(h, "TOPLEFT", parent, "TOPLEFT", x, y)
        P.Point(h, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -S.size.PAD, S.size.PAD)
        h.slcWidth = width
        return h, 0
    end)

    scroll = S.ScrollRegion(host, ROW_H)
    scroll:SetAllPoints(host)


    scroll.Content.slcWidth = PANEL_W - S.size.PAD * 2 - SCROLL_CHANNEL

    return panel
end


function SessionPanel:Toggle()
    Build()


    if floating and panel:IsShown() then
        floating = false
        HidePanel()
        return "closed"
    end

    floating = true
    SessionPanel:Refresh()
    if panel:IsShown() then return "opened" end


    floating = false
    return "norun"
end
function SessionPanel:Init()
    S = addon.Style
    L = addon.Layout
    P = addon.Pixel



    SessionPanel.view = addon.Callbacks:RegisterView("session", {
        shown = function()
            if not panel then return false end
            return panel:IsShown() or (floating and addon.Session:IsRunning())
        end,
        paint = Paint,
    })


    local function Repaint() addon.Callbacks:Invalidate("session") end
    addon.Callbacks:Register("SessionChanged", function(session, kind, candidate)
        if addon.UI.VoterFrame.Concerns(kind, candidate) then
            addon.Callbacks:Invalidate("session", session, kind, candidate)
        end
    end)
    addon.Callbacks:Register("RunStarted", Repaint)
    addon.Callbacks:Register("RunEnded", Repaint)
    addon.Callbacks:Register("RollRequested", Repaint)
end
