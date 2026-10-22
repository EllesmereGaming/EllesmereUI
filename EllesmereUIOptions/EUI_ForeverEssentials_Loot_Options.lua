if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Loot_Options.lua
--  Builds the "Loot" page inside the Forever Essentials module: a live
--  preview of the feed in the content header, then its settings.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = EllesmereUI._LootFeed.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._EUI_LootHeaderBuilder = HeaderBuilder

local STYLES = { BOX = "Box", BAR = "Accent Bar", TRAY = "Icon Tray", TOAST = "Loot Toast" }
local STYLE_ORDER = { "BOX", "BAR", "TRAY", "TOAST" }

_G._EUI_BuildLootFeedPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local LF = EllesmereUI._LootFeed
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    EllesmereUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not LF.Get("enabled")
    end
    local function itemsOff()
        return off() or not LF.Get("items")
    end
    -- Auction prices count only while the tracker or an item price shows, and
    -- only with the price addon's API at hand.
    local function auctionSource()
        return EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"].AuctionAPI() ~= nil
    end
    local function pricesUnused()
        return not (LF.Get("tracker") or (LF.Get("items") and LF.Get("showPrice")))
    end
    local function auctionOff()
        return off() or not auctionSource() or pricesUnused()
    end
    local function auctionTip()
        if off() then return "Loot Feed" end
        if not auctionSource() then return "This option requires Auctionator to be loaded." end
        return "This option requires Gold per Hour Tracker or Show Item Price to be enabled."
    end
    local function style()
        return LF.Get("style")
    end
    -- Loot Toast keeps its gold frame.
    local function borderOff()
        return off() or style() == "TOAST"
    end
    local function noBorderColor()
        return borderOff() or LF.Get("borderSize") == 0
    end
    -- Switching a source re-registers the feed's events.
    local function Reapply()
        LF.Apply()
        LF.RefreshPreview()
        EllesmereUI:RefreshPage()
    end
    -- Binds cfg to setting key; apply runs after a change (none: the next row
    -- shown picks it up). Greyed out while the feed is off unless disabled is
    -- given.
    local function Bind(cfg, key, apply, disabled, disabledTooltip)
        cfg.disabled, cfg.disabledTooltip = disabled or off, disabledTooltip or "Loot Feed"
        cfg.getValue = cfg.getValue or function() return LF.Get(key) end
        cfg.setValue = cfg.setValue or function(v)
            LF.Cfg()[key] = v
            if apply then apply() end
        end
        return cfg
    end
    local function Toggle(key, text, tooltip, apply, disabled, disabledTooltip)
        return Bind({ type = "toggle", text = text, tooltip = tooltip }, key, apply, disabled, disabledTooltip)
    end
    local function Slider(key, text, min, max, tooltip, apply)
        return Bind({ type = "slider", text = text, tooltip = tooltip, min = min, max = max, step = 1 },
            key, apply or LF.ApplyStyle)
    end
    -- An inline swatch for the prefix .. "R" / "G" / "B" colour.
    local function Swatch(region, prefix, tooltip, disabled, disabledTooltip)
        EllesmereUI.BuildInlineSwatches(region, { {
            tooltip = tooltip, disabled = disabled, disabledTooltip = disabledTooltip,
            getValue = function() return LF.Get(prefix .. "R"), LF.Get(prefix .. "G"), LF.Get(prefix .. "B"), 1 end,
            setValue = function(r, g, b)
                local c = LF.Cfg()
                c[prefix .. "R"], c[prefix .. "G"], c[prefix .. "B"] = r, g, b
                if prefix == "border" and style() == "BAR" then
                    c.borderTexture = LF.Get("borderTexture") or "solid"
                end
                LF.ApplyStyle()
            end,
        } }, { disabled = off, disabledTooltip = "Loot Feed" })
    end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LOOT FEED", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Loot Feed",
          tooltip = "Shows what you loot and gain as short-lived rows that fade out.",
          getValue = function() return not off() end,
          setValue = function(v)
              LF.Cfg().enabled = v
              Reapply()
          end },
        { type = "labeledButton", text = "Preview", buttonText = "Show Samples",
          tooltip = "Shows a sample row for every enabled source.",
          disabled = off, disabledTooltip = "Loot Feed",
          onClick = function() LF.Preview() end }
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Style", values = STYLES, order = STYLE_ORDER }, "style", function()
            LF.ApplyStyle()
            if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                EllesmereUI.RepositionBarToMover("EUI_LootFeed")
            end
            EllesmereUI:RefreshPage()
        end),
        Bind({ type = "slider", text = "Accent Bar Width", min = 0, max = 6, step = 1,
               tooltip = "0 hides the accent bar." }, "barWidth", LF.ApplyStyle,
            function() return off() or style() == "BOX" or style() == "TOAST" end,
            function() return off() and "Loot Feed" or "Style" end)
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  SOURCES
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "SOURCES", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("items", "Items", "Items you loot or receive.", Reapply),
        Toggle("money", "Money", "Money you loot.", Reapply)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("reputation", "Reputation",
            "Reputation gains and losses, with your progress in the current standing.", Reapply),
        Toggle("currency", "Currencies", "Honor, badges and other currencies, with your total.", Reapply)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("skills", "Skill Ups", "Weapon and profession skill increases.", Reapply),
        Toggle("tracker", "Gold per Hour Tracker", "Pins a row with your gold per hour.",
            function()
                LF.Apply()
                LF.ApplyStyle()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_LootFeed")
                end
                EllesmereUI:RefreshPage()
            end)
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  ITEMS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ITEMS", y);  y = y - h

    local qualityValues, qualityOrder = _G._EUI_ItemQualityValues(Enum.ItemQuality.Legendary)

    _, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Minimum Quality", values = qualityValues, order = qualityOrder,
               tooltip = "Items below this quality are not shown.",
               getValue = function() return tostring(LF.Get("minQuality")) end,
               setValue = function(v)
                   LF.Cfg().minQuality = tonumber(v)
                   LF.RefreshPreview()
               end }, nil, nil, itemsOff, "Items"),
        Toggle("showIlvl", "Show Item Level", "Shows the item level of weapons and armor.", LF.RefreshPreview,
            itemsOff, "Items")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("showPrice", "Show Item Price", "Shows what the looted stack is worth.",
            function()
                LF.RefreshPreview()
                EllesmereUI:RefreshPage()  -- Use Auctionator Prices greys with it
            end, itemsOff, "Items"),
        Toggle("auctionPrices", "Use Auctionator Prices", "Prices items from Auctionator scans.",
            LF.RefreshPreview, auctionOff, auctionTip)
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("width", "Width", 150, 600),
        Slider("rowHeight", "Row Height", 20, 60, "Tile size in the Icon Tray style.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("maxRows", "Max Rows", 1, 12),
        Slider("duration", "Display Time", 1, 30, "Seconds a row stays before it fades out.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Grow Direction",
               values = { UP = "Up", DOWN = "Down" }, order = { "UP", "DOWN" } }, "grow", LF.ApplyStyle),
        Slider("textSize", "Text Size", 8, 24)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("spacing", "Spacing", 0, 30,
            "Space between loot rows or Icon Tray tiles. Loot Toast adds room for its decorative frame."),
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local _, textureValues, textureOrder = EllesmereUI.BuildBarTextureTables()
    local displayRow
    displayRow, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Background Texture", values = textureValues, order = textureOrder },
            "bgTexture", LF.ApplyStyle),
        Bind({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
               tooltip = "Opacity of the row background.",
               getValue = function() return math.floor(LF.Get("bgA") * 100 + 0.5) end,
               setValue = function(v)
                   LF.Cfg().bgA = v / 100
                   LF.ApplyStyle()
               end })
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(displayRow._rightRegion, "bg", "Background Color")
    end

    local borderValues, borderOrder = EllesmereUI.GetBorderTextureDropdown()
    local borderRow
    borderRow, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Border Style", values = borderValues, order = borderOrder,
               tooltip = "Accent Bar applies the border to the icon.",
               getValue = function() return LF.Get("borderTexture") or "solid" end,
               setValue = function(v)
                   local c = LF.Cfg()
                   c.borderTexture = v
                   c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                   c.borderTextureShiftX, c.borderTextureShiftY = nil, nil
                   local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                   c.borderR, c.borderG, c.borderB, c.borderBehind = color.r, color.g, color.b, behind
                   local size = EllesmereUI.GetBorderDefaultSize(nil, v)
                   if size then c.borderSize = size end
                   if c.borderSizePx then c.borderSizePx = false end
                   LF.ApplyStyle()
                   EllesmereUI:RefreshPage(true)
               end }, nil, nil, borderOff, function() return off() and "Loot Feed" or "Style" end),
        EllesmereUI.BorderPxSliderCfg{
            trackWidth = 120, tooltip = "0 hides the border.",
            disabled = borderOff, disabledTooltip = function() return off() and "Loot Feed" or "Style" end,
            getStep = function() return LF.Get("borderSize") end,
            setStep = function(v)
                local c = LF.Cfg()
                c.borderTexture, c.borderSize = LF.Get("borderTexture") or "solid", v
            end,
            getTex = function() return LF.Get("borderTexture") or "solid" end,
            getPx = function() return LF.Get("borderSizePx") end,
            setPx = function(v) LF.Cfg().borderSizePx = v end,
            apply = function() LF.ApplyStyle(); EllesmereUI:RefreshPage() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local offsetX, offsetY = EllesmereUI.BorderOffsetRowCfgs{
            getTex = function() return LF.Get("borderTexture") end,
            getStep = function() return LF.Get("borderSize") end,
            getPx = function() return LF.Get("borderSizePx") end,
            getX = function() return LF.Get("borderTextureOffset") end,
            setX = function(v) LF.Cfg().borderTextureOffset = v end,
            getY = function() return LF.Get("borderTextureOffsetY") end,
            setY = function(v) LF.Cfg().borderTextureOffsetY = v end,
            apply = LF.ApplyStyle,
        }
        local function CogRow(cfg)
            return { type = "slider", label = cfg.text, min = cfg.min, max = cfg.max, step = cfg.step,
                get = cfg.getValue, set = cfg.setValue }
        end
        local function Shift(key, label)
            return { type = "slider", label = label, min = -10, max = 10, step = 1,
                get = function() return LF.Get(key) or 0 end,
                set = function(v) LF.Cfg()[key] = v; LF.ApplyStyle() end }
        end
        EllesmereUI.BuildInlineCog(borderRow._leftRegion, { title = "Border Options",
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function()
                local tex = LF.Get("borderTexture")
                return borderOff() or not tex or tex == "solid" or tex == ""
            end,
            disabledTooltip = "This option requires a textured border.",
            rows = {
                Shift("borderTextureShiftX", "Shift X"), Shift("borderTextureShiftY", "Shift Y"),
                CogRow(offsetX), CogRow(offsetY),
                { type = "toggle", label = "Show Behind",
                  get = function() return LF.Get("borderBehind") end,
                  set = function(v) LF.Cfg().borderBehind = v; LF.ApplyStyle() end },
                { type = "toggle", label = "Separator",
                  tooltip = "Adds a matching divider beside the icon (Box) or the accent bar (Icon Tray).",
                  hidden = function() return style() ~= "BOX" and style() ~= "TRAY" end,
                  disabled = function()
                      return LF.Get("borderSize") == 0 or (style() == "TRAY" and LF.Get("barWidth") == 0)
                          or not EllesmereUI.GetBorderCompanion(LF.Get("borderTexture"), "sepV")
                  end,
                  disabledTooltip = function()
                      if style() == "TRAY" and LF.Get("barWidth") == 0 then return "Accent Bar Width" end
                      return "This option requires a Pixels or Pixels Textured border above size 0."
                  end,
                  get = function() return LF.Get("separator") end,
                  set = function(v) LF.Cfg().separator = v; LF.ApplyStyle() end },
            } })
        Swatch(borderRow._rightRegion, "border", "Border Color", noBorderColor,
            function()
                if off() then return "Loot Feed" end
                if style() == "TOAST" then return "Style" end
                return "Border Size"
            end)
    end

    _, h = W:DualRow(parent, y,
        Toggle("qualityBorder", "Quality Borders", "Colors item rows by item quality.", LF.ApplyStyle,
            function()
                if off() or not LF.Get("items") then return true end
                return style() ~= "BAR" and style() ~= "TOAST" and LF.Get("borderSize") == 0
            end,
            function() return off() and "Loot Feed" or not LF.Get("items") and "Items" or "Border Size" end),
        BLANK()
    );  y = y - h

    return math.abs(y)
end
