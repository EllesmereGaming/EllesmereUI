if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ShoppingList_Options.lua
--  Registers the Shopping List sidebar addon with two tabs:
--    * General -- the module switch, visibility and every feature
--    * Window  -- a live preview in the content header, then the window's
--                 look (the Damage Meters window's controls)
--  Reads go through the module's Get (saved value, else the default).
-------------------------------------------------------------------------------
-- Page names are DEEP-LINK IDENTIFIERS: every NavigateToElementSettings tuple
-- carries them as strings and fails SILENTLY on a mismatch.
local ns = EllesmereUI._ModuleNS["EllesmereUIShoppingList"]
if not ns then return end  -- module disabled: no options page

local PAGE_GENERAL = "General"
local PAGE_WINDOW = "Window"
local DIS = "Shopping List"  -- the disabled rows' "requires" tooltip

local COLOR_MODES = { accent = "Accent Color", custom = "Custom Color" }
local COLOR_MODE_ORDER = { "accent", "custom" }
local ICON_STYLES = { none = "None", item = "Item Icon" }
local ICON_STYLE_ORDER = { "none", "item" }
local NUMBER_FORMATS = { slash = "6/10", spaced = "6 / 10", missing = "4 missing", percent = "60%" }
local NUMBER_FORMAT_ORDER = { "slash", "spaced", "missing", "percent" }
local QTY_FORMATS = { x = "x4", plain = "4" }
local QTY_FORMAT_ORDER = { "x", "plain" }
local REAGENT_SORTS = { missing = "Missing First", name = "Name", recipe = "Recipe Order" }
local REAGENT_SORT_ORDER = { "missing", "name", "recipe" }

-- The preview surface in the content header (Window page). Exported so the
-- module's getHeaderBuilder can hand it back when the page cache outlives it.
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

-------------------------------------------------------------------------------
--  Row helpers shared by both pages.
-------------------------------------------------------------------------------
local Get = ns.Get

local function off() return not Get("enabled") end

-- The "requires" tooltip of a control that also waits on a feature toggle:
-- the module while it is off, else that toggle.
local function Needs(label)
    return function() return off() and DIS or label end
end

-- Style writes (repaint only), and feature writes (switch features on/off).
local function Set(key, v)
    ns.Set(key, v)
    ns.ApplyStyle()
end
local function SetFeature(key, v)
    ns.Set(key, v)
    ns.Apply()
end

local function Toggle(key, text, tooltip, setValue)
    return { type = "toggle", text = text, tooltip = tooltip,
        disabled = off, disabledTooltip = DIS,
        getValue = function() return Get(key) == true end,
        setValue = setValue or function(v) Set(key, v) end }
end
local function FeatureToggle(key, text, tooltip)
    return Toggle(key, text, tooltip, function(v)
        SetFeature(key, v)
        EllesmereUI:RefreshPage()
    end)
end
local function Slider(key, text, low, high, step, extra)
    local cfg = { type = "slider", text = text, min = low, max = high, step = step or 1,
        disabled = off, disabledTooltip = DIS,
        getValue = function() return Get(key) end,
        setValue = function(v) Set(key, v) end }
    if extra then for k, v in pairs(extra) do cfg[k] = v end end
    return cfg
end
local function Dropdown(key, text, values, order, setValue)
    return { type = "dropdown", text = text, values = values, order = order,
        disabled = off, disabledTooltip = DIS,
        getValue = function() return Get(key) end,
        setValue = setValue or function(v) Set(key, v) end }
end

-- Inline swatches. A saved colour table may be shared with the defaults, so
-- every write stores a new one.
local function ColorSwatch(key, tooltip, hasAlpha)
    return { tooltip = tooltip, hasAlpha = hasAlpha, disabled = off, disabledTooltip = DIS,
        getValue = function()
            local c = Get(key)
            return c.r, c.g, c.b, c.a or 1
        end,
        setValue = function(r, g, b, a)
            Set(key, { r = r, g = g, b = b, a = hasAlpha and (a or 1) or nil })
        end }
end
local function RGBSwatch(kr, kg, kb, tooltip, ka)
    return { tooltip = tooltip, hasAlpha = ka ~= nil, disabled = off, disabledTooltip = DIS,
        getValue = function() return Get(kr), Get(kg), Get(kb), ka and Get(ka) or 1 end,
        setValue = function(r, g, b, a)
            ns.Set(kr, r); ns.Set(kg, g); ns.Set(kb, b)
            if ka then ns.Set(ka, a or 1) end
            ns.ApplyStyle()
        end }
end
-- The custom alternative to an accent colour: dimmed while the accent is in
-- use, and its first click switches to the custom colour.
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
local function AccentOrCustom(region, flagKey, colorKey, label)
    local accent = { tooltip = "Accent Color", disabled = off, disabledTooltip = DIS,
        getValue = function() return EllesmereUI.ResolveActiveAccent() end,
        setValue = function() end,
        refreshAlpha = function() return Get(flagKey) and 1 or 0.3 end,
        onClick = function()
            Set(flagKey, true)
            EllesmereUI:RefreshPage()
        end }
    local custom = Alternative(ColorSwatch(colorKey, label or "Custom Color"),
        function() return not Get(flagKey) end,
        function() Set(flagKey, false) end)
    EllesmereUI.BuildInlineSwatches(region, { accent, custom })
end
local function Swatch(region, sc)
    EllesmereUI.BuildInlineSwatches(region, { sc })
end
local function OffsetCog(region, title, keyX, keyY)
    EllesmereUI.BuildInlineCog(region, {
        title = title, icon = EllesmereUI.DIRECTIONS_ICON,
        disabled = off, disabledTooltip = DIS,
        rows = {
            { type = "slider", label = "X Offset", min = -20, max = 20, step = 1,
              get = function() return Get(keyX) end,
              set = function(v) Set(keyX, v) end },
            { type = "slider", label = "Y Offset", min = -20, max = 20, step = 1,
              get = function() return Get(keyY) end,
              set = function(v) Set(keyY, v) end },
        },
    })
end

-------------------------------------------------------------------------------
--  General page
-------------------------------------------------------------------------------
local function BuildGeneralPage(_, parent, yOffset)
    local W = EllesmereUI.Widgets
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { leftCfg = { type = "toggle", text = "Enable Shopping List",
              tooltip = "Track recipes from the profession window and see the reagents they need against what you have.",
              getValue = function() return not off() end,
              setValue = function(v)
                  ns.Set("enabled", v)
                  ns.Apply()
                  EllesmereUI:RefreshPage()
              end },
          getStore = ns.P,
          legacyKey = "visibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true },
          disabledFn = off, disabledTooltip = DIS,
          onChanged = EllesmereUI.RequestVisibilityUpdate,
          onOptionChanged = EllesmereUI.RequestVisibilityUpdate });  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("locked", "Lock Position", "No dragging or resizing. Unlock Mode can still place the window."),
        Toggle("hideWhenEmpty", "Hide When Empty", "Hide the window while nothing is tracked.",
            function(v) Set("hideWhenEmpty", v); if ns.RefreshWindow then ns.RefreshWindow() end end)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("showWithProfession", "Show With Profession Window",
            "Show the list while a profession window is open, whatever the rules above say.",
            function(v) Set("showWithProfession", v); if ns.RefreshWindow then ns.RefreshWindow() end end),
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  TRACKING
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TRACKING", y);  y = y - h

    local row
    row, h = W:DualRow(parent, y,
        FeatureToggle("trackButton", "Quantity Box in Profession Window",
            "A count box beside the recipe in the profession window. With Blizzard's Track Recipe not used, the Track Recipe checkbox tracks in this list only and an Add button appears. The count is a number of crafts; every craft takes one off."),
        FeatureToggle("useBlizzardTrack", "Use Blizzard's Track Recipe",
            "Blizzard's Track Recipe checkbox is the list's one tracking method: ticking it adds the recipe with the box's quantity, unticking removes it, and both stay the same set (tracked recipes also show in the objective tracker).")
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Quantity Box",
            disabled = function() return off() or not Get("trackButton") end,
            disabledTooltip = Needs("Quantity Box in Profession Window"),
            rows = {
                { type = "slider", label = "Default Quantity", min = 1, max = 20, step = 1,
                  get = function() return Get("defaultQty") end,
                  set = function(v) ns.Set("defaultQty", v) end },
            },
        })
    end

    _, h = W:DualRow(parent, y,
        Dropdown("reagentSort", "Reagent Order", REAGENT_SORTS, REAGENT_SORT_ORDER, function(v)
            SetFeature("reagentSort", v)
        end),
        Toggle("hideCompleted", "Hide Completed Reagents", "Reagents you have enough of leave the list.",
            function(v) SetFeature("hideCompleted", v) end)
    );  y = y - h

    -- Last in the section: its right slot is blank on WoW Forever.
    row, h = W:DualRow(parent, y,
        FeatureToggle("subCrafts", "Sub-Crafts",
            "Marks reagents you can craft yourself (an anvil) and offers to track their recipe for what is missing. Learned from each profession window you open."),
        -- Retail only: WoW Forever has no warband bank to count.
        EllesmereUI.IS_FOREVER and BLANK() or Toggle("countWarbandBank", "Count Warband Bank",
            "Count the warband bank toward what you have, next to your bags and bank.",
            function(v) SetFeature("countWarbandBank", v) end)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Sub-Crafts",
            disabled = function() return off() or not Get("subCrafts") end,
            disabledTooltip = Needs("Sub-Crafts"),
            rows = {
                { type = "toggle", label = "Track Automatically",
                  tooltip = "Tracking a recipe also tracks the recipes of its reagents you can craft, for what you are missing (one level deep).",
                  get = function() return Get("autoTrackSubCrafts") == true end,
                  set = function(v) ns.Set("autoTrackSubCrafts", v) end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  COOLDOWNS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "COOLDOWNS", y);  y = y - h

    row, h = W:DualRow(parent, y,
        FeatureToggle("cooldowns", "Recipe Cooldowns",
            "Remembers recipes with a cooldown (transmutes and the like) once you have seen them on cooldown in the profession window, and lists when each is ready."),
        (function()
            local cfg = Toggle("cooldownChat", "Chat Reminder When Ready", "A chat line (and the sound, if one is picked) when a remembered cooldown is ready.",
                function(v) ns.Set("cooldownChat", v); EllesmereUI:RefreshPage() end)
            cfg.disabled = function() return off() or not Get("cooldowns") end
            cfg.disabledTooltip = Needs("Recipe Cooldowns")
            return cfg
        end)()
    );  y = y - h
    if not EllesmereUI._prebuilding and ns.Sounds then
        local sndValues, sndOrder = EllesmereUI.BuildSoundDropdownValues(ns.Sounds())
        EllesmereUI.BuildInlineCog(row._rightRegion, {
            title = "Reminder",
            disabled = function() return off() or not Get("cooldowns") or not Get("cooldownChat") end,
            disabledTooltip = function()
                if off() then return DIS end
                return Get("cooldowns") and "Chat Reminder When Ready" or "Recipe Cooldowns"
            end,
            rows = {
                { type = "dropdown", label = "Sound", values = sndValues, order = sndOrder,
                  get = function() return Get("cooldownSound") end,
                  set = function(v)
                      ns.Set("cooldownSound", v)
                      ns.PlaySoundKey(v)
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  VENDOR
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "VENDOR", y);  y = y - h

    row, h = W:DualRow(parent, y,
        FeatureToggle("vendorButtons", "Track Button on Merchant Items",
            "A + on each merchant item: track it as a vendor item, with its price."),
        FeatureToggle("vendorHighlight", "Highlight Needed Items",
            "Outlines the merchant items your list still needs (missing reagents and vendor items).")
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local sc = ColorSwatch("vendorHighlightColor", "Highlight Color")
        sc.disabled = function() return off() or not Get("vendorHighlight") end
        sc.disabledTooltip = Needs("Highlight Needed Items")
        Swatch(row._rightRegion, sc)
    end

    row, h = W:DualRow(parent, y,
        FeatureToggle("buyButton", "Buy Needed Button",
            "A button in the merchant window that buys what the list still needs from that merchant. Nothing is bought without a click."),
        Toggle("costInHeader", "Show List Cost in Title",
            "The gold the list still costs (vendor items, and reagents a merchant was seen selling) next to the title.",
            function(v) Set("costInHeader", v) end)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Buy Needed",
            disabled = function() return off() or not Get("buyButton") end,
            disabledTooltip = Needs("Buy Needed Button"),
            rows = {
                { type = "slider", label = "Confirm Above (gold)", min = 0, max = 500, step = 5,
                  get = function() return Get("buyConfirmGold") end,
                  set = function(v) ns.Set("buyConfirmGold", v) end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  TOOLTIPS & AUCTION HOUSE
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TOOLTIPS & AUCTION HOUSE", y);  y = y - h

    _, h = W:DualRow(parent, y,
        FeatureToggle("tooltipLine", "Shopping List Line on Item Tooltips",
            "Adds \"Shopping List: have / need\" to the tooltip of any item the list needs."),
        FeatureToggle("ahButton", "Auction House Search Button",
            "A button on the Auction House search bar: each click searches the next missing reagent, right-click picks one. Search only - nothing is posted or bought.")
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  PROFESSION WINDOW
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "PROFESSION WINDOW", y);  y = y - h

    _, h = W:DualRow(parent, y,
        FeatureToggle("toolButtons", "Profession Tool Buttons",
            "Click-to-cast buttons beside the profession window for the tools you know (Cooking: Basic Campfire). Placed out of combat."),
        FeatureToggle("skillUpColor", "Skill-Up Color",
            "The selected recipe's chance to raise your skill, in its difficulty color, as the game reports it.")
    );  y = y - h

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Window page
-------------------------------------------------------------------------------
local function BuildWindowPage(_, parent, yOffset)
    local W = EllesmereUI.Widgets
    local BLANK = EllesmereUI.BlankRowCfg
    local y = yOffset
    local _, h, row
    parent._showRowDivider = true
    ns.BarTextures()
    EllesmereUI:SetContentHeader(HeaderBuilder)

    local borderValues, borderOrder = EllesmereUI.GetBorderTextureDropdown()
    -- Shadow is drawn behind its surface and the bars have no layer behind
    -- them (the Damage Meters bars leave it out too).
    local barValues, barOrder = EllesmereUI.GetBorderTextureDropdown()
    barValues.shadow = nil
    for i = #barOrder, 1, -1 do
        if barOrder[i] == "shadow" then table.remove(barOrder, i) end
    end
    local function BorderStyle(window, text)
        local key = window and "windowBorderTexture" or "borderTexture"
        return { type = "dropdown", text = text,
            values = window and borderValues or barValues, order = window and borderOrder or barOrder,
            disabled = off, disabledTooltip = DIS,
            getValue = function() return Get(key) end,
            setValue = function(v)
                local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                local size = EllesmereUI.GetBorderDefaultSize(ns.BORDER_KEY, v) or 1
                ns.Set(key, v)
                if window then
                    ns.Set("windowBorderSize", size)
                    ns.Set("windowBorderSizePx", false)
                    ns.Set("windowBorderColor", { r = color.r, g = color.g, b = color.b, a = 1 })
                    ns.Set("windowBorderBehind", behind == true)
                else
                    ns.Set("borderSize", size)
                    ns.Set("borderSizePx", false)
                    ns.Set("borderR", color.r); ns.Set("borderG", color.g); ns.Set("borderB", color.b)
                end
                ns.ApplyStyle()
                EllesmereUI:RefreshPage()
            end }
    end
    local function BorderSize(window, text)
        local stepKey = window and "windowBorderSize" or "borderSize"
        local pxKey = window and "windowBorderSizePx" or "borderSizePx"
        local texKey = window and "windowBorderTexture" or "borderTexture"
        return EllesmereUI.BorderPxSliderCfg({ text = text,
            disabled = off, disabledTooltip = DIS,
            getStep = function() return Get(stepKey) end,
            setStep = function(v) ns.Set(stepKey, v) end,
            getTex = function() return Get(texKey) end,
            getPx = function() return Get(pxKey) end,
            setPx = function(v) ns.Set(pxKey, v) end,
            apply = function() ns.ApplyStyle() end })
    end

    ---------------------------------------------------------------------------
    --  WINDOW
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "WINDOW", y);  y = y - h

    row, h = W:DualRow(parent, y, BorderStyle(true, "Border Style"), BorderSize(true, "Border Size"));  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options", icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = off, disabledTooltip = DIS,
            rows = {
                { type = "toggle", label = "Include Header",
                  get = function() return Get("windowBorderIncludeHeader") ~= false end,
                  set = function(v) Set("windowBorderIncludeHeader", v) end },
                { type = "toggle", label = "Show Behind",
                  get = function() return Get("windowBorderBehind") == true end,
                  set = function(v) Set("windowBorderBehind", v) end },
            },
        })
        Swatch(row._rightRegion, ColorSwatch("windowBorderColor", "Border Color", true))
    end

    row, h = W:DualRow(parent, y,
        Slider("bgAlpha", "Background Opacity", 0, 1, 0.01),
        { type = "input", text = "Title", inputWidth = 160, inputStyle = "popup",
          placeholder = "Shopping List",
          tooltip = "The window's title. Leave blank for \"Shopping List\".",
          disabled = off, disabledTooltip = DIS,
          getValue = function() return Get("titleText") end,
          setValue = function(text)
              Set("titleText", (text or ""):match("^%s*(.-)%s*$"))
          end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._leftRegion, RGBSwatch("bgR", "bgG", "bgB", "Background Color"))
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  HEADER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "HEADER", y);  y = y - h

    row, h = W:DualRow(parent, y,
        Slider("hdrHeight", "Header Height", 14, 40),
        Slider("hdrBgAlpha", "Opacity", 0, 1, 0.01)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._rightRegion, ColorSwatch("hdrBgColor", "Header Background"))
    end

    row, h = W:DualRow(parent, y,
        Slider("hdrBottomBorderSize", "Header Bottom Border", 0, 4, 1),
        Slider("hdrIconSize", "Icon Size", 14, 30)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._leftRegion, ColorSwatch("hdrBottomBorderColor", "Header Border Color", true))
        AccentOrCustom(row._rightRegion, "iconColorUseAccent", "iconColor", "Icon Color")
        EllesmereUI.BuildInlineCog(row._rightRegion, {
            title = "Icon Visibility", disabled = off, disabledTooltip = DIS,
            rows = {
                { type = "toggle", label = "Mouseover Icons",
                  tooltip = "The header icons show only while the pointer is over the window.",
                  get = function() return Get("hdrMouseoverIcons") == true end,
                  set = function(v) Set("hdrMouseoverIcons", v) end },
            },
        })
    end

    row, h = W:DualRow(parent, y, Slider("hdrFontSize", "Text Size", 8, 20), BLANK());  y = y - h
    if not EllesmereUI._prebuilding then
        AccentOrCustom(row._leftRegion, "hdrTextUseAccent", "hdrTextColor", "Title Color")
        OffsetCog(row._leftRegion, "Title Position", "hdrTextOffX", "hdrTextOffY")
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  BARS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BARS", y);  y = y - h

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
        Dropdown("barTexture", "Bar Texture", texValues, texOrder),
        Slider("barHeight", "Bar Height", 8, 40)
    );  y = y - h

    row, h = W:DualRow(parent, y,
        Dropdown("colorMode", "Color", COLOR_MODES, COLOR_MODE_ORDER, function(v)
            Set("colorMode", v)
            EllesmereUI:RefreshPage()
        end),
        Slider("barFillAlpha", "Opacity", 0, 1, 0.01)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._leftRegion, Alternative(ColorSwatch("barColor", "Custom Color"),
            function() return Get("colorMode") == "custom" end,
            function() Set("colorMode", "custom") end))
    end

    row, h = W:DualRow(parent, y,
        Slider("barSpacing", "Spacing", 0, 10, 1, { pixel = true }),
        Dropdown("iconStyle", "Icon Style", ICON_STYLES, ICON_STYLE_ORDER)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._rightRegion, {
            title = "Icon Zoom",
            disabled = function() return off() or Get("iconStyle") == "none" end,
            disabledTooltip = Needs("Icon Style"),
            rows = {
                { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                  get = function() return Get("iconZoom") end,
                  set = function(v) Set("iconZoom", v) end },
            },
        })
    end

    row, h = W:DualRow(parent, y, BorderStyle(false, "Border Style"), BorderSize(false, "Border Size"));  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options", icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = off, disabledTooltip = DIS,
            rows = {
                { type = "toggle", label = "Border Follows Bar",
                  tooltip = "The border wraps only the filled part of each bar.",
                  get = function() return Get("borderFollowFill") == true end,
                  set = function(v) Set("borderFollowFill", v) end },
            },
        })
        Swatch(row._rightRegion, RGBSwatch("borderR", "borderG", "borderB", "Border Color", "borderA"))
    end

    row, h = W:DualRow(parent, y,
        Toggle("showHoverTooltip", "Show Tooltip on Hover", "The item or recipe tooltip when the pointer is over a row."),
        Slider("barBgAlpha", "Background", 0, 1, 0.01)
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._rightRegion, RGBSwatch("barBgR", "barBgG", "barBgB", "Bar Background"))
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  BAR TEXT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BAR TEXT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Dropdown("numberFormat", "Number Format", NUMBER_FORMATS, NUMBER_FORMAT_ORDER),
        Dropdown("qtyFormat", "Recipe Quantity", QTY_FORMATS, QTY_FORMAT_ORDER)
    );  y = y - h

    row, h = W:DualRow(parent, y,
        Slider("leftFontSize", "Left Text Size", 8, 18),
        Slider("rightFontSize", "Right Text Size", 8, 18)
    );  y = y - h
    local sizeRow = row

    row, h = W:DualRow(parent, y,
        Toggle("sectionTextUseAccent", "Accent Section Titles", "Section titles (Recipes, Reagents...) in the accent color.",
            function(v) Set("sectionTextUseAccent", v); EllesmereUI:RefreshPage() end),
        BLANK()
    );  y = y - h
    if not EllesmereUI._prebuilding then
        Swatch(row._leftRegion, Alternative(ColorSwatch("sectionTextColor", "Section Title Color"),
            function() return not Get("sectionTextUseAccent") end,
            function() Set("sectionTextUseAccent", false) end))
    end
    row = sizeRow
    if not EllesmereUI._prebuilding then
        Swatch(row._leftRegion, ColorSwatch("leftTextColor", "Left Text Color"))
        OffsetCog(row._leftRegion, "Left Text", "leftTextOffsetX", "leftTextOffsetY")
        Swatch(row._rightRegion, ColorSwatch("rightTextColor", "Right Text Color"))
        OffsetCog(row._rightRegion, "Right Text", "rightTextOffsetX", "rightTextOffsetY")
    end

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Registration
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    EllesmereUI:RegisterModule("EllesmereUIShoppingList", {
        title       = "Shopping List",
        description = "Track recipes and see the reagents you still need to buy or gather.",
        pages       = { PAGE_GENERAL, PAGE_WINDOW },
        searchTerms = { "shopping", "profession", "reagents", "crafting", "materials", "recipe",
                        "vendor", "transmute", "cooldown", "auction" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then return BuildGeneralPage(pageName, parent, yOffset) end
            if pageName == PAGE_WINDOW then return BuildWindowPage(pageName, parent, yOffset) end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_WINDOW then return HeaderBuilder end
        end,
        onReset = function()
            local db = ns.DB()
            if db then db:ResetProfile() end
            if EllesmereUIDB and EllesmereUIDB.unlockAnchors then
                EllesmereUIDB.unlockAnchors[ns.UNLOCK_KEY] = nil
            end
            ns.Apply()
            ns.ApplyStyle()
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
