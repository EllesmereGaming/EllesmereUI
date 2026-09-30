if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\CastBarPage_Options.lua
--  Resource Bars options: Cast Bar page. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Cast Bar page
function ns.ERB_BuildCastBarPage(pageName, parent, yOffset)
    local env = ns._ERB_OptEnv
    local DB, PP, CLASS_COLORS, _clickMappings = env.DB, env.PP, env.CLASS_COLORS, env._clickMappings
    local ShuffleCastBarIcons, UpdateCastBarPreview, _castBarPreviewBuilder = env.ShuffleCastBarIcons, env.UpdateCastBarPreview, env._castBarPreviewBuilder
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    env.SetCastBarPreviewFill(math.random(30, 85) / 100)
    ShuffleCastBarIcons()
    EllesmereUI:SetContentHeader(_castBarPreviewBuilder)

    -- Wipe click mappings (shared with display page; never from a hidden pre-build -- see the matching guard in BuildBarDisplayPage)
    if not EllesmereUI._prebuilding then
        wipe(_clickMappings)
    end

    -- Re-append SharedMedia textures for cast bar (catches lazy-registered SM packs)
    EllesmereUI.AppendSharedMediaTextures(
        _G._ERB_CastBarTextureNames or {},
        _G._ERB_CastBarTextureOrder or {},
        nil,
        _G._ERB_CastBarTextures
    )
    -- Texture dropdown values (same as nameplates)
    local texValues = {}
    local texOrder = {}
    do
        local names = _G._ERB_CastBarTextureNames or {}
        local order = _G._ERB_CastBarTextureOrder or {}
        local lookup = _G._ERB_CastBarTextures or {}
        for _, key in ipairs(order) do
            if key ~= "---" then
                texValues[key] = names[key] or key
            end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return lookup[key]
            end,
        }
    end

    local castOff = function() local p = DB(); return p and not p.castBar.enabled end

    local function RefreshCast()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized("ERB_CastBar")
        end
        UpdateCastBarPreview()
    end

    local castSection
    castSection, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    -- Strata dropdown values for the Cast Bar Frame Strata control.
    local cbStrataValues = EllesmereUI.FRAME_STRATA_LABELS
    local cbStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE

    -- Row 1: Enable Player Cast Bar | Frame Strata
    local castEnableRow
    castEnableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.enabled end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.enabled = v; RefreshCast()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          values = cbStrataValues, order = cbStrataOrder,
          getValue = function()
              local p = DB(); return p and p.castBar.frameStrata or "MEDIUM"
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.frameStrata = v; RefreshCast()
          end }
    );  y = y - h
    -- (No position cog here: the cast bar is positioned via Unlock Mode; the old X/Y offset cog wrote anchor keys the runtime never reads.)

    -- Row 2: Height | Width (sync icons push to power + health bars)
    local classSizeRow
    local cbhDis, cbhTip, cbhRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Height", castOff, "Player Cast Bar")
    local cbwDis, cbwTip, cbwRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Width", castOff, "Player Cast Bar")
    classSizeRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Height",
          min = 1, max = 60, step = 1,
          disabled = cbhDis, disabledTooltip = cbhTip, rawTooltip = cbhRaw,
          getValue = function() local p = DB(); return p and p.castBar.height or 20 end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.height = v; RefreshCast()
          end },
        { type = "slider", text = "Width",
          min = 50, max = 800, step = 1,
          disabled = cbwDis, disabledTooltip = cbwTip, rawTooltip = cbwRaw,
          getValue = function() local p = DB(); return p and p.castBar.width or 220 end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.width = v; RefreshCast()
          end }
    );  y = y - h

    -- Row 3: Show Spell Icon (cog: Icon on Right) | Show Spark
    local iconRow
    iconRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Spell Icon",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.showIcon ~= false end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showIcon = v; RefreshCast()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Show Spark",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.showSpark end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showSpark = v; RefreshCast()
          end }
    );  y = y - h
    -- Inline cog on Show Spell Icon: Icon on Right
    if not EllesmereUI._prebuilding then
        local rgn = iconRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function()
                local p = DB(); return p and (not p.castBar.enabled or p.castBar.showIcon == false)
            end,
            disabledTooltip = function()
                local p = DB(); return (p and not p.castBar.enabled) and "Player Cast Bar" or "Show Spell Icon"
            end,
            title = "Spell Icon Settings",
            rows = {
                { type = "toggle", label = "Icon on Right",
                  tooltip = "Attach the spell icon to the right of the cast bar instead of the left.",
                  get = function() local p = DB(); return p and p.castBar.iconOnRight end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.iconOnRight = v; RefreshCast()
                  end },
                { type = "toggle", label = "Show Icon Divider",
                  tooltip = "Draw a 1px divider between the spell icon and the cast bar, matching the border color.",
                  get = function() local p = DB(); return p and p.castBar.showIconDivider end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.showIconDivider = v; RefreshCast()
                  end },
                -- Border Art Divider: the divider in the border style's own art (the
                -- Pixels styles); any other style keeps the solid line.
                { type = "toggle", label = "Border Art Divider",
                  tooltip = "Draws the icon divider in the border style's art instead of a solid line.",
                  disabled = function()
                      local p = DB(); if not p then return true end
                      local cb = p.castBar
                      return (not cb.showIconDivider) or EllesmereUI.BlizzStyle.Get("castbar")
                          or not EllesmereUI.GetBorderCompanion(cb.borderTexture, "sepV")
                  end,
                  disabledTooltip = function()
                      if EllesmereUI.BlizzStyle.Get("castbar") then
                          return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("castbar"), "disabled")
                      end
                      local p = DB()
                      if not (p and p.castBar.showIconDivider) then return "Show Icon Divider" end
                      return "This option requires a border style with matching art, such as Pixels."
                  end,
                  rawTooltip = function()
                      if EllesmereUI.BlizzStyle.Get("castbar") then return true end
                      local p = DB()
                      return (p and p.castBar.showIconDivider) and true or false
                  end,
                  get = function() local p = DB(); return p and p.castBar.iconDividerArt or false end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.iconDividerArt = v and true or false; RefreshCast()
                  end },
            },
        })
    end

    -- Row 4: Always Show
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Always Show",
          tooltip = "Keep the cast bar visible (sitting empty) when you are not casting, instead of hiding it.",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.alwaysShow end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.alwaysShow = v; RefreshCast()
          end },
        { type = "toggle", text = "Smooth Bar Animation",
          tooltip = "Eases the cast fill between updates. Turn off for a raw, uneased fill.",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return not (p and p.castBar.smoothFill == false) end,
          setValue = function(v)
              local p = DB(); if not p then return end
              if v then p.castBar.smoothFill = nil else p.castBar.smoothFill = false end
              RefreshCast()
          end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 16);  y = y - h

    local displaySection
    displaySection, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "castbar")

    -- Row: Cast Bar Border Style dropdown (+ inline offset cog)
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local cbBsRow
        cbBsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("castbar", { type="dropdown", text="Border Style",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              values=texValues, order=texOrder,
              getValue=function() local p = DB(); return p and p.castBar.borderTexture or "solid" end,
              setValue=function(v)
                  local p = DB(); if not p then return end
                  p.castBar.borderTexture = v; p.castBar.borderTextureOffset = nil; p.castBar.borderTextureOffsetY = nil; p.castBar.borderTextureShiftX = nil; p.castBar.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  p.castBar.borderR = _bcol.r; p.castBar.borderG = _bcol.g; p.castBar.borderB = _bcol.b; p.castBar.borderA = 1
                  p.castBar.borderBehind = _bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then p.castBar.borderSize = defSz end
                  if p.castBar.borderSizePx then p.castBar.borderSizePx = false end
                  RefreshCast(); EllesmereUI:RefreshPage(true)
              end }),
            -- Classic WoW UI: the slot sizes the vanilla frame instead.
            (EllesmereUI.BlizzStyle.Active("castbar") == "classic") and EllesmereUI.BlizzStyle.ClassicBorderSizeCfg(
                function() local p = DB(); return p and p.castBar.stockBorderScale end,
                function(v)
                    local p = DB(); if not p then return end
                    p.castBar.stockBorderScale = v; RefreshCast()
                    if EllesmereUI.ReapplyMatchPads then EllesmereUI.ReapplyMatchPads("ERB_CastBar") end
                end,
                { disabled = castOff, disabledTooltip = "Player Cast Bar" }) or
            EllesmereUI.BlizzStyle.Gate("castbar", EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              getStep = function() local p = DB(); return p and (p.castBar.borderSize or 0) or 0 end,
              setStep = function(v) local p = DB(); if p then p.castBar.borderSize = v end end,
              getTex = function() local p = DB(); return p and (p.castBar.borderTexture or "solid") or "solid" end,
              getPx = function() local p = DB(); return p and p.castBar.borderSizePx end,
              setPx = function(v) local p = DB(); if p then p.castBar.borderSizePx = v end end,
              apply = function() RefreshCast(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
        do
            local p = DB()
            local tex = p and p.castBar.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local p = DB(); return p and (p.castBar.borderSize or 0) or 0 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = castOff,
                    disabledTooltip = "Player Cast Bar",
                    getTex = function() local p = DB(); return p and (p.castBar.borderTexture or "solid") or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local p = DB(); return p and p.castBar.borderSizePx end,
                    getX = function() local p = DB(); return p and p.castBar.borderTextureOffset end,
                    setX = function(v) local p = DB(); if p then p.castBar.borderTextureOffset = v end end,
                    getY = function() local p = DB(); return p and p.castBar.borderTextureOffsetY end,
                    setY = function(v) local p = DB(); if p then p.castBar.borderTextureOffsetY = v end end,
                    apply = function() RefreshCast(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("castbar", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("castbar", ocfgR));  y = y - h
            end
        end
        -- Inline border color swatch on Border slider (right region); none
        -- under Classic WoW UI, whose slider sizes the vanilla frame.
        if not EllesmereUI._prebuilding and EllesmereUI.BlizzStyle.Active("castbar") ~= "classic" then
            local rgn = cbBsRow._rightRegion
            local ctrl = rgn._control
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, cbBsRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.castBar.borderR or 0), (p and p.castBar.borderG or 0),
                           (p and p.castBar.borderB or 0), (p and p.castBar.borderA or 1)
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.castBar.borderR, p.castBar.borderG, p.castBar.borderB, p.castBar.borderA = r, g, b, a
                    RefreshCast(); EllesmereUI:RefreshPage()
                end,
                true, 20)
            PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            -- Disable swatch when border size is 0
            local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
            borderSwatchBlock:SetAllPoints()
            borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
            borderSwatchBlock:EnableMouse(true)
            borderSwatchBlock:SetScript("OnEnter", function()
                if EllesmereUI.BlizzStyle.Get("castbar") then
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("Blizzard Style", "disabled"))
                else
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
                end
            end)
            borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderSwatchState()
                local p = DB()
                local noBorder = not p or (p.castBar.borderSize or 0) == 0 or EllesmereUI.BlizzStyle.Get("castbar")
                if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateBorderSwatchState() end)
            UpdateBorderSwatchState()
        end
        if not EllesmereUI._prebuilding then
            local rgn = cbBsRow._leftRegion
            local sepValues, sepOrder = ns.ERB_SeparatorArtValues(true)
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local p = DB(); if not p then return 0 end
                          local v = p.castBar.borderTextureShiftX
                          if v then return v end
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                          return dsx
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderTextureShiftX = v == 0 and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local p = DB(); if not p then return 0 end
                          local v = p.castBar.borderTextureShiftY
                          if v then return v end
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                          return dsy
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderTextureShiftY = v == 0 and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local p = DB(); return p and p.castBar.borderBehind or false end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderBehind = v == false and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    -- Extend Top / Extend Bottom: the whole border host (bar + icon). This cog
                    -- has no bar-off block, so the rows carry their own.
                    { type = "slider", label = "Extend Top", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                      disabled = castOff, disabledTooltip = "Player Cast Bar",
                      get = function() local p = DB(); return p and p.castBar.borderExtendTop or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderExtendTop = v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Extend Bottom", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                      disabled = castOff, disabledTooltip = "Player Cast Bar",
                      get = function() local p = DB(); return p and p.castBar.borderExtendBottom or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderExtendBottom = v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art. Across the whole bar, icon included.
                    { type = "dropdown", label = "Bottom Separator", values = sepValues, order = sepOrder,
                      tooltip = "Draws a separator line along the bar's bottom edge.",
                      disabled = castOff, disabledTooltip = "Player Cast Bar",
                      get = function()
                          local p = DB(); if not (p and p.castBar.edgeSep) then return "none" end
                          return p.castBar.edgeSepArt or "match"
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          if v == "none" then p.castBar.edgeSep = false else p.castBar.edgeSep = true; p.castBar.edgeSepArt = v end
                          RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Separator Y Offset", min = -50, max = 50, step = 1,
                      disabled = function() local p = DB(); return castOff() or not (p and p.castBar.edgeSep) end,
                      disabledTooltip = function() return castOff() and "Player Cast Bar" or "Bottom Separator" end,
                      get = function() local p = DB(); return p and p.castBar.edgeSepY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.edgeSepY = v; RefreshCast(); EllesmereUI:RefreshPage()
                      end },
                },
            })
            local function UpdateCogVis()
                local p = DB()
                local tex = p and p.castBar.borderTexture or "solid"
                if tex == "solid" or EllesmereUI.BlizzStyle.Get("castbar") then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row 2: Fill Color (opacity slider + inline swatches + cog: gradient) | Background
    local castColorRow
    castColorRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and (p.castBar.fillOpacity or 100) or 100 end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.fillOpacity = v; RefreshCast()
          end },
        ns.ERB_CastBlizzOnlyGate({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function()
              local p = DB(); return math.floor(((p and p.castBar.bgA or 0.7) * 100) + 0.5)
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.bgA = v / 100; RefreshCast()
          end })
    );  y = y - h
    -- Fill Color inline swatches: gradient end / custom / class. Blizzard Style
    -- keeps the stock fill art, so the colour swatches are inert there; the
    -- Classic WoW UI fill is the user's, so they stay live under it.
    local castFillBlizz = EllesmereUI.BlizzStyle.Active("castbar") == "blizzard"
    EllesmereUI.BuildInlineSwatches(castColorRow._leftRegion, {
              { tooltip = "Gradient End Color", hasAlpha = true,
                disabled = function()
                    local p = DB()
                    if not p or not p.castBar.enabled then return true end
                    return not p.castBar.gradientEnabled
                end,
                disabledTooltip = function()
                    if castFillBlizz then return "This option requires Blizzard Style to be disabled" end
                    local p = DB()
                    if not p or not p.castBar.enabled then return "Player Cast Bar" end
                    return "Gradient"
                end,
                getValue = function()
                    local p = DB()
                    if not p then return 0.20, 0.20, 0.80, 1 end
                    return p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA
                end,
                setValue = function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA = r, g, b, a
                    RefreshCast()
                end },
              { tooltip = "Custom Colored", hasAlpha = false,
                getValue = function()
                    local p = DB()
                    if not p then
                        local _, cf = UnitClass("player")
                        local cc = CLASS_COLORS[cf]
                        return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1
                    end
                    return p.castBar.fillR, p.castBar.fillG, p.castBar.fillB, 1
                end,
                setValue = function(r, g, b)
                    local p = DB(); if not p then return end
                    p.castBar.fillR, p.castBar.fillG, p.castBar.fillB = r, g, b
                    if p.castBar.classColored then p.castBar.classColored = false end
                    RefreshCast(); EllesmereUI:RefreshPage()
                end,
                onClick = function(self)
                    local p = DB(); if not p then return end
                    if p.castBar.classColored then
                        p.castBar.classColored = false
                        RefreshCast(); EllesmereUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function()
                    local p = DB()
                    return (p and not p.castBar.classColored) and 1 or 0.3
                end },
              { tooltip = "Class Colored",
                getValue = function()
                    local _, classFile = UnitClass("player")
                    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then return cc.r, cc.g, cc.b, 1 end
                    return 1, 0.70, 0, 1
                end,
                setValue = function() end,
                onClick = function()
                    local p = DB(); if not p then return end
                    p.castBar.classColored = true
                    RefreshCast(); EllesmereUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local p = DB()
                    return (not p or p.castBar.classColored == true) and 1 or 0.3
                end },
    }, { disabled = function() return castFillBlizz or castOff() end,
         disabledTooltip = function()
             if castFillBlizz then return "This option requires Blizzard Style to be disabled" end
             return "Player Cast Bar"
         end })
    -- Inline cog on Fill Color for gradient settings
    if not EllesmereUI._prebuilding then
        local rgn = castColorRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local p = DB(); return castFillBlizz or (p and not p.castBar.enabled) end,
            disabledTooltip = castFillBlizz and "Blizzard Style" or "Player Cast Bar",
            requireState = castFillBlizz and "disabled" or nil,
            title = "Gradient Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local p = DB(); return p and p.castBar.gradientEnabled end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.gradientEnabled = v; RefreshCast()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                  order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local p = DB(); return p and p.castBar.gradientDir or "HORIZONTAL" end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.gradientDir = v; RefreshCast()
                  end },
            },
        })
    end

    -- Inline color swatch on Background (right region)
    if not EllesmereUI._prebuilding then
        local rgn = castColorRow._rightRegion
        local ctrl = rgn._control
        local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, castColorRow:GetFrameLevel() + 3,
            function()
                local p = DB()
                return (p and p.castBar.bgR or 0), (p and p.castBar.bgG or 0), (p and p.castBar.bgB or 0)
            end,
            function(r, g, b)
                local p = DB(); if not p then return end
                p.castBar.bgR, p.castBar.bgG, p.castBar.bgB = r, g, b
                RefreshCast()
            end,
            nil, 20)
        PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local p = DB()
            -- Gated with the Background slider beside it: Blizzard Style
            -- paints the stock background art; the classic bar keeps this colour.
            if EllesmereUI.BlizzStyle.Active("castbar") == "blizzard" then
                bgSwatch:SetAlpha(0.15); bgSwatch:Disable()
                bgSwatch._disabledTooltip = EllesmereUI.BlizzStyle.Label("castbar")
            elseif not p or not p.castBar.enabled then
                bgSwatch:SetAlpha(0.15); bgSwatch:Disable()
                bgSwatch._disabledTooltip = "Player Cast Bar"
            else
                bgSwatch:SetAlpha(1); bgSwatch:Enable()
                bgSwatch._disabledTooltip = nil
            end
            bgUpdateSwatch()
        end
        UpdateBgSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatch)
    end

    -- Row 3: Bar Texture | Spell Text (cog RESIZE: text size + x/y)
    -- Bar Texture is gated under Blizzard Style only (the stock fill art);
    -- the Classic WoW UI fill is the user's texture, so the row stays live.
    local castTexCfg = { type = "dropdown", text = "Bar Texture",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          values = texValues, order = texOrder,
          getValue = function() local p = DB(); return p and p.castBar.texture or "none" end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.texture = v; RefreshCast()
          end }
    if EllesmereUI.BlizzStyle.Active("castbar") == "blizzard" then EllesmereUI.BlizzStyle.Gate("castbar", castTexCfg) end
    local textRow
    textRow, h = W:DualRow(parent, y,
        castTexCfg,
        { type = "dropdown", text = "Spell Text",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          values = { none = "None", left = "Left", right = "Right", center = "Center" },
          order = { "none", "left", "right", "center" },
          getValue = function()
              local p = DB(); if not p or not p.castBar.showSpellText then return "none" end
              return p.castBar.spellTextSide or "left"
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              if v == "none" then
                  p.castBar.showSpellText = false
              else
                  p.castBar.showSpellText = true
                  p.castBar.spellTextSide = v
              end
              RefreshCast(); EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    -- Spell Text colour (RGBA; white = the untinted text), left of the dropdown;
    -- the Spell Text Settings cog below chains left of it. Dimmed and blocked
    -- while the cast bar is off or Spell Text is None.
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(textRow._rightRegion, {
            { tooltip = "Spell Text Color", hasAlpha = true,
              disabled = function()
                  local p = DB()
                  return not (p and p.castBar.enabled and p.castBar.showSpellText)
              end,
              disabledTooltip = function() return castOff() and "Player Cast Bar" or "Spell Text" end,
              getValue = function()
                  local p = DB(); if not p then return 1, 1, 1, 1 end
                  local c = p.castBar
                  return c.spellTextR or 1, c.spellTextG or 1, c.spellTextB or 1, c.spellTextA or 1
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  local c = p.castBar
                  c.spellTextR, c.spellTextG, c.spellTextB, c.spellTextA = r, g, b, a
                  RefreshCast(); EllesmereUI:RefreshPage()
              end },
        }, { size = 20 })
    end
    -- Inline cog (RESIZE) on Spell Text for text size + x/y
    if not EllesmereUI._prebuilding then
        local rgn = textRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local p = DB(); return p and (not p.castBar.enabled or not p.castBar.showSpellText) end,
            disabledTooltip = "Player Cast Bar",
            title = "Spell Text Settings",
            rows = {
                { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                  get = function() local p = DB(); return p and p.castBar.spellTextSize or 11 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.spellTextSize = v; RefreshCast()
                  end },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.castBar.spellTextX or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.spellTextX = v; RefreshCast()
                  end },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.castBar.spellTextY or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.spellTextY = v; RefreshCast()
                  end },
            },
        })
    end
    -- Row 4: Duration Text (cog RESIZE: timer size + x/y) | Show Total Duration
    local timerRow
    timerRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Duration Text",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          values = { none = "None", right = "Right", left = "Left" },
          order = { "none", "right", "left" },
          getValue = function()
              local p = DB(); if not p or not p.castBar.showTimer then return "none" end
              return p.castBar.timerSide or "right"
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              if v == "none" then
                  p.castBar.showTimer = false
              else
                  p.castBar.showTimer = true
                  p.castBar.timerSide = v
              end
              RefreshCast(); EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Show Total Duration",
          tooltip = "Shows elapsed / total duration (e.g. 0.4 / 2.0) instead of counting down from the total.",
          disabled = function()
              local p = DB()
              return castOff() or not (p and p.castBar.showTimer)
          end,
          disabledTooltip = "Duration Text",
          getValue = function() local p = DB(); return p and p.castBar.showTotalDuration end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showTotalDuration = v; RefreshCast()
          end }
    );  y = y - h
    -- Duration Text colour (RGBA; white = the untinted text), left of the
    -- dropdown; the Timer Settings cog below chains left of it. Dimmed and
    -- blocked while the cast bar is off or Duration Text is None.
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(timerRow._leftRegion, {
            { tooltip = "Duration Text Color", hasAlpha = true,
              disabled = function()
                  local p = DB()
                  return not (p and p.castBar.enabled and p.castBar.showTimer)
              end,
              disabledTooltip = function() return castOff() and "Player Cast Bar" or "Duration Text" end,
              getValue = function()
                  local p = DB(); if not p then return 1, 1, 1, 1 end
                  local c = p.castBar
                  return c.timerR or 1, c.timerG or 1, c.timerB or 1, c.timerA or 1
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  local c = p.castBar
                  c.timerR, c.timerG, c.timerB, c.timerA = r, g, b, a
                  RefreshCast(); EllesmereUI:RefreshPage()
              end },
        }, { size = 20 })
    end
    -- Inline cog (RESIZE) on Duration Text for timer size + x/y
    if not EllesmereUI._prebuilding then
        local rgn = timerRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local p = DB(); return p and (not p.castBar.enabled or not p.castBar.showTimer) end,
            disabledTooltip = "Player Cast Bar",
            title = "Timer Settings",
            rows = {
                { type = "slider", label = "Timer Size", min = 8, max = 24, step = 1,
                  get = function() local p = DB(); return p and p.castBar.timerSize or 11 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.timerSize = v; RefreshCast()
                  end },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.castBar.timerX or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.timerX = v; RefreshCast()
                  end },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.castBar.timerY or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.timerY = v; RefreshCast()
                  end },
            },
        })
    end


    -- MARKS section
    _, h = W:SectionHeader(parent, "TICK MARKERS", y);  y = y - h

    local marksOff = function()
        local p = DB()
        return castOff() or not (p and p.castBar.showChannelTicks)
    end

    -- Helper: attach an inline color swatch to a region with disabled overlay
    local function AttachInlineSwatch(rgn, getFunc, setFunc, disabledFunc, disabledTooltip)
        if EllesmereUI._prebuilding then return end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, getFunc, setFunc, true, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)

        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints()
        block:SetFrameLevel(swatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(disabledTooltip))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        EllesmereUI.RegisterWidgetRefresh(function()
            local off = disabledFunc()
            swatch:SetAlpha(off and 0.3 or 1)
            if off then block:Show() else block:Hide() end
            updateSwatch()
        end)
        local initOff = disabledFunc()
        swatch:SetAlpha(initOff and 0.3 or 1)
        if initOff then block:Show() else block:Hide() end
    end

    -- Marks Row 1: Enable Tick Markers (master) | Channel Ticks (+ color)
    local marksRow1
    marksRow1, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Tick Markers",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.showChannelTicks end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showChannelTicks = v
              if v and not (p.castBar.showTickMarks or p.castBar.showLastTick) then
                  p.castBar.showTickMarks = true
              end
              RefreshCast()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Channel Ticks",
          tooltip = "Shows tick marks on channeled spells. Only supported spells are shown, request missing spells on Discord.",
          disabled = marksOff,
          disabledTooltip = "Tick Markers",
          getValue = function() local p = DB(); return p and p.castBar.showTickMarks end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showTickMarks = v; RefreshCast()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    AttachInlineSwatch(marksRow1._rightRegion,
        function()
            local p = DB(); if not p then return 1, 1, 1, 0.7 end
            return p.castBar.tickMarksR or 1, p.castBar.tickMarksG or 1,
                   p.castBar.tickMarksB or 1, p.castBar.tickMarksA or 0.7
        end,
        function(r, g, b, a)
            local p = DB(); if not p then return end
            p.castBar.tickMarksR = r; p.castBar.tickMarksG = g
            p.castBar.tickMarksB = b; p.castBar.tickMarksA = a
            RefreshCast()
        end,
        function() return marksOff() or not (DB() and DB().castBar.showTickMarks) end,
        "Channel Ticks"
    )

    -- Marks Row 2: Last Tick (+ color) | Colored Empowered Stages
    local marksRow2
    marksRow2, h = W:DualRow(parent, y,
        { type = "toggle", text = "Last Tick",
          tooltip = "Highlights the final damage tick. Requires a supported channeled spell.",
          disabled = marksOff,
          disabledTooltip = "Tick Markers",
          getValue = function() local p = DB(); return p and p.castBar.showLastTick end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.showLastTick = v; RefreshCast()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Colored Empowered Stages",
          tooltip = "Changes the cast bar color based on the current empower stage. Colors transition from red (stage 1) through yellow to green (max stage).",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.coloredEmpowerStages end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.coloredEmpowerStages = v; RefreshCast()
          end }
    );  y = y - h

    AttachInlineSwatch(marksRow2._leftRegion,
        function()
            local p = DB(); if not p then return 1, 0.82, 0, 0.95 end
            return p.castBar.lastTickR or 1, p.castBar.lastTickG or 0.82,
                   p.castBar.lastTickB or 0, p.castBar.lastTickA or 0.95
        end,
        function(r, g, b, a)
            local p = DB(); if not p then return end
            p.castBar.lastTickR = r; p.castBar.lastTickG = g
            p.castBar.lastTickB = b; p.castBar.lastTickA = a
            RefreshCast()
        end,
        function() return marksOff() or not (DB() and DB().castBar.showLastTick) end,
        "Last Tick"
    )

    -- LATENCY section
    _, h = W:SectionHeader(parent, "LATENCY", y);  y = y - h

    local latOff = function()
        local p = DB()
        return castOff() or not (p and p.castBar.latencyEnabled)
    end

    -- Latency Row 1: Enable Latency Overlay (+ color) | Show Latency Text
    local latRow1
    latRow1, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Latency Overlay",
          tooltip = "Shows a colored overlay at the end of the cast bar representing your network latency for each spell. Helps you time spell queuing.",
          disabled = castOff,
          disabledTooltip = "Player Cast Bar",
          getValue = function() local p = DB(); return p and p.castBar.latencyEnabled end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.latencyEnabled = v; RefreshCast()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Show Latency Text",
          tooltip = "Appends your latency in milliseconds to the cast timer, e.g. 1.8 (42ms).",
          disabled = latOff,
          disabledTooltip = "Latency Overlay",
          getValue = function() local p = DB(); return p and p.castBar.latencyShowText end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.castBar.latencyShowText = v; RefreshCast()
          end }
    );  y = y - h

    AttachInlineSwatch(latRow1._leftRegion,
        function()
            local p = DB(); if not p then return 0.835, 0.290, 0.290, 1 end
            return p.castBar.latencyR or 0.835, p.castBar.latencyG or 0.290,
                   p.castBar.latencyB or 0.290, p.castBar.latencyA or 1
        end,
        function(r, g, b, a)
            local p = DB(); if not p then return end
            p.castBar.latencyR = r; p.castBar.latencyG = g
            p.castBar.latencyB = b; p.castBar.latencyA = a
            RefreshCast()
        end,
        latOff,
        "Latency Overlay"
    )

    -- Wire up click mappings for cast bar preview hit overlays (never from a hidden pre-build: the shared live table would end up pointing at off-screen rows)
    if not EllesmereUI._prebuilding then
        _clickMappings.castBar       = { section = castSection, target = classSizeRow }
        _clickMappings.castIcon      = { section = castSection, target = iconRow, slotSide = "left" }
        _clickMappings.castSpellText = { section = displaySection, target = textRow, slotSide = "right" }
        _clickMappings.castTimer     = { section = displaySection, target = timerRow, slotSide = "left" }
    end

    return math.abs(y)
end
