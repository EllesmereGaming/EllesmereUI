if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_GearDurability_Options.lua
--  Options section for the standalone Gear Durability display (registered under
--  EllesmereUIQoL). Embedded on the same page as the BattleRes / Bloodlust
--  trackers via _G._EUI_BuildGearDurabilitySection.
-------------------------------------------------------------------------------

if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

local function DB()
    local fn = _G._EUI_GearDurability_DB
    return fn and fn() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.gearDurability
end

local function Cfg(key, fallback)
    local p = P()
    if not p then return fallback end
    if p[key] == nil then return fallback end
    return p[key]
end

local function Set(key, v)
    local p = P()
    if p then p[key] = v end
end

local function Refresh()
    if _G._EUI_GearDurability_Apply then _G._EUI_GearDurability_Apply() end
    -- Content-sized element: keep the live mover in sync after size changes.
    if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
        EllesmereUI.RepositionBarToMover("EUI_GearDurability")
    end
end

local VIS_VALUES = { ALWAYS = "Always", NEVER = "Never" }
local VIS_ORDER  = { "ALWAYS", "NEVER" }

_G._EUI_BuildGearDurabilitySection = function(parent, yOffset, W, PP)
    local y = yOffset
    local _, h, row

    _, h = W:SectionHeader(parent, "GEAR DURABILITY", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Enable Gear Durability",
          values=VIS_VALUES, order=VIS_ORDER,
          getValue=function() return Cfg("visibility") or "NEVER" end,
          -- DependentSetValue: the rows below Row 1 are hidden while Never;
          -- only the Never <-> shown flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return Cfg("visibility") ~= "NEVER" end,
              function(v)
                  local was = Cfg("visibility") or "NEVER"
                  Set("visibility", v)
                  if was == "NEVER" and v ~= "NEVER" then
                      if _G._EUI_GearDurability_Apply then _G._EUI_GearDurability_Apply() end
                      if _G._EUI_GearDurability_SeedPos then _G._EUI_GearDurability_SeedPos() end
                  end
                  Refresh(); EllesmereUI:RefreshPage()
              end) },
        { type="slider", text="Font Size",
          disabled=function() return Cfg("visibility") == "NEVER" end,
          disabledTooltip="Gear Durability",
          min=8, max=30, step=1, isPercent=false,
          getValue=function() return Cfg("fontSize") or 14 end,
          setValue=function(v) Set("fontSize", v); Refresh() end })
    y = y - h

    -- Rows below are HIDDEN entirely while the display is set to Never (the
    -- dropdown's DependentSetValue forces the rebuild on flips).
    if Cfg("visibility") ~= "NEVER" then
    row, h = W:DualRow(parent, y,
        { type="toggle", text="Show Icon",
          getValue=function() return Cfg("showIcon", true) ~= false end,
          setValue=function(v) Set("showIcon", v); Refresh() end },
        { type="toggle", text="Show Percentage",
          getValue=function() return Cfg("showPercent", true) ~= false end,
          setValue=function(v) Set("showPercent", v); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Dynamic Durability Color",
          tooltip="Colors the readout from white at full durability through to red as it drops, matching the DataBars durability block.",
          getValue=function() return Cfg("dynamicColor", true) ~= false end,
          setValue=function(v) Set("dynamicColor", v); Refresh(); EllesmereUI:RefreshPage() end },
        { type="colorpicker", text="Text Color", hasAlpha=false,
          disabled=function() return Cfg("dynamicColor", true) ~= false end,
          disabledTooltip="This option requires Dynamic Durability Color to be off",
          getValue=function()
              local c = Cfg("color")
              if c then return c.r or 1, c.g or 1, c.b or 1 end
              return 1, 1, 1
          end,
          setValue=function(r, g, b) Set("color", { r = r, g = g, b = b }); Refresh() end })
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Hide at Full Durability",
          tooltip="Hides the display entirely while every equipped item is at 100%.",
          getValue=function() return Cfg("hideAtFull", false) == true end,
          setValue=function(v) Set("hideAtFull", v); Refresh() end },
        { type="label", text="" })
    y = y - h
    end   -- close hidden-while-Never gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
