if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Loot_Options.lua
--  Builds the "Loot" page inside the Forever Essentials module.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

_G._EUI_BuildLootFeedPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local LF = EllesmereUI._LootFeed
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    local function off()
        return not LF.Get("enabled")
    end
    local function itemsOff()
        return off() or not LF.Get("items")
    end
    local function noBorder()
        return off() or LF.Get("borderSize") == 0
    end
    -- Switching a source re-registers the feed's events.
    local function Reapply()
        LF.Apply()
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
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  ITEMS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ITEMS", y);  y = y - h

    local qualityValues, qualityOrder = {}, {}
    for q = 0, 5 do
        local key, color = tostring(q), ITEM_QUALITY_COLORS[q]
        local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or key
        qualityValues[key] = color and (color.hex .. label .. "|r") or label
        qualityOrder[q + 1] = key
    end

    _, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Minimum Quality", values = qualityValues, order = qualityOrder,
               tooltip = "Items below this quality are not shown.",
               getValue = function() return tostring(LF.Get("minQuality")) end,
               setValue = function(v) LF.Cfg().minQuality = tonumber(v) end }, nil, nil, itemsOff, "Items"),
        Toggle("showIlvl", "Show Item Level", "Shows the item level of weapons and armor.", nil, itemsOff, "Items")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("showPrice", "Show Vendor Price", "Shows what the looted stack sells for at a vendor.",
            nil, itemsOff, "Items"),
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("width", "Width", 150, 600),
        Slider("rowHeight", "Row Height", 20, 60)
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

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local displayRow
    displayRow, h = W:DualRow(parent, y,
        Bind({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
               tooltip = "Opacity of the row background.",
               getValue = function() return math.floor(LF.Get("bgA") * 100 + 0.5) end,
               setValue = function(v)
                   LF.Cfg().bgA = v / 100
                   LF.ApplyStyle()
               end }),
        Slider("borderSize", "Border Size", 0, 4, "0 hides the border.", function()
            LF.ApplyStyle()
            EllesmereUI:RefreshPage()
        end)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(displayRow._leftRegion, "bg", "Background Color")
        -- Nothing to colour at size 0 (the slider + inline swatch pattern).
        Swatch(displayRow._rightRegion, "border", "Border Color", noBorder,
            function() return off() and "Loot Feed" or "Border Size" end)
    end

    _, h = W:DualRow(parent, y,
        Toggle("qualityBorder", "Quality Borders", "Colors the border of item rows by item quality.", LF.ApplyStyle,
            function() return noBorder() or not LF.Get("items") end,
            function() return off() and "Loot Feed" or LF.Get("borderSize") == 0 and "Border Size" or "Items" end),
        BLANK()
    );  y = y - h

    return math.abs(y)
end
