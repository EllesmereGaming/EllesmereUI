if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local L = {}
addon.Layout = L

local P = addon.Pixel
local S = addon.Style
local size = S.size







function L.WidthOf(frame)
    local recorded = frame.slcWidth
    if type(recorded) == "number" and recorded > 0 then return recorded end

    local measured = frame:GetWidth()
    if type(measured) == "number" and measured > 0 then return measured end


    addon.Log:W("UI", "layout: parent has no resolved width; set .slcWidth on it")
    return 0
end





local Cursor = {}
Cursor.__index = Cursor



function L.Cursor(parent, opts)
    opts = opts or {}
    local x = opts.x or 0
    return setmetatable({
        parent = parent,
        x      = x,
        width  = opts.width or (L.WidthOf(parent) - x * 2),
        y      = -(opts.top or 0),
        start  = -(opts.top or 0),
    }, Cursor)
end


function Cursor:Add(builder, ...)
    local frame, height = builder(self.parent, self.x, self.width, self.y, ...)
    self.y = self.y - (height or 0)
    return frame, height
end


function Cursor:Gap(amount)
    self.y = self.y - (amount or size.ITEM_GAP)
    return self
end


function Cursor:Consumed()
    return self.start - self.y
end


function Cursor:Y() return self.y end


function Cursor:Height(padBottom)
    return -self.y + (padBottom or 0)
end









function Cursor:Split(n, gap)
    gap = gap or size.SECTION
    local each = (self.width - gap * (n - 1)) / n
    local columns = {}
    for i = 1, n do
        columns[i] = setmetatable({
            parent = self.parent,
            x      = self.x + (each + gap) * (i - 1),
            width  = each,
            y      = self.y,
            start  = self.y,
        }, Cursor)
    end
    return unpack(columns, 1, n)
end

function Cursor:Join(...)
    local lowest = self.y
    for i = 1, select("#", ...) do
        local column = select(i, ...)
        if column.y < lowest then lowest = column.y end
    end
    self.y = lowest
    return self
end






function L.Section(parent, x, width, y, text, opts)
    local frame, h = S.Heading(parent, x, width, y, text, opts)
    return frame, h
end



function L.Spacer(parent, x, width, y, height)
    return nil, height or size.ITEM_GAP
end


function L.Row(parent, x, width, y, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 1)
    P.Size(f, width, height or size.ROW_H)
    P.Point(f, "TOPLEFT", parent, "TOPLEFT", x, y)


    local hover = S.RoundFill(f, S.color.rowHover, S.radius.CTRL, "BACKGROUND")
    hover:Hide()
    f.Hover = hover

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() hover:Show() end)
    f:SetScript("OnLeave", function() hover:Hide() end)


    function f:AdoptHover(child)
        child.slcHoverIn  = function() hover:Show() end
        child.slcHoverOut = function() hover:SetShown(f:IsMouseOver()) end
        return child
    end


    function f:SetStripe(index)
        if not index then return end

        if index % 2 == 1 then return end
        S.RoundFill(f, S.color.rowStripe, S.radius.CTRL, "BACKGROUND", -1)
    end

    return f, height or size.ROW_H
end


local function BoundedLabel(row, control, text, fontObject)
    local fs = S.Label(row, fontObject or S.fontBody, "LEFT")
    fs:SetText(text)
    P.Point(fs, "LEFT", row, "LEFT", size.ROW_PAD, 0)
    P.Point(fs, "RIGHT", control, "LEFT", -size.GAP, 0)
    return fs
end
L.BoundedLabel = BoundedLabel


function L.RevealIfTruncated(owner, fs, fullText)
    P.AfterLayout(function()
        local natural, bounded = fs:GetStringWidth(), fs:GetWidth()


        if issecretvalue and (issecretvalue(natural) or issecretvalue(bounded)) then
            return
        end
        if type(natural) ~= "number" or type(bounded) ~= "number" then return end

        if natural <= bounded + 0.5 then return end

        owner:HookScript("OnEnter", function(self)
            S.TextTooltip(self, fullText or fs:GetText())
        end)
        owner:HookScript("OnLeave", function() S.HideTextTooltip() end)
    end)
end


local HELP_LINES = 2
local HELP_GAP   = 3
local HELP_INSET = 7



local function FontHeight(fontObject, fallback)
    local _, h = fontObject:GetFont()
    return tonumber(h) or fallback
end


local function HelpLines(help)
    local n = help:GetNumLines()
    if issecretvalue and issecretvalue(n) then return nil end
    if type(n) ~= "number" or n < 1 then return nil end
    return math.min(n, HELP_LINES)
end



function L.Toggle(parent, x, width, y, opts)
    local hasHelp = opts.tooltip ~= nil
    local nameH = FontHeight(S.fontSetting, 13.5)
    local helpH = FontHeight(S.fontSmall, 12)


    local height = size.ROW_H
    if hasHelp then
        height = math.max(size.SET_ROW_H, math.ceil(
            HELP_INSET * 2 + nameH + HELP_GAP + HELP_LINES * helpH))
    end

    local row = L.Row(parent, x, width, y, height)
    row:SetStripe(opts.stripe)

    local box = S.Switch(row, opts.set)
    P.Point(box, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    box:SetChecked(opts.get and opts.get() or false)
    row:AdoptHover(box)
    row.Box = box
    row.Get = opts.get

    local label = BoundedLabel(row, box, opts.label, S.fontSetting)
    row.LabelText = label

    if hasHelp then


        local help = S.Label(row, S.fontSmall, "LEFT", HELP_LINES)
        help:SetText(opts.tooltip)
        P.Point(help, "TOPLEFT", label, "BOTTOMLEFT", 0, -HELP_GAP)
        P.Point(help, "TOPRIGHT", label, "BOTTOMRIGHT", 0, -HELP_GAP)
        row.HelpText = help

        local function place(lines)
            local top = (height - (nameH + HELP_GAP + lines * helpH)) / 2
            label:ClearAllPoints()
            P.Point(label, "TOPLEFT", row, "TOPLEFT", size.ROW_PAD, -top)


            P.Point(label, "TOPRIGHT", box, "LEFT", -size.GAP, height / 2 - top)
        end

        place(HELP_LINES)
        local function recentre()
            P.AfterLayout(function()
                local lines = HelpLines(help)
                if lines then place(lines) end
            end)
        end
        recentre()



        function row:SetHelpText(text)
            help:SetText(text)
            recentre()
        end
    else
        L.RevealIfTruncated(row, label, opts.label)
    end


    row:SetScript("OnMouseUp", function()
        if not opts.set then return end
        box.Toggle()
    end)

    if opts.tooltip then
        local function show(self)
            S.SideTooltip(self)
            S.TooltipSection(GameTooltip, opts.label)
            GameTooltip:AddLine(opts.tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
        row:HookScript("OnEnter", show)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
        box:HookScript("OnEnter", show)
        box:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return row, height
end


function L.Input(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(opts.stripe)

    local holder, edit = S.EditBox(row, opts.width or 60)
    P.Point(holder, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    row:AdoptHover(edit)
    row.Holder, row.EditBox = holder, edit

    edit:SetNumeric(opts.numeric and true or false)
    edit:SetText(tostring(opts.get and opts.get() or ""))
    edit:SetScript("OnEnterPressed", function(self)
        if opts.set then opts.set(self:GetText()) end
        self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(opts.get and opts.get() or ""))
        self:ClearFocus()
    end)


    local label = BoundedLabel(row, holder, opts.label, S.fontSetting)
    L.RevealIfTruncated(row, label, opts.tooltip and (opts.label .. "\n" .. opts.tooltip))

    if opts.tooltip then
        row:HookScript("OnEnter", function(self)
            S.SideTooltip(self)
            S.TooltipSection(GameTooltip, opts.label)
            GameTooltip:AddLine(opts.tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return row, size.ROW_H
end



function L.Select(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y)
    row:SetStripe(opts.stripe)

    local select = S.SelectButton(row)
    P.Point(select, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    row:AdoptHover(select)
    row.Control = select
    local text = select.Text

    local function TextFor(value)
        for _, o in ipairs(opts.options) do
            if o.value == value then return o.text end
        end
        return opts.options[1] and opts.options[1].text or ""
    end

    local function Fit()
        local widest = 0
        for _, o in ipairs(opts.options) do
            text:SetText(o.text)
            local w = text:GetUnboundedStringWidth()
            if type(w) == "number" and w > widest then widest = w end
        end
        text:SetText(TextFor(opts.get and opts.get()))
        P.Size(select, math.max(select.MinWidth,
            math.ceil(widest) + select.Chrome), size.CTRL_H)
    end
    Fit()
    P.AfterLayout(Fit)
    P.OnRescale(Fit)

    function row:Sync()
        text:SetText(TextFor(opts.get and opts.get()))
    end

    select:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        S.ShowSelectMenu(self, opts.options, opts.get and opts.get(), function(value)
            if opts.set then opts.set(value) end
            row:Sync()
        end)
    end)

    local window = S.WindowOf(parent)
    if window then window:HookScript("OnHide", function() S.HideSelectMenu() end) end

    local label = BoundedLabel(row, select, opts.label, S.fontSetting)
    L.RevealIfTruncated(row, label, opts.tooltip and (opts.label .. "\n" .. opts.tooltip))
    if opts.tooltip then
        row:HookScript("OnEnter", function(self)
            S.SideTooltip(self)
            S.TooltipSection(GameTooltip, opts.label)
            GameTooltip:AddLine(opts.tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
        select:HookScript("OnEnter", function()
            S.SideTooltip(row)
            S.TooltipSection(GameTooltip, opts.label)
            GameTooltip:AddLine(opts.tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        select:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return row, size.ROW_H
end



function L.Readout(parent, x, width, y, opts)
    local row = L.Row(parent, x, width, y, opts.height or size.ROW_H)
    row:EnableMouse(false)

    local value = S.Label(row, opts.font or S.fontSmall, "RIGHT")
    P.Point(value, "RIGHT", row, "RIGHT", -size.ROW_PAD, 0)
    value:SetText(opts.value or "")
    row.Value = value

    local label = BoundedLabel(row, value, opts.label, S.fontSmall)
    row.LabelText = label

    return row, row:GetHeight()
end


function L.Paragraph(parent, x, width, y, text, fontObject)
    local fs = S.Label(parent, fontObject or S.fontBody, "LEFT", "wrap")
    fs:SetWidth(P.Snap(width))
    P.Point(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text or "")

    local h = fs:GetStringHeight()
    if issecretvalue and issecretvalue(h) then h = nil end
    if type(h) ~= "number" or h <= 0 then


        h = 14
    end

    return fs, math.ceil(h)
end


function L.ButtonRow(parent, x, width, y, specs)
    local row = L.Row(parent, x, width, y, size.BTN_H)
    row:EnableMouse(false)

    local previous
    for i = 1, #specs do
        local spec = specs[i]
        local b = S.Button(row, spec.text, spec.opts)
        if previous then
            P.Point(b, "RIGHT", previous, "LEFT", -size.GAP, 0)
        else
            P.Point(b, "RIGHT", row, "RIGHT", 0, 0)
        end
        if spec.onClick then b:SetScript("OnClick", spec.onClick) end
        row[spec.key or i] = b
        previous = b
    end

    return row, size.BTN_H
end







function L.Above(child, parent, delta)
    child:SetFrameLevel(parent:GetFrameLevel() + (delta or 1))
    return child
end
