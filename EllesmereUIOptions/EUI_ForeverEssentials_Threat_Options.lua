if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Threat_Options.lua
--  Builds the "Threat" page inside the Forever Essentials module.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

_G._EUI_BuildThreatMeterPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local TM = EllesmereUI._ThreatMeter
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    local function off()
        return not TM.Get("enabled")
    end
    local function Set(key, v)
        TM.Cfg()[key] = v
        TM.ApplyStyle()
    end
    local function SetAndRefresh(key, v)
        Set(key, v)
        EllesmereUI:RefreshPage()
    end
    local function Swatch(region, tooltip, prefix, disabled, disabledTooltip)
        EllesmereUI.BuildInlineSwatches(region, {
            { tooltip = tooltip,
              disabled = disabled, disabledTooltip = disabledTooltip,
              getValue = function() return TM.Get(prefix .. "R"), TM.Get(prefix .. "G"), TM.Get(prefix .. "B"), 1 end,
              setValue = function(r, g, b)
                  local c = TM.Cfg()
                  c[prefix .. "R"], c[prefix .. "G"], c[prefix .. "B"] = r, g, b
                  TM.ApplyStyle()
              end },
        }, { disabled = off, disabledTooltip = "Threat Meter" })
    end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "THREAT METER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Threat Meter",
          tooltip = "Shows everyone's threat on your target, highest first. With a friendly target, it shows the threat on what they are fighting.",
          getValue = function() return not off() end,
          setValue = function(v)
              TM.Cfg().enabled = v
              TM.Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "labeledButton", text = "Preview", buttonText = "Show Bars",
          disabled = off,
          disabledTooltip = "Threat Meter",
          onClick = function() TM.Preview() end }
    );  y = y - h

    local pullRow
    pullRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Pull Aggro Bar",
          tooltip = "An extra bar showing how much threat takes aggro from the tank.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("pullBar") end,
          setValue = function(v) SetAndRefresh("pullBar", v) end },
        { type = "toggle", text = "Ignore Pets",
          tooltip = "Leaves pets out of the list.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("ignorePets") end,
          setValue = function(v) Set("ignorePets", v) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(pullRow._leftRegion, "Pull Aggro Bar Color", "pull",
            function() return off() or not TM.Get("pullBar") end, "Pull Aggro Bar")
    end

    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = function() return TM.Cfg() end,
          legacyKey = "visibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
          disabledFn = off, disabledTooltip = "Threat Meter",
          onChanged = function() EllesmereUI.RequestVisibilityUpdate() end,
          onOptionChanged = function() EllesmereUI.RequestVisibilityUpdate() end });  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  WARNING
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "WARNING", y);  y = y - h

    local function warnOff()
        return off() or not TM.Get("warnSound")
    end
    local sndValues, sndOrder = EllesmereUI.BuildSoundDropdownValues(TM.Sounds())
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Warning Sound",
          tooltip = "Plays once when your threat climbs past the threshold, and again only after it has dropped back below.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("warnSound") end,
          setValue = function(v) SetAndRefresh("warnSound", v) end },
        { type = "dropdown", text = "Sound", values = sndValues, order = sndOrder,
          disabled = warnOff, disabledTooltip = "Warning Sound",
          getValue = function() return TM.Get("warnSoundKey") end,
          setValue = function(v) Set("warnSoundKey", v) end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Warn At (%)", min = 50, max = 100, step = 1,
          tooltip = "100% is where you pull aggro.",
          disabled = warnOff, disabledTooltip = "Warning Sound",
          getValue = function() return TM.Get("warnAt") end,
          setValue = function(v) Set("warnAt", v) end },
        { type = "toggle", text = "Not While Tanking",
          tooltip = "No warning while you have the tank role, or are in Bear Form or Defensive Stance.",
          disabled = warnOff, disabledTooltip = "Warning Sound",
          getValue = function() return TM.Get("warnSkipTank") end,
          setValue = function(v) Set("warnSkipTank", v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Width", min = 80, max = 500, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("width") end,
          setValue = function(v) Set("width", v) end },
        { type = "slider", text = "Bar Height", min = 8, max = 40, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("barHeight") end,
          setValue = function(v) Set("barHeight", v) end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Max Bars", min = 1, max = 40, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("maxBars") end,
          setValue = function(v) Set("maxBars", v) end },
        { type = "slider", text = "Bar Spacing", min = 0, max = 10, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("spacing") end,
          setValue = function(v) Set("spacing", v) end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Header",
          tooltip = "A title row with the name of the mob whose threat is shown.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("showHeader") end,
          setValue = function(v) Set("showHeader", v) end },
        { type = "toggle", text = "Grow Upward",
          tooltip = "Stacks the bars upward from the bottom edge instead of down from the top.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("growUp") end,
          setValue = function(v) Set("growUp", v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local texValues, texOrder = {}, {}
    do
        local t = TM.textures
        EllesmereUI.AppendSharedMediaTextures(t.names, t.order, nil, t.lookup)
        for _, key in ipairs(t.order) do
            if key ~= "---" then texValues[key] = t.names[key] or key end
            texOrder[#texOrder + 1] = key
        end
    end

    local borderRow
    borderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("borderSize") end,
          setValue = function(v) SetAndRefresh("borderSize", v) end },
        { type = "dropdown", text = "Bar Texture", values = texValues, order = texOrder,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("texture") end,
          setValue = function(v) Set("texture", v) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        -- Nothing to colour at size 0 (the slider + inline swatch pattern).
        Swatch(borderRow._leftRegion, "Border Color", "border",
            function() return off() or TM.Get("borderSize") == 0 end, "Border Size")
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Bar Opacity", min = 0, max = 100, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("barOpacity") end,
          setValue = function(v) Set("barOpacity", v) end },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return math.floor(TM.Get("bgA") * 100 + 0.5) end,
          setValue = function(v) Set("bgA", v / 100) end }
    );  y = y - h

    do
        local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
        local outlineValues = {
            ["__global"] = { text = "EUI Global Default" },
            ["none"]     = { text = "Drop Shadow" },
            ["outline"]  = { text = "Outline" },
            ["thick"]    = { text = "Thick Outline" },
        }
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return TM.Get("font") end,
              setValue = function(v) Set("font", v) end },
            { type = "dropdown", text = "Font Outline", values = outlineValues,
              order = { "__global", "none", "outline", "thick" },
              disabled = off, disabledTooltip = "Threat Meter",
              getValue = function() return TM.Get("outlineMode") end,
              setValue = function(v) Set("outlineMode", v) end }
        );  y = y - h
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("textSize") end,
          setValue = function(v) Set("textSize", v) end },
        { type = "toggle", text = "Show Threat Value",
          tooltip = "The threat number on each bar, for example 12.3k.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("showValue") end,
          setValue = function(v) Set("showValue", v) end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Threat Percent",
          tooltip = "How close each player is to pulling aggro. 100% takes it.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("showPercent") end,
          setValue = function(v) Set("showPercent", v) end },
        { type = "label", text = "" }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  COLORS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "COLORS", y);  y = y - h

    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Custom Player Color",
          tooltip = "Your own bar in a fixed color instead of your class color.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("playerColorOn") end,
          setValue = function(v) SetAndRefresh("playerColorOn", v) end },
        { type = "toggle", text = "Custom Tank Color",
          tooltip = "The bar of whoever holds aggro in a fixed color instead of their class color.",
          disabled = off, disabledTooltip = "Threat Meter",
          getValue = function() return TM.Get("tankColorOn") end,
          setValue = function(v) SetAndRefresh("tankColorOn", v) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(colorRow._leftRegion, "Player Color", "player",
            function() return off() or not TM.Get("playerColorOn") end, "Custom Player Color")
        Swatch(colorRow._rightRegion, "Tank Color", "tank",
            function() return off() or not TM.Get("tankColorOn") end, "Custom Tank Color")
    end

    return math.abs(y)
end
