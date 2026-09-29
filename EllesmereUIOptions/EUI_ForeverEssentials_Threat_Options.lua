if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Threat_Options.lua
--  Builds the "Threat" page inside the Forever Essentials module: a live
--  preview of the meter in the content header, then its settings. Reads go
--  through the meter's Get (saved value, else the default); writes create only
--  the key they change.
-------------------------------------------------------------------------------
local module = EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"]
local ns = module and module.ThreatMeter
if not ns then return end  -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = ns.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._EUI_ThreatHeaderBuilder = HeaderBuilder

local ICON_STYLES = { none = "None", blizzard = "Blizzard", modern = "Modern", pixel = "Pixel", glyph = "Glyph",
    arcade = "Arcade", legend = "Legend", midnight = "Midnight", runic = "Runic" }
local ICON_STYLE_ORDER = { "none", "---", "blizzard", "modern", "pixel", "glyph", "arcade", "legend", "midnight", "runic" }
local BAR_COLORS = { class = "Class Color", accent = "Accent Color", custom = "Custom Color" }
local BAR_COLOR_ORDER = { "class", "accent", "custom" }
local OUTLINES = { __global = "EUI Global Default", none = "Drop Shadow", outline = "Outline", thick = "Thick Outline" }
local OUTLINE_ORDER = { "__global", "none", "outline", "thick" }
local PCT_POSITIONS = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center" }
local PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER" }

_G._EUI_BuildThreatMeterPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local BLANK = EllesmereUI.BlankRowCfg
    local BS = EllesmereUI.BlizzStyle
    local Get, GetStyle = ns.Get, ns.GetStyleValue
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    -- Style page gates: Gate() for settings neither stock look uses,
    -- BlizzOnly() for those only Blizzard Style ignores.
    local function Gate(cfg)
        return BS.Gate("threatmeter", cfg)
    end
    local function BlizzOnly(cfg)
        if BS.Active("threatmeter") == "blizzard" then return Gate(cfg) end
        return cfg
    end

    ns.BarTextures()
    EllesmereUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not Get("enabled")
    end
    -- A row that needs the meter on and one more condition: greyed by either,
    -- with the requirement that is actually blocking it. raw marks a whole
    -- sentence (shown as is instead of wrapped).
    local function Needs(cond, requirement, raw)
        return function() return off() or cond() end,
            function() if off() then return "Threat Meter" end return requirement end,
            raw and function() return not off() end or nil
    end
    -- Writes only (read live by the meter), writes that restyle, and writes
    -- whose toggle gates other rows.
    local function Store(key, v)
        ns.Cfg()[key] = v
    end
    local function Set(key, v)
        ns.Cfg()[key] = v
        ns.ApplyStyle()
    end
    local function SetAndRefresh(key, v)
        Set(key, v)
        EllesmereUI:RefreshPage()
    end
    -- A size whose swatch greys out at zero refreshes the page only when it
    -- crosses zero, so a slider drag just restyles.
    local function IsZero(group, key)
        return (GetStyle(group, key) or 0) == 0
    end
    local function SetStyleSize(group, key, v)
        local was = IsZero(group, key)
        ns.SetStyleValue(group, key, v)
        if IsZero(group, key) ~= was then EllesmereUI:RefreshPage() end
    end

    local function Toggle(key, text, tooltip, setValue)
        return { type = "toggle", text = text, tooltip = tooltip,
            disabled = off, disabledTooltip = "Threat Meter",
            getValue = function() return Get(key) end,
            setValue = setValue or function(v) Set(key, v) end }
    end
    local function Slider(key, text, low, high, tooltip)
        return { type = "slider", text = text, min = low, max = high, step = 1, tooltip = tooltip,
            disabled = off, disabledTooltip = "Threat Meter",
            getValue = function() return Get(key) end,
            setValue = function(v) Set(key, v) end }
    end
    local function StyleToggle(group, key, text, gates)
        return { type = "toggle", text = text,
            disabled = off, disabledTooltip = "Threat Meter",
            getValue = function() return GetStyle(group, key) end,
            setValue = function(v)
                ns.SetStyleValue(group, key, v)
                if gates then EllesmereUI:RefreshPage() end
            end }
    end
    local function StyleSlider(group, key, text, low, high, step)
        return { type = "slider", text = text, min = low, max = high, step = step or 1,
            disabled = off, disabledTooltip = "Threat Meter",
            getValue = function() return GetStyle(group, key) end,
            setValue = function(v) ns.SetStyleValue(group, key, v) end }
    end

    -- Inline swatches. A saved colour table is shared or converted, so every
    -- write stores a new one.
    local function ColorSwatch(key, tooltip, disabled, disabledTooltip)
        return { tooltip = tooltip, disabled = disabled, disabledTooltip = disabledTooltip,
            getValue = function() local c = Get(key); return c.r, c.g, c.b end,
            setValue = function(r, g, b) Set(key, { r = r, g = g, b = b }) end }
    end
    local function StyleSwatch(group, key, tooltip)
        local sc = { tooltip = tooltip, disabled = off, disabledTooltip = "Threat Meter" }
        if type(key) == "table" then
            sc.getValue = function() return GetStyle(group, key[1]), GetStyle(group, key[2]), GetStyle(group, key[3]) end
            sc.setValue = function(r, g, b) ns.SetStyleValues(group, { [key[1]] = r, [key[2]] = g, [key[3]] = b }) end
        else
            sc.getValue = function() local c = GetStyle(group, key); return c.r, c.g, c.b end
            sc.setValue = function(r, g, b) ns.SetStyleValue(group, key, { r = r, g = g, b = b, a = 1 }) end
        end
        return sc
    end
    -- The custom alternative to a class or accent colour: dimmed while that one
    -- is in use, and its first click switches to the custom colour.
    local function Alternative(sc, isActive, activate)
        sc.refreshAlpha = function() return isActive() and 1 or 0.3 end
        sc.onClick = function(self)
            if not isActive() then
                activate()
                EllesmereUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end
        return sc
    end
    local function AlternativeTo(sc, group, flag)
        return Alternative(sc, function() return not GetStyle(group, flag) end,
            function() ns.SetStyleValue(group, flag, false) end)
    end
    local function Swatch(region, sc)
        EllesmereUI.BuildInlineSwatches(region, { sc })
    end
    local function OffsetCog(region, title, keyX, keyY, disabled, disabledTooltip, rawTooltip)
        EllesmereUI.BuildInlineCog(region, {
            title = title, icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = disabled, disabledTooltip = disabledTooltip, rawTooltip = rawTooltip,
            rows = {
                { type = "slider", label = "X Offset", min = -20, max = 20, step = 1,
                  get = function() return GetStyle(keyX[1], keyX[2]) end,
                  set = function(v) ns.SetStyleValue(keyX[1], keyX[2], v) end },
                { type = "slider", label = "Y Offset", min = -20, max = 20, step = 1,
                  get = function() return GetStyle(keyY[1], keyY[2]) end,
                  set = function(v) ns.SetStyleValue(keyY[1], keyY[2], v) end },
            },
        })
    end

    ---------------------------------------------------------------------------
    --  THREAT METER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "THREAT METER", y);  y = y - h
    y = BS.Note(parent, y, "threatmeter")

    -- Lock state belongs to the lock icon on the meter itself.
    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { leftCfg = { type = "toggle", text = "Enable Threat Meter",
              tooltip = "Shows everyone's threat on your target, highest first. With a friendly target, it shows the threat on what they are fighting.",
              getValue = function() return not off() end,
              setValue = function(v)
                  ns.Cfg().enabled = v
                  ns.Apply()
                  EllesmereUI:RefreshPage()
              end },
          getStore = ns.Cfg,
          legacyKey = "visibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
          -- Stored as onlyWithThreat: nil (the default) hides the meter while it
          -- has no threat to list, false keeps it on screen.
          extraItems = {
              { key = "onlyWithThreat", label = "Only With Threat", default = true,
                tooltip = "Only show the meter while there is threat to list. Unchecked keeps the header and its buttons on screen." },
          },
          disabledFn = off, disabledTooltip = "Threat Meter",
          onChanged = EllesmereUI.RequestVisibilityUpdate,
          onOptionChanged = EllesmereUI.RequestVisibilityUpdate });  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("focusEnabled", "Enable Focus Tracking", "Adds a Target/Focus switch to the meter header.",
            function(v)
                ns.SetFocusEnabled(v)
                ns.ApplyStyle()
            end),
        { type = "toggle", text = "Ignore Pets",
          tooltip = "Leaves pets out of the list.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return not Get("pets") end,
          setValue = function(v) Set("pets", not v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  WARNING (its settings are built while the sound is on)
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "WARNING", y);  y = y - h

    local warnOn = Get("warnSound")
    local warnToggle = Toggle("warnSound", "Warning Sound",
        "Plays once when your threat climbs past the threshold, and again only after it has dropped back below.",
        EllesmereUI.SectionToggleSetValue(function(v) Store("warnSound", v) end))
    if warnOn then
        local sndValues, sndOrder = EllesmereUI.BuildSoundDropdownValues(ns.Sounds())
        _, h = W:DualRow(parent, y, warnToggle,
            { type = "dropdown", text = "Sound", values = sndValues, order = sndOrder,
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return Get("warnSoundKey") end,
              setValue = function(v) Store("warnSoundKey", v) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Warn At (%)", min = 50, max = 100, step = 1,
              tooltip = "100% is where you pull aggro.",
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return Get("warnAt") end,
              setValue = function(v) Store("warnAt", v) end },
            Toggle("warnSkipTank", "Not While Tanking",
                "No warning while you have the tank role, or are in Bear Form or Defensive Stance.",
                function(v) Store("warnSkipTank", v) end)
        );  y = y - h
    else
        _, h = W:DualRow(parent, y, warnToggle, BLANK());  y = y - h
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  THREAT % TEXT (the Nameplates and Unit Frames settings; a module that
    --  is off has no row)
    ---------------------------------------------------------------------------
    local np = EllesmereUI._ModuleNS["EllesmereUINameplates"]
    local uf = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
    local hasNP = np and np.db
    local hasUF = uf and uf.db
    if hasNP or hasUF then
        _, h = W:SectionHeader(parent, "THREAT % TEXT", y);  y = y - h

        -- Toggle | Position, the Threat % cog on the dropdown. blocked (optional)
        -- greys the row with blockedTip; a toggle left on stays clickable so it
        -- can still be turned off.
        local function PctRow(text, tooltip, profile, apply, blocked, blockedTip)
            local function PGet(key) return profile()[key] end
            local function PSet(key, v)
                profile()[key] = v
                apply(key, v)
            end
            local function pctOff() return (blocked and blocked()) or not PGet("threatPctEnabled") end
            local function pctOffTip()
                if blocked and blocked() then return blockedTip end
                return text
            end
            local function Offset(key, label, low, high)
                return { type = "slider", label = label, min = low, max = high, step = 1,
                    get = function() return PGet(key) end,
                    set = function(v) PSet(key, v) end }
            end
            local row
            row, h = W:DualRow(parent, y,
                { type = "toggle", text = text, tooltip = tooltip,
                  disabled = blocked and function() return blocked() and not PGet("threatPctEnabled") end,
                  disabledTooltip = blocked and blockedTip,
                  getValue = function() return PGet("threatPctEnabled") end,
                  setValue = function(v)
                      PSet("threatPctEnabled", v)
                      EllesmereUI:RefreshPage()
                  end },
                { type = "dropdown", text = "Position", values = PCT_POSITIONS, order = PCT_POSITION_ORDER,
                  disabled = pctOff, disabledTooltip = pctOffTip,
                  getValue = function() return PGet("threatPctPosition") end,
                  setValue = function(v) PSet("threatPctPosition", v) end }
            );  y = y - h
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(row._rightRegion, {
                    title = "Threat %", disabled = pctOff, disabledTooltip = pctOffTip,
                    rows = {
                        { type = "toggle", label = "Color by Threat",
                          tooltip = "Colors the number by threat status. Off shows it in white.",
                          get = function() return PGet("threatPctColorByThreat") end,
                          set = function(v) PSet("threatPctColorByThreat", v) end },
                        Offset("threatPctSize", "Size", 6, 20),
                        Offset("threatPctXOffset", "X Offset", -100, 100),
                        Offset("threatPctYOffset", "Y Offset", -100, 100),
                    },
                })
            end
        end

        if hasNP then
            PctRow("Show on Nameplates",
                "Shows your threat percentage on each enemy nameplate while you are in combat with it.",
                function() return np.db.profile end,
                function() np.RefreshThreatPct() end)
        end
        if hasUF then
            PctRow("Show on Target & Focus Frames",
                "Shows your threat percentage on the target and focus frames while you are in combat with that unit.",
                function() return uf.db.profile end,
                function(key, v)
                    if key == "threatPctEnabled" then uf.SetThreatPctEnabled(v) else uf.RefreshThreatPct() end
                end,
                function() return not (uf.frames.target or uf.frames.focus) end,
                "This option requires an EllesmereUI Target or Focus frame.")
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
    end

    ---------------------------------------------------------------------------
    --  BARS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BARS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("barHeight", "Bar Height", 8, 40),
        Slider("barSpacing", "Bar Spacing", 0, 10)
    );  y = y - h

    local texValues, texOrder = {}, {}
    do
        local lookup, names = ns.BarTextures(), ns.BarTextureNames
        for _, key in ipairs(ns.BarTextureOrder) do
            if key ~= "---" then texValues[key] = names[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return lookup[key] end }
    end
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture", values = texValues, order = texOrder,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return GetStyle("bars", "barTexture") end,
          setValue = function(v) ns.SetStyleValue("bars", "barTexture", v) end },
        { type = "dropdown", text = "Icon Style", values = ICON_STYLES, order = ICON_STYLE_ORDER,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return GetStyle("bars", "iconStyle") end,
          setValue = function(v) ns.SetStyleValue("bars", "iconStyle", v) end }
    );  y = y - h

    local pullRow
    pullRow, h = W:DualRow(parent, y,
        Toggle("pullBar", "Pull Aggro Bar", "An extra bar showing how much threat takes aggro from the tank.",
            function(v) SetAndRefresh("pullBar", v) end),
        Toggle("growUp", "Grow Upward", "Lists the highest threat at the bottom instead of the top.")
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local pullOff, pullTip = Needs(function() return not Get("pullBar") end, "Pull Aggro Bar")
        Swatch(pullRow._leftRegion, ColorSwatch("pullColor", "Pull Aggro Bar Color", pullOff, pullTip))
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  HEADER (its settings are built while the header is shown)
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "HEADER", y);  y = y - h

    local headerToggle = Toggle("showHeader", "Show Header",
        "A title row with the name of the mob whose threat is shown.",
        EllesmereUI.SectionToggleSetValue(function(v) Set("showHeader", v) end))
    if Get("showHeader") then
        _, h = W:DualRow(parent, y, headerToggle, StyleSlider("header", "hdrHeight", "Header Height", 14, 40));  y = y - h

        local textRow
        textRow, h = W:DualRow(parent, y,
            StyleSlider("header", "hdrFontSize", "Header Text Size", 8, 20),
            StyleToggle("header", "hdrTextUseAccent", "Accent Header Text", true)
        );  y = y - h
        if not EllesmereUI._prebuilding then
            OffsetCog(textRow._leftRegion, "Title Position", { "header", "hdrTextOffX" }, { "header", "hdrTextOffY" },
                off, "Threat Meter")
            Swatch(textRow._rightRegion, AlternativeTo(StyleSwatch("header", "hdrTextColor", "Header Text Color"),
                "header", "hdrTextUseAccent"))
        end

        local bgRow
        bgRow, h = W:DualRow(parent, y,
            StyleSlider("header", "hdrBgAlpha", "Header Opacity", 0, 1, 0.01),
            Gate({ type = "slider", text = "Header Bottom Border", min = 0, max = 4, step = 1,
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return GetStyle("header", "hdrBottomBorderSize") end,
              setValue = function(v) SetStyleSize("header", "hdrBottomBorderSize", v) end })
        );  y = y - h
        if not EllesmereUI._prebuilding then
            Swatch(bgRow._leftRegion, Gate(StyleSwatch("header", "hdrBgColor", "Header Background")))
            local lineSwatch = StyleSwatch("header", "hdrBottomBorderColor", "Header Border Color")
            lineSwatch.disabled, lineSwatch.disabledTooltip =
                Needs(function() return IsZero("header", "hdrBottomBorderSize") end, "Header Bottom Border")
            Swatch(bgRow._rightRegion, Gate(lineSwatch))
        end
    else
        _, h = W:DualRow(parent, y, headerToggle, BLANK());  y = y - h
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  COLORS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "COLORS", y);  y = y - h

    local function BarColorMode()
        if GetStyle("colors", "showClassColor") ~= false then return "class" end
        if GetStyle("colors", "barColorUseAccent") ~= false then return "accent" end
        return "custom"
    end
    local function SetBarColorMode(v)
        if v == "class" then
            ns.SetStyleValue("colors", "showClassColor", true)
        else
            ns.SetStyleValues("colors", { showClassColor = false, barColorUseAccent = v == "accent" })
        end
    end
    local fillRow
    fillRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Color", values = BAR_COLORS, order = BAR_COLOR_ORDER,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = BarColorMode,
          setValue = function(v)
              SetBarColorMode(v)
              EllesmereUI:RefreshPage()
          end },
        StyleSlider("colors", "barFillAlpha", "Bar Opacity", 0, 1, 0.01)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(fillRow._leftRegion, Alternative(StyleSwatch("colors", "barColor", "Custom Color"),
            function() return BarColorMode() == "custom" end,
            function() SetBarColorMode("custom") end))
    end

    local customRow
    customRow, h = W:DualRow(parent, y,
        Toggle("playerColorOn", "Custom Player Color", "Your own bar in a fixed color instead of your class color.",
            function(v) SetAndRefresh("playerColorOn", v) end),
        Toggle("tankColorOn", "Custom Tank Color", "The bar of whoever holds aggro in a fixed color instead of their class color.",
            function(v) SetAndRefresh("tankColorOn", v) end)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local playerOff, playerTip = Needs(function() return not Get("playerColorOn") end, "Custom Player Color")
        Swatch(customRow._leftRegion, ColorSwatch("playerColor", "Player Color", playerOff, playerTip))
        local tankOff, tankTip = Needs(function() return not Get("tankColorOn") end, "Custom Tank Color")
        Swatch(customRow._rightRegion, ColorSwatch("tankColor", "Tank Color", tankOff, tankTip))
    end

    local barBgRow
    barBgRow, h = W:DualRow(parent, y,
        BlizzOnly(StyleToggle("colors", "barBgUseClassColor", "Class-Colored Background", true)),
        BlizzOnly(StyleSlider("colors", "barBgAlpha", "Bar Background Opacity", 0, 1, 0.01))
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(barBgRow._leftRegion, BlizzOnly(AlternativeTo(StyleSwatch("colors", { "barBgR", "barBgG", "barBgB" },
            "Bar Background"), "colors", "barBgUseClassColor")))
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  BAR TEXT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BAR TEXT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("fontSize", "Text Size", 8, 24),
        { type = "dropdown", text = "Displayed Value",
          tooltip = "Pull % reaches 100 where a player would take aggro, Tank % where they match the tank's threat.",
          values = ns.DisplayValues, order = ns.DisplayOrder,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = ns.GetDisplayedValue,
          setValue = function(v)
              ns.SetDisplayedValue(v)
              ns.ApplyStyle()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    do
        local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return Get("font") end,
              setValue = function(v) Set("font", v) end },
            { type = "dropdown", text = "Font Outline", values = OUTLINES, order = OUTLINE_ORDER,
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return Get("outlineMode") end,
              setValue = function(v) Set("outlineMode", v) end }
        );  y = y - h
    end

    -- Value text settings do nothing while no value is displayed.
    local valueOff, valueTip, valueRaw = Needs(function() return ns.GetDisplayedValue() == "none" end,
        "This option requires a Displayed Value other than None.", true)
    local valuesToggle = StyleToggle("colors", "rightTextUseClassColor", "Class-Colored Values", true)
    valuesToggle.disabled, valuesToggle.disabledTooltip, valuesToggle.rawTooltip = valueOff, valueTip, valueRaw
    local nameRow
    nameRow, h = W:DualRow(parent, y,
        StyleToggle("colors", "leftTextUseClassColor", "Class-Colored Names", true),
        valuesToggle
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(nameRow._leftRegion, AlternativeTo(StyleSwatch("colors", "leftTextColor", "Name Color"),
            "colors", "leftTextUseClassColor"))
        OffsetCog(nameRow._leftRegion, "Name Position", { "bars", "leftTextOffsetX" }, { "bars", "leftTextOffsetY" },
            off, "Threat Meter")
        local valueSwatch = AlternativeTo(StyleSwatch("colors", "rightTextColor", "Value Color"),
            "colors", "rightTextUseClassColor")
        valueSwatch.disabled, valueSwatch.disabledTooltip, valueSwatch.rawTooltip = valueOff, valueTip, valueRaw
        Swatch(nameRow._rightRegion, valueSwatch)
        OffsetCog(nameRow._rightRegion, "Value Position", { "bars", "rightTextOffsetX" }, { "bars", "rightTextOffsetY" },
            valueOff, valueTip, valueRaw)
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  WINDOW & BORDERS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "WINDOW & BORDERS", y);  y = y - h

    local windowBorderOff, windowBorderTip = Needs(function() return IsZero("borders", "windowBorderSize") end,
        "Window Border Size")
    local includeHeader = StyleToggle("borders", "windowBorderIncludeHeader", "Include Header in Border")
    includeHeader.disabled, includeHeader.disabledTooltip = windowBorderOff, windowBorderTip
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        StyleSlider("colors", "bgAlpha", "Background", 0, 1, 0.01),
        Gate(includeHeader)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(bgRow._leftRegion, BlizzOnly(StyleSwatch("colors", { "bgR", "bgG", "bgB" }, "Background Color")))
    end

    local borderValues, borderOrder = EllesmereUI.GetBorderTextureDropdown()
    -- Shadow is drawn behind its surface, and the bars have no layer behind
    -- them, so their list leaves it out (as the Damage Meters bars do).
    local barValues, barOrder = EllesmereUI.GetBorderTextureDropdown()
    barValues.shadow = nil
    for i = #barOrder, 1, -1 do
        if barOrder[i] == "shadow" then table.remove(barOrder, i) end
    end
    local function BorderStyle(window, text)
        local key = window and "windowBorderTexture" or "borderTexture"
        return { type = "dropdown", text = text,
            values = window and borderValues or barValues, order = window and borderOrder or barOrder,
            disabled = off, disabledTooltip = "Threat Meter",
            getValue = function() return GetStyle("borders", key) end,
            setValue = function(v)
                local color = EllesmereUI.GetBorderStyleSelectDefaults(v)
                local size = EllesmereUI.GetBorderDefaultSize(ns.BORDER_KEY, v) or 1
                local patch = { [key] = v }
                if window then
                    patch.windowBorderSize, patch.windowBorderSizePx = size, false
                    patch.windowBorderColor = { r = color.r, g = color.g, b = color.b, a = 1 }
                else
                    patch.borderSize, patch.borderSizePx = size, false
                    patch.borderR, patch.borderG, patch.borderB = color.r, color.g, color.b
                    patch.borderTextureOffset, patch.borderTextureOffsetY = false, false
                    patch.borderTextureShiftX, patch.borderTextureShiftY = 0, 0
                end
                ns.SetStyleValues("borders", patch)
                EllesmereUI:RefreshPage()
            end }
    end
    -- One slider write can change both the size step and its exact pixels; they
    -- land together in one restyle.
    local pending = {}
    local function BorderSize(window, text)
        local stepKey = window and "windowBorderSize" or "borderSize"
        local pxKey = window and "windowBorderSizePx" or "borderSizePx"
        local texKey = window and "windowBorderTexture" or "borderTexture"
        return EllesmereUI.BorderPxSliderCfg({ text = text,
            disabled = off, disabledTooltip = "Threat Meter",
            getStep = function() return GetStyle("borders", stepKey) end,
            setStep = function(v) pending[stepKey] = v end,
            getTex = function() return GetStyle("borders", texKey) end,
            getPx = function() return GetStyle("borders", pxKey) end,
            setPx = function(v) pending[pxKey] = v end,
            apply = function()
                local was = IsZero("borders", stepKey)
                ns.SetStyleValues("borders", pending)
                wipe(pending)
                if IsZero("borders", stepKey) ~= was then EllesmereUI:RefreshPage() end
            end })
    end

    local windowRow
    windowRow, h = W:DualRow(parent, y,
        Gate(BorderStyle(true, "Window Border Style")),
        Gate(BorderSize(true, "Window Border Size"))
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local sc = StyleSwatch("borders", "windowBorderColor", "Window Border Color")
        sc.disabled, sc.disabledTooltip = windowBorderOff, windowBorderTip
        Swatch(windowRow._rightRegion, Gate(sc))
    end

    local barBorderRow
    barBorderRow, h = W:DualRow(parent, y,
        Gate(BorderStyle(false, "Bar Border Style")),
        Gate(BorderSize(false, "Bar Border Size"))
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local sc = StyleSwatch("borders", { "borderR", "borderG", "borderB" }, "Bar Border Color")
        sc.disabled, sc.disabledTooltip = Needs(function() return IsZero("borders", "borderSize") end, "Bar Border Size")
        Swatch(barBorderRow._rightRegion, Gate(sc))
    end

    return math.abs(y)
end
