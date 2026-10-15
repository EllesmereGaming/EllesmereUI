if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\CoreTextColoring_Options.lua
--  Nameplates options: the Core Text Coloring section of the Display page,
--  one Text Coloring half per assigned text in position order. Called by
--  BuildDisplayLayout (DisplayLayout_Options.lua) right after the Core Text
--  Positions section; returns y. Shared helpers come from ns._NPO_OptEnv, the
--  text slots from ns.NPO_TEXT_SLOTS and ns.NPO_TextSlotShown.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

local function BuildCoreTextColoring(parent, y, W)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults = env.DB, env.DBVal, env.defaults
    local PP, UpdatePreview, RefreshAllPlates = env.PP, env.UpdatePreview, env.RefreshAllPlates

    -- The assigned texts in position order. While none is assigned the section
    -- is not built at all (no header, no spacer).
    local shown = {}
    local slots = ns.NPO_TEXT_SLOTS
    for i = 1, #slots do
        if ns.NPO_TextSlotShown(slots[i].key) then shown[#shown + 1] = slots[i] end
    end
    if #shown == 0 then return y end

    local _, h = W:SectionHeader(parent, "CORE TEXT COLORING", y);  y = y - h

    parent._showRowDivider = true

    -- Text Coloring halves: one per assigned text, in their own section. The
    -- dropdown picks the slot's colour mode; ns.NP_SlotColorMode reads the saved
    -- mode, or derives it from the older colour keys until one is picked, so the
    -- page and the plates always agree.
    -- Custom paints the slot colour; Hostility / Class paints enemy players by
    -- class and NPCs by the Tapped / Neutral / Hostile name colours every slot
    -- shares (Target of Target: the target's class, else the slot colour); Level
    -- Difficulty paints the unit's level difficulty colour (every text but Target
    -- of Target, which names another unit).
    local COLOR_MODE_ORDER = { "custom", "class" }
    local COLOR_MODE_ORDER_LEVEL = { "custom", "class", "level" }
    local function TextColoringCfg(slotKey, label)
        local el = DBVal(slotKey)
        if el == "none" then return EllesmereUI.BlankRowCfg() end
        local values, order
        if el == "targetOfTarget" then
            values, order = { custom = "Custom", class = "Class" }, COLOR_MODE_ORDER
        else
            values = { custom = "Custom", class = "Hostility / Class", level = "Level Difficulty" }
            order = COLOR_MODE_ORDER_LEVEL
        end
        return { type="dropdown", text=label, values=values, order=order,
          getValue=function() return ns.NP_SlotColorMode(slotKey, DB()) end,
          -- The mode is saved only when the pick differs from what the slot derives
          -- with none saved, so picking the derived value pins nothing. Rebuild: the
          -- shared NPC swatches exist only on a Hostility / Class half.
          setValue=function(v)
            local db = DB()
            db[slotKey .. "ColorMode"] = nil
            if ns.NP_SlotColorMode(slotKey, db) ~= v then
                db[slotKey .. "ColorMode"] = v
            end
            ns.RefreshAllSettings()
            UpdatePreview(); EllesmereUI:RefreshPage(true)
          end }
    end

    -- A Text Coloring half's inline controls. The swatches sit beside the
    -- dropdown, shown by the mode from the page refresh: Custom the slot colour,
    -- Hostility / Class the three shared NPC colours (Target of Target: the slot
    -- colour, used for an NPC target), Level Difficulty none. Level | Name and
    -- Name | Level add a cog left of the shown swatches (beside the dropdown when
    -- none show) with the name and level part colours (inline escapes on that part
    -- only; the rest of the text keeps the mode's colour). The NPC swatches are
    -- built only on a Hostility / Class half, so no other half traces the shared
    -- keys for Spec Overrides. Every write goes through the dropdown, a cog row or
    -- a swatch, which the Spec Overrides capture follows on its own.
    local npcSwatchUpdates = {}  -- the shared NPC swatches of every row, repainted together
    local function MakeTextColoringInline(row, regionKey, slotKey, title)
        local el = DBVal(slotKey)
        if el == "none" then return end
        local rgn = row[regionKey]
        local colorKey = slotKey .. "Color"
        local isToT = el == "targetOfTarget"
        local function Mode() return ns.NP_SlotColorMode(slotKey, DB()) end
        local function Apply()
            ns.RefreshAllSettings()
            UpdatePreview()
        end

        local anchor = rgn._lastInline or rgn._control
        local gap = rgn._lastInline and -8 or -12
        local custom, updateCustom = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
            function()
                local c = (DB() and DB()[colorKey]) or defaults[colorKey]
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                DB()[colorKey] = { r = r, g = g, b = b }
                Apply()
            end, nil, 20)
        PP.Point(custom, "RIGHT", anchor, "LEFT", gap, 0)
        custom:SetScript("OnEnter", function()
            if isToT and Mode() == "class" then
                EllesmereUI.ShowWidgetTooltip(custom, EllesmereUI.L("NPC Target Color"))
            else
                EllesmereUI.ShowWidgetTooltip(custom, EllesmereUI.L("Custom Color"))
            end
        end)
        custom:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rgn._lastInline = custom

        -- Hostility / Class: Tapped / Neutral / Hostile left to right, Hostile in
        -- the custom swatch's place.
        local npc, npcUpd
        if not isToT and Mode() == "class" then
            npc, npcUpd = {}, {}
            local prev, prevGap = anchor, gap
            local function NPCSwatch(key, fallbackKey, tip)
                local sw, upd = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = (DB() and DB()[key]) or defaults[fallbackKey]
                        return c.r, c.g, c.b
                    end,
                    -- Read live by the per-unit painter, so a health colour pass repaints.
                    function(r, g, b)
                        DB()[key] = { r = r, g = g, b = b }
                        RefreshAllPlates()
                        UpdatePreview()
                        for i = 1, #npcSwatchUpdates do npcSwatchUpdates[i]() end
                    end, nil, 20)
                PP.Point(sw, "RIGHT", prev, "LEFT", prevGap, 0)
                prev, prevGap = sw, -8
                sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tip) end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                npc[#npc + 1] = sw
                npcUpd[#npcUpd + 1] = upd
                npcSwatchUpdates[#npcSwatchUpdates + 1] = upd
                return sw
            end
            NPCSwatch("enemyNameHostileColor", "hostile", EllesmereUI.L("Hostile Color"))
            NPCSwatch("enemyNameNeutralColor", "neutral", EllesmereUI.L("Neutral Color"))
            -- Leftmost swatch (the label clamp's bound unless a cog follows).
            rgn._lastInline = NPCSwatch("enemyNameTappedColor", "tapped", EllesmereUI.L("Tapped Color"))
        end

        -- Level | Name and Name | Level: the part colours on a cog left of the
        -- swatches. It becomes the leftmost item, which the label clamp keeps clear of.
        local cog
        if el == "levelName" or el == "nameLevel" then
            local nameOnKey, nameColorKey = slotKey .. "NameColorOn", slotKey .. "NameColor"
            local lvlOnKey, lvlColorKey = slotKey .. "LevelColorOn", slotKey .. "LevelColor"
            local diffKey = slotKey .. "LevelDiffOn"
            -- A part colour not picked yet starts from the slot colour.
            local function PartColor(key)
                local db = DB()
                local c = (db and (db[key] or db[colorKey])) or defaults[colorKey]
                return c.r, c.g, c.b
            end
            cog = EllesmereUI.BuildInlineCog(rgn, {
                title = title,
                captureRegion = rgn,
                rows = {
                    { type="toggle", label="Custom Name Color",
                      get=function() return DBVal(nameOnKey) == true end,
                      set=function(v) DB()[nameOnKey] = v; Apply() end },
                    { type="colorpicker", label="Name Color",
                      hidden=function() return DBVal(nameOnKey) ~= true end,
                      get=function() return PartColor(nameColorKey) end,
                      set=function(r, g, b) DB()[nameColorKey] = { r = r, g = g, b = b }; Apply() end },
                    { type="toggle", label="Custom Level Color",
                      get=function() return DBVal(lvlOnKey) == true end,
                      set=function(v)
                        DB()[lvlOnKey] = v
                        if v then DB()[diffKey] = false end
                        Apply()
                      end },
                    { type="colorpicker", label="Level Color",
                      hidden=function() return DBVal(lvlOnKey) ~= true end,
                      get=function() return PartColor(lvlColorKey) end,
                      set=function(r, g, b) DB()[lvlColorKey] = { r = r, g = g, b = b }; Apply() end },
                    -- The whole text already takes the difficulty colour in Level
                    -- Difficulty mode.
                    { type="toggle", label="Level Difficulty Color",
                      hidden=function() return Mode() == "level" end,
                      get=function() return ns.NP_SlotLevelDiff(slotKey, DB()) end,
                      set=function(v)
                        DB()[diffKey] = v
                        if v then DB()[lvlOnKey] = false end
                        Apply()
                      end },
                },
            })
        end

        local cogLeftOf  -- what the cog sits beside; follows the swatches the mode shows
        local function ShowForMode()
            local m = Mode()
            local showCustom = m == "custom" or (isToT and m == "class")
            custom:SetShown(showCustom)
            updateCustom()
            local npcOn = npc and m == "class"
            if npc then
                for i = 1, #npc do
                    npc[i]:SetShown(npcOn)
                    npcUpd[i]()
                end
            end
            if cog then
                local left = (npcOn and npc[#npc]) or (showCustom and custom) or rgn._control
                if left ~= cogLeftOf then
                    cogLeftOf = left
                    cog:ClearAllPoints()
                    PP.Point(cog, "RIGHT", left, "LEFT", -8, 0)
                end
            end
        end
        EllesmereUI.RegisterWidgetRefresh(ShowForMode)
        ShowForMode()
    end

    -- Two halves per row in position order; an odd last half sits beside a
    -- blank one.
    for k = 1, #shown, 2 do
        local l, r = shown[k], shown[k + 1]
        local row, rowH = W:DualRow(parent, y, TextColoringCfg(l.key, l.coloring),
            r and TextColoringCfg(r.key, r.coloring) or EllesmereUI.BlankRowCfg())
        if not EllesmereUI._prebuilding then
            MakeTextColoringInline(row, "_leftRegion", l.key, l.coloring)
            if r then MakeTextColoringInline(row, "_rightRegion", r.key, r.coloring) end
        end
        y = y - rowH
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return y
end

-- Used by DisplayLayout_Options.lua
ns.NPO_BuildCoreTextColoring = BuildCoreTextColoring
