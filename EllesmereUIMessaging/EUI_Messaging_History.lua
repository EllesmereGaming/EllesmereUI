if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  History browser, designed as the EllesmereUI bags window:
--
--    header   35px band: "Message History", the conversation count dimmed
--             beside it, the search box and the close X at the right
--    sidebar  "Conversations": a row per conversation (class icon or the
--             Battle.net logo, name, message count), newest first; the
--             selected row carries the accent bar and the accent wash
--    content  the conversation by day: a section header per day ("Monday,
--             3 November (12)" and the hairline), the messages under it;
--             the bags' 4px scroll thumb
--    footer   Delete / Open conversation
--
--  Backdrop, border, colors and metrics are the bags window's. The search
--  matches names and message text. Built on first use; the message rows and
--  day headers are pooled and laid out once per selection.
-------------------------------------------------------------------------------
local _, addonNS = ...
local ns = addonNS.Whispers

local W, H = 720, 460
local HEADER_H = 35
local FOOTER_H = 34
local SIDEBAR_W = 190
local ROW_H = 26
local ICON_SIZE = 16
local PAD = 12
local SECTION_H = 22

local frame, search, sidebarChild, content, contentChild, empty, title, countText
local openButton, deleteButton, copyButton
local rows, sections, lines = {}, {}, {}
local entries = {}   -- filtered, sorted { key, entry }
local selected

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function Font(fs, size)
    local EUI = EllesmereUI
    local path = (EUI and EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT
    fs:SetFont(path, size, "")
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Battle.net friends by their BattleTag (the number dimmed), everyone else
-- (characters, GMs) by their name
local function DisplayName(entry)
    local name = entry.n or "?"
    if entry.k == "bn" then
        local tag, number = name:match("^([^#]+)(#%d+)$")
        if tag then return tag .. "|cff888888" .. number .. "|r" end
        return name
    end
    return ns.ShortName(name)
end

local function Px(region)
    local EUI = EllesmereUI
    local mult = EUI and EUI.PP and EUI.PP.mult
    if mult then return mult end
    local _, h = GetPhysicalScreenSize()
    local scale = region:GetEffectiveScale()
    return (h and h > 0 and scale and scale > 0) and (768 / h / scale) or 1
end

-- Classic WoW UI: the windows' tint on the tooltip tile (dark, as the Damage
-- Meters' Classic window)
local CLASSIC_TINT = { 0.06, 0.06, 0.06, 0.92 }

-- 1px border, as EllesmereUI's frames draw it
local function Border(f, r, g, b, a)
    local px = Px(f)
    for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local edge = f:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetColorTexture(r, g, b, a)
        edge:SetPoint(spec[1])
        edge:SetPoint(spec[2])
        if spec[3] then edge:SetHeight(px) else edge:SetWidth(px) end
    end
end

-- The class icon (the character-create sheet, on every client), else nil
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local function SetEntryIcon(tex, entry)
    local coords = entry.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[entry.c]
    if coords then
        tex:SetTexture(CLASS_SHEET)
        tex:SetTexCoord(unpack(coords))
    elseif entry.k == "bn" then
        tex:SetTexture("Interface\\FriendsFrame\\Battlenet-Battleneticon")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        tex:SetTexture("Interface\\ChatFrame\\UI-ChatWhisperIcon")
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
local function Matches(entry, query)
    if query == "" then return true end
    if (entry.n or ""):lower():find(query, 1, true) then return true end
    for _, rec in ipairs(entry.m or {}) do
        if type(rec[3]) == "string" and rec[3]:lower():find(query, 1, true) then return true end
    end
    return false
end

local function Rebuild()
    wipe(entries)
    local h = ns.OwnerHistory(false) or {}
    local query = search and (search:GetText() or ""):lower() or ""
    local total = 0
    for key, entry in pairs(h) do
        total = total + 1
        if Matches(entry, query) then entries[#entries + 1] = { key = key, entry = entry } end
    end
    table.sort(entries, function(a, b) return (a.entry.t or 0) > (b.entry.t or 0) end)
    countText:SetText(total == 1 and "1 conversation" or (total .. " conversations"))
    -- keep the selection when it is still listed, else take the newest
    local found = false
    for _, e in ipairs(entries) do if e.key == selected then found = true end end
    if not found then selected = entries[1] and entries[1].key end
end

local function SelectedItem()
    for _, e in ipairs(entries) do if e.key == selected then return e end end
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, sidebarChild)
    row:SetHeight(ROW_H)
    row.indicator = row:CreateTexture(nil, "OVERLAY")
    row.indicator:SetPoint("TOPLEFT")
    row.indicator:SetPoint("BOTTOMLEFT")
    row.indicator:SetWidth(Px(row) * 2)
    row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.label = row:CreateFontString(nil, "OVERLAY")
    Font(row.label, 11)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -36, 0)
    row.count = row:CreateFontString(nil, "OVERLAY")
    Font(row.count, 10)
    row.count:SetJustifyH("RIGHT")
    row.count:SetTextColor(0.5, 0.5, 0.5)
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.06) end end)
    row:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0) end end)
    row:SetScript("OnClick", function(self)
        selected = self.key
        ns.RefreshHistory(true)
    end)
    rows[i] = row
    return row
end

local function RefreshSidebar()
    local ar, ag, ab = ns.Accent()
    local y = 0
    for i, item in ipairs(entries) do
        local row = Row(i)
        local entry = item.entry
        local isSelected = (item.key == selected)
        row.key = item.key
        row.selected = isSelected
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", sidebarChild, "RIGHT")
        SetEntryIcon(row.icon, entry)
        row.icon:SetAlpha(isSelected and 1 or 0.75)
        local r, g, b = ns.ClassColor(entry.c)
        row.label:SetText(DisplayName(entry))
        row.label:SetTextColor(r or 1, g or 1, b or 1, isSelected and 1 or 0.75)
        row.count:SetText(#(entry.m or {}))
        if isSelected then
            row.indicator:SetColorTexture(ar, ag, ab, 1)
            row.indicator:Show()
            row.bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            row.indicator:Hide()
            row.bg:SetColorTexture(1, 1, 1, 0)
        end
        row:Show()
        y = y - ROW_H
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    sidebarChild:SetHeight(math.max(1, -y))
end

-------------------------------------------------------------------------------
--  Content: day sections and messages
-------------------------------------------------------------------------------
local function Section(i)
    local s = sections[i]
    if s then return s end
    s = CreateFrame("Frame", nil, contentChild)
    s:SetHeight(SECTION_H)
    s.label = s:CreateFontString(nil, "OVERLAY")
    Font(s.label, 12)
    s.label:SetPoint("LEFT", s, "LEFT", 0, 0)
    s.label:SetTextColor(1, 1, 1, 0.8)
    s.count = s:CreateFontString(nil, "OVERLAY")
    Font(s.count, 12)
    s.count:SetPoint("LEFT", s.label, "RIGHT", 4, 0)
    s.count:SetTextColor(0.7, 0.7, 0.7, 0.9)
    s.line = s:CreateTexture(nil, "ARTWORK")
    s.line:SetHeight(Px(s))
    s.line:SetPoint("LEFT", s.count, "RIGHT", 8, 0)
    s.line:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    s.line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    sections[i] = s
    return s
end

local function Line(i)
    local fs = lines[i]
    if fs then return fs end
    fs = contentChild:CreateFontString(nil, "OVERLAY")
    Font(fs, 12)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    fs:SetNonSpaceWrap(true)
    lines[i] = fs
    return fs
end

local function MessageColor(entry, dir)
    local info = ChatTypeInfo and ChatTypeInfo[(entry.k == "bn" and "BN_" or "") .. (dir == ns.IN and "WHISPER" or "WHISPER_INFORM")]
    if info then return info.r, info.g, info.b end
    return 1, 0.5, 1
end

local function RefreshContent(scrollToEnd)
    local item = SelectedItem()
    openButton:SetEnabled(item ~= nil)
    deleteButton:SetEnabled(item ~= nil)
    copyButton:SetEnabled(item ~= nil)
    local width = content:GetWidth() or 0
    contentChild:SetWidth(width)
    local nLines, nSections, y = 0, 0, 0

    if item and width > 0 then
        local entry = item.entry
        local r, g, b = ns.ClassColor(entry.c)
        -- in the messages a BattleTag goes without its number
        local name = (entry.k == "bn" and (entry.n or ""):match("^[^#]+")) or DisplayName(entry)
        local who = r and (Hex(r, g, b) .. name .. "|r") or name
        local _, myClass = UnitClass("player")
        local mr, mg, mb = ns.ClassColor(myClass)
        local me = UnitName("player")
        me = mr and (Hex(mr, mg, mb) .. me .. "|r") or me

        -- count messages per day first, for the section headers
        local perDay = {}
        for _, rec in ipairs(entry.m or {}) do
            local day = date("%Y%m%d", rec[1])
            perDay[day] = (perDay[day] or 0) + 1
        end

        local lastDay
        for _, rec in ipairs(entry.m or {}) do
            local t, dir, text = rec[1], rec[2], rec[3]
            local day = date("%Y%m%d", t)
            if day ~= lastDay then
                if lastDay then y = y - 8 end
                nSections = nSections + 1
                local s = Section(nSections)
                s.label:SetText(date("%A, %d %B %Y", t))
                s.count:SetText("(" .. perDay[day] .. ")")
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 0, y)
                s:SetPoint("RIGHT", contentChild, "RIGHT")
                s:Show()
                y = y - SECTION_H - 2
                lastDay = day
            end
            nLines = nLines + 1
            local fs = Line(nLines)
            fs:SetWidth(width)
            fs:SetText("|cff808080" .. date("%H:%M", t) .. "|r  " .. (dir == ns.IN and who or me) .. ": " .. (text or ""))
            fs:SetTextColor(MessageColor(entry, dir))
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 0, y)
            fs:Show()
            y = y - (fs:GetStringHeight() or 14) - 4
        end
    end
    for i = nSections + 1, #sections do sections[i]:Hide() end
    for i = nLines + 1, #lines do lines[i]:Hide() end
    contentChild:SetHeight(math.max(1, -y))
    empty:SetShown(#entries == 0)
    if scrollToEnd then
        C_Timer.After(0, function()
            content:SetVerticalScroll(math.max(0, content:GetVerticalScrollRange() or 0))
        end)
    end
end

function ns.RefreshHistory(scrollToEnd)
    if not frame then return end
    Rebuild()
    RefreshSidebar()
    RefreshContent(scrollToEnd)
end

-------------------------------------------------------------------------------
--  Scroll thumb (the bags': a 4px thumb in a 16px hit strip)
-------------------------------------------------------------------------------
local function Scrollbar(scrollFrame, step)
    local track = CreateFrame("Button", nil, scrollFrame:GetParent())
    track:SetWidth(16)
    track:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 14, 0)
    track:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 14, 0)
    track:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    if ns.Forever() then thumb:SetColorTexture(unpack(ns.FV.thumb)) else thumb:SetColorTexture(1, 1, 1, 0.27) end
    local function Update()
        local range = scrollFrame:GetVerticalScrollRange() or 0
        if range <= 0 then thumb:Hide() return end
        local trackH = track:GetHeight() or 0
        local viewH = scrollFrame:GetHeight() or 0
        local thumbH = math.max(20, trackH * viewH / (viewH + range))
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(trackH - thumbH) * (scrollFrame:GetVerticalScroll() / range))
        thumb:Show()
    end
    scrollFrame:SetScript("OnScrollRangeChanged", Update)
    scrollFrame:SetScript("OnVerticalScroll", Update)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * step)))
    end)
    -- (OnUpdate only while the thumb is dragged)
    local function Drag()
        local range = scrollFrame:GetVerticalScrollRange() or 0
        local top, trackH = track:GetTop(), track:GetHeight()
        if range <= 0 or not top or not trackH or trackH <= 0 then return end
        local _, cy = GetCursorPosition()
        local fraction = math.min(1, math.max(0, (top - cy / track:GetEffectiveScale()) / trackH))
        scrollFrame:SetVerticalScroll(fraction * range)
    end
    track:SetScript("OnMouseDown", function() track:SetScript("OnUpdate", Drag) end)
    track:SetScript("OnMouseUp", function() track:SetScript("OnUpdate", nil) end)
    return Update
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------
-- The EllesmereUI button: dark plate, white border, dimmed label
local function Button(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(130, 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.089, 0.080, 0.072, 0.6)
    -- WoW Forever: a bronze hairline and a gold label
    local fv = ns.Forever()
    if fv then Border(b, unpack(ns.FV.line)) else Border(b, 1, 1, 1, 0.3) end
    b.text = b:CreateFontString(nil, "OVERLAY")
    Font(b.text, 11)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    local function Paint(hover)
        local enabled = b:IsEnabled()
        local r, g, bl = 1, 1, 1
        if fv then r, g, bl = unpack(ns.FV.gold) end
        b.text:SetTextColor(r, g, bl, enabled and (hover and (fv and 1 or 0.7) or (fv and 0.85 or 0.55)) or 0.25)
        b.bg:SetColorTexture(0.089, 0.080, 0.072, hover and enabled and 0.65 or 0.6)
    end
    b:SetScript("OnEnter", function() Paint(true) end)
    b:SetScript("OnLeave", function() Paint(false) end)
    b:SetScript("OnEnable", function() Paint(false) end)
    b:SetScript("OnDisable", function() Paint(false) end)
    b:SetScript("OnClick", onClick)
    Paint(false)
    return b
end

-------------------------------------------------------------------------------
--  Copy: the selected conversation as plain text in a box, all selected, for
--  Ctrl+C (game text can't be selected; an input box can, as in WIM)
-------------------------------------------------------------------------------
local copyFrame, copyBox

-- Plain text: links keep their visible name, color codes go
local function Plain(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

local function ConversationText(entry)
    local them = (entry.k == "bn" and (entry.n or ""):match("^[^#]+")) or ns.ShortName(entry.n or "?")
    local me = UnitName("player")
    local out = {}
    for _, rec in ipairs(entry.m or {}) do
        out[#out + 1] = ("[%s] %s: %s"):format(date("%Y-%m-%d %H:%M", rec[1]), rec[2] == ns.IN and them or me, Plain(rec[3]))
    end
    return table.concat(out, "\n")
end

local function ShowCopy(entry)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "EllesmereUIMessagingCopy", UIParent)
        copyFrame:SetSize(560, 360)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("DIALOG")
        copyFrame:SetToplevel(true)
        copyFrame:SetClampedToScreen(true)
        copyFrame:SetMovable(true)
        copyFrame:EnableMouse(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        tinsert(UISpecialFrames, copyFrame:GetName())
        local bg = copyFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        local shade = copyFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        shade:SetAllPoints()
        shade:SetColorTexture(0, 0, 0, 0.45)
        if ns.BlizzBody(bg, 1) or ns.ClassicBody(bg, unpack(CLASSIC_TINT)) then
            shade:Hide()
        elseif not ns.ForeverFrame(copyFrame) then
            Border(copyFrame, 1, 1, 1, 0.15)
        end
        local hdr = copyFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
        -- WoW Forever: the Damage Meters' header band, a gold title;
        -- Blizzard Style: the stock meter's header bar
        if not ns.FvHeaderBand(hdr, copyFrame, HEADER_H)
            and not ns.ClassicHeader(hdr, copyFrame, HEADER_H, CLASSIC_TINT[1], CLASSIC_TINT[2], CLASSIC_TINT[3], 1) then
            hdr:SetPoint("TOPLEFT")
            hdr:SetPoint("TOPRIGHT")
            hdr:SetHeight(HEADER_H)
            if not ns.BlizzHeader(hdr) then hdr:SetColorTexture(0, 0, 0, 0.5) end
        end
        local lift = ns.FvBandLift(HEADER_H)
        copyFrame.title = copyFrame:CreateFontString(nil, "OVERLAY")
        Font(copyFrame.title, 13)
        copyFrame.title:SetPoint("LEFT", copyFrame, "TOPLEFT", 8, -HEADER_H / 2 + lift)
        if ns.Forever() then copyFrame.title:SetTextColor(unpack(ns.FV.gold)) else copyFrame.title:SetTextColor(1, 1, 1) end
        local hint = copyFrame:CreateFontString(nil, "OVERLAY")
        Font(hint, 11)
        hint:SetPoint("LEFT", copyFrame.title, "RIGHT", 8, 0)
        hint:SetTextColor(0.6, 0.6, 0.6)
        hint:SetText("Ctrl+C to copy")
        local close = CreateFrame("Button", nil, copyFrame)
        close:SetSize(22, 22)
        close:SetPoint("RIGHT", copyFrame, "TOPRIGHT", -8, -HEADER_H / 2 + lift)
        close.icon = close:CreateTexture(nil, "ARTWORK")
        close.icon:SetSize(14, 14)
        close.icon:SetPoint("CENTER")
        close.icon:SetTexture(ns.EUI_ICONS .. "eui-close.png")
        close.icon:SetVertexColor(1, 1, 1, 0.75)
        close:SetScript("OnEnter", function(self) self.icon:SetVertexColor(1, 1, 1, 1) end)
        close:SetScript("OnLeave", function(self) self.icon:SetVertexColor(1, 1, 1, 0.75) end)
        if not ns.FvCloseButton(close, close.icon) then ns.ClassicCloseButton(close, close.icon) end
        close:SetScript("OnClick", function() copyFrame:Hide() end)

        local scroll = CreateFrame("ScrollFrame", nil, copyFrame)
        scroll:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", PAD, -(HEADER_H + PAD))
        scroll:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -(PAD + 12), PAD)
        copyBox = CreateFrame("EditBox", nil, scroll)
        copyBox:SetMultiLine(true)
        copyBox:SetAutoFocus(false)
        Font(copyBox, 12)
        copyBox:SetWidth(560 - 2 * PAD - 12)
        copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        -- read-only: typing restores the text
        copyBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self.text then
                self:SetText(self.text)
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(copyBox)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        end)
        Scrollbar(scroll, 40)
    end
    copyFrame.title:SetText(DisplayName(entry))
    copyBox.text = ConversationText(entry)
    copyBox:SetText(copyBox.text)
    copyFrame:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end

local function ConfirmDelete(item)
    EllesmereUI:ShowConfirmPopup({
        title = "Delete History",
        message = ("Delete the history of %s?"):format(DisplayName(item.entry)),
        confirmText = DELETE or "Delete",
        cancelText = CANCEL or "Cancel",
        onConfirm = function()
            ns.DeleteHistory(item.key)
            selected = nil
            ns.RefreshHistory(true)
        end,
    })
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "EllesmereUIMessagingHistory", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())

    -- backdrop: the EllesmereUI art under a light shade, 1px white border
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.25)
    -- Blizzard Style: the Damage Meters' borderless black body in place of
    -- the art; WoW Forever: the chat's bronze frame in place of the border
    -- Classic WoW UI: the dark tooltip tile inside the chat tab's border
    if ns.BlizzBody(bg, 1) or ns.ClassicBody(bg, unpack(CLASSIC_TINT)) then
        shade:Hide()
    elseif not ns.ForeverFrame(frame) then
        Border(frame, 1, 1, 1, 0.15)
    end

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    -- WoW Forever: the Damage Meters' header band (its contents lifted onto
    -- the band's body, above the rod), a gold title, the red close button,
    -- a bronze-lined search box
    local fv = ns.Forever()
    local hdrBg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    if not ns.FvHeaderBand(hdrBg, header, HEADER_H)
        and not ns.ClassicHeader(hdrBg, header, HEADER_H, CLASSIC_TINT[1], CLASSIC_TINT[2], CLASSIC_TINT[3], 1) then
        hdrBg:SetAllPoints()
        -- Blizzard Style: the stock meter's header bar
        if not ns.BlizzHeader(hdrBg) then hdrBg:SetColorTexture(0, 0, 0, 0.5) end
    end
    local lift = ns.FvBandLift(HEADER_H)

    title = header:CreateFontString(nil, "OVERLAY")
    Font(title, 13)
    title:SetPoint("LEFT", header, "LEFT", 8, lift)
    if fv then title:SetTextColor(unpack(ns.FV.gold)) else title:SetTextColor(1, 1, 1) end
    title:SetText("Message History")
    countText = header:CreateFontString(nil, "OVERLAY")
    Font(countText, 11)
    countText:SetPoint("LEFT", title, "RIGHT", 8, 0)
    countText:SetTextColor(0.6, 0.6, 0.6)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", header, "RIGHT", -8, lift)
    close.icon = close:CreateTexture(nil, "ARTWORK")
    close.icon:SetSize(14, 14)
    close.icon:SetPoint("CENTER")
    close.icon:SetTexture(ns.EUI_ICONS .. "eui-close.png")
    close.icon:SetVertexColor(1, 1, 1, 0.75)
    close:SetScript("OnEnter", function(self) self.icon:SetVertexColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self.icon:SetVertexColor(1, 1, 1, 0.75) end)
    if not ns.FvCloseButton(close, close.icon) then ns.ClassicCloseButton(close, close.icon) end
    close:SetScript("OnClick", function() frame:Hide() end)

    -- search box (the bags')
    search = CreateFrame("EditBox", nil, header)
    search:SetSize(160, 22)
    search:SetPoint("RIGHT", header, "RIGHT", -35, lift)
    search:SetAutoFocus(false)
    Font(search, 12)
    search:SetTextInsets(5, 26, 0, 0)
    local searchBg = search:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if fv then Border(search, unpack(ns.FV.line)) else Border(search, 0.25, 0.25, 0.25, 1) end
    local placeholder = search:CreateFontString(nil, "OVERLAY")
    Font(placeholder, 11)
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    placeholder:SetText(SEARCH and (SEARCH .. "...") or "Search...")
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    clear.text = clear:CreateFontString(nil, "OVERLAY")
    Font(clear.text, 14)
    clear.text:SetText("x")
    clear.text:SetPoint("CENTER", 0, 1)
    clear.text:SetTextColor(0.8, 0.8, 0.8)
    clear:Hide()
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    search:SetScript("OnTextChanged", function(self)
        local has = (self:GetText() or "") ~= ""
        placeholder:SetShown(not has)
        clear:SetShown(has)
        ns.RefreshHistory(true)
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- footer
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOTER_H)
    local footerBg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    footerBg:SetAllPoints()
    footerBg:SetColorTexture(0, 0, 0, 0.25)

    openButton = Button(footer, "Open conversation", function()
        local item = SelectedItem()
        if not item then return end
        local entry = item.entry
        local convo
        if entry.k == "bn" then
            local bnID = ns.FindBNID(entry.n)
            convo = bnID and ns.GetBNConvo(bnID, true)
        else
            convo = ns.ConvoForCharacter(entry.n, nil, true)
        end
        if convo then
            ns.ShowWindow(convo, true)
        else
            ns.Print("that Battle.net friend isn't on your friends list right now.")
        end
    end)
    openButton:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
    deleteButton = Button(footer, DELETE or "Delete", function()
        local item = SelectedItem()
        if item then ConfirmDelete(item) end
    end)
    deleteButton:SetPoint("RIGHT", openButton, "LEFT", -8, 0)
    copyButton = Button(footer, "Copy", function()
        local item = SelectedItem()
        if item then ShowCopy(item.entry) end
    end)
    copyButton:SetPoint("RIGHT", deleteButton, "LEFT", -8, 0)

    -- sidebar
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H)
    sidebar:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
    sidebar:SetWidth(SIDEBAR_W)
    local sideBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(0, 0, 0, 0.25)
    local sep = sidebar:CreateTexture(nil, "ARTWORK")
    sep:SetWidth(Px(sidebar))
    sep:SetPoint("TOPRIGHT")
    sep:SetPoint("BOTTOMRIGHT")
    sep:SetColorTexture(0.15, 0.15, 0.15, 1)
    local sideHeader = sidebar:CreateFontString(nil, "OVERLAY")
    Font(sideHeader, 10)
    sideHeader:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -7)
    sideHeader:SetText("Conversations")
    if fv then sideHeader:SetTextColor(unpack(ns.FV.tan)) else sideHeader:SetTextColor(0.5, 0.5, 0.5) end

    local sideScroll = CreateFrame("ScrollFrame", nil, sidebar)
    sideScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -24)
    sideScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -Px(sidebar), 0)
    sidebarChild = CreateFrame("Frame", nil, sideScroll)
    sidebarChild:SetWidth(SIDEBAR_W)
    sidebarChild:SetHeight(1)
    sideScroll:SetScrollChild(sidebarChild)
    sideScroll:SetScript("OnSizeChanged", function(self, w) sidebarChild:SetWidth(w) end)
    sideScroll:EnableMouseWheel(true)
    sideScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 28)))
    end)

    -- content
    content = CreateFrame("ScrollFrame", nil, frame)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD + 4, -PAD)
    content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -(PAD + 12), PAD)
    contentChild = CreateFrame("Frame", nil, content)
    contentChild:SetSize(1, 1)
    content:SetScrollChild(contentChild)
    content:SetScript("OnSizeChanged", function() if frame:IsShown() then RefreshContent(false) end end)
    Scrollbar(content, 40)

    empty = frame:CreateFontString(nil, "OVERLAY")
    Font(empty, 12)
    empty:SetPoint("CENTER", content, "CENTER")
    empty:SetTextColor(0.5, 0.5, 0.5)
    empty:SetText("No whisper history yet.")
    empty:Hide()

    frame:SetScript("OnShow", function() ns.RefreshHistory(true) end)
end

-------------------------------------------------------------------------------
--  Public
-------------------------------------------------------------------------------
function ns.ShowHistory(key)
    Build()
    if key then selected = key end
    if frame:IsShown() then ns.RefreshHistory(true) else frame:Show() end
end

function ns.ToggleHistory()
    if frame and frame:IsShown() then frame:Hide() else ns.ShowHistory() end
end

ns.On("HistoryChanged", function()
    if frame and frame:IsShown() then ns.RefreshHistory(false) end
end)

-- Live while open (e.g. beside the whisper window): every saved message
-- updates the list (order, counts) and the shown conversation. A burst of
-- messages refreshes once. Reading at the bottom follows the new messages;
-- scrolled up, the place is kept.
local refreshQueued = false
ns.On("LineAdded", function(_, line)
    if refreshQueued or line.d == ns.SYSTEM or not (frame and frame:IsShown()) then return end
    if not ns.settings.history.enabled then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        if not frame:IsShown() then return end
        local range = content:GetVerticalScrollRange() or 0
        local atBottom = (content:GetVerticalScroll() or 0) >= range - 2
        ns.RefreshHistory(atBottom)
    end)
end)
