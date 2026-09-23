if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- the QoL module lists the Travel tab on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_QoL_FlightTimer_Options.lua
--  Builds the "Travel" page inside the Quality of Life module.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

local TEXT_SIDES = { none = "None", left = "Left", center = "Center", right = "Right" }
local TEXT_SIDE_ORDER = { "none", "left", "center", "right" }

_G._EUI_BuildFlightTimerPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PP
    local FT = EllesmereUI._FlightTimer
    local y = yOffset
    local _, h

    local function off()
        return not FT.Get("enabled")
    end
    local function Set(key, v)
        FT.Cfg()[key] = v
        FT.ApplyStyle()
    end

    -- Cog button on a row half, left of whatever that half already holds.
    local function AddCog(rgn, title, rows, cogOff, offTip)
        local _, cogShow = EllesmereUI.BuildCogPopup({ title = title, rows = rows })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(cogOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(offTip))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function Update()
            local isOff = cogOff()
            cogBtn:SetAlpha(isOff and 0.15 or 0.4)
            if isOff then cogBlock:Show() else cogBlock:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(Update)
        Update()
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
          tooltip = "Shows a progress bar with the time left while you ride a flight path. Move and resize it in Unlock Mode.",
          getValue = function() return not off() end,
          setValue = function(v)
              FT.Cfg().enabled = v
              FT.Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "labeledButton", text = "Preview", buttonText = "Show Bar",
          disabled = off,
          disabledTooltip = "Enable Flight Timer",
          onClick = function() FT.Preview() end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "labeledButton", text = "Learned Flight Speed", buttonText = "Reset",
          tooltip = "Flight times start as an estimate and get more accurate after each flight you finish. Reset to start over from the estimate.",
          disabled = function() return FT.Cfg().speed == nil end,
          onClick = function()
              FT.Cfg().speed = nil
              EllesmereUI:RefreshPage()
          end },
        { type = "label", text = "" }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Width", min = 50, max = 800, step = 1,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("width") end,
          setValue = function(v) Set("width", v) end },
        { type = "slider", text = "Height", min = 4, max = 60, step = 1,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("height") end,
          setValue = function(v) Set("height", v) end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local texValues, texOrder = {}, {}
    do
        local t = FT.textures
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(t.names, t.order, nil, t.lookup)
        end
        for _, key in ipairs(t.order) do
            if key ~= "---" then texValues[key] = t.names[key] or key end
            texOrder[#texOrder + 1] = key
        end
    end

    local borderRow
    borderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("borderSize") end,
          setValue = function(v) Set("borderSize", v) end },
        { type = "dropdown", text = "Bar Texture", values = texValues, order = texOrder,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("texture") end,
          setValue = function(v) Set("texture", v) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(borderRow._leftRegion, {
            { tooltip = "Border Color",
              getValue = function() return FT.Get("borderR"), FT.Get("borderG"), FT.Get("borderB"), 1 end,
              setValue = function(r, g, b)
                  local c = FT.Cfg()
                  c.borderR, c.borderG, c.borderB = r, g, b
                  FT.ApplyStyle()
              end },
        }, { disabled = off, disabledTooltip = "Enable Flight Timer" })
    end

    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar fill.",
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("fillOpacity") end,
          setValue = function(v) Set("fillOpacity", v) end },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return math.floor(FT.Get("bgA") * 100 + 0.5) end,
          setValue = function(v) Set("bgA", v / 100) end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(colorRow._leftRegion, {
            { tooltip = "Custom Colored",
              getValue = function()
                  local c = FT.Cfg()
                  if c.fillR then return c.fillR, c.fillG, c.fillB, 1 end
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
        }, { disabled = off, disabledTooltip = "Enable Flight Timer" })
    end

    local textRow
    textRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Destination Text", values = TEXT_SIDES, order = TEXT_SIDE_ORDER,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("destText") end,
          setValue = function(v) Set("destText", v); EllesmereUI:RefreshPage() end },
        { type = "dropdown", text = "Time Text", values = TEXT_SIDES, order = TEXT_SIDE_ORDER,
          disabled = off, disabledTooltip = "Enable Flight Timer",
          getValue = function() return FT.Get("timeText") end,
          setValue = function(v) Set("timeText", v); EllesmereUI:RefreshPage() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        AddCog(textRow._leftRegion, "Destination Text Settings", TextCogRows("dest"),
            function() return off() or FT.Get("destText") == "none" end, "Destination Text")
        AddCog(textRow._rightRegion, "Time Text Settings", TextCogRows("time"),
            function() return off() or FT.Get("timeText") == "none" end, "Time Text")
    end

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
              disabled = off, disabledTooltip = "Enable Flight Timer",
              getValue = function() return FT.Get("font") end,
              setValue = function(v) Set("font", v) end },
            { type = "dropdown", text = "Font Outline", values = outlineValues,
              order = { "__global", "none", "outline", "thick" },
              disabled = off, disabledTooltip = "Enable Flight Timer",
              getValue = function() return FT.Get("outlineMode") end,
              setValue = function(v) Set("outlineMode", v) end }
        );  y = y - h
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Total Time",
          tooltip = "Shows the full flight time next to the time left, for example 1:23 / 4:19.",
          disabled = function() return off() or FT.Get("timeText") == "none" end,
          disabledTooltip = "Time Text",
          getValue = function() return FT.Get("showTotal") end,
          setValue = function(v) FT.Cfg().showTotal = v end },
        { type = "label", text = "" }
    );  y = y - h

    return math.abs(y)
end
