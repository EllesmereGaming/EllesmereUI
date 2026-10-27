if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\SwingTimerPage_Options.lua
--  Resource Bars options: Swing Timer page. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page
-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

-- Swing Timer page (WoW Forever only: the page exists only where the client
-- has C_SwingTimer; see EUI_ResourceBars_SwingTimer.lua). Same widget set as
-- the GCD Bar page, plus the row/text/range rows the swing timer adds.
function ns.ERB_BuildSwingTimerPage(pageName, parent, yOffset)
    local env = ns._ERB_OptEnv
    local DB, PP = env.DB, env.PP
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    EllesmereUI.AppendSharedMediaTextures(
        _G._ERB_BarTextureNames or {},
        _G._ERB_BarTextureOrder or {},
        nil,
        _G._ERB_BarTextures
    )
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

    local ST_TIP = "Swing Timer"
    local stOff = function() local p = DB(); return p and not p.swingTimer.enabled end

    local function RefreshST()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized("ERB_SwingTimer")
        end
    end

    local _sec
    _sec, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h
    EllesmereUI.BuildSectionUnlockJump(_sec, { key = "ERB_SwingTimer", disabled = stOff, disabledTooltip = ST_TIP })

    local sStrataValues = EllesmereUI.FRAME_STRATA_LABELS
    local sStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE

    -- Row: Enable Swing Timer (+ position cog) | Frame Strata
    local enableRow
    enableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Swing Timer",
          tooltip = "One bar per weapon that can swing, each filling over the time to the next auto attack.",
          getValue = function() local p = DB(); return p and p.swingTimer.enabled end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.swingTimer.enabled = v; RefreshST(); EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          disabled = stOff, disabledTooltip = ST_TIP,
          values = sStrataValues, order = sStrataOrder,
          getValue = function() local p = DB(); return p and p.swingTimer.frameStrata or "MEDIUM" end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.frameStrata = v; RefreshST() end }
    );  y = y - h
    -- Inline position cog (X/Y + unlock) on Enable, as on the GCD Bar page
    if not EllesmereUI._prebuilding then
        local rgn = enableRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local p = DB(); return p and not p.swingTimer.enabled end,
            disabledTooltip = ST_TIP,
            title = "Swing Timer Position",
            rows = {
                { type = "slider", label = "X Offset", min = -600, max = 600, step = 1,
                  get = function()
                      local p = DB(); if not p then return 0 end
                      local g = p.swingTimer
                      if g.unlockPos and g.unlockPos.point then return g.unlockPos.x or 0 end
                      return g.anchorX or 0
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      local g = p.swingTimer
                      if g.unlockPos and g.unlockPos.point then g.unlockPos.x = v else g.anchorX = v end
                      RefreshST()
                  end },
                { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1,
                  get = function()
                      local p = DB(); if not p then return 0 end
                      local g = p.swingTimer
                      if g.unlockPos and g.unlockPos.point then return g.unlockPos.y or 0 end
                      return g.anchorY or -130
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      local g = p.swingTimer
                      if g.unlockPos and g.unlockPos.point then g.unlockPos.y = v else g.anchorY = v end
                      RefreshST()
                  end },
            },
            footer = { unlockKey = "ERB_SwingTimer" },
        })
    end

    -- Row: Row Height | Width. Height is per row; the mover reports the whole stack.
    local shDis, shTip, shRaw = EllesmereUI.MatchGuard("ERB_SwingTimer", "Height", stOff, ST_TIP)
    local swDis, swTip, swRaw = EllesmereUI.MatchGuard("ERB_SwingTimer", "Width", stOff, ST_TIP)
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Row Height", min = 1, max = 60, step = 1,
          tooltip = "Height of each weapon row.",
          disabled = shDis, disabledTooltip = shTip, rawTooltip = shRaw,
          getValue = function() local p = DB(); return p and p.swingTimer.height or 12 end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.height = v; RefreshST() end },
        { type = "slider", text = "Width", min = 50, max = 800, step = 1,
          disabled = swDis, disabledTooltip = swTip, rawTooltip = swRaw,
          getValue = function() local p = DB(); return p and p.swingTimer.width or 220 end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.width = v; RefreshST() end }
    );  y = y - h

    -- Row: Row Spacing | Text Size (+ text offsets cog)
    local stTextRow
    stTextRow, h = W:DualRow(parent, y,
        { type = "slider", pixel = true, text = "Row Spacing", min = 0, max = 20, step = 1,
          tooltip = "Gap between the weapon rows.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.rowSpacing or 2 end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.rowSpacing = v; RefreshST() end },
        { type = "slider", text = "Text Size", min = 6, max = 24, step = 1,
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.textSize or 11 end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.textSize = v; RefreshST() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local function OffsetRow(label, key)
            return { type = "slider", label = label, min = -100, max = 100, step = 1,
              get = function() local p = DB(); return p and p.swingTimer[key] or 0 end,
              set = function(v) local p = DB(); if not p then return end; p.swingTimer[key] = v; RefreshST() end }
        end
        EllesmereUI.BuildInlineCog(stTextRow._rightRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = stOff, disabledTooltip = ST_TIP,
            title = "Text Position",
            rows = {
                OffsetRow("Time X Offset", "timeX"),
                OffsetRow("Time Y Offset", "timeY"),
                OffsetRow("Label X Offset", "labelX"),
                OffsetRow("Label Y Offset", "labelY"),
            },
        })
    end

    -- Row: Visibility (shared checklist) | Hide When Idle (+ idle fill cog)
    local stShowRow
    stShowRow, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = function() local p = DB(); return p and p.swingTimer end,
          legacyKey = "visibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true, noPetBattle = true },
          disabledFn = stOff, disabledTooltip = ST_TIP,
          onChanged = function() RefreshST() end,
          onOptionChanged = function() RefreshST() end },
        { type = "toggle", text = "Hide When Idle",
          tooltip = "Hide the bar while no swing is running.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.hideWhenIdle end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.hideWhenIdle = v; RefreshST() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(stShowRow._rightRegion, {
            title = "Idle Rows",
            rows = {
                { type = "toggle", label = "Show Fill Color When Idle",
                  tooltip = "Show an idle row full of its fill color instead of the background color.",
                  get = function() local p = DB(); return (p and p.swingTimer.idleShowFill) == true end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      if v then p.swingTimer.idleShowFill = true else p.swingTimer.idleShowFill = nil end
                      RefreshST()
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    _sec, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Global Settings > Style: the rows wear the Resource Bars row's stock
    -- frame (ns.ST_Style), which gates the EUI border rows as on the other
    -- bars.
    local stStock = ns.ST_Style() ~= "eui"
    local stClassic = stStock and ns.ERB_BarsClassic()
    local function Gate(cfg)
        if stStock then return EllesmereUI.BlizzStyle.Gate("resourcebars", cfg) end
        return cfg
    end
    if stStock then y = EllesmereUI.BlizzStyle.Note(parent, y, "resourcebars") end

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog).
    -- Classic WoW UI: the Border Size slot sizes the vanilla frame instead.
    do
        local btValues, btOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            Gate({ type="dropdown", text="Border Style",
              disabled = stOff, disabledTooltip = ST_TIP,
              values=btValues, order=btOrder,
              getValue=function() local p = DB(); return p and p.swingTimer.borderTexture or "solid" end,
              setValue=function(v)
                  local p = DB(); if not p then return end
                  local g = p.swingTimer
                  g.borderTexture = v; g.borderTextureOffset = nil; g.borderTextureOffsetY = nil; g.borderTextureShiftX = nil; g.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  g.borderR = _bcol.r; g.borderG = _bcol.g; g.borderB = _bcol.b; g.borderA = 1
                  g.borderBehind = _bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then g.borderSize = defSz end
                  if g.borderSizePx then g.borderSizePx = false end
                  RefreshST(); EllesmereUI:RefreshPage(true)
              end }),
            stClassic and EllesmereUI.BlizzStyle.ClassicBorderSizeCfg(
                function() local p = DB(); return p and p.swingTimer.stockBorderScale end,
                function(v)
                    local p = DB(); if not p then return end
                    p.swingTimer.stockBorderScale = v
                    RefreshST()
                    EllesmereUI.ReapplyMatchPads("ERB_SwingTimer")
                    EllesmereUI:RefreshPage()
                end,
                { disabled = stOff, disabledTooltip = ST_TIP }) or
            Gate(EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = stOff, disabledTooltip = ST_TIP,
              getStep = function() local p = DB(); return p and (p.swingTimer.borderSize or 0) or 0 end,
              setStep = function(v) local p = DB(); if p then p.swingTimer.borderSize = v end end,
              getTex = function() local p = DB(); return p and (p.swingTimer.borderTexture or "solid") or "solid" end,
              getPx = function() local p = DB(); return p and p.swingTimer.borderSizePx end,
              setPx = function(v) local p = DB(); if p then p.swingTimer.borderSizePx = v end end,
              apply = function() RefreshST(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local p = DB()
            local tex = p and p.swingTimer.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local p = DB(); return p and (p.swingTimer.borderSize or 0) or 0 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = stOff, disabledTooltip = ST_TIP,
                    getTex = function() local p = DB(); return p and (p.swingTimer.borderTexture or "solid") or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local p = DB(); return p and p.swingTimer.borderSizePx end,
                    getX = function() local p = DB(); return p and p.swingTimer.borderTextureOffset end,
                    setX = function(v) local p = DB(); if p then p.swingTimer.borderTextureOffset = v end end,
                    getY = function() local p = DB(); return p and p.swingTimer.borderTextureOffsetY end,
                    setY = function(v) local p = DB(); if p then p.swingTimer.borderTextureOffsetY = v end end,
                    apply = function() RefreshST(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y, Gate(ocfgL), Gate(ocfgR));  y = y - h
            end
        end
        -- Border color swatch on the size slider (right region), the Corner
        -- Radius cog left of it; neither in the search pre-build (they index
        -- nothing, and the row is a stand-in there) nor on Classic WoW UI's
        -- frame size slider
        if not EllesmereUI._prebuilding and not stClassic then
            EllesmereUI.BuildInlineSwatches(bsRow._rightRegion, {
                { tooltip = "Border Color", hasAlpha = true,
                  disabled = function()
                      local p = DB()
                      return not (p and p.swingTimer.enabled and (p.swingTimer.borderSize or 0) > 0)
                  end,
                  disabledTooltip = function()
                      if stOff() then return ST_TIP end
                      return "This option requires a Border Size above 0."
                  end,
                  getValue = function()
                      local p = DB()
                      return (p and p.swingTimer.borderR or 0), (p and p.swingTimer.borderG or 0),
                             (p and p.swingTimer.borderB or 0), (p and p.swingTimer.borderA or 1)
                  end,
                  setValue = function(r, g, b, a)
                      local p = DB(); if not p then return end
                      p.swingTimer.borderR, p.swingTimer.borderG, p.swingTimer.borderB, p.swingTimer.borderA = r, g, b, a
                      RefreshST(); EllesmereUI:RefreshPage()
                  end },
            }, { size = 20 })
            -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
            -- border size control. The stock styles keep the rows square.
            EllesmereUI.BuildInlineCog(bsRow._rightRegion, {
                title = "Corner Radius", tip = "Corner Radius",
                disabled = function() if stOff() or stStock then return true end; local p = DB(); return not EllesmereUI.RoundedStyleOK(p and p.swingTimer.borderTexture) end,
                disabledTooltip = function()
                    if stStock then return EllesmereUI.BlizzStyle.Label("resourcebars") end
                    if stOff() then return ST_TIP end
                    return "This option requires the Solid, Glow or Shadow border style."
                end,
                requireState = function() return stStock and "disabled" or "enabled" end,
                rows = EllesmereUI.RoundedCornerRows({
                    { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                      get = function() local p = DB(); return p and p.swingTimer.cornerRadius or 0 end,
                      set = function(v) local p = DB(); if not p then return end; p.swingTimer.cornerRadius = v; RefreshST() end },
                }, function() local p = DB(); return p and p.swingTimer.cornerMask end,
                   function(v) local p = DB(); if not p then return end; p.swingTimer.cornerMask = v; RefreshST() end),
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = bsRow._leftRegion
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function() local p = DB(); if not p then return 0 end; local v = p.swingTimer.borderTextureShiftX; if v then return v end; local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.swingTimer.borderTexture or "solid", p.swingTimer.borderSize or 0); return dsx end,
                      set = function(v) local p = DB(); if not p then return end; p.swingTimer.borderTextureShiftX = v == 0 and nil or v; RefreshST(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function() local p = DB(); if not p then return 0 end; local v = p.swingTimer.borderTextureShiftY; if v then return v end; local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.swingTimer.borderTexture or "solid", p.swingTimer.borderSize or 0); return dsy end,
                      set = function(v) local p = DB(); if not p then return end; p.swingTimer.borderTextureShiftY = v == 0 and nil or v; RefreshST(); EllesmereUI:RefreshPage() end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local p = DB(); return p and p.swingTimer.borderBehind or false end,
                      set = function(v) local p = DB(); if not p then return end; p.swingTimer.borderBehind = v == false and nil or v; RefreshST(); EllesmereUI:RefreshPage() end },
                },
            })
            local function UpdateCogVis()
                local p = DB()
                local tex = p and p.swingTimer.borderTexture or "solid"
                if tex == "solid" or stClassic then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row: Color (gradient end / Main Hand / Off Hand / Ranged / class + gradient cog) | Background (+ bg swatch)
    local function RowSwatch(prefix, tip)
        return { tooltip = tip, hasAlpha = true,
            getValue = function()
                local p = DB(); if not p then return 1, 1, 1, 1 end
                local g = p.swingTimer
                return g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"]
            end,
            setValue = function(r, gg, b, a)
                local p = DB(); if not p then return end
                local g = p.swingTimer
                g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = r, gg, b, a
                if g.classColored then g.classColored = false end
                RefreshST(); EllesmereUI:RefreshPage()
            end,
            onClick = function(self)
                local p = DB(); if not p then return end
                if p.swingTimer.classColored then p.swingTimer.classColored = false; RefreshST(); EllesmereUI:RefreshPage(); return end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end,
            refreshAlpha = function() local p = DB(); return (p and not p.swingTimer.classColored) and 1 or 0.3 end }
    end
    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "multiSwatch", text = "Color",
          disabled = stOff, disabledTooltip = ST_TIP,
          swatches = {
              { tooltip = "Gradient End Color", hasAlpha = true,
                disabled = function() local p = DB(); return not (p and p.swingTimer.gradientEnabled) end,
                disabledTooltip = function() if stOff() then return ST_TIP end; return "Gradient" end,
                getValue = function() local p = DB(); if not p then return 0.20, 0.20, 0.80, 1 end; return p.swingTimer.gradientR, p.swingTimer.gradientG, p.swingTimer.gradientB, p.swingTimer.gradientA end,
                setValue = function(r, g, b, a) local p = DB(); if not p then return end; p.swingTimer.gradientR, p.swingTimer.gradientG, p.swingTimer.gradientB, p.swingTimer.gradientA = r, g, b, a; RefreshST() end },
              RowSwatch("mh", "Main Hand Color"),
              RowSwatch("oh", "Off Hand Color"),
              RowSwatch("r",  "Ranged Color"),
              { tooltip = "Class Colored",
                getValue = function() local _, classFile = UnitClass("player"); local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]; if cc then return cc.r, cc.g, cc.b, 1 end; return 1, 0.70, 0, 1 end,
                setValue = function() end,
                onClick = function() local p = DB(); if not p then return end; p.swingTimer.classColored = true; RefreshST(); EllesmereUI:RefreshPage() end,
                refreshAlpha = function() local p = DB(); return (not p or p.swingTimer.classColored == true) and 1 or 0.3 end },
          } },
        { type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return math.floor(((p and p.swingTimer.bgA or 0.7) * 100) + 0.5) end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.bgA = v / 100; RefreshST() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = colorRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local p = DB(); return p and not p.swingTimer.enabled end,
            disabledTooltip = ST_TIP,
            title = "Gradient Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local p = DB(); return p and p.swingTimer.gradientEnabled end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.gradientEnabled = v; RefreshST(); EllesmereUI:RefreshPage() end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local p = DB(); return p and p.swingTimer.gradientDir or "HORIZONTAL" end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.gradientDir = v; RefreshST() end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineSwatches(colorRow._rightRegion, {
            { tooltip = "Background Color",
              getValue = function() local p = DB(); return (p and p.swingTimer.bgR or 0), (p and p.swingTimer.bgG or 0), (p and p.swingTimer.bgB or 0) end,
              setValue = function(r, g, b) local p = DB(); if not p then return end; p.swingTimer.bgR, p.swingTimer.bgG, p.swingTimer.bgB = r, g, b; RefreshST() end },
        }, { size = 20, disabled = stOff, disabledTooltip = ST_TIP })
    end

    -- Row: Bar Texture | Deplete Fill
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture",
          disabled = stOff, disabledTooltip = ST_TIP,
          values = texValues, order = texOrder,
          getValue = function() local p = DB(); return p and p.swingTimer.texture or "none" end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.texture = v; RefreshST() end },
        { type = "toggle", text = "Deplete Fill",
          tooltip = "Start each row full and drain it as the swing timer elapses, instead of filling it up.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.depleteFill end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.depleteFill = v; RefreshST() end }
    );  y = y - h

    -- Row: Show Spark | Tracked Weapons (checkbox dropdown, built below)
    local sparkRow
    sparkRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Spark",
          tooltip = "Show a small glowing spark that moves along the leading edge of the fill while a swing is running.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.showSpark end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.showSpark = v; RefreshST() end },
        { type = "dropdown", text = "Tracked Weapons",
          tooltip = "Choose which weapons get a swing row. A row also needs a weapon in that slot.",
          disabled = stOff, disabledTooltip = ST_TIP,
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        -- Not tied to Show Spark: a combined off hand's spark shows either way.
        -- Colours: store keys <key>SparkR/G/B/A, unset by default; each swatch
        -- shows the colour the bar paints (ST_SparkColor). A pick of the unset
        -- colour (white, or a combined off hand's fill) stores nothing, so the
        -- picker's Cancel leaves an unset spark following its default.
        local function Near(x, y) return math.abs(x - y) < 0.002 end
        local function SparkSwatch(name, key)
            local prefix = key .. "Spark"
            return { tooltip = name, hasAlpha = true,
                getValue = function()
                    if ns.ST_SparkColor then return ns.ST_SparkColor(key) end
                    return 1, 1, 1, 1
                end,
                setValue = function(r, gg, b, a)
                    local p = DB(); if not p then return end
                    a = a or 1
                    if ns.ST_SparkColor then
                        local ur, ug, ub, ua = ns.ST_SparkColor(key, true)
                        if Near(r, ur) and Near(gg, ug) and Near(b, ub) and Near(a, ua) then
                            r, gg, b, a = nil, nil, nil, nil
                        end
                    end
                    local g = p.swingTimer
                    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = r, gg, b, a
                    RefreshST()
                end }
        end
        EllesmereUI.BuildInlineCog(sparkRow._leftRegion, {
            disabled = stOff, disabledTooltip = ST_TIP,
            title = "Spark",
            rows = {
                { type = "slider", label = "Width", min = 1, max = 32, step = 1,
                  get = function() local p = DB(); return p and p.swingTimer.sparkWidth or 8 end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.sparkWidth = v; RefreshST() end },
                { type = "slider", pixel = true, label = "Overhang", min = 0, max = 20, step = 1,
                  tooltip = "How far the spark reaches past the top and bottom of the bar.",
                  get = function() local p = DB(); return p and p.swingTimer.sparkOverhang or 0 end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.sparkOverhang = v; RefreshST() end },
                { type = "multiswatch", label = "Spark Colors",
                  swatches = {
                      SparkSwatch("Main Hand", "mh"),
                      SparkSwatch("Off Hand", "oh"),
                      SparkSwatch("Ranged", "r"),
                  } },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sparkRow._rightRegion
        if rgn._control then rgn._control:Hide() end
        -- Checked = the row shows. The keys are the per-row toggles this
        -- list replaces (nil = on), so every profile carries over as is.
        local WEAPON_ITEMS = {
            { key = "showMH", label = "Main Hand" },
            { key = "showOH", label = "Off Hand" },
            { key = "showR",  label = "Ranged" },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 210, rgn:GetFrameLevel() + 2, WEAPON_ITEMS,
            function(k) local p = DB(); return not p or p.swingTimer[k] ~= false end,
            function(k, v)
                local p = DB(); if not p then return end
                p.swingTimer[k] = v
                -- The cog's Combine Hands greys out while a hand is off.
                RefreshST(); EllesmereUI:RefreshPage()
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        local function UpdateWeaponsDD()
            local off = stOff()
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
            cbDDRefresh()
        end
        UpdateWeaponsDD()
        EllesmereUI.RegisterWidgetRefresh(UpdateWeaponsDD)
        -- Combine Hands needs both hands tracked, so it rides this row's cog.
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = stOff, disabledTooltip = ST_TIP,
            title = "Tracked Weapons",
            rows = {
                { type = "toggle", label = "Always Show Rows",
                  tooltip = "Show every row ticked in the list even when no weapon is equipped in that slot, so the bar keeps the same layout on every class.",
                  get = function() local p = DB(); return p and p.swingTimer.alwaysShowRows == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.alwaysShowRows = v; RefreshST() end },
                { type = "toggle", label = "Hide Label Without Weapon",
                  tooltip = "A row shown only because of Always Show Rows drops its MH / OH / R label while no weapon is equipped in that slot. A shield keeps its Shield label.",
                  disabled = function() local p = DB(); return not (p and p.swingTimer.alwaysShowRows) end,
                  disabledTooltip = "Always Show Rows",
                  get = function() local p = DB(); return p and p.swingTimer.hideLabelNoWeapon == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.hideLabelNoWeapon = v; RefreshST() end },
                { type = "toggle", label = "Show Shield As Off Hand",
                  tooltip = "Show the Off Hand row, labelled Shield, while a shield is equipped. Always Show Rows also labels it.",
                  get = function() local p = DB(); return p and p.swingTimer.shieldRow == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.shieldRow = v; RefreshST() end },
                { type = "toggle", label = "Combine Hands",
                  tooltip = "Show the off hand as a spark on the Main Hand bar instead of its own row.",
                  disabled = function() local p = DB(); return p and (p.swingTimer.showMH == false or p.swingTimer.showOH == false) end,
                  disabledTooltip = function() local p = DB(); return (p and p.swingTimer.showMH == false) and "Main Hand" or "Off Hand" end,
                  get = function() local p = DB(); return p and p.swingTimer.combineHands == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.combineHands = v; RefreshST() end },
            },
        })
    end

    -- Row: Show Time | Show Weapon Label
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Time",
          tooltip = "Show the seconds left to the next swing on each row.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.showTime ~= false end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.showTime = v; RefreshST() end },
        { type = "toggle", text = "Show Weapon Label",
          tooltip = "Tag each row with its weapon slot: MH (Main Hand), OH (Off Hand), R (Ranged).",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.showLabel ~= false end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.showLabel = v; RefreshST() end }
    );  y = y - h

    -- A cog's colour row: store keys prefix .. R/G/B/A, `def` the fallback
    -- {r, g, b, a}; `off` (optional) greys it out with `offTip`.
    -- `shared` (optional): a prefix whose colour shows while this one is unset.
    local function ColorRow(label, prefix, def, tip, off, offTip, shared)
        return { type = "colorpicker", label = label, tooltip = tip, hasAlpha = true,
            disabled = off, disabledTooltip = offTip,
            get = function()
                local p = DB(); local g = p and p.swingTimer
                if not g then return def[1], def[2], def[3], def[4] end
                local k = prefix
                if shared and g[prefix .. "R"] == nil then k = shared end
                return g[k .. "R"] or def[1], g[k .. "G"] or def[2], g[k .. "B"] or def[3], g[k .. "A"] or def[4]
            end,
            set = function(r, gg, b, a)
                local p = DB(); if not p then return end
                local g = p.swingTimer
                g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = r, gg, b, a
                RefreshST()
            end }
    end
    local stateNotFull = function() local p = DB(); return not p or p.swingTimer.attackState ~= "full" end
    local stateOff = function() local p = DB(); return not p or p.swingTimer.attackState == "off" end
    local guideOff = function() local p = DB(); return not p or (p.swingTimer.moveGuide or "off") == "off" end

    -- Row: Range Check (+ out-of-range alpha cog) | Attack State (+ colors cog)
    local stateRow
    stateRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Range Check",
          tooltip = "Dim a row and paint its text red while the current target is out of that weapon's auto attack range.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.rangeCheck ~= false end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.rangeCheck = v; RefreshST() end },
        { type = "dropdown", text = "Attack State",
          tooltip = "Queued Only colors and names a queued attack; Full also colors rows while the attack is on or waiting.",
          disabled = stOff, disabledTooltip = ST_TIP,
          values = { off = "Off", queued = "Queued Only", full = "Full" },
          order = { "off", "queued", "full" },
          getValue = function() local p = DB(); return p and p.swingTimer.attackState or "queued" end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.attackState = v; RefreshST(); EllesmereUI:RefreshPage() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(stateRow._rightRegion, {
            disabled = stOff, disabledTooltip = ST_TIP,
            title = "Attack State Colors",
            rows = {
                ColorRow("On", "active", { 0.047, 0.824, 0.616, 1 }, "While the attack is on and a swing is running.", stateNotFull, "This option requires Attack State Full."),
                ColorRow("Waiting", "pending", { 0.659, 0.502, 0.949, 1 }, "While the attack is on but nothing is swinging.", stateNotFull, "This option requires Attack State Full."),
                ColorRow("Heroic Strike", "queueHS", { 1, 0.70, 0.20, 1 }, "Heroic Strike queued.", stateOff, "This option requires an Attack State other than Off.", "queue"),
                ColorRow("Raptor Strike", "queueRaptor", { 1, 0.70, 0.20, 1 }, "Raptor Strike queued.", stateOff, "This option requires an Attack State other than Off.", "queue"),
                ColorRow("Maul", "queueMaul", { 1, 0.70, 0.20, 1 }, "Maul queued.", stateOff, "This option requires an Attack State other than Off.", "queue"),
                ColorRow("Cleave", "queueCleave", { 0.95, 0.35, 0.25, 1 }, "Cleave queued.", stateOff, "This option requires an Attack State other than Off."),
                { type = "toggle", label = "Queued On Main Hand Only",
                  tooltip = "Show a queued attack on the Main Hand row only, not on the Off Hand row.",
                  disabled = stateOff, disabledTooltip = "This option requires an Attack State other than Off.",
                  get = function() local p = DB(); return p and p.swingTimer.queueMainHandOnly == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.queueMainHandOnly = v; RefreshST() end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(stateRow._leftRegion, {
            title = "Range Check",
            rows = {
                { type = "slider", label = "Out of Range Opacity", min = 0, max = 100, step = 1,
                  tooltip = "Opacity of a row whose target is out of range.",
                  get = function() local p = DB(); return math.floor(((p and p.swingTimer.outOfRangeAlpha or 0.4) * 100) + 0.5) end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.outOfRangeAlpha = v / 100; RefreshST() end },
            },
        })
    end
    -- Row: Movement Guide (+ GO / STILL colors and Text Cue cog) | (blank: last
    -- row of the section)
    local guideRow
    guideRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Movement Guide",
          tooltip = "Marks when you can move (GO) and, for wand Shoot and Auto Shot, when you must stand still (STILL).",
          disabled = stOff, disabledTooltip = ST_TIP,
          values = { off = "Off", segments = "Segments", windup = "Wind-Up Bar" },
          order = { "off", "segments", "windup" },
          getValue = function() local p = DB(); return p and p.swingTimer.moveGuide or "off" end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.moveGuide = v; RefreshST(); EllesmereUI:RefreshPage() end },
        EllesmereUI.BlankRowCfg()
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(guideRow._leftRegion, {
            disabled = function() return stOff() or guideOff() end,
            disabledTooltip = function() if stOff() then return ST_TIP end; return "Movement Guide" end,
            title = "Movement Guide",
            rows = {
                ColorRow("Go", "latency", { 0.949, 0.957, 0.969, 0.9 }, "The last stretch of each swing, as long as your latency."),
                ColorRow("Still", "aim", { 1, 0.82, 0.25, 0.6 }, "The half second to stand still before a wand or Auto Shot fires."),
                { type = "toggle", label = "Text Cue",
                  tooltip = "The Ranged row's time reads Move (seconds left to move), then Still, then Go. Needs Show Time.",
                  get = function() local p = DB(); return p and p.swingTimer.moveCue == true end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.moveCue = v; RefreshST() end },
            },
        })
    end

    return math.abs(y)
end
