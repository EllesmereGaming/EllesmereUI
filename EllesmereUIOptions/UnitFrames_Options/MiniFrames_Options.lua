if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\MiniFrames_Options.lua
--  Unit Frames options: Mini Frames and Boss Frames builders. Definitions
--  only; the shared helpers come from ns._UFO_OptEnv (filled by
--  EUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end  -- module disabled: no options page

---------------------------------------------------------------------------
--  Mini frame donor settings helper
--  Returns the settings table unitKey copies its look from (its Copy Look
--  From pick, else focus, target, player). Routed through the runtime
--  resolver so the options preview and the live frames can never disagree
--  about which frame is on screen to inherit from.
---------------------------------------------------------------------------
local function GetMiniDonorSettings(unitKey)
    local env = ns._UFO_OptEnv
    local db = env.db
    return ns.GetMiniDonorSettings and ns.GetMiniDonorSettings(unitKey) or db.profile.player
end

---------------------------------------------------------------------------
--  Shared mini frame settings builder
---------------------------------------------------------------------------
local function BuildMiniTextAndSize(W, parent, y, settingsTable, unitKey, enableRow, afterSizeRow, opts)
    local env = ns._UFO_OptEnv
    local AddDarkModeBlock, BuildBarTexDropdown, BuildInactiveNotice, PP = env.AddDarkModeBlock, env.BuildBarTexDropdown, env.BuildInactiveNotice, env.PP
    local RegisterWidgetRefresh, ReloadAndUpdate, db, healthTextOrder = env.RegisterWidgetRefresh, env.ReloadAndUpdate, env.db, env.healthTextOrder
    local healthTextOrderBoss, healthTextValues = env.healthTextOrderBoss, env.healthTextValues
    local _, h
    opts = opts or {}


    -- Shorthand accessors for this mini frame's settings
    local function MGet(key) return settingsTable[key] end
    local function MSet(key, val) settingsTable[key] = val; ReloadAndUpdate() end
    local function MVal(key, default)
        local v = settingsTable[key]
        if v ~= nil then return v end
        return default
    end

    -- DISPLAY
    local displayHeader
    displayHeader, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "unitframes")

    -- Enable row (passed in from each builder)
    local enableRowFrame
    if enableRow then
        enableRowFrame, h = enableRow(W, parent, y)
        y = y - h
    end

    -- If this unit isn't on the EllesmereUI frame, skip the (inapplicable)
    -- settings below and show a short notice instead.
    if enableRow and ns.GetUnitFrameSource(unitKey) ~= "eui" then
        y = BuildInactiveNotice(parent, y, ns.GetUnitFrameSource(unitKey))
        return y, displayHeader, nil, nil, nil, enableRowFrame
    end

    -- Bar Texture override. Mini frames inherit the main frames' donor texture
    -- (Copy Look From) by default; a specific pick here overrides it for
    -- this frame only. Lands as the last DISPLAY row: Row 2 for ToT/Focus Target/Pet, Row 3 for Boss.
    do
        local mtVals, mtOrder = BuildBarTexDropdown()
        table.insert(mtOrder, 1, "inherit")
        mtVals["inherit"] = "Inherit (Main Frames)"
        -- Menu item preview background for "Inherit" shows the donor texture.
        local mo = mtVals._menuOpts
        if mo then
            local baseBg = mo.background
            mo.background = function(key)
                if key == "inherit" then
                    local donor = GetMiniDonorSettings(unitKey)
                    local dk = donor and donor.healthBarTexture
                    if dk == "inherit" then dk = nil end
                    dk = dk or db.profile.healthBarTexture
                    return dk and (ns.healthBarTextures or {})[dk] or nil
                end
                return baseBg and baseBg(key) or nil
            end
        end
        -- Boss frames get a "Hover Borders" control in the right slot (mirrors
        -- Raid Frames); the other mini frames leave that slot empty.
        local isBoss = (unitKey == "boss")
        local rightSlot
        if isBoss then
            rightSlot = { type="dropdown", text="Hover Borders",
                values={ __placeholder = "All" }, order={ "__placeholder" },
                getValue=function() return "__placeholder" end,
                setValue=function() end }
        else
            -- ToT / Focus Target / Pet: per-frame Strata override (same options as
            -- main frames' Frame Strata); inherits the global value until set
            -- (getter falls back to db.profile.frameStrata).
            local miniStrataValues = EllesmereUI.FRAME_STRATA_LABELS
            local miniStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
            rightSlot = { type="dropdown", text="Strata",
                tooltip="Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
                values = miniStrataValues, order = miniStrataOrder,
                getValue=function() return settingsTable.frameStrata or db.profile.frameStrata or "MEDIUM" end,
                setValue=function(v)
                    settingsTable.frameStrata = v
                    ReloadAndUpdate()
                end }
        end
        local barTexRow
        barTexRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture", values=mtVals, order=mtOrder,
              getValue=function()
                  local v = settingsTable.healthBarTexture
                  if v == nil then return "inherit" end
                  return v
              end,
              setValue=function(v)
                  if v == "inherit" then
                      settingsTable.healthBarTexture = nil
                  else
                      settingsTable.healthBarTexture = v
                  end
                  ReloadAndUpdate()
              end },
            rightSlot);  y = y - h

        -- Boss Hover Borders: checkbox dropdown (Hover Border / Target Border,
        -- both default off) with inline color swatches. Enabling one recolors
        -- the boss frame's existing border to that color (hover > target).
        if isBoss and not EllesmereUI._prebuilding then
            local PP = EllesmereUI.PP
            local rightRgn = barTexRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local hbKeyMap = { hover = "bossHoverBorderEnabled", target = "bossTargetBorderEnabled" }
            local hbItems = {
                { key = "hover",  label = "Hover Border" },
                { key = "target", label = "Target Border" },
            }
            local UpdateHBSwatchVis  -- forward declare; assigned after swatches
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 170, rightRgn:GetFrameLevel() + 2,
                hbItems,
                function(k) return settingsTable[hbKeyMap[k]] and true or false end,
                function(k, v)
                    settingsTable[hbKeyMap[k]] = v
                    ReloadAndUpdate()
                    if UpdateHBSwatchVis then UpdateHBSwatchVis() end
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil

            -- Inline swatches: Hover (nearest the dropdown), then Target to its left.
            local lvl = barTexRow:GetFrameLevel() + 3
            local hoverSwatch, updHover = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = settingsTable.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, settingsTable.bossHoverBorderAlpha or 1
                end,
                function(r, g, b, a)
                    settingsTable.bossHoverBorderColor = { r=r, g=g, b=b }
                    settingsTable.bossHoverBorderAlpha = a
                    ReloadAndUpdate()
                end, true, 20)
            hoverSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = hoverSwatch
            hoverSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hoverSwatch, "Hover") end)
            hoverSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local targetSwatch, updTarget = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = settingsTable.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b, settingsTable.bossTargetBorderAlpha or 1
                end,
                function(r, g, b, a)
                    settingsTable.bossTargetBorderColor = { r=r, g=g, b=b }
                    settingsTable.bossTargetBorderAlpha = a
                    ReloadAndUpdate()
                end, true, 20)
            targetSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = targetSwatch
            targetSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(targetSwatch, "Target") end)
            targetSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Gray a swatch when its border state is off (still clickable so the
            -- color can be pre-set), matching the Raid Frames Hover Borders row.
            UpdateHBSwatchVis = function()
                hoverSwatch:SetAlpha(settingsTable.bossHoverBorderEnabled and 1 or 0.3)
                targetSwatch:SetAlpha(settingsTable.bossTargetBorderEnabled and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(function() updHover(); updTarget(); UpdateHBSwatchVis() end)
            UpdateHBSwatchVis()
        end
    end

    -- Boss Border Style | Border Size (+ Width Offset | Height Offset for a
    -- textured style): the boss frames' own border, or the main frames'
    -- while the style reads Inherit. Full pairs, so Strata below stays
    -- the section's odd last slot.
    if unitKey == "boss" then
        y = y - ns.UF_BossFrameBorderRows(W, parent, y, settingsTable, ReloadAndUpdate)
    end

    -- DISPLAY bottom row for boss: the mini frames carry their Strata
    -- override in the Bar Texture row's right slot, which boss spends on
    -- Hover Borders, so boss gets its own row here. Without it nothing in
    -- the UI writes a boss strata at all -- the main frames' dropdown is
    -- per-frame and the profile-wide value is only the fallback.
    if unitKey == "boss" then
        local bossStrataValues = EllesmereUI.FRAME_STRATA_LABELS
        local bossStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Strata",
              tooltip="Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
              values = bossStrataValues, order = bossStrataOrder,
              getValue=function() return settingsTable.frameStrata or db.profile.frameStrata or "MEDIUM" end,
              setValue=function(v)
                  settingsTable.frameStrata = v
                  ReloadAndUpdate()
              end },
            { type="label", text="" });  y = y - h
    end

    -- DISPLAY bottom row: per-frame Border Size override for ToT/Focus Target/Pet.
    -- Size only, no color/texture (those still inherit from main frames);
    -- borderSizeOverride nil = inherit donor size until set. Boss frames use
    -- their own Border Style | Border Size row above instead.
    if unitKey ~= "boss" then
        _, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Border Size", min=0, max=4, step=1,
              tooltip="Overrides the border size from the main frames for this frame only. Border color and texture still follow the main frames.",
              getValue=function()
                  local donor = GetMiniDonorSettings(unitKey)
                  return settingsTable.borderSizeOverride or (donor and donor.borderSize) or 1
              end,
              setValue=function(v) settingsTable.borderSizeOverride = v; ReloadAndUpdate() end }),
            { type="toggle", text="Show Highlight Border",
              tooltip="Show the main frames' hover highlight border on this frame. Turn off so this frame never recolors on mouseover. No effect when Highlight is off in the main frames' Hover Borders.",
              getValue=function() return settingsTable.showHighlightBorder ~= false end,
              setValue=function(v) settingsTable.showHighlightBorder = v end });  y = y - h
    end

    -- Optional extra rows after enable (e.g. portrait, cast icon, indicators)
    if afterSizeRow then
        y = afterSizeRow(W, parent, y)
    end

    -- HEALTH BAR section
    local textHeader
    textHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

    -- Row 1: Bar Height + Bar Width
    local sizeRow
    local mhDis, mhTip, mhRaw = EllesmereUI.MatchGuard(unitKey, "Height")
    local mwDis, mwTip, mwRaw = EllesmereUI.MatchGuard(unitKey, "Width")
    local rightSlot
    if EllesmereUI.BlizzStyle.Get("unitframes") then
        -- Blizzard Style: the stock size is fixed, so the whole frame scales
        -- instead; the slider takes the gated width's slot (no blank slot).
        rightSlot = { type="slider", text="Frame Scale", min=50, max=200, step=5,
            tooltip="Scales the whole frame. Blizzard Style frames are the stock size, so this stands in for Bar Width and Health Bar Height.",
            getValue=function() return math.floor((settingsTable.blizzScale or 1) * 100 + 0.5) end,
            setValue=function(v) settingsTable.blizzScale = v / 100; ReloadAndUpdate() end }
    elseif opts.hideBarWidth then
        rightSlot = { type="label", text="" }
    else
        rightSlot = EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Bar Width", min=60, max=300, step=1,
            disabled=mwDis, disabledTooltip=mwTip, rawTooltip=mwRaw,
            getValue=function() return settingsTable.frameWidth end,
            setValue=function(v) settingsTable.frameWidth = v; ReloadAndUpdate() end })
    end
    sizeRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Health Bar Height", min=10, max=100, step=1,
          disabled=mhDis, disabledTooltip=mhTip, rawTooltip=mhRaw,
          getValue=function() return settingsTable.healthHeight end,
          setValue=function(v) settingsTable.healthHeight = v; ReloadAndUpdate() end }),
        rightSlot);  y = y - h

    -- Row 2: Fill Color + Bar Background/Opacity. Boss frames present each as an
    -- opacity slider with inline class/custom swatches (mirroring Main Frames' Bar
    -- Background); other mini units keep the combined "Bar Color" multiSwatch + "Bar Opacity" slider.
    do
        local isBoss = (unitKey == "boss")

        local leftSlot2, rightSlot2
        if isBoss then
            -- Fill Color = the health fill opacity (formerly "Fill Opacity")
            -- with the fill color swatches moved inline below.
            leftSlot2 = { type="slider", text="Fill Color", min=0, max=100, step=1,
              disabled=function() return db.profile.darkTheme end,
              disabledTooltip="Dark Mode", requireState="disabled",
              getValue=function() return MVal("healthBarOpacity", 90) end,
              setValue=function(v) MSet("healthBarOpacity", v) end }
            rightSlot2 = { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return MVal("customBgAlpha", 100) end,
              setValue=function(v) MSet("customBgAlpha", v) end }
        else
            -- "Fill Color" picker: Custom Colored Fill + Class Colored Fill.
            -- Bar Background was split out to its own slider + swatch row below
            -- (still the same customBgColor / customBgAlpha variables).
            local fillSwatches = {
                { tooltip = "Custom Colored Fill", hasAlpha = false,
                  getValue = function()
                      local c = MGet("customFillColor")
                      if c then return c.r, c.g, c.b end
                      return 37/255, 193/255, 29/255
                  end,
                  setValue = function(r, g, b)
                      settingsTable.customFillColor = { r=r, g=g, b=b }
                      ReloadAndUpdate()
                  end,
                  onClick = function(self)
                      if MVal("healthClassColored", false) then
                          if MGet("customFillColor") == nil then
                              settingsTable.customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                          end
                          settingsTable.healthClassColored = false
                          ReloadAndUpdate(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return MVal("healthClassColored", false) and 0.3 or 1
                  end },
                { tooltip = "Class Colored Fill", hasAlpha = false,
                  getValue = function()
                      local _, ct = UnitClass("player")
                      if ct and RAID_CLASS_COLORS[ct] then
                          local cc = RAID_CLASS_COLORS[ct]
                          return cc.r, cc.g, cc.b
                      end
                      return 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      settingsTable.healthClassColored = true
                      ReloadAndUpdate(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return MVal("healthClassColored", false) and 1 or 0.3
                  end },
            }
            leftSlot2 = { type="multiSwatch", text="Fill Color", swatches = fillSwatches }
            rightSlot2 = { type="slider", text="Fill Opacity", min=0, max=100, step=1,
              disabled=function() return db.profile.darkTheme end,
              disabledTooltip="Dark Mode", requireState="disabled",
              getValue=function() return MVal("healthBarOpacity", 90) end,
              setValue=function(v) MSet("healthBarOpacity", v) end }
        end

        local colorRow
        colorRow, h = W:DualRow(parent, y, leftSlot2, rightSlot2);  y = y - h

        if isBoss then
            -- Inline Custom + Class fill swatches on the Fill Color slider (left
            -- region); both toggle healthClassColored, the inactive one dims to 0.3.
            if not EllesmereUI._prebuilding then
                local rgn = colorRow._leftRegion
                local fClassGet = function()
                    local _, ct = UnitClass("player")
                    local cc = ct and RAID_CLASS_COLORS[ct]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end
                local fClassSw, fClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fClassGet, function() end, false, 20)
                fClassSw._eabOrigClick = fClassSw:GetScript("OnClick")
                fClassSw:SetScript("OnClick", function()
                    settingsTable.healthClassColored = true
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                fClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fClassSw, "Class Colored Fill") end)
                fClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(fClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = fClassSw
                RegisterWidgetRefresh(function()
                    fClassUpdate()
                    fClassSw:SetAlpha(MVal("healthClassColored", false) and 1 or 0.3)
                end)
                fClassSw:SetAlpha(MVal("healthClassColored", false) and 1 or 0.3)

                local fCustomGet = function()
                    local c = MGet("customFillColor")
                    if c then return c.r, c.g, c.b end
                    return 37/255, 193/255, 29/255
                end
                local fCustomSet = function(r, g, b)
                    settingsTable.customFillColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end
                local fCustomSw, fCustomUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fCustomGet, fCustomSet, false, 20)
                fCustomSw._eabOrigClick = fCustomSw:GetScript("OnClick")
                fCustomSw:SetScript("OnClick", function(self)
                    if MVal("healthClassColored", false) then
                        if MGet("customFillColor") == nil then
                            settingsTable.customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                        end
                        settingsTable.healthClassColored = false
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end)
                fCustomSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fCustomSw, "Custom Colored Fill") end)
                fCustomSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(fCustomSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = fCustomSw
                RegisterWidgetRefresh(function()
                    fCustomUpdate()
                    fCustomSw:SetAlpha(MVal("healthClassColored", false) and 0.3 or 1)
                end)
                fCustomSw:SetAlpha(MVal("healthClassColored", false) and 0.3 or 1)
            end

            -- Inline Custom + Class background swatches on the Bar Background
            -- slider (right region); both toggle bgClassColored, inactive dims to 0.3.
            if not EllesmereUI._prebuilding then
                local rgn = colorRow._rightRegion
                local bgClassGet = function()
                    local _, ct = UnitClass("player")
                    local cc = ct and RAID_CLASS_COLORS[ct]
                    if cc then return cc.r, cc.g, cc.b end
                    return 1, 1, 1
                end
                local bgClassSw, bgClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgClassGet, function() end, false, 20)
                bgClassSw._eabOrigClick = bgClassSw:GetScript("OnClick")
                bgClassSw:SetScript("OnClick", function()
                    settingsTable.bgClassColored = true
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end)
                bgClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSw, "Class Colored Background") end)
                bgClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(bgClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = bgClassSw
                RegisterWidgetRefresh(function()
                    bgClassUpdate()
                    bgClassSw:SetAlpha(MVal("bgClassColored", false) and 1 or 0.3)
                end)
                bgClassSw:SetAlpha(MVal("bgClassColored", false) and 1 or 0.3)

                local bgSwGet = function()
                    local c = MGet("customBgColor")
                    if c then return c.r, c.g, c.b end
                    return 17/255, 17/255, 17/255
                end
                local bgSwSet = function(r, g, b)
                    settingsTable.customBgColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end
                local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
                bgSw._eabOrigClick = bgSw:GetScript("OnClick")
                bgSw:SetScript("OnClick", function(self)
                    if MVal("bgClassColored", false) then
                        settingsTable.bgClassColored = false
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end)
                bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
                bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = bgSw
                RegisterWidgetRefresh(function()
                    bgSwUpdate()
                    bgSw:SetAlpha(MVal("bgClassColored", false) and 0.3 or 1)
                end)
                bgSw:SetAlpha(MVal("bgClassColored", false) and 0.3 or 1)
            end
        end

        -- Dark Mode disables Fill Color controls (flat dark health bar ignores
        -- fill/background colors). Boss also blocks Bar Background so its swatches
        -- gray out like Main Frames; other mini units' Bar Opacity has its own disable handler.
        if not EllesmereUI._prebuilding then
        AddDarkModeBlock(colorRow._leftRegion)
        if isBoss then AddDarkModeBlock(colorRow._rightRegion) end
        end
    end

    -- Smooth Health Bars + Reverse Fill. For the mini frames (ToT / Focus
    -- Target / Pet) Smooth Health Bars is relocated to the Center Text row
    -- (slot 2) below, leaving only Reverse Fill on this row. Boss keeps both.
    local smoothBarsWidget = { type="toggle", text="Smooth Health Bars",
          getValue=function() return MVal("smoothBars", false) end,
          setValue=function(v) MSet("smoothBars", v) end }
    local reverseFillWidget = { type="toggle", text="Reverse Fill",
          getValue=function() return settingsTable.healthReverseFill end,
          setValue=function(v) settingsTable.healthReverseFill = v; ReloadAndUpdate() end }
    if unitKey == "boss" then
        _, h = W:DualRow(parent, y, smoothBarsWidget, reverseFillWidget);  y = y - h
    else
        -- Bar Background (opacity slider + inline color swatch) | Reverse Fill.
        -- Reuses the existing customBgAlpha (opacity) + customBgColor (color)
        -- variables -- same as the Boss frames and the runtime health bg, so
        -- no saved option changes.
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return MVal("customBgAlpha", 100) end,
              setValue=function(v) MSet("customBgAlpha", v) end },
            reverseFillWidget);  y = y - h
        -- inline bg colors - custom swatch + class swatch
        -- tot/focus use class for player, reaction for npc
        -- pet resolves to player's class color
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(bgRow._leftRegion, {
                { tooltip = "Custom Background Color", hasAlpha = false,
                  getValue = function()
                      local c = MGet("customBgColor")
                      if c then return c.r, c.g, c.b end
                      return 17/255, 17/255, 17/255
                  end,
                  setValue = function(r, g, b)
                      settingsTable.customBgColor = { r=r, g=g, b=b }
                      ReloadAndUpdate()
                  end,
                  onClick = function(self)
                      if MVal("bgClassColored", false) then
                          settingsTable.bgClassColored = false
                          ReloadAndUpdate(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return MVal("bgClassColored", false) and 0.3 or 1
                  end },
                { tooltip = "Class Colored Background", hasAlpha = false,
                  getValue = function()
                      local _, ct = UnitClass("player")
                      local cc = ct and RAID_CLASS_COLORS[ct]
                      if cc then return cc.r, cc.g, cc.b end
                      return 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      settingsTable.bgClassColored = true
                      ReloadAndUpdate(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return MVal("bgClassColored", false) and 1 or 0.3
                  end },
            })
        end
    end

    -- Vertical Fill swaps the fill AXIS (Reverse Fill above flips direction within
    -- it, so vertical+reverse fills top-to-bottom); own row since Reverse Fill's row is already full on both layouts.
    _, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle", text="Vertical Fill",
          tooltip="Fill the health bar bottom-to-top instead of left-to-right. Reverse Fill flips it to top-to-bottom.",
          getValue=function() return settingsTable.healthVerticalFill end,
          setValue=function(v) settingsTable.healthVerticalFill = v; ReloadAndUpdate() end }),
        { type="spacer" });  y = y - h

    -- Row 3: Left Text + Right Text (with inline swatches + cogs)
    local textRow
    textRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Left Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
          getValue=function() return MVal("leftTextContent", "name") end,
          setValue=function(v)
            settingsTable.leftTextContent = v
            if v ~= "none" then
                if settingsTable.rightTextContent == v then settingsTable.rightTextContent = "none" end
                if settingsTable.centerTextContent == v then settingsTable.centerTextContent = "none" end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
          end,
        },
        { type="dropdown", text="Right Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
          getValue=function() return MVal("rightTextContent", "none") end,
          setValue=function(v)
            settingsTable.rightTextContent = v
            if v ~= "none" then
                if settingsTable.leftTextContent == v then settingsTable.leftTextContent = "none" end
                if settingsTable.centerTextContent == v then settingsTable.centerTextContent = "none" end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
          end,
        });  y = y - h
    -- Inline color swatches + cog on Left Text: Custom + Class (CDM Border Size pattern)
    if not EllesmereUI._prebuilding then
        local rgn = textRow._leftRegion
        local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
            rgn, rgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        classSw:SetScript("OnClick", function()
            if MVal("leftTextContent", "name") == "none" then return end
            MSet("leftTextClassColor", true); EllesmereUI:RefreshPage()
        end)
        classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
        classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local swGet = function()
            return MVal("leftTextColorR", 1), MVal("leftTextColorG", 1), MVal("leftTextColorB", 1)
        end
        local swSet = function(r, g, b)
            settingsTable.leftTextColorR = r; settingsTable.leftTextColorG = g; settingsTable.leftTextColorB = b
            ReloadAndUpdate()
        end
        local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
        PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
        rgn._lastInline = sw
        local origClick = sw:GetScript("OnClick")
        sw:SetScript("OnClick", function(self, ...)
            if MVal("leftTextContent", "name") == "none" then return end
            if MVal("leftTextClassColor", false) then
                MSet("leftTextClassColor", false); EllesmereUI:RefreshPage(); return
            end
            if origClick then origClick(self, ...) end
        end)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdSwatches()
            local isNone = MVal("leftTextContent", "name") == "none"
            local isClass = MVal("leftTextClassColor", false)
            sw:SetAlpha((isClass or isNone) and 0.3 or 1)
            classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
        UpdSwatches()

        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return MVal("leftTextContent", "name") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Left Text Settings",
            rows = ns.UF_NameFormatRows("leftText", "name", MVal, MSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return MVal("leftTextSize", settingsTable.textSize or 12) end,
                  set=function(v) MSet("leftTextSize", v) end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return MVal("leftTextX", 0) end,
                  set=function(v) MSet("leftTextX", v) end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return MVal("leftTextY", 0) end,
                  set=function(v) MSet("leftTextY", v) end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return MVal("leftTextWidthPct", 100) end,
                  set=function(v) MSet("leftTextWidthPct", v) end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = MVal("leftTextContent","name") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = MVal("leftTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) MSet("leftTextTargetSepColor", { r=r, g=g, b=b }) end,
                      onClick = function(self)
                          if MVal("leftTextTargetSepClassColor", false) then
                              MSet("leftTextTargetSepClassColor", false)
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return MVal("leftTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() MSet("leftTextTargetSepClassColor", true) end,
                      refreshAlpha = function() return MVal("leftTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return MVal("leftTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      MSet("leftTextTargetSep", v)
                  end,
                  disabled=function() return MVal("leftTextContent","name") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return MVal("leftTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      MSet("leftTextTargetPrefix", v)
                  end,
                  disabled=function() return MVal("leftTextContent","name") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end
    -- Inline color swatches + cog on Right Text: Custom + Class (CDM Border Size pattern)
    if not EllesmereUI._prebuilding then
        local rgn = textRow._rightRegion
        local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
            rgn, rgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        classSw:SetScript("OnClick", function()
            if MVal("rightTextContent", "none") == "none" then return end
            MSet("rightTextClassColor", true); EllesmereUI:RefreshPage()
        end)
        classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
        classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local swGet = function()
            return MVal("rightTextColorR", 1), MVal("rightTextColorG", 1), MVal("rightTextColorB", 1)
        end
        local swSet = function(r, g, b)
            settingsTable.rightTextColorR = r; settingsTable.rightTextColorG = g; settingsTable.rightTextColorB = b
            ReloadAndUpdate()
        end
        local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
        PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
        rgn._lastInline = sw
        local origClick = sw:GetScript("OnClick")
        sw:SetScript("OnClick", function(self, ...)
            if MVal("rightTextContent", "none") == "none" then return end
            if MVal("rightTextClassColor", false) then
                MSet("rightTextClassColor", false); EllesmereUI:RefreshPage(); return
            end
            if origClick then origClick(self, ...) end
        end)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdSwatches()
            local isNone = MVal("rightTextContent", "none") == "none"
            local isClass = MVal("rightTextClassColor", false)
            sw:SetAlpha((isClass or isNone) and 0.3 or 1)
            classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
        UpdSwatches()

        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return MVal("rightTextContent", "none") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Right Text Settings",
            rows = ns.UF_NameFormatRows("rightText", "none", MVal, MSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return MVal("rightTextSize", settingsTable.textSize or 12) end,
                  set=function(v) MSet("rightTextSize", v) end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return MVal("rightTextX", 0) end,
                  set=function(v) MSet("rightTextX", v) end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return MVal("rightTextY", 0) end,
                  set=function(v) MSet("rightTextY", v) end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return MVal("rightTextWidthPct", 100) end,
                  set=function(v) MSet("rightTextWidthPct", v) end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = MVal("rightTextContent","none") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = MVal("rightTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) MSet("rightTextTargetSepColor", { r=r, g=g, b=b }) end,
                      onClick = function(self)
                          if MVal("rightTextTargetSepClassColor", false) then
                              MSet("rightTextTargetSepClassColor", false)
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return MVal("rightTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() MSet("rightTextTargetSepClassColor", true) end,
                      refreshAlpha = function() return MVal("rightTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return MVal("rightTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      MSet("rightTextTargetSep", v)
                  end,
                  disabled=function() return MVal("rightTextContent","none") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return MVal("rightTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      MSet("rightTextTargetPrefix", v)
                  end,
                  disabled=function() return MVal("rightTextContent","none") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Row 4: Center Text (with inline swatch + cog). Slot 2 holds Smooth Health
    -- Bars for the mini frames (ToT / Focus Target / Pet); boss gets the
    -- Extra Text zone there instead (4th text zone, same as Main Frames).
    local centerRow
    centerRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Center Text", values=healthTextValues, order=(unitKey == "boss") and healthTextOrderBoss or healthTextOrder,
          getValue=function() return MVal("centerTextContent", "none") end,
          setValue=function(v)
            settingsTable.centerTextContent = v
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
          end },
        (unitKey ~= "boss") and smoothBarsWidget
        or { type="dropdown", text="Extra Text (full length)", values=healthTextValues, order=healthTextOrderBoss,
          getValue=function() return MVal("extraTextContent", "none") end,
          setValue=function(v)
            settingsTable.extraTextContent = v
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
          end });  y = y - h
    -- Inline color swatches + cog on Center Text: Custom + Class (CDM Border Size pattern)
    if not EllesmereUI._prebuilding then
        local rgn = centerRow._leftRegion
        local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
            rgn, rgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        classSw:SetScript("OnClick", function()
            if MVal("centerTextContent", "none") == "none" then return end
            MSet("centerTextClassColor", true); EllesmereUI:RefreshPage()
        end)
        classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
        classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local swGet = function()
            return MVal("centerTextColorR", 1), MVal("centerTextColorG", 1), MVal("centerTextColorB", 1)
        end
        local swSet = function(r, g, b)
            settingsTable.centerTextColorR = r; settingsTable.centerTextColorG = g; settingsTable.centerTextColorB = b
            ReloadAndUpdate()
        end
        local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
        PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
        rgn._lastInline = sw
        local origClick = sw:GetScript("OnClick")
        sw:SetScript("OnClick", function(self, ...)
            if MVal("centerTextContent", "none") == "none" then return end
            if MVal("centerTextClassColor", false) then
                MSet("centerTextClassColor", false); EllesmereUI:RefreshPage(); return
            end
            if origClick then origClick(self, ...) end
        end)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdSwatches()
            local isNone = MVal("centerTextContent", "none") == "none"
            local isClass = MVal("centerTextClassColor", false)
            sw:SetAlpha((isClass or isNone) and 0.3 or 1)
            classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
        UpdSwatches()

        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return MVal("centerTextContent", "none") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Center Text Settings",
            rows = ns.UF_NameFormatRows("centerText", "none", MVal, MSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return MVal("centerTextSize", settingsTable.textSize or 12) end,
                  set=function(v) MSet("centerTextSize", v) end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return MVal("centerTextX", 0) end,
                  set=function(v) MSet("centerTextX", v) end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return MVal("centerTextY", 0) end,
                  set=function(v) MSet("centerTextY", v) end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return MVal("centerTextWidthPct", 100) end,
                  set=function(v) MSet("centerTextWidthPct", v) end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = MVal("centerTextContent","none") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = MVal("centerTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) MSet("centerTextTargetSepColor", { r=r, g=g, b=b }) end,
                      onClick = function(self)
                          if MVal("centerTextTargetSepClassColor", false) then
                              MSet("centerTextTargetSepClassColor", false)
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return MVal("centerTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() MSet("centerTextTargetSepClassColor", true) end,
                      refreshAlpha = function() return MVal("centerTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return MVal("centerTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      MSet("centerTextTargetSep", v)
                  end,
                  disabled=function() return MVal("centerTextContent","none") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return MVal("centerTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      MSet("centerTextTargetPrefix", v)
                  end,
                  disabled=function() return MVal("centerTextContent","none") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Inline color swatches + cog on Extra Text (boss only, Center row right
    -- region). Same pattern as Center Text above; the cog adds Alignment
    -- (the Extra Text zone's distinguishing setting, as on Main Frames).
    if unitKey == "boss" and not EllesmereUI._prebuilding then
        local rgn = centerRow._rightRegion
        local classSw, classSwUp = EllesmereUI.BuildColorSwatch(
            rgn, rgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(classSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        classSw:SetScript("OnClick", function()
            if MVal("extraTextContent", "none") == "none" then return end
            MSet("extraTextClassColor", true); EllesmereUI:RefreshPage()
        end)
        classSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSw, "Class Colored") end)
        classSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local swGet = function()
            return MVal("extraTextColorR", 1), MVal("extraTextColorG", 1), MVal("extraTextColorB", 1)
        end
        local swSet = function(r, g, b)
            settingsTable.extraTextColorR = r; settingsTable.extraTextColorG = g; settingsTable.extraTextColorB = b
            ReloadAndUpdate()
        end
        local sw, swUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, nil, 20)
        PP.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
        rgn._lastInline = sw
        local swOrigClick = sw:GetScript("OnClick")
        sw:SetScript("OnClick", function(self, ...)
            if MVal("extraTextContent", "none") == "none" then return end
            if MVal("extraTextClassColor", false) then
                MSet("extraTextClassColor", false); EllesmereUI:RefreshPage(); return
            end
            if swOrigClick then swOrigClick(self, ...) end
        end)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Custom Colored") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdSwatches()
            local isNone = MVal("extraTextContent", "none") == "none"
            local isClass = MVal("extraTextClassColor", false)
            sw:SetAlpha((isClass or isNone) and 0.3 or 1)
            classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() swUp(); classSwUp(); UpdSwatches() end)
        UpdSwatches()

        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() return MVal("extraTextContent", "none") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Extra Text Settings",
            rows = ns.UF_NameFormatRows("extraText", "none", MVal, MSet, {
                { type="dropdown", label="Alignment",
                  values={ ["left"]="Left", ["right"]="Right", ["center"]="Center" }, order={ "left", "right", "center" },
                  get=function() return MVal("extraTextAlign", "left") end,
                  set=function(v) MSet("extraTextAlign", v) end },
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return MVal("extraTextSize", settingsTable.textSize or 12) end,
                  set=function(v) MSet("extraTextSize", v) end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return MVal("extraTextX", 0) end,
                  set=function(v) MSet("extraTextX", v) end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return MVal("extraTextY", 0) end,
                  set=function(v) MSet("extraTextY", v) end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return MVal("extraTextWidthPct", 100) end,
                  set=function(v) MSet("extraTextWidthPct", v) end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = MVal("extraTextContent","none") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = MVal("extraTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) MSet("extraTextTargetSepColor", { r=r, g=g, b=b }) end,
                      onClick = function(self)
                          if MVal("extraTextTargetSepClassColor", false) then
                              MSet("extraTextTargetSepClassColor", false)
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return MVal("extraTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() MSet("extraTextTargetSepClassColor", true) end,
                      refreshAlpha = function() return MVal("extraTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return MVal("extraTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      MSet("extraTextTargetSep", v)
                  end,
                  disabled=function() return MVal("extraTextContent","none") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return MVal("extraTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      MSet("extraTextTargetPrefix", v)
                  end,
                  disabled=function() return MVal("extraTextContent","none") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Blizzard Style: the stock level number in the boss art's level circle
    -- (the small frames' stock art carries none), with its size and
    -- offsets on a cog. The row is the preview level text's click target
    -- (stashed on the page: the boss targets table reads it).
    if unitKey == "boss" and EllesmereUI.BlizzStyle.Get("unitframes") then
        parent._ufLevelRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Level",
              tooltip="Shows the unit's level in the frame's level circle, as the default UI does.",
              getValue=function() return settingsTable.blizzShowLevel ~= false end,
              setValue=function(v) settingsTable.blizzShowLevel = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
            { type="label", text="" });  y = y - h
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(parent._ufLevelRow._leftRegion, {
                disabled = function() return settingsTable.blizzShowLevel == false end,
                disabledTooltip = "This option requires Show Level.",
                title = "Level Text Settings",
                rows = {
                    -- The size follows the name text until set here.
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return MVal("blizzLevelSize", MVal("leftTextSize", settingsTable.textSize or 12)) end,
                      set=function(v) MSet("blizzLevelSize", v) end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return MVal("blizzLevelX", 0) end,
                      set=function(v) MSet("blizzLevelX", v) end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return MVal("blizzLevelY", 0) end,
                      set=function(v) MSet("blizzLevelY", v) end },
                    { type="toggle", label="Difficulty Color",
                      tooltip="Colors an attackable unit's level by difficulty, as the default UI does.",
                      get=function() return MVal("blizzLevelDifficultyColor", true) end,
                      set=function(v) MSet("blizzLevelDifficultyColor", v) end },
                },
            })
        end
    end

    -- POWER BAR section (mini units with a power bar: boss, and the pet on WoW Forever).
    -- Fill always uses the unit's power color (powerPercentPowerColor default on);
    -- a height of 0 effectively hides the bar.
    if opts.hasPowerBar then
        local powerHeader
        powerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

        -- Row 1: Power Bar Height (+ Reverse Fill cog) | Above Health Bar toggle
        local pwrRow1
        pwrRow1, h = W:DualRow(parent, y,
            -- Blizzard Style: the stock track fixes height and spot; the
            -- Reverse Fill cog on this slot keeps working (keepRow).
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Power Bar Height", min=0, max=100, step=1,
              getValue=function() return MVal("powerHeight", 6) end,
              setValue=function(v) MSet("powerHeight", v) end }, true),
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle", text="Above Health Bar",
              getValue=function() return MVal("powerPosition", "below") == "above" end,
              setValue=function(v) MSet("powerPosition", v and "above" or "below") end }));  y = y - h
        -- Expose the Power Bar Height row + POWER BAR header so the boss
        -- preview's power-bar click overlay can scroll here.
        parent._powerHeaderFrame = powerHeader
        parent._powerHeightRow = pwrRow1
        -- Reverse Fill cog on Power Bar Height (left) -- mirrors Main Frames.
        if not EllesmereUI._prebuilding then
            local rgn = pwrRow1._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Power Bar Fill",
                rows = {
                    { type="toggle", label="Reverse Fill",
                      get=function() return MVal("powerReverseFill", false) end,
                      set=function(v) MSet("powerReverseFill", v) end },
                },
            })
        end

        -- Row 2: Bar Background (opacity slider + power/custom bg swatches) |
        -- Fill Color (opacity slider + power/custom fill swatches). Mirrors the
        -- Main Frames power bar; the opacity sliders replace the old plain ones.
        local pwrRow2
        pwrRow2, h = W:DualRow(parent, y,
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return MVal("customPowerBgAlpha", 100) end,
              setValue=function(v) MSet("customPowerBgAlpha", v) end },
            { type="slider", text="Fill Color", min=0, max=100, step=1,
              getValue=function() return MVal("powerBarOpacity", 100) end,
              setValue=function(v) MSet("powerBarOpacity", v) end });  y = y - h
        -- Inline Power Colored + Custom background swatches on Bar Background
        -- (left region); both toggle powerBgPowerColored, the inactive one
        -- dims to 0.3 (mirrors the Main Frames power Bar Background).
        if not EllesmereUI._prebuilding then
            local rgn = pwrRow2._leftRegion
            local bgPwrGet = function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                return info.r * f, info.g * f, info.b * f
            end
            local bgPwrSw, bgPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgPwrGet, function() end, false, 20)
            bgPwrSw._eabOrigClick = bgPwrSw:GetScript("OnClick")
            bgPwrSw:SetScript("OnClick", function()
                settingsTable.powerBgPowerColored = true
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end)
            bgPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSw, "Power Colored Background. Power colors can be adjusted in Global Settings -> Colors.") end)
            bgPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgPwrSw
            RegisterWidgetRefresh(function()
                bgPwrUpdate()
                bgPwrSw:SetAlpha(MVal("powerBgPowerColored", false) and 1 or 0.3)
            end)
            bgPwrSw:SetAlpha(MVal("powerBgPowerColored", false) and 1 or 0.3)

            local bgGet = function()
                local c = MGet("customPowerBgColor")
                if c then return c.r, c.g, c.b end
                return 17/255, 17/255, 17/255
            end
            local bgSet = function(r, g, b)
                settingsTable.customPowerBgColor = { r=r, g=g, b=b }
                ReloadAndUpdate()
            end
            local bgSw, bgSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgGet, bgSet, false, 20)
            bgSw._eabOrigClick = bgSw:GetScript("OnClick")
            bgSw:SetScript("OnClick", function(self)
                if MVal("powerBgPowerColored", false) then
                    settingsTable.powerBgPowerColored = false
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            bgSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSw, "Custom Background Color") end)
            bgSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = bgSw
            RegisterWidgetRefresh(function()
                bgSwUp()
                bgSw:SetAlpha(MVal("powerBgPowerColored", false) and 0.3 or 1)
            end)
            bgSw:SetAlpha(MVal("powerBgPowerColored", false) and 0.3 or 1)
        end
        -- Inline Power Colored + Custom fill swatches on Fill Color (right
        -- region); both toggle powerPercentPowerColor (default on = power
        -- colored), the inactive one dims to 0.3.
        if not EllesmereUI._prebuilding then
            local rgn = pwrRow2._rightRegion
            local fPwrGet = function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                return info.r, info.g, info.b
            end
            local fPwrSw, fPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fPwrGet, function() end, false, 20)
            fPwrSw._eabOrigClick = fPwrSw:GetScript("OnClick")
            fPwrSw:SetScript("OnClick", function()
                settingsTable.powerPercentPowerColor = true
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end)
            fPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fPwrSw, "Power Colored Fill. Power colors can be adjusted in Global Settings -> Colors.") end)
            fPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(fPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = fPwrSw
            RegisterWidgetRefresh(function()
                fPwrUpdate()
                fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)
            end)
            fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)

            local fGet = function()
                local c = MGet("customPowerFillColor")
                if c then return c.r, c.g, c.b end
                return 0, 0, 1
            end
            local fSet = function(r, g, b)
                settingsTable.customPowerFillColor = { r=r, g=g, b=b }
                ReloadAndUpdate()
            end
            local fSw, fSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, fGet, fSet, false, 20)
            fSw._eabOrigClick = fSw:GetScript("OnClick")
            fSw:SetScript("OnClick", function(self)
                if MVal("powerPercentPowerColor", true) ~= false then
                    settingsTable.powerPercentPowerColor = false
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            fSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fSw, "Custom Colored Fill") end)
            fSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            PP.Point(fSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = fSw
            RegisterWidgetRefresh(function()
                fSwUp()
                fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
            end)
            fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
        end

        -- Row 3: Power Text (format) + Text Position -- ported from Main Frames.
        -- Reads/writes the same per-unit keys; MSet -> ReloadAndUpdate live-updates
        -- the real boss frames AND the preview (runtime already supports boss).
        local pwrTextRow
        pwrTextRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Power Text",
              values = { ["none"]="None", ["smart"]="Smart Text", ["curpp"]="Power Value", ["perpp"]="Power %", ["both"]="Value | %" },
              order  = { "none", "smart", "curpp", "perpp", "both" },
              getValue=function() return MVal("powerTextFormat", "perpp") end,
              setValue=function(v)
                  settingsTable.powerTextFormat = v
                  if v ~= "none" and MVal("powerPercentText", "none") == "none" then
                      settingsTable.powerPercentText = "center"
                  end
                  if v == "none" then settingsTable.powerPercentText = "none" end
                  ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Text Position",
              values = { ["none"]="None", ["left"]="Left", ["right"]="Right", ["center"]="Center" },
              order  = { "none", "---", "left", "right", "center" },
              getValue=function() return MVal("powerPercentText", "none") end,
              setValue=function(v) MSet("powerPercentText", v); EllesmereUI:RefreshPage() end });  y = y - h
        -- Expose the power-text row so the preview's power-text click overlay
        -- can scroll here (mirrors parent._powerHeightRow / _powerHeaderFrame).
        parent._powerTextRow = pwrTextRow
        -- Inline Text Color swatches on Power Text (left): Custom + Power Colored,
        -- mutually exclusive (mirrors Main Frames' Text Color multiSwatch). Custom
        -- click: first clears power-colored (selecting custom), second opens the
        -- picker. Power-colored click: selects power-colored + clears custom.
        if not EllesmereUI._prebuilding then
            local rgn = pwrTextRow._leftRegion
            local customSw, customSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local c = MGet("powerTextColor")
                    if c then return c.r, c.g, c.b end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    settingsTable.powerTextColor = { r=r, g=g, b=b }
                    ReloadAndUpdate()
                end, false, 20)
            PP.Point(customSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = customSw
            local customOrigClick = customSw:GetScript("OnClick")
            customSw:SetScript("OnClick", function(self, ...)
                if MVal("powerPercentTextPowerColor", false) then
                    settingsTable.powerPercentTextPowerColor = false
                    ReloadAndUpdate(); EllesmereUI:RefreshPage(); return
                end
                if customOrigClick then customOrigClick(self, ...) end
            end)
            customSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSw, "Custom Text Color") end)
            customSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local powerSw, powerSwUp = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    if info then return info.r, info.g, info.b end
                    return 1, 1, 1
                end,
                function() end, false, 20)
            PP.Point(powerSw, "RIGHT", customSw, "LEFT", -8, 0)
            rgn._lastInline = powerSw
            powerSw:SetScript("OnClick", function()
                settingsTable.powerPercentTextPowerColor = true
                settingsTable.powerTextColor = nil
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end)
            powerSw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(powerSw, "Power Colored Text") end)
            powerSw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdSwatches()
                local isPower = MVal("powerPercentTextPowerColor", false)
                customSw:SetAlpha(isPower and 0.3 or 1)
                powerSw:SetAlpha(isPower and 1 or 0.3)
            end
            RegisterWidgetRefresh(function() customSwUp(); powerSwUp(); UpdSwatches() end)
            UpdSwatches()
        end
        -- Show % cog on Power Text (left)
        if not EllesmereUI._prebuilding then
            local rgn = pwrTextRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = function() local fmt = MVal("powerTextFormat", "perpp"); return fmt == "none" or fmt == "curpp" end,
                disabledTooltip = "This option is only available for formats that display a percentage.",
                title = "Power Text",
                rows = {
                    { type="toggle", label="Show %",
                      get=function() return MVal("powerShowPercent", true) ~= false end,
                      set=function(v) MSet("powerShowPercent", v) end },
                },
            })
        end
        -- Size + X/Y offsets cog on Text Position (right)
        if not EllesmereUI._prebuilding then
            local rgn = pwrTextRow._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.RESIZE_ICON,
                disabled = function() return MVal("powerPercentText", "none") == "none" end,
                disabledTooltip = "This option requires a text position other than none.",
                title = "Text Position",
                rows = {
                    { type="slider", label="Size", min=6, max=100, step=1,
                      get=function() return MVal("powerPercentSize", 9) end,
                      set=function(v) MSet("powerPercentSize", v) end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return MVal("powerPercentX", 0) end,
                      set=function(v) MSet("powerPercentX", v) end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return MVal("powerPercentY", 0) end,
                      set=function(v) MSet("powerPercentY", v) end },
                },
            })
        end

        -- Power bar border size and color, matching Player/Target/Focus.
        local pwrBorderRow
        pwrBorderRow, h = W:DualRow(parent, y,
            { type="slider", text="Border Size", min=0, max=4, step=1, trackWidth=120,
              getValue=function() return MVal("powerBorderSize", 0) end,
              setValue=function(v) MSet("powerBorderSize", v) end },
            { type="label", text="" });  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = pwrBorderRow._leftRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, pwrBorderRow:GetFrameLevel() + 3,
                function()
                    local c = MGet("powerBorderColor") or { r=0, g=0, b=0 }
                    return c.r, c.g, c.b, MVal("powerBorderAlpha", 1)
                end,
                function(r, g, b, a)
                    settingsTable.powerBorderColor = { r=r, g=g, b=b }
                    settingsTable.powerBorderAlpha = a
                    ReloadAndUpdate()
                end,
                true, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
            swatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, "Border Color")
            end)
            swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            rgn._lastInline = swatch
            RegisterWidgetRefresh(updateSwatch)
        end
    end

    -- Extra section rendered at the very bottom, below the Power Bar (boss "Indicators").
    if opts.afterPowerRow then
        y = opts.afterPowerRow(W, parent, y)
    end

    return y, displayHeader, sizeRow, textHeader, textRow, enableRowFrame
end

-- Inline "Portrait on Right" cog attached to a Show Portrait toggle
-- region. Clicking the cog opens a popup with a toggle that swaps
-- settings.portraitSide between "left" and "right" live; withArtStyle
-- (Target of Target / Focus Target) adds the 2D / Class art choice.
local function AttachPortraitSideCog(rgn, settingsTable, withArtStyle, unitKey)
    local env = ns._UFO_OptEnv
    local ReloadAndUpdate, UpdatePreview, classThemeSubOrder, classThemeSubValues = env.ReloadAndUpdate, env.UpdatePreview, env.classThemeSubOrder, env.classThemeSubValues
    local _, portraitShow
    local rows = {
        { type="toggle", label="Portrait on Right",
          get=function() return (settingsTable.portraitSide or "left") == "right" end,
          set=function(v)
              settingsTable.portraitSide = v and "right" or "left"
              ReloadAndUpdate(); UpdatePreview()
          end },
    }
    if withArtStyle then
        rows[#rows + 1] = { type="dropdown", label="Art Style",
            values={ ["2d"] = "2D Portrait", ["class"] = "Class" }, order={ "2d", "class" },
            get=function() return settingsTable.portraitMode == "class" and "class" or "2d" end,
            set=function(v)
                local function ApplyArt()
                    settingsTable.portraitMode = v
                    ReloadAndUpdate(); UpdatePreview()
                end
                if v == "2d" and settingsTable.portraitMode == "class"
                    and settingsTable.portraitMirror and not EllesmereUI.BlizzStyle.Get("unitframes")
                    and ns.UF_Ask2DMirroredPortraits(function()
                        ApplyArt()
                        EllesmereUI:RefreshPage()
                    end) then
                    if portraitShow and portraitShow._popupFrame then portraitShow._popupFrame:Hide() end
                    return
                end
                ApplyArt()
            end }
        rows[#rows + 1] = { type="dropdown", label="Class Style",
            values=classThemeSubValues, order=classThemeSubOrder,
            get=function() return settingsTable.classThemeStyle or "modern" end,
            set=function(v)
                settingsTable.classThemeStyle = v
                ReloadAndUpdate(); UpdatePreview()
            end,
            disabled=function() return settingsTable.portraitMode ~= "class" end,
            disabledTooltip="This option requires Art Style to be set to Class", rawTooltip=true }
        -- The Non-Player Portrait opt-in and its choice, as on the main frames.
        rows[#rows + 1] = { type="toggle", label="Custom Non-Player Portrait",
            tooltip="Pick what NPCs show in Class art instead of their 2D portrait.",
            get=function() return settingsTable.portraitNonPlayerOn == true end,
            set=function(v)
                settingsTable.portraitNonPlayerOn = v or nil
                ReloadAndUpdate()
            end }
        -- No 3D here: a mini frame's fade never reaches a model (the
        -- runtime resolves a saved "3d" to 2D the same way).
        rows[#rows + 1] = { type="dropdown", label="Non-Player Portrait",
            values={ ["2d"] = "2D Portrait", ["none"] = "Nothing" }, order={ "2d", "none" },
            get=function() return settingsTable.portraitNonPlayer == "none" and "none" or "2d" end,
            set=function(v)
                settingsTable.portraitNonPlayer = v
                ReloadAndUpdate()
            end,
            disabled=function()
                return settingsTable.portraitMode ~= "class" or not settingsTable.portraitNonPlayerOn
            end,
            disabledTooltip=function()
                if settingsTable.portraitMode ~= "class" then
                    return "This option requires Art Style to be set to Class"
                end
                return "Custom Non-Player Portrait"
            end }
    end
    if unitKey == "targettarget" or unitKey == "boss" then
        rows[#rows + 1] = { type="toggle", label="Mirror Portrait",
            tooltip="Mirrors playable-race portraits in 2D. Always flips class art horizontally.",
            disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
            disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
            requireState="disabled",
            get=function() return settingsTable.portraitMirror == true end,
            set=function(v)
                local function ApplyMirror()
                    settingsTable.portraitMirror = v or nil
                    ns.UF_RefreshPortraitMirror(unitKey)
                    UpdatePreview()
                end
                if v and not settingsTable.portraitMirror and settingsTable.portraitMode ~= "3d"
                    and settingsTable.portraitMode ~= "class"
                    and ns.UF_Ask2DMirroredPortraits(function()
                        ApplyMirror()
                        EllesmereUI:RefreshPage()
                    end) then
                    if portraitShow and portraitShow._popupFrame then portraitShow._popupFrame:Hide() end
                    return
                end
                ApplyMirror()
            end }
        rows[#rows + 1] = { type="toggle", label="Vertical Border Separator",
            tooltip="Draws the selected border style between the attached portrait and the bars.",
            disabled=function()
                local donor = unitKey == "boss" and ns.UF_BossBorderSettings() or GetMiniDonorSettings(unitKey)
                return EllesmereUI.BlizzStyle.Get("unitframes") or (settingsTable.borderSizeOverride or donor.borderSize or 1) <= 0
                    or not EllesmereUI.GetBorderCompanion(donor.borderTexture or "solid", "sepV")
            end,
            disabledTooltip=function()
                if EllesmereUI.BlizzStyle.Get("unitframes") then return EllesmereUI.BlizzStyle.Label("unitframes") end
                return "This option requires a border style with divider art and a Border Size above 0."
            end,
            rawTooltip=true,
            get=function() return settingsTable.portraitSeparator == true end,
            set=function(v)
                settingsTable.portraitSeparator = v or nil
                ReloadAndUpdate(); UpdatePreview()
            end }
    end
    _, portraitShow = EllesmereUI.BuildInlineCog(rgn, {
        gap = 9,
        title = "Portrait Settings",
        -- Side and art only show on a shown portrait (the stock styles
        -- always show one); the Show Portrait setters refresh this state.
        disabled = function()
            return settingsTable.showPortrait == false and not EllesmereUI.BlizzStyle.Get("unitframes")
        end,
        disabledTooltip = "Show Portrait",
        rows = rows,
    })
end

-- Shared builder for the two independent mini frames (Target of Target,
-- Focus Target). settingsTable/unitKey select which one; each renders its
-- own single enable toggle + Show Portrait (right slot), Pet-style.
function ns.UFO_BuildFoTToTOptions(W, parent, y, settingsTable, unitKey)
    local env = ns._UFO_OptEnv
    local AttachFrameSourceCog, BuildApplyAllRow, MINI_GROUP_ORDER, PromptReloadIfUnspawned = env.AttachFrameSourceCog, env.BuildApplyAllRow, env.MINI_GROUP_ORDER, env.PromptReloadIfUnspawned
    local ReloadAndUpdate, abs, db = env.ReloadAndUpdate, env.abs, env.db
    settingsTable = settingsTable or db.profile.targettarget
    unitKey = unitKey or "targettarget"
    local enableText = (unitKey == "focustarget") and "Enable Focus Target" or "Enable Target of Target"
    local _, h

    _, h = BuildApplyAllRow(parent, y, MINI_GROUP_ORDER, unitKey, true); y = y - h

    local portraitRow
    local function enableRow(Ww, pp, yy)
        local isEUI = ns.GetUnitFrameSource(unitKey) == "eui"
        -- The Frame Source cog's "Blizzard Default" only makes sense when the
        -- parent target/focus frame is itself on Blizzard's frame (its native
        -- child target-of-target is then alive; see ns.GetUnitFrameSource);
        -- the cog's dropdown is blocked otherwise with an explanation.
        local parentLabel = (unitKey == "focustarget") and "Focus" or "Target"
        local parentKey = (unitKey == "focustarget") and "focus" or "target"
        local childName = (unitKey == "focustarget") and "focus-target" or "target-of-target"
        portraitRow, h = Ww:DualRow(pp, yy,
            { type="toggle", text=enableText,
              getValue=function() return db.profile.enabledFrames[unitKey] ~= false end,
              setValue=function(v)
                db.profile.enabledFrames[unitKey] = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage(true)
                PromptReloadIfUnspawned({ unitKey })
              end },
            isEUI and EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle", text="Show Portrait",
              getValue=function() return EllesmereUI.BlizzStyle.Get("unitframes") or settingsTable.showPortrait ~= false end,
              setValue=function(v)
                settingsTable.showPortrait = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage()
              end }) or { type="label", text="" })
        if isEUI and not EllesmereUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, settingsTable, true, unitKey)
        end
        AttachFrameSourceCog(portraitRow._leftRegion, unitKey, {
            tooltip = "Due to Blizzard API restrictions, Blizzard's native " .. childName
                .. " can't be hidden in combat and will show the whole time you are in combat. Recommended: match the "
                .. parentLabel .. " frame's source -- both Blizzard Default, or both EllesmereUI.",
            disabled = function() return ns.GetUnitFrameSource(parentKey) ~= "blizzard" end,
            disabledTooltip = "\"Blizzard Default\" is only available when the " .. parentLabel
                .. " frame's source is set to Blizzard Default -- the " .. childName
                .. " then comes from Blizzard's " .. parentKey .. " frame.",
        })
        return portraitRow, h
    end

    local displayHeader, sizeRow, textHeader, textRow
    y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, settingsTable, unitKey, enableRow)

    -- Store click targets for hover highlight system
    parent._ufClickTargets = {
        healthBar  = { section = displayHeader,  target = sizeRow },
        portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
        nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
    }

    return abs(y)
end

function ns.UFO_BuildPetOptions(W, parent, y)
    local env = ns._UFO_OptEnv
    local AttachFrameSourceCog, BuildApplyAllRow, MINI_GROUP_ORDER, PromptReloadIfUnspawned = env.AttachFrameSourceCog, env.BuildApplyAllRow, env.MINI_GROUP_ORDER, env.PromptReloadIfUnspawned
    local ReloadAndUpdate, UpdatePreview, abs, db = env.ReloadAndUpdate, env.UpdatePreview, env.abs, env.db
    local _, h

    _, h = BuildApplyAllRow(parent, y, MINI_GROUP_ORDER, "pet", true); y = y - h

    local portraitRow
    local function enableRow(Ww, pp, yy)
        local isEUI = ns.GetUnitFrameSource("pet") == "eui"
        portraitRow, h = Ww:DualRow(pp, yy,
            { type="toggle", text="Enable Pet Frame",
              getValue=function() return db.profile.enabledFrames.pet ~= false end,
              setValue=function(v)
                db.profile.enabledFrames.pet = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "pet" })
              end },
            isEUI and EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle", text="Show Portrait",
              getValue=function() return EllesmereUI.BlizzStyle.Get("unitframes") or db.profile.pet.showPortrait ~= false end,
              setValue=function(v)
                db.profile.pet.showPortrait = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage()
              end }) or { type="label", text="" })
        if isEUI and not EllesmereUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, db.profile.pet)
        end
        AttachFrameSourceCog(portraitRow._leftRegion, "pet", {
            extraRows = {
                { type = "toggle", label = "Always Show Pet Frame",
                  tooltip = "Show the pet frame whenever you have a pet, ignoring the Player frame's visibility settings.",
                  get = function() return db.profile.pet.alwaysShow == true end,
                  set = function(v)
                      db.profile.pet.alwaysShow = v and true or nil
                      if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  end },
            },
        })
        return portraitRow, h
    end

    -- WoW Forever: the pet has power (its POWER BAR section exists in the
    -- EUI look only; the stock styles paint their own stock bar) and
    -- hunter pets track happiness (PET HAPPINESS, below the power bar).
    -- Retail builds neither.
    local petOpts, petPower, happyHeader, happyRow
    if EllesmereUI.IS_FOREVER == true then
        petPower = ns.UF_PetHasPower and not EllesmereUI.BlizzStyle.Get("unitframes")
        local P = db.profile.pet
        local function happyOff() return P.happinessEnabled == false end
        -- The live icon repaints itself; the preview mirrors it.
        local function happyApply() ns.UF_ApplyPetHappiness(); UpdatePreview() end
        petOpts = { hasPowerBar = petPower, afterPowerRow = function(Ww, pp, yy)
            local hh
            happyHeader, hh = Ww:SectionHeader(pp, "PET HAPPINESS", yy);  yy = yy - hh

            -- Row 1: Show Happiness | Size
            happyRow, hh = Ww:DualRow(pp, yy,
                { type="toggle", text="Show Happiness",
                  tooltip="Shows your hunter pet's happiness beside the pet frame.",
                  getValue=function() return P.happinessEnabled ~= false end,
                  setValue=function(v)
                      P.happinessEnabled = v
                      happyApply()
                      EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Size", min=10, max=64, step=1,
                  disabled=happyOff, disabledTooltip="Show Happiness",
                  getValue=function() return P.happinessSize or 20 end,
                  setValue=function(v) P.happinessSize = v; happyApply() end });  yy = yy - hh

            -- Row 2: Position (+ offsets cog) | blank (odd last slot)
            local posRow
            posRow, hh = Ww:DualRow(pp, yy,
                { type="dropdown", text="Position",
                  values={ left="Left", right="Right", top="Top" }, order={ "left", "right", "top" },
                  disabled=happyOff, disabledTooltip="Show Happiness",
                  getValue=function() return P.happinessAlign or "right" end,
                  setValue=function(v) P.happinessAlign = v; happyApply() end },
                EllesmereUI.BlankRowCfg());  yy = yy - hh
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(posRow._leftRegion, {
                    icon = EllesmereUI.DIRECTIONS_ICON,
                    disabled = happyOff, disabledTooltip = "Show Happiness",
                    title = "Happiness Position",
                    rows = {
                        { type="slider", label="X Offset", min=-100, max=100, step=1,
                          get=function() return P.happinessX or 0 end,
                          set=function(v) P.happinessX = v; happyApply() end },
                        { type="slider", label="Y Offset", min=-100, max=100, step=1,
                          get=function() return P.happinessY or 0 end,
                          set=function(v) P.happinessY = v; happyApply() end },
                    },
                })
            end
            return yy
        end }
    end

    local displayHeader, sizeRow, textHeader, textRow
    y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.pet, "pet", enableRow, nil, petOpts)

    -- Store click targets for hover highlight system
    parent._ufClickTargets = {
        healthBar  = { section = displayHeader,  target = sizeRow },
        portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
        nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
    }
    -- WoW Forever: the preview's power bar, power text and happiness icon
    -- (only once the sections exist: an inactive frame builds none).
    if happyRow then
        local tg = parent._ufClickTargets
        if petPower then
            tg.powerBar     = { section = parent._powerHeaderFrame, target = parent._powerHeightRow, slotSide = "left" }
            tg.powerBarText = { section = parent._powerHeaderFrame, target = parent._powerTextRow, slotSide = "left" }
        end
        tg.petHappiness = { section = happyHeader, target = happyRow, slotSide = "left" }
    end

    return abs(y)
end

function ns.UFO_BuildBossOptions(W, parent, y)
    local env = ns._UFO_OptEnv
    local AttachDebuffModeWarn, AttachFrameSourceCog, DebuffModeDropdownCfg, PP = env.AttachDebuffModeWarn, env.AttachFrameSourceCog, env.DebuffModeDropdownCfg, env.PP
    local HideExhaustionRow = env.HideExhaustionRow
    local PromptReloadIfUnspawned, ReloadAndUpdate, SwapAuraSlot, abs = env.PromptReloadIfUnspawned, env.ReloadAndUpdate, env.SwapAuraSlot, env.abs
    local buffAnchorOrder, buffAnchorValues, buffGrowthOrder, buffGrowthValues = env.buffAnchorOrder, env.buffAnchorValues, env.buffGrowthOrder, env.buffGrowthValues
    local db = env.db
    local _, h

    -- Activate/Deactivate Boss Preview button (matches Party Mode's activate
    -- button, centered above the first section). Disabled while Boss Frames are
    -- off: the in-game preview rides on the real (now-disabled) boss frames and renders broken.
    local activateBtnFrame, activateBtnLbl, activateBtn
    local function PreviewLabel()
        return ns._bossPreviewActive and EllesmereUI.L("Deactivate Boss Preview") or EllesmereUI.L("Activate Boss Preview")
    end
    local function BossFramesDisabled()
        return ns.GetUnitFrameSource("boss") ~= "eui"
    end
    activateBtnFrame, h = W:WideButton(parent, PreviewLabel(), y, function()
        if BossFramesDisabled() then return end
        if not ns.SetBossPreview then return end
        ns.SetBossPreview(not ns._bossPreviewActive)
        if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
    end);  y = y - h
    do
        activateBtn = select(1, activateBtnFrame:GetChildren())
        if activateBtn then
            local regions = { activateBtn:GetRegions() }
            for i = 1, #regions do
                local rgn = regions[i]
                if rgn and rgn.GetText and rgn:GetText() then
                    activateBtnLbl = rgn; break
                end
            end
        end
    end
    local function UpdateActivateBtn()
        local off = BossFramesDisabled()
        if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
        if activateBtn then
            activateBtn:SetAlpha(off and 0.4 or 1)
            activateBtn:EnableMouse(not off)
        end
    end
    UpdateActivateBtn()
    EllesmereUI.RegisterWidgetRefresh(UpdateActivateBtn)

    -- Rows exposed as upvalues so the click-to-scroll targets (below) can point at
    -- them. growthRow holds Show Cast Icon + Cast Bar Height after the swap;
    -- simpleRow/simpleBuffRow/bossAuraRow + bossAuraHeader are the Buffs and Debuffs section rows.
    local portraitRow, growthRow, simpleRow, simpleBuffRow, bossAuraRow, bossAuraHeader, bossCastHeader, castMainRow
    local function enableRow(Ww, pp, yy)
        local isEUI = ns.GetUnitFrameSource("boss") == "eui"
        local eh
        portraitRow, eh = Ww:DualRow(pp, yy,
            { type="toggle", text="Enable Boss Frames",
              getValue=function() return db.profile.enabledFrames.boss ~= false end,
              setValue=function(v)
                db.profile.enabledFrames.boss = v
                -- Force-stop the in-game preview when disabling boss frames;
                -- it rides on the now-disabled frames and renders broken.
                if not v and ns._bossPreviewActive and ns.SetBossPreview then
                    ns.SetBossPreview(false)
                end
                -- Live apply on the spawned EUI frames (unit-watch register/
                -- unregister). Frames never spawned this session no-op here
                -- and hit the reload prompt below instead.
                if ns.UF_SetBossFramesActive then ns.UF_SetBossFramesActive(v) end
                ReloadAndUpdate()
                EllesmereUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "boss" })
              end },
            isEUI and EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle", text="Show Portrait",
              getValue=function() return EllesmereUI.BlizzStyle.Get("unitframes") or db.profile.boss.showPortrait ~= false end,
              setValue=function(v)
                db.profile.boss.showPortrait = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage()
              end }) or { type="label", text="" })
        if isEUI and not EllesmereUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, db.profile.boss, false, "boss")
        end
        AttachFrameSourceCog(portraitRow._leftRegion, "boss", {
            onBeforeSet = function(v)
                -- Force-stop the in-game preview when boss frames are no longer
                -- EUI-owned; it rides on the real boss frames and renders broken.
                if v ~= "eui" and ns._bossPreviewActive and ns.SetBossPreview then
                    ns.SetBossPreview(false)
                end
            end,
        })
        local total = eh
        if isEUI then
            local castRow, ch = Ww:DualRow(pp, yy - eh,
                { type="dropdown", text="Stack Direction", values={ up="Up", down="Down" }, order={ "up", "down" },
                  getValue=function() return db.profile.boss.bossStackDirection or "down" end,
                  setValue=function(v) db.profile.boss.bossStackDirection = v; ReloadAndUpdate() end },
                -- Top-to-top step; Stack Direction sets the side, so no negatives.
                { type="slider", pixel=true, text="Vertical Spacing", min=0, max=200, step=1,
                  getValue=function() return math.abs(db.profile.bossSpacing or 80) end,
                  setValue=function(v) db.profile.bossSpacing = v; ReloadAndUpdate() end })
            total = total + ch
        end
        return portraitRow, total
    end

    local function bossAfterSize(Ww, pp, yy)
        local _, hh
        -- BUFFS AND DEBUFFS section (below DISPLAY)
        bossAuraHeader, hh = Ww:SectionHeader(pp, "Buffs and Debuffs", yy);  yy = yy - hh

        -- Effective boss aura locations: Simple display overrides the stored
        -- location at runtime (dropdowns show None while active), so every
        -- disabled check must treat location as None whenever simple mode is on.
        -- Raw key checks deadlock: defaults hold simpleDebuffs="left" alongside
        -- debuffAnchor="bottomleft", locking BOTH the Simple dropdown (raw anchor not none) and the Location dropdown (simple active) at once.
        local function BossDebuffLocationActive()
            local s = db.profile.boss
            if ns.GetBossSimpleDebuffMode(s) ~= "none" then return false end
            return (s.debuffAnchor or "bottomleft") ~= "none"
        end
        local function BossBuffLocationActive()
            local s = db.profile.boss
            if ns.GetBossSimpleBuffMode(s) ~= "none" then return false end
            if s.showBuffs == false then return false end
            return (s.buffAnchor or "topleft") ~= "none"
        end
        -- Composite show-state of the two aura sizing rows (Buff/Debuff Size +
        -- Text Size). A row hides while its column's effective Location is None
        -- (Simple mode also reads as None; it has its own text/size controls). All
        -- four Location/Simple setters capture this BEFORE writing and force a full
        -- rebuild on change: any of them can flip EITHER row (collision pushes, SwapAuraSlot displacing the other anchor, simple forcing showBuffs/debuffAnchor).
        local function BossBuffRowShown()
            local p = db.profile.boss
            return ns.GetBossSimpleBuffMode(p) == "none" and p.showBuffs ~= false
        end
        local function BossDebuffRowShown()
            local p = db.profile.boss
            return ns.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") ~= "none"
        end
        local function BossAuraRowsState()
            return tostring(BossBuffRowShown()) .. "/" .. tostring(BossDebuffRowShown())
        end

        -- Simple Buff Display: identical to Simple Debuff Display above but for
        -- buffs. Defaults to None. Forces a single Left/Right column matched to
        -- the frame height, overriding Buffs Location + Buff Size while active.
        local simpleBuffTextOff = function()
            return BossBuffLocationActive()
            or ns.GetBossSimpleBuffMode(db.profile.boss) == "none"
            or not db.profile.boss.simpleBuffShowCooldownText
        end
        simpleBuffRow, hh = Ww:DualRow(pp, yy,
            { type="dropdown", text="Simple Buff Display",
              disabled = function()
                  return BossBuffLocationActive()
              end,
              disabledTooltip="Buffs Location", requireState="disabled",
              tooltip = "Force boss buffs into a single large column matched to the frame height.",
              values = { none = "None", left = "Left", right = "Right" },
              order = { "none", "left", "right" },
              getValue=function() return ns.GetBossSimpleBuffMode(db.profile.boss) end,
              setValue=function(v)
                  local prevState = BossAuraRowsState()
                  db.profile.boss.simpleBuffs = v
                  if v ~= "none" then
                      -- Same-side collision: if Simple Debuff Display occupies this
                      -- side, push it off (set to None) so they never overlap.
                      if ns.GetBossSimpleDebuffMode(db.profile.boss) == v then
                          db.profile.boss.simpleDebuffs = "none"
                      end
                      -- Selecting a side takes over from the normal Buffs
                      -- Location, so force that setting to None.
                      db.profile.boss.showBuffs = false
                  end
                  ReloadAndUpdate()
                  if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  if BossAuraRowsState() ~= prevState then
                      EllesmereUI:RefreshPage(true)
                  else
                      EllesmereUI:RefreshPage()
                  end
              end },
            { type="slider", text="Buff Text Size", min=6, max=100, step=1, trackWidth=120,
              disabled=simpleBuffTextOff, disabledTooltip="Show Duration (Inside Cog)",
              getValue=function() return db.profile.boss.simpleBuffCooldownTextSize or 14 end,
              setValue=function(v) db.profile.boss.simpleBuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh

        -- Directions cog on Simple Buff Display: the simple column's own X/Y
        -- offset (defaults to the regular buff offsets via ns.GetBossSimpleBuffOffset);
        -- writing here makes the simple offset independent. Disabled while None.
        if not EllesmereUI._prebuilding then
            local leftRgn = simpleBuffRow._leftRegion
            EllesmereUI.BuildInlineCog(leftRgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function() return ns.GetBossSimpleBuffMode(db.profile.boss) == "none" end,
                disabledTooltip = "Simple Buff Display",
                title = "Simple Buff Position",
                rows = {
                    -- Max buffs shown in simple mode. Shares the boss maxBuffs key
                    -- with Buffs Location (the two modes are mutually exclusive);
                    -- the runtime caps frame.Buffs.num to it.
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return db.profile.boss.maxBuffs or 4 end,
                      set=function(v) db.profile.boss.maxBuffs = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Shares the boss buffMaxPerRow key with Buffs Location
                    -- (mutually exclusive modes), like Max Count above.
                    { type="slider", label="Max Per Row", min=1, max=20, step=1,
                      get=function() return db.profile.boss.buffMaxPerRow or db.profile.boss.maxBuffs or 4 end,
                      set=function(v) db.profile.boss.buffMaxPerRow = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset X", min=-200, max=200, step=1,
                      get=function() local x = ns.GetBossSimpleBuffOffset(db.profile.boss); return x end,
                      set=function(v) db.profile.boss.simpleBuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() local _, y = ns.GetBossSimpleBuffOffset(db.profile.boss); return y end,
                      set=function(v) db.profile.boss.simpleBuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Physical-pixel-perfect gap between the simple buff icons.
                    { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                      get=function() return db.profile.boss.simpleBuffSpacing or 1 end,
                      set=function(v) db.profile.boss.simpleBuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                },
            })
        end

        -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
        do
            local rightRgn = simpleBuffRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Buff Text Size
            -- swatches (same keys); greyed + disabled on this row cog's condition.
            local buffOff = function() return BossBuffLocationActive() or ns.GetBossSimpleBuffMode(db.profile.boss) == "none" end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.buffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.buffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.buffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.buffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            EllesmereUI.BuildInlineCog(rightRgn, { disabled = buffOff, disabledTooltip = "Simple Buff Display",
                title = "Duration & Stack",
                rows = {
                    { type="toggle", label="Show Duration",
                      get=function() return db.profile.boss.simpleBuffShowCooldownText end,
                      set=function(v) db.profile.boss.simpleBuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="slider", label="Duration X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.simpleBuffCooldownTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.simpleBuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Duration Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.simpleBuffCooldownTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.simpleBuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Size", min=6, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextSize or 14 end,
                      set=function(v) db.profile.boss.buffStackTextSize = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Stack Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                      get=function() return db.profile.boss.buffStackTextPosition or "bottomright" end,
                      set=function(v) db.profile.boss.buffStackTextPosition = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.buffStackTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.buffStackTextOffsetY = v; ReloadAndUpdate() end },
                },
            })
        end
        -- (Show Duration toggle lives inside the Duration & Stack cog above.)

        -- Simple Debuff Display: forces Left anchor + debuff height =
        -- frame bar height so boss debuffs render as one large column.
        -- Row 1 slot 2 is "Simple Text Size": the cooldown-text size slider,
        -- gated by an inline Show-Cooldown-Text toggle, with an inline cog
        -- holding the stack size and stack X/Y position controls.
        
        local simpleTextOff = function()
            return BossDebuffLocationActive()
            or ns.GetBossSimpleDebuffMode(db.profile.boss) == "none"
            or not db.profile.boss.simpleDebuffShowCooldownText
        end
        simpleRow, hh = Ww:DualRow(pp, yy,
            { type="dropdown", text="Simple Debuff Display",
              disabled = function()
                  return BossDebuffLocationActive()
              end,
              disabledTooltip="Debuffs Location", requireState="disabled",
              tooltip = "Force boss debuffs into a single large column matched to the frame height.",
              values = { none = "None", left = "Left", right = "Right" },
              order = { "none", "left", "right" },
              getValue=function() return ns.GetBossSimpleDebuffMode(db.profile.boss) end,
              setValue=function(v)
                  local prevState = BossAuraRowsState()
                  db.profile.boss.simpleDebuffs = v
                  if v ~= "none" then
                      -- Same-side collision: if Simple Buff Display occupies this
                      -- side, push it off (set to None) so they never overlap.
                      if ns.GetBossSimpleBuffMode(db.profile.boss) == v then
                          db.profile.boss.simpleBuffs = "none"
                      end
                      -- Selecting a side takes over from the normal Debuffs
                      -- Location, so force that setting to None.
                      db.profile.boss.debuffAnchor = "none"
                  end
                  ReloadAndUpdate()
                  if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  if BossAuraRowsState() ~= prevState then
                      EllesmereUI:RefreshPage(true)
                  else
                      EllesmereUI:RefreshPage()
                  end
              end },
            { type="slider", text="Debuff Text Size", min=6, max=100, step=1, trackWidth=120,
              disabled=simpleTextOff, disabledTooltip="Show Duration (Inside Cog)",
              getValue=function() return db.profile.boss.simpleDebuffCooldownTextSize or 14 end,
              setValue=function(v) db.profile.boss.simpleDebuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh

        -- Directions cog on Simple Debuff Display: the simple column's own X/Y
        -- offset. Defaults to the regular debuff offsets for existing users
        -- (ns.GetBossSimpleDebuffOffset); writing here makes the simple offset
        -- independent. Disabled while Simple Debuff Display is None.
        if not EllesmereUI._prebuilding then
            local leftRgn = simpleRow._leftRegion
            EllesmereUI.BuildInlineCog(leftRgn, {
                icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function() return ns.GetBossSimpleDebuffMode(db.profile.boss) == "none" end,
                disabledTooltip = "Simple Debuff Display",
                title = "Simple Debuff Position",
                rows = {
                    -- Max debuffs shown in simple mode. Shares the boss maxDebuffs
                    -- key with Debuffs Location (the two modes are mutually
                    -- exclusive); the runtime caps frame.Debuffs.num to it.
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return db.profile.boss.maxDebuffs or 10 end,
                      set=function(v) db.profile.boss.maxDebuffs = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Shares the boss debuffMaxPerRow key with Debuffs Location
                    -- (mutually exclusive modes), like Max Count above.
                    { type="slider", label="Max Per Row", min=1, max=20, step=1,
                      get=function() return db.profile.boss.debuffMaxPerRow or db.profile.boss.maxDebuffs or 10 end,
                      set=function(v) db.profile.boss.debuffMaxPerRow = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset X", min=-200, max=200, step=1,
                      get=function() local x = ns.GetBossSimpleDebuffOffset(db.profile.boss); return x end,
                      set=function(v) db.profile.boss.simpleDebuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() local _, y = ns.GetBossSimpleDebuffOffset(db.profile.boss); return y end,
                      set=function(v) db.profile.boss.simpleDebuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Physical-pixel-perfect gap between the simple debuff icons.
                    { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                      get=function() return db.profile.boss.simpleDebuffSpacing or 1 end,
                      set=function(v) db.profile.boss.simpleDebuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                },
            })
        end

        -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
        if not EllesmereUI._prebuilding then
            local rightRgn = simpleRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Debuff Text
            -- Size swatches (same keys); greyed + disabled on this row cog's
            -- condition.
            local debuffOff = function() return BossDebuffLocationActive() or ns.GetBossSimpleDebuffMode(db.profile.boss) == "none" end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.debuffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.debuffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.debuffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.debuffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            EllesmereUI.BuildInlineCog(rightRgn, { disabled = debuffOff, disabledTooltip = "Simple Debuff Display",
                title = "Duration & Stack",
                rows = {
                    { type="toggle", label="Show Duration",
                      get=function() return db.profile.boss.simpleDebuffShowCooldownText end,
                      set=function(v) db.profile.boss.simpleDebuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="slider", label="Duration X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.simpleDebuffCooldownTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.simpleDebuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Duration Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.simpleDebuffCooldownTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.simpleDebuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Size", min=6, max=100, step=1,
                      get=function() return db.profile.boss.debuffStackTextSize or 14 end,
                      set=function(v) db.profile.boss.debuffStackTextSize = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Stack Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                      get=function() return db.profile.boss.debuffStackTextPosition or "bottomright" end,
                      set=function(v) db.profile.boss.debuffStackTextPosition = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.debuffStackTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.debuffStackTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.debuffStackTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.debuffStackTextOffsetY = v; ReloadAndUpdate() end },
                },
            })
        end
        -- (Show Duration toggle lives inside the Duration & Stack cog above.)

        bossAuraRow, hh = Ww:DualRow(pp, yy,
            { type="dropdown", text="Buffs Location", values=buffAnchorValues, order=buffAnchorOrder,
              disabled = function() return ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" end,
              disabledTooltip = "Simple Buff Display", requireState = "disabled",
              getValue=function()
                  local s = db.profile.boss
                  -- Forced to None while Simple Buff Display is active (it takes
                  -- over placement); the setter also stores None (showBuffs=false).
                  if ns.GetBossSimpleBuffMode(s) ~= "none" then return "none" end
                  if s.showBuffs == false then return "none" end
                  return s.buffAnchor or "topleft"
              end,
              setValue=function(v)
                  local prevState = BossAuraRowsState()
                  local s = db.profile.boss
                  if v == "none" then
                      s.showBuffs = false
                  else
                      s.showBuffs = true
                      SwapAuraSlot(s, "buffAnchor", v)
                  end
                  ReloadAndUpdate()
                  if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  if BossAuraRowsState() ~= prevState then
                      EllesmereUI:RefreshPage(true)
                  else
                      EllesmereUI:RefreshPage()
                  end
              end },
            { type="dropdown", text="Debuffs Location", values=buffAnchorValues, order=buffAnchorOrder,
              disabled = function() return ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" end,
              disabledTooltip = "Simple Debuff Display", requireState = "disabled",
              getValue=function()
                  -- Forced to None while Simple Debuff Display is active (it
                  -- takes over placement); the setter also stores None.
                  if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then return "none" end
                  return db.profile.boss.debuffAnchor or "bottomleft"
              end,
              setValue=function(v)
                  local prevState = BossAuraRowsState()
                  SwapAuraSlot(db.profile.boss, "debuffAnchor", v)
                  if db.profile.boss.buffAnchor == "none" then
                      db.profile.boss.showBuffs = false
                  end
                  ReloadAndUpdate()
                  if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  -- Full rebuild when either aura row's visibility flipped;
                  -- otherwise the fast refresh keeps dependent disabled
                  -- states (Boss Debuff Filter) current.
                  if BossAuraRowsState() ~= prevState then
                      EllesmereUI:RefreshPage(true)
                  else
                      EllesmereUI:RefreshPage()
                  end
              end });  yy = yy - hh

        -- Boss Buff Size | Debuff Size: icon size sliders, each with an inline
        -- DIRECTIONS cog holding the cluster X/Y offset; setters refresh live
        -- frames + both previews. Debuff Size (and its cog) disable while Simple
        -- Debuff Display frame-matches the size, or when no debuffs show at all (Simple None + Location None).
        local bossDebuffSizeOff = function()
            local p = db.profile.boss
            return ns.GetBossSimpleDebuffMode(p) ~= "none" or (p.debuffAnchor or "bottomleft") == "none"
        end
        -- Buff Size (and its directions cog) are disabled while Simple Buff
        -- Display frame-matches the size, or when buffs are hidden (Buffs
        -- Location None). Shared so the cog matches.
        local bossBuffSizeOff = function()
            local p = db.profile.boss
            return ns.GetBossSimpleBuffMode(p) ~= "none" or p.showBuffs == false
        end
        -- Buff Text Size gates on the "Show Duration" toggle inside its
        -- Duration & Stack cog (mirrors Debuff Text Size on the row below).
        local buffTextOff = function()
            return not BossBuffLocationActive()
            or not db.profile.boss.buffShowCooldownText
        end
        -- Buff Size | Buff Text Size row: HIDDEN entirely while the buff
        -- column's effective Location is None (see BossBuffRowShown; the
        -- dropdown setters above force the rebuild on flips).
        if BossBuffRowShown() then
        local bossAuraSizeRow
        bossAuraSizeRow, hh = Ww:DualRow(pp, yy,
            { type="slider", text="Buff Size", min=10, max=70, step=1,
              disabled=bossBuffSizeOff,
              disabledTooltip=function()
                  if ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" then
                      return EllesmereUI.DisabledTooltip("Simple Buff Display", "disabled")
                  end
                  return EllesmereUI.DisabledTooltip("Buffs Location")
              end,
              rawTooltip=true,
              getValue=function() return db.profile.boss.buffSize or 22 end,
              setValue=function(v)
                  db.profile.boss.buffSize = v; ReloadAndUpdate()
                  if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
              end },
            { type="slider", text="Buff Text Size", min=6, max=100, step=1, trackWidth=120,
              disabled=buffTextOff, disabledTooltip="Show Duration (Inside Cog)",
              getValue=function() return db.profile.boss.buffCooldownTextSize or 10 end,
              setValue=function(v) db.profile.boss.buffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh
        if not EllesmereUI._prebuilding then  -- Directions cog on Buff Size (X/Y cluster offset)
            EllesmereUI.BuildInlineCog(bossAuraSizeRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = bossBuffSizeOff, title = "Buff Position", rows = {
                { type="slider", label="Offset X", min=-200, max=200, step=1,
                  get=function() return db.profile.boss.buffOffsetX or 0 end,
                  set=function(v) db.profile.boss.buffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                { type="slider", label="Offset Y", min=-200, max=200, step=1,
                  get=function() return db.profile.boss.buffOffsetY or 0 end,
                  set=function(v) db.profile.boss.buffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                -- Physical-pixel-perfect gap between the boss buff icons.
                { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                  get=function() return db.profile.boss.buffSpacing or 1 end,
                  set=function(v) db.profile.boss.buffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
            } })
        end
        if not EllesmereUI._prebuilding then  -- Icon Zoom cog on Buff Size (gated only on buffs hidden, so it
            -- stays adjustable in Simple Buff Display, where zoom still applies)
            local bossBuffZoomOff = function() return db.profile.boss.showBuffs == false end
            EllesmereUI.BuildInlineCog(bossAuraSizeRow._leftRegion, { disabled = bossBuffZoomOff, disabledTooltip = "Buffs Location", title = "Icon Zoom", rows = {
                { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                  get=function() return db.profile.boss.buffIconZoom or 0.07 end,
                  set=function(v) db.profile.boss.buffIconZoom = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
            } })
        end
        -- Buff Text Size cog + swatches (right slot): Show Duration +
        -- Duration X/Y + Stack, with inline Duration/Stack text-color
        -- swatches; greyed on the same condition as the cog.
        if not EllesmereUI._prebuilding then
            local PP = EllesmereUI.PanelPP
            local rightRgn = bossAuraSizeRow._rightRegion
            local buffOff = function() return not BossBuffLocationActive() end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.buffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.buffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            do
                local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                    function() local c = db.profile.boss.buffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                    function(r, g, b) db.profile.boss.buffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                rightRgn._lastInline = sw
                local function apply() upd(); local o = buffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                apply(); EllesmereUI.RegisterWidgetRefresh(apply)
            end
            EllesmereUI.BuildInlineCog(rightRgn, { disabled = buffOff, disabledTooltip = "Buffs Location",
                title = "Duration & Stack",
                rows = {
                    { type="toggle", label="Show Duration",
                      get=function() return db.profile.boss.buffShowCooldownText end,
                      set=function(v) db.profile.boss.buffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="slider", label="Duration X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffCooldownTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.buffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Duration Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffCooldownTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.buffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Size", min=6, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextSize or 14 end,
                      set=function(v) db.profile.boss.buffStackTextSize = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Stack Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                      get=function() return db.profile.boss.buffStackTextPosition or "bottomright" end,
                      set=function(v) db.profile.boss.buffStackTextPosition = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack X", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextOffsetX or 0 end,
                      set=function(v) db.profile.boss.buffStackTextOffsetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Stack Y", min=-100, max=100, step=1,
                      get=function() return db.profile.boss.buffStackTextOffsetY or 0 end,
                      set=function(v) db.profile.boss.buffStackTextOffsetY = v; ReloadAndUpdate() end },
                },
            })
        end
        end   -- close buff sizing row hidden-while-None gate

        -- Per-unit aura filters for boss frames (NOT synced; boss1-5 share the
        -- one "boss" settings table). Debuff Filter = the single-select mode
        -- dropdown (DebuffModeDropdownCfg; per-spell control through Tracked
        -- Auras), Buff Filter = the two-lane checkbox dropdown.
        do
            local PP = EllesmereUI.PanelPP
            local buffFilterItems, BUFF_FILTER_KEYS, BOSS_BUFF_NEG_SKEYS
                -- Non-player buff vocabulary is just these three (see
                -- the Main Frames list).
                buffFilterItems = {
                    { isHeader = true, label = "Show", rightLabel = "Hide" },
                    { key = "stealable",         label = "Stealable",          dual = true, tooltip = "Buffs you can spellsteal or purge" },
                    { key = "bigDefensive",      label = "Big Defensive",      dual = true, tooltip = "Major defensive cooldowns" },
                    { key = "dispellable",       label = "Dispellable",        dual = true, tooltip = "Auras with a dispel type you can dispel" },
                }
                BUFF_FILTER_KEYS = { ownOnly = "onlyPlayerBuffs", raidFrames = "buffRaid", raidInCombat = "buffRaidInCombat", dispellable = "buffDispellable", crowdControl = "buffCrowdControl", bigDefensive = "buffBigDefensive", externalDefensive = "buffExternalDefensive", cancelable = "buffCancelable", stealable = "buffStealable" }
                BOSS_BUFF_NEG_SKEYS   = { stealable = "Stealable", bigDefensive = "BigDefensive", dispellable = "Dispellable" }
            -- Debuff Size | Debuff Text Size: mirrors the buff pair above. Debuff
            -- Text Size gates on "Show Duration" inside its Duration & Stack cog
            -- (also holds Duration X/Y + Stack size/position/X/Y). HIDDEN while the
            -- debuff column's effective Location is None (BossDebuffRowShown; setters above force rebuild on flips).
            if BossDebuffRowShown() then
            local debuffTextOff = function()
                return not BossDebuffLocationActive()
                or not db.profile.boss.debuffShowCooldownText
            end
            local textSizeRow
            textSizeRow, hh = Ww:DualRow(pp, yy,
                { type="slider", text="Debuff Size", min=10, max=70, step=1,
                  disabled=bossDebuffSizeOff,
                  disabledTooltip=function()
                      if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then
                          return EllesmereUI.DisabledTooltip("Simple Debuff Display", "disabled")
                      end
                      return EllesmereUI.DisabledTooltip("Debuffs Location")
                  end,
                  rawTooltip=true,
                  getValue=function() return db.profile.boss.debuffSize or 22 end,
                  setValue=function(v)
                      db.profile.boss.debuffSize = v; ReloadAndUpdate()
                      if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                  end },
                { type="slider", text="Debuff Text Size", min=6, max=100, step=1, trackWidth=120,
                  disabled=debuffTextOff, disabledTooltip="Show Duration (Inside Cog)",
                  getValue=function() return db.profile.boss.debuffCooldownTextSize or 10 end,
                  setValue=function(v) db.profile.boss.debuffCooldownTextSize = v; ReloadAndUpdate() end });  yy = yy - hh
            if not EllesmereUI._prebuilding then  -- Directions cog on Debuff Size (X/Y cluster offset)
                EllesmereUI.BuildInlineCog(textSizeRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = bossDebuffSizeOff, title = "Debuff Position", rows = {
                    { type="slider", label="Offset X", min=-200, max=200, step=1,
                      get=function() return db.profile.boss.debuffOffsetX or 0 end,
                      set=function(v) db.profile.boss.debuffOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() return db.profile.boss.debuffOffsetY or 0 end,
                      set=function(v) db.profile.boss.debuffOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Physical-pixel-perfect gap between the boss debuff icons.
                    { type="slider", pixel=true, label="Spacing", min=-1, max=10, step=1,
                      get=function() return db.profile.boss.debuffSpacing or 1 end,
                      set=function(v) db.profile.boss.debuffSpacing = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                } })
            end
            if not EllesmereUI._prebuilding then  -- Icon Zoom cog on Debuff Size
                local bossDebuffZoomOff = function() return (db.profile.boss.debuffAnchor or "bottomleft") == "none" end
                EllesmereUI.BuildInlineCog(textSizeRow._leftRegion, { disabled = bossDebuffZoomOff, disabledTooltip = "Debuffs Location", title = "Icon Zoom", rows = {
                    { type="slider", label="Zoom", min=0, max=0.20, step=0.01,
                      get=function() return db.profile.boss.debuffIconZoom or 0.07 end,
                      set=function(v) db.profile.boss.debuffIconZoom = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                } })
            end
            -- Debuff Text Size cog (right): Show Duration + Duration X/Y + Stack.
            -- Disabled while Simple Debuff Display is active.
            if not EllesmereUI._prebuilding then
                local rightRgn = textSizeRow._rightRegion
                -- Inline Duration + Stack text-color swatches on the Debuff Text
                -- Size slider; greyed + mouse-disabled on the same condition as
                -- the row's cog.
                local debuffOff = function() return not BossDebuffLocationActive() end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.debuffCooldownTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.debuffCooldownTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Duration Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                do
                    local sw, upd = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
                        function() local c = db.profile.boss.debuffStackTextColor; if c then return c.r, c.g, c.b end; return 1, 1, 1 end,
                        function(r, g, b) db.profile.boss.debuffStackTextColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
                    sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Stack Text Color") end)
                    sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    PP.Point(sw, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
                    rightRgn._lastInline = sw
                    local function apply() upd(); local o = debuffOff(); sw:SetAlpha(o and 0.3 or 1); sw:EnableMouse(not o) end
                    apply(); EllesmereUI.RegisterWidgetRefresh(apply)
                end
                EllesmereUI.BuildInlineCog(rightRgn, { disabled = debuffOff, disabledTooltip = "Debuffs Location",
                    title = "Duration & Stack",
                    rows = {
                        { type="toggle", label="Show Duration",
                          get=function() return db.profile.boss.debuffShowCooldownText end,
                          set=function(v) db.profile.boss.debuffShowCooldownText = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                        { type="slider", label="Duration X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffCooldownTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.debuffCooldownTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Duration Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffCooldownTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.debuffCooldownTextOffsetY = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Size", min=6, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextSize or 14 end,
                          set=function(v) db.profile.boss.debuffStackTextSize = v; ReloadAndUpdate() end },
                        { type="dropdown", label="Stack Position",
                          values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                          order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                          get=function() return db.profile.boss.debuffStackTextPosition or "bottomright" end,
                          set=function(v) db.profile.boss.debuffStackTextPosition = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack X", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextOffsetX or 0 end,
                          set=function(v) db.profile.boss.debuffStackTextOffsetX = v; ReloadAndUpdate() end },
                        { type="slider", label="Stack Y", min=-100, max=100, step=1,
                          get=function() return db.profile.boss.debuffStackTextOffsetY or 0 end,
                          set=function(v) db.profile.boss.debuffStackTextOffsetY = v; ReloadAndUpdate() end },
                    },
                })
                -- Disabled while Simple Debuff Display is active: simple mode
                -- uses its own (simpleDebuff*) cooldown text, so the regular
                -- debuff Duration & Stack controls do not apply.
            end
            end   -- close debuff sizing row hidden-while-None gate

            -- Built alongside the aura controls, then appended at the end
            -- of this section to keep border settings consistently last.
            local function AddBossAuraBorderSettings()
                local B = db.profile.boss
                local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
                local borderRow
                borderRow, hh = Ww:DualRow(pp, yy,
                    EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Border Style", values=texValues, order=texOrder,
                      getValue=function() return B.auraBorderTexture or "solid" end,
                      setValue=function(v)
                          local color, behind, behindUnitFrame = EllesmereUI.GetBorderStyleSelectDefaults(v)
                          B.auraBorderTexture = v
                          B.auraBorderTextureOffset = nil; B.auraBorderTextureOffsetY = nil
                          B.auraBorderTextureShiftX = nil; B.auraBorderTextureShiftY = nil
                          B.auraBorderBehind = behind
                          B.auraBorderBehindUnitFrame = behindUnitFrame
                          B.auraBorderR=color.r; B.auraBorderG=color.g; B.auraBorderB=color.b; B.auraBorderA=1
                          local ds=EllesmereUI.GetBorderDefaultSize("unitframes",v); if ds then B.auraBorderSize=ds end
                          -- A style pick returns the icons to their legacy step; clear a
                          -- set exact size (false travels through mirror sync, nil would not).
                          if B.auraBorderSizePx then B.auraBorderSizePx = false end
                          ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
                          -- The Width / Height Offset row exists only under a textured style.
                          EllesmereUI:RefreshPage(true)
                      end }),
                    EllesmereUI.BlizzStyle.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size", trackWidth=120,
                      getStep=function() return B.auraBorderSize or 1 end,
                      setStep=function(step) B.auraBorderSize=step end,
                      getTex=function() return B.auraBorderTexture or "solid" end,
                      getPx=function() return B.auraBorderSizePx end,
                      setPx=function(v) B.auraBorderSizePx=v end,
                      apply=function() ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end }))
                ); yy = yy - hh
                -- Width Offset | Height Offset: a textured aura border's outward
                -- offsets (a Solid border has none).
                do
                    local abTex = B.auraBorderTexture or "solid"
                    if abTex ~= "solid" and abTex ~= "" then
                        local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                            addonKey="unitframes",
                            getTex=function() return B.auraBorderTexture or "solid" end,
                            getStep=function() return B.auraBorderSize or 1 end,
                            getSizeKey=function() return B.auraBorderSize or 1 end,
                            getPx=function() return B.auraBorderSizePx end,
                            getX=function() return B.auraBorderTextureOffset end,
                            setX=function(v) B.auraBorderTextureOffset=v end,
                            getY=function() return B.auraBorderTextureOffsetY end,
                            setY=function(v) B.auraBorderTextureOffsetY=v end,
                            apply=function() ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end,
                        })
                        local offRow
                        offRow, hh = Ww:DualRow(pp, yy,
                            EllesmereUI.BlizzStyle.Gate("unitframes", ocfgL),
                            EllesmereUI.BlizzStyle.Gate("unitframes", ocfgR)); yy = yy - hh
                    end
                end
                if not EllesmereUI._prebuilding then
                    local rgn=borderRow._leftRegion
                    local btn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON, title="Border Options", rows={
                        { type="slider",label="Shift X",min=-10,max=10,step=1,
                          get=function() local v=B.auraBorderTextureShiftX;if v~=nil then return v end;local _,_,x=EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1);return x end,
                          set=function(v) B.auraBorderTextureShiftX=v==0 and nil or v;ReloadAndUpdate() end },
                        { type="slider",label="Shift Y",min=-10,max=10,step=1,
                          get=function() local v=B.auraBorderTextureShiftY;if v~=nil then return v end;local _,_,_,y=EllesmereUI.GetBorderDefaults("unitframes",B.auraBorderTexture or "solid",B.auraBorderSize or 1);return y end,
                          set=function(v) B.auraBorderTextureShiftY=v==0 and nil or v;ReloadAndUpdate() end },
                        { type="toggle",label="Show Behind",get=function() return B.auraBorderBehind or false end,set=function(v) B.auraBorderBehind=v;ReloadAndUpdate() end },
                        { type="toggle",label="Behind Unit Frame",get=function() return B.auraBorderBehindUnitFrame or false end,set=function(v) B.auraBorderBehindUnitFrame=v;ReloadAndUpdate() end },
                        { type="toggle",label="Border Above Effects",
                          tooltip="Draws boss aura icon borders over their cooldown swipes and glows. Duration and stack text stay above the borders.",
                          disabled=function()
                              local tex = B.auraBorderTexture or "solid"
                              return B.auraBorderBehind or B.auraBorderBehindUnitFrame
                                  or tex == "solid" or tex == "" or (B.auraBorderSize or 1) <= 0
                          end,
                          disabledTooltip="This option requires a textured Aura Border with a size above 0, and its Show Behind and Behind Unit Frame options disabled.",
                          rawTooltip=true,
                          get=function() return B.auraBorderAboveEffects == true end,
                          set=function(v) B.auraBorderAboveEffects=v;ReloadAndUpdate() end },
                    } })
                    local function vis() if (B.auraBorderTexture or "solid")=="solid" then btn:Hide() else btn:Show() end end
                    EllesmereUI.RegisterWidgetRefresh(vis);vis()
                end
                if not EllesmereUI._prebuilding then
                    local rgn=borderRow._rightRegion
                    local sw,upd=EllesmereUI.BuildColorSwatch(rgn,borderRow:GetFrameLevel()+3,
                        function() return B.auraBorderR or 0,B.auraBorderG or 0,B.auraBorderB or 0,B.auraBorderA or 1 end,
                        function(r,g,b,a) B.auraBorderR=r;B.auraBorderG=g;B.auraBorderB=b;B.auraBorderA=a;ReloadAndUpdate() end,true,20)
                    PP.Point(sw,"RIGHT",rgn._control,"LEFT",-8,0)
                    EllesmereUI.RegisterWidgetRefresh(upd)
                end
            end
            AddBossAuraBorderSettings()
            -- Boss Debuff Filter in slot 1: the native mode dropdown, disabled
            -- with the requirement tooltip while no debuffs show at all (Simple
            -- Debuff Display None + Debuffs Location None). The right slot is the
            -- Boss Buff Filter.
            local filterRow
            local filterOff = function()
                local p = db.profile.boss
                return ns.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") == "none"
            end
            local function BossS() return db.profile.boss end
            local buffFilterOff
            local bossFilterRightSlot = { type="label", text="" }
                buffFilterOff = function()
                    local p = db.profile.boss
                    return ns.GetBossSimpleBuffMode(p) == "none" and not p.showBuffs
                end
                bossFilterRightSlot = { type="dropdown", text="Boss Buff Filter",
                  disabled=buffFilterOff, disabledTooltip="Buffs", requireState="displayed",
                  values={ __placeholder="..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end, setValue=function() end }
            filterRow, hh = Ww:DualRow(pp, yy,
                DebuffModeDropdownCfg("Boss Debuff Filter", "boss", BossS, ReloadAndUpdate,
                  { disabled=filterOff, disabledTooltip="Debuffs", requireState="displayed" }),
                bossFilterRightSlot);  yy = yy - hh
            if not EllesmereUI._prebuilding then
                AttachDebuffModeWarn(filterRow._leftRegion, BossS, filterOff)
                -- Hide Exhaustion, the Debuff Filter cog row every unit shares.
                EllesmereUI.BuildInlineCog(filterRow._leftRegion, {
                    title = "Debuff Filter",
                    tip = "Debuff Filter Options",
                    disabled = filterOff,
                    disabledTooltip = "Debuffs",
                    requireState = "displayed",
                    rows = { HideExhaustionRow(BossS, ReloadAndUpdate) },
                })
            end
            -- Right slot: Boss Buff Filter (two-lane checkbox dropdown).
            if not EllesmereUI._prebuilding then
                local rgn = filterRow._rightRegion
                if rgn._control then rgn._control:Hide() end
                local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2, buffFilterItems,
                    function(k, neg)
                        if neg then
                            local m = db.profile.boss.buffNegClasses
                            local sk = BOSS_BUFF_NEG_SKEYS[k]
                            return m ~= nil and sk ~= nil and m[sk] == true
                        end
                        return db.profile.boss[BUFF_FILTER_KEYS[k]] or false
                    end,
                    function(k, v, neg)
                        local bt = db.profile.boss
                        local sk = BOSS_BUFF_NEG_SKEYS[k]
                        if neg then
                            if not sk then return end
                            bt.buffNegClasses = bt.buffNegClasses or {}
                            bt.buffNegClasses[sk] = v and true or nil
                            if not next(bt.buffNegClasses) then bt.buffNegClasses = nil end
                            if v then bt[BUFF_FILTER_KEYS[k]] = nil end
                            ReloadAndUpdate()
                            return
                        end
                        if v and sk and bt.buffNegClasses then
                            bt.buffNegClasses[sk] = nil
                            if not next(bt.buffNegClasses) then bt.buffNegClasses = nil end
                        end
                        bt[BUFF_FILTER_KEYS[k]] = v
                        ReloadAndUpdate()
                    end)
                PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD; rgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(cbRefresh)
                local buffFilterBlock = CreateFrame("Frame", nil, cbDD)
                buffFilterBlock:SetAllPoints()
                buffFilterBlock:SetFrameLevel(cbDD:GetFrameLevel() + 10)
                buffFilterBlock:EnableMouse(true)
                buffFilterBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(cbDD, EllesmereUI.DisabledTooltip("Buffs", "displayed"))
                end)
                buffFilterBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBuffFilterDisabled()
                    if buffFilterOff() then
                        cbDD:SetAlpha(0.3); buffFilterBlock:Show()
                    else
                        cbDD:SetAlpha(1); buffFilterBlock:Hide()
                    end
                end
                UpdateBuffFilterDisabled()
                EllesmereUI.RegisterWidgetRefresh(UpdateBuffFilterDisabled)
            end
        end

        -- Cogwheel on Buffs Location (disabled while Simple Buff Display
        -- overrides placement, or when Buffs Location is None)
        if not EllesmereUI._prebuilding then
            local leftRgn = bossAuraRow._leftRegion
            EllesmereUI.BuildInlineCog(leftRgn, {
                disabled = bossBuffSizeOff,
                -- Both branches are whole sentences (raw), so translated clients wrap once.
                disabledTooltip = function() return ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" and EllesmereUI.DisabledTooltip("Simple Buff Display", "disabled") or EllesmereUI.DisabledTooltip("Buffs Location") end,
                rawTooltip = true,
                title = "Buff Settings",
                rows = {
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return db.profile.boss.buffGrowth or "auto" end,
                      set=function(v) db.profile.boss.buffGrowth = v; ReloadAndUpdate() end },
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return db.profile.boss.maxBuffs or 4 end,
                      set=function(v) db.profile.boss.maxBuffs = v; ReloadAndUpdate() end },
                    { type="slider", label="Max Per Row", min=1, max=20, step=1,
                      get=function() return db.profile.boss.buffMaxPerRow or db.profile.boss.maxBuffs or 4 end,
                      set=function(v) db.profile.boss.buffMaxPerRow = v; ReloadAndUpdate() end },
                    { type="toggle", label="Dispel Type Borders",
                      disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                      disabledTooltip="This option requires Blizzard Style to be disabled",
                      get=function() return db.profile.boss.buffDispelBorder == true end,
                      set=function(v) db.profile.boss.buffDispelBorder = v; ReloadAndUpdate() end },
                },
            })
        end

        -- Cogwheel on Debuffs Location (hidden when Simple Debuff Display overrides placement)
        if not EllesmereUI._prebuilding then
            local rightRgn = bossAuraRow._rightRegion
            EllesmereUI.BuildInlineCog(rightRgn, {
                disabled = bossDebuffSizeOff,
                disabledTooltip = function() return ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" and EllesmereUI.DisabledTooltip("Simple Debuff Display", "disabled") or EllesmereUI.DisabledTooltip("Debuffs Location") end,
                rawTooltip = true,
                title = "Debuff Settings",
                rows = {
                    { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                      get=function() return db.profile.boss.debuffGrowth or "auto" end,
                      set=function(v) db.profile.boss.debuffGrowth = v; ReloadAndUpdate() end },
                    { type="slider", label="Max Count", min=1, max=20, step=1,
                      get=function() return db.profile.boss.maxDebuffs or 10 end,
                      set=function(v) db.profile.boss.maxDebuffs = v; ReloadAndUpdate() end },
                    { type="slider", label="Max Per Row", min=1, max=20, step=1,
                      get=function() return db.profile.boss.debuffMaxPerRow or db.profile.boss.maxDebuffs or 10 end,
                      set=function(v) db.profile.boss.debuffMaxPerRow = v; ReloadAndUpdate() end },
                },
            })

        end

        -- Buff/Debuff text colors now live as inline swatches on the Buff Text
        -- Size / Debuff Text Size sliders above (Duration + Stack per side).

        return yy
    end

    -- New "Indicators" section, rendered at the BOTTOM (below the Power Bar)
    -- via opts.afterPowerRow. Holds the non-aura indicators moved out of the
    -- Buffs and Debuffs section above.
    local function bossIndicators(Ww, pp, yy)
        local hh

        _, hh = Ww:SectionHeader(pp, "Indicators", yy);  yy = yy - hh

        -- Row 1: Out of Range Alpha | Spell Target
        -- (Out of Range read live by the range ticker, so no reload needed.)
        local bossTgtRow
        bossTgtRow, hh = Ww:DualRow(pp, yy,
            { type="slider", text="Out of Range Alpha", min=10, max=100, step=1,
              tooltip="Fades boss frames when the boss is out of range of your spells. Set to 100% to disable the fade.",
              getValue=function() return math.floor(((db.profile.boss.oorAlpha or 0.4) * 100) + 0.5) end,
              setValue=function(v) db.profile.boss.oorAlpha = v / 100 end },
            { type="toggle", text="Spell Target",
              tooltip = "Show the name of who the boss is casting on.",
              getValue=function() return db.profile.boss.showCastTarget == true end,
              setValue=function(v)
                  db.profile.boss.showCastTarget = v
                  ReloadAndUpdate()
              end });  yy = yy - hh
        -- Inline cog on Spell Target: X/Y offsets for the cast target
        -- text. Boss-scoped copies of the shared castbar keys, which the
        -- runtime and preview already consume (castSpellTargetX/Y ->
        -- _tgtOX/_tgtOY in the cast text zone layout).
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(bossTgtRow._rightRegion, {
                title = "Spell Target",
                rows = {
                    { type="slider", label="X Offset", min=-300, max=300, step=1,
                      get=function() return db.profile.boss.castSpellTargetX or 0 end,
                      set=function(v) db.profile.boss.castSpellTargetX = v; ReloadAndUpdate() end },
                    { type="slider", label="Y Offset", min=-300, max=300, step=1,
                      get=function() return db.profile.boss.castSpellTargetY or 0 end,
                      set=function(v) db.profile.boss.castSpellTargetY = v; ReloadAndUpdate() end },
                },
            })
        end

        -- Row 2: Show Raid Marker | Raid Marker Size (+ position cog)
        local function bossRmOff()
            return db.profile.boss.raidMarkerEnabled == false
        end
        local bossRmRow
        bossRmRow, hh = Ww:DualRow(pp, yy,
            { type="toggle", text="Show Raid Marker",
              tooltip="Shows the raid target marker icon on boss frames.",
              getValue=function() return db.profile.boss.raidMarkerEnabled ~= false end,
              setValue=function(v)
                db.profile.boss.raidMarkerEnabled = v
                ReloadAndUpdate()
                EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Raid Marker Size", min=12, max=48, step=1,
              disabled=bossRmOff, disabledTooltip="Raid Marker",
              getValue=function() return db.profile.boss.raidMarkerSize or 28 end,
              setValue=function(v) db.profile.boss.raidMarkerSize = v; ReloadAndUpdate() end });  yy = yy - hh
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(bossRmRow._leftRegion, {
                title = "Raid Marker Position",
                rows = {
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return db.profile.boss.raidMarkerX or 0 end,
                      set=function(v) db.profile.boss.raidMarkerX = v; ReloadAndUpdate() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return db.profile.boss.raidMarkerY or 0 end,
                      set=function(v) db.profile.boss.raidMarkerY = v; ReloadAndUpdate() end },
                    { type="dropdown", label="Alignment", values={ left="Left", center="Center", right="Right" }, order={ "left", "center", "right" },
                      get=function() return db.profile.boss.raidMarkerAlign or "left" end,
                      set=function(v) db.profile.boss.raidMarkerAlign = v; ReloadAndUpdate() end },
                },
            })
        end

        return yy
    end

    -- CAST BAR section, rendered below the Power Bar. Mirrors the player cast
    -- bar's Show Cast Bar/Height/Bar Background/Spell Name/Duration/Reverse Fill.
    -- All keys are boss-scoped (db.profile.boss.*), read by the shared castbar
    -- runtime + preview so both live-update. "Show Cast Bar" off (showCastbar=false) hides it entirely (runtime disables Castbar; preview zero-heights it).
    local function bossCastBar(Ww, pp, yy)
        local B = db.profile.boss
        local hh

        -- The Show Cast Bar toggle gates the rest of the section. AddCastBlock
        -- greys a region (slider/dropdown/toggle + any inline swatch) to 0.3 and
        -- blocks its mouse while the cast bar is off, tracked live via the
        -- widget-refresh fast path (mirrors AddDarkModeBlock). The toggle's own color swatches gate separately so the toggle stays interactive.
        local castColorSwatches = {}
        local function AddCastBlock(rgn, enabledAlpha)
            if not rgn then return end
            local block = CreateFrame("Frame", nil, rgn)
            block:SetAllPoints()
            block:SetFrameLevel(rgn:GetFrameLevel() + 50)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(block, EllesmereUI.DisabledTooltip("Show Cast Bar"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function Update()
                if B.showCastbar == false then
                    rgn:SetAlpha(0.3); block:Show()
                else
                    rgn:SetAlpha(enabledAlpha and enabledAlpha() or 1); block:Hide()
                end
            end
            Update()
            EllesmereUI.RegisterWidgetRefresh(Update)
        end

        bossCastHeader, hh = Ww:SectionHeader(pp, "CAST BAR", yy);  yy = yy - hh

        -- Row 1: Show Cast Bar (+ inline fill-color swatch) | Cast Bar Height
        castMainRow, hh = Ww:DualRow(pp, yy,
            { type="toggle", text="Show Cast Bar",
              getValue=function() return B.showCastbar ~= false end,
              -- DependentSetValue: rows 2-4 below are hidden while the
              -- cast bar is off; the flip forces the full rebuild.
              setValue=EllesmereUI.DependentSetValue(
                  function() return B.showCastbar ~= false end,
                  function(v) B.showCastbar = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end) },
            { type="slider", text="Cast Bar Height", min=1, max=40, step=1,
              disabled=function() return B.showCastbar == false end,
              disabledTooltip="Show Cast Bar",
              getValue=function() return B.castbarHeight or 14 end,
              setValue=function(v) B.castbarHeight = v; ReloadAndUpdate() end });  yy = yy - hh
        -- Enemy cast colors on Show Cast Bar (left region), matching target/focus.
        if not EllesmereUI._prebuilding then
            local rgn = castMainRow._leftRegion
            local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
                local sw, updateSw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = B[colorKey] or fallback
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        B[colorKey] = { r=r, g=g, b=b }
                        ReloadAndUpdate()
                    end, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tooltip) end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                rgn._lastInline = sw
                castColorSwatches[#castColorSwatches + 1] = { sw = sw, enabledAlpha = disabledFn
                    and function() return disabledFn() and 0.3 or 1 end }
                if disabledFn then
                    local function Update()
                        local off = disabledFn()
                        sw:SetAlpha(off and 0.3 or 1)
                        sw:EnableMouse(not off)
                        if updateSw then updateSw() end
                    end
                    Update()
                    EllesmereUI.RegisterWidgetRefresh(Update)
                end
            end
            AddCastColorSwatch("Interrupt Ready Mid-Cast", "castbarInterruptMidCastColor",
                { r=0.318, g=0.820, b=0.357 },
                function() return B.castbarInterruptMidCastEnabled ~= true end)
            AddCastColorSwatch("Interrupt on CD", "castbarInterruptReadyColor", { r=0.92, g=0.35, b=0.20 })
            AddCastColorSwatch("Uninterruptible Cast", "castbarUninterruptibleColor", { r=0.5, g=0.5, b=0.5 })
            AddCastColorSwatch("Interruptible Cast", "castbarFillColor", { r=0.863, g=0.820, b=0.639 })
        end
        -- Inline settings cog matching target/focus, plus boss positioning.
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(castMainRow._leftRegion, {
                disabled = function() return B.showCastbar == false end, disabledTooltip = "Show Cast Bar",
                title = "Cast Bar",
                rows = {
                    { type="toggle", label="Hide When Idle",
                      tooltip="Only show the cast bar while a cast is in progress; hide it the rest of the time.",
                      get=function() return B.castbarHideWhenInactive ~= false end,
                      set=function(v) B.castbarHideWhenInactive = v; ReloadAndUpdate() end },
                    { type="slider", label="Fill Opacity", min=0, max=100, step=1,
                      tooltip="Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
                      get=function() return B.castFillOpacity or 100 end,
                      set=function(v) B.castFillOpacity = v; ReloadAndUpdate() end },
                    { type="toggle", label="Raise Cast Bar Strata (All)",
                      tooltip="Lifts player, target, focus, and boss cast bars above other frames so they are never hidden behind them.",
                      get=function() return db.profile.raiseCastbarStrata ~= false end,
                      set=function(v) db.profile.raiseCastbarStrata = v; ReloadAndUpdate() end },
                    { type="toggle", label="Show Kick Ready Mid-Cast Tick",
                      tooltip="Shows a small white tick mark where the cast will be when your interrupt comes off cooldown.",
                      get=function() return B.castbarKickTickEnabled ~= false end,
                      set=function(v) B.castbarKickTickEnabled = v; ReloadAndUpdate() end },
                    { type="toggle", label="Show Kick Ready Mid-Cast Bar",
                      tooltip="Colors the cast segment during which your interrupt will be available.",
                      get=function() return B.castbarInterruptMidCastEnabled == true end,
                      set=function(v) B.castbarInterruptMidCastEnabled = v; ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                    { type="slider", label="Offset X", min=-500, max=500, step=1,
                      get=function() return B.castbarOffsetX or 0 end,
                      set=function(v) B.castbarOffsetX = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    { type="slider", label="Offset Y", min=-200, max=200, step=1,
                      get=function() return B.castbarOffsetY or 0 end,
                      set=function(v) B.castbarOffsetY = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end },
                    -- Opt-in for the Border Style | Border Size rows (built
                    -- below only while on; the rebuild shows or drops them).
                    { type="toggle", label="Custom Border Style",
                      tooltip="Show the border style and size controls for the cast bar.",
                      disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                      disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
                      requireState="disabled",
                      get=function() return B.castBorderCustom == true end,
                      set=function(v) B.castBorderCustom = v; ReloadAndUpdate(); EllesmereUI:RefreshPage(true) end },
                },
            })
        end

        -- Rows 2-4 are HIDDEN entirely while Show Cast Bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips). The
        -- master row's own inlines (color swatches) keep the
        -- AddCastBlock grey+block treatment; its cog disables itself.
        if B.showCastbar ~= false then
        -- Row 2: Show Cast Icon (+ icon cog) | Cast Bar Width (right under Cast
        -- Bar Height so the two dimensions sit stacked in the same column)
        growthRow, hh = Ww:DualRow(pp, yy,
            { type="toggle", text="Show Cast Icon",
              getValue=function() return B.showCastIcon ~= false end,
              setValue=function(v) B.showCastIcon = v; ReloadAndUpdate() end },
            { type="slider", text="Cast Bar Width", min=0, max=500, step=1,
              tooltip="Sets a custom width for the cast bar. Set to 0 to match the boss frame width.",
              getValue=function() return B.castbarWidth or 0 end,
              -- Custom widths floor at 30 (matches the unlock-mode resize
              -- minimum): below the cast icon size the bar layout inverts.
              setValue=function(v) if v > 0 and v < 30 then v = 30 end; B.castbarWidth = v; ReloadAndUpdate(); if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end end });  yy = yy - hh
        -- Icon cog (left): "Icon Border" / "Make Icon Part of the Bar" /
        -- "Border Wraps Icon" / "Vertical Separator" / "Show Icon on Right".
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(growthRow._leftRegion, {
                title = "Cast Icon",
                rows = {
                    { type = "toggle", label = "Icon Border",
                      tooltip = "Use the cast bar's border style, size and color around the icon.",
                      disabled = function() return EllesmereUI.BlizzStyle.Get("unitframes") or B.showCastIcon == false end,
                      disabledTooltip = "This option requires Show Icon and the EllesmereUI style.",
                      get = function() return B.castIconBorder == true end,
                      set = function(v) B.castIconBorder = v; ReloadAndUpdate() end },
                    { type = "toggle", label = "Make Icon Part of the Bar",
                      tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                      -- The stock styles count a shown icon as part of the bar
                      -- (their frame art wraps both), so the toggle reads on and locks.
                      disabled = function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                      disabledTooltip = function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
                      requireState = "disabled",
                      get = function()
                          if EllesmereUI.BlizzStyle.Get("unitframes") then return true end
                          return B.castbarIconInWidth ~= false
                      end,
                      set = function(v) B.castbarIconInWidth = v; ReloadAndUpdate() end },
                    { type = "toggle", label = "Border Wraps Icon",
                      tooltip = "Draw the custom cast bar border around the icon and the bar together. An icon with an offset keeps its own border.",
                      disabled = function()
                          return EllesmereUI.BlizzStyle.Get("unitframes") or B.castBorderCustom ~= true
                              or not ns.UF_CastIconInWidth("boss", B)
                      end,
                      disabledTooltip = "This option requires Custom Border Style, Show Icon and Make Icon Part of the Bar, with the EllesmereUI style.",
                      get = function() return B.castBorderWrapIcon == true end,
                      set = function(v) B.castBorderWrapIcon = v; ReloadAndUpdate() end },
                    { type = "toggle", label = "Vertical Separator",
                      tooltip = "Draw a divider between the integrated icon and the bar, using the cast bar's border appearance.",
                      disabled = function()
                          return EllesmereUI.BlizzStyle.Get("unitframes") or not ns.UF_CastIconInWidth("boss", B)
                              or not ns.UF_CastIconSeamOK(B)
                      end,
                      disabledTooltip = function()
                          if EllesmereUI.BlizzStyle.Get("unitframes") or not ns.UF_CastIconInWidth("boss", B) then
                              return "This option requires Show Icon and Make Icon Part of the Bar, with the EllesmereUI style."
                          end
                          return "This option requires Solid or a border style with divider art, and a Border Size above 0."
                      end,
                      get = function() return B.castIconSeparator == true end,
                      set = function(v) B.castIconSeparator = v; ReloadAndUpdate() end },
                    { type = "toggle", label = "Show Icon on Right",
                      tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                      get = function() return B.castbarIconRight == true end,
                      set = function(v) B.castbarIconRight = v; ReloadAndUpdate() end },
                },
            })
        end
        -- Row 3: Reverse Fill | Bar Background (opacity slider + color swatch).
        -- Bar Background sits right below the size sliders (mirrors the main
        -- frames' cast bar section, where it follows the Height row).
        local reverseRow
        reverseRow, hh = Ww:DualRow(pp, yy,
            { type="toggle", text="Reverse Fill",
              getValue=function() return B.castReverseFill == true end,
              setValue=function(v) B.castReverseFill = v; ReloadAndUpdate() end },
            { type="slider", text="Bar Background", min=0, max=100, step=1,
              getValue=function() return math.floor((B.castBgAlpha or 0.5) * 100 + 0.5) end,
              setValue=function(v) B.castBgAlpha = v / 100; ReloadAndUpdate() end });  yy = yy - hh
        -- Inline color swatch on Bar Background (right region).
        if not EllesmereUI._prebuilding then
            local rgn = reverseRow._rightRegion
            local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local c = B.castBgColor
                    if c then return c.r, c.g, c.b end
                    return 0, 0, 0
                end,
                function(r, g, b) B.castBgColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, "Cast Background") end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            rgn._lastInline = sw
        end

        -- Row 4: Spell Name (dropdown + swatch + Size/X/Y cog) | Duration (same)
        local castTextRow
        castTextRow, hh = Ww:DualRow(pp, yy,
            { type="dropdown", text="Spell Name",
              values={ none="None", left="Left", right="Right", center="Center" },
              order={ "none", "left", "right", "center" },
              getValue=function() return B.castSpellNameSide or "left" end,
              setValue=function(v)
                B.castSpellNameSide = v
                -- Conflict rule (mirrors player): name and the spell target may
                -- not share a side -- setting the name onto the target's side
                -- turns the target (Indicators) off.
                if v ~= "none" and (B.showCastTarget ~= false) and (B.castSpellTargetSide or "right") == v then
                    B.showCastTarget = false
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Duration",
              values={ none="None", right="Right", left="Left" },
              order={ "none", "right", "left" },
              getValue=function()
                if B.showCastDuration == false then return "none" end
                return B.castDurationSide or "right"
              end,
              setValue=function(v)
                if v == "none" then
                    B.showCastDuration = false
                else
                    B.showCastDuration = true
                    B.castDurationSide = v
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
              end });  yy = yy - hh
        -- Spell Name (left): color swatch + Size/X/Y cog
        if not EllesmereUI._prebuilding then
            local rgn = castTextRow._leftRegion
            local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function() local c = B.castSpellNameColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b end,
                function(r, g, b) B.castSpellNameColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = sw
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Spell Name",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return B.castSpellNameSize or 11 end,
                      set=function(v) B.castSpellNameSize = v; ReloadAndUpdate() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return B.castSpellNameX or 0 end,
                      set=function(v) B.castSpellNameX = v; ReloadAndUpdate() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return B.castSpellNameY or 0 end,
                      set=function(v) B.castSpellNameY = v; ReloadAndUpdate() end },
                },
            })
        end
        -- Duration (right): color swatch + Size/X/Y cog
        if not EllesmereUI._prebuilding then
            local rgn = castTextRow._rightRegion
            local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function() local c = B.castDurationColor or { r=1, g=1, b=1 }; return c.r, c.g, c.b end,
                function(r, g, b) B.castDurationColor = { r=r, g=g, b=b }; ReloadAndUpdate() end, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = sw
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Duration",
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return B.castDurationSize or 10 end,
                      set=function(v) B.castDurationSize = v; ReloadAndUpdate() end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return B.castDurationX or 0 end,
                      set=function(v) B.castDurationX = v; ReloadAndUpdate() end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return B.castDurationY or 0 end,
                      set=function(v) B.castDurationY = v; ReloadAndUpdate() end },
                },
            })
        end
        -- Custom Border Style rows (the Cast Bar cog's opt-in): one table
        -- styles all five boss cast bars; no unlock element, no sync links.
        if B.castBorderCustom == true then
            yy = yy - ns.UF_CastBorderRows(Ww, pp, yy, function() return B end, ReloadAndUpdate)
        end
        -- Classic WoW UI: Border Size closes the section (odd last slot).
        yy = yy - ns.UF_ClassicCastBorderRow(Ww, pp, yy,
            function() return B end,
            ns.UF_CastClassicKey("boss"),
            function() ReloadAndUpdate() end)

        end   -- close boss Cast Bar hidden-while-disabled gate

        -- The Show Cast Bar toggle's own color swatches stay gated grey +
        -- blocked while the cast bar is off (the Height slider uses a
        -- native disabled state; the hidden rows need nothing).
        for _, item in ipairs(castColorSwatches) do AddCastBlock(item.sw, item.enabledAlpha) end
        return yy
    end

    local displayHeader, sizeRow, textHeader, textRow
    y, displayHeader, sizeRow, textHeader, textRow = BuildMiniTextAndSize(W, parent, y, db.profile.boss, "boss", enableRow, bossAfterSize, { hasPowerBar = true, afterPowerRow = function(Ww, pp, yy)
        yy = bossCastBar(Ww, pp, yy)
        return bossIndicators(Ww, pp, yy)
    end })

    -- Store click targets for hover highlight system
    parent._ufClickTargets = {
        -- Health bar -> Health Bar Height (sizeRow left, HEALTH BAR section);
        -- Power bar -> Power Bar Height (pwrRow1 left, POWER BAR section).
        healthBar  = { section = textHeader or displayHeader,  target = sizeRow,  slotSide = "left" },
        powerBar   = { section = parent._powerHeaderFrame or displayHeader,  target = parent._powerHeightRow,  slotSide = "left" },
        powerBarText = { section = parent._powerHeaderFrame or displayHeader,  target = parent._powerTextRow,  slotSide = "left" },
        portrait   = { section = displayHeader,  target = portraitRow,   slotSide = "right" },
        nameText   = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        healthText = { section = textHeader or displayHeader,  target = textRow or sizeRow },
        -- Blizzard Style level number -> Show Level (+ its cog).
        levelText  = { section = textHeader or displayHeader,  target = parent._ufLevelRow, slotSide = "left" },
        -- Cast bar -> Cast Bar Height; spell icon -> Show Cast Icon. Both live
        -- in growthRow after the swap (Show Cast Icon left, Cast Bar Height right).
        castBar    = { section = bossCastHeader or displayHeader,  target = castMainRow or growthRow,  slotSide = "left" },
        castIcon   = { section = bossCastHeader or displayHeader,  target = growthRow,  slotSide = "left" },
        -- Buffs/Debuffs scroll to the active control: Simple Display when it's
        -- on (the column is forced), otherwise the normal Location dropdown.
        buffIcon   = function()
            if ns.GetBossSimpleBuffMode(db.profile.boss) ~= "none" then
                return { section = bossAuraHeader or displayHeader, target = simpleBuffRow }
            end
            return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "left" }
        end,
        debuffIcon = function()
            if ns.GetBossSimpleDebuffMode(db.profile.boss) ~= "none" then
                return { section = bossAuraHeader or displayHeader, target = simpleRow }
            end
            return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "right" }
        end,
    }

    return abs(y)
end
