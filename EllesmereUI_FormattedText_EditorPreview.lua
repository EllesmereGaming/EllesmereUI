if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local EUI, FT = EllesmereUI, EllesmereUI.FormattedText

local function Label(parent, size, r, g, b)
    return EUI.MakeFont(parent, size, nil, r, g, b, 1)
end

local function Scrollbar(parent, horizontal, scroll)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation(horizontal and "HORIZONTAL" or "VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(1, 1, 1, .05)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = bar:GetThumbTexture()
    thumb:SetColorTexture(.51, .74, 1, .55)
    thumb:SetSize(horizontal and 32 or 5, horizontal and 5 or 24)
    bar:SetScript("OnValueChanged", function(_, value)
        if horizontal then scroll:SetHorizontalScroll(value) else scroll:SetVerticalScroll(value) end
    end)
    return bar
end

local function Build(host)
    local panel = host._formattedPreview
    if panel then panel:SetAllPoints(host); panel:Show(); return panel end
    panel = CreateFrame("Frame", nil, host)
    panel:SetAllPoints(host)
    host._formattedPreview = panel
    local heading = Label(panel, 12, .51, .74, 1)
    heading:SetPoint("TOPLEFT", 0, -2)
    heading:SetText(EllesmereUI.L("PREVIEW"))
    local sample = Label(panel, 10, .65, .70, .75)
    sample:SetPoint("TOPRIGHT", 0, -3)
    sample:SetText(EllesmereUI.L("Sample values"))

    local card = CreateFrame("Frame", nil, panel)
    card:SetPoint("TOPLEFT", 0, -25)
    card:SetPoint("TOPRIGHT", 0, -25)
    card:SetHeight(44)
    panel.card = card
    EUI.SolidTex(card, "BACKGROUND", .055, .075, .10, 1):SetAllPoints()
    local accent = EUI.SolidTex(card, "ARTWORK", .51, .74, 1, .7)
    accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(2)
    local scroll = CreateFrame("ScrollFrame", nil, card)
    scroll:SetPoint("TOPLEFT", 14, -12)
    scroll:SetPoint("BOTTOMRIGHT", -18, 12)
    scroll:SetClipsChildren(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local fs = Label(child, 18, .93, .95, .97)
    fs:SetPoint("TOPLEFT")
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetSpacing(5); fs:SetWordWrap(true)
    local ruler = Label(panel, 18, 1, 1, 1)
    ruler:SetSpacing(5); ruler:SetWordWrap(true); ruler:Hide()
    panel.fs, panel.ruler, panel.scroll, panel.child = fs, ruler, scroll, child
    local hbar, vbar = Scrollbar(card, true, scroll), Scrollbar(card, false, scroll)
    hbar:SetPoint("BOTTOMLEFT", 14, 6); hbar:SetPoint("BOTTOMRIGHT", -18, 6); hbar:SetHeight(5)
    vbar:SetPoint("TOPRIGHT", -6, -12); vbar:SetPoint("BOTTOMRIGHT", -6, 12); vbar:SetWidth(5)
    panel.hbar, panel.vbar = hbar, vbar
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local bar = IsShiftKeyDown() and hbar or vbar
        local low, high = bar:GetMinMaxValues()
        bar:SetValue(math.max(low, math.min(high, bar:GetValue() - delta * 30)))
    end)
    local hint = Label(panel, 10, .65, .70, .75)
    hint:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -8)
    hint:SetJustifyH("LEFT"); hint:SetWordWrap(true)
    hint:SetText(EllesmereUI.L("Shift + scroll moves the preview sideways."))
    local status = Label(panel, 11, .65, .70, .75)
    status:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    status:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -10)
    status:SetJustifyH("LEFT"); status:SetWordWrap(true)
    panel.status, panel.hint = status, hint
    return panel
end

local function Status(panel, text, info)
    local issue = info.issues[1]
    if text:match("^%s*$") then
        panel.status:SetText(EllesmereUI.L("Enter text or a tag to see a preview."))
        panel.status:SetTextColor(.65, .70, .75, 1)
    elseif issue then
        local message = issue.code == "unterminated-tag" and EllesmereUI.L("Unfinished tag at character %d.")
            or EllesmereUI.L("Check the tag at character %d. Hover the info icon for syntax.")
        if issue.code == "too-many-tags" then message = EllesmereUI.L("Use at most 64 tags in one format.")
        elseif issue.code == "invalid-template" then message = EllesmereUI.L("This format is too long or contains an unsupported character.") end
        local preceding = text:sub(1, issue.position - 1)
        local position = (strlenutf8 and strlenutf8(preceding) or #preceding) + 1
        panel.status:SetText(string.format(message, position))
        panel.status:SetTextColor(1, .73, .36, 1)
    else
        panel.status:SetText(EllesmereUI.L("Format is valid."))
        panel.status:SetTextColor(.30, .83, .67, 1)
    end
end

-- Only text edits schedule work. Sample contexts never subscribe to unit events.
function FT:EditorPreview(context)
    local timer, panel, lastText
    local function Cancel()
        if timer then timer:Cancel(); timer = nil end
    end
    local function Update(text)
        if text == lastText then return end
        lastText = text
        local value = text:gsub("||", "|")
        local plan = FT:Compile(value, context)
        Status(panel, value, FT:Describe(plan))
        -- These widths are synthetic, public sample text, never gameplay values.
        local sample = FT:Preview(plan)
        panel.ruler:SetText(sample)
        local _, lineBreaks = sample:gsub("\n", "")
        local _, fontSize = panel.fs:GetFont()
        local textHeight = (lineBreaks + 1) * fontSize + lineBreaks * panel.fs:GetSpacing() + 2
        local sampleWidth = panel.ruler:GetStringWidth() + 2
        -- Anchored scroll bounds can still be zero during the first layout pass.
        local viewportWidth = math.max(1, panel:GetParent():GetWidth() - 32)
        -- Reserve the horizontal scrollbar gutter only when its bar is visible.
        local bottomPadding = sampleWidth - viewportWidth >= 1 and 18 or 12
        panel.scroll:SetPoint("BOTTOMRIGHT", -18, bottomPadding)
        panel.vbar:SetPoint("BOTTOMRIGHT", -6, bottomPadding)
        local cardHeight = math.min(144, textHeight + 12 + bottomPadding)
        panel.card:SetHeight(cardHeight)
        panel:GetParent():SetHeight(25 + cardHeight + 8 + panel.hint:GetStringHeight() + 10 + panel.status:GetStringHeight())
        local viewportHeight = cardHeight - 12 - bottomPadding
        local width = math.max(viewportWidth, sampleWidth)
        local height = math.max(viewportHeight, textHeight)
        panel.child:SetSize(width, height)
        panel.fs:SetSize(width, textHeight)
        local rangeX, rangeY = width - viewportWidth, height - viewportHeight
        -- Ignore subpixel overflow that cannot meaningfully be scrolled.
        if rangeX < 1 then rangeX = 0 end
        if rangeY < 1 then rangeY = 0 end
        panel.hbar:SetMinMaxValues(0, rangeX)
        panel.vbar:SetMinMaxValues(0, rangeY)
        panel.hbar:SetValue(0); panel.vbar:SetValue(0)
        panel.hbar:SetShown(rangeX > 0)
        panel.vbar:SetShown(rangeY > 0)
        if value == "" then panel.fs:SetText("") end
        FT:ConfigurePreview(panel.fs, context, value):Render()
    end
    return {
        height = 114,
        setup = function(host)
            panel = Build(host)
            lastText = nil
        end,
        changed = function(_, text, immediate)
            Cancel()
            if immediate then Update(text); return end
            timer = C_Timer.NewTimer(.10, function()
                timer = nil
                if panel and panel:IsShown() then Update(text) end
            end)
        end,
        release = function()
            Cancel()
            if panel then FT:Detach(panel.fs); panel:Hide() end
            panel, lastText = nil, nil
        end,
    }
end
