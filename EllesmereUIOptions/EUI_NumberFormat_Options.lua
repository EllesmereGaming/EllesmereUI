if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_NumberFormat_Options.lua -- Global Settings > Numbers. How large
--  numbers are shortened (EllesmereUI_NumberFormat.lua): Precision and
--  threshold per value type, picked in the page header, plus the global Unit
--  Style and Letter Case. Every value lives in the active profile's
--  numberFormat table; this page only writes it and calls RefreshNumberFormat.
--  The Global Settings module dispatches the builder, the header and the
--  search variants (one per value type) from here.
--  eui-style: allow comment-budget (file header below the client gate)
-------------------------------------------------------------------------------

-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local PREVIEW_VALUES = { 8765, 45320, 1234567, 2345678901 }
local TYPES = EllesmereUI.NUMBER_FORMAT_TYPES

local TYPE_LABELS = {
    health = "Health", maxHealth = "Max Health", absorb = "Absorb",
    bossHealth = "Boss Health", meter = "Damage Meter",
}
-- One label per type, so each search hit restores its own type.
local PRECISION_LABELS = {
    health = "Health Precision", maxHealth = "Max Health Precision",
    absorb = "Absorb Precision", bossHealth = "Boss Health Precision",
    meter = "Damage Meter Precision",
}
local PRECISION_TIPS = {
    health = "Current health values on Unit Frames, Raid Frames, Nameplates and the Resource Bars health bar. Standard keeps Blizzard's format. Smart shows three digits (1.23M, 12.3M, 123M).",
    maxHealth = "Maximum health values on Unit Frames, Raid Frames, Nameplates and the Resource Bars health bar. Standard keeps Blizzard's format. Smart shows three digits (1.23M, 12.3M, 123M).",
    absorb = "Absorb and heal absorb values on Unit Frames, Raid Frames and Nameplates. Standard keeps Blizzard's format. Smart shows three digits (1.23M, 12.3M, 123M).",
    bossHealth = "Current and maximum health on the Unit Frames boss frames. Standard keeps Blizzard's format. Smart shows three digits (1.23M, 12.3M, 123M).",
    meter = "Damage Meters and the Mythic+ run summary. Standard keeps the Damage Meters' own format. Smart shows three digits (1.23M, 12.3M, 123M).",
}

-- The type the page shows; also set by a search jump (getPrebuildVariants).
local selectedType = TYPES[1]
EllesmereUI._setNumberFormatType = function(valueType) selectedType = valueType end
function _G._EUI_NumberFormatVariants()
    return { setter = EllesmereUI._setNumberFormatType, keys = TYPES, currentKey = selectedType }
end

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

local function AllStandard()
    for i = 1, #TYPES do
        if Precision(TYPES[i]) ~= "standard" then return false end
    end
    return true
end

-- n as valueType reads now: the module's own call while it is on Standard.
local function FormatAs(valueType, n)
    local opts = EllesmereUI.NumberFormatOptions(valueType)
    if opts then return AbbreviateNumbers(n, opts) end
    if EllesmereUI.ForeverAbbreviateNumbers then return EllesmereUI.ForeverAbbreviateNumbers(n) end
    return AbbreviateNumbers(n)
end

-- Repaints the header's preview and markers; set by the header builder.
local headerRefresh

local function Apply()
    EllesmereUI.RefreshNumberFormat()
    if headerRefresh then headerRefresh() end
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

local PRECISION_VALUES = { standard = "Standard", smart = "Smart (3 Digits)",
                           [0] = "0 Decimals", [1] = "1 Decimal", [2] = "2 Decimals" }
local PRECISION_ORDER = { "standard", "smart", 0, 1, 2 }
local THRESHOLD_VALUES = { [1000] = "1,000", [10000] = "10,000", [100000] = "100,000" }
local THRESHOLD_ORDER = { 1000, 10000, 100000 }
local THRESHOLD_TIP = "Numbers below this stay whole."
local THRESHOLD_LOCK = "This option requires a Precision other than Standard"

-------------------------------------------------------------------------------
--  Header: value type tabs, a live preview, and the type's Precision and
--  threshold
-------------------------------------------------------------------------------
local INFO_ICON = [[Interface\AddOns\EllesmereUI\media\icons\eui-info.png]]

-- A header label and dropdown with the row tooltip on the label; withInfo puts
-- an (i) after the label that shares the label's tooltip.
local function HeaderDropdown(hdr, text, tip, w, values, order, getValue, setValue, withInfo)
    local L = EllesmereUI.L
    local lbl = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 1)
    lbl:SetText(L(text))
    local dd = EllesmereUI.BuildDropdownControl(hdr, w, hdr:GetFrameLevel() + 5, values, order, getValue, setValue)
    local info
    if withInfo then
        info = hdr:CreateTexture(nil, "OVERLAY")
        info:SetTexture(INFO_ICON)
        info:SetVertexColor(1, 1, 1, 0.45)
        EllesmereUI.PanelPP.Size(info, 12, 12)
        info:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
    end
    local hit = CreateFrame("Frame", nil, hdr)
    hit:SetPoint("TOPLEFT", lbl, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", info or lbl, "BOTTOMRIGHT", 0, 0)
    hit:SetMouseClickEnabled(false)
    hit:SetMouseMotionEnabled(true)
    hit:SetScript("OnEnter", function()
        if info then info:SetVertexColor(1, 1, 1, 0.9) end
        EllesmereUI.ShowWidgetTooltip(lbl, tip())
    end)
    hit:SetScript("OnLeave", function()
        if info then info:SetVertexColor(1, 1, 1, 0.45) end
        EllesmereUI.HideWidgetTooltip()
    end)
    return lbl, dd, info
end

local function HeaderBuilder(hdr, hdrW)
    local PP = EllesmereUI.PanelPP
    local L = EllesmereUI.L
    local accent = EllesmereUI.ELLESMERE_GREEN
    local vt = selectedType
    local y = -16

    local labels = {}
    for i = 1, #TYPES do labels[TYPES[i]] = TYPE_LABELS[TYPES[i]] end
    local seg, segH, segRefresh = EllesmereUI.BuildSegmentedControl({
        parent     = hdr,
        keys       = TYPES,
        labels     = labels,
        autoWidth  = true,
        square     = true,
        getChecked = function(key) return key == selectedType end,
        onToggle   = function(key)
            if key == selectedType then return end
            local savedScroll = EllesmereUI.GetContentScroll and EllesmereUI.GetContentScroll() or 0
            selectedType = key
            -- One pass builds the page and its header for the new type.
            EllesmereUI:RefreshPage(true)
            EllesmereUI.SmoothScrollTo(savedScroll)
        end,
    })
    seg:SetFrameLevel(hdr:GetFrameLevel() + 5)
    PP.Point(seg, "TOP", hdr, "TOP", 0, y)
    y = y - segH - 20

    -- Preview: one column per value, the raw number small above its result.
    local COL_W = 130
    local results = {}
    for i = 1, #PREVIEW_VALUES do
        local v = PREVIEW_VALUES[i]
        local x = (i - (#PREVIEW_VALUES + 1) / 2) * COL_W
        local raw = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.4)
        raw:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v))
        PP.Point(raw, "TOP", hdr, "TOP", x, y)
        local res = EllesmereUI.MakeFont(hdr, 20, nil, accent.r, accent.g, accent.b, 1)
        PP.Point(res, "TOP", hdr, "TOP", x, y - 16)
        results[i] = res
    end
    y = y - 16 - 24 - 18

    -- Precision (its (i) names the modules and the cut) and threshold of the
    -- shown type, either side of the middle.
    local pLbl, pDD, pInfo = HeaderDropdown(hdr, PRECISION_LABELS[vt],
        function() return L(PRECISION_TIPS[vt]) .. "\n\n" .. EllesmereUI.L("Numbers are cut, not rounded.") end,
        170, PRECISION_VALUES, PRECISION_ORDER,
        function() return Precision(vt) end,
        function(v) SetTypeField(vt, "precision", v) end, true)
    PP.Point(pDD, "TOPRIGHT", hdr, "TOP", -20, y)
    -- The label centers on the dropdown; the (i) sits 3px lower to meet the
    -- label's optical middle.
    pLbl:SetPoint("RIGHT", pDD, "LEFT", -(12 + 12 + 5), 0)
    pInfo:ClearAllPoints()
    pInfo:SetPoint("LEFT", pLbl, "RIGHT", 5, -3)
    local tLbl, tDD = HeaderDropdown(hdr, "Start Abbreviating At", function() return L(THRESHOLD_TIP) end,
        110, THRESHOLD_VALUES, THRESHOLD_ORDER,
        function() return Threshold(vt) end,
        function(v) SetTypeField(vt, "threshold", v) end)
    tLbl:SetPoint("TOPLEFT", hdr, "TOP", 20, y - 8)
    tDD:SetPoint("LEFT", tLbl, "RIGHT", 12, 0)
    -- Locked while the type is on Standard: greyed, with the row lock tooltip.
    local tLock = CreateFrame("Frame", nil, hdr)
    tLock:SetPoint("TOPLEFT", tLbl, "TOPLEFT", 0, 0)
    tLock:SetPoint("BOTTOMRIGHT", tDD, "BOTTOMRIGHT", 0, 0)
    tLock:SetFrameLevel(tDD:GetFrameLevel() + 10)
    tLock:EnableMouse(true)
    tLock:SetScript("OnEnter", function()
        EllesmereUI.ShowWidgetTooltip(tDD, EllesmereUI.ResolveDisabledTip({ disabledTooltip = THRESHOLD_LOCK }))
    end)
    tLock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    y = y - 30 - 16

    headerRefresh = function()
        for i = 1, #PREVIEW_VALUES do results[i]:SetText(FormatAs(vt, PREVIEW_VALUES[i])) end
        local locked = Precision(vt) == "standard"
        tLbl:SetAlpha(locked and 0.3 or 1)
        tDD:SetAlpha(locked and 0.3 or 1)
        tDD:EnableMouse(not locked)
        tLock:SetShown(locked)
        pDD._refreshLabel()
        tDD._refreshLabel()
        if segRefresh then segRefresh() end
    end
    headerRefresh()

    return math.abs(y)
end

function _G._EUI_NumberFormatHeaderBuilder()
    return HeaderBuilder
end

function _G._EUI_NumberFormatRefreshHeader()
    if headerRefresh then headerRefresh() end
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._EUI_BuildNumberFormatPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local vt = selectedType

    EllesmereUI:SetContentHeader(HeaderBuilder)
    -- The type's Precision and threshold sit in the header, which the search
    -- never indexes: register them here, per type, with the type as selector
    -- key. Their section is not on the page, so a jump selects the type and
    -- stops there. The body rows are global and stay untagged, so a jump to
    -- them keeps the shown type.
    local setter = EllesmereUI._setNumberFormatType
    if EllesmereUI._RegisterSearchEntry then
        local L = EllesmereUI.L
        local module, page = EllesmereUI._buildingModule, EllesmereUI._buildingPage
        for _, e in ipairs({ { PRECISION_LABELS[vt], PRECISION_TIPS[vt] }, { "Start Abbreviating At", THRESHOLD_TIP } }) do
            local loc = L(e[1])
            EllesmereUI._RegisterSearchEntry(e[1], loc ~= e[1] and loc or nil, e[2], module, page, "PRECISION", setter, vt)
        end
    end

    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  UNITS (GLOBAL): every type
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "UNITS (GLOBAL)", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Letter Case",
          tooltip = "Upper or lower case unit letters, for every value type with a Precision other than Standard.",
          values = { upper = "K M B", lower = "k m b" },
          order = { "upper", "lower" },
          getValue = function()
              local nf = EllesmereUI.GetNumberFormatDB()
              return (nf and nf.case == "lower") and "lower" or "upper"
          end,
          setValue = function(v) SetGlobalField("case", v ~= "upper" and v or nil) end,
          disabled = function() return AllStandard() or EllesmereUI.NumberFormatUsesGlyphs() end,
          disabledTooltip = function()
              if EllesmereUI.NumberFormatUsesGlyphs() then return "Your client's units have no letter case" end
              return "This option requires a value type with a Precision other than Standard"
          end },
        { type = "dropdown", text = "Unit Style",
          tooltip = "Client Language uses your client's own units (ten-thousand groups on Chinese and Korean clients). Western always uses K, M and B. Applies to every value type.",
          values = { auto = "Client Language", western = "Western (K, M, B)" },
          order = { "auto", "western" },
          getValue = function()
              local nf = EllesmereUI.GetNumberFormatDB()
              return (nf and nf.units == "western") and "western" or "auto"
          end,
          setValue = function(v) SetGlobalField("units", v ~= "auto" and v or nil) end,
          disabled = function() return not EllesmereUI.LocaleHasNumberAbbreviation() end,
          disabledTooltip = "Only East Asian clients have their own units" });  y = y - h

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
