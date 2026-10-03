if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\HealthSection_Options.lua
--  Resource Bars options: HEALTH BAR section builder. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Shared, context-aware HEALTH section builder. ctx.cfg() -> health config table
-- (DB().health). Returns the y after the rendered rows. ctx.advanced is always
-- false: the Advanced per-spec page was retired.
function ns.ERB_BuildHealthSection(parent, y, ctx)
    local env = ns._ERB_OptEnv
    local DB, PP, Refresh, SmoothRefresh = env.DB, env.PP, env.Refresh, env.SmoothRefresh
    local RefreshHealth, RebuildHealth, AddFormBarBtn, AddFormTextBtn = env.RefreshHealth, env.RebuildHealth, env.AddFormBarBtn, env.AddFormTextBtn
    local AttachThresholdNotice, BuildHashCog, BuildThresholdSettingsButton = env.AttachThresholdNotice, env.BuildHashCog, env.BuildThresholdSettingsButton
    local W = EllesmereUI.Widgets
    local _, h
    local function cfg() return ctx.cfg() end
    local function healthOff() local c = cfg(); return not (c and c.enabled) end

    local hdr
    hdr, h = W:SectionHeader(parent, "HEALTH BAR", y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "resourcebars")

    local _advTop = y  -- content top; also used by the Simple override overlay
    -- Row 1: Show Health Bar | Orientation
    local healthEnableRow
    healthEnableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Health Bar",
          getValue = function() local c = cfg(); return c and c.enabled end,
          -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
          setValue = EllesmereUI.DependentSetValue(
              function() local c = cfg(); return c and c.enabled end,
              function(v)
                  local c = cfg(); if not c then return end
                  c.enabled = v; RebuildHealth()
                  EllesmereUI:RefreshPage()
              end) },
        { type = "dropdown", text = "Orientation",
          disabled = healthOff,
          disabledTooltip = "Health Bar",
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
    AddFormBarBtn(healthEnableRow._leftRegion, cfg, RebuildHealth)
    end

    -- Texture lists for the health overlays (EUI_ResourceBars_HealthIndicators.lua): the shared
    -- absorb styles (copied: the SharedMedia tail is appended into the copies) then the
    -- SharedMedia bar textures. The absorb rows keep None (their off switch); the max health
    -- reduction has its own toggle, so its list drops it.
    local hiNames = CopyTable(EllesmereUI.ABSORB_STYLE_NAMES)
    local hiOrder = CopyTable(EllesmereUI.ABSORB_STYLE_ORDER)
    local hiHealOrder = CopyTable(EllesmereUI.HEAL_ABSORB_STYLE_ORDER)
    local hiLossOrder = {}
    for _, k in ipairs(hiOrder) do
        if k ~= "none" then hiLossOrder[#hiLossOrder + 1] = k end
    end
    do
        local smNames, smSep = _G._ERB_BarTextureNames or {}, false
        for _, k in ipairs(_G._ERB_BarTextureOrder or {}) do
            if type(k) == "string" and k:find("^sm:") then
                if not smSep then
                    smSep = true
                    hiOrder[#hiOrder + 1] = "---"
                    hiHealOrder[#hiHealOrder + 1] = "---"
                    hiLossOrder[#hiLossOrder + 1] = "---"
                end
                hiNames[k] = smNames[k] or k
                hiOrder[#hiOrder + 1] = k
                hiHealOrder[#hiHealOrder + 1] = k
                hiLossOrder[#hiLossOrder + 1] = k
            end
        end
    end
    -- Preview swatch behind each menu row, resolved exactly like the overlay.
    hiNames._menuOpts = { itemHeight = 28, background = function(k)
        if k and k ~= "---" and k ~= "none" then return ns.HealthIndicatorTex(k) end
    end }

    -- Max health reduction overlay, off by default: its texture and colour are listed while it is on.
    if not EllesmereUI._prebuilding then
        local k = ns.HEALTH_INDICATORS[3]
        local function lossOff() local c = cfg(); return not (c and c[k.show] == true) end
        EllesmereUI.BuildInlineCog(healthEnableRow._leftRegion, {
            title = "Max Health Reduction",
            disabled = healthOff,
            disabledTooltip = "Health Bar",
            rows = {
                { type = "toggle", label = "Show Reduction",
                  get = function() local c = cfg(); return c and c[k.show] == true end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c[k.show] = v or nil; RefreshHealth()
                  end },
                { type = "dropdown", label = "Texture", hidden = lossOff,
                  values = hiNames, order = hiLossOrder,
                  get = function() local c = cfg(); return c and c[k.style] or "striped" end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c[k.style] = v; RefreshHealth()
                  end },
                { type = "colorpicker", label = "Color", hasAlpha = true, hidden = lossOff,
                  get = function()
                      local c = cfg(); local col = c and c[k.color]
                      if col then return col.r or k.r, col.g or k.g, col.b or k.b, col.a or k.a end
                      return k.r, k.g, k.b, k.a
                  end,
                  set = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c[k.color] = { r = r, g = g, b = b, a = a }; RefreshHealth()
                  end },
            },
        })
    end

    -- Per-spec health enables live in Spec Overrides: "Show Health Bar" is captured while editing as a group.

    -- Everything below Row 1 is hidden entirely while the bar is off.
    if not healthOff() then
    -- Absorb Style | Absorb Opacity, then Heal Absorb Style | Heal Absorb Opacity: None turns
    -- the overlay off, the inline swatch sets its colour and the slider its opacity.
    for _, def in ipairs({
        { k = ns.HEALTH_INDICATORS[1], styleText = "Absorb Style", opacityText = "Absorb Opacity", order = hiOrder },
        { k = ns.HEALTH_INDICATORS[2], styleText = "Heal Absorb Style", opacityText = "Heal Absorb Opacity", order = hiHealOrder },
    }) do
        local k, styleText = def.k, def.styleText
        local function styleOf() local c = cfg(); return c and c[k.style] or "none" end
        local function styleOff() return styleOf() == "none" end
        local absorbRow
        absorbRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = styleText, values = hiNames, order = def.order,
              getValue = styleOf,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c[k.style] = (v ~= "none") and v or nil; RefreshHealth()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = def.opacityText, min = 5, max = 100, step = 1,
              disabled = styleOff,
              disabledTooltip = styleText,
              getValue = function() local c = cfg(); return c and c[k.opacity] or k.opacityDef end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c[k.opacity] = v; RefreshHealth()
              end }
        );  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = absorbRow._leftRegion
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, absorbRow:GetFrameLevel() + 3,
                function()
                    local c = cfg(); local col = c and c[k.color]
                    if col then return col.r or k.r, col.g or k.g, col.b or k.b, 1 end
                    return k.r, k.g, k.b, 1
                end,
                function(r, g, b)
                    local c = cfg(); if not c then return end
                    c[k.color] = { r = r, g = g, b = b }; RefreshHealth()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
            -- Blocked while the style is None, and for the outlined stripes, which carry their own colours.
            local swBlock = CreateFrame("Frame", nil, swatch)
            swBlock:SetAllPoints()
            swBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swBlock:EnableMouse(true)
            swBlock:SetScript("OnEnter", function()
                local tip = styleOff() and EllesmereUI.DisabledTooltip(styleText) or "This style uses its own colors"
                EllesmereUI.ShowWidgetTooltip(swatch, tip)
            end)
            swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSwatchDis()
                local st = styleOf()
                local dis = st == "none" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR"
                swatch:SetAlpha(dis and 0.3 or 1)
                if dis then swBlock:Show() else swBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchDis)
            UpdateSwatchDis()
        end
    end

    -- Row 2: Height | Width. A MatchGuard (dimension matched to ANOTHER element via
    -- Unlock Mode) is a global relationship and greys the slider in BOTH modes: a
    -- matched dimension cannot be per-spec overridden (only the "apply to all bars"
    -- sync icons below are Simple-only). Orientation-aware: a vertical bar swaps the
    -- drawn axes, so the Height slider controls what the match calls Width.
    local function healthOri()
        local c, p = cfg(), DB()
        return (c and c.orientation) or (p and p.general and p.general.orientation)
    end
    local function guard(propKey)
        return ns.OrientedMatchGuard("ERB_Health", propKey, healthOri, healthOff, "Health Bar")
    end
    local hhDis, hhTip, hhRaw = guard("Height")
    local hwDis, hwTip, hwRaw = guard("Width")
    local healthSizeRow
    healthSizeRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Height",
          min = 1, max = 40, step = 1,
          disabled = hhDis, disabledTooltip = hhTip, rawTooltip = hhRaw,
          getValue = function() local c = cfg(); return c and c.height or 20 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.height = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Width",
          min = 50, max = 800, step = 1,
          disabled = hwDis, disabledTooltip = hwTip, rawTooltip = hwRaw,
          getValue = function() local c = cfg(); return c and c.width or 220 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.width = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if not ctx.advanced and ctx.syncRows then
        ctx.syncRows.healthHeight = healthSizeRow._leftRegion
        ctx.syncRows.healthWidth  = healthSizeRow._rightRegion
        if not EllesmereUI._prebuilding then
            local rgn = healthSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.health.height or 20
                    p.secondary.pipHeight = v; p.primary.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.health.height or 20
                    return (p.secondary.pipHeight or 20) == v and (p.primary.height or 16) == v
                end,
                flashTargets = function() return { ctx.syncRows.healthHeight, ctx.syncRows.classHeight, ctx.syncRows.powerHeight } end,
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = healthSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.health.width or 220
                    p.secondary.pipWidth = v
                    p.primary.width = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.health.width or 220
                    return (p.primary.width or 220) == v and (p.secondary.pipWidth or 214) == v
                end,
                flashTargets = function() return { ctx.syncRows.healthWidth, ctx.syncRows.classWidth, ctx.syncRows.powerWidth } end,
            })
        end
    end

    -- Health Border Style dropdown + inline offset cog. Style/size/colour/cog operate on cfg(); the cross-bar "apply to all" sync icons (+ _syncRows registration) are Simple-only.
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local hpBsRow
        hpBsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("resourcebars", { type="dropdown", text="Border Style",
              disabled = healthOff,
              disabledTooltip = "Health Bar",
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
                  RebuildHealth(); EllesmereUI:RefreshPage(true)
              end }),
            ns.ERB_ClassicBorderRow() and ns.ERB_ClassicBorderSizeCfg(cfg, healthOff, "Health Bar", RebuildHealth, "ERB_Health") or
            EllesmereUI.BlizzStyle.Gate("resourcebars", EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = healthOff,
              disabledTooltip = "Health Bar",
              getStep = function() local c = cfg(); return c and c.borderSize or 1 end,
              setStep = function(v) local c = cfg(); if c then c.borderSize = v end end,
              getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
              getPx = function() local c = cfg(); return c and c.borderSizePx end,
              setPx = function(v) local c = cfg(); if c then c.borderSizePx = v end end,
              apply = function() RebuildHealth(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
        -- border size control.
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(hpBsRow._rightRegion, {
                title = "Corner Radius", tip = "Corner Radius",
                disabled = function() if healthOff() then return true end; local c = cfg(); return not EllesmereUI.RoundedStyleOK(c and c.borderTexture) end,
                disabledTooltip = function() if healthOff() then return "Health Bar" end; return "This option requires the Solid, Glow or Shadow border style." end,
                rows = {
                    { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                      get = function() local c = cfg(); return c and c.cornerRadius or 0 end,
                      set = function(v) local c = cfg(); if not c then return end; c.cornerRadius = v; RebuildHealth() end },
                },
            })
        end
        -- Width Offset | Height Offset: the textured border's outward offsets get their own row while a
        -- textured style is selected (the stock styles gate it away exactly like the row above).
        do
            local c = cfg()
            local tex = c and c.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local c = cfg(); return c and c.borderSize or 1 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = healthOff,
                    disabledTooltip = "Health Bar",
                    getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local c = cfg(); return c and c.borderSizePx end,
                    getX = function() local c = cfg(); return c and c.borderTextureOffset end,
                    setX = function(v) local c = cfg(); if c then c.borderTextureOffset = v end end,
                    getY = function() local c = cfg(); return c and c.borderTextureOffsetY end,
                    setY = function(v) local c = cfg(); if c then c.borderTextureOffsetY = v end end,
                    apply = function() RebuildHealth(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgR));  y = y - h
            end
        end
        if not EllesmereUI._prebuilding and not ns.ERB_ClassicBorderRow() then
            local rgn = hpBsRow._rightRegion
            local ctrl = rgn._control
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, hpBsRow:GetFrameLevel() + 3,
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
            swBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("Health Bar")) end)
            swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderSwDis()
                if healthOff() then borderSwatch:SetAlpha(0.3); swBlock:Show()
                else borderSwatch:SetAlpha(1); swBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderSwDis)
            UpdateBorderSwDis()
        end
        if not EllesmereUI._prebuilding then
            local rgn = hpBsRow._leftRegion
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
                          c.borderTextureShiftX = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
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
                          c.borderTextureShiftY = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local c = cfg(); return c and c.borderBehind or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderBehind = v == false and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
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
        -- Cross-bar "apply to all" sync icons: Simple only
        if not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding and ns.ERB_ClassicBorderRow() then
            ctx.syncRows.healthBorder = hpBsRow._rightRegion
            ns.ERB_ClassicBorderSync(hpBsRow._rightRegion, DB, "health", SmoothRefresh,
                function() return { ctx.syncRows.healthBorder, ctx.syncRows.classBorder, ctx.syncRows.powerBorder } end)
        elseif not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding then
            ctx.syncRows.healthBorder = hpBsRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = hpBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local s = p.health
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                        ns.ERB_CopyBorderPx(t, s)
                        t.borderBehind = s.borderBehind
                    end
                    apply(p.secondary); apply(p.primary)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.health.borderTexture or "solid"
                    local bh = p.health.borderBehind or false
                    return (p.secondary.borderTexture or "solid") == bt and (p.primary.borderTexture or "solid") == bt
                        and (p.secondary.borderBehind or false) == bh and (p.primary.borderBehind or false) == bh
                end,
                flashTargets = function() return { hpBsRow._leftRegion } end,
            })
            EllesmereUI.BuildSyncIcon({
                region  = hpBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local r, g, b, a = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA
                    local sz = p.health.borderSize or 1
                    local bt = p.health.borderTexture or "solid"
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz; p.secondary.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.secondary, p.health)
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz; p.primary.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.primary, p.health)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA, p.health.borderSize or 1
                    local sbt = p.health.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt and ns.ERB_SameBorderPx(t, p.health) end
                    return eq(p.secondary) and eq(p.primary)
                end,
                flashTargets = function() return { ctx.syncRows.healthBorder, ctx.syncRows.classBorder, ctx.syncRows.powerBorder } end,
            })
        end
    end

    -- Row 4: Opacity | Fill Color (gradient/custom/class). The Opacity "apply to all" sync icon is Simple-only; the gradient swatch disables while threshold coloring is on.
    local healthBorderRow
    healthBorderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Opacity",
          min = 0, max = 100, step = 5,
          disabled = healthOff,
          disabledTooltip = "Health Bar",
          getValue = function() local c = cfg(); return math.floor((c and c.barAlpha or 1) * 100 + 0.5) end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.barAlpha = v / 100; RefreshHealth()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
          disabled = healthOff,
          disabledTooltip = "Health Bar",
          getValue = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.fillOpacity = v; RebuildHealth()
          end }
    );  y = y - h
    -- Fill Color inline swatches: gradient end / custom / class
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildInlineSwatches(healthBorderRow._rightRegion, {
            { tooltip = "Gradient End Color", hasAlpha = true,
              disabled = function()
                  local c = cfg(); if not c then return true end
                  if not c.enabled then return true end
                  local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                  if tse and (tse.thresholdEnabled ~= false) then return true end
                  return not c.gradientEnabled
              end,
              disabledTooltip = function()
                  local c = cfg()
                  if not c or not c.enabled then return "Health Bar" end
                  local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                  if tse and (tse.thresholdEnabled ~= false) then return "This option requires Threshold Settings to be disabled" end
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
                  if not c then return 37/255, 193/255, 29/255, 1 end
                  return c.fillR, c.fillG, c.fillB, 1
              end,
              setValue = function(r, g, b)
                  local c = cfg(); if not c then return end
                  c.fillR, c.fillG, c.fillB = r, g, b
                  if not c.customColored then c.customColored = true end
                  SmoothRefresh(); EllesmereUI:RefreshPage()
              end,
              onClick = function(self)
                  local c = cfg(); if not c then return end
                  if not c.customColored then
                      c.customColored = true
                      RebuildHealth(); EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isClassColored = not c or not c.customColored
                  return isClassColored and 0.3 or 1
              end },
            { tooltip = "Class Colored",
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b, 1 end
                  return 37/255, 193/255, 29/255, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.customColored = false
                  RebuildHealth(); EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isClassColored = not c or not c.customColored
                  return isClassColored and 1 or 0.3
              end },
    }, { disabled = healthOff, disabledTooltip = "Health Bar" })
    end
    if not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding then
        ctx.syncRows.healthOpacity = healthBorderRow._leftRegion
        local rgn = healthBorderRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Opacity to all Bars",
            onClick = function()
                local p = DB(); if not p then return end
                local v = p.health.barAlpha or 1
                p.secondary.barAlpha = v; p.primary.barAlpha = v
                SmoothRefresh(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local p = DB(); if not p then return false end
                local v = p.health.barAlpha or 1
                return (p.secondary.barAlpha or 1) == v and (p.primary.barAlpha or 1) == v
            end,
            flashTargets = function() return { ctx.syncRows.healthOpacity, ctx.syncRows.classOpacity, ctx.syncRows.powerOpacity } end,
        })
    end
    -- Fill Color inline cog: gradient settings
    if not EllesmereUI._prebuilding then
        local rgn = healthBorderRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = "Health Bar",
            title = "Fill Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local c = cfg(); return c and c.gradientEnabled end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.gradientEnabled = v; RebuildHealth()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                  order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local c = cfg(); return c and c.gradientDir or "HORIZONTAL" end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.gradientDir = v; RebuildHealth()
                  end },
            },
        })
    end

    -- Out of Combat Opacity cog: dims the Health bar to this alpha out of combat (100 = no fade); applied by ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat.
    if not EllesmereUI._prebuilding then
        local rgn = healthBorderRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = "Health Bar",
            title = "Out of Combat Opacity",
            rows = {
                { type = "toggle", label = "Fade Out of Combat",
                  get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocFadeEnabled = v; RefreshHealth()
                  end },
                { type = "slider", label = "Opacity",
                  min = 0, max = 100, step = 1,
                  disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                  get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocAlpha = v / 100; RefreshHealth()
                  end },
            },
        })
    end

    -- Text Color disables when the bar is off OR Health Text is None
    local function healthTextDis()
        local c = cfg()
        if not c then return false end
        if not c.enabled then return true end
        return c.textFormat == "none"
    end
    local function healthTextDisTip()
        local c = cfg()
        if c and not c.enabled then return "Health Bar" end
        return "This option requires a Health Text format other than None"
    end

    local healthTextSizeRow
    healthTextSizeRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Health Text",
          disabled = healthOff,
          disabledTooltip = "Health Bar",
          values = { none = "None", perhp = "Health %", perhpnosign = "Health % (No Sign)", curhpshort = "Health #", perhpnum = "Health % | #", both = "Health # | %" },
          order = { "none", "---", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" },
          getValue = function() local c = cfg(); return c and c.textFormat or "none" end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.textFormat = v; RefreshHealth(); EllesmereUI:RefreshPage()
          end },
        { type = "multiSwatch", text = "Text Color",
          disabled = healthTextDis,
          disabledTooltip = healthTextDisTip,
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
                  RebuildHealth(); SmoothRefresh()
              end,
              onClick = function(self)
                  local c = cfg(); if not c then return end
                  if c.textCustomColored == false then
                      c.textCustomColored = true; RebuildHealth()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isClassColored = c and c.textCustomColored == false
                  return isClassColored and 0.3 or 1
              end },
            { tooltip = "Class Colored",
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b, 1 end
                  return 1, 1, 1, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.textCustomColored = false; RebuildHealth()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isClassColored = c and c.textCustomColored == false
                  return isClassColored and 1 or 0.3
              end },
          } }
    );  y = y - h
    -- Health Text inline cog: anchor + x/y offsets
    if not EllesmereUI._prebuilding then
        local rgn = healthTextSizeRow._leftRegion
        local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = "Health Bar",
            title = "Health Text",
            rows = {
                { type = "dropdown", label = "Anchor",
                  values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                  order = { "LEFT", "CENTER", "RIGHT" },
                  tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                  get = function() local c = cfg(); return c and c.textAnchor or "CENTER" end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textAnchor = v; RefreshHealth()
                  end },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = function() local c = cfg(); return c and c.textXOffset or 0 end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textXOffset = v; RefreshHealth()
                  end },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = function() local c = cfg(); return c and c.textYOffset or 0 end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.textYOffset = v; RefreshHealth()
                  end },
            },
        })
        AddFormTextBtn(rgn, cogBtn, cfg, RefreshHealth)
    end

    -- Row 5: Text Size | Threshold Settings
    local healthColorRow
    healthColorRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
          disabled = healthTextDis,
          disabledTooltip = healthTextDisTip,
          getValue = function() local c = cfg(); return c and c.textSize or 11 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.textSize = v; RefreshHealth()
          end },
        { type = "label", text = "Threshold Settings" }
    );  y = y - h
    -- Threshold Settings popup: edits DB().health (multi-spec, with the spec dropdown).

    if not EllesmereUI._prebuilding then
    local _thrNoticeH   -- assigned below: the notice badge lives on the button itself
    local healthSettingsBtn = BuildThresholdSettingsButton({
        parentRgn = healthColorRow._rightRegion,
        getBarData = function() return cfg() end,
        noticeFn = function() if _thrNoticeH then _thrNoticeH() end end,
        singleSpec = ctx.advanced or nil,
        refreshFn = function() RefreshHealth(); SmoothRefresh() end,
        rebuildFn = function() RebuildHealth() end,
        disabledFn = healthOff,
        disabledTip = "Health Bar",
        showHash = false,
        showPartialCog = false,
        thresholdLabel = "Threshold %",
        threshMin = 1, threshMax = 99,
        popupTitle = "Health Bar Threshold",
        defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
    })
    _thrNoticeH = AttachThresholdNotice(healthSettingsBtn, cfg, ctx.advanced and ctx.specID or nil)

    BuildHashCog({
        parentRgn = healthColorRow._rightRegion,
        anchorTo = healthSettingsBtn,
        getBarData = function() return DB().health end,
        refreshFn = function() RebuildHealth() end,
        popupTitle = EllesmereUI.L("Health Bar Hash Lines"),
    })
    end
    -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
    if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
        EllesmereUI.SpecOverrides_AttachEditLock(healthColorRow._rightRegion,
            "Thresholds have their own per-spec system and can't be edited while editing a spec group")
    end
    end   -- close Health Bar hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides Health in Advanced, so edits here aren't silently ignored.
    if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "health") end

    return y
end
