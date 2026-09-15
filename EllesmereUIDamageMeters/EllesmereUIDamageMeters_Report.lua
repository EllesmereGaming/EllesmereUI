if EUI_CLIENT_BLOCKED then return end
-- Chat reports use a readable snapshot of this window's metric and segment.
-- Independent of Details; nothing is collected or sent in the background.
local _, ns = ...
local EUI, C = EllesmereUI, ns.ReportContext
if not EUI or not C then return end
local R = {}
ns.Report = R
local panel, sending
local function Settings() return ns.EDM.DB() end
local RESTRICTED = EllesmereUI.L("Report data is not readable yet. Try again after combat.")

local function Secret(v) return issecretvalue(v) end
local function Number(v)
    return not Secret(v) and type(v) == "number" and v == v and v >= 0 and v < math.huge
end
local function Clean(s)
    if Secret(s) or type(s) ~= "string" then return nil end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|", ""):gsub("[%c]", " "))
end
-- WoW's chat limit is in bytes. Do not cut through a UTF-8 character.
local function ChatLine(s)
    s = Clean(s) or ""
    if #s <= 255 then return s end
    local last = 253
    while last > 1 and s:byte(last) >= 128 and s:byte(last) < 192 do last = last - 1 end
    return s:sub(1, last - 1) .. "..."
end
local function Notify(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("EllesmereUI: " .. message) end
end

local function ReadSnapshot(W)
    if InCombatLockdown() then return nil, RESTRICTED end
    local api = C_DamageMeter
    local session
    if W.curSessionID then
        session = api.GetCombatSessionFromID(W.curSessionID, W.curDMType)
    else
        session = api.GetCombatSessionFromType(W.curSession, W.curDMType)
    end
    if Secret(session) then return nil, RESTRICTED end
    if not session then return nil, EllesmereUI.L("There is no data in this segment to report.") end
    if Secret(session.combatSources) then return nil, RESTRICTED end
    local sources = session.combatSources
    if type(sources) ~= "table" or #sources == 0 then return nil, EllesmereUI.L("There is no data in this segment to report.") end

    local deaths = W.curDMType == Enum.DamageMeterType.Deaths
    -- Match the meter's chronological death list and its Feign Death filtering.
    if deaths then
        W.Refresh()
        sources = W._barSources or {}
    end
    local total = session.totalAmount
    if not deaths and not Number(total) then return nil, RESTRICTED end
    local rateLabel
    if W.curDMType == Enum.DamageMeterType.DamageDone then rateLabel = "DPS"
    elseif W.curDMType == Enum.DamageMeterType.HealingDone then rateLabel = "HPS"
    elseif W.curDMType ~= Enum.DamageMeterType.Interrupts and W.curDMType ~= Enum.DamageMeterType.Dispels and not deaths then rateLabel = "/s" end
    local duration = C.Duration(W.curSession, W.curSessionID)
    if not Number(duration) then duration = nil end
    local rows = {}
    for i, source in ipairs(sources) do
        if Secret(source) then return nil, RESTRICTED end
        local name = Clean(source.name)
        if not name or name == "" then return nil, RESTRICTED end
        if deaths then
            local time = source.deathTimeSeconds
            if not Number(time) then return nil, RESTRICTED end
            rows[#rows + 1] = { name = name, time = time, order = i }
        else
            local amount, rate = source.totalAmount, source.amountPerSecond
            if not Number(amount) then return nil, RESTRICTED end
            if rateLabel then
                if Secret(rate) then return nil, RESTRICTED end
                if rate == nil and duration and duration > 0 then rate = amount / duration end
                if not Number(rate) then return nil, RESTRICTED end
            end
            if amount > 0 then rows[#rows + 1] = { name = name, amount = amount, rate = rate, order = i } end
        end
    end
    if #rows == 0 or (not deaths and total <= 0) then return nil, EllesmereUI.L("There is no data in this segment to report.") end
    if not deaths then
        table.sort(rows, function(a, b)
            if a.amount == b.amount then return a.order < b.order end
            return a.amount > b.amount
        end)
    end
    local segment = EllesmereUI.L(C.SessionNames[W.curSession] or "Current")
    if W.curSessionID then
        segment = EllesmereUI.L("Previous Combat")
        for _, s in ipairs(api.GetAvailableCombatSessions() or {}) do
            if not Secret(s.sessionID) and s.sessionID == W.curSessionID then
                segment = Clean(s.name) or segment
                break
            end
        end
    end
    local title = EllesmereUI.L(C.TypeNames[W.curDMType] or "Damage Done") .. " - " .. segment
    if duration and duration > 0 then title = title .. " [" .. C.Timer(duration) .. "]" end
    return { title = title, rows = rows, total = total, rateLabel = rateLabel, deaths = deaths }
end

function R.Snapshot(W)
    local ok, snapshot, err = pcall(ReadSnapshot, W)
    if not ok then return nil, RESTRICTED end
    return snapshot, err
end

function R.Lines(snapshot, count)
    count = math.max(1, math.min(40, math.floor(tonumber(count) or 5)))
    local lines = { ChatLine("EllesmereUI: " .. snapshot.title) }
    for i = 1, math.min(count, #snapshot.rows) do
        local row = snapshot.rows[i]
        local value
        if snapshot.deaths then
            value = C.Timer(row.time)
        else
            value = C.Abbreviate(row.amount)
            if snapshot.rateLabel then value = value .. " (" .. C.Abbreviate(row.rate) .. " " .. snapshot.rateLabel .. ")" end
            value = value .. string.format(" - %.1f%%", row.amount / snapshot.total * 100)
        end
        lines[#lines + 1] = ChatLine(i .. ". " .. row.name .. ": " .. value)
    end
    return lines
end

local function InstanceGroup() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
function R.Destinations()
    local entries = {
        { key = "SAY", text = EllesmereUI.L("Say") },
        { key = "PARTY", text = EllesmereUI.L("Party"), disabled = not IsInGroup(LE_PARTY_CATEGORY_HOME) },
        { key = "RAID", text = EllesmereUI.L("Raid"), disabled = not IsInRaid(LE_PARTY_CATEGORY_HOME) },
        { key = "INSTANCE_CHAT", text = EllesmereUI.L("Instance Chat"), disabled = not InstanceGroup() },
        { key = "GUILD", text = EllesmereUI.L("Guild"), disabled = not IsInGuild() },
        { key = "OFFICER", text = EllesmereUI.L("Officer"), disabled = not IsInGuild() },
        { key = "WHISPER", text = EllesmereUI.L("Whisper") },
    }
    local channels = { GetChannelList() }
    for i = 1, #channels, 3 do
        if not channels[i + 2] then
            entries[#entries + 1] = { key = "CHANNEL:" .. channels[i + 1], text = channels[i] .. ". " .. channels[i + 1] }
        end
    end
    return entries
end

function R.Resolve(key, recipient)
    for _, entry in ipairs(R.Destinations()) do
        if entry.key == key then
            if entry.disabled then return nil, nil, EllesmereUI.L("That chat channel is unavailable.") end
            if key == "WHISPER" then
                recipient = Clean(recipient)
                recipient = recipient and recipient:match("^%s*(.-)%s*$")
                if not recipient or recipient == "" or recipient:find("%s") then return nil, nil, EllesmereUI.L("Enter a player name, including realm if needed.") end
                return key, recipient
            end
            if key:sub(1, 8) == "CHANNEL:" then
                local id = GetChannelName(key:sub(9))
                if not id or id == 0 then return nil, nil, EllesmereUI.L("That chat channel is unavailable.") end
                return "CHANNEL", id
            end
            return key
        end
    end
    return nil, nil, EllesmereUI.L("That chat channel is unavailable.")
end

-- One click submits the entire report. Outdoor Say/custom-channel calls stay
-- on the original hardware-event stack; a timer loses that authorization.
-- Other destinations pace only the requested chat lines, with no further clicks.
-- The timer is transport pacing, never a gate for reading combat data.
function R.Send(lines, key, recipient, onDone)
    if Settings().reportEnabled ~= true then return false, EllesmereUI.L("Chat reports are disabled.") end
    if #lines < 2 or #lines > 41 then return false, EllesmereUI.L("There is no data in this segment to report.") end
    if sending then return false, EllesmereUI.L("A report is already being sent.") end
    if InCombatLockdown() then return false, RESTRICTED end
    local channel, target, err = R.Resolve(key, recipient)
    if not channel then return false, err end
    local send = C_ChatInfo.SendChatMessage
    local job = { lines = {}, index = 1, onDone = onDone }
    for i, line in ipairs(lines) do job.lines[i] = ChatLine(line) end
    sending = job
    local function finish(message)
        if sending ~= job then return end
        sending = nil
        if onDone then onDone(message) end
    end
    local immediate = not IsInInstance() and (channel == "SAY" or channel == "CHANNEL")
    local function step()
        if sending ~= job then return end
        if Settings().reportEnabled ~= true then finish(EllesmereUI.L("Chat reports are disabled.")); return end
        if InCombatLockdown() then finish(EllesmereUI.L("Report stopped because combat started.")); return end
        local liveChannel, liveTarget = R.Resolve(key, recipient)
        if liveChannel ~= channel or liveTarget ~= target then finish(EllesmereUI.L("Report stopped because the destination changed.")); return end
        local ok = pcall(send, job.lines[job.index], channel, nil, target)
        if not ok then finish(EllesmereUI.L("WoW could not send this report to that channel.")); return end
        job.index = job.index + 1
        if job.index > #job.lines then finish(EllesmereUI.L("Report sent."))
        elseif not immediate then job.timer = C_Timer.NewTimer(0.3, step) end
    end
    if immediate then
        while sending == job do step() end
    else
        step()
    end
    return true
end

function R.Cancel()
    local job = sending
    sending = nil
    if job and job.timer then job.timer:Cancel() end
    if job and job.onDone then job.onDone(EllesmereUI.L("Report stopped.")) end
end

-- Use the same primitives and dropdown factory as the EllesmereUI options UI.
local function Font(parent, size, alpha)
    local fs = EUI.MakeFont(parent, size, nil, 1, 1, 1, alpha or 1)
    fs:SetJustifyH("LEFT")
    return fs
end
local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 30)
    b.bg, b.border, b.label = EUI.MakeStyledButton(b, text, 13, EUI.WB_COLOURS, onClick)
    b:SetScript("OnDisable", function() b:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function() b:SetAlpha(1) end)
    return b
end
local function HideMenus()
    C.HideMenu()
    if not panel then return end
    for _, b in ipairs({panel.channelBtn, panel.countBtn}) do
        if b and b._ddMenu then b._ddMenu:Hide() end
    end
end
local function SetControlsEnabled(enabled)
    for _, b in ipairs({panel.channelBtn, panel.countBtn, panel.sendBtn}) do
        if enabled then b:Enable() else b:Disable() end
    end
    panel.whisper:EnableKeyboard(enabled)
end

local function UpdateThumb()
    local p = panel
    local visible = p.scroll:GetHeight()
    local range = math.max(0, p.preview:GetHeight() - visible)
    p.track:SetShown(range > 0)
    if range <= 0 then return end
    local trackH = p.track:GetHeight()
    local thumbH = math.max(24, trackH * visible / (visible + range))
    p.thumb:SetHeight(thumbH)
    p.track:SetMinMaxValues(0, range)
    if p.track:GetValue() ~= p.scroll:GetVerticalScroll() then
        p.track:SetValue(p.scroll:GetVerticalScroll())
    end
end
local function ScrollTo(value)
    local p = panel
    local range = math.max(0, p.preview:GetHeight() - p.scroll:GetHeight())
    p.scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
    UpdateThumb()
end
local function UpdatePreview()
    local p = panel
    p.lines = R.Lines(p.snapshot, p.count)
    local text = table.concat(p.lines, "\n")
    p.preview:SetText(text)
    p.preview:ClearFocus()
    p.previewMeasure:SetText(text)
    -- Measure only after the panel is visible; hidden FontString geometry can
    -- be zero on the real client. Reserve two rows even for a single player.
    local contentH = math.max(#p.lines * 22 + 16, p.previewMeasure:GetStringHeight() + 16)
    local previewH = math.min(192, math.max(74, contentH))
    local whisper = p.key == "WHISPER"
    local previewTop = whisper and 240 or 184
    p.whisper:SetShown(whisper); p.whisperLabel:SetShown(whisper)
    p.previewHeading:ClearAllPoints(); p.previewHeading:SetPoint("TOPLEFT", 18, -(previewTop - 25))
    p.summary:ClearAllPoints(); p.summary:SetPoint("TOPRIGHT", -18, -(previewTop - 25))
    p.summary:SetText(EllesmereUI.Lf("%1$d entries / %2$d messages", #p.lines - 1, #p.lines))
    p.previewBox:ClearAllPoints(); p.previewBox:SetPoint("TOPLEFT", 18, -previewTop)
    p.previewBox:SetSize(484, previewH)
    p.scroll:SetSize(464, previewH - 16)
    p.preview:SetHeight(contentH - 16)
    p:SetHeight(previewTop + previewH + 90)
    p.countBtn:_refreshLabel(); p.channelBtn:_refreshLabel()
    if not sending then SetControlsEnabled(true) end
    p.status:SetText(EllesmereUI.L("One click sends the header and every entry shown below."))
    p.sendBtn.label:SetText(EllesmereUI.L("Send Report"))
    p.closeBtn.label:SetText(EllesmereUI.L("Close"))
    ScrollTo(0)
end
local function RefreshDestinations()
    local p = panel
    for k in pairs(p.channelValues) do if k ~= "_menuOpts" then p.channelValues[k] = nil end end
    for i = #p.channelOrder, 1, -1 do p.channelOrder[i] = nil end
    p.unavailable = {}
    for _, entry in ipairs(R.Destinations()) do
        p.channelOrder[#p.channelOrder + 1] = entry.key
        p.channelValues[entry.key] = entry.text
        p.unavailable[entry.key] = entry.disabled
    end
    if p.channelBtn then p.channelBtn:_invalidateMenu() end
end
local function SelectChannel(key)
    local p = panel
    for _, entry in ipairs(R.Destinations()) do
        if entry.key == key and not entry.disabled then
            p.key = key
            Settings().reportChannel = key
            UpdatePreview()
            return true
        end
    end
end
local function ApplyAccent(r, g, b)
    local p = panel
    p.accent:SetColorTexture(r, g, b, 1)
    p.icon:SetVertexColor(r, g, b, 1)
    p.previewHeading:SetTextColor(r, g, b, 0.9)
    if not p.sendBtn:IsMouseOver() then
        p.sendBtn.bg:SetColorTexture(r, g, b, 0.12)
        p.sendBtn.border:SetColor(r, g, b, 0.45)
    end
end

local function CreatePanel()
    local p = CreateFrame("Frame", "EllesmereUIDMReport", UIParent)
    panel = p
    p:Hide(); p:SetSize(520, 360); p:SetPoint("CENTER"); p:SetClampedToScreen(true)
    p:SetFrameStrata("DIALOG"); p:SetFrameLevel(100); p:EnableMouse(true)
    p:SetMovable(true)
    EUI.SolidTex(p, "BACKGROUND", 0.06, 0.08, 0.10, 1):SetAllPoints()
    p.border = EUI.MakeBorder(p, 1, 1, 1, 0.15, EUI.PanelPP)
    p.accent = EUI.SolidTex(p, "BORDER", 1, 1, 1, 1)
    p.accent:SetPoint("TOPLEFT"); p.accent:SetPoint("TOPRIGHT"); p.accent:SetHeight(2)
    p.header = CreateFrame("Frame", nil, p)
    p.header:SetPoint("TOPLEFT", 0, -2); p.header:SetPoint("TOPRIGHT", 0, -2); p.header:SetHeight(66)
    p.header:EnableMouse(true); p.header:RegisterForDrag("LeftButton")
    p.header:SetScript("OnDragStart", function() p:StartMoving() end)
    p.header:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    p.icon = p.header:CreateTexture(nil, "ARTWORK")
    p.icon:SetTexture("Interface\\AddOns\\EllesmereUIDamageMeters\\Media\\dm_report.png")
    p.icon:SetSize(32, 32); p.icon:SetPoint("TOPLEFT", 12, -8)
    p.title = Font(p.header, 16); p.title:SetPoint("TOPLEFT", 48, -15); p.title:SetText(EllesmereUI.L("Report to Chat"))
    p.subtitle = Font(p.header, 12, 0.6)
    p.subtitle:SetPoint("TOPLEFT", 18, -44); p.subtitle:SetWidth(484); p.subtitle:SetWordWrap(false)
    local divider = EUI.SolidTex(p, "BORDER", 1, 1, 1, 0.08)
    divider:SetPoint("TOPLEFT", 18, -74); divider:SetPoint("TOPRIGHT", -18, -74); divider:SetHeight(1)
    local channelLabel = Font(p, 12, 0.65); channelLabel:SetPoint("TOPLEFT", 18, -88); channelLabel:SetText(EllesmereUI.L("Send to"))
    local countLabel = Font(p, 12, 0.65); countLabel:SetPoint("TOPLEFT", 346, -88); countLabel:SetText(EllesmereUI.L("Entries"))
    p.channelValues = {_menuOpts = {parent = p}}
    p.channelOrder = {}
    RefreshDestinations()
    p.channelBtn = EUI.BuildDropdownControl(p, 312, p:GetFrameLevel()+2, p.channelValues, p.channelOrder,
        function() return p.key end, function(key) SelectChannel(key) end,
        function(key) return p.unavailable[key] end)
    p.channelBtn:SetPoint("TOPLEFT", 18, -108)
    local countValues, countOrder = {_menuOpts = {parent = p}}, {1,3,5,10,15,20,25,40}
    for _, n in ipairs(countOrder) do countValues[n] = tostring(n) end
    p.countBtn = EUI.BuildDropdownControl(p, 156, p:GetFrameLevel()+2, countValues, countOrder,
        function() return p.count or 5 end, function(n)
            p.count = n; Settings().reportLines = n; UpdatePreview()
        end)
    p.countBtn:SetPoint("TOPLEFT", 346, -108)
    p.whisperLabel = Font(p, 12, 0.65); p.whisperLabel:SetPoint("TOPLEFT", 18, -152); p.whisperLabel:SetText(EllesmereUI.L("Player-Realm"))
    p.whisper = CreateFrame("EditBox", nil, p)
    p.whisper:SetSize(484, 28); p.whisper:SetPoint("TOPLEFT", 18, -172)
    p.whisper:SetAutoFocus(false); p.whisper:SetMaxLetters(100)
    p.whisper:SetFont(EUI.EXPRESSWAY, 13, ""); p.whisper:SetTextColor(1,1,1,0.9); p.whisper:SetTextInsets(10,10,0,0)
    EUI.SolidTex(p.whisper, "BACKGROUND", EUI.DD_BG_R, EUI.DD_BG_G, EUI.DD_BG_B, EUI.DD_BG_A):SetAllPoints()
    EUI.MakeBorder(p.whisper, 1, 1, 1, EUI.DD_BRD_A, EUI.PanelPP)
    p.whisper:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.whisper:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p.previewHeading = Font(p, 11); p.previewHeading:SetText(EllesmereUI.L("REPORT PREVIEW"))
    p.summary = Font(p, 11, 0.45); p.summary:SetJustifyH("RIGHT")
    p.previewBox = CreateFrame("Frame", nil, p)
    EUI.SolidTex(p.previewBox, "BACKGROUND", 0,0,0,0.22):SetAllPoints()
    EUI.MakeBorder(p.previewBox, 1,1,1,0.08, EUI.PanelPP)
    p.scroll = CreateFrame("ScrollFrame", nil, p.previewBox)
    p.scroll:SetPoint("TOPLEFT", 10,-8); p.scroll:EnableMouseWheel(true)
    p.preview = CreateFrame("EditBox", nil, p.scroll)
    p.preview:SetMultiLine(true); p.preview:SetAutoFocus(false); p.preview:SetWidth(452)
    p.preview:SetFont(EUI.EXPRESSWAY, 13, ""); p.preview:SetTextColor(1,1,1,0.85)
    p.preview:SetTextInsets(0,0,0,0); p.preview:SetSpacing(5)
    p.previewMeasure = Font(p,13); p.previewMeasure:SetWidth(452); p.previewMeasure:SetSpacing(5)
    p.previewMeasure:SetAlpha(0); p.previewMeasure:SetPoint("TOPLEFT", p.previewBox,"TOPLEFT",10,-8)
    p.preview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    p.preview:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(table.concat(p.lines, "\n")) end
    end)
    p.scroll:SetScrollChild(p.preview)
    p.scroll:SetScript("OnMouseWheel", function(_, delta) ScrollTo(p.scroll:GetVerticalScroll() - delta * 44) end)
    p.track = CreateFrame("Slider", nil, p.previewBox)
    p.track:SetWidth(4); p.track:SetPoint("TOPRIGHT", -5,-8); p.track:SetPoint("BOTTOMRIGHT", -5,8)
    p.track:SetOrientation("VERTICAL"); p.track:SetMinMaxValues(0, 1); p.track:SetValueStep(1)
    p.track:SetObeyStepOnDrag(true)
    EUI.SolidTex(p.track,"BACKGROUND",1,1,1,0.03):SetAllPoints()
    p.thumb = EUI.SolidTex(p.track,"ARTWORK",1,1,1,0.27); p.thumb:SetSize(4,24)
    p.track:SetThumbTexture(p.thumb)
    p.track:SetScript("OnValueChanged",function(_, value) ScrollTo(value) end)
    p.track:SetScript("OnEnter",function() p.thumb:SetColorTexture(1,1,1,0.5) end)
    p.track:SetScript("OnLeave",function() p.thumb:SetColorTexture(1,1,1,0.27) end)
    p.status = Font(p,11,0.6); p.status:SetPoint("BOTTOMLEFT",18,54); p.status:SetSize(484,26)
    p.status:SetJustifyV("MIDDLE")
    p.sendBtn = Button(p,EllesmereUI.L("Send Report"),312,function()
        p.whisper:ClearFocus(); p.preview:ClearFocus(); HideMenus()
        SetControlsEnabled(false); p.sendBtn.label:SetText(EllesmereUI.L("Sending..."))
        p.closeBtn.label:SetText(EllesmereUI.L("Cancel")); p.status:SetText(EllesmereUI.L("Sending the complete report..."))
        local ok, err = R.Send(p.lines,p.key,p.whisper:GetText(),function(message)
            SetControlsEnabled(true); p.sendBtn.label:SetText(EllesmereUI.L("Send Report"))
            p.closeBtn.label:SetText(EllesmereUI.L("Close"))
            p.status:SetText(message)
            if message == EllesmereUI.L("Report sent.") then p.sendBtn:Disable() end
        end)
        if not ok then
            SetControlsEnabled(true); p.sendBtn.label:SetText(EllesmereUI.L("Send Report"))
            p.closeBtn.label:SetText(EllesmereUI.L("Close")); p.status:SetText(err)
        end
    end)
    p.sendBtn:SetPoint("BOTTOMLEFT",18,16)
    p.sendBtn:SetScript("OnEnter",function()
        local r,g,b = EUI.GetAccentColor()
        p.sendBtn.bg:SetColorTexture(r,g,b,0.22); p.sendBtn.border:SetColor(r,g,b,0.75)
        p.sendBtn.label:SetTextColor(1,1,1,1)
    end)
    p.sendBtn:SetScript("OnLeave",function()
        local r,g,b = EUI.GetAccentColor()
        p.sendBtn.bg:SetColorTexture(r,g,b,0.12); p.sendBtn.border:SetColor(r,g,b,0.45)
        p.sendBtn.label:SetTextColor(1,1,1,EUI.BTN_TXT_A)
    end)
    p.closeBtn = Button(p,EllesmereUI.L("Close"),156,function() p:Hide() end)
    p.closeBtn:SetPoint("BOTTOMRIGHT",-18,16)
    p:SetScript("OnHide",function()
        R.Cancel(); HideMenus(); p.whisper:ClearFocus(); p.preview:ClearFocus()
        p:UnregisterAllEvents(); p:StopMovingOrSizing()
        p.window, p.snapshot, p.lines = nil, nil, nil
    end)
    p:SetScript("OnShow",function()
        p:RegisterEvent("PLAYER_REGEN_DISABLED")
        p:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
        p:RegisterEvent("GROUP_ROSTER_UPDATE"); p:RegisterEvent("PLAYER_GUILD_UPDATE")
    end)
    p:SetScript("OnEvent",function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then p:Hide()
        elseif p:IsShown() then RefreshDestinations() end
    end)
    EUI.RegAccent({type="callback",obj=p,fn=function(r,g,b)
        if p:IsShown() then ApplyAccent(r,g,b) end
    end})
    EUI._popupFrames[#EUI._popupFrames+1] = {popup=p}
    UISpecialFrames[#UISpecialFrames+1] = "EllesmereUIDMReport"
    return p
end

function R.Close(W)
    if panel and (not W or panel.window == W) then panel:Hide() end
end

function R.Open(W)
    if Settings().reportEnabled ~= true then return end
    if sending then Notify(EllesmereUI.L("A report is already being sent.")); return end
    if panel and panel:IsShown() and panel.window == W then panel:Hide(); return end
    local snapshot, err = R.Snapshot(W)
    if not snapshot then Notify(err); return end
    -- Native dropdowns are deferred with the options widgets. Load them on the
    -- first report click; do not create a second imitation of the design system.
    if not EUI.BuildDropdownControl then EUI:EnsureLoaded() end
    if not EUI.BuildDropdownControl then Notify(EllesmereUI.L("EllesmereUI options must be enabled to open the report dialog.")); return end
    HideMenus()
    local p = panel or CreatePanel()
    p.window, p.snapshot = W, snapshot
    p.count = math.max(1, math.min(40, math.floor(tonumber(Settings().reportLines) or 5)))
    p.subtitle:SetText(snapshot.title)
    p:SetScale(EUI.GetPopupScale())
    p:Show()
    RefreshDestinations()
    local default = InstanceGroup() and "INSTANCE_CHAT" or IsInRaid(LE_PARTY_CATEGORY_HOME) and "RAID"
        or IsInGroup(LE_PARTY_CATEGORY_HOME) and "PARTY" or "SAY"
    if not SelectChannel(Settings().reportChannel or default) then SelectChannel(default) end
    ApplyAccent(EUI.GetAccentColor())
end
