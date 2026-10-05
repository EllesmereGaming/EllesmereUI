if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\PowerSection_Options.lua
--  Resource Bars options: POWER BAR section builder. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Shared, context-aware POWER section builder; mirrors the health one. ctx.cfg() -> power table (DB().primary Simple, per-spec override Advanced).
function ns.ERB_BuildPowerSection(parent, y, ctx)
    local env = ns._ERB_OptEnv
    local DB, PP, Refresh, SmoothRefresh = env.DB, env.PP, env.Refresh, env.SmoothRefresh
    local RefreshPower, RebuildPower, AddFormBarBtn, AddFormTextBtn = env.RefreshPower, env.RebuildPower, env.AddFormBarBtn, env.AddFormTextBtn
    local AttachThresholdNotice, BuildHashCog, BuildThresholdSettingsButton = env.AttachThresholdNotice, env.BuildHashCog, env.BuildThresholdSettingsButton
    local W = EllesmereUI.Widgets
    local _, h
    local function cfg() return ctx.cfg() end
    local function powerOff() local c = cfg(); return not (c and c.enabled) end
    local powerDisTip = "Power Bar"

    local hdr
    hdr, h = W:SectionHeader(parent, "POWER BAR", y);  y = y - h

    local _advTop = y  -- content top; also used by the Simple override overlay
    -- Row 1: Show Power Bar | Orientation
    local powerEnableRow
    powerEnableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Power Bar",
          getValue = function() local c = cfg(); return c and c.enabled end,
          -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
          setValue = EllesmereUI.DependentSetValue(
              function() local c = cfg(); return c and c.enabled end,
              function(v)
                  local c = cfg(); if not c then return end
                  c.enabled = v; RebuildPower()
                  EllesmereUI:RefreshPage()
              end) },
        { type = "dropdown", text = "Orientation",
          disabled = powerOff,
          disabledTooltip = powerDisTip,
          values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
          order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
          getValue = function()
              local c = cfg(); local p = DB()
              return (c and c.orientation) or (p and p.general.orientation) or "HORIZONTAL"
          end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.orientation = v; Refresh()
          end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
    AddFormBarBtn(powerEnableRow._leftRegion, cfg, RebuildPower)
    end

    -- Per-spec power enables live in Spec Overrides: "Show Power Bar" is captured while editing as a group.

    -- Everything below Row 1 is hidden entirely while the bar is off.
    if not powerOff() then
    -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only). Orientation-aware, as on the health bar above.
    local function powerOri()
        local c, p = cfg(), DB()
        return (c and c.orientation) or (p and p.general and p.general.orientation)
    end
    local function guard(propKey)
        return ns.OrientedMatchGuard("ERB_Power", propKey, powerOri, powerOff, powerDisTip)
    end
    local phDis, phTip, phRaw = guard("Height")
    local pwDis, pwTip, pwRaw = guard("Width")
    local powerSizeRow
    powerSizeRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Height",
          min = 1, max = 100, step = 1,
          disabled = phDis, disabledTooltip = phTip, rawTooltip = phRaw,
          getValue = function() local c = cfg(); return c and c.height or 16 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.height = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Width",
          min = 50, max = 800, step = 1,
          disabled = pwDis, disabledTooltip = pwTip, rawTooltip = pwRaw,
          getValue = function() local c = cfg(); return c and c.width or 220 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.width = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if not ctx.advanced and ctx.syncRows then
        ctx.syncRows.powerHeight = powerSizeRow._leftRegion
        ctx.syncRows.powerWidth  = powerSizeRow._rightRegion
        if not EllesmereUI._prebuilding then
            local rgn = powerSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.primary.height or 16
                    p.secondary.pipHeight = v; p.health.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.primary.height or 16
                    return (p.secondary.pipHeight or 20) == v and (p.health.height or 20) == v
                end,
                flashTargets = function() return { ctx.syncRows.powerHeight, ctx.syncRows.classHeight, ctx.syncRows.healthHeight } end,
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = powerSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.primary.width or 220
                    p.secondary.pipWidth = v
                    p.health.width = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.primary.width or 220
                    return (p.secondary.pipWidth or 214) == v and (p.health.width or 220) == v
                end,
                flashTargets = function() return { ctx.syncRows.powerWidth, ctx.syncRows.classWidth, ctx.syncRows.healthWidth } end,
            })
        end
    end

    -- Power Border Style dropdown + inline offset cog
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local pwrBsRow
        pwrBsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("resourcebars", { type="dropdown", text="Border Style",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values=texValues, order=texOrder,
              getValue=function() local c = cfg(); return c and c.borderTexture or "solid" end,
              setValue=function(v)
                  local c = cfg(); if not c then return end
                  c.borderTexture = v; c.borderTextureOffset = nil; c.borderTextureOffsetY = nil; c.borderTextureShiftX = nil; c.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  c.borderR = _bcol.r; c.borderG = _bcol.g; c.borderB = _bcol.b; c.borderA = 1
                  c.borderBehind = _bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then c.borderSize = defSz end
                  if c.borderSizePx then c.borderSizePx = false end
                  RebuildPower(); EllesmereUI:RefreshPage(true)
              end }),
            ns.ERB_ClassicBorderRow() and ns.ERB_ClassicBorderSizeCfg(cfg, powerOff, powerDisTip, RebuildPower, "ERB_Power") or
            EllesmereUI.BlizzStyle.Gate("resourcebars", EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getStep = function() local c = cfg(); return c and c.borderSize or 1 end,
              setStep = function(v) local c = cfg(); if c then c.borderSize = v end end,
              getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
              getPx = function() local c = cfg(); return c and c.borderSizePx end,
              setPx = function(v) local c = cfg(); if c then c.borderSizePx = v end end,
              apply = function() RebuildPower(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
        do
            local c = cfg()
            local tex = c and c.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local c = cfg(); return c and c.borderSize or 1 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = powerOff,
                    disabledTooltip = powerDisTip,
                    getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local c = cfg(); return c and c.borderSizePx end,
                    getX = function() local c = cfg(); return c and c.borderTextureOffset end,
                    setX = function(v) local c = cfg(); if c then c.borderTextureOffset = v end end,
                    getY = function() local c = cfg(); return c and c.borderTextureOffsetY end,
                    setY = function(v) local c = cfg(); if c then c.borderTextureOffsetY = v end end,
                    apply = function() RebuildPower(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgR));  y = y - h
            end
        end
        if not EllesmereUI._prebuilding and not ns.ERB_ClassicBorderRow() then
            local rgn = pwrBsRow._rightRegion
            local ctrl = rgn._control
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, pwrBsRow:GetFrameLevel() + 3,
                function()
                    local c = cfg()
                    return (c and c.borderR or 0), (c and c.borderG or 0),
                           (c and c.borderB or 0), (c and c.borderA or 1)
                end,
                function(r, g, b, a)
                    local c = cfg(); if not c then return end
                    c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                true, 20)
            PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
            local swBlock = CreateFrame("Frame", nil, borderSwatch)
            swBlock:SetAllPoints()
            swBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
            swBlock:EnableMouse(true)
            swBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip(powerDisTip)) end)
            swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderSwDis()
                if powerOff() then borderSwatch:SetAlpha(0.3); swBlock:Show()
                else borderSwatch:SetAlpha(1); swBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderSwDis)
            UpdateBorderSwDis()
        end
        if not EllesmereUI._prebuilding then
            local rgn = pwrBsRow._leftRegion
            local sepValues, sepOrder = ns.ERB_SeparatorArtValues(true)
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local c = cfg(); if not c then return 0 end
                          local v = c.borderTextureShiftX
                          if v then return v end
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                          return dsx
                      end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderTextureShiftX = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local c = cfg(); if not c then return 0 end
                          local v = c.borderTextureShiftY
                          if v then return v end
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                          return dsy
                      end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderTextureShiftY = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local c = cfg(); return c and c.borderBehind or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderBehind = v == false and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    -- Draw Above GCD Bar: this border over a GCD bar that overlaps the power
                    -- bar (ns.ERB_PowerLift). Kept out of the Border Style syncs. Show
                    -- Behind keeps the border under its own fill, so it greys this out.
                    { type = "toggle", label = "Draw Above GCD Bar",
                      tooltip = "Draws the power bar's border above the GCD bar where the two overlap.",
                      disabled = function()
                          local p, c = DB(), cfg()
                          return (powerOff() or not (p and p.gcdBar.enabled) or (c and c.borderBehind)) and true or false
                      end,
                      disabledTooltip = function()
                          if powerOff() then return powerDisTip end
                          local p = DB(); if not (p and p.gcdBar.enabled) then return "GCD Bar" end
                          return "This option can't be used while Show Behind is enabled."
                      end,
                      rawTooltip = function()
                          local p = DB()
                          return not powerOff() and (p and p.gcdBar.enabled) and true or false
                      end,
                      get = function() local c = cfg(); return c and c.borderAboveGCD or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderAboveGCD = v and true or false; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    -- Extend Top / Extend Bottom: 0 = off, stored explicitly (mirror sync
                    -- never carries a nil). Screen axes, so a vertical bar too.
                    { type = "slider", label = "Extend Top", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                      disabled = powerOff, disabledTooltip = powerDisTip,
                      get = function() local c = cfg(); return c and c.borderExtendTop or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendTop = v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Extend Bottom", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                      disabled = powerOff, disabledTooltip = powerDisTip,
                      get = function() local c = cfg(); return c and c.borderExtendBottom or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendBottom = v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art (edgeSepArt). Out of the Border Style syncs.
                    { type = "dropdown", label = "Bottom Separator", values = sepValues, order = sepOrder,
                      tooltip = "Draws a separator line along the bar's bottom edge.",
                      disabled = powerOff, disabledTooltip = powerDisTip,
                      get = function()
                          local c = cfg(); if not (c and c.edgeSep) then return "none" end
                          return c.edgeSepArt or "match"
                      end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          if v == "none" then c.edgeSep = false else c.edgeSep = true; c.edgeSepArt = v end
                          RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Separator Y Offset", min = -50, max = 50, step = 1,
                      disabled = function() local c = cfg(); return powerOff() or not (c and c.edgeSep) end,
                      disabledTooltip = function() return powerOff() and powerDisTip or "Bottom Separator" end,
                      get = function() local c = cfg(); return c and c.edgeSepY or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.edgeSepY = v; RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                },
            })
            local function UpdateCogVis()
                local c = cfg()
                local tex = c and c.borderTexture or "solid"
                if tex == "solid" or ns.ERB_ClassicBorderRow() then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        if not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding and ns.ERB_ClassicBorderRow() then
            ctx.syncRows.powerBorder = pwrBsRow._rightRegion
            ns.ERB_ClassicBorderSync(pwrBsRow._rightRegion, DB, "primary", SmoothRefresh,
                function() return { ctx.syncRows.powerBorder, ctx.syncRows.classBorder, ctx.syncRows.healthBorder } end)
        elseif not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding then
            ctx.syncRows.powerBorder = pwrBsRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = pwrBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local s = p.primary
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                        ns.ERB_CopyBorderPx(t, s)
                        t.borderBehind = s.borderBehind
                    end
                    apply(p.secondary); apply(p.health)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.primary.borderTexture or "solid"
                    local bh = p.primary.borderBehind or false
                    return (p.secondary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                        and (p.secondary.borderBehind or false) == bh and (p.health.borderBehind or false) == bh
                end,
                flashTargets = function() return { pwrBsRow._leftRegion } end,
            })
            EllesmereUI.BuildSyncIcon({
                region  = pwrBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local r, g, b, a = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA
                    local sz = p.primary.borderSize or 1
                    local bt = p.primary.borderTexture or "solid"
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz; p.secondary.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.secondary, p.primary)
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz; p.health.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.health, p.primary)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA, p.primary.borderSize or 1
                    local sbt = p.primary.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt and ns.ERB_SameBorderPx(t, p.primary) end
                    return eq(p.secondary) and eq(p.health)
                end,
                flashTargets = function() return { ctx.syncRows.powerBorder, ctx.syncRows.classBorder, ctx.syncRows.healthBorder } end,
            })
        end
    end

    -- Row 4: Opacity | Fill Color (gradient/custom/power-colored)
    local powerBorderRow
    powerBorderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Opacity",
          min = 0, max = 100, step = 5,
          disabled = powerOff,
          disabledTooltip = powerDisTip,
          getValue = function() local c = cfg(); return math.floor((c and c.barAlpha or 1) * 100 + 0.5) end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.barAlpha = v / 100; RefreshPower()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
          disabled = powerOff,
          disabledTooltip = powerDisTip,
          getValue = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.fillOpacity = v; RebuildPower()
          end }
    );  y = y - h
    -- Fill Color inline swatches: gradient end / custom / power
    if not EllesmereUI._prebuilding then
    -- Spender Colors paint the fill flat once a row names a spell, as the bar does
    -- (unless they recolor the text instead).
    local function SpendersFlatten(c, tse)
        if not (tse and tse.spenderColorEnabled) then return false end
        if tse.thresholdTextInstead and c.textFormat ~= "none" then return false end
        local list = tse.spenderColors
        if list then
            for i = 1, #list do
                if list[i].spellID then return true end
            end
        end
        return false
    end
    EllesmereUI.BuildInlineSwatches(powerBorderRow._rightRegion, {
            { tooltip = "Gradient End Color", hasAlpha = true,
              disabled = function()
                  local c = cfg(); if not c then return true end
                  if not c.enabled then return true end
                  local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                  if tse and (tse.thresholdEnabled ~= false) then return true end
                  if SpendersFlatten(c, tse) then return true end
                  return not c.gradientEnabled
              end,
              disabledTooltip = function()
                  local c = cfg()
                  if not c or not c.enabled then return powerDisTip end
                  local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                  if tse and (tse.thresholdEnabled ~= false) then return "This option requires Threshold Settings to be disabled" end
                  if SpendersFlatten(c, tse) then return "This option requires Spender Colors to be disabled" end
                  return "Gradient"
              end,
              getValue = function()
                  local c = cfg()
                  if not c then return 0.20, 0.20, 0.80, 1 end
                  return c.gradientR, c.gradientG, c.gradientB, c.gradientA
              end,
              setValue = function(r, g, b, a)
                  local c = cfg(); if not c then return end
                  c.gradientR, c.gradientG, c.gradientB, c.gradientA = r, g, b, a
                  SmoothRefresh()
              end },
            { tooltip = "Custom Colored",
              hasAlpha = false,
              getValue = function()
                  local c = cfg()
                  if not c then return 0x23/255, 0x8F/255, 0xE7/255, 1 end
                  return c.fillR, c.fillG, c.fillB, 1
              end,
              setValue = function(r, g, b)
                  local c = cfg(); if not c then return end
                  c.fillR, c.fillG, c.fillB = r, g, b
                  RebuildPower(); SmoothRefresh()
              end,
              onClick = function(self)
                  local c = cfg(); if not c then return end
                  if not c.customColored then
                      c.customColored = true; RebuildPower()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isPowerColored = not c or not c.customColored
                  return isPowerColored and 0.3 or 1
              end },
            { tooltip = "Power Colored",
              getValue = function()
                  -- gpp() is nil for specs with no primary power (BM/MM
                  -- hunter: Focus is the class resource bar) -- fall to
                  -- the default swatch color rather than index with nil.
                  local gpp = _G._ERB_GetPrimaryPowerType
                  local pt = gpp and gpp()
                  local pc = pt and _G._ERB_PowerColors and _G._ERB_PowerColors[pt]
                  if pc then return pc[1], pc[2], pc[3], 1 end
                  return 0x23/255, 0x8F/255, 0xE7/255, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.customColored = false; RebuildPower()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isPowerColored = not c or not c.customColored
                  return isPowerColored and 1 or 0.3
              end },
    }, { disabled = powerOff, disabledTooltip = powerDisTip })
    end
    if not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding then
        ctx.syncRows.powerOpacity = powerBorderRow._leftRegion
        local rgn = powerBorderRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Opacity to all Bars",
            onClick = function()
                local p = DB(); if not p then return end
                local v = p.primary.barAlpha or 1
                p.secondary.barAlpha = v; p.health.barAlpha = v
                SmoothRefresh(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local p = DB(); if not p then return false end
                local v = p.primary.barAlpha or 1
                return (p.secondary.barAlpha or 1) == v and (p.health.barAlpha or 1) == v
            end,
            flashTargets = function() return { ctx.syncRows.powerOpacity, ctx.syncRows.classOpacity, ctx.syncRows.healthOpacity } end,
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = powerBorderRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = powerDisTip,
            title = "Fill Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local c = cfg(); return c and c.gradientEnabled end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.gradientEnabled = v; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                  order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local c = cfg(); return c and c.gradientDir or "HORIZONTAL" end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.gradientDir = v; RebuildPower()
                  end },
            },
        })
    end

    -- Out of Combat Opacity cog: dims the Power bar to this alpha out of combat (100 = no fade); applied by ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat.
    if not EllesmereUI._prebuilding then
        local rgn = powerBorderRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = powerDisTip,
            title = "Out of Combat Opacity",
            rows = {
                { type = "toggle", label = "Fade Out of Combat",
                  get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocFadeEnabled = v; RefreshPower()
                  end },
                { type = "slider", label = "Opacity",
                  min = 0, max = 100, step = 1,
                  disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                  get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocAlpha = v / 100; RefreshPower()
                  end },
            },
        })
    end

    -- Text Color disables when the bar is off OR Power Text is None
    local function powerTextDis()
        local c = cfg()
        if not c then return false end
        if not c.enabled then return true end
        return c.textFormat == "none"
    end
    local function powerTextDisTip()
        local c = cfg()
        if c and not c.enabled then return powerDisTip end
        return "This option requires a Power Text format other than None"
    end

    local powerTextSizeRow
    powerTextSizeRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Power Text",
          disabled = powerOff,
          disabledTooltip = powerDisTip,
          values = { none = "None", smart = "Smart Text", curpp = "Power Value", perpp = "Power %", both = "Power Value | Power %" },
          order = { "none", "smart", "curpp", "perpp", "both" },
          getValue = function() local c = cfg(); return c and c.textFormat or "none" end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.textFormat = v; RefreshPower(); EllesmereUI:RefreshPage()
          end },
        { type = "multiSwatch", text = "Text Color",
          disabled = powerTextDis,
          disabledTooltip = powerTextDisTip,
          swatches = {
            { tooltip = "Custom Colored",
              hasAlpha = true,
              getValue = function()
                  local c = cfg()
                  if not c then return 1, 1, 1, 1 end
                  return c.textFillR, c.textFillG, c.textFillB, c.textFillA
              end,
              setValue = function(r, g, b, a)
                  local c = cfg(); if not c then return end
                  c.textFillR, c.textFillG, c.textFillB, c.textFillA = r, g, b, a
                  RebuildPower(); SmoothRefresh()
              end,
              onClick = function(self)
                  local c = cfg(); if not c then return end
                  if c.textCustomColored == false then
                      c.textCustomColored = true; RebuildPower()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isPowerColored = c and c.textCustomColored == false
                  return isPowerColored and 0.3 or 1
              end },
            { tooltip = "Power Colored",
              getValue = function()
                  -- gpp() is nil for specs with no primary power (BM/MM
                  -- hunter: Focus is the class resource bar) -- fall to
                  -- the default swatch color rather than index with nil.
                  local gpp = _G._ERB_GetPrimaryPowerType
                  local pt = gpp and gpp()
                  local pc = pt and _G._ERB_PowerColors and _G._ERB_PowerColors[pt]
                  if pc then return pc[1], pc[2], pc[3], 1 end
                  return 0x23/255, 0x8F/255, 0xE7/255, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.textCustomColored = false; RebuildPower()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isPowerColored = c and c.textCustomColored == false
                  return isPowerColored and 1 or 0.3
              end },
          } }
    );  y = y - h

    -- Row 5: Text Size | Threshold Settings
    local powerColorRow
    powerColorRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
          disabled = powerTextDis,
          disabledTooltip = powerTextDisTip,
          getValue = function() local c = cfg(); return c and c.textSize or 11 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.textSize = v; RefreshPower()
          end },
        { type = "label", text = "Threshold Settings" }
    );  y = y - h
    -- Power Text inline cog: percent sign, anchor, x/y offsets
    if not EllesmereUI._prebuilding then
        local rgn = powerTextSizeRow._leftRegion
        local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = "Power Bar",
            title = "Power Text",
            rows = {
                { type = "toggle", label = "Show %",
                  get = function() local c = cfg(); return (not c) or c.showPercent ~= false end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.showPercent = v; RefreshPower()
                  end },
                { type = "dropdown", label = "Anchor",
                  values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                  order = { "LEFT", "CENTER", "RIGHT" },
						tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                  get = function() local c = cfg(); return c and c.textAnchor or "CENTER" end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textAnchor = v; RefreshPower()
                  end },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = function() local c = cfg(); return c and c.textXOffset or 0 end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textXOffset = v; RefreshPower()
                  end },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = function() local c = cfg(); return c and c.textYOffset or 0 end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textYOffset = v; RefreshPower()
                  end },
            },
        })
        AddFormTextBtn(rgn, cogBtn, cfg, RefreshPower)
    end
    if not EllesmereUI._prebuilding then
    local _thrNoticeP   -- assigned below: the notice badge lives on the button itself
    local powerSettingsBtn = BuildThresholdSettingsButton({
        parentRgn = powerColorRow._rightRegion,
        getBarData = function() return cfg() end,
        noticeFn = function() if _thrNoticeP then _thrNoticeP() end end,
        singleSpec = ctx.advanced or nil,
        refreshFn = function() RefreshPower(); SmoothRefresh() end,
        rebuildFn = function() RebuildPower() end,
        disabledFn = powerOff,
        disabledTip = "Power Bar",
        showHash = false,
        showPartialCog = true,
        showSpenders = true,
        thresholdLabel = "Threshold %",
        threshMin = 1, threshMax = 99,
        popupTitle = "Power Bar Threshold",
        defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
        formCapable = true,
    })
    _thrNoticeP = AttachThresholdNotice(powerSettingsBtn, cfg, ctx.advanced and ctx.specID or nil)

    BuildHashCog({
        parentRgn = powerColorRow._rightRegion,
        anchorTo = powerSettingsBtn,
        getBarData = function() return DB().primary end,
        refreshFn = function() RebuildPower() end,
        popupTitle = EllesmereUI.L("Power Bar Hash Lines"),
    })
    end
    -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
    if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
        EllesmereUI.SpecOverrides_AttachEditLock(powerColorRow._rightRegion,
            "Thresholds have their own per-spec system and can't be edited while editing a spec group")
    end
    end   -- close Power Bar hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides Power in Advanced, so edits here aren't silently ignored.
    if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "primary") end

    return y
end
