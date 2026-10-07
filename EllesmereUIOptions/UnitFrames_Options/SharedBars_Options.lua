if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedBars_Options.lua
--  Unit Frames options: Health Bar, Power Bar, Class Resource and Absorbs sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
--  EUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end  -- module disabled: no options page

function ns.UFO_BuildHealthBarSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local AddDarkModeBlock, GROUP_UNIT_ORDER, PP, RegisterWidgetRefresh = env.AddDarkModeBlock, env.GROUP_UNIT_ORDER, env.PP, env.RegisterWidgetRefresh
    local ReloadAndUpdate, SHORT_LABELS, UNIT_DB_MAP, UpdatePreview = env.ReloadAndUpdate, env.SHORT_LABELS, env.UNIT_DB_MAP, env.UpdatePreview
    local db, healthTextOrder, healthTextOrderPlayer, healthTextOrderTargetFocus = env.db, env.healthTextOrder, env.healthTextOrderPlayer, env.healthTextOrderTargetFocus
    local healthTextValues, optState = env.healthTextValues, env.optState
    local W, SDB, SGet, SSet = ctx.W, ctx.SDB, ctx.SGet, ctx.SSet
    local SShowsLevel, SVal = ctx.SShowsLevel, ctx.SVal
    local _, h

    -------------------------------------------------------------------
    --  HEALTH BAR
    -------------------------------------------------------------------
    local sharedBarsHeader
    sharedBarsHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

    -- Row 1: Bar Height + Bar Width
    local sharedSizeRow
    local ufhDis, ufhTip, ufhRaw = EllesmereUI.MatchGuard(optState.selectedUnit, "Height")
    local ufwDis, ufwTip, ufwRaw = EllesmereUI.MatchGuard(optState.selectedUnit, "Width")
    sharedSizeRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Health Bar Height", min=15, max=100, step=1,
          disabled=ufhDis, disabledTooltip=ufhTip, rawTooltip=ufhRaw,
          getValue=function() return SVal("healthHeight", 46) end,
          setValue=function(v) SSet("healthHeight", v) end }),
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Bar Width", min=80, max=400, step=1,
          disabled=ufwDis, disabledTooltip=ufwTip, rawTooltip=ufwRaw,
          getValue=function() return SVal("frameWidth", 181) end,
          setValue=function(v) SSet("frameWidth", v) end }));  y = y - h
    -- Blizzard Style: the stock size is fixed, so the whole frame scales instead
    -- (this row is the preview's health-bar click target while the size row hides).
    local sharedScaleRow
    if EllesmereUI.BlizzStyle.Get("unitframes") then
        sharedScaleRow, h = W:DualRow(parent, y,
            { type="slider", text="Frame Scale", min=50, max=200, step=5,
              tooltip="Scales the whole frame. Blizzard Style frames are the stock size, so this stands in for Bar Width and Health Bar Height.",
              getValue=function() return math.floor(SVal("blizzScale", 1) * 100 + 0.5) end,
              setValue=function(v) SSet("blizzScale", v / 100) end },
            -- Reverse Fill otherwise lives in the cog on the hidden size row.
            { type="toggle", text="Reverse Fill",
              getValue=function() return SVal("healthReverseFill", false) end,
              setValue=function(v) SSet("healthReverseFill", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    end
    -- Sync icons: Bar Height (left) and Bar Width (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedSizeRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Health Bar Height to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().healthHeight or 46
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().healthHeight = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().healthHeight or 46
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().healthHeight or 46) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().healthHeight or 46
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().healthHeight = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Reverse Fill cog on Bar Height (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedSizeRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Health Bar Fill",
            rows = {
                { type="toggle", label="Reverse Fill",
                  get=function() return SVal("healthReverseFill", false) end,
                  set=function(v) SSet("healthReverseFill", v); ReloadAndUpdate(); UpdatePreview() end },
                -- Vertical Fill swaps the bar's fill AXIS; Reverse Fill flips the
                -- direction within it (bottom-to-top default, top-to-bottom reversed).
                { type="toggle", label="Vertical Fill",
                  tooltip="Fill the health bar bottom-to-top instead of left-to-right. Reverse Fill flips it to top-to-bottom.",
                  get=function() return SVal("healthVerticalFill", false) end,
                  -- RefreshPage re-labels the Absorbs Placement dropdowns for the
                  -- new axis (cog popups bake labels in at first build).
                  set=function(v) SSet("healthVerticalFill", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedSizeRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Width to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().frameWidth or 181
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().frameWidth = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().frameWidth or 181
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().frameWidth or 181) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().frameWidth or 181
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().frameWidth = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 2: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
    local sharedHealthColorRow
    sharedHealthColorRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Fill Color",
          swatches = {
            { tooltip = "Gradient End Color", hasAlpha = false,
              disabled = function() return not SVal("gradientEnabled", false) end,
              disabledTooltip = function() return "Gradient" end,
              getValue = function()
                  local c = SGet("gradientColor")
                  if c then return c.r, c.g, c.b end
                  return 0.20, 0.20, 0.80
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().gradientColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { tooltip = "Custom Colored Fill",
              hasAlpha = false,
              -- Dynamic Color resolves the fill from health percent, so the flat
              -- custom/class choice below has no effect while it is on. Greyed and
              -- click-blocked rather than reset: the stored customFillColor and
              -- healthClassColored are left exactly as the user had them and come
              -- back untouched the moment Dynamic Color goes to Off.
              disabled = function() return SVal("healthColorMode", "none") ~= "none" end,
              disabledTooltip = "Dynamic Color is on -- the fill color comes from the unit's health", rawTooltip = true,
              getValue = function()
                  local c = SGet("customFillColor")
                  if c then return c.r, c.g, c.b end
                  return 37/255, 193/255, 29/255
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().customFillColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end,
              onClick = function(self)
                  if SVal("healthClassColored", true) then
                      -- Seed the custom fill on first use: without a stored
                      -- customFillColor the runtime falls back to oUF's class/reaction
                      -- color (bar looks unchanged until dragged); never overwrites an existing custom color.
                      if SGet("customFillColor") == nil then
                          UNIT_DB_MAP[optState.selectedUnit]().customFillColor = { r = 37/255, g = 193/255, b = 29/255 }
                      end
                      SSet("healthClassColored", false)
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SVal("healthClassColored", true) and 0.3 or 1
              end },
            { tooltip = "Class Colored Fill",
              hasAlpha = false,
              -- Same as the custom swatch: inert while Dynamic Color is on, so it
              -- greys out instead of silently doing nothing. Class Reactive still
              -- uses the class color, but as the 100% stop of the curve, not as
              -- this flat choice.
              disabled = function() return SVal("healthColorMode", "none") ~= "none" end,
              disabledTooltip = "Dynamic Color is on -- the fill color comes from the unit's health", rawTooltip = true,
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
                  SSet("healthClassColored", true)
                  UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("healthClassColored", true) and 1 or 0.3
              end },
          } },
        { type="slider", text="Bar Background", min=0, max=100, step=1,
          getValue=function() return SVal("customBgAlpha", 100) end,
          setValue=function(v) SSet("customBgAlpha", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    -- Inline swatches on Bar Background (right): Custom + Class pair mirroring the
    -- Bar Color picker; either toggles bgClassColored, the inactive one dims to 0.3.
    if not EllesmereUI._prebuilding then
        local rgn = sharedHealthColorRow._rightRegion
        -- Class-colored background swatch (shows player class color; not editable).
        local bgClassGet = function()
            local _, ct = UnitClass("player")
            local cc = ct and RAID_CLASS_COLORS[ct]
            if cc then return cc.r, cc.g, cc.b end
            return 1, 1, 1
        end
        local bgClassSw, bgClassUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgClassGet, function() end, false, 20)
        bgClassSw._eabOrigClick = bgClassSw:GetScript("OnClick")
        bgClassSw:SetScript("OnClick", function()
            SSet("bgClassColored", true)
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        bgClassSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSw, "Class Colored Background") end)
        bgClassSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        PP.Point(bgClassSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgClassSw
        RegisterWidgetRefresh(function()
            bgClassUpdate()
            bgClassSw:SetAlpha(SVal("bgClassColored", false) and 1 or 0.3)
        end)
        bgClassSw:SetAlpha(SVal("bgClassColored", false) and 1 or 0.3)

        -- Custom background color swatch.
        local bgSwGet = function()
            local c = SGet("customBgColor")
            if c then return c.r, c.g, c.b end
            return 17/255, 17/255, 17/255
        end
        local bgSwSet = function(r, g, b)
            UNIT_DB_MAP[optState.selectedUnit]().customBgColor = { r=r, g=g, b=b }
            ReloadAndUpdate(); UpdatePreview()
        end
        local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
        bgSw._eabOrigClick = bgSw:GetScript("OnClick")
        bgSw:SetScript("OnClick", function(self)
            if SVal("bgClassColored", false) then
                SSet("bgClassColored", false)
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
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
            bgSw:SetAlpha(SVal("bgClassColored", false) and 0.3 or 1)
        end)
        bgSw:SetAlpha(SVal("bgClassColored", false) and 0.3 or 1)
    end
    -- Sync icon: Bar Background (right) -- background color + opacity
    if not EllesmereUI._prebuilding then
        local rgn = sharedHealthColorRow._rightRegion
        local function ApplyBgTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local bc = src.customBgColor or { r=17/255, g=17/255, b=17/255 }
            local bgA = src.customBgAlpha or 100
            local bgClass = src.bgClassColored or false
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.customBgColor = { r=bc.r, g=bc.g, b=bc.b }
                    d.customBgAlpha = bgA
                    d.bgClassColored = bgClass
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Background to all Frames",
            onClick = function() ApplyBgTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then return true end
                    if a == nil or b == nil then return false end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    if not colEq(d.customBgColor, src.customBgColor) then return false end
                    if (d.customBgAlpha or 100) ~= (src.customBgAlpha or 100) then return false end
                    if (d.bgClassColored or false) ~= (src.bgClassColored or false) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyBgTo(checkedKeys) end,
            },
        })
    end
    -- Sync icon: Bar Color (left) -- fill/class color and gradient
    if not EllesmereUI._prebuilding then
        local rgn = sharedHealthColorRow._leftRegion
        -- Dynamic Color lives in this slot's cog, and its three stops are inline
        -- swatches on this row, so they travel with the rest of Bar Color.
        local DYN_STOP_KEYS = { "dynamicColor100", "dynamicColor50", "dynamicColor0" }
        local function ApplyColorTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local cc = src.healthClassColored or false
            local fc = src.customFillColor
            local gEn = src.gradientEnabled or false
            local gDir = src.gradientDir or "HORIZONTAL"
            local gc = src.gradientColor
            local dynMode = src.healthColorMode or "none"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.healthClassColored = cc
                    if fc then d.customFillColor = { r=fc.r, g=fc.g, b=fc.b }
                    else d.customFillColor = nil end
                    d.gradientEnabled = gEn
                    d.gradientDir = gDir
                    if gc then d.gradientColor = { r=gc.r, g=gc.g, b=gc.b }
                    else d.gradientColor = nil end
                    d.healthColorMode = dynMode
                    for _, ck in ipairs(DYN_STOP_KEYS) do
                        local sc = src[ck]
                        if sc then d[ck] = { r=sc.r, g=sc.g, b=sc.b } else d[ck] = nil end
                    end
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Color to all Frames",
            onClick = function() ApplyColorTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then return true end
                    if a == nil or b == nil then return false end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    if (d.healthClassColored or false) ~= (src.healthClassColored or false) then return false end
                    if not colEq(d.customFillColor, src.customFillColor) then return false end
                    if (d.gradientEnabled or false) ~= (src.gradientEnabled or false) then return false end
                    if not colEq(d.gradientColor, src.gradientColor) then return false end
                    if (d.gradientDir or "HORIZONTAL") ~= (src.gradientDir or "HORIZONTAL") then return false end
                    if (d.healthColorMode or "none") ~= (src.healthColorMode or "none") then return false end
                    for _, ck in ipairs(DYN_STOP_KEYS) do
                        if not colEq(d[ck], src[ck]) then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyColorTo(checkedKeys) end,
            },
        })
    end
    -- Fill Color cog on Bar Color (left region): the two settings that decide
    -- what color the fill actually ends up, beyond the flat swatches.
    -- Dynamic Color and Gradient COMPOSE -- Dynamic picks the color from the
    -- unit's health percent, Gradient then runs from that color to the
    -- gradient end color -- so they share one popup rather than fighting.
    if not EllesmereUI._prebuilding then
        local rgn = sharedHealthColorRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Fill Color Settings",
            rows = {
                -- Ported from the Raid Frames "Fill Color" dropdown: same modes,
                -- same curve shape, same stop defaults, so a unit frame and a
                -- party frame on the same mode paint the same color at the same
                -- health. The 100%/50%/0% stops are swatches on the row itself
                -- (cog popups have no color row type).
                { type="dropdown", label="Dynamic Color",
                  tooltip="Color the health bar by how much health is left, instead of a flat color. Classic runs green at full health through yellow to red at empty. Custom Colors blends between the three stop swatches on this row -- full (100%), half (50%) and empty (0%). Class Reactive shows the class color at full health, bleeding into the 50% and 0% colors as the unit takes damage. Off leaves the flat Fill Color swatches in charge; either way the Gradient below still applies, running from whichever color this picks.",
                  values={ none="Off", classic="Classic",
                           customDynamic="Custom Colors", classReactive="Class Reactive" },
                  order={ "none", "classic", "customDynamic", "classReactive" },
                  get=function() return SVal("healthColorMode", "none") end,
                  -- RefreshPage re-runs the stop swatches' show/hide pass.
                  set=function(v) SSet("healthColorMode", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                { type="toggle", label="Enable Gradient",
                  get=function() return SVal("gradientEnabled", false) end,
                  set=function(v) SSet("gradientEnabled", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                { type="dropdown", label="Gradient Direction",
                  values={ HORIZONTAL="Horizontal", VERTICAL="Vertical" }, order={ "HORIZONTAL", "VERTICAL" },
                  get=function() return SVal("gradientDir", "HORIZONTAL") end,
                  set=function(v) SSet("gradientDir", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
            },
        })
    end
    -- Dynamic Color stop swatches (100% | 50% | 0%), chained LEFT of the cog so
    -- they sit at the far end of the row's inline run: hiding them for the modes
    -- that don't read them then leaves no hole in the middle of the controls,
    -- and Off restores exactly the original [cog][gradient][custom][class] look.
    if not EllesmereUI._prebuilding then
        local rgn = sharedHealthColorRow._leftRegion
        local dynDefs = {
            { key = "dynamicColor100", def = { r = 0, g = 1, b = 0 },
              tip = "Health bar color at full (100%) health" },
            { key = "dynamicColor50",  def = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 },
              tip = "Health bar color at half (50%) health" },
            { key = "dynamicColor0",   def = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 },
              tip = "Health bar color at empty (0%) health" },
        }
        local dynSwatches, dynUpdaters = {}, {}
        local prevAnchor = rgn._lastInline or rgn._control
        for i = #dynDefs, 1, -1 do
            local dd = dynDefs[i]
            local sw, swUpdate = EllesmereUI.BuildColorSwatch(
                rgn, sharedHealthColorRow:GetFrameLevel() + 3,
                function()
                    local c = SGet(dd.key) or dd.def
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[optState.selectedUnit]()[dd.key] = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 18)
            sw:SetPoint("RIGHT", prevAnchor, "LEFT", -8, 0)
            sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, dd.tip) end)
            sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            dynSwatches[i] = sw
            dynUpdaters[i] = swUpdate
            prevAnchor = sw
        end
        rgn._lastInline = prevAnchor
        -- dynSwatches[1] is the 100% stop. Class Reactive drives that stop from
        -- the unit's own class color, so only 50%/0% are editable there.
        -- The swatch UPDATERS must run on every refresh too: the stops are
        -- per-unit, and switching the selected unit refreshes widgets rather
        -- than rebuilding the page, so without this the swatches keep showing
        -- the previous unit's colors.
        local function UpdateDynSwatchVis()
            local mode = SVal("healthColorMode", "none")
            local isDynamic = mode == "customDynamic"
            local isReactive = mode == "classReactive"
            for i, sw in ipairs(dynSwatches) do
                if dynUpdaters[i] then dynUpdaters[i]() end
                if isDynamic or (isReactive and i > 1) then sw:Show() else sw:Hide() end
            end
        end
        RegisterWidgetRefresh(UpdateDynSwatchVis)
        UpdateDynSwatchVis()
    end

    -- Dark Mode: disable all Bar Color + Bar Background controls (the flat dark
    -- health bar ignores fill/background colors).
    if not EllesmereUI._prebuilding then
    AddDarkModeBlock(sharedHealthColorRow._leftRegion)
    AddDarkModeBlock(sharedHealthColorRow._rightRegion)
    end

    -- Row 3: Smooth Health Bars + Bar Opacity
    local sharedOpacityRow
    sharedOpacityRow, h = W:DualRow(parent, y,
        { type="toggle", text="Smooth Health Bars",
          getValue=function() return SVal("smoothBars", false) end,
          setValue=function(v) SSet("smoothBars", v) end },
        { type="slider", text="Fill Opacity", min=0, max=100, step=1,
          disabled=function() return db.profile.darkTheme end,
          disabledTooltip="Dark Mode", requireState="disabled",
          getValue=function() return SVal("healthBarOpacity", 90) end,
          setValue=function(v)
              SSet("healthBarOpacity", v)
              UpdatePreview()
          end });  y = y - h
    -- Sync icon: Bar Opacity (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedOpacityRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Opacity to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().healthBarOpacity or 90
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().healthBarOpacity = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().healthBarOpacity or 90
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().healthBarOpacity or 90) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().healthBarOpacity or 90
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().healthBarOpacity = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 4: Left Text + Right Text
    local sharedTextRow
    sharedTextRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Left Text", values=healthTextValues, order=(optState.selectedUnit == "player" and healthTextOrderPlayer) or ((optState.selectedUnit == "target" or optState.selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
          getValue=function() return SVal("leftTextContent", "name") end,
          setValue=function(v)
              local hadLevel = SShowsLevel()
              SSet("leftTextContent", v)
              if v ~= "none" then
                  if SGet("rightTextContent") == v then SSet("rightTextContent", "none") end
                  if SGet("centerTextContent") == v then SSet("centerTextContent", "none") end
              end
              UpdatePreview(); EllesmereUI:RefreshPage(SShowsLevel() ~= hadLevel)
          end,
        },
        { type="dropdown", text="Right Text", values=healthTextValues, order=(optState.selectedUnit == "player" and healthTextOrderPlayer) or ((optState.selectedUnit == "target" or optState.selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
          getValue=function() return SVal("rightTextContent", "both") end,
          setValue=function(v)
              local hadLevel = SShowsLevel()
              SSet("rightTextContent", v)
              if v ~= "none" then
                  if SGet("leftTextContent") == v then SSet("leftTextContent", "none") end
                  if SGet("centerTextContent") == v then SSet("centerTextContent", "none") end
              end
              UpdatePreview(); EllesmereUI:RefreshPage(SShowsLevel() ~= hadLevel)
          end,
        });  y = y - h
    -- Sync icon: Left Text (left)
    if not EllesmereUI._prebuilding then
        local rgn = sharedTextRow._leftRegion
        local function ApplyLeftTextTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local v = src.leftTextContent or "name"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.leftTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    d.leftTextClassColor = src.leftTextClassColor
                    d.leftTextColorR, d.leftTextColorG, d.leftTextColorB = src.leftTextColorR, src.leftTextColorG, src.leftTextColorB
                    d.leftTextSize = src.leftTextSize
                    d.leftTextX, d.leftTextY = src.leftTextX, src.leftTextY
                    d.leftTextWidthPct = src.leftTextWidthPct
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Left Text to all Frames",
            onClick = function() ApplyLeftTextTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local v = src.leftTextContent or "name"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    if (d.leftTextContent or "name") ~= expected then return false end
                    if (d.leftTextClassColor or false) ~= (src.leftTextClassColor or false) then return false end
                    if (d.leftTextColorR or 1) ~= (src.leftTextColorR or 1) then return false end
                    if (d.leftTextColorG or 1) ~= (src.leftTextColorG or 1) then return false end
                    if (d.leftTextColorB or 1) ~= (src.leftTextColorB or 1) then return false end
                    if (d.leftTextSize or 0) ~= (src.leftTextSize or 0) then return false end
                    if (d.leftTextX or 0) ~= (src.leftTextX or 0) then return false end
                    if (d.leftTextY or 0) ~= (src.leftTextY or 0) then return false end
                    if (d.leftTextWidthPct or 100) ~= (src.leftTextWidthPct or 100) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyLeftTextTo(checkedKeys) end,
            },
        })
    end
    -- Inline swatches on Left Text (CDM Border Size double-swatch pattern): class
    -- sets leftTextClassColor, custom opens the picker and switches back from class.
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedTextRow._leftRegion
        local ltAnchor = leftRgn._lastInline or leftRgn._control
        -- Class Colored swatch (nearest the control): shows the player's class color.
        local ltClassSwatch, ltUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            leftRgn, leftRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(ltClassSwatch, "RIGHT", ltAnchor, "LEFT", -8, 0)
        ltClassSwatch:SetScript("OnClick", function()
            if SVal("leftTextContent", "name") == "none" then return end
            SSet("leftTextClassColor", true)
            -- Bespoke write: notify for exact Spec Overrides attribution (the
            -- forced RefreshPage below would otherwise resync-absorb it).
            EllesmereUI._NotifySettingWrite(ltClassSwatch)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        ltClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ltClassSwatch, "Class Colored") end)
        ltClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- Custom Colored swatch (left of the class swatch): opens the color picker.
        local ltSwGet = function()
            return SVal("leftTextColorR", 1), SVal("leftTextColorG", 1), SVal("leftTextColorB", 1)
        end
        local ltSwSet = function(r, g, b)
            SSet("leftTextColorR", r); SSet("leftTextColorG", g); SSet("leftTextColorB", b)
            UpdatePreview()
        end
        local ltSwatch, ltUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ltSwGet, ltSwSet, nil, 20)
        PP.Point(ltSwatch, "RIGHT", ltClassSwatch, "LEFT", -8, 0)
        leftRgn._lastInline = ltSwatch
        local ltOrigClick = ltSwatch:GetScript("OnClick")
        ltSwatch:SetScript("OnClick", function(self, ...)
            if SVal("leftTextContent", "name") == "none" then return end
            if SVal("leftTextClassColor", false) then
                SSet("leftTextClassColor", false)
                EllesmereUI._NotifySettingWrite(self)
                UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if ltOrigClick then ltOrigClick(self, ...) end
        end)
        ltSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ltSwatch, "Custom Colored") end)
        ltSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateLtSwatches()
            local isNone = SVal("leftTextContent", "name") == "none"
            local isClass = SVal("leftTextClassColor", false)
            ltSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
            ltClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() ltUpdateSwatch(); ltUpdateClassSwatch(); UpdateLtSwatches() end)
        UpdateLtSwatches()
        -- The class-color mode flag is written only by bespoke swatch OnClicks (no
        -- widget getter reads it), so Spec Overrides' read-trace can't link an
        -- override to this row without a capture accessor declared explicitly.
        if EllesmereUI.AddCaptureAccessor then
            EllesmereUI.AddCaptureAccessor(leftRgn, {
                type = "toggle", text = "Left Text Class Color",
                getValue = function() return SVal("leftTextClassColor", false) end,
                setValue = function(v) SSet("leftTextClassColor", v) end,
            })
        end
    end
    -- Cogwheel on Left Text (left region)
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedTextRow._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = function() return SVal("leftTextContent", "name") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Left Text Settings",
            rows = ns.UF_NameFormatRows("leftText", "name", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("leftTextSize", SDB().textSize or 12) end,
                  set=function(v) SSet("leftTextSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("leftTextX", 0) end,
                  set=function(v) SSet("leftTextX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("leftTextY", 0) end,
                  set=function(v) SSet("leftTextY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("leftTextWidthPct", 100) end,
                  set=function(v) SSet("leftTextWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = SVal("leftTextContent","name") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("leftTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("leftTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("leftTextTargetSepClassColor", false) then
                              SSet("leftTextTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("leftTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("leftTextTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("leftTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("leftTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("leftTextTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("leftTextContent","name") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return SVal("leftTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      SSet("leftTextTargetPrefix", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("leftTextContent","name") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end
    -- Sync icon: Right Text (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedTextRow._rightRegion
        local function ApplyRightTextTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local v = src.rightTextContent or "both"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.rightTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    d.rightTextClassColor = src.rightTextClassColor
                    d.rightTextColorR, d.rightTextColorG, d.rightTextColorB = src.rightTextColorR, src.rightTextColorG, src.rightTextColorB
                    d.rightTextSize = src.rightTextSize
                    d.rightTextX, d.rightTextY = src.rightTextX, src.rightTextY
                    d.rightTextWidthPct = src.rightTextWidthPct
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Right Text to all Frames",
            onClick = function() ApplyRightTextTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local v = src.rightTextContent or "both"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    if (d.rightTextContent or "both") ~= expected then return false end
                    if (d.rightTextClassColor or false) ~= (src.rightTextClassColor or false) then return false end
                    if (d.rightTextColorR or 1) ~= (src.rightTextColorR or 1) then return false end
                    if (d.rightTextColorG or 1) ~= (src.rightTextColorG or 1) then return false end
                    if (d.rightTextColorB or 1) ~= (src.rightTextColorB or 1) then return false end
                    if (d.rightTextSize or 0) ~= (src.rightTextSize or 0) then return false end
                    if (d.rightTextX or 0) ~= (src.rightTextX or 0) then return false end
                    if (d.rightTextY or 0) ~= (src.rightTextY or 0) then return false end
                    if (d.rightTextWidthPct or 100) ~= (src.rightTextWidthPct or 100) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyRightTextTo(checkedKeys) end,
            },
        })
    end
    -- Inline swatches on Right Text (CDM Border Size double-swatch pattern): class
    -- sets rightTextClassColor, custom opens the picker and switches back from class.
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedTextRow._rightRegion
        local rtAnchor = rightRgn._lastInline or rightRgn._control
        local rtClassSwatch, rtUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            rightRgn, rightRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(rtClassSwatch, "RIGHT", rtAnchor, "LEFT", -8, 0)
        rtClassSwatch:SetScript("OnClick", function()
            if SVal("rightTextContent", "both") == "none" then return end
            SSet("rightTextClassColor", true)
            -- Bespoke write: notify for exact Spec Overrides attribution (the
            -- forced RefreshPage below would otherwise resync-absorb it).
            EllesmereUI._NotifySettingWrite(rtClassSwatch)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        rtClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(rtClassSwatch, "Class Colored") end)
        rtClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local rtSwGet = function()
            return SVal("rightTextColorR", 1), SVal("rightTextColorG", 1), SVal("rightTextColorB", 1)
        end
        local rtSwSet = function(r, g, b)
            SSet("rightTextColorR", r); SSet("rightTextColorG", g); SSet("rightTextColorB", b)
            UpdatePreview()
        end
        local rtSwatch, rtUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, rtSwGet, rtSwSet, nil, 20)
        PP.Point(rtSwatch, "RIGHT", rtClassSwatch, "LEFT", -8, 0)
        rightRgn._lastInline = rtSwatch
        local rtOrigClick = rtSwatch:GetScript("OnClick")
        rtSwatch:SetScript("OnClick", function(self, ...)
            if SVal("rightTextContent", "both") == "none" then return end
            if SVal("rightTextClassColor", false) then
                SSet("rightTextClassColor", false)
                EllesmereUI._NotifySettingWrite(self)
                UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if rtOrigClick then rtOrigClick(self, ...) end
        end)
        rtSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(rtSwatch, "Custom Colored") end)
        rtSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateRtSwatches()
            local isNone = SVal("rightTextContent", "both") == "none"
            local isClass = SVal("rightTextClassColor", false)
            rtSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
            rtClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() rtUpdateSwatch(); rtUpdateClassSwatch(); UpdateRtSwatches() end)
        UpdateRtSwatches()
        -- Mirror of the Left Text class-flag accessor: see that comment.
        if EllesmereUI.AddCaptureAccessor then
            EllesmereUI.AddCaptureAccessor(rightRgn, {
                type = "toggle", text = "Right Text Class Color",
                getValue = function() return SVal("rightTextClassColor", false) end,
                setValue = function(v) SSet("rightTextClassColor", v) end,
            })
        end
    end
    -- Cogwheel on Right Text (right region)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedTextRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            disabled = function() return SVal("rightTextContent", "both") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Right Text Settings",
            rows = ns.UF_NameFormatRows("rightText", "both", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("rightTextSize", SDB().textSize or 12) end,
                  set=function(v) SSet("rightTextSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("rightTextX", 0) end,
                  set=function(v) SSet("rightTextX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("rightTextY", 0) end,
                  set=function(v) SSet("rightTextY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("rightTextWidthPct", 100) end,
                  set=function(v) SSet("rightTextWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = SVal("rightTextContent","both") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("rightTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("rightTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("rightTextTargetSepClassColor", false) then
                              SSet("rightTextTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("rightTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("rightTextTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("rightTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("rightTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("rightTextTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("rightTextContent","both") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return SVal("rightTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      SSet("rightTextTargetPrefix", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("rightTextContent","both") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Row 5: Center Text
    local sharedCenterTextRow
    sharedCenterTextRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Center Text", values=healthTextValues, order=(optState.selectedUnit == "player" and healthTextOrderPlayer) or ((optState.selectedUnit == "target" or optState.selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
          getValue=function() return SVal("centerTextContent", "none") end,
          setValue=function(v)
              local hadLevel = SShowsLevel()
              SSet("centerTextContent", v)
              ReloadAndUpdate(); UpdatePreview()
              EllesmereUI:RefreshPage(SShowsLevel() ~= hadLevel)
          end },
        { type="dropdown", text="Extra Text (full length)", values=healthTextValues, order=(optState.selectedUnit == "player" and healthTextOrderPlayer) or ((optState.selectedUnit == "target" or optState.selectedUnit == "focus") and healthTextOrderTargetFocus) or healthTextOrder,
          getValue=function() return SVal("extraTextContent", "none") end,
          setValue=function(v)
              local hadLevel = SShowsLevel()
              SSet("extraTextContent", v)
              ReloadAndUpdate(); UpdatePreview()
              EllesmereUI:RefreshPage(SShowsLevel() ~= hadLevel)
          end });  y = y - h
    -- Sync icon: Center Text (left)
    if not EllesmereUI._prebuilding then
        local rgn = sharedCenterTextRow._leftRegion
        local function ApplyCenterTextTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local v = src.centerTextContent or "none"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.centerTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    d.centerTextClassColor = src.centerTextClassColor
                    d.centerTextColorR, d.centerTextColorG, d.centerTextColorB = src.centerTextColorR, src.centerTextColorG, src.centerTextColorB
                    d.centerTextSize = src.centerTextSize
                    d.centerTextX, d.centerTextY = src.centerTextX, src.centerTextY
                    d.centerTextWidthPct = src.centerTextWidthPct
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Center Text to all Frames",
            onClick = function() ApplyCenterTextTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local v = src.centerTextContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    if (d.centerTextContent or "none") ~= expected then return false end
                    if (d.centerTextClassColor or false) ~= (src.centerTextClassColor or false) then return false end
                    if (d.centerTextColorR or 1) ~= (src.centerTextColorR or 1) then return false end
                    if (d.centerTextColorG or 1) ~= (src.centerTextColorG or 1) then return false end
                    if (d.centerTextColorB or 1) ~= (src.centerTextColorB or 1) then return false end
                    if (d.centerTextSize or 0) ~= (src.centerTextSize or 0) then return false end
                    if (d.centerTextX or 0) ~= (src.centerTextX or 0) then return false end
                    if (d.centerTextY or 0) ~= (src.centerTextY or 0) then return false end
                    if (d.centerTextWidthPct or 100) ~= (src.centerTextWidthPct or 100) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyCenterTextTo(checkedKeys) end,
            },
        })
    end
    -- Inline swatches on Center Text (CDM Border Size double-swatch pattern): class
    -- sets centerTextClassColor, custom opens the picker and switches back from class.
    if not EllesmereUI._prebuilding then
        local ctrRgn = sharedCenterTextRow._leftRegion
        local ctAnchor = ctrRgn._lastInline or ctrRgn._control
        local ctClassSwatch, ctUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            ctrRgn, ctrRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(ctClassSwatch, "RIGHT", ctAnchor, "LEFT", -8, 0)
        ctClassSwatch:SetScript("OnClick", function()
            if SVal("centerTextContent", "none") == "none" then return end
            SSet("centerTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        ctClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ctClassSwatch, "Class Colored") end)
        ctClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local ctSwGet = function()
            return SVal("centerTextColorR", 1), SVal("centerTextColorG", 1), SVal("centerTextColorB", 1)
        end
        local ctSwSet = function(r, g, b)
            SSet("centerTextColorR", r); SSet("centerTextColorG", g); SSet("centerTextColorB", b)
            UpdatePreview()
        end
        local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(ctrRgn, ctrRgn:GetFrameLevel() + 5, ctSwGet, ctSwSet, nil, 20)
        PP.Point(ctSwatch, "RIGHT", ctClassSwatch, "LEFT", -8, 0)
        ctrRgn._lastInline = ctSwatch
        local ctOrigClick = ctSwatch:GetScript("OnClick")
        ctSwatch:SetScript("OnClick", function(self, ...)
            if SVal("centerTextContent", "none") == "none" then return end
            if SVal("centerTextClassColor", false) then
                SSet("centerTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if ctOrigClick then ctOrigClick(self, ...) end
        end)
        ctSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ctSwatch, "Custom Colored") end)
        ctSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateCtSwatches()
            local isNone = SVal("centerTextContent", "none") == "none"
            local isClass = SVal("centerTextClassColor", false)
            ctSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
            ctClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() ctUpdateSwatch(); ctUpdateClassSwatch(); UpdateCtSwatches() end)
        UpdateCtSwatches()
    end
    -- Cogwheel on Center Text (left region)
    if not EllesmereUI._prebuilding then
        local ctrRgn = sharedCenterTextRow._leftRegion
        EllesmereUI.BuildInlineCog(ctrRgn, {
            disabled = function() return SVal("centerTextContent", "none") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Center Text Settings",
            rows = ns.UF_NameFormatRows("centerText", "none", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("centerTextSize", SDB().textSize or 12) end,
                  set=function(v) SSet("centerTextSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("centerTextX", 0) end,
                  set=function(v) SSet("centerTextX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("centerTextY", 0) end,
                  set=function(v) SSet("centerTextY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("centerTextWidthPct", 100) end,
                  set=function(v) SSet("centerTextWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = SVal("centerTextContent","none") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("centerTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("centerTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("centerTextTargetSepClassColor", false) then
                              SSet("centerTextTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("centerTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("centerTextTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("centerTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("centerTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("centerTextTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("centerTextContent","none") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return SVal("centerTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      SSet("centerTextTargetPrefix", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("centerTextContent","none") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Extra Text shares the Center Text row (its dropdown is that row's right slot);
    -- its inline controls attach to that row's RIGHT region. Sync icon: Extra Text.
    if not EllesmereUI._prebuilding then
        local rgn = sharedCenterTextRow._rightRegion
        local function ApplyExtraTextTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local v = src.extraTextContent or "none"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.extraTextContent = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    d.extraTextClassColor = src.extraTextClassColor
                    d.extraTextColorR, d.extraTextColorG, d.extraTextColorB = src.extraTextColorR, src.extraTextColorG, src.extraTextColorB
                    d.extraTextSize = src.extraTextSize
                    d.extraTextX, d.extraTextY = src.extraTextX, src.extraTextY
                    d.extraTextAlign = src.extraTextAlign
                    d.extraTextWidthPct = src.extraTextWidthPct
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Extra Text to all Frames",
            onClick = function() ApplyExtraTextTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local v = src.extraTextContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local expected = ((v == "absorb" or v == "absorbshort" or v == "healabsorb" or v == "healabsorbshort" or v == "group") and key ~= "player") and "none" or v
                    if (d.extraTextContent or "none") ~= expected then return false end
                    if (d.extraTextClassColor or false) ~= (src.extraTextClassColor or false) then return false end
                    if (d.extraTextColorR or 1) ~= (src.extraTextColorR or 1) then return false end
                    if (d.extraTextColorG or 1) ~= (src.extraTextColorG or 1) then return false end
                    if (d.extraTextColorB or 1) ~= (src.extraTextColorB or 1) then return false end
                    if (d.extraTextSize or 0) ~= (src.extraTextSize or 0) then return false end
                    if (d.extraTextX or 0) ~= (src.extraTextX or 0) then return false end
                    if (d.extraTextY or 0) ~= (src.extraTextY or 0) then return false end
                    if (d.extraTextAlign or "left") ~= (src.extraTextAlign or "left") then return false end
                    if (d.extraTextWidthPct or 100) ~= (src.extraTextWidthPct or 100) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyExtraTextTo(checkedKeys) end,
            },
        })
    end
    -- Inline swatches on Extra Text (Center row right region): class sets
    -- extraTextClassColor, custom opens the picker.
    if not EllesmereUI._prebuilding then
        local etrRgn = sharedCenterTextRow._rightRegion
        local etAnchor = etrRgn._lastInline or etrRgn._control
        local etClassSwatch, etUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            etrRgn, etrRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(etClassSwatch, "RIGHT", etAnchor, "LEFT", -8, 0)
        etClassSwatch:SetScript("OnClick", function()
            if SVal("extraTextContent", "none") == "none" then return end
            SSet("extraTextClassColor", true); UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        etClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(etClassSwatch, "Class Colored") end)
        etClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local etSwGet = function()
            return SVal("extraTextColorR", 1), SVal("extraTextColorG", 1), SVal("extraTextColorB", 1)
        end
        local etSwSet = function(r, g, b)
            SSet("extraTextColorR", r); SSet("extraTextColorG", g); SSet("extraTextColorB", b)
            UpdatePreview()
        end
        local etSwatch, etUpdateSwatch = EllesmereUI.BuildColorSwatch(etrRgn, etrRgn:GetFrameLevel() + 5, etSwGet, etSwSet, nil, 20)
        PP.Point(etSwatch, "RIGHT", etClassSwatch, "LEFT", -8, 0)
        etrRgn._lastInline = etSwatch
        local etOrigClick = etSwatch:GetScript("OnClick")
        etSwatch:SetScript("OnClick", function(self, ...)
            if SVal("extraTextContent", "none") == "none" then return end
            if SVal("extraTextClassColor", false) then
                SSet("extraTextClassColor", false); UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if etOrigClick then etOrigClick(self, ...) end
        end)
        etSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(etSwatch, "Custom Colored") end)
        etSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateEtSwatches()
            local isNone = SVal("extraTextContent", "none") == "none"
            local isClass = SVal("extraTextClassColor", false)
            etSwatch:SetAlpha((isClass or isNone) and 0.3 or 1)
            etClassSwatch:SetAlpha((isClass and not isNone) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() etUpdateSwatch(); etUpdateClassSwatch(); UpdateEtSwatches() end)
        UpdateEtSwatches()
    end
    -- Cogwheel on Extra Text (Center row right region): Alignment + Size/X/Y
    if not EllesmereUI._prebuilding then
        local etrRgn = sharedCenterTextRow._rightRegion
        EllesmereUI.BuildInlineCog(etrRgn, {
            disabled = function() return SVal("extraTextContent", "none") == "none" end,
            disabledTooltip = "This option requires a text selection other than none.",
            title = "Extra Text Settings",
            rows = ns.UF_NameFormatRows("extraText", "none", SVal, SSet, {
                { type="dropdown", label="Alignment",
                  values={ ["left"]="Left", ["right"]="Right", ["center"]="Center" }, order={ "left", "right", "center" },
                  get=function() return SVal("extraTextAlign", "left") end,
                  set=function(v) SSet("extraTextAlign", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("extraTextSize", SDB().textSize or 12) end,
                  set=function(v) SSet("extraTextSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("extraTextX", 0) end,
                  set=function(v) SSet("extraTextX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("extraTextY", 0) end,
                  set=function(v) SSet("extraTextY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("extraTextWidthPct", 100) end,
                  set=function(v) SSet("extraTextWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() local c = SVal("extraTextContent","none") return c ~= "nametotarget" and c ~= "targetname" end,
                  disabledTooltip="This option only applies when Name > Target or Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("extraTextTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("extraTextTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("extraTextTargetSepClassColor", false) then
                              SSet("extraTextTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("extraTextTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("extraTextTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("extraTextTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("extraTextTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("extraTextTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("extraTextContent","none") ~= "nametotarget" end,
                  disabledTooltip="This option only applies when Name > Target is selected." },
                { type="input", label="Prefix", inputWidth=60,
                  tooltip="Text shown before the target's name.",
                  get=function() return SVal("extraTextTargetPrefix", "T:") end,
                  set=function(v)
                      -- Unlike Separator, empty is kept: no prefix.
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      SSet("extraTextTargetPrefix", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("extraTextContent","none") ~= "targetname" end,
                  disabledTooltip="This option only applies when Target is selected." },
                                }),
        })
    end

    -- Level text in Blizzard's difficulty colors: the level part of the
    -- Level, Level | Name and Name | Level texts, so the row exists only
    -- while one of the unit's text slots shows one. It sits above Show
    -- Level, whose blank slot stays last in the section.
    if SShowsLevel() then
        local _
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Level Text: Difficulty Color",
              tooltip="Colors level text by difficulty, from grey (trivial) through green, yellow and orange to red (5+ levels above you).",
              getValue=function() return SVal("levelDifficultyColor", false) == true end,
              setValue=function(v)
                  SSet("levelDifficultyColor", v); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Level Text: Include Friendly",
              tooltip="Friendly units get their level's color too, instead of gold.",
              disabled=function() return SVal("levelDifficultyColor", false) ~= true end,
              disabledTooltip="Level Text: Difficulty Color",
              getValue=function() return SVal("levelDifficultyColorFriendly", false) == true end,
              setValue=function(v) SSet("levelDifficultyColorFriendly", v); UpdatePreview() end });  y = y - h
    end

    -- Blizzard Style: the stock level number in the frame's level circle,
    -- with its size, offsets and difficulty colouring on a cog. The row is
    -- the preview level text's click target (stashed on the page: the
    -- targets table at the end reads it).
    if EllesmereUI.BlizzStyle.Get("unitframes") then
        parent._ufLevelRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Level",
              tooltip="Shows the unit's level in the frame's level circle, as the default UI does.",
              getValue=function() return SVal("blizzShowLevel", true) end,
              setValue=function(v) SSet("blizzShowLevel", v); UpdatePreview(); EllesmereUI:RefreshPage() end },
            { type="label", text="" });  y = y - h
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(parent._ufLevelRow._leftRegion, {
                disabled = function() return not SVal("blizzShowLevel", true) end,
                disabledTooltip = "This option requires Show Level.",
                title = "Level Text Settings",
                rows = {
                    -- The size follows the name text until set here.
                    { type="slider", label="Size", min=8, max=100, step=1,
                      get=function() return SVal("blizzLevelSize", SVal("leftTextSize", SDB().textSize or 12)) end,
                      set=function(v) SSet("blizzLevelSize", v); UpdatePreview() end },
                    { type="slider", label="X Offset", min=-150, max=150, step=1,
                      get=function() return SVal("blizzLevelX", 0) end,
                      set=function(v) SSet("blizzLevelX", v); UpdatePreview() end },
                    { type="slider", label="Y Offset", min=-150, max=150, step=1,
                      get=function() return SVal("blizzLevelY", 0) end,
                      set=function(v) SSet("blizzLevelY", v); UpdatePreview() end },
                    -- The player's own level never takes a difficulty colour.
                    { type="toggle", label="Difficulty Color",
                      tooltip="Colors an attackable unit's level by difficulty, as the default UI does.",
                      disabled=function() return optState.selectedUnit == "player" end,
                      disabledTooltip="This option does not apply to the player frame.",
                      get=function() return SVal("blizzLevelDifficultyColor", true) end,
                      set=function(v) SSet("blizzLevelDifficultyColor", v); UpdatePreview() end },
                },
            })
        end
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y, sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow
end

function ns.UFO_BuildPowerBarSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, PP, RegisterWidgetRefresh, ReloadAndUpdate = env.GROUP_UNIT_ORDER, env.PP, env.RegisterWidgetRefresh, env.ReloadAndUpdate
    local SHORT_LABELS, UNIT_DB_MAP, UpdatePreview, optState = env.SHORT_LABELS, env.UNIT_DB_MAP, env.UpdatePreview, env.optState
    local W, SDB, SGet, SSet = ctx.W, ctx.SDB, ctx.SGet, ctx.SSet
    local SSetSupported, SVal, SValSupported = ctx.SSetSupported, ctx.SVal, ctx.SValSupported
    local _, h

    -------------------------------------------------------------------
    --  POWER BAR
    -------------------------------------------------------------------
    local sharedPowerHeader
    sharedPowerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

    local ppPosValues = { ["below"]="Below Health Bar", ["above"]="Above Health Bar", ["detached_bottom"]="Detached Bottom", ["detached_top"]="Detached Top", ["none"]="None" }
    local ppPosOrder = { "below", "above", "---", "detached_bottom", "detached_top", "---", "none" }
    local ppTextValues = { ["none"]="None", ["left"]="Left", ["right"]="Right", ["center"]="Center" }
    local ppTextOrder = { "none", "---", "left", "right", "center" }
    local ppFmtValues = { ["none"]="None", ["smart"]="Smart Text", ["curpp"]="Power Value", ["perpp"]="Power %", ["both"]="Value | %" }
    local ppFmtOrder = { "none", "smart", "curpp", "perpp", "both" }

    -- Row 1: Bar Height + Bar Position
    local sharedPowerRow1
    sharedPowerRow1, h = W:DualRow(parent, y,
        -- Blizzard Style: the stock track fixes the height; the Reverse Fill
        -- cog on this slot keeps working (keepRow).
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Power Bar Height", min=0, max=100, step=1,
          getValue=function() return SValSupported("powerHeight", 6) end,
          setValue=function(v) SSetSupported("powerHeight", v); ReloadAndUpdate(); UpdatePreview() end }, true),
        { type="dropdown", text="Bar Position", values=ppPosValues, order=ppPosOrder,
          getValue=function() return SVal("powerPosition", "below") end,
          setValue=function(v)
              SSet("powerPosition", v)
              ReloadAndUpdate(); UpdatePreview()
              -- Attached bars paint a Solid border: the power border's Width /
              -- Height Offset row comes and goes with the detached state.
              EllesmereUI:RefreshPage(true)
          end });  y = y - h
    -- Cog on Position for X/Y offsets + Width (disabled unless detached)
    if not EllesmereUI._prebuilding then
        local posRgn = sharedPowerRow1._rightRegion
        EllesmereUI.BuildInlineCog(posRgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = function() local pos = SVal("powerPosition", "below"); return pos ~= "detached_top" and pos ~= "detached_bottom" end,
            disabledTooltip = "This option requires a detached position to be active.",
            title = "Position Settings",
            rows = {
                { type="slider", label="Width", min=0, max=400, step=1,
                  get=function() return SVal("powerWidth", 0) end,
                  set=function(v) SSet("powerWidth", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-200, max=200, step=1,
                  get=function() return SVal("powerX", 0) end,
                  set=function(v) SSet("powerX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                  get=function() return SVal("powerY", 0) end,
                  set=function(v) SSet("powerY", v); UpdatePreview() end },
            },
        })
    end
    -- Sync icons: Power Height (left) and Power Position (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow1._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Power Bar Height to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerHeight or 6
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerHeight = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerHeight or 6
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerHeight or 6) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().powerHeight or 6
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerHeight = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Reverse Fill cog on Bar Height (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow1._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Power Bar Fill",
            rows = {
                { type="toggle", label="Reverse Fill",
                  get=function() return SVal("powerReverseFill", false) end,
                  set=function(v) SSet("powerReverseFill", v); ReloadAndUpdate(); UpdatePreview() end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow1._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Position to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerPosition or "below"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerPosition = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerPosition or "below"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerPosition or "below") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().powerPosition or "below"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerPosition = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 2: Power Text (format) + Fill Opacity
    local sharedPowerRow2
    sharedPowerRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Power Text", values=ppFmtValues, order=ppFmtOrder,
          getValue=function() return SVal("powerTextFormat", "perpp") end,
          setValue=function(v)
              SSet("powerTextFormat", v)
              -- Auto-set position to center if user picks a format while position is "none"
              if v ~= "none" and SVal("powerPercentText", "none") == "none" then
                  SSet("powerPercentText", "center")
              end
              -- If format is "none", clear position too
              if v == "none" then SSet("powerPercentText", "none") end
              ReloadAndUpdate(); UpdatePreview()
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Fill Opacity", min=0, max=100, step=1,
          getValue=function() return SVal("powerBarOpacity", 100) end,
          setValue=function(v)
              SSet("powerBarOpacity", v)
              UpdatePreview()
          end });  y = y - h
    -- Cogwheel on Power Text for Show % toggle
    if not EllesmereUI._prebuilding then
        local fmtRgn = sharedPowerRow2._leftRegion
        EllesmereUI.BuildInlineCog(fmtRgn, {
            disabled = function() local fmt = SVal("powerTextFormat", "perpp"); return fmt == "none" or fmt == "curpp" end,
            disabledTooltip = "This option is only available for formats that display a percentage.",
            title = "Power Text",
            rows = {
                { type="toggle", label="Show %",
                  get=function() return SVal("powerShowPercent", true) ~= false end,
                  set=function(v)
                      SSet("powerShowPercent", v)
                      UpdatePreview()
                  end },
            },
        })
    end
    -- Sync icon: Power Text Format (left of row 2)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow2._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Power Text Format to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerTextFormat or "perpp"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerTextFormat = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerTextFormat or "perpp"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerTextFormat or "perpp") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().powerTextFormat or "perpp"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerTextFormat = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Fill Opacity sync (right of row 2)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow2._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Opacity to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerBarOpacity or 100
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().powerBarOpacity = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerBarOpacity or 100
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerBarOpacity or 100) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().powerBarOpacity or 100
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerBarOpacity = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 3: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
    local sharedPowerRow3
    sharedPowerRow3, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Fill Color",
          swatches = {
            { tooltip = "Gradient End Color", hasAlpha = false,
              disabled = function() return not SVal("powerGradientEnabled", false) end,
              disabledTooltip = function() return "Gradient" end,
              getValue = function()
                  local c = SGet("powerGradientColor")
                  if c then return c.r, c.g, c.b end
                  return 0.20, 0.20, 0.80
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().powerGradientColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { tooltip = "Custom Colored Fill",
              hasAlpha = false,
              getValue = function()
                  local c = SGet("customPowerFillColor")
                  if c then return c.r, c.g, c.b end
                  return 0, 0, 1
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().customPowerFillColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end,
              onClick = function(self)
                  local v = SVal("powerPercentPowerColor", true)
                  if v then
                      SSet("powerPercentPowerColor", false)
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SVal("powerPercentPowerColor", true) and 0.3 or 1
              end },
            { tooltip = "Power Colored Fill. Power colors can be adjusted in Global Settings -> Colors.",
              hasAlpha = false,
              getValue = function()
                  local _, pToken = UnitPowerType("player")
                  local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                  return info.r, info.g, info.b
              end,
              setValue = function() end,
              onClick = function()
                  SSet("powerPercentPowerColor", true)
                  UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("powerPercentPowerColor", true) and 1 or 0.3
              end },
          } },
        { type="slider", text="Bar Background", min=0, max=100, step=1,
          getValue=function() return SVal("customPowerBgAlpha", 100) end,
          setValue=function(v) SSet("customPowerBgAlpha", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    -- Inline swatches on Bar Background (right): Custom + Power Colored pair
    -- mirroring Bar Color; either toggles powerBgPowerColored, inactive dims to 0.3.
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow3._rightRegion
        -- Power-colored background swatch (shows the player's power color; not editable).
        local bgPwrGet = function()
            local _, pToken = UnitPowerType("player")
            local info = EllesmereUI.GetPowerColor(pToken or "MANA")
            local f = EllesmereUI.GetPowerBgDarkenFactor()
            return info.r * f, info.g * f, info.b * f
        end
        local bgPwrSw, bgPwrUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgPwrGet, function() end, false, 20)
        bgPwrSw._eabOrigClick = bgPwrSw:GetScript("OnClick")
        bgPwrSw:SetScript("OnClick", function()
            SSet("powerBgPowerColored", true)
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        bgPwrSw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSw, "Power Colored Background. Power colors can be adjusted in Global Settings -> Colors.") end)
        bgPwrSw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        PP.Point(bgPwrSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgPwrSw
        RegisterWidgetRefresh(function()
            bgPwrUpdate()
            bgPwrSw:SetAlpha(SVal("powerBgPowerColored", false) and 1 or 0.3)
        end)
        bgPwrSw:SetAlpha(SVal("powerBgPowerColored", false) and 1 or 0.3)

        -- Custom background color swatch.
        local bgSwGet = function()
            local c = SGet("customPowerBgColor")
            if c then return c.r, c.g, c.b end
            return 17/255, 17/255, 17/255
        end
        local bgSwSet = function(r, g, b)
            UNIT_DB_MAP[optState.selectedUnit]().customPowerBgColor = { r=r, g=g, b=b }
            ReloadAndUpdate(); UpdatePreview()
        end
        local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
        bgSw._eabOrigClick = bgSw:GetScript("OnClick")
        bgSw:SetScript("OnClick", function(self)
            if SVal("powerBgPowerColored", false) then
                SSet("powerBgPowerColored", false)
                ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
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
            bgSw:SetAlpha(SVal("powerBgPowerColored", false) and 0.3 or 1)
        end)
        bgSw:SetAlpha(SVal("powerBgPowerColored", false) and 0.3 or 1)
    end
    -- Sync icon: Bar Background (right) -- background color + opacity
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow3._rightRegion
        local function ApplyBgTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local bc = src.customPowerBgColor or { r=17/255, g=17/255, b=17/255 }
            local bgA = src.customPowerBgAlpha or 100
            local bgPwr = src.powerBgPowerColored or false
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.customPowerBgColor = { r=bc.r, g=bc.g, b=bc.b }
                    d.customPowerBgAlpha = bgA
                    d.powerBgPowerColored = bgPwr
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Background to all Frames",
            onClick = function() ApplyBgTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then return true end
                    if a == nil or b == nil then return false end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    if not colEq(d.customPowerBgColor, src.customPowerBgColor) then return false end
                    if (d.customPowerBgAlpha or 100) ~= (src.customPowerBgAlpha or 100) then return false end
                    if (d.powerBgPowerColored or false) ~= (src.powerBgPowerColored or false) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyBgTo(checkedKeys) end,
            },
        })
    end
    -- Sync icon: Bar Color (left) -- fill/power color and gradient
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow3._leftRegion
        local function ApplyColorTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local pc = src.powerPercentPowerColor
            if pc == nil then pc = true end
            local fc = src.customPowerFillColor
            local gEn = src.powerGradientEnabled or false
            local gDir = src.powerGradientDir or "HORIZONTAL"
            local gc = src.powerGradientColor
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.powerPercentPowerColor = pc
                    if fc then d.customPowerFillColor = { r=fc.r, g=fc.g, b=fc.b }
                    else d.customPowerFillColor = nil end
                    d.powerGradientEnabled = gEn
                    d.powerGradientDir = gDir
                    if gc then d.powerGradientColor = { r=gc.r, g=gc.g, b=gc.b }
                    else d.powerGradientColor = nil end
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Color to all Frames",
            onClick = function() ApplyColorTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then return true end
                    if a == nil or b == nil then return false end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                local v = src.powerPercentPowerColor
                if v == nil then v = true end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local ov = d.powerPercentPowerColor
                    if ov == nil then ov = true end
                    if ov ~= v then return false end
                    if not colEq(d.customPowerFillColor, src.customPowerFillColor) then return false end
                    if (d.powerGradientEnabled or false) ~= (src.powerGradientEnabled or false) then return false end
                    if not colEq(d.powerGradientColor, src.powerGradientColor) then return false end
                    if (d.powerGradientDir or "HORIZONTAL") ~= (src.powerGradientDir or "HORIZONTAL") then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyColorTo(checkedKeys) end,
            },
        })
    end
    -- Gradient cog on Bar Color (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow3._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Gradient Settings",
            rows = {
                { type="toggle", label="Enable Gradient",
                  get=function() return SVal("powerGradientEnabled", false) end,
                  set=function(v) SSet("powerGradientEnabled", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
                { type="dropdown", label="Gradient Direction",
                  values={ HORIZONTAL="Horizontal", VERTICAL="Vertical" }, order={ "HORIZONTAL", "VERTICAL" },
                  get=function() return SVal("powerGradientDir", "HORIZONTAL") end,
                  set=function(v) SSet("powerGradientDir", v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end },
            },
        })
    end

    -- Row 4: Text Position + Text Color
    local sharedPowerRow4
    sharedPowerRow4, h = W:DualRow(parent, y,
        { type="dropdown", text="Text Position", values=ppTextValues, order=ppTextOrder,
          getValue=function() return SVal("powerPercentText", "none") end,
          setValue=function(v) SSet("powerPercentText", v); ReloadAndUpdate(); UpdatePreview() end },
        { type="multiSwatch", text="Text Color",
          swatches = {
            { tooltip = "Custom Text Color",
              hasAlpha = false,
              getValue = function()
                  local c = SGet("powerTextColor")
                  if c then return c.r, c.g, c.b end
                  return 1, 1, 1
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().powerTextColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end,
              onClick = function(self)
                  local v = SVal("powerPercentTextPowerColor", false)
                  if v then
                      SSet("powerPercentTextPowerColor", false)
                      UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SVal("powerPercentTextPowerColor", false) and 0.3 or 1
              end },
            { tooltip = "Power Colored Text",
              hasAlpha = false,
              getValue = function()
                  local _, pToken = UnitPowerType("player")
                  local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                  return info.r, info.g, info.b
              end,
              setValue = function() end,
              onClick = function()
                  SSet("powerPercentTextPowerColor", true)
                  UNIT_DB_MAP[optState.selectedUnit]().powerTextColor = nil
                  UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("powerPercentTextPowerColor", false) and 1 or 0.3
              end },
          } });  y = y - h
    -- Cogwheel on Text Position for size + x/y offsets (left of row 4)
    if not EllesmereUI._prebuilding then
        local ppRgn = sharedPowerRow4._leftRegion
        local ppRows = {
            { type="slider", label="Size", min=6, max=100, step=1,
              get=function() return SVal("powerPercentSize", 9) end,
              set=function(v) SSet("powerPercentSize", v); UpdatePreview() end },
            { type="slider", label="X Offset", min=-50, max=50, step=1,
              get=function() return SVal("powerPercentX", 0) end,
              set=function(v) SSet("powerPercentX", v); UpdatePreview() end },
            { type="slider", label="Y Offset", min=-50, max=50, step=1,
              get=function() return SVal("powerPercentY", 0) end,
              set=function(v) SSet("powerPercentY", v); UpdatePreview() end },
        }
        -- WoW Forever druids: the Mana + Form Power bar's text has its own
        -- offsets (EUI_UnitFrames_ForeverFormBar.lua); unset, they follow
        -- the power text's.
        local _, cpClass = UnitClass("player")
        if EllesmereUI.IS_FOREVER == true and optState.selectedUnit == "player" and cpClass == "DRUID" then
            local function NoFormBar() return not SVal("foreverFormBar", false) end
            local function FormOffset(key, base)
                local v = SVal(key, nil)
                if v == nil then v = SVal(base, 0) end
                return v
            end
            ppRows[#ppRows + 1] = { type="slider", label="Form Text X Offset", min=-50, max=50, step=1,
                disabled = NoFormBar, disabledTooltip = "Requires Power Type: Mana + Form Power.", rawTooltip = true,
                get=function() return FormOffset("foreverFormTextX", "powerPercentX") end,
                set=function(v) SSet("foreverFormTextX", v) end }
            ppRows[#ppRows + 1] = { type="slider", label="Form Text Y Offset", min=-50, max=50, step=1,
                disabled = NoFormBar, disabledTooltip = "Requires Power Type: Mana + Form Power.", rawTooltip = true,
                get=function() return FormOffset("foreverFormTextY", "powerPercentY") end,
                set=function(v) SSet("foreverFormTextY", v) end }
        end
        EllesmereUI.BuildInlineCog(ppRgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = function() return SVal("powerPercentText", "none") == "none" end,
            disabledTooltip = "This option requires a text position other than none.",
            title = "Text Position",
            rows = ppRows,
        })
    end
    -- Text Position sync (left of row 4)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow4._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Power Text Position to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerPercentText or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().powerPercentText = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerPercentText or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerPercentText or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().powerPercentText or "none"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().powerPercentText = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Sync icon: Text Color (right of row 4)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerRow4._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Color to all Frames",
            onClick = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local v = src.powerPercentTextPowerColor or false
                local tc = src.powerTextColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    d.powerPercentTextPowerColor = v
                    if tc then d.powerTextColor = { r=tc.r, g=tc.g, b=tc.b }
                    else d.powerTextColor = nil end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().powerPercentTextPowerColor or false
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().powerPercentTextPowerColor or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local src = UNIT_DB_MAP[optState.selectedUnit]()
                    local v = src.powerPercentTextPowerColor or false
                    local tc = src.powerTextColor
                    for _, key in ipairs(checkedKeys) do
                        local d = UNIT_DB_MAP[key]()
                        d.powerPercentTextPowerColor = v
                        if tc then d.powerTextColor = { r=tc.r, g=tc.g, b=tc.b }
                        else d.powerTextColor = nil end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 5: Power Border Style (+ cog) | Power Border Size (+ inline swatches)
    local pbTexValues, pbTexOrder = EllesmereUI.GetBorderTextureDropdown()
    local sharedPowerBorderRow
    sharedPowerBorderRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Border Style",
          disabled=function()
              local pos = SVal("powerPosition", "below")
              return pos ~= "detached_top" and pos ~= "detached_bottom"
          end,
          disabledTooltip=function()
              return EllesmereUI.L("Border Style is only configurable when the Power Bar is detached. Attached Power Bars always use Solid.")
          end, rawTooltip=true,
          values=pbTexValues, order=pbTexOrder,
          getValue=function() return SGet("powerBorderStyle") or "solid" end,
          setValue=function(v)
              SSet("powerBorderStyle", v)
              SSet("powerBorderOffsetX", nil)
              SSet("powerBorderOffsetY", nil)
              SSet("powerBorderShiftX", nil)
              SSet("powerBorderShiftY", nil)
              if v ~= "solid" then
                  -- The style's select colour (Pixels grey), else white.
                  SSet("powerBorderColor", EllesmereUI.GetBorderSelectColor(v) or { r = 1, g = 1, b = 1 })
                  SSet("powerBorderAlpha", 1)
              else
                  SSet("powerBorderColor", { r = 0, g = 0, b = 0 })
                  SSet("powerBorderAlpha", 1)
              end
              local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
              if defSz then SSet("powerBorderSize", defSz) end
              -- A style pick returns the bar to its legacy step; clear a set
              -- exact size (false travels through mirror sync, nil would not).
              if SGet("powerBorderSizePx") then SDB().powerBorderSizePx = false end
              ReloadAndUpdate()
              -- The Width / Height Offset row exists only under a textured style.
              EllesmereUI:RefreshPage(true)
          end }),
        EllesmereUI.BlizzStyle.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size",
          disabled=function()
              local pos = SVal("powerPosition", "below")
              return pos == "none"
          end,
          disabledTooltip=function()
              return EllesmereUI.L("Border is only available when the Power Bar is shown.")
          end, rawTooltip=true,
          trackWidth=120,
          getStep=function() return SVal("powerBorderSize", 0) end,
          setStep=function(step) SDB().powerBorderSize = step end,
          getTex=function()
              -- The style the bar is painted with (ns.UpdatePowerBorder): an
              -- attached bar is forced Solid whatever the dropdown holds.
              local pos = SVal("powerPosition", "below")
              if pos == "above" or pos == "below" then return "solid" end
              return SGet("powerBorderStyle") or "solid"
          end,
          getPx=function() return SGet("powerBorderSizePx") end,
          setPx=function(v) SDB().powerBorderSizePx = v end,
          apply=ReloadAndUpdate })));  y = y - h
    -- Width Offset | Height Offset: a textured power border's outward offsets.
    -- Only a detached bar can be textured (an attached bar is painted Solid),
    -- so the row exists only while the painted style is textured.
    do
        local pbPos = SVal("powerPosition", "below")
        local pbTex = SGet("powerBorderStyle") or "solid"
        if (pbPos == "detached_top" or pbPos == "detached_bottom") and pbTex ~= "solid" and pbTex ~= "" then
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function()
                    local pos = SVal("powerPosition", "below")
                    if pos == "above" or pos == "below" then return "solid" end
                    return SGet("powerBorderStyle") or "solid"
                end,
                getStep = function() return SVal("powerBorderSize", 0) end,
                getSizeKey = function() return SVal("powerBorderSize", 0) end,
                getPx = function() return SGet("powerBorderSizePx") end,
                getX = function() return SGet("powerBorderOffsetX") end,
                setX = function(v) SDB().powerBorderOffsetX = v end,
                getY = function() return SGet("powerBorderOffsetY") end,
                setY = function(v) SDB().powerBorderOffsetY = v end,
                apply = ReloadAndUpdate,
            })
            _, h = W:DualRow(parent, y,
                EllesmereUI.BlizzStyle.Gate("unitframes", ocfgL),
                EllesmereUI.BlizzStyle.Gate("unitframes", ocfgR));  y = y - h
        end
    end
    -- Cog for power border shift / layering (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPowerBorderRow._leftRegion
        local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Power Border Options",
            rows = {
                { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                  get = function()
                      local v = SGet("powerBorderShiftX")
                      if v then return v end
                      local tex = SGet("powerBorderStyle") or "solid"
                      local sz = SVal("powerBorderSize", 0)
                      local _, _, dsx = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                      return dsx
                  end,
                  set = function(v) SSet("powerBorderShiftX", v == 0 and nil or v); ReloadAndUpdate() end },
                { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                  get = function()
                      local v = SGet("powerBorderShiftY")
                      if v then return v end
                      local tex = SGet("powerBorderStyle") or "solid"
                      local sz = SVal("powerBorderSize", 0)
                      local _, _, _, dsy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                      return dsy
                  end,
                  set = function(v) SSet("powerBorderShiftY", v == 0 and nil or v); ReloadAndUpdate() end },
                { type = "toggle", label = "Show Behind",
                  get = function() return SVal("powerBorderBehind", false) end,
                  set = function(v) SSet("powerBorderBehind", v); ReloadAndUpdate() end },
            },
        })
        local function UpdatePBCogVis()
            local pos = SVal("powerPosition", "below")
            local isDet = (pos == "detached_top" or pos == "detached_bottom")
            local tex = SGet("powerBorderStyle") or "solid"
            if not isDet or tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdatePBCogVis)
        UpdatePBCogVis()
    end
    -- Inline swatches on Border Size (right region)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedPowerBorderRow._rightRegion
        local ctrl = rightRgn._lastInline or rightRgn._control
        -- Border color swatch
        local pbSwatch, updatePBSwatch = EllesmereUI.BuildColorSwatch(
            rightRgn, sharedPowerBorderRow:GetFrameLevel() + 3,
            function()
                local c = SGet("powerBorderColor") or { r = 0, g = 0, b = 0 }
                return c.r, c.g, c.b, SVal("powerBorderAlpha", 1)
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().powerBorderColor = { r=r, g=g, b=b }
                UNIT_DB_MAP[optState.selectedUnit]().powerBorderAlpha = a
                ReloadAndUpdate()
            end,
            true, 20)
        PP.Point(pbSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        pbSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(pbSwatch, "Border Color")
        end)
        pbSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rightRgn._lastInline = pbSwatch
        EllesmereUI.RegisterWidgetRefresh(function() updatePBSwatch() end)
    end

    -- Spell Cost Prediction (player only, WoW Forever only; the page rebuilds
    -- on unit change): toggle with a preview eyeball | its color. Above Power
    -- Type, which keeps its height when hidden. Built with the engine
    -- (EllesmereUI_SpellCostPrediction.lua, nil off Forever) loaded: the
    -- color and the preview read its color rule.
    if optState.selectedUnit == "player" and EllesmereUI.SpellCostPrediction then
        local costRow
        costRow, h = W:DualRow(parent, y,
            { type="toggle", text="Spell Cost Prediction",
              tooltip="While you cast, shows on the bar the mana the spell will cost.",
              getValue=function() return SVal("powerCostPrediction", false) == true end,
              setValue=function(v) SSet("powerCostPrediction", v); UpdatePreview(); EllesmereUI:RefreshPage() end },
            { type="colorpicker", text="Spell Cost Color",
              disabled=function() return SVal("powerCostPrediction", false) ~= true end,
              disabledTooltip="Spell Cost Prediction",
              getValue=function()
                  local r, g, b = ns.UF_PowerCostColor(SDB())
                  return r, g, b
              end,
              setValue=function(r, g, b)
                  SSet("powerCostColor", { r=r, g=g, b=b }); UpdatePreview()
              end });  y = y - h
        -- Inline eyeball: preview the cost on the live preview. Session-only.
        if not EllesmereUI._prebuilding then
            local rgn = costRow._leftRegion
            local eyeBtn = CreateFrame("Button", nil, rgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(0.4)
            rgn._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshCostEye()
                eyeTex:SetTexture(ns._ufShowPowerCostPreview and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
            end
            RefreshCostEye()
            eyeBtn:SetScript("OnClick", function()
                ns._ufShowPowerCostPreview = not ns._ufShowPowerCostPreview
                RefreshCostEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, ns._ufShowPowerCostPreview and "Hide spell cost preview" or "Show spell cost preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
        end
    end
    if optState.selectedUnit == "player" and EllesmereUI.IS_FOREVER == true then
        -- Mana Regen Spark (EllesmereUI_ManaRegenSpark.lua), the section's
        -- last row; warriors and rogues get no spark engine, so no row. A
        -- druid's Power Type shares it: one choice for every form, stored
        -- under a string key so it can never meet a retail spec ID in the
        -- table.
        -- Off or one of two modes: a view over manaRegenSpark (on/off) and
        -- manaRegenSparkMode (nil = 5-Second Rule), so saved choices read as before.
        local sparkCfg = { type="dropdown", text="Mana Regen Spark",
              tooltip="5-Second Rule sweeps a spark across the bar for 5 seconds after you spend mana, until mana regen resumes. Regen Ticks then keeps sweeping every 2 seconds while mana regenerates.",
              values = { off = "Off", fsr = "5-Second Rule", ticks = "Regen Ticks" },
              order = { "off", "fsr", "ticks" },
              getValue=function()
                  if SVal("manaRegenSpark", false) ~= true then return "off" end
                  return SVal("manaRegenSparkMode", "fsr") == "ticks" and "ticks" or "fsr"
              end,
              setValue=function(v)
                  if v ~= "off" then SSet("manaRegenSparkMode", v == "ticks" and "ticks" or nil) end
                  SSet("manaRegenSpark", v ~= "off")
              end }
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            _, h = W:DualRow(parent, y,
                -- Mana + Form Power: Mana plus foreverFormBar (a second bar
                -- with the form's power, EUI_UnitFrames_ForeverFormBar.lua).
                { type="dropdown", text="Power Type",
                  tooltip="Mana keeps the bar on Mana in Bear and Cat Form. Mana + Form Power also shows your Energy or Rage in a second bar.",
                  values = { ["default"] = "Match Form", ["alt"] = "Mana", ["both"] = "Mana + Form Power" },
                  order = { "default", "alt", "both" },
                  getValue = function()
                      local pdb = UNIT_DB_MAP["player"]()
                      local ov = pdb.powerTypeOverride
                      if not (ov and ov.foreverDruid) then return "default" end
                      return pdb.foreverFormBar and "both" or "alt"
                  end,
                  setValue = function(v)
                      local pdb = UNIT_DB_MAP["player"]()
                      if v ~= "default" then
                          if not pdb.powerTypeOverride then pdb.powerTypeOverride = {} end
                          pdb.powerTypeOverride.foreverDruid = true
                      elseif pdb.powerTypeOverride then
                          pdb.powerTypeOverride.foreverDruid = nil
                      end
                      pdb.foreverFormBar = (v == "both") or nil
                      ReloadAndUpdate()
                  end },
                sparkCfg);  y = y - h
        elseif EllesmereUI.ManaRegenSpark then
            _, h = W:DualRow(parent, y, sparkCfg, EllesmereUI.BlankRowCfg());  y = y - h
        end
    end

    -- Row 6: Power Type override (player-only, spec-dependent)
    do
        local _, playerClass = UnitClass("player")
        -- Specs that offer an alternative power type on the player power bar.
        -- { defaultLabel, altLabel, altPowerType (Enum.PowerType value to force) }
        -- For Shadow Priest the alt is "no override" (nil) so UnitPowerType returns Insanity.
        local SPEC_POWER_ALTS = {
            DRUID  = {
                [1] = { "Astral Power", "Mana",     0 },   -- Balance
                [2] = { "Energy",       "Mana",     0 },   -- Feral
                [3] = { "Rage",         "Mana",     0 },   -- Guardian
            },
            PRIEST = {
                [3] = { "Mana",         "Insanity", nil },  -- Shadow (default is our Mana override)
            },
            SHAMAN = {
                [1] = { "Maelstrom",    "Mana",     0 },   -- Elemental
            },
        }
        local classAlts = SPEC_POWER_ALTS[playerClass]
        -- Retail only: these alternatives are retail spec resources, and the
        -- WoW Forever classes have no specs to key them on.
        if classAlts and not EllesmereUI.IS_FOREVER then
            local GetSpec = C_SpecializationInfo.GetSpecialization
            -- Labels follow the CURRENT spec: the page is built once and
            -- cached, so they are refilled on every spec change (see
            -- UpdatePowerTypeRow), never only at build time.
            local ptValues = {}
            local ptOrder  = { "default", "alt" }
            local function FillPowerTypeValues(s)
                local data = s and classAlts[s]
                ptValues["default"] = data and data[1] or nil
                ptValues["alt"]     = data and data[2] or nil
            end
            local labelSpec = GetSpec()
            FillPowerTypeValues(labelSpec)

            local sharedPowerRow5
            sharedPowerRow5, h = W:DualRow(parent, y,
                { type="dropdown", text="Power Type",
                  values = ptValues, order = ptOrder,
                  -- Stored by SPEC ID, not the GetSpecialization() index: one
                  -- profile holds one set, so an index key collides across
                  -- classes (slot 3 is Guardian, Shadow AND Augmentation).
                  -- classAlts stays index-keyed, it is already per class.
                  getValue = function()
                      local s = GetSpec()
                      if not s or not classAlts[s] then return "default" end
                      local sid = C_SpecializationInfo
                          and C_SpecializationInfo.GetSpecializationInfo(s)
                      if not sid then return "default" end
                      local ov = UNIT_DB_MAP["player"]().powerTypeOverride
                      if ov and ov[sid] then return "alt" end
                      return "default"
                  end,
                  setValue = function(v)
                      local s = GetSpec()
                      if not s then return end
                      local sid = C_SpecializationInfo
                          and C_SpecializationInfo.GetSpecializationInfo(s)
                      if not sid then return end
                      local pdb = UNIT_DB_MAP["player"]()
                      if v == "alt" then
                          if not pdb.powerTypeOverride then pdb.powerTypeOverride = {} end
                          pdb.powerTypeOverride[sid] = true
                      else
                          if pdb.powerTypeOverride then pdb.powerTypeOverride[sid] = nil end
                      end
                      ReloadAndUpdate()
                  end },
                { type="label", text="" }); y = y - h

            local function UpdatePowerTypeRow()
                local s = GetSpec()
                if s ~= labelSpec then
                    labelSpec = s
                    FillPowerTypeValues(s)
                    local dd = sharedPowerRow5._leftRegion and sharedPowerRow5._leftRegion._control
                    if dd and dd._invalidateMenu then dd._invalidateMenu() end
                end
                if optState.selectedUnit == "player" and s and classAlts[s] then
                    sharedPowerRow5:Show()
                else
                    sharedPowerRow5:Hide()
                end
            end
            RegisterWidgetRefresh(UpdatePowerTypeRow)
            UpdatePowerTypeRow()
        end
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y, sharedPowerHeader, sharedPowerRow1, sharedPowerRow2
end

function ns.UFO_BuildClassResourceSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, RegisterWidgetRefresh, ReloadAndUpdate, SHORT_LABELS = env.GROUP_UNIT_ORDER, env.RegisterWidgetRefresh, env.ReloadAndUpdate, env.SHORT_LABELS
    local UNIT_DB_MAP, UpdatePreview, classPowerPosOrder, classPowerPosValues = env.UNIT_DB_MAP, env.UpdatePreview, env.classPowerPosOrder, env.classPowerPosValues
    local classPowerStyleOrder, classPowerStyleValues, optState = env.classPowerStyleOrder, env.classPowerStyleValues, env.optState
    local W, SApplySupport, SGetSupported, SSetSupported = ctx.W, ctx.SApplySupport, ctx.SGetSupported, ctx.SSetSupported
    local SValSupported = ctx.SValSupported
    local _, h
    local row

    -- CLASS RESOURCE section: only shown in multi-edit or when player is selected
    local _showClassRes = optState.selectedUnit == "player"
    -- Declared outside the gate: returned for the click mapping.
    local sharedClassResHeader, sharedClassResRow
    if _showClassRes then
    _, h = W:Spacer(parent, y, 20); y = y - h

    -------------------------------------------------------------------
    --  CLASS RESOURCE
    -------------------------------------------------------------------
    sharedClassResHeader, h = W:SectionHeader(parent, "CLASS RESOURCE", y); y = y - h

    -- The class resource style that builds: WoW Forever outside its own
    -- style builds a saved "blizzard" as modern, and a rogue under the
    -- EllesmereUI look reads its own style (ns.UF_ForeverCPStyle, nil
    -- elsewhere). Display and gating only; writes and syncs keep the saved value.
    local function SCPStyle()
        local v = SValSupported("classPowerStyle", "none")
        if ns.UF_ForeverCPStyle then v = ns.UF_ForeverCPStyle(v) end
        return v
    end

    -- Row 1: Enable Class Resource + Class Colors (with inline swatch)
    sharedClassResRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Enable Class Resource", values=classPowerStyleValues, order=classPowerStyleOrder,
          -- Forever ships no class resource bar that can be re-parented: the
          -- per-class globals the Blizzard style adopts are all Mainline-only.
          -- Under the WoW Forever style the entry is the combo point arc
          -- instead (placed by Combo Points, below), and stays live.
          disabledValues=function(k)
              if k == "blizzard" and EllesmereUI.IS_FOREVER and not EllesmereUI.BlizzStyle.Forever("unitframes") then
                  return "This option requires the WoW Forever style."
              end
              -- One owner for Blizzard's class resource frame: while Resource
              -- Bars' Blizzard Class Resource Art is on, Blizzard is greyed here.
              -- Only while not already chosen, so it can still be changed away.
              if k == "blizzard" and SValSupported("classPowerStyle", "none") ~= "blizzard" then
                  if _G._ERB_BlizzArtWanted and _G._ERB_BlizzArtWanted() then
                      return "This option can't be used while Blizzard Class Resource Art is enabled in Resource Bars."
                  end
              end
          end,
          getValue=function() return SCPStyle() end,
          -- DependentSetValue: Rows 2-3 below are hidden while the style
          -- is None; only the None <-> enabled flip forces the rebuild
          -- (style-to-style changes keep the cheap refresh path).
          setValue=EllesmereUI.DependentSetValue(
              function() return SCPStyle() ~= "none" end,
              function(v)
                  -- WoW Forever rogues under the EllesmereUI look pick their
                  -- own style (ns.UF_RogueCPKey); the shared one stays as is.
                  local rogueKey = ns.UF_RogueCPKey and ns.UF_RogueCPKey()
                  if rogueKey then
                      UNIT_DB_MAP[optState.selectedUnit]()[rogueKey] = v
                      if ns.frames and ns.frames._toggleClassPower then
                          ns.frames._toggleClassPower()
                      end
                      ReloadAndUpdate()
                  else
                      SSetSupported("classPowerStyle", v)
                      SSetSupported("showClassPowerBar", v ~= "none")
                      if ns.frames and ns.frames._toggleClassPower then
                          ns.frames._toggleClassPower(v)
                      end
                  end
                  UpdatePreview()
                  C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
                  -- WoW Forever: Blizzard's own combo points (beside Blizzard's
                  -- own target frame) went to the hidden parent for another
                  -- Combo Points spot: only a reload brings them back.
                  if v == "none" and ns._ufComboFrameByLoc then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Blizzard's combo points return to its target frame after a UI reload.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          reload      = true,
                      })
                  end
              end) },
        { type="multiSwatch", text="Fill Color",
          disabled=function() return SCPStyle() ~= "modern" end,
          disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
          swatches = {
            { tooltip = "Custom Colored",
              hasAlpha = false,
              getValue = function()
                  local c = SGetSupported("classPowerCustomColor")
                  c = c or { r = 1, g = 0.82, b = 0 }
                  return c.r, c.g, c.b, 1
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().classPowerCustomColor = { r=r, g=g, b=b }
                  if ns.frames and ns.frames._toggleClassPower then
                      ns.frames._toggleClassPower()
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end,
              onClick = function(self)
                  if SGetSupported("classPowerClassColor") then
                      SSetSupported("classPowerClassColor", false)
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SGetSupported("classPowerClassColor") and 0.3 or 1
              end },
            { tooltip = "Dynamic Colored",
              getValue = function()
                  local _, ct = UnitClass("player")
                  if ct and RAID_CLASS_COLORS[ct] then
                      local cc = RAID_CLASS_COLORS[ct]
                      return cc.r, cc.g, cc.b, 1
                  end
                  return 1, 0.82, 0, 1
              end,
              setValue = function() end,
              onClick = function()
                  SSetSupported("classPowerClassColor", true)
                  ReloadAndUpdate(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SGetSupported("classPowerClassColor") and 1 or 0.3
              end },
          } });  y = y - h
    SApplySupport(sharedClassResRow._leftRegion, "classPowerStyle")
    SApplySupport(sharedClassResRow._rightRegion, "classPowerClassColor")

    -- Inline "Empty Bar Color" swatch on Class Colors row (next to custom color swatch)
    if not EllesmereUI._prebuilding then
        local ccRgn = sharedClassResRow._rightRegion
        local emptySwatch = EllesmereUI.BuildColorSwatch(ccRgn, ccRgn:GetFrameLevel() + 5,
            function()
                local c = SGetSupported("classPowerEmptyColor")
                c = c or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }
                return c.r, c.g, c.b, c.a or 1
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().classPowerEmptyColor = { r = r, g = g, b = b, a = a or 1 }
                if ns.frames and ns.frames._toggleClassPower then
                    ns.frames._toggleClassPower()
                end
                ReloadAndUpdate(); UpdatePreview()
            end, true, 20)
        emptySwatch:SetPoint("RIGHT", ccRgn._lastInline or ccRgn._control, "LEFT", -6, 0)
        ccRgn._lastInline = emptySwatch
        local function UpdateEmptySwatch()
            local crOff = SCPStyle() ~= "modern"
            if crOff then
                emptySwatch:SetAlpha(0.15); emptySwatch:Disable()
            else
                emptySwatch:SetAlpha(1); emptySwatch:Enable()
            end
        end
        UpdateEmptySwatch()
        RegisterWidgetRefresh(UpdateEmptySwatch)
        emptySwatch:HookScript("OnEnter", function(self)
            if SCPStyle() ~= "modern" then
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("This option requires Class Resource to be set to Modern."))
            else
                EllesmereUI.ShowWidgetTooltip(self, "Empty Bar Color")
            end
        end)
        emptySwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end
    -- Sync icons: Enable Class Resource (left) and Class Colors (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedClassResRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Resource Style to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerStyle or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    UNIT_DB_MAP[key]().classPowerStyle = v
                    UNIT_DB_MAP[key]().showClassPowerBar = (v ~= "none")
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerStyle or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().classPowerStyle or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerStyle or "none"
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().classPowerStyle = v
                        UNIT_DB_MAP[key]().showClassPowerBar = (v ~= "none")
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedClassResRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Colors to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerClassColor
                if v == nil then v = true end
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerClassColor = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerClassColor
                if v == nil then v = true end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local ov = UNIT_DB_MAP[key]().classPowerClassColor
                    if ov == nil then ov = true end
                    if ov ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerClassColor
                    if v == nil then v = true end
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerClassColor = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Rows 2-3 are HIDDEN entirely while Enable Class Resource is None
    -- (the dropdown's DependentSetValue forces the rebuild on flips).
    if SCPStyle() ~= "none" then
    -- Row 2: Position (with cog for x/y) + Size
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Position", values=classPowerPosValues, order=classPowerPosOrder,
          disabled=function() return SCPStyle() ~= "modern" end,
          disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
          getValue=function() return SValSupported("classPowerPosition", "top") end,
          setValue=function(v)
              SSetSupported("classPowerPosition", v)
              if ns.frames and ns.frames._toggleClassPower then
                  ns.frames._toggleClassPower()
              end
              UpdatePreview(); UpdatePreview()
          end },
        { type="slider", text="Size", min=4, max=100, step=1,
          disabled=function() return SCPStyle() ~= "modern" end,
          disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
          getValue=function() return SValSupported("classPowerSize", 8) end,
          setValue=function(v)
              SSetSupported("classPowerSize", v)
              if ns.frames and ns.frames._toggleClassPower then
                  ns.frames._toggleClassPower()
              end
              UpdatePreview(); UpdatePreview()
          end });  y = y - h
    SApplySupport(row._leftRegion, "classPowerPosition")
    SApplySupport(row._rightRegion, "classPowerSize")
    -- Cog on Position for X/Y
    if not EllesmereUI._prebuilding then
        local posRgn = row._leftRegion
        EllesmereUI.BuildInlineCog(posRgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() return SCPStyle() ~= "modern" or SValSupported("classPowerPosition", "top") == "above" end,
            disabledTooltip = function() return SCPStyle() ~= "modern" and "This option requires Class Resource to be set to Modern." or "This option requires a dropdown selection other than Above Health Bar" end,
            title = "Class Resource Position",
            rows = {
                { type="slider", label="X Offset", min=-100, max=100, step=1,
                  get=function() return SValSupported("classPowerBarX", 0) end,
                  set=function(v) SSetSupported("classPowerBarX", v)
                      if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                      UpdatePreview(); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-100, max=100, step=1,
                  get=function() return SValSupported("classPowerBarY", 0) end,
                  set=function(v) SSetSupported("classPowerBarY", v)
                      if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
                      UpdatePreview(); UpdatePreview() end },
            },
        })
    end
    -- Sync icons: Class Resource Position (left) and Size (right)
    if not EllesmereUI._prebuilding then
        local rgn = row._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Resource Position to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerPosition or "top"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerPosition = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerPosition or "top"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().classPowerPosition or "top") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerPosition or "top"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerPosition = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = row._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Resource Size to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSize or 8
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerSize = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSize or 8
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().classPowerSize or 8) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSize or 8
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 3: Bar Spacing + Background Color (with alpha)
    local sharedClassResRow3
    sharedClassResRow3, h = W:DualRow(parent, y,
        { type="slider", pixel=true, text="Bar Spacing", min=0, max=10, step=1,
          disabled=function() return SCPStyle() ~= "modern" end,
          disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
          getValue=function() return SValSupported("classPowerSpacing", 2) end,
          setValue=function(v)
              SSetSupported("classPowerSpacing", v)
              if ns.frames and ns.frames._toggleClassPower then ns.frames._toggleClassPower() end
              UpdatePreview(); UpdatePreview()
          end },
        { type="colorpicker", text="Background Color", hasAlpha=true,
          disabled=function() return SCPStyle() ~= "modern" end,
          disabledTooltip="Class Resource must be set to Modern", rawTooltip=true,
          getValue=function()
              local c = SGetSupported("classPowerBgColor")
              c = c or { r=0.082, g=0.082, b=0.082, a=1.0 }
              return c.r, c.g, c.b, c.a
          end,
          setValue=function(r, g, b, a)
              SSetSupported("classPowerBgColor", { r=r, g=g, b=b, a=a or 1 })
              UpdatePreview()
          end });  y = y - h
    SApplySupport(sharedClassResRow3._leftRegion, "classPowerSpacing")
    SApplySupport(sharedClassResRow3._rightRegion, "classPowerBgColor")
    -- Sync icons: Bar Spacing (left) and Background Color (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedClassResRow3._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Resource Bar Spacing to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSpacing or 2
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().classPowerSpacing = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSpacing or 2
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().classPowerSpacing or 2) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerSpacing or 2
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().classPowerSpacing = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedClassResRow3._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Class Resource Background Color to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerBgColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if v then UNIT_DB_MAP[key]().classPowerBgColor = { r=v.r, g=v.g, b=v.b, a=v.a }
                    else UNIT_DB_MAP[key]().classPowerBgColor = nil end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerBgColor
                local vr = v and v.r or 0
                local vg = v and v.g or 0
                local vb = v and v.b or 0
                local va = v and v.a or 0.5
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local ov = UNIT_DB_MAP[key]().classPowerBgColor
                    local or_ = ov and ov.r or 0
                    local og = ov and ov.g or 0
                    local ob = ov and ov.b or 0
                    local oa = ov and ov.a or 0.5
                    if or_ ~= vr or og ~= vg or ob ~= vb or oa ~= va then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().classPowerBgColor
                    for _, key in ipairs(checkedKeys) do
                        if v then UNIT_DB_MAP[key]().classPowerBgColor = { r=v.r, g=v.g, b=v.b, a=v.a }
                        else UNIT_DB_MAP[key]().classPowerBgColor = nil end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- WoW Forever: where the "Blizzard" class resource (the combo point arc)
    -- shows -- the target frame (the stock spot), the player frame, or
    -- nowhere. The section's last row, built under the WoW Forever style for
    -- the classes with combo points there.
    if EllesmereUI.IS_FOREVER == true and EllesmereUI.BlizzStyle.Forever("unitframes")
       and ns.UF_ComboClass() then
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Combo Points",
              tooltip="Choose where your combo points show.",
              values={ target = "Target Frame", player = "Player Frame", never = "Never" },
              order={ "target", "player", "never" },
              disabled=function() return SCPStyle() ~= "blizzard" end,
              disabledTooltip="Class Resource must be set to Blizzard", rawTooltip=true,
              getValue=function() return ns.UF_ComboLocation() end,
              setValue=function(v)
                  UNIT_DB_MAP["player"]().foreverComboLocation = v
                  ns.UF_ApplyForeverComboArc()
                  -- Blizzard's own, beside Blizzard's own target frame, went
                  -- to the hidden parent for another spot: only a reload
                  -- brings it back.
                  if v == "target" and ns._ufComboFrameByLoc then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Blizzard's combo points return to its target frame after a UI reload.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          reload      = true,
                      })
                  end
              end },
            EllesmereUI.BlankRowCfg());  y = y - h
    end
    end   -- close Class Resource hidden-while-None gate

    end -- _showClassRes

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y, sharedClassResHeader, sharedClassResRow
end

function ns.UFO_BuildAbsorbsHealsSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, RegisterWidgetRefresh, ReloadAndUpdate, SHORT_LABELS = env.GROUP_UNIT_ORDER, env.RegisterWidgetRefresh, env.ReloadAndUpdate, env.SHORT_LABELS
    local UNIT_DB_MAP, UpdatePreview, db, optState = env.UNIT_DB_MAP, env.UpdatePreview, env.db, env.optState
    local W, SApplySupport, SGetSupported, SSetSupported = ctx.W, ctx.SApplySupport, ctx.SGetSupported, ctx.SSetSupported
    local SValSupported = ctx.SValSupported
    local _, h

    -------------------------------------------------------------------
    --  ABSORBS (player/target/focus -- mirrors the Raid Frames section)
    -------------------------------------------------------------------
    -- Declared outside the gate: the click-mapping table at the bottom of
    -- this function references them (block-locals would be nil there).
    local sharedAbsorbsHeader, absorbRow, healAbsorbRow
    local _supportsAbsorbs = (optState.selectedUnit == "player" or optState.selectedUnit == "target" or optState.selectedUnit == "focus")
    if _supportsAbsorbs then
    sharedAbsorbsHeader, h = W:SectionHeader(parent, "ABSORBS AND HEALS", y); y = y - h

    -- Names and orders live on ns (EllesmereUIUnitFrames.lua, shared with the
    -- Textures page tile); fresh copies here because the SharedMedia tail
    -- below is appended into them. Shield (regular) absorb order; heal absorb
    -- uses its own (it adds the two "Outlined" variants on top).
    local absorbStyleValues = CopyTable(ns.ABSORB_STYLE_NAMES)
    local absorbStyleOrder = CopyTable(ns.ABSORB_STYLE_ORDER)
    local healAbsorbStyleOrder = CopyTable(ns.HEAL_ABSORB_STYLE_ORDER)
    -- Append SharedMedia statusbar textures after a divider, mirroring the Bar
    -- Texture dropdown. SM keys ("sm:" prefixed) come from AppendSharedMediaTextures
    -- into the shared health-bar tables; render resolves via ns.ResolveAbsorbStyleTex
    -- -> the health-bar texture lookup. Shield and heal-absorb share absorbStyleValues, so both gain the SM entries and preview swatch.
    do
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
        local smNames = ns.healthBarTextureNames or {}
        local smKeys = {}
        for _, k in ipairs(ns.healthBarTextureOrder or {}) do
            if type(k) == "string" and k:find("^sm:") then
                smKeys[#smKeys + 1] = k
                absorbStyleValues[k] = smNames[k] or k
            end
        end
        if #smKeys > 0 then
            absorbStyleOrder[#absorbStyleOrder + 1] = "---"
            healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = "---"
            for _, k in ipairs(smKeys) do
                absorbStyleOrder[#absorbStyleOrder + 1] = k
                healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = k
            end
        end
        -- Preview swatch behind each menu row, resolved exactly like render.
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" or key == "none" then return nil end
                return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex(key) or nil
            end,
        }
    end

    -- Effective absorb opacity: absorbOpacity once set, otherwise the
    -- pre-split behavior (clean -> absorbCleanAlpha, other styles 80).
    -- Must match GetAbsorbOpacity in EllesmereUIUnitFrames.lua.
    local function EffAbsorbOpacity()
        local v = SValSupported("absorbOpacity", nil)
        if v then return v end
        if SValSupported("showPlayerAbsorb", "none") == "clean" then
            return SValSupported("absorbCleanAlpha", 30)
        end
        return 80
    end

    -- Absorb Style / Heal Absorb Style sync icons carry style + swatch + every
    -- inline-cog setting together. Each entry is a DB key + default, so an unset
    -- value compares equal to an explicit one; color tables are deep-copied and compared by component.
    local ABSORB_SYNC_DEFS = {
        { k = "showPlayerAbsorb", d = "none" },
        { k = "absorbColor",      d = { r = 1, g = 1, b = 1 } },
        { k = "absorbEdgeMode",   d = "overlay" },
        { k = "showOvershield",   d = true },
        { k = "overshieldMode" },  -- d nil on purpose: unset copies as unset (legacy-boolean fallback stays live)
        { k = "absorbGlowLine",        d = false },
        { k = "absorbGlowLineTexture", d = "blizzard" },
    }
    local HEAL_ABSORB_SYNC_DEFS = {
        { k = "healAbsorbStyle",     d = "clean" },
        { k = "healAbsorbColor",     d = { r = 0.8, g = 0.15, b = 0.15 } },
        { k = "healAbsorbEdgeMode",  d = "overlay" },
        { k = "healAbsorbBgOpacity", d = 15 },
    }
    local function _AbsSyncValEq(a, b)
        if type(a) == "table" or type(b) == "table" then
            a = a or {}; b = b or {}
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end
        return a == b
    end
    local function CopyAbsorbSync(defs, srcUnit, dstUnit)
        if srcUnit == dstUnit then return end
        local src, dst = UNIT_DB_MAP[srcUnit](), UNIT_DB_MAP[dstUnit]()
        for _, e in ipairs(defs) do
            local v = src[e.k]; if v == nil then v = e.d end
            if type(v) == "table" then
                dst[e.k] = { r = v.r, g = v.g, b = v.b, a = v.a }
            else
                dst[e.k] = v
            end
        end
    end
    local function AbsorbSyncMatches(defs, srcUnit, units)
        local src = UNIT_DB_MAP[srcUnit]()
        for _, unit in ipairs(units) do
            local dst = UNIT_DB_MAP[unit]()
            for _, e in ipairs(defs) do
                local a = src[e.k]; if a == nil then a = e.d end
                local b = dst[e.k]; if b == nil then b = e.d end
                if not _AbsSyncValEq(a, b) then return false end
            end
        end
        return true
    end

    -- Row 1: Absorb Style (+ color swatch + placement cog) | Absorb Opacity
    absorbRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
          getValue=function() return SValSupported("showPlayerAbsorb", "none") end,
          setValue=function(v)
              if v == "clean" then
                  UNIT_DB_MAP[optState.selectedUnit]().absorbOpacity = 30
              else
                  UNIT_DB_MAP[optState.selectedUnit]().absorbOpacity = 90
              end
              SSetSupported("showPlayerAbsorb", v)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Absorb Opacity", min=5, max=100, step=1,
          disabled=function() return SValSupported("showPlayerAbsorb", "none") == "none" end,
          disabledTooltip="Absorb Style",
          getValue=EffAbsorbOpacity,
          setValue=function(v) SSetSupported("absorbOpacity", v) end });  y = y - h
    SApplySupport(absorbRow._leftRegion, "showPlayerAbsorb")
    SApplySupport(absorbRow._rightRegion, "absorbOpacity")
    -- Inline color swatch for absorb color
    if not EllesmereUI._prebuilding then
        local rgn = absorbRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, absorbRow:GetFrameLevel() + 3,
            function()
                local c = SGetSupported("absorbColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().absorbColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local function UpdateAbsorbSwatchVis()
            swatch:SetAlpha(SValSupported("showPlayerAbsorb", "none") == "none" and 0.3 or 1)
        end
        RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
        UpdateAbsorbSwatchVis()
    end
    -- Inline cog: absorb placement (overlay / right edge / left edge)
    do
        local rgn = absorbRow._leftRegion
        -- Placement labels follow the FILL AXIS: saved values stay right/left (they
        -- mean the FAR/NEAR end of the fill), but wording flips to top/bottom on a
        -- vertical bar. MUTATED IN PLACE, never rebuilt: RefreshPage's fast path
        -- doesn't rebuild the page and the cog popup is built once then cached, so a
        -- fresh table would never reach it; _invalidateMenu forces the cached menu to reread this table on next click.
        local absorbEdgeLabels = { overlay = "Overlay", overlayReverse = "Overlay Reverse", overlayReverseFull = "Overlay Reverse (Full)" }
        local absorbEdgeLabelsVert  -- last applied axis; nil until the first sync
        -- Returns true only if the axis flipped, so the caller can skip
        -- _invalidateMenu on unrelated refreshes (would break a wired-open click).
        local function SyncAbsorbEdgeLabels()
            local vert = (SValSupported("healthVerticalFill", false)) and true or false
            if absorbEdgeLabelsVert == vert then return false end
            absorbEdgeLabelsVert = vert
            absorbEdgeLabels.right = vert and "From Top Edge"    or "From Right Edge"
            absorbEdgeLabels.left  = vert and "From Bottom Edge" or "From Left Edge"
            return true
        end
        SyncAbsorbEdgeLabels()
        local _, cogShow = EllesmereUI.BuildInlineCog(rgn, {
            title = "Absorb Rendering",
            rows = {
                { type="dropdown", label="Placement",
                  values = absorbEdgeLabels,
                  -- Wide enough for "Overlay Reverse (Full)".
                  ddWidth = 190,
                  order = { "overlay", "overlayReverse", "overlayReverseFull", "right", "left" },
                  get=function() SyncAbsorbEdgeLabels(); return SValSupported("absorbEdgeMode", "overlay") end,
                  set=function(v) SSetSupported("absorbEdgeMode", v) end },
                { type="dropdown", label="Show Overshield",
                  tooltip="Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                  values = { never = "Never", always = "Always", fromleft = "From Left" },
                  order = { "never", "always", "fromleft" },
                  -- From Left only exists in the plain Overlay placement:
                  -- edge modes have no overshield, Overlay Reverse
                  -- already clamps the whole absorb inside the fill and
                  -- its Full variant draws the excess from the origin edge.
                  itemDisabled=function(v)
                      return v == "fromleft" and SValSupported("absorbEdgeMode", "overlay") ~= "overlay"
                  end,
                  get=function()
                      -- Legacy boolean fallback: profiles saved before the
                      -- dropdown keep their toggle's meaning.
                      local m = SValSupported("overshieldMode", nil)
                      if m == nil then m = (SValSupported("showOvershield", true) == false) and "never" or "always" end
                      return m
                  end,
                  set=function(v)
                      -- Mirror the legacy boolean so pre-dropdown readers
                      -- (incl. the live-client profile) track Never/Always.
                      SSetSupported("showOvershield", v ~= "never")
                      SSetSupported("overshieldMode", v)
                  end },
                -- Opt-in glow line on the shield's edge (runtime twin:
                -- ns.UF_AbsorbGlowApply). Nothing is drawn with Absorb Style
                -- None, on a vertical fill or with the placement on the edge
                -- the health fills from.
                { type="toggle", label="Blizzard Glow Line",
                  tooltip="Adds the Blizzard shield glow line where the shield meets current health.",
                  disabled=function()
                      if SValSupported("showPlayerAbsorb", "none") == "none" then return true end
                      if SValSupported("healthVerticalFill", false) == true then return true end
                      local originEdge = (SValSupported("healthReverseFill", false) == true) and "right" or "left"
                      return SValSupported("absorbEdgeMode", "overlay") == originEdge
                  end,
                  disabledTooltip=function()
                      if SValSupported("showPlayerAbsorb", "none") == "none" then
                          return "The glow line is not shown with Absorb Style None"
                      end
                      if SValSupported("healthVerticalFill", false) ~= true and SValSupported("healthReverseFill", false) == true then
                          return "The glow line is not shown on a vertical fill or with the From Right Edge placement"
                      end
                      return "The glow line is not shown on a vertical fill or with the From Left Edge placement"
                  end,
                  rawTooltip=true,
                  get=function() return SValSupported("absorbGlowLine", false) == true end,
                  set=function(v) SSetSupported("absorbGlowLine", v and true or false) end },
                { type="dropdown", label="Glow Line Texture",
                  tooltip="Art used for the glow line and the overshield edge.",
                  values = { blizzard = "Blizzard", pixelsGlow = "Pixels Glow Line", pixelsOvershield = "Pixels Overshield Line" },
                  order = { "blizzard", "pixelsGlow", "pixelsOvershield" },
                  disabled=function() return SValSupported("absorbGlowLine", false) ~= true end,
                  disabledTooltip="Blizzard Glow Line",
                  get=function() return SValSupported("absorbGlowLineTexture", "blizzard") end,
                  set=function(v) SSetSupported("absorbGlowLineTexture", v) end },
                -- Single global toggle (boss block key, nil = enabled):
                -- boss frames render absorbs with the TARGET frame's
                -- absorb styling -- no per-boss customization.
                { type="toggle", label="Show on Boss Frames",
                  tooltip="Render absorbs on Boss Frames using the Target frame's absorb styling.",
                  get=function() return not (db.profile.boss and db.profile.boss.showAbsorbs == false) end,
                  set=function(v)
                      local b = db.profile.boss
                      if b then
                          if v then b.showAbsorbs = nil else b.showAbsorbs = false end
                      end
                      ReloadAndUpdate()
                  end },
            },
        })
        -- Re-label on every page refresh (the Vertical Fill toggle fires one) and
        -- drop any built menu so its entries rebuild with the new wording.
        RegisterWidgetRefresh(function()
            if not SyncAbsorbEdgeLabels() then return end
            local pf = cogShow and cogShow._popupFrame
            if pf and pf.GetChildren then
                for _, child in ipairs({ pf:GetChildren() }) do
                    if child._invalidateMenu then child._invalidateMenu() end
                end
            end
        end)
    end
    -- Sync icon: Absorb Style + color swatch + cog settings across all frames
    if not EllesmereUI._prebuilding then
        local rgn = absorbRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Absorb Style, color and rendering to all Frames",
            onClick = function()
                for _, key in ipairs(GROUP_UNIT_ORDER) do CopyAbsorbSync(ABSORB_SYNC_DEFS, optState.selectedUnit, key) end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                return AbsorbSyncMatches(ABSORB_SYNC_DEFS, optState.selectedUnit, GROUP_UNIT_ORDER)
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do CopyAbsorbSync(ABSORB_SYNC_DEFS, optState.selectedUnit, key) end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 2: Heal Absorb Style (+ color swatch + placement cog) | Heal Absorb Opacity
    healAbsorbRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Heal Absorb Style", values=absorbStyleValues,
          order=healAbsorbStyleOrder,
          getValue=function() return SValSupported("healAbsorbStyle", "clean") end,
          setValue=function(v)
              if v == "clean" then
                  UNIT_DB_MAP[optState.selectedUnit]().healAbsorbOpacity = 50
              else
                  UNIT_DB_MAP[optState.selectedUnit]().healAbsorbOpacity = 75
              end
              SSetSupported("healAbsorbStyle", v)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Heal Absorb Opacity", min=5, max=100, step=1,
          disabled=function() return SValSupported("healAbsorbStyle", "clean") == "none" end,
          disabledTooltip="Heal Absorb Style",
          getValue=function() return SValSupported("healAbsorbOpacity", 65) end,
          setValue=function(v) SSetSupported("healAbsorbOpacity", v) end });  y = y - h
    SApplySupport(healAbsorbRow._leftRegion, "healAbsorbStyle")
    SApplySupport(healAbsorbRow._rightRegion, "healAbsorbOpacity")
    -- Inline eyeball: preview heal absorb on the live preview (hides the shield
    -- absorb there so heal absorb shows in isolation). Session-only runtime flag.
    if not EllesmereUI._prebuilding then
        local rgn = healAbsorbRow._leftRegion
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        rgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshHealEye()
            eyeTex:SetTexture(optState.showHealAbsorbPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshHealEye()
        eyeBtn:SetScript("OnClick", function()
            optState.showHealAbsorbPreview = not optState.showHealAbsorbPreview
            RefreshHealEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, optState.showHealAbsorbPreview and "Hide heal absorb preview" or "Show heal absorb preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end
    -- Inline color swatch for heal absorb color
    if not EllesmereUI._prebuilding then
        local rgn = healAbsorbRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, healAbsorbRow:GetFrameLevel() + 3,
            function()
                local c = SGetSupported("healAbsorbColor")
                if c then return c.r or 0.8, c.g or 0.15, c.b or 0.15, 1 end
                return 0.8, 0.15, 0.15, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().healAbsorbColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- Blocking overlay: disabled for "none" and the pre-colored
        -- "Large Outlined Stripes" heal styles (their texture is not tinted).
        local swatchBlock = CreateFrame("Frame", nil, swatch)
        swatchBlock:SetAllPoints()
        swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
        swatchBlock:EnableMouse(true)
        swatchBlock:Hide()
        local function UpdateHealAbsorbSwatchVis()
            local st = SValSupported("healAbsorbStyle", "clean")
            local off = (st == "none" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
            swatch:SetAlpha(off and 0.3 or 1)
            if off then swatchBlock:Show() else swatchBlock:Hide() end
        end
        RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
        UpdateHealAbsorbSwatchVis()
    end
    -- Inline cog: heal absorb placement (independent of shield absorb)
    do
        local rgn = healAbsorbRow._leftRegion
        -- Placement labels follow the FILL AXIS: saved values stay right/left (they
        -- mean the FAR/NEAR end of the fill), but wording flips to top/bottom on a
        -- vertical bar. MUTATED IN PLACE, never rebuilt: RefreshPage's fast path
        -- doesn't rebuild the page and the cog popup is built once then cached, so a
        -- fresh table would never reach it; _invalidateMenu forces the cached menu to reread this table on next click.
        local healAbsorbEdgeLabels = { overlay = "Overlay" }
        local healAbsorbEdgeLabelsVert  -- last applied axis; nil until the first sync
        -- Returns true only if the axis flipped, so the caller can skip
        -- _invalidateMenu on unrelated refreshes (would break a wired-open click).
        local function SyncHealAbsorbEdgeLabels()
            local vert = (SValSupported("healthVerticalFill", false)) and true or false
            if healAbsorbEdgeLabelsVert == vert then return false end
            healAbsorbEdgeLabelsVert = vert
            healAbsorbEdgeLabels.right = vert and "From Top Edge"    or "From Right Edge"
            healAbsorbEdgeLabels.left  = vert and "From Bottom Edge" or "From Left Edge"
            return true
        end
        SyncHealAbsorbEdgeLabels()
        local _, cogShow = EllesmereUI.BuildInlineCog(rgn, {
            title = "Heal Absorb Rendering",
            rows = {
                { type="dropdown", label="Placement",
                  values = healAbsorbEdgeLabels,
                  order = { "overlay", "right", "left" },
                  get=function() SyncHealAbsorbEdgeLabels(); return SValSupported("healAbsorbEdgeMode", "overlay") end,
                  set=function(v) SSetSupported("healAbsorbEdgeMode", v) end },
                { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                  get=function() return SValSupported("healAbsorbBgOpacity", 15) end,
                  set=function(v) SSetSupported("healAbsorbBgOpacity", v) end },
            },
        })
        -- Re-label on every page refresh (the Vertical Fill toggle fires one) and
        -- drop any built menu so its entries rebuild with the new wording.
        RegisterWidgetRefresh(function()
            if not SyncHealAbsorbEdgeLabels() then return end
            local pf = cogShow and cogShow._popupFrame
            if pf and pf.GetChildren then
                for _, child in ipairs({ pf:GetChildren() }) do
                    if child._invalidateMenu then child._invalidateMenu() end
                end
            end
        end)
    end
    -- Sync icon: Heal Absorb Style + color swatch + cog settings across all frames
    if not EllesmereUI._prebuilding then
        local rgn = healAbsorbRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Heal Absorb Style, color and rendering to all Frames",
            onClick = function()
                for _, key in ipairs(GROUP_UNIT_ORDER) do CopyAbsorbSync(HEAL_ABSORB_SYNC_DEFS, optState.selectedUnit, key) end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                return AbsorbSyncMatches(HEAL_ABSORB_SYNC_DEFS, optState.selectedUnit, GROUP_UNIT_ORDER)
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do CopyAbsorbSync(HEAL_ABSORB_SYNC_DEFS, optState.selectedUnit, key) end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 3: Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
    local absorbBarRow
    absorbBarRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Absorb Bar",
          values={ none="None", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", bottomRight="Bottom Right", bottomLeft="Bottom Left" },
          order={ "none", "aboveRight", "aboveLeft", "topRight", "topLeft", "bottomRight", "bottomLeft" },
          getValue=function() return SValSupported("absorbBarPosition", "none") end,
          setValue=function(v) SSetSupported("absorbBarPosition", v); EllesmereUI:RefreshPage() end },
        { type="slider", text="Bar Height", min=1, max=20, step=1,
          disabled=function() return SValSupported("absorbBarPosition", "none") == "none" end,
          disabledTooltip="Absorb Bar",
          getValue=function() return SValSupported("absorbBarHeight", 4) end,
          setValue=function(v) SSetSupported("absorbBarHeight", v) end });  y = y - h
    SApplySupport(absorbBarRow._leftRegion, "absorbBarPosition")
    SApplySupport(absorbBarRow._rightRegion, "absorbBarHeight")
    if not EllesmereUI._prebuilding then
        local rgn = absorbBarRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, absorbBarRow:GetFrameLevel() + 3,
            function()
                local c = SGetSupported("absorbBarColor")
                if c then return c.r, c.g, c.b, c.a or 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().absorbBarColor = { r=r, g=g, b=b, a=a }
                ReloadAndUpdate(); UpdatePreview()
            end, true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local function UpdateAbsorbBarSwatchVis()
            swatch:SetAlpha(SValSupported("absorbBarPosition", "none") == "none" and 0.3 or 1)
        end
        RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
        UpdateAbsorbBarSwatchVis()
    end

    -- Row 4: Heal Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
    local healAbsorbBarRow
    healAbsorbBarRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Heal Absorb Bar",
          values={ none="None", aboveAbsorb="Above Absorb Bar", belowAbsorb="Below Absorb Bar", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", bottomRight="Bottom Right", bottomLeft="Bottom Left" },
          order={ "none", "aboveAbsorb", "belowAbsorb", "aboveRight", "aboveLeft", "topRight", "topLeft", "bottomRight", "bottomLeft" },
          getValue=function() return SValSupported("healAbsorbBarPosition", "none") end,
          setValue=function(v) SSetSupported("healAbsorbBarPosition", v); EllesmereUI:RefreshPage() end },
        { type="slider", text="Bar Height", min=1, max=20, step=1,
          disabled=function() return SValSupported("healAbsorbBarPosition", "none") == "none" end,
          disabledTooltip="Heal Absorb Bar",
          getValue=function() return SValSupported("healAbsorbBarHeight", 4) end,
          setValue=function(v) SSetSupported("healAbsorbBarHeight", v) end });  y = y - h
    SApplySupport(healAbsorbBarRow._leftRegion, "healAbsorbBarPosition")
    SApplySupport(healAbsorbBarRow._rightRegion, "healAbsorbBarHeight")
    if not EllesmereUI._prebuilding then
        local rgn = healAbsorbBarRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, healAbsorbBarRow:GetFrameLevel() + 3,
            function()
                local c = SGetSupported("healAbsorbBarColor")
                if c then return c.r, c.g, c.b, c.a or 1 end
                return 200/255, 29/255, 29/255, 1
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().healAbsorbBarColor = { r=r, g=g, b=b, a=a }
                ReloadAndUpdate(); UpdatePreview()
            end, true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local function UpdateHealAbsorbBarSwatchVis()
            swatch:SetAlpha(SValSupported("healAbsorbBarPosition", "none") == "none" and 0.3 or 1)
        end
        RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
        UpdateHealAbsorbBarSwatchVis()
    end

    -- Row 5: Heal Prediction (+ your / others' color swatches) | Prediction Opacity
    local healPredRow
    healPredRow, h = W:DualRow(parent, y,
        { type="toggle", text="Heal Prediction",
          tooltip="Shows incoming heals past the health bar: yours, then other players'.",
          getValue=function() return SValSupported("healPrediction", false) == true end,
          setValue=function(v) SSetSupported("healPrediction", v); EllesmereUI:RefreshPage() end },
        { type="slider", text="Prediction Opacity", min=5, max=100, step=1,
          disabled=function() return SValSupported("healPrediction", false) ~= true end,
          disabledTooltip="Heal Prediction",
          getValue=function() return SValSupported("healPredOpacity", 60) end,
          setValue=function(v) SSetSupported("healPredOpacity", v) end });  y = y - h
    SApplySupport(healPredRow._leftRegion, "healPrediction")
    SApplySupport(healPredRow._rightRegion, "healPredOpacity")
    -- Inline eyeball: preview heal prediction on the live preview. Session-only.
    if not EllesmereUI._prebuilding then
        local rgn = healPredRow._leftRegion
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        rgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshPredEye()
            eyeTex:SetTexture(ns._ufShowHealPredPreview and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
        end
        RefreshPredEye()
        eyeBtn:SetScript("OnClick", function()
            ns._ufShowHealPredPreview = not ns._ufShowHealPredPreview
            RefreshPredEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._ufShowHealPredPreview and "Hide heal prediction preview" or "Show heal prediction preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end
    if not EllesmereUI._prebuilding then
        local rgn = healPredRow._leftRegion
        local function PredSwatch(key, default, tip)
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healPredRow:GetFrameLevel() + 3,
                function()
                    local c = SGetSupported(key) or default
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    UNIT_DB_MAP[optState.selectedUnit]()[key] = { r=r, g=g, b=b }
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            swatch:HookScript("OnEnter", function(sw) EllesmereUI.ShowWidgetTooltip(sw, tip) end)
            swatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateVis()
                swatch:SetAlpha(SValSupported("healPrediction", false) == true and 1 or 0.3)
            end
            RegisterWidgetRefresh(UpdateVis)
            UpdateVis()
        end
        -- Each swatch lands left of the last, so build others' first: reads yours, others'.
        PredSwatch("healPredOtherColor", ns.UF_HEAL_PRED_OTHER or { r = 40/255, g = 170/255, b = 40/255 }, "Other players' heals")
        PredSwatch("healPredColor", ns.UF_HEAL_PRED_MY or { r = 102/255, g = 243/255, b = 102/255 }, "Your heals")
    end
    -- Row 6: Overheal (how far heal prediction may run past the bar's end) | Texture
    -- (Health Bar follows the frame's own health texture; no absorb stripes:
    -- stripes read as absorbs on these frames).
    local healPredTexValues = { health = "Health Bar", flat = "Flat" }
    local healPredTexOrder = { "health", "flat", "---" }
    for _, k in ipairs(ns.healthBarTextureOrder or {}) do
        if k ~= "none" and k ~= "---" and not healPredTexValues[k] then
            healPredTexValues[k] = (ns.healthBarTextureNames and ns.healthBarTextureNames[k]) or k
            healPredTexOrder[#healPredTexOrder + 1] = k
        end
    end
    healPredTexValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" or key == "health" then return nil end
            if key == "flat" then return "Interface\\Buttons\\WHITE8X8" end
            return EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, nil)
        end,
    }
    local overhealRow
    overhealRow, h = W:DualRow(parent, y,
        { type="slider", text="Overheal", min=0, max=50, step=1,
          tooltip="How far incoming heals can extend past the end of the health bar, as a percent of its length. 0 keeps them inside the bar.",
          disabled=function() return SValSupported("healPrediction", false) ~= true end,
          disabledTooltip="Heal Prediction",
          getValue=function() return SValSupported("healPredOverheal", 0) end,
          setValue=function(v) SSetSupported("healPredOverheal", v) end },
        { type="dropdown", text="Heal Prediction Texture", values=healPredTexValues, order=healPredTexOrder,
          disabled=function() return SValSupported("healPrediction", false) ~= true end,
          disabledTooltip="Heal Prediction",
          getValue=function() return SValSupported("healPredTexture", "health") end,
          setValue=function(v) SSetSupported("healPredTexture", v); UpdatePreview() end });  y = y - h
    SApplySupport(overhealRow._leftRegion, "healPredOverheal")
    SApplySupport(overhealRow._rightRegion, "healPredTexture")

    _, h = W:Spacer(parent, y, 20); y = y - h
    end -- _supportsAbsorbs

    return y, sharedAbsorbsHeader, absorbRow, healAbsorbRow
end
