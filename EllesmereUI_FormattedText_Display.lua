if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local FT = EllesmereUI.FormattedText
local plans = FT._internal.plans
local bindings
local Display = {}
Display.__index = Display
local numberFormats = {}
for precision = 0, FT.MAX_PRECISION do numberFormats["%." .. precision .. "f"] = true end
local numberRulers

-- Formatting stays in the engine. Forward its potentially restricted result
-- to another native text setter without inspection or measurement.
function FT:FormatNumber(format, value)
    assert(numberFormats[format], "invalid numeric text format")
    if not numberRulers then numberRulers = {} end
    local fs = numberRulers[format]
    if not fs then
        local host = CreateFrame("Frame")
        host:Hide()
        fs = host:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY, 12, "")
        numberRulers[format] = fs
    end
    fs:SetFormattedText(format, value)
    return fs:GetText()
end

function FT:Attach(fontString, context)
    assert(fontString and fontString.SetFormattedText and type(context) == "table"
        and type(context.type) == "string", "FormattedText needs a FontString and a typed context")
    if not bindings then bindings = setmetatable({}, { __mode = "k" }) end
    local display = bindings[fontString]
    if not display then
        display = setmetatable({ fs = fontString, values = {}, readers = {} }, Display)
        bindings[fontString] = display
    end
    if display.context ~= context then display:SetActive(false) end
    display.context = context
    return display
end

function Display:SetTemplate(template)
    self:SetActive(false)
    self:StopNative()
    local plan = FT:Compile(template, self.context.type)
    local data = plans[plan]
    self.plan, self.data = plan, data
    self.template = template
    self.justify = nil
    local driver = FT._internal.drivers and FT._internal.drivers[self.context.type]
    self.available = driver and driver.available
    self.styleVersion = (self.styleVersion or 0) + 1
    local overrides = self.context.readers
    for i = 1, #data.nodes do
        local v = data.nodes[i].variant
        local key = data.nodes[i].color and v.uncoloredReaderKey or v.readerKey
        local reader = not (v.numeric and data.nodes[i].precision ~= nil) and overrides and overrides[key]
        self.readers[i] = reader or v.read
        if v.numeric then FT._internal.PrepareNumber(data.nodes[i]) end
    end
    for i = #data.nodes + 1, #self.readers do self.readers[i] = nil end
    if not data.styled and self.clip then self.clip:Hide(); self.fs:Show() end
    if self.clip then
        for i = 1, #self.runs do self.runs[i]:Hide() end
        for i = 1, #self.runs do self.runs[i]._formattedAnchored = nil end
    end
    self:SetActive(true)
    return FT:Describe(plan)
end

-- Configure an owned display during layout. Native presets and custom templates
-- use one component; live values remain native arguments, never template text.
function FT:Configure(fontString, context, template)
    local display = self:Attach(fontString, context)
    if template and template ~= "" then
        display:SetTemplate(template)
    else
        display:SetActive(false)
        display.template, display.plan, display.data = nil, nil, nil
        if display.clip then display.clip:Hide(); fontString:Show() end
    end
    return display
end

function FT:Write(fontString, format, ...)
    local display = bindings and bindings[fontString]
    if not display then display = self:Attach(fontString, { type = "values", managed = true }) end
    if display.nativeBinding then return end
    if display.template then
        if not display.context.transient then display:Render() end
        return
    end
    if not display.data or display.data.format ~= format then
        display.plan = self:CompileFormat(format)
        display.data = plans[display.plan]
    end
    -- Preserve the native argument lane and its zero-allocation preset path.
    fontString:SetFormattedText(format, ...)
end

function FT:WriteText(fontString, value)
    if not issecretvalue(value) and value == nil then value = "" end
    self:Write(fontString, "%s", value)
end

-- Owner-driven contexts borrow raw arguments for this paint only. Their readers
-- never sample gameplay state or retain restricted values between updates.
function FT:Paint(fontString, contextType, template, ...)
    local display = bindings and bindings[fontString]
    if not display or not display.context or display.context.type ~= contextType or not display.context.transient
        or display.ownerType ~= contextType or display.ownerTemplate ~= template then
        display = self:Configure(fontString, { type = contextType, managed = true, transient = true, args = {} }, template)
        display.ownerType, display.ownerTemplate = contextType, template
    end
    if not display.template then return false end
    local args, count = display.context.args, select("#", ...)
    for i = 1, count do args[i] = select(i, ...) end
    local active = display.active
    display.active = true
    display:Render()
    display.active = active
    for i = 1, count do args[i] = nil end
    return true
end

function FT:ConfigureUnit(fontString, unit, template, covered, powerType)
    local display = bindings and bindings[fontString]
    if not display or not display.context or not display.context.ownedUnit or display.ownerTemplate ~= template then
        display = self:Configure(fontString, { type = "unit", unit = unit, ownedUnit = true, covered = covered }, template)
        display.ownerTemplate = template
    else
        display:SetUnit(unit)
    end
    display.context.powerType = powerType
    return display
end

function FT:WriteUnit(fontString, unit, template, covered, powerType, format, ...)
    self:ConfigureUnit(fontString, unit, template, covered, powerType)
    self:Write(fontString, format, ...)
end

function FT:ConfigurePreview(fontString, contextType, template, samples)
    local display = bindings and bindings[fontString]
    if not display or not display.context or not display.context.preview
        or display.context.type ~= contextType or display.ownerTemplate ~= template then
        display = self:Configure(fontString, { type = contextType, preview = true, samples = samples }, template)
        display.ownerTemplate = template
    else display.context.samples = samples end
    return display
end

function FT:Refresh(fontString)
    local display = bindings and bindings[fontString]
    if display and display.template and not display.context.transient then display:Render() end
end

function FT:Restyle(fontString)
    local display = bindings and bindings[fontString]
    if not (display and display.data and display.data.styled and display.runs) then return end
    for i = 1, #display.data.runs do
        local run, def = display.runs[i], display.data.runs[i]
        if run then
            if def.color then
                local c = def.color
                local _, _, _, a = fontString:GetTextColor()
                run:SetTextColor(c[1], c[2], c[3], def.alpha ~= nil and 1 or a)
                run:SetAlpha(def.alpha ~= nil and def.alpha or fontString:GetAlpha())
            else
                run:SetTextColor(fontString:GetTextColor())
                run:SetAlpha(fontString:GetAlpha())
            end
        end
    end
end

function Display:StopNative()
    if self.nativeBinding then self.nativeBinding:Disable(); self.nativeBinding = nil end
    if self.runs then
        for i = 1, #self.runs do
            local run = self.runs[i]
            if run._formattedBinding then run._formattedBinding:Disable(); run._formattedBound = nil end
        end
    end
end

function FT:StopNative(fontString)
    local display = bindings and bindings[fontString]
    if display then display:StopNative() end
end

-- The component owns the native writer until StopNative; ordinary writes cannot
-- race a duration binding. The owner supplies the engine binding and its clock.
function FT:SetNativeBinding(fontString, binding)
    local display = bindings and bindings[fontString]
    if not display then display = self:Attach(fontString, { type = "values", managed = true }) end
    if display.nativeBinding ~= binding then display:StopNative(); display.nativeBinding = binding end
    binding:Enable(); binding:UpdateFontString()
end

function FT:SetShown(fontString, shown)
    local display = bindings and bindings[fontString]
    if display and display.template and display.data then
        if not shown then
            display:SetActive(false)
            if display.clip then display.clip:Hide() end
            fontString:Hide()
            return
        elseif not display.active then
            display:SetActive(true)
            if not display.context.transient then display:Render() end
        end
        if display.data.styled and display.clip then fontString:Hide(); display.clip:Show(); return end
    end
    fontString:SetShown(shown)
end

function Display:_SetActive(active)
    if self.active == active then return end
    if self.unsubscribe then self.unsubscribe(); self.unsubscribe = nil end
    self.active = active
    if not active then self:StopNative() end
    local driver = self.context and FT._internal.drivers and FT._internal.drivers[self.context.type]
    if self.active and self.data and #self.data.nodes > 0 and driver then
        self.unsubscribe = driver.subscribe(self, self.data.dependencies)
    end
end

function Display:SetActive(active)
    self.enabled = active == true
    if self.enabled and self.template and not self.visibility then
        local watcher = CreateFrame("Frame", nil, self.fs:GetParent())
        self.visibility = watcher
        watcher:SetScript("OnHide", function() self:_SetActive(false) end)
        watcher:SetScript("OnShow", function()
            if self.enabled then
                self:_SetActive(true)
                if not self.context.transient then self:Render() end
            end
        end)
    end
    if self.visibility and self.visibility:GetParent() ~= self.fs:GetParent() then
        self.visibility:SetParent(self.fs:GetParent())
    end
    self:_SetActive(self.enabled and (not self.visibility or self.visibility:IsShown()))
end

function Display:SetUnit(unit)
    if self.context.unit == unit then return end
    self.context.unit = unit
    if self.active then self:_SetActive(false); self:_SetActive(true) end
end

local function DressRun(run, display)
    if run._formattedStyle ~= display.styleVersion then
        local fs = display.fs
        run:SetFont(display.fontFile, display.fontSize, display.fontFlags)
        run:SetShadowOffset(fs:GetShadowOffset())
        run:SetSpacing(fs:GetSpacing())
        run:SetWordWrap(false)
        run:SetJustifyH("LEFT")
        run:SetJustifyV(fs:GetJustifyV())
        run:SetWidth(0)
        run._formattedStyle = display.styleVersion
    end
    run:SetShadowColor(display.fs:GetShadowColor())
end

-- Separate native FontStrings give each styled value a real alpha override.
-- Native anchors lay out secret text widths; Lua never reads those widths.
function Display:RenderStyled()
    local fs, data = self.fs, self.data
    -- Unconstrained slots derive their native bounds from this hidden anchor's text.
    fs:SetFormattedText(data.format, unpack(self.values, 1, #data.nodes))
    local file, size, flags = fs:GetFont()
    if file ~= self.fontFile or size ~= self.fontSize or flags ~= self.fontFlags then
        self.fontFile, self.fontSize, self.fontFlags = file, size, flags
        self.styleVersion = (self.styleVersion or 0) + 1
    end
    if not self.clip then
        self.clip = CreateFrame("Frame", nil, fs:GetParent())
        self.clip:SetClipsChildren(true)
        self.measure = self.clip:CreateFontString(nil, "OVERLAY")
        self.measure:SetAlpha(0)
        self.measures = { self.measure }
        self.runs = {}
    end
    local clip, measure = self.clip, self.measure
    if clip:GetParent() ~= fs:GetParent() then clip:SetParent(fs:GetParent()) end
    clip:SetFrameLevel(fs:GetParent():GetFrameLevel())
    clip:SetAllPoints(fs)
    DressRun(measure, self)
    local justify = fs:GetJustifyH()
    if justify ~= self.justify then
        measure:ClearAllPoints()
        measure:SetPoint(justify, fs, justify, 0, 0)
        self.justify = justify
    end
    measure:SetFormattedText(data.format, unpack(self.values, 1, #data.nodes))
    if #data.lines > 1 then
        local height = #data.lines * size + (#data.lines - 1) * fs:GetSpacing()
        local vertical = fs:GetJustifyV()
        local top = vertical == "TOP" and 0 or vertical == "BOTTOM" and height or height / 2
        local vAnchor = vertical == "TOP" and "TOP" or vertical == "BOTTOM" and "BOTTOM" or "CENTER"
        local hAnchor = justify == "LEFT" and "LEFT" or justify == "RIGHT" and "RIGHT" or ""
        for i = 1, #data.lines do
            local ruler = self.measures[i]
            if not ruler then ruler = clip:CreateFontString(nil, "OVERLAY"); ruler:SetAlpha(0); self.measures[i] = ruler end
            DressRun(ruler, self)
            ruler:ClearAllPoints()
            ruler:SetPoint("TOP" .. hAnchor, fs, vAnchor == "CENTER" and justify or vAnchor .. hAnchor,
                0, top - (i - 1) * (size + fs:GetSpacing()))
            local line = data.lines[i]
            ruler:SetFormattedText(line.format, unpack(self.values, line.first, line.last))
        end
    end
    local previous
    for i = 1, #data.runs do
        local def = data.runs[i]
        local run = self.runs[i]
        if not run then run = clip:CreateFontString(nil, "OVERLAY"); self.runs[i] = run end
        DressRun(run, self)
        if not run._formattedAnchored then
            run:ClearAllPoints()
            if previous and data.runs[i - 1].line == def.line then run:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            else run:SetPoint("LEFT", self.measures[def.line or 1], "LEFT", 0, 0) end
            run._formattedAnchored = true
        end
        if def.color then
            local c = def.color
            if def.alpha ~= nil then
                run:SetTextColor(c[1], c[2], c[3], 1)
                run:SetAlpha(def.alpha)
            else
                local _, _, _, a = fs:GetTextColor()
                run:SetTextColor(c[1], c[2], c[3], a)
                run:SetAlpha(fs:GetAlpha())
            end
        else
            run:SetTextColor(fs:GetTextColor())
            run:SetAlpha(fs:GetAlpha())
        end
        local bound = false
        if def.variant and def.variant.bind and not self.context.preview then
            local binding
            binding, bound = def.variant.bind(self.context, run, run._formattedBinding)
            run._formattedBinding, run._formattedBound = binding, bound
        elseif run._formattedBinding then
            run._formattedBinding:Disable(); run._formattedBound = nil
        end
        if bound then
            run._formattedLiteral = nil
        elseif def.literal then
            if run._formattedLiteral ~= def then
                run:SetFormattedText("%s", def.escaped)
                run._formattedLiteral = def
            end
        else
            run._formattedLiteral = nil
            run:SetFormattedText(def.variant.format, self.values[def.index])
        end
        run:Show()
        previous = run
    end
    for i = #data.runs + 1, #self.runs do self.runs[i]:Hide() end
    fs:Hide()
    clip:Show()
end

function Display:Render()
    local data = self.data
    if not data or not self.active then return end
    local context, values = self.context, self.values
    if context.preview then
        for i = 1, #data.nodes do
            local v = data.nodes[i].variant
            values[i] = context.samples and context.samples[v.sampleKey] or v.preview
        end
    elseif self.available and not self.available(context) then
        self.fs:SetText("")
        if self.clip then self.clip:Hide() end
        return
    else
        local readers = self.readers
        for i = 1, #data.nodes do values[i] = readers[i](context) end
    end
    for i = 1, #data.nodes do
        local node = data.nodes[i]
        if node.variant.numeric then
            local value = values[i]
            if context.preview then value = tonumber(value) or value end
            values[i] = FT._internal.FormatValue(node, value)
        end
    end
    if data.styled then self:RenderStyled()
    else self.fs:SetFormattedText(data.format, unpack(values, 1, #data.nodes)) end
    -- Never retain live (possibly restricted) values between paints.
    for i = 1, #data.nodes do values[i] = nil end
end

function Display:Update(dependency)
    if self.data and (not dependency or self.data.dependencies[dependency]) then self:Render() end
end

function Display:Detach(preserveVisibility)
    self:SetActive(false)
    self:StopNative()
    if self.clip then
        self.clip:Hide()
        if not preserveVisibility then self.fs:Show() end
    end
    self.data, self.plan, self.context, self.available, self.template = nil, nil, nil, nil, nil
    self.ownerTemplate, self.ownerType = nil, nil
    for i = 1, #self.readers do self.readers[i] = nil end
end

function FT:Detach(fontString, preserveVisibility)
    local display = bindings and bindings[fontString]
    if display then display:Detach(preserveVisibility) end
end
