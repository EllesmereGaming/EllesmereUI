if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local EUI, FT = EllesmereUI, EllesmereUI.FormattedText

local function Paint(text, color)
    return "|cff" .. color .. text .. "|r"
end

function FT:GetHelp(context)
    local guide = self:GetGuide(context)
    local lines = { "[:tag:modifier:]", EllesmereUI.L("Modifiers are optional."),
        EllesmereUI.L("Mix tags with your own text, spaces, and punctuation."), "",
        Paint(EllesmereUI.L("AVAILABLE TAGS"), "00cc99") }
    for i = 1, #guide.tags do
        local tag = guide.tags[i]
        local names = { tag.syntax or tag.id }
        for j = 1, #tag.aliases do names[#names + 1] = tag.aliases[j] end
        local supported = table.concat(tag.modifiers, ", ")
        if tag.numeric then supported = supported .. (supported ~= "" and ", " or "") .. "0f-9f" end
        lines[#lines + 1] = table.concat(names, " / ") .. " - " .. tag.description
            .. (supported ~= "" and " (" .. supported .. ")" or "")
    end
    for i = 1, #guide.modifiers do
        local mod = guide.modifiers[i]
        lines[#lines + 1] = table.concat(mod.names, " / ") .. " - " .. mod.description
    end
    if guide.precision then
        lines[#lines + 1] = EllesmereUI.L("Add :2f: for two decimal places. Omit it for whole numbers, including percentages.")
        lines[#lines + 1] = EllesmereUI.L("Precision: 0f through 9f. Put it before the color.")
    end
    for i = 1, #guide.examples do
        local example = guide.examples[i]
        lines[#lines + 1] = example.input .. " -> " .. example.output
    end
    lines[#lines + 1] = EllesmereUI.L("Put a hex color last, then optional opacity from 0 to 100.")
    if guide.style then lines[#lines + 1] = guide.style.input .. " -> " .. guide.style.output end
    if guide.literal then lines[#lines + 1] = guide.literal.input .. " -> " .. guide.literal.output end
    return table.concat(lines, "\n")
end

function FT:ShowEditor(opts)
    assert(type(opts) == "table" and type(opts.get) == "function" and type(opts.set) == "function",
        "FormattedText editor needs get and set")
    local context = opts.context or "unit"
    local current = opts.get()
    if type(current) ~= "string" then current = "" end
    local function Normalize(value)
        return (value:gsub("||", "|"):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    EUI:ShowInputPopup({
        title = opts.title or EllesmereUI.L("Custom Text"),
        message = EllesmereUI.L("Use [:tag:modifier:] to display a value."),
        placeholder = "[:name:] - [:hp:percent:]%",
        initialText = current,
        maxLetters = 4096,
        width = 620, inputWidth = 572,
        multiline = true, showCount = true,
        inputHeight = 84, growInput = { min = 84, max = 180 },
        content = FT:EditorPreview(context),
        infoTooltip = function() return FT:GetGuide(context) end,
        infoTooltipOptions = { width = 640, anchorPoint = "RIGHT", anchorTo = "LEFT",
            anchorX = -1, anchorY = 0, fitScreen = true,
            layout = function(tooltip, guide, width) return FT:LayoutGuide(tooltip, guide, width) end },
        validate = function(value)
            value = Normalize(value)
            return value ~= "" and #FT:Describe(FT:Compile(value, context)).issues == 0
        end,
        onConfirm = function(value) opts.set(Normalize(value)) end,
    })
end

-- Native options rows consume this definition; the same get/set powers the editor and overrides.
function FT:EditorConfig(opts)
    return { type = "button", text = opts.text or EllesmereUI.L("Custom Text"),
        getValue = opts.get, setValue = opts.set,
        onClick = function() FT:ShowEditor(opts) end,
        disabled = opts.disabled, disabledTooltip = opts.disabledTooltip, _formattedText = opts }
end

-- One declaration connects a native content dropdown to its template setting.
function FT:ConfigureContent(cfg, opts)
    local values, order = {}, {}
    for key, value in pairs(cfg.values or {}) do values[key] = value end
    local customIndex
    for i = 1, #(cfg.order or {}) do
        order[i] = cfg.order[i]
        if order[i] == "custom" then customIndex = i end
    end
    if not customIndex then
        customIndex = math.min(3, #order + 1)
        table.insert(order, customIndex, "custom")
    end
    local function IsDivider(key) return type(key) == "string" and key:sub(1, 3) == "---" end
    if not IsDivider(order[customIndex - 1]) then
        table.insert(order, customIndex, "---formatted-text-before")
        customIndex = customIndex + 1
    end
    if not IsDivider(order[customIndex + 1]) then table.insert(order, customIndex + 1, "---formatted-text-after") end
    values.custom = { text = EllesmereUI.L("Custom"), action = function()
        FT:ShowEditor({ context = opts.context or "unit",
            get = opts.get, set = function(template)
                opts.set(template)
                cfg.setValue("custom")
            end })
    end }
    cfg.values, cfg.order, cfg._formattedText = values, order, opts
    return cfg
end

function FT:ConfigureCogContent(row, opts)
    local cfg = self:ConfigureContent({ values = row.values, order = row.order,
        getValue = row.get, setValue = row.set }, opts)
    row.values, row.order, row._formattedText = cfg.values, cfg.order, opts
    return row
end

function FT:CaptureEditor(region, cfg)
    local opts = cfg and cfg._formattedText
    if not (region and opts and EUI.AddCaptureAccessor) then return end
    EUI.AddCaptureAccessor(region, {
        type = "input", text = (cfg.text or "") .. " Custom Format",
        getValue = function() return opts.get() or "" end,
        setValue = function(template)
            opts.set(template ~= "" and template or nil)
            if opts.apply then opts.apply() end
        end,
    })
end
