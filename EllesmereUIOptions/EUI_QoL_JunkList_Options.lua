if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_JunkList_Options.lua
--  Options section for the Junk Items window (registered under EllesmereUIQoL).
-------------------------------------------------------------------------------

if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

local function P()
    local fn = _G._EUI_JunkList_DB
    local d = fn and fn()
    return d and d.profile and d.profile.junkList
end

local function Cfg(key, fallback)
    local p = P()
    if not p or p[key] == nil then return fallback end
    return p[key]
end

local function Set(key, v)
    local p = P()
    if p then p[key] = v end
end

local function Refresh()
    if _G._EUI_JunkList_Apply then _G._EUI_JunkList_Apply() end
end

_G._EUI_BuildJunkListSection = function(parent, yOffset, W, PP)
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "JUNK ITEMS", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable Junk Items Window",
          tooltip = "Shows a small window listing the gray and white stacks in your bags that sell for the least at a vendor. Items with no vendor value list first, unless soulbound. Quest items are never listed.\n\nCtrl + Left Click an item to DELETE it.\nMiddle Click an item to hide it from the list permanently.",
          getValue = function() return Cfg("enabled", false) == true end,
          -- DependentSetValue: the rows below are hidden while the window is off;
          -- the flip forces the full rebuild.
          setValue = EllesmereUI.DependentSetValue(
              function() return Cfg("enabled", false) == true end,
              function(v) Set("enabled", v); Refresh(); EllesmereUI:RefreshPage() end) },
        Cfg("enabled", false) ~= true and EllesmereUI.BlankRowCfg() or
        { type    = "slider",
          text    = "Items Shown",
          min     = 1, max = 6, step = 1, isPercent = false,
          tooltip = "How many of the cheapest stacks to list.",
          getValue = function() return Cfg("itemCount", 4) end,
          setValue = function(v) Set("itemCount", v); Refresh() end }
    ); y = y - h

    if Cfg("enabled", false) == true then
    _, h = W:DualRow(parent, y,
        { type    = "slider",
          text    = "Icon Size",
          min     = 16, max = 64, step = 1, isPercent = false,
          getValue = function() return Cfg("iconSize", 32) end,
          setValue = function(v) Set("iconSize", v); Refresh() end },
        { type    = "slider",
          text    = "Icon Spacing",
          min     = 0, max = 30, step = 1, isPercent = false,
          tooltip = "Horizontal space between icons. Fixed regardless of the prices shown, so raise it if long prices touch their neighbours.",
          getValue = function() return Cfg("iconSpacing", 6) end,
          setValue = function(v) Set("iconSpacing", v); Refresh() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "dropdown",
          text    = "Price Position",
          values  = { bottom = "Below Icon", top = "Above Icon" },
          order   = { "bottom", "top" },
          getValue = function() return Cfg("priceSide", "bottom") end,
          setValue = function(v) Set("priceSide", v); Refresh() end },
        { type    = "toggle",
          text    = "Show Empty Bag Slots",
          tooltip = "Shows your free and total bag slots in the window title, as in Bag Slots - 4/30. When off, the title is hidden.",
          getValue = function() return Cfg("showFreeSlots", false) == true end,
          setValue = function(v) Set("showFreeSlots", v); Refresh() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type       = "labeledButton",
          text       = "Excluded Items",
          buttonText = "Clear",
          width      = 90,
          tooltip    = "Clears the list of items you middle-clicked away, so they can show up in the window again.",
          onClick    = function()
              if _G._EUI_JunkList_ClearExclusions then _G._EUI_JunkList_ClearExclusions() end
          end },
        EllesmereUI.BlankRowCfg()
    ); y = y - h
    end   -- close hidden-while-disabled gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
