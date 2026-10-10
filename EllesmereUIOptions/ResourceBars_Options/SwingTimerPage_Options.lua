if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\SwingTimerPage_Options.lua
--  Resource Bars options: Swing Timer page. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

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
          caps = { partyIncludesRaid = false, luaDragonriding = true },
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

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog)
    do
        local btValues, btOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
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
              end },
            EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = stOff, disabledTooltip = ST_TIP,
              getStep = function() local p = DB(); return p and (p.swingTimer.borderSize or 0) or 0 end,
              setStep = function(v) local p = DB(); if p then p.swingTimer.borderSize = v end end,
              getTex = function() local p = DB(); return p and (p.swingTimer.borderTexture or "solid") or "solid" end,
              getPx = function() local p = DB(); return p and p.swingTimer.borderSizePx end,
              setPx = function(v) local p = DB(); if p then p.swingTimer.borderSizePx = v end end,
              apply = function() RefreshST(); EllesmereUI:RefreshPage() end,
            }));  y = y - h
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
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end
        do
            local rgn = bsRow._rightRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bsRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.swingTimer.borderR or 0), (p and p.swingTimer.borderG or 0),
                           (p and p.swingTimer.borderB or 0), (p and p.swingTimer.borderA or 1)
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.swingTimer.borderR, p.swingTimer.borderG, p.swingTimer.borderB, p.swingTimer.borderA = r, g, b, a
                    RefreshST(); EllesmereUI:RefreshPage()
                end, true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            rgn._lastInline = swatch  -- the Corner Radius cog chains left of the swatch
            -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
            -- border size control.
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(bsRow._rightRegion, {
                    title = "Corner Radius", tip = "Corner Radius",
                    disabled = function() if stOff() then return true end; local p = DB(); return not EllesmereUI.RoundedStyleOK(p and p.swingTimer.borderTexture) end,
                    disabledTooltip = function() if stOff() then return ST_TIP end; return "This option requires the Solid, Glow or Shadow border style." end,
                    rows = EllesmereUI.RoundedCornerRows({
                        { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                          get = function() local p = DB(); return p and p.swingTimer.cornerRadius or 0 end,
                          set = function(v) local p = DB(); if not p then return end; p.swingTimer.cornerRadius = v; RefreshST() end },
                    }, function() local p = DB(); return p and p.swingTimer.cornerMask end,
                       function(v) local p = DB(); if not p then return end; p.swingTimer.cornerMask = v; RefreshST() end),
                })
            end
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
                local noBorder = not p or (p.swingTimer.borderSize or 0) == 0
                if noBorder then swatch:SetAlpha(0.3); block:Show() else swatch:SetAlpha(1); block:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateSwatchState() end)
            UpdateSwatchState()
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
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
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
    do
        local swatch = colorRow._leftRegion._control
        local function UpdateGradientSwatch()
            local p = DB()
            if not p or not p.swingTimer.enabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = ST_TIP
            elseif not p.swingTimer.gradientEnabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = "Gradient"
            else swatch:SetAlpha(1); swatch:Enable(); swatch._disabledTooltip = nil end
        end
        UpdateGradientSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
    end
    if not EllesmereUI._prebuilding then
        local rgn = colorRow._rightRegion
        local ctrl = rgn._control
        local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, colorRow:GetFrameLevel() + 3,
            function() local p = DB(); return (p and p.swingTimer.bgR or 0), (p and p.swingTimer.bgG or 0), (p and p.swingTimer.bgB or 0) end,
            function(r, g, b) local p = DB(); if not p then return end; p.swingTimer.bgR, p.swingTimer.bgG, p.swingTimer.bgB = r, g, b; RefreshST() end,
            nil, 20)
        PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local p = DB()
            if not p or not p.swingTimer.enabled then bgSwatch:SetAlpha(0.15); bgSwatch:Disable(); bgSwatch._disabledTooltip = ST_TIP
            else bgSwatch:SetAlpha(1); bgSwatch:Enable(); bgSwatch._disabledTooltip = nil end
            bgUpdateSwatch()
        end
        UpdateBgSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatch)
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

    -- Row: Range Check (+ out-of-range alpha cog) | Highlight Queued Attacks
    -- (+ inline Heroic Strike / Maul / Raptor Strike and Cleave colour swatches)
    local queueRow
    queueRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Range Check",
          tooltip = "Dim a row and paint its text red while the current target is out of that weapon's auto attack range.",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.rangeCheck ~= false end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.rangeCheck = v; RefreshST() end },
        { type = "toggle", text = "Highlight Queued Attacks",
          tooltip = "While an on-next-swing attack is queued, the Main Hand and Off Hand rows take its color and show its name (Heroic Strike, Maul and Raptor Strike share one color, Cleave has its own).",
          disabled = stOff, disabledTooltip = ST_TIP,
          getValue = function() local p = DB(); return p and p.swingTimer.queueHighlight ~= false end,
          setValue = function(v) local p = DB(); if not p then return end; p.swingTimer.queueHighlight = v; RefreshST(); EllesmereUI:RefreshPage() end }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(queueRow._leftRegion, {
            title = "Range Check",
            rows = {
                { type = "slider", label = "Out of Range Opacity", min = 0, max = 100, step = 1,
                  tooltip = "Opacity of a row whose target is out of range.",
                  get = function() local p = DB(); return math.floor(((p and p.swingTimer.outOfRangeAlpha or 0.4) * 100) + 0.5) end,
                  set = function(v) local p = DB(); if not p then return end; p.swingTimer.outOfRangeAlpha = v / 100; RefreshST() end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = queueRow._rightRegion
        local ctrl = rgn._control
        -- Heroic Strike / Maul / Raptor Strike (the "queue" keys) beside the toggle,
        -- Cleave to its left.
        local qSwatch, qUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, queueRow:GetFrameLevel() + 3,
            function() local p = DB(); return (p and p.swingTimer.queueR or 1), (p and p.swingTimer.queueG or 0.70), (p and p.swingTimer.queueB or 0.20), (p and p.swingTimer.queueA or 1) end,
            function(r, g, b, a) local p = DB(); if not p then return end; p.swingTimer.queueR, p.swingTimer.queueG, p.swingTimer.queueB, p.swingTimer.queueA = r, g, b, a; RefreshST() end,
            true, 20)
        PP.Point(qSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local cSwatch, cUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, queueRow:GetFrameLevel() + 3,
            function() local p = DB(); return (p and p.swingTimer.queueCleaveR or 0.95), (p and p.swingTimer.queueCleaveG or 0.35), (p and p.swingTimer.queueCleaveB or 0.25), (p and p.swingTimer.queueCleaveA or 1) end,
            function(r, g, b, a) local p = DB(); if not p then return end; p.swingTimer.queueCleaveR, p.swingTimer.queueCleaveG, p.swingTimer.queueCleaveB, p.swingTimer.queueCleaveA = r, g, b, a; RefreshST() end,
            true, 20)
        PP.Point(cSwatch, "RIGHT", qSwatch, "LEFT", -4, 0)
        rgn._lastInline = cSwatch
        -- Hover names the attack a swatch colours, or the requirement while disabled.
        local function SwatchTip(sw, name)
            sw:SetMotionScriptsWhileDisabled(true)
            sw:HookScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, self._disabledTooltip and EllesmereUI.DisabledTooltip(self._disabledTooltip) or name)
            end)
            sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        SwatchTip(qSwatch, "Heroic Strike / Maul / Raptor Strike Color")
        SwatchTip(cSwatch, "Cleave Color")
        local function UpdateQueueSwatch()
            local p = DB()
            local tip
            if not p or not p.swingTimer.enabled then tip = ST_TIP
            elseif p.swingTimer.queueHighlight == false then tip = "Highlight Queued Attacks" end
            if tip then
                qSwatch:SetAlpha(0.15); qSwatch:Disable(); cSwatch:SetAlpha(0.15); cSwatch:Disable()
            else
                qSwatch:SetAlpha(1); qSwatch:Enable(); cSwatch:SetAlpha(1); cSwatch:Enable()
            end
            qSwatch._disabledTooltip = tip; cSwatch._disabledTooltip = tip
            qUpdateSwatch(); cUpdateSwatch()
        end
        UpdateQueueSwatch()
        EllesmereUI.RegisterWidgetRefresh(UpdateQueueSwatch)
    end

    return math.abs(y)
end
