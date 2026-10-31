if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_NumberFormat_Options.lua -- Global Settings > Number Format. How large
--  numbers are shortened (EllesmereUI_NumberFormat.lua): the global Unit Style
--  and Letter Case, plus Precision and threshold per value type. Every value
--  lives in the active profile's numberFormat table; this page only writes it
--  and calls RefreshNumberFormat. It registers nothing: the Global Settings
--  module dispatches its builder.
--  eui-style: allow comment-budget (file header below the client gate)
-------------------------------------------------------------------------------

-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local PREVIEW_VALUES = { 8765, 45320, 1234567, 2345678901 }

-------------------------------------------------------------------------------
--  Settings access (the active profile's numberFormat; nil before it exists)
-------------------------------------------------------------------------------

-- Precision and threshold exactly as the engine applies them.
local function Precision(valueType)
    return (EllesmereUI.NumberFormatTypeSettings(valueType))
end

local function Threshold(valueType)
    local _, threshold = EllesmereUI.NumberFormatTypeSettings(valueType)
    return threshold
end

local function Apply()
    EllesmereUI.RefreshNumberFormat()
    EllesmereUI:RefreshPage()
end

-- Writes one field of a value type; "standard" is stored as nil.
local function SetTypeField(valueType, key, v)
    local nf = EllesmereUI.GetNumberFormatDB(true)
    if not nf then return end
    nf.types = nf.types or {}
    local t = nf.types[valueType] or {}
    nf.types[valueType] = t
    if key == "precision" and v == "standard" then v = nil end
    t[key] = v
    Apply()
end

local function SetGlobalField(key, v)
    local nf = EllesmereUI.GetNumberFormatDB(true)
    if not nf then return end
    nf[key] = v
    Apply()
end

local function PreviewText()
    local parts = {}
    for i = 1, #PREVIEW_VALUES do
        parts[i] = EllesmereUI.AbbreviateNumber(PREVIEW_VALUES[i])
    end
    return EllesmereUI.L("Preview") .. ":   " .. table.concat(parts, "   ")
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._EUI_BuildNumberFormatPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Intro: sized host + single TOPLEFT point (the search geometry
    -- contract). Chrome only, so the search index pass skips it.
    if not EllesmereUI._prebuilding then
        local introHost = CreateFrame("Frame", nil, parent)
        PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 44)
        PP.Point(introHost, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)
        local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
        intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
        intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
        intro:SetJustifyH("CENTER")
        intro:SetWordWrap(true)
        intro:SetText(EllesmereUI.L("How large numbers are shortened across EllesmereUI."))
    end
    y = y - 48

    ---------------------------------------------------------------------------
    --  UNITS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "UNITS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Unit Style",
          tooltip = "Client Language uses your client's own units (ten-thousand groups on Chinese and Korean clients). Western always uses K, M and B.",
          values = { auto = "Client Language", western = "Western (K, M, B)" },
          order = { "auto", "western" },
          getValue = function()
              local nf = EllesmereUI.GetNumberFormatDB()
              return (nf and nf.units == "western") and "western" or "auto"
          end,
          setValue = function(v) SetGlobalField("units", v ~= "auto" and v or nil) end,
          disabled = function() return not EllesmereUI.LocaleHasNumberAbbreviation() end,
          disabledTooltip = "Only East Asian clients have their own units" },
        { type = "dropdown", text = "Letter Case",
          tooltip = "Upper or lower case unit letters.",
          values = { upper = "K M B", lower = "k m b" },
          order = { "upper", "lower" },
          getValue = function()
              local nf = EllesmereUI.GetNumberFormatDB()
              return (nf and nf.case == "lower") and "lower" or "upper"
          end,
          setValue = function(v) SetGlobalField("case", v ~= "upper" and v or nil) end,
          disabled = function() return Precision("meter") == "standard" or EllesmereUI.NumberFormatUsesGlyphs() end,
          disabledTooltip = function()
              if EllesmereUI.NumberFormatUsesGlyphs() then return "Your client's units have no letter case" end
              return "This option requires a Precision other than Standard"
          end });  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DAMAGE METERS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DAMAGE METERS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Precision",
          tooltip = "Standard keeps the Damage Meters' own format. Smart shows three digits (1.23M, 12.3M, 123M). Also applies to the gold bar and the Mythic+ run summary.",
          values = { standard = "Standard", smart = "Smart (3 Digits)",
                     [0] = "0 Decimals", [1] = "1 Decimal", [2] = "2 Decimals" },
          order = { "standard", "smart", 0, 1, 2 },
          getValue = function() return Precision("meter") end,
          setValue = function(v) SetTypeField("meter", "precision", v) end },
        { type = "dropdown", text = "Start Abbreviating At",
          tooltip = "Numbers below this stay whole.",
          values = { [1000] = "1,000", [10000] = "10,000", [100000] = "100,000" },
          order = { 1000, 10000, 100000 },
          getValue = function() return Threshold("meter") end,
          setValue = function(v) SetTypeField("meter", "threshold", v) end,
          disabled = function() return Precision("meter") == "standard" end,
          disabledTooltip = "This option requires a Precision other than Standard" });  y = y - h

    -- Live preview: chrome only, so the search index pass skips it but still
    -- steps past its row so the rows below index at their live positions.
    if not EllesmereUI._prebuilding then
        local host = CreateFrame("Frame", nil, parent)
        PP.Size(host, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 34)
        PP.Point(host, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
        host._skipRowDivider = true
        local lbl = EllesmereUI.MakeFont(host, 13, nil, 1, 1, 1, 0.8)
        lbl:SetPoint("LEFT", host, "LEFT", 20, 0)
        lbl:SetText(PreviewText())
        EllesmereUI.RegisterWidgetRefresh(function() lbl:SetText(PreviewText()) end)
    end
    y = y - 34

    y = EllesmereUI.BuildNoteRow(parent, y, "Numbers are cut, not rounded.")

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
