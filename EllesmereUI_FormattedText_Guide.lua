if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local EUI, FT = EllesmereUI, EllesmereUI.FormattedText
local WHITE, MUTED, GOLD, BLUE = "edf3f8", "a5b1be", "f0c681", "83bcff"
local function Ink(value, color) return "|cff" .. color .. value .. "|r" end

-- The guide and its examples come from the same registry as the compiler.
function FT:GetGuide(context)
    local guide = { tags = self:GetCatalog(context), modifiers = {}, examples = {} }
    local modifiers, firstNumber = {}, nil
    for i = 1, #guide.tags do
        local tag = guide.tags[i]
        if tag.numeric and not firstNumber then firstNumber = tag end
        for j = 1, #tag.modifiers do
            local key = tag.modifiers[j]
            local mod = modifiers[key]
            if not mod then
                mod = { key = key, names = { key }, description = tag.modifierDescriptions[key] or "" }
                for alias, canonical in pairs(tag.modifierAliases) do
                    if canonical == key and alias ~= key then mod.names[#mod.names + 1] = alias end
                end
                table.sort(mod.names)
                modifiers[key] = mod
                if key == "abbreviated" then guide.hasAbbreviation = true end
                guide.modifiers[#guide.modifiers + 1] = mod
            end
        end
    end
    table.sort(guide.modifiers, function(a, b) return a.key < b.key end)
    local examples = self:GetExamples(context)
    if #examples == 0 then
        for i = 1, math.min(2, #guide.tags) do examples[#examples + 1] = guide.tags[i].examples[1] end
    end
    local function Example(template)
        local plan = self:Compile(template, context)
        if #self:Describe(plan).issues == 0 then return { input = template, output = self:Preview(plan) } end
    end
    for i = 1, #examples do
        local example = Example(examples[i])
        if example then guide.examples[#guide.examples + 1] = example end
    end
    if firstNumber then
        local id = firstNumber.id
        local shape = firstNumber.modifierAliases.percent and ":percent" or firstNumber.modifierAliases.abr and ":abr" or ""
        local suffix = shape == ":percent" and "%" or ""
        guide.precision = { Example("[:" .. id .. shape .. ":]" .. suffix),
            Example("[:" .. id .. shape .. ":2f:]" .. suffix) }
    end
    guide.hero = guide.precision and guide.precision[2] or guide.examples[1]
    local tag = firstNumber or guide.tags[1]
    if tag then
        local abbreviated = firstNumber and firstNumber.modifierAliases.abr and ":abr" or ""
        guide.style = Example("[:" .. tag.id .. abbreviated .. (firstNumber and ":2f" or "") .. ":#00CC99:85:]")
    end
    guide.literal = Example("[:text:example:#83BCFF:85:]")
    return guide
end

local function Accent()
    local r, g, b = .05, .82, .62
    if EUI.GetAccentColor then r, g, b = EUI.GetAccentColor() end
    return r, g, b, string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- A pooled layout inside the shared tooltip. Only static guide text is measured.
local function Canvas(tooltip)
    local root = tooltip._formattedGuide
    if not root then
        root = CreateFrame("Frame", nil, tooltip)
        root:SetAllPoints()
        root.fonts, root.textures = {}, {}
        tooltip._formattedGuide = root
    end
    tooltip.customContent = root
    root:Show()
    root.fontIndex, root.textureIndex = 0, 0
    return root
end

local function Label(root, x, y, width, text, size, color, alpha)
    root.fontIndex = root.fontIndex + 1
    local fs = root.fonts[root.fontIndex]
    if not fs then
        fs = EUI.MakeFont(root, size, nil, 1, 1, 1, 1)
        root.fonts[root.fontIndex] = fs
    end
    local font, _, flags = fs:GetFont()
    fs:SetFont(font, size, flags)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true); fs:SetSpacing(2)
    fs:SetText(Ink(text, color or WHITE))
    fs:SetAlpha(alpha or 1)
    fs:Show()
    return fs:GetStringHeight()
end

local function Fill(root, x, y, width, height, r, g, b, alpha, sublevel)
    root.textureIndex = root.textureIndex + 1
    local tex = root.textures[root.textureIndex]
    if not tex then tex = root:CreateTexture(nil, "BACKGROUND"); root.textures[root.textureIndex] = tex end
    -- Same-layer textures may be batched in a different order by the client.
    tex:SetDrawLayer("BACKGROUND", sublevel or -6)
    tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    tex:SetSize(width, height); tex:SetColorTexture(r, g, b, alpha); tex:Show()
    return tex
end

local function Section(root, x, y, width, number, title, accent)
    Label(root, x, y + 1, 22, number, 10, accent)
    return math.max(16, Label(root, x + 25, y, width - 25, title, 14)) + 13
end

local function Recipe(root, x, y, width, example, accent)
    local textH = Label(root, x + 12, y + 10, width - 24, example.input, 12, WHITE)
    local outputH = Label(root, x + 12, y + 17 + textH, width - 24, example.output, 17, accent)
    local height = textH + outputH + 28
    Fill(root, x, y, width, height, 1, 1, 1, .035)
    return height
end

function FT:LayoutGuide(tooltip, guide, width)
    local root = Canvas(tooltip)
    local r, g, b, accent = Accent()
    local pad, gap = 20, 22
    local inner = width - pad * 2
    local bgR, bgG, bgB = EUI.GetTooltipBg()
    local backdrop = Fill(root, 0, 0, width, 1, bgR, bgG, bgB, .98, -8)
    Fill(root, 0, 0, width, 3, r, g, b, 1, -4)
    local header = Fill(root, 0, 3, width, 1, r, g, b, .055)
    Label(root, pad, 17, inner, EllesmereUI.L("TEXT FORMATTING"), 10, accent)
    local y = 35 + Label(root, pad, 35, inner, EllesmereUI.L("Custom Text Tags"), 25) + 8
    y = y + Label(root, pad, y, inner,
        EllesmereUI.L("Combine tags with plain text. Modifiers and colors are optional."), 12, MUTED) + 20
    header:SetHeight(y - 3)
    y = y + 16
    if guide.hero then
        local inputW = math.floor(inner * .66)
        local inputH = Label(root, pad + 13, y + 12, inputW - 26, EllesmereUI.L("FORMAT"), 9, MUTED)
        inputH = inputH + Label(root, pad + 13, y + 18 + inputH, inputW - 26, guide.hero.input, 15)
        local outputH = Label(root, pad + inputW + 12, y + 12, inner - inputW - 24, EllesmereUI.L("RESULT"), 9, accent)
        outputH = outputH + Label(root, pad + inputW + 12, y + 18 + outputH, inner - inputW - 24, guide.hero.output, 24, accent)
        local height = math.max(inputH, outputH) + 34
        Fill(root, pad, y, inner, height, r, g, b, .075)
        Fill(root, pad + inputW, y + 12, 1, height - 24, r, g, b, .22)
        y = y + height + 20
    end
    y = y + Label(root, pad, y, inner,
        Ink("[:", MUTED) .. Ink(EllesmereUI.L("value"), WHITE) .. Ink(":", MUTED)
        .. Ink(EllesmereUI.L("modifiers"), GOLD) .. Ink(":", MUTED)
        .. Ink("#RRGGBB", BLUE) .. Ink(":", MUTED) .. Ink(EllesmereUI.L("opacity"), "00cc99") .. Ink(":]", MUTED), 12) + 17
    local leftW = math.floor((inner - gap) * .49)
    local rightX, rightW = pad + leftW + gap, inner - leftW - gap
    local leftY = y + Section(root, pad, y, leftW, "01", EllesmereUI.L("Available Tags"), accent)
    local rightY = y + Section(root, rightX, y, rightW, "02", EllesmereUI.L("Modifiers"), GOLD)
    for i = 1, #guide.tags do
        local tag = guide.tags[i]
        local names = Ink(tag.syntax or "[:" .. tag.id .. ":]", WHITE)
        if #tag.aliases > 0 then names = names .. "  " .. Ink(table.concat(tag.aliases, " / "), accent) end
        local supports = {}
        for j = 1, #tag.modifiers do
            local canonical, shortest = tag.modifiers[j], tag.modifiers[j]
            for alias, key in pairs(tag.modifierAliases) do
                if key == canonical and #alias < #shortest then shortest = alias end
            end
            supports[#supports + 1] = shortest
        end
        if #supports > 0 then names = names .. "   " .. Ink(table.concat(supports, "  "), GOLD) end
        local height = Label(root, pad, leftY, leftW, names, 12)
        height = height + Label(root, pad, leftY + height + 4, leftW, tag.description, 11, MUTED) + 12
        leftY = leftY + height
    end
    for i = 1, #guide.modifiers do
        local mod = guide.modifiers[i]
        rightY = rightY + Label(root, rightX, rightY, rightW, table.concat(mod.names, " / "), 12, GOLD) + 4
        rightY = rightY + Label(root, rightX, rightY, rightW, mod.description, 11, MUTED) + 12
    end
    if #guide.modifiers == 0 and not guide.precision then
        rightY = rightY + Label(root, rightX, rightY, rightW,
            EllesmereUI.L("Mix these tags with your own words, spaces, and punctuation."), 12, MUTED) + 14
    end
    if guide.precision then
        local start = rightY
        rightY = rightY + Label(root, rightX + 12, rightY + 12, rightW - 24,
            EllesmereUI.L("Decimal Places"), 13, GOLD) + 20
        rightY = rightY + Label(root, rightX + 12, rightY, rightW - 24,
            EllesmereUI.L("Add :2f: for two decimal places. Omit it for whole numbers, including percentages."), 11, MUTED) + 10
        for i = 1, #guide.precision do
            local example = guide.precision[i]
            rightY = rightY + Label(root, rightX + 12, rightY, rightW - 24,
                Ink(example.input, WHITE) .. "  " .. Ink(example.output, GOLD), 11) + 7
        end
        rightY = rightY + Label(root, rightX + 12, rightY, rightW - 24,
            EllesmereUI.L("Precision: 0f through 9f. Put it before the color."), 10, MUTED) + 12
        Fill(root, rightX, start, rightW, rightY - start, .94, .73, .36, .055)
    end
    rightY = rightY + 2
    if #guide.modifiers > 0 then
        rightY = rightY + Label(root, rightX, rightY, rightW,
            EllesmereUI.L("Supported modifiers appear in gold beside each tag."), 10, MUTED) + 10
    end
    local examples = math.min(2, #guide.examples)
    if examples > 0 then
        rightY = rightY + 16
        rightY = rightY + Label(root, rightX, rightY, rightW, EllesmereUI.L("Examples"), 13, BLUE) + 10
        for i = 1, examples do
            rightY = rightY + Recipe(root, rightX, rightY, rightW, guide.examples[i], accent) + 7
        end
    end
    y = math.max(leftY, rightY) + 12
    Fill(root, pad, y, inner, 1, 1, 1, 1, .09)
    y = y + 17
    y = y + Section(root, pad, y, inner, "03", EllesmereUI.L("Color & Opacity"), BLUE)
    if guide.style then
        local inputW = math.floor(inner * .68)
        local inputH = Label(root, pad + 12, y + 11, inputW - 24, guide.style.input, 13, BLUE)
        local outputH = Label(root, pad + inputW, y + 12, inner - inputW - 12, guide.style.output, 22, "00cc99", .85)
        local noteH = Label(root, pad + 12, y + math.max(inputH, outputH) + 19, inner - 24,
            Ink("#00CC99", "00cc99") .. "  " .. EllesmereUI.L("sets the color") .. "     "
            .. Ink("85", WHITE) .. "  " .. EllesmereUI.L("sets 85% opacity"), 11, MUTED)
        local height = math.max(inputH, outputH) + noteH + 30
        Fill(root, pad, y, inner, height, .3, .6, 1, .055)
        y = y + height + 9
    end
    y = y + Label(root, pad, y, inner,
        EllesmereUI.L("Add color after modifiers, then opacity (0-100). Style applies only to that tag."), 10, MUTED) + 12
    if guide.literal then
        y = y + Label(root, pad, y, inner,
            EllesmereUI.L("Style your own words with [:text:words:]. The text keeps its case and spaces."), 11, MUTED) + 8
        y = y + Label(root, pad, y, inner,
            Ink(guide.literal.input, WHITE) .. "  " .. Ink(guide.literal.output, BLUE), 12) + 12
    end
    if guide.hasAbbreviation then
        y = y + Label(root, pad, y, inner,
            EllesmereUI.L("Restricted abbreviated values use the game's formatter, which may trim trailing zeroes."), 10, MUTED) + 10
    end
    for i = root.fontIndex + 1, #root.fonts do root.fonts[i]:Hide() end
    for i = root.textureIndex + 1, #root.textures do root.textures[i]:Hide() end
    backdrop:SetHeight(y + 6)
    return y + 6
end
