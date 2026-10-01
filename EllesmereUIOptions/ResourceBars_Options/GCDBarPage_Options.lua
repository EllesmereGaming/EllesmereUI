if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\GCDBarPage_Options.lua
--  Resource Bars options: GCD Bar page. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- GCD Bar page
function ns.ERB_BuildGCDBarPage(pageName, parent, yOffset)
    local env = ns._ERB_OptEnv
    local DB, PP, CLASS_COLORS = env.DB, env.PP, env.CLASS_COLORS
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Re-append SharedMedia textures (catches lazy-registered SM packs)
    EllesmereUI.AppendSharedMediaTextures(
        _G._ERB_BarTextureNames or {},
        _G._ERB_BarTextureOrder or {},
        nil,
        _G._ERB_BarTextures
    )
    -- Bar texture dropdown values (same set the renderer uses)
    local texValues, texOrder = {}, {}
    do
        local texNames = _G._ERB_BarTextureNames or {}
        local texOrder2 = _G._ERB_BarTextureOrder or {}
        local texLookup = _G._ERB_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then texValues[key] = texNames[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return texLookup[key] end }
    end

    local gcdOff = function() local p = DB(); return p and not p.gcdBar.enabled end

    local function RefreshGCD()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized("ERB_GCDBar")
        end
    end

    local _sec
    _sec, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    local gStrataValues = EllesmereUI.FRAME_STRATA_LABELS
    local gStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE

    -- Row: Enable GCD Bar (+ position cog) | Frame Strata
    local enableRow
    enableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable GCD Bar",
          tooltip = "Shows a bar that fills over the global cooldown.",
          getValue = function() local p = DB(); return p and p.gcdBar.enabled end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.gcdBar.enabled = v; RefreshGCD(); EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          values = gStrataValues, order = gStrataOrder,
          getValue = function() local p = DB(); return p and p.gcdBar.frameStrata or "MEDIUM" end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.frameStrata = v; RefreshGCD() end }
    );  y = y - h
    -- Inline position cog (X/Y + unlock) on Enable
    if not EllesmereUI._prebuilding then
        local rgn = enableRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local p = DB(); return p and not p.gcdBar.enabled end,
            disabledTooltip = "GCD Bar",
            title = "GCD Bar Position",
            rows = {
                -- X/Y edit whichever position is in effect: the saved unlock position takes priority in the renderer, so once it exists these sliders adjust it (otherwise the CENTER offset).
                { type = "slider", label = "X Offset", min = -600, max = 600, step = 1,
                  get = function()
                      local p = DB(); if not p then return 0 end
                      local g = p.gcdBar
                      if g.unlockPos and g.unlockPos.point then return g.unlockPos.x or 0 end
                      return g.anchorX or 0
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      local g = p.gcdBar
                      if g.unlockPos and g.unlockPos.point then g.unlockPos.x = v else g.anchorX = v end
                      RefreshGCD()
                  end },
                { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1,
                  get = function()
                      local p = DB(); if not p then return 0 end
                      local g = p.gcdBar
                      if g.unlockPos and g.unlockPos.point then return g.unlockPos.y or 0 end
                      return g.anchorY or -78
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      local g = p.gcdBar
                      if g.unlockPos and g.unlockPos.point then g.unlockPos.y = v else g.anchorY = v end
                      RefreshGCD()
                  end },
            },
            footer = { unlockKey = "ERB_GCDBar" },
        })
    end

    -- Row: Height | Width. Orientation-aware: this bar's size callbacks report the drawn axes, so its sliders must be guarded on the matching axis for vertical orientations.
    local function gcdOri()
        local p = DB()
        return p and p.gcdBar and p.gcdBar.orientation
    end
    local ghDis, ghTip, ghRaw = ns.OrientedMatchGuard("ERB_GCDBar", "Height", gcdOri, gcdOff, "GCD Bar")
    local gwDis, gwTip, gwRaw = ns.OrientedMatchGuard("ERB_GCDBar", "Width", gcdOri, gcdOff, "GCD Bar")
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Height", min = 1, max = 60, step = 1,
          disabled = ghDis, disabledTooltip = ghTip, rawTooltip = ghRaw,
          getValue = function() local p = DB(); return p and p.gcdBar.height or 12 end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.height = v; RefreshGCD() end },
        { type = "slider", text = "Width", min = 50, max = 800, step = 1,
          disabled = gwDis, disabledTooltip = gwTip, rawTooltip = gwRaw,
          getValue = function() local p = DB(); return p and p.gcdBar.width or 220 end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.width = v; RefreshGCD() end }
    );  y = y - h

    -- Row: Orientation | Instance Only
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Orientation",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          values = { HORIZONTAL = "Horizontal (Right)", HORIZONTAL_LEFT = "Horizontal (Left)", VERTICAL_UP = "Vertical (Up)", VERTICAL_DOWN = "Vertical (Down)" },
          order = { "HORIZONTAL", "HORIZONTAL_LEFT", "VERTICAL_UP", "VERTICAL_DOWN" },
          getValue = function() local p = DB(); return p and p.gcdBar.orientation or "HORIZONTAL" end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.orientation = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
        { type = "toggle", text = "Instance Only",
          tooltip = "Only show the GCD bar while in a dungeon, raid, arena or battleground.",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return p and p.gcdBar.instanceOnly end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.instanceOnly = v; RefreshGCD() end }
    );  y = y - h

    -- Row: Only Instant Casts | Always Show (+ idle fill cog)
    local gcdShowRow
    gcdShowRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Only Instant Casts",
          tooltip = "Only show the GCD bar for instant-cast abilities. While hard-casting or channeling a spell, the bar stays hidden (the cast bar already shows that progress).",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return p and p.gcdBar.instantOnly end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.instantOnly = v; RefreshGCD() end },
        { type = "toggle", text = "Always Show",
          tooltip = "Keep the GCD bar visible (sitting empty) when no global cooldown is running, instead of hiding it.",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return p and p.gcdBar.alwaysShow end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.alwaysShow = v; RefreshGCD() end }
    );  y = y - h
    -- Inline cog on Always Show: idle fill appearance
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(gcdShowRow._rightRegion, {
            title = "Always Show",
            rows = {
                { type = "toggle", label = "Show Fill Color When Idle",
                  tooltip = "Show the bar full of its fill color while no global cooldown is running, instead of the background color.",
                  get = function() local p = DB(); return (p and p.gcdBar.idleShowFill) == true end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      if v then p.gcdBar.idleShowFill = true else p.gcdBar.idleShowFill = nil end
                      RefreshGCD()
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    _sec, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog)
    do
        local btValues, btOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              values=btValues, order=btOrder,
              getValue=function() local p = DB(); return p and p.gcdBar.borderTexture or "solid" end,
              setValue=function(v)
                  local p = DB(); if not p then return end
                  p.gcdBar.borderTexture = v; p.gcdBar.borderTextureOffset = nil; p.gcdBar.borderTextureOffsetY = nil; p.gcdBar.borderTextureShiftX = nil; p.gcdBar.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  p.gcdBar.borderR = _bcol.r; p.gcdBar.borderG = _bcol.g; p.gcdBar.borderB = _bcol.b; p.gcdBar.borderA = 1
                  p.gcdBar.borderBehind = _bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then p.gcdBar.borderSize = defSz end
                  if p.gcdBar.borderSizePx then p.gcdBar.borderSizePx = false end
                  RefreshGCD(); EllesmereUI:RefreshPage(true)
              end },
            EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getStep = function() local p = DB(); return p and (p.gcdBar.borderSize or 0) or 0 end,
              setStep = function(v) local p = DB(); if p then p.gcdBar.borderSize = v end end,
              getTex = function() local p = DB(); return p and (p.gcdBar.borderTexture or "solid") or "solid" end,
              getPx = function() local p = DB(); return p and p.gcdBar.borderSizePx end,
              setPx = function(v) local p = DB(); if p then p.gcdBar.borderSizePx = v end end,
              apply = function() RefreshGCD(); EllesmereUI:RefreshPage() end,
            }));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local p = DB()
            local tex = p and p.gcdBar.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local p = DB(); return p and (p.gcdBar.borderSize or 0) or 0 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = gcdOff, disabledTooltip = "GCD Bar",
                    getTex = function() local p = DB(); return p and (p.gcdBar.borderTexture or "solid") or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local p = DB(); return p and p.gcdBar.borderSizePx end,
                    getX = function() local p = DB(); return p and p.gcdBar.borderTextureOffset end,
                    setX = function(v) local p = DB(); if p then p.gcdBar.borderTextureOffset = v end end,
                    getY = function() local p = DB(); return p and p.gcdBar.borderTextureOffsetY end,
                    setY = function(v) local p = DB(); if p then p.gcdBar.borderTextureOffsetY = v end end,
                    apply = function() RefreshGCD(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end
        -- Border color swatch on the size slider (right region)
        do
            local rgn = bsRow._rightRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bsRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.gcdBar.borderR or 0), (p and p.gcdBar.borderG or 0),
                           (p and p.gcdBar.borderB or 0), (p and p.gcdBar.borderA or 1)
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.gcdBar.borderR, p.gcdBar.borderG, p.gcdBar.borderB, p.gcdBar.borderA = r, g, b, a
                    RefreshGCD(); EllesmereUI:RefreshPage()
                end, true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSwatchState()
                local p = DB()
                local noBorder = not p or (p.gcdBar.borderSize or 0) == 0
                if noBorder then swatch:SetAlpha(0.3); block:Show() else swatch:SetAlpha(1); block:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateSwatchState() end)
            UpdateSwatchState()
        end
        -- Offset cog on Border Style (left region), hidden for "solid"
        if not EllesmereUI._prebuilding then
            local rgn = bsRow._leftRegion
            local sepValues, sepOrder = ns.ERB_SeparatorArtValues(true)
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureShiftX; if v then return v end; local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return dsx end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureShiftX = v == 0 and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureShiftY; if v then return v end; local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return dsy end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureShiftY = v == 0 and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local p = DB(); return p and p.gcdBar.borderBehind or false end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderBehind = v == false and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    -- Extend Top / Extend Bottom (0 = off); the cog has no bar-off block.
                    { type = "slider", label = "Extend Top", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                      disabled = gcdOff, disabledTooltip = "GCD Bar",
                      get = function() local p = DB(); return p and p.gcdBar.borderExtendTop or 0 end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderExtendTop = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "Extend Bottom", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                      disabled = gcdOff, disabledTooltip = "GCD Bar",
                      get = function() local p = DB(); return p and p.gcdBar.borderExtendBottom or 0 end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderExtendBottom = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art.
                    { type = "dropdown", label = "Bottom Separator", values = sepValues, order = sepOrder,
                      tooltip = "Draws a separator line along the bar's bottom edge.",
                      disabled = gcdOff, disabledTooltip = "GCD Bar",
                      get = function() local p = DB(); if not (p and p.gcdBar.edgeSep) then return "none" end; return p.gcdBar.edgeSepArt or "match" end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          if v == "none" then p.gcdBar.edgeSep = false else p.gcdBar.edgeSep = true; p.gcdBar.edgeSepArt = v end
                          RefreshGCD(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Separator Y Offset", min = -50, max = 50, step = 1,
                      disabled = function() local p = DB(); return gcdOff() or not (p and p.gcdBar.edgeSep) end,
                      disabledTooltip = function() return gcdOff() and "GCD Bar" or "Bottom Separator" end,
                      get = function() local p = DB(); return p and p.gcdBar.edgeSepY or 0 end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.edgeSepY = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                },
            })
            local function UpdateCogVis()
                local p = DB()
                local tex = p and p.gcdBar.borderTexture or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row: Color (gradient end / custom / class + gradient cog) | Background (+ bg swatch)
    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "multiSwatch", text = "Color",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          swatches = {
              { tooltip = "Gradient End Color", hasAlpha = true,
                getValue = function() local p = DB(); if not p then return 0.20, 0.20, 0.80, 1 end; return p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA end,
                setValue = function(r, g, b, a) local p = DB(); if not p then return end; p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA = r, g, b, a; RefreshGCD() end },
              { tooltip = "Custom Colored", hasAlpha = true,
                getValue = function() local p = DB(); if not p then local _, cf = UnitClass("player"); local cc = CLASS_COLORS[cf]; return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1 end; return p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA end,
                setValue = function(r, g, b, a) local p = DB(); if not p then return end; p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA = r, g, b, a; if p.gcdBar.classColored then p.gcdBar.classColored = false end; RefreshGCD(); EllesmereUI:RefreshPage() end,
                onClick = function(self) local p = DB(); if not p then return end; if p.gcdBar.classColored then p.gcdBar.classColored = false; RefreshGCD(); EllesmereUI:RefreshPage(); return end; if self._eabOrigClick then self._eabOrigClick(self) end end,
                refreshAlpha = function() local p = DB(); return (p and not p.gcdBar.classColored) and 1 or 0.3 end },
              { tooltip = "Class Colored",
                getValue = function() local _, classFile = UnitClass("player"); local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]; if cc then return cc.r, cc.g, cc.b, 1 end; return 1, 0.70, 0, 1 end,
                setValue = function() end,
                onClick = function() local p = DB(); if not p then return end; p.gcdBar.classColored = true; RefreshGCD(); EllesmereUI:RefreshPage() end,
                refreshAlpha = function() local p = DB(); return (not p or p.gcdBar.classColored == true) and 1 or 0.3 end },
          } },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return math.floor(((p and p.gcdBar.bgA or 0.7) * 100) + 0.5) end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.bgA = v / 100; RefreshGCD() end }
    );  y = y - h
    -- Gradient cog on Color
    if not EllesmereUI._prebuilding then
        local rgn = colorRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local p = DB(); return p and not p.gcdBar.enabled end,
            disabledTooltip = "GCD Bar",
            title = "Gradient Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local p = DB(); return p and p.gcdBar.gradientEnabled end,
                  set = function(v) local p = DB(); if not p then return end; p.gcdBar.gradientEnabled = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local p = DB(); return p and p.gcdBar.gradientDir or "HORIZONTAL" end,
                  set = function(v) local p = DB(); if not p then return end; p.gcdBar.gradientDir = v; RefreshGCD() end },
            },
        })
    end
    -- Gradient end-color swatch enable/disable
    do
        local swatch = colorRow._leftRegion._control
        local function UpdateGradientSwatch()
            local p = DB()
            if not p or not p.gcdBar.enabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = "GCD Bar"
            elseif not p.gcdBar.gradientEnabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = "Gradient"
            else swatch:SetAlpha(1); swatch:Enable(); swatch._disabledTooltip = nil end
        end
        UpdateGradientSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
    end
    -- Background color swatch on the Background slider (right region)
    if not EllesmereUI._prebuilding then
        local rgn = colorRow._rightRegion
        local ctrl = rgn._control
        local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, colorRow:GetFrameLevel() + 3,
            function() local p = DB(); return (p and p.gcdBar.bgR or 0), (p and p.gcdBar.bgG or 0), (p and p.gcdBar.bgB or 0) end,
            function(r, g, b) local p = DB(); if not p then return end; p.gcdBar.bgR, p.gcdBar.bgG, p.gcdBar.bgB = r, g, b; RefreshGCD() end,
            nil, 20)
        PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local p = DB()
            if not p or not p.gcdBar.enabled then bgSwatch:SetAlpha(0.15); bgSwatch:Disable(); bgSwatch._disabledTooltip = "GCD Bar"
            else bgSwatch:SetAlpha(1); bgSwatch:Enable(); bgSwatch._disabledTooltip = nil end
            bgUpdateSwatch()
        end
        UpdateBgSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatch)
    end

    -- Row: Bar Texture | Show Spark
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          values = texValues, order = texOrder,
          getValue = function() local p = DB(); return p and p.gcdBar.texture or "none" end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.texture = v; RefreshGCD() end },
        { type = "toggle", text = "Show Spark",
          tooltip = "Show a small glowing spark that moves along the leading edge of the fill.",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return p and p.gcdBar.showSpark end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.showSpark = v; RefreshGCD() end }
    );  y = y - h

    -- Row: Deplete Fill (left half only)
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Deplete Fill",
          tooltip = "Start the bar full and drain it as the global cooldown elapses, instead of filling it up.",
          disabled = gcdOff, disabledTooltip = "GCD Bar",
          getValue = function() local p = DB(); return p and p.gcdBar.depleteFill end,
          setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.depleteFill = v; RefreshGCD() end },
        { type = "spacer" }
    );  y = y - h

    return math.abs(y)
end
