if EUI_CLIENT_BLOCKED then return end
local EUI = EllesmereUI
local module = EUI._ModuleNS["EllesmereUIForeverEssentials"]
local ns = module and module.ThreatMeter
if not ns then return end

_G._EUI_BuildThreatMeterPage = function(_, parent, y)
    ns.BarTextures()
    EUI:SetContentHeader(function(header, width)
        local building = true
        local view = ns.CreateSettingsPreview(header, width, function(height)
            if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
                EUI:SetContentHeaderHeightSilent(height)
            end
        end)
        building = false
        return view.previewHeight
    end)
    local W, start = EUI.Widgets, y
    parent._showRowDivider = true
    local function Section(text)
        local _, h = W:SectionHeader(parent, text, y); y = y - h
    end
    local function Row(left, right)
        local row, h = W:DualRow(parent, y, left, right or { type = "label", text = "" }); y = y - h
        if EUI._prebuilding then return end
        for i, cfg in ipairs({ left, right }) do
            local region = i == 1 and row._leftRegion or row._rightRegion
            if cfg.inlineColor then
                local color = cfg.inlineColor
                color.tooltip = color.text
                EUI.BuildInlineSwatches(region, { color })
            end
            if cfg.textOffsets then
                local sliders = {}
                for _, slider in ipairs(cfg.textOffsets) do
                    sliders[#sliders + 1] = { type = "slider", label = slider.text,
                        min = slider.min, max = slider.max, step = slider.step,
                        get = slider.getValue, set = slider.setValue }
                end
                EUI.BuildInlineCog(region, { title = cfg.text .. " Position", rows = sliders,
                    disabled = cfg.disabled })
            end
        end
    end
    local function Decorate(cfg, color, offsets)
        cfg.inlineColor, cfg.textOffsets = color, offsets
        return cfg
    end
    local function Refresh()
        ns.ApplyStyle()
        if EUI.RefreshPage then EUI:RefreshPage() end
    end
    local function ConfigSetting(key, text, kind, options)
        local cfg = { type = kind, text = text,
            getValue = function() return ns.Config()[key] end,
            setValue = function(v)
                ns.Config()[key] = v
                Refresh()
            end }
        for k, v in pairs(options or {}) do cfg[k] = v end
        return cfg
    end
    local function Toggle(key, text)
        return ConfigSetting(key, text, "toggle")
    end
    local function Setting(group, key, text, kind, more)
        local cfg = { type = kind, text = text,
            disabled = function()
                if group == "header" then return not ns.Config().showHeader end
                if key == "rightTextOffsetX" or key == "rightTextOffsetY" or key == "rightTextUseClassColor" then
                    return ns.GetDisplayedValue() == "none"
                end
                return false
            end,
            getValue = function() return ns.GetStyleGroup(group)[key] end,
            setValue = function(v) ns.SetStyleValues(group, { [key] = v }) end }
        for k, v in pairs(more or {}) do cfg[k] = v end
        return cfg
    end
    local function Slider(group, key, text, low, high, step)
        return Setting(group, key, text, "slider", { min = low, max = high, step = step or 1 })
    end
    local function ConfigSlider(key, text, low, high)
        return ConfigSetting(key, text, "slider", { min = low, max = high, step = 1 })
    end
    local function ConfigColor(key, text)
        return { type = "colorpicker", text = text, hasAlpha = false,
            disabled = function()
                local c = ns.Config()
                if key == "pullColor" then return not c.pullBar end
                if key == "playerColor" then return not c.playerColorOn end
                if key == "tankColor" then return not c.tankColorOn end
                return false
            end,
            getValue = function() local c = ns.Config()[key]; return c.r, c.g, c.b end,
            setValue = function(r, g, b) ns.Config()[key] = { r = r, g = g, b = b }; Refresh() end }
    end
    local function Color(group, key, text, extra)
        return { type = "colorpicker", text = text, hasAlpha = false,
            disabled = function()
                if group == "header" then return not ns.Config().showHeader end
                return key == "rightTextColor" and ns.GetDisplayedValue() == "none"
            end,
            getValue = function()
                local values = ns.GetStyleGroup(group)
                if type(key) == "table" then return values[key[1]], values[key[2]], values[key[3]] end
                local c = values[key]; return c.r, c.g, c.b
            end,
            setValue = function(r, g, b)
                local values = {}
                for k, v in pairs(extra or {}) do values[k] = v end
                if type(key) == "table" then values[key[1]], values[key[2]], values[key[3]] = r, g, b
                else values[key] = { r = r, g = g, b = b, a = 1 } end
                ns.SetStyleValues(group, values)
            end }
    end
    local borderValues, borderOrder = EUI.GetBorderTextureDropdown()
    local function BorderStyle(key, text, window)
        return Setting("borders", key, text, "dropdown", {
            values = borderValues, order = borderOrder,
            setValue = function(v)
                local color = EUI.GetBorderStyleSelectDefaults(v)
                local size = EUI.GetBorderDefaultSize("damagemeters", v) or 1
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
            end })
    end
    local function BorderSize(key, exactKey, text)
        local textureKey = key == "windowBorderSize" and "windowBorderTexture" or "borderTexture"
        local function Set(k, v)
            local c = ns.Config()
            c.appearance.borders = c.appearance.borders or {}
            c.appearance.borders[k] = v
        end
        return EUI.BorderPxSliderCfg({ text = text,
            getStep = function() return ns.GetStyleGroup("borders")[key] end,
            setStep = function(v) Set(key, v) end,
            getTex = function() return ns.GetStyleGroup("borders")[textureKey] end,
            getPx = function() return ns.GetStyleGroup("borders")[exactKey] end,
            setPx = function(v) Set(exactKey, v) end,
            apply = Refresh })
    end

    Section("GENERAL")
    Row(Toggle("enabled", "Show Threat Meter"), Toggle("locked", "Lock Position"))
    Row(ConfigSetting("focusEnabled", "Enable Focus Tracking", "toggle", {
        tooltip = "Shows a Target/Focus selector in the meter header. When disabled, always tracks your target. For a friendly unit, tracks the enemy they are targeting.",
        setValue = function(v) ns.SetFocusEnabled(v); Refresh() end }), Toggle("pets", "Include Pets"))
    if EUI.BuildVisibilityRow then
        local _, h = EUI.BuildVisibilityRow(W, parent, y, {
            getStore = ns.Config, legacyKey = "visibility",
            caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
            onChanged = Refresh, onOptionChanged = Refresh,
        }); y = y - h
    end

    Section("AGGRO WARNING")
    local soundValues, soundOrder = EUI.BuildSoundDropdownValues(ns.Sounds())
    local function warningOff() return not ns.Config().warnSound end
    Row(Toggle("warnSound", "Warning Sound"), ConfigSetting("warnSoundKey", "Warning Sound Selection", "dropdown", {
        values = soundValues, order = soundOrder, disabled = warningOff }))
    local warnAt = ConfigSlider("warnAt", "Warn At (%)", 50, 100)
    warnAt.disabled = warningOff
    warnAt.tooltip = "100% means taking aggro. Plays once when crossing the threshold; rearms after dropping below it."
    Row(warnAt, Toggle("warnSkipTank", "Skip Tank Role / Stance"))
    Row({ type = "labeledButton", text = "Test Warning Sound", buttonText = "Play",
        onClick = function() ns.PlaySoundKey(ns.Config().warnSoundKey) end })

    Section("BARS & ICONS")
    Row(ConfigSlider("barHeight", "Bar Height", 12, 32), Toggle("growUp", "Grow Bars Upward"))
    Row(Setting("bars", "barTexture", "Bar Texture", "dropdown", { values = ns.BarTextureNames, order = ns.BarTextureOrder }),
        Setting("colors", "showClassColor", "Class-Colored Bars", "toggle"))
    Row(ConfigSlider("barSpacing", "Bar Spacing", 0, 10),
        Setting("bars", "iconStyle", "Class Icon Style", "dropdown", {
            values = { none = "None", blizzard = "Blizzard", modern = "Modern", pixel = "Pixel", glyph = "Glyph",
                arcade = "Arcade", legend = "Legend", midnight = "Midnight", runic = "Runic" },
            order = { "none", "---", "blizzard", "modern", "pixel", "glyph", "arcade", "legend", "midnight", "runic" } }))

    Section("HEADER")
    Row(Toggle("showHeader", "Show Header"), Slider("header", "hdrHeight", "Header Height", 14, 40))
    Row(Decorate(Slider("header", "hdrFontSize", "Header Text Size", 8, 20), nil, {
            Slider("header", "hdrTextOffX", "Header Text X", -20, 20), Slider("header", "hdrTextOffY", "Header Text Y", -20, 20) }),
        Decorate(Setting("header", "hdrTextUseAccent", "Accent Header Text", "toggle"),
            Color("header", "hdrTextColor", "Header Text Color", { hdrTextUseAccent = false })))
    Row(Decorate(Slider("header", "hdrBgAlpha", "Header Opacity", 0, 1, 0.01), Color("header", "hdrBgColor", "Header Background")),
        Decorate(Slider("header", "hdrBottomBorderSize", "Header Bottom Border", 0, 4), Color("header", "hdrBottomBorderColor", "Header Border Color")))

    Section("BAR COLORS")
    Row(Decorate(Toggle("pullBar", "Pull Aggro Bar"), ConfigColor("pullColor", "Pull Aggro Color")),
        Decorate(Toggle("playerColorOn", "Custom Player Color"), ConfigColor("playerColor", "Player Color")))
    Row(Decorate(Toggle("tankColorOn", "Custom Tank Color"), ConfigColor("tankColor", "Tank Color")),
        Decorate(Setting("colors", "barColorUseAccent", "Accent Bar Color", "toggle", {
            setValue = function(v)
                local values = { barColorUseAccent = v }
                if v then values.showClassColor = false end
                ns.SetStyleValues("colors", values)
            end }),
            Color("colors", "barColor", "Custom Bar Color", { showClassColor = false, barColorUseAccent = false })))
    Row(Slider("colors", "barFillAlpha", "Bar Opacity", 0, 1, 0.01), Slider("colors", "barBgAlpha", "Bar Background Opacity", 0, 1, 0.01))
    Row(Decorate(Setting("colors", "barBgUseClassColor", "Class-Colored Background", "toggle"),
        Color("colors", { "barBgR", "barBgG", "barBgB" }, "Bar Background", { barBgUseClassColor = false })))

    Section("BAR TEXT")
    Row(ConfigSlider("fontSize", "Font Size", 8, 18), { type = "dropdown", text = "Displayed Value",
        tooltip = "Tank %: 100% equals the aggro holder's threat. Pull %: 100% is your personal aggro threshold. Warnings always use Pull %. The Pull Aggro reference shows its threshold value, or 100% when only percentages are displayed.",
        values = ns.DisplayValues, order = ns.DisplayOrder,
        getValue = ns.GetDisplayedValue,
        setValue = function(v) ns.SetDisplayedValue(v); Refresh() end })
    if EUI.BuildFontDropdownData then
        local values, order = EUI.BuildFontDropdownData()
        Row(ConfigSetting("font", "Font", "dropdown", { values = values, order = order }),
            ConfigSetting("outlineMode", "Font Outline", "dropdown", {
            values = { __global = "EUI Global Default", none = "Drop Shadow", outline = "Outline", thick = "Thick Outline" },
            order = { "__global", "none", "outline", "thick" } }))
    end
    Row(Decorate(Setting("colors", "leftTextUseClassColor", "Class-Colored Names", "toggle"),
            Color("colors", "leftTextColor", "Name Color", { leftTextUseClassColor = false }), {
                Slider("bars", "leftTextOffsetX", "Name X Offset", -20, 20), Slider("bars", "leftTextOffsetY", "Name Y Offset", -20, 20) }),
        Decorate(Setting("colors", "rightTextUseClassColor", "Class-Colored Values", "toggle"),
            Color("colors", "rightTextColor", "Value Color", { rightTextUseClassColor = false }), {
                Slider("bars", "rightTextOffsetX", "Value X Offset", -20, 20), Slider("bars", "rightTextOffsetY", "Value Y Offset", -20, 20) }))

    Section("WINDOW & BORDERS")
    Row(Decorate(Slider("colors", "bgAlpha", "Window Opacity", 0, 1, 0.01), Color("colors", { "bgR", "bgG", "bgB" }, "Window Background")),
        Setting("borders", "windowBorderIncludeHeader", "Include Header in Border", "toggle"))
    Row(BorderStyle("windowBorderTexture", "Window Border Style", true),
        Decorate(BorderSize("windowBorderSize", "windowBorderSizePx", "Window Border Size"), Color("borders", "windowBorderColor", "Window Border Color")))
    Row(BorderStyle("borderTexture", "Bar Border Style", false),
        Decorate(BorderSize("borderSize", "borderSizePx", "Bar Border Size"), Color("borders", { "borderR", "borderG", "borderB" }, "Bar Border Color")))
    return start - y
end
