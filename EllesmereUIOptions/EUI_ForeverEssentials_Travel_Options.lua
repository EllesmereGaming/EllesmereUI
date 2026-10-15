if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Travel_Options.lua
--  Builds the "Travel" page inside the Forever Essentials module: a live
--  preview of the flight timer in the content header, then its settings.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = EllesmereUI._FlightTimer.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._EUI_TravelHeaderBuilder = HeaderBuilder

_G._EUI_BuildFlightTimerPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local FT = EllesmereUI._FlightTimer
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    EllesmereUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not FT.Get("enabled")
    end
    local function Set(key, v)
        FT.Cfg()[key] = v
        FT.ApplyStyle()
    end

    local function TextCogRows(prefix)
        return {
            { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
              get = function() return FT.Get(prefix .. "Size") end,
              set = function(v) Set(prefix .. "Size", v) end },
            { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
              get = function() return FT.Get(prefix .. "X") end,
              set = function(v) Set(prefix .. "X", v) end },
            { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
              get = function() return FT.Get(prefix .. "Y") end,
              set = function(v) Set(prefix .. "Y", v) end },
        }
    end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "FLIGHT TIMER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Flight Timer",
          tooltip = "Shows a bar with the time left while you ride a flight path.",
          getValue = function() return not off() end,
          setValue = function(v)
              FT.Cfg().enabled = v
              FT.Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Fade In/Out",
          tooltip = "Fades the timer in at takeoff and out on landing.",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("fade") end,
          setValue = function(v) FT.Cfg().fade = v end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Width", min = 50, max = 800, step = 1,
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("width") end,
          setValue = function(v) Set("width", v) end },
        -- The track's own key (trackHeight), not the retired bar's height.
        { type = "slider", text = "Height", min = 1, max = 30, step = 1,
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("trackHeight") end,
          setValue = function(v) Set("trackHeight", v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local texValues, texOrder = {}, {}
    do
        local t = FT.textures
        EllesmereUI.AppendSharedMediaTextures(t.names, t.order, nil, t.lookup)
        for _, key in ipairs(t.order) do
            if key ~= "---" then texValues[key] = t.names[key] or key end
            texOrder[#texOrder + 1] = key
        end
    end

    local borderRow
    borderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("borderSize") end,
          setValue = function(v) Set("borderSize", v); EllesmereUI:RefreshPage() end },
        { type = "dropdown", text = "Bar Texture", values = texValues, order = texOrder,
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("texture") end,
          setValue = function(v) Set("texture", v) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(borderRow._leftRegion, {
            { tooltip = "Border Color",
              -- Nothing to colour at size 0 (the slider + inline swatch pattern).
              disabled = function() return off() or FT.Get("borderSize") == 0 end,
              disabledTooltip = function() return off() and "Flight Timer" or "Border Size" end,
              getValue = function() return FT.Get("borderR"), FT.Get("borderG"), FT.Get("borderB"), 1 end,
              setValue = function(r, g, b)
                  local c = FT.Cfg()
                  c.borderR, c.borderG, c.borderB = r, g, b
                  FT.ApplyStyle()
              end },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar fill.",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("fillOpacity") end,
          setValue = function(v) Set("fillOpacity", v) end },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return math.floor(FT.Get("bgA") * 100 + 0.5) end,
          setValue = function(v) Set("bgA", v / 100) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(colorRow._leftRegion, {
            { tooltip = "Custom Colored",
              getValue = function()
                  local fr = FT.Get("fillR")
                  if fr then return fr, FT.Get("fillG"), FT.Get("fillB"), 1 end
                  local EG = EllesmereUI.ELLESMERE_GREEN
                  return EG.r, EG.g, EG.b, 1
              end,
              setValue = function(r, g, b)
                  local c = FT.Cfg()
                  c.fillR, c.fillG, c.fillB = r, g, b
                  c.classColored = false
                  FT.ApplyStyle(); EllesmereUI:RefreshPage()
              end,
              onClick = function(self)
                  if FT.Get("classColored") then
                      Set("classColored", false); EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function() return FT.Get("classColored") and 0.3 or 1 end },
            { tooltip = "Class Colored",
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                  if cc then return cc.r, cc.g, cc.b, 1 end
                  return 1, 1, 1, 1
              end,
              setValue = function() end,
              onClick = function()
                  Set("classColored", true); EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function() return FT.Get("classColored") and 1 or 0.3 end },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    local textRow
    textRow, h = W:DualRow(parent, y,
        -- "none" hides; nil falls back to the shown default.
        { type = "toggle", text = "Show Names",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("destText") ~= "none" end,
          setValue = function(v) Set("destText", not v and "none" or nil); EllesmereUI:RefreshPage() end },
        { type = "toggle", text = "Show Time",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("timeText") ~= "none" end,
          setValue = function(v) Set("timeText", not v and "none" or nil); EllesmereUI:RefreshPage() end }
    );  y = y - h
    EllesmereUI.BuildInlineCog(textRow._leftRegion, { title = "Name Text Settings", rows = TextCogRows("dest"),
        icon = EllesmereUI.DIRECTIONS_ICON, gap = 9, disabledTooltip = "Show Names",
        disabled = function() return off() or FT.Get("destText") == "none" end })
    EllesmereUI.BuildInlineCog(textRow._rightRegion, { title = "Time Text Settings", rows = TextCogRows("time"),
        icon = EllesmereUI.DIRECTIONS_ICON, gap = 9, disabledTooltip = "Show Time",
        disabled = function() return off() or FT.Get("timeText") == "none" end })

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Total Time",
          tooltip = "Shows the full flight time next to the time left, for example 1:23 / 4:19.",
          disabled = function() return off() or FT.Get("timeText") == "none" end,
          disabledTooltip = "Show Time",
          getValue = function() return FT.Get("showTotal") end,
          setValue = function(v) FT.Cfg().showTotal = v end },
        { type = "toggle", text = "Early Exit Button",
          tooltip = "Shows a button next to the bar that lands you at the next flight point.",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("earlyExit") end,
          setValue = function(v) Set("earlyExit", v) end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show End Caps",
          tooltip = "The dots at the two ends of the track.",
          disabled = off, disabledTooltip = "Flight Timer",
          getValue = function() return FT.Get("showEndCaps") end,
          setValue = function(v) Set("showEndCaps", v) end },
        EllesmereUI.BlankRowCfg()
    );  y = y - h

    return math.abs(y)
end
