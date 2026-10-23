if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local EUI, FT = EllesmereUI, EllesmereUI.FormattedText
local formats, abbreviationRows, abbreviationOptions = {}, nil, {}
for precision = 0, FT.MAX_PRECISION do formats[precision] = "%." .. precision .. "f" end

local function Rows()
    if not abbreviationRows then abbreviationRows = EUI.GetNumberAbbreviationData() end
    return abbreviationRows
end

local function AbbreviationOptions(precision)
    local options = abbreviationOptions[precision]
    if options then return options end
    local rows, source, factor = {}, Rows(), 10 ^ precision
    for i = 1, #source do
        local row = source[i]
        rows[i] = { breakpoint = row.breakpoint, abbreviation = row.abbreviation,
            abbreviationIsGlobal = row.abbreviationIsGlobal,
            significandDivisor = row.significandDivisor * row.fractionDivisor / factor,
            fractionDivisor = factor }
    end
    options = { config = CreateAbbreviateConfig(rows) }
    abbreviationOptions[precision] = options
    return options
end

function FT._internal.PrepareNumber(node)
    if node.variant.abbreviated then AbbreviationOptions(node.precision or 0) end
end

-- Restricted numbers only enter native formatters; no arithmetic, parsing,
-- comparison, or inspection of their rendered strings occurs in Lua.
function FT._internal.FormatValue(node, value)
    local variant, precision = node.variant, node.precision or 0
    if issecretvalue(value) then
        if variant.abbreviated then return AbbreviateNumbers(value, AbbreviationOptions(precision)) end
        return FT:FormatNumber(formats[precision], value)
    end
    -- Mixed numeric/text providers retain unavailable markers and labels.
    if type(value) ~= "number" then
        local number = type(value) == "string" and tonumber(value)
        if not number then return value end
        value = number
    end
    if variant.abbreviated then
        local rows = Rows()
        for i = 1, #rows do
            local row = rows[i]
            if value >= row.breakpoint then
                local suffix = row.abbreviationIsGlobal ~= false and _G[row.abbreviation] or row.abbreviation
                return string.format(formats[precision], value / (row.significandDivisor * row.fractionDivisor)) .. (suffix or "")
            end
        end
    end
    return string.format(formats[precision], value)
end
