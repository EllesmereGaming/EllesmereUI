if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedCastAuras_Options.lua
--  Unit Frames options: Cast Bar and Buffs and Debuffs sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
--  EUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end  -- module disabled: no options page

function ns.UFO_BuildCastBarSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, PP, RegisterWidgetRefresh, ReloadAndUpdate = env.GROUP_UNIT_ORDER, env.PP, env.RegisterWidgetRefresh, env.ReloadAndUpdate
    local SHORT_LABELS, UF_ImpCastGlowDesc, UNIT_DB_MAP, UpdatePreview = env.SHORT_LABELS, env.UF_ImpCastGlowDesc, env.UNIT_DB_MAP, env.UpdatePreview
    local db, optState = env.db, env.optState
    local W, SGetSupported, SSetSupported, SVal = ctx.W, ctx.SGetSupported, ctx.SSetSupported, ctx.SVal
    local SValSupported = ctx.SValSupported
    local h

    -------------------------------------------------------------------
    --  CAST BAR
    -------------------------------------------------------------------
    local sharedCastHeader
    sharedCastHeader, h = W:SectionHeader(parent, "CAST BAR", y); y = y - h

    -- Helper: get/set castbar visibility per unit
    local function GetCastbarEnabled(unitKey)
        if unitKey == "player" then
            return UNIT_DB_MAP.player().showPlayerCastbar or false
        else
            return UNIT_DB_MAP[unitKey]().showCastbar ~= false
        end
    end
    local function SetCastbarEnabled(unitKey, val)
        if unitKey == "player" then
            UNIT_DB_MAP.player().showPlayerCastbar = val
        else
            UNIT_DB_MAP[unitKey]().showCastbar = val
        end
    end

    -- Height getter/setter: player -> playerCastbarHeight, target/focus -> castbarHeight
    local function GetCastbarHeight()
        local u = optState.selectedUnit
        if u == "player" then
            local v = UNIT_DB_MAP.player().playerCastbarHeight or 0
            return (v <= 0) and 14 or v
        else
            return UNIT_DB_MAP[u]().castbarHeight or 14
        end
    end
    local function SetCastbarHeight(v)
        if optState.selectedUnit == "player" then UNIT_DB_MAP.player().playerCastbarHeight = v
        else UNIT_DB_MAP[optState.selectedUnit]().castbarHeight = v end
    end

    -- Player-only hint: this is the compact mini cast bar under the player frame;
    -- the full-size one belongs to Resource & Cast Bars, deep-linked here. The page
    -- fully rebuilds on unit change, so gating on selectedUnit re-evaluates per unit.
    if optState.selectedUnit == "player" then
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        ar, ag, ab = ar or 12/255, ag or 210/255, ab or 157/255
        local accentHex = EllesmereUI.HexColor(ar, ag, ab)
        local hintText = EllesmereUI.Lf("For player frame, this provides a simple, mini castbar below player frame. To edit the main player cast bar, %sclick here|r", accentHex)
        -- Full-width label (nil right slot expands the left region) renders text
        -- through the panel's own widget path; a transparent button over the row
        -- click-throughs to Resource & Cast Bars > Cast Bar (accent "click here").
        local hintRow
        hintRow, h = W:DualRow(parent, y, { type = "label", text = hintText }, nil)  -- eui-style: allow dualrow-nil
        -- Labels are single-line by default; wrap this hint inside the full-width
        -- row so "click here" stays on screen.
        local lbl = hintRow._leftRegion and hintRow._leftRegion._label
        if lbl then
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(true)
            local rw = hintRow._leftRegion:GetWidth()
            if not rw or rw < 80 then rw = 300 end
            lbl:SetWidth(rw - 40)
        end
        if not EllesmereUI._prebuilding then
        local clickRgn = hintRow._leftRegion or hintRow
        local linkBtn = CreateFrame("Button", nil, clickRgn)
        linkBtn:SetAllPoints(clickRgn)
        linkBtn:SetFrameLevel(clickRgn:GetFrameLevel() + 5)
        linkBtn:SetScript("OnClick", function()
            EllesmereUI:NavigateToElementSettings("EllesmereUIResourceBars", "Cast Bar")
        end)
        linkBtn:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, "Open Resource & Cast Bars > Cast Bar")
        end)
        linkBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        y = y - h
    end

    -- Row 1: Show Cast Bar (toggle + fill swatch) | Height (slider). This row and
    -- the player hint stay visible while the cast bar is off; the rows below hide
    -- entirely. Height composes the castbar-off disable into the size-match guard.
    local sharedCastRow1
    local cbKey = optState.selectedUnit .. "Castbar"
    local cbhDis, cbhTip, cbhRaw = EllesmereUI.MatchGuard(cbKey, "Height",
        function() return not GetCastbarEnabled(optState.selectedUnit) end,
        "Show Cast Bar")
    sharedCastRow1, h = W:DualRow(parent, y,
        { type="toggle", text="Show Cast Bar",
          getValue=function() return GetCastbarEnabled(optState.selectedUnit) end,
          -- DependentSetValue: rows below Row 1 hide while the cast bar is off,
          -- so the toggle flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return GetCastbarEnabled(optState.selectedUnit) end,
              function(v) SetCastbarEnabled(optState.selectedUnit, v); ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage() end) },
        { type="slider", text="Height", min=1, max=40, step=1,
          disabled=cbhDis, disabledTooltip=cbhTip, rawTooltip=cbhRaw,
          getValue=GetCastbarHeight,
          setValue=function(v) SetCastbarHeight(v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    -- Inline cast color swatch(es) on Show Cast Bar
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedCastRow1._leftRegion
        local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
            local sw, updateSw = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
                function()
                    local c = SGetSupported(colorKey)
                    c = c or fallback
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    SSetSupported(colorKey, { r = r, g = g, b = b })
                    ReloadAndUpdate(); UpdatePreview()
                end, false, 20)
            PP.Point(sw, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            sw:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tooltip) end)
            sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            leftRgn._lastInline = sw
            -- Optional disabled gate: grey (0.3) + non-interactive when disabledFn
            -- is true; used by the default-off Interrupt Ready Mid-Cast swatch so
            -- it tracks its enable toggle in the cog.
            if disabledFn then
                local function applySwState()
                    local off = disabledFn()
                    sw:SetAlpha(off and 0.3 or 1)
                    sw:EnableMouse(not off)
                    if updateSw then updateSw() end
                end
                applySwState()
                EllesmereUI.RegisterWidgetRefresh(applySwState)
            end
        end
        if optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
            -- Inline swatches anchor right-to-left: Mid-Cast added first (rightmost),
            -- then CD, then Interruptible, matching Nameplates' left-to-right order.
            -- Mid-Cast greys unless its enable toggle in the cog is on.
            AddCastColorSwatch("Interrupt Ready Mid-Cast", "castbarInterruptMidCastColor", { r = 0.318, g = 0.820, b = 0.357 },
                function() return not SValSupported("castbarInterruptMidCastEnabled", false) end)
            AddCastColorSwatch("Interrupt on CD", "castbarInterruptReadyColor", { r = 0.92, g = 0.35, b = 0.20 })
            AddCastColorSwatch("Uninterruptible Cast", "castbarUninterruptibleColor", { r = 0.5, g = 0.5, b = 0.5 })
            AddCastColorSwatch("Interruptible Cast", "castbarFillColor", { r = 0.863, g = 0.820, b = 0.639 })
        else
            AddCastColorSwatch("Fill Color", "castbarFillColor", { r = 1, g = 0.7, b = 0 })
        end
    end
    -- Sync icon: Show Cast Bar + Fill Color (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedCastRow1._leftRegion
        local isKickUnit = optState.selectedUnit == "target" or optState.selectedUnit == "focus"
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = isKickUnit and "Apply Show Cast Bar and Cast Color to Target and Focus"
                or "Apply Show Cast Bar and Fill Color to all Frames",
            onClick = function()
                local v = GetCastbarEnabled(optState.selectedUnit)
                local c = UNIT_DB_MAP[optState.selectedUnit]().castbarFillColor
                local readyC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarInterruptReadyColor
                local unintC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarUninterruptibleColor
                local keys = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                for _, key in ipairs(keys) do
                    SetCastbarEnabled(key, v)
                    if c then UNIT_DB_MAP[key]().castbarFillColor = { r = c.r, g = c.g, b = c.b } end
                    if readyC then UNIT_DB_MAP[key]().castbarInterruptReadyColor = { r = readyC.r, g = readyC.g, b = readyC.b } end
                    if unintC then UNIT_DB_MAP[key]().castbarUninterruptibleColor = { r = unintC.r, g = unintC.g, b = unintC.b } end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = GetCastbarEnabled(optState.selectedUnit)
                local c = UNIT_DB_MAP[optState.selectedUnit]().castbarFillColor
                local readyC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarInterruptReadyColor
                local unintC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarUninterruptibleColor
                local keys = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                for _, key in ipairs(keys) do
                    if GetCastbarEnabled(key) ~= v then return false end
                    local kc = UNIT_DB_MAP[key]().castbarFillColor
                    if c and kc then
                        if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                    elseif c ~= kc then return false end
                    if isKickUnit then
                        local kr = UNIT_DB_MAP[key]().castbarInterruptReadyColor
                        if readyC and kr then
                            if kr.r ~= readyC.r or kr.g ~= readyC.g or kr.b ~= readyC.b then return false end
                        elseif readyC ~= kr then return false end
                        local ku = UNIT_DB_MAP[key]().castbarUninterruptibleColor
                        if unintC and ku then
                            if ku.r ~= unintC.r or ku.g ~= unintC.g or ku.b ~= unintC.b then return false end
                        elseif unintC ~= ku then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = GetCastbarEnabled(optState.selectedUnit)
                    local c = UNIT_DB_MAP[optState.selectedUnit]().castbarFillColor
                    local readyC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarInterruptReadyColor
                    local unintC = isKickUnit and UNIT_DB_MAP[optState.selectedUnit]().castbarUninterruptibleColor
                    for _, key in ipairs(checkedKeys) do
                        SetCastbarEnabled(key, v)
                        if c then UNIT_DB_MAP[key]().castbarFillColor = { r = c.r, g = c.g, b = c.b } end
                        if readyC and (key == "target" or key == "focus") then
                            UNIT_DB_MAP[key]().castbarInterruptReadyColor = { r = readyC.r, g = readyC.g, b = readyC.b }
                        end
                        if unintC and (key == "target" or key == "focus") then
                            UNIT_DB_MAP[key]().castbarUninterruptibleColor = { r = unintC.r, g = unintC.g, b = unintC.b }
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Inline cog on Show Cast Bar: Hide When Idle (all units) + kick-ready tick
    -- (target/focus only). Deliberately outside the Show Cast Bar sync icon:
    -- these are per-unit detail settings.
    if not EllesmereUI._prebuilding then
        local rgn = sharedCastRow1._leftRegion
        local cogRows = {
            { type = "toggle", label = "Hide When Idle",
              tooltip = "Only show the cast bar while a cast is in progress; hide it the rest of the time.",
              get = function()
                  local v = UNIT_DB_MAP[optState.selectedUnit]().castbarHideWhenInactive
                  if v == nil then return true end
                  return v
              end,
              set = function(v)
                  UNIT_DB_MAP[optState.selectedUnit]().castbarHideWhenInactive = v
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type = "slider", label = "Fill Opacity", min = 0, max = 100, step = 1,
              tooltip = "Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
              get = function() return UNIT_DB_MAP[optState.selectedUnit]().castFillOpacity or 100 end,
              set = function(v)
                  UNIT_DB_MAP[optState.selectedUnit]().castFillOpacity = v
                  ReloadAndUpdate(); UpdatePreview()
              end },
            -- Global (not per-frame, not synced): ONE db.profile key lifts every
            -- unit's cast bar to HIGH strata; off leaves them at the frame's
            -- strata. Default on.
            { type = "toggle", label = "Raise Cast Bar Strata (All)",
              tooltip = "Lifts player, target, focus, and boss cast bars above other frames so they are never hidden behind them.",
              get = function() return db.profile.raiseCastbarStrata ~= false end,
              set = function(v)
                  db.profile.raiseCastbarStrata = v
                  ReloadAndUpdate()
              end },
        }
        if optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
            cogRows[#cogRows + 1] = { type = "toggle", label = "Show Kick Ready Mid-Cast Tick",
                tooltip = "Shows a small white tick mark on the cast bar at the point where the cast will be when your interrupt comes off cooldown.",
                get = function()
                    local v = SGetSupported("castbarKickTickEnabled")
                    if v == nil then return true end
                    return v
                end,
                set = function(v)
                    SSetSupported("castbarKickTickEnabled", v)
                    ReloadAndUpdate(); UpdatePreview()
                end }
            cogRows[#cogRows + 1] = { type = "toggle", label = "Show Kick Ready Mid-Cast Bar",
                tooltip = "When your interrupt is on cooldown now but will be ready before the enemy cast finishes, color the part of the cast bar during which your interrupt will be available. The color clears the instant your interrupt comes off cooldown.",
                get = function()
                    local v = SGetSupported("castbarInterruptMidCastEnabled")
                    if v == nil then return false end
                    return v
                end,
                set = function(v)
                    SSetSupported("castbarInterruptMidCastEnabled", v)
                    ReloadAndUpdate(); UpdatePreview()
                    -- Refresh so the inline Mid-Cast swatch greys/ungreys at once;
                    -- the cog popup stays open.
                    EllesmereUI:RefreshPage()
                end }
        end
        -- Opt-in for the Border Style | Border Size rows (built below only
        -- while on; the rebuild shows or drops them).
        cogRows[#cogRows + 1] = { type = "toggle", label = "Custom Border Style",
            tooltip = "Show the border style and size controls for the cast bar.",
            disabled = function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
            disabledTooltip = function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
            requireState = "disabled",
            get = function() return UNIT_DB_MAP[optState.selectedUnit]().castBorderCustom == true end,
            set = function(v)
                UNIT_DB_MAP[optState.selectedUnit]().castBorderCustom = v
                ReloadAndUpdate()
                EllesmereUI.ReapplyMatchPads(optState.selectedUnit .. "Castbar")
                EllesmereUI:RefreshPage(true)
            end }
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Cast Bar",
            rows = cogRows,
        })
    end
    -- Sync icon: Cast Bar Height (right region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedCastRow1._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Cast Bar Height to all Frames",
            onClick = function()
                local v = GetCastbarHeight()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key == "player" then UNIT_DB_MAP[key]().playerCastbarHeight = v
                    else UNIT_DB_MAP[key]().castbarHeight = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = GetCastbarHeight()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local kv
                    if key == "player" then kv = UNIT_DB_MAP[key]().playerCastbarHeight or 20
                    else kv = UNIT_DB_MAP[key]().castbarHeight or 20 end
                    if kv ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = GetCastbarHeight()
                    for _, key in ipairs(checkedKeys) do
                        if key == "player" then UNIT_DB_MAP[key]().playerCastbarHeight = v
                        else UNIT_DB_MAP[key]().castbarHeight = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Rows 2-4 are HIDDEN while Show Cast Bar is off (DependentSetValue rebuilds
    -- on flips). Row locals are hoisted above the gate: the element-nav map
    -- references them, and an in-gate declaration would leave it reading nil globals.
    local castRow2, castTextRow, castTargetRow
    if GetCastbarEnabled(optState.selectedUnit) then
    -- Row 2: Show Icon | Bar Background (opacity slider + inline color swatch)
    local function GetShowIcon()
        if optState.selectedUnit == "player" then
            local v = UNIT_DB_MAP.player().showPlayerCastIcon
            if v == nil then return true end
            return v
        else
            local v = UNIT_DB_MAP[optState.selectedUnit]().showCastIcon
            if v == nil then return true end
            return v
        end
    end
    local function SetShowIcon(val)
        if optState.selectedUnit == "player" then
            UNIT_DB_MAP.player().showPlayerCastIcon = val
        else
            UNIT_DB_MAP[optState.selectedUnit]().showCastIcon = val
        end
    end
    castRow2, h = W:DualRow(parent, y,
        { type="toggle", text="Show Icon",
          getValue=GetShowIcon,
          setValue=function(v) SetShowIcon(v); ReloadAndUpdate(); UpdatePreview() end },
        { type="slider", text="Bar Background", min=0, max=100, step=1,
          getValue=function() return math.floor(SValSupported("castBgAlpha", 0.5) * 100 + 0.5) end,
          setValue=function(v) UNIT_DB_MAP[optState.selectedUnit]().castBgAlpha = v / 100; ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    -- Sync icon: Show Icon (left)
    if not EllesmereUI._prebuilding then
        local rgn = castRow2._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Show Icon to all Frames",
            onClick = function()
                local v = GetShowIcon()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key == "player" then UNIT_DB_MAP[key]().showPlayerCastIcon = v
                    else UNIT_DB_MAP[key]().showCastIcon = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = GetShowIcon()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local kv
                    if key == "player" then
                        kv = UNIT_DB_MAP[key]().showPlayerCastIcon
                        if kv == nil then kv = true end
                    else
                        kv = UNIT_DB_MAP[key]().showCastIcon
                        if kv == nil then kv = true end
                    end
                    if kv ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = GetShowIcon()
                    for _, key in ipairs(checkedKeys) do
                        if key == "player" then UNIT_DB_MAP[key]().showPlayerCastIcon = v
                        else UNIT_DB_MAP[key]().showCastIcon = v end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Inline cog on Show Icon: "Icon Border", "Make Icon Part of the Bar",
    -- "Border Wraps Icon", "Vertical Separator", "Show Icon on Right",
    -- "Show Icon on Portrait", additive Offset X/Y nudges. Operates on the
    -- selected unit. An icon on the portrait greys the bar-side placement rows.
    if not EllesmereUI._prebuilding then
        local rgn = castRow2._leftRegion
        local function IconOnPortrait()
            return ns.UF_CastIconOnPortrait(optState.selectedUnit, UNIT_DB_MAP[optState.selectedUnit]())
        end
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Cast Icon",
            rows = {
                { type = "toggle", label = "Icon Border",
                  tooltip = "Use the cast bar's border style, size and color around the icon.",
                  disabled = function() return EllesmereUI.BlizzStyle.Get("unitframes") or not GetShowIcon() or IconOnPortrait() end,
                  disabledTooltip = "This option requires Show Icon beside the cast bar and the EllesmereUI style.",
                  get = function() return UNIT_DB_MAP[optState.selectedUnit]().castIconBorder == true end,
                  set = function(v)
                      UNIT_DB_MAP[optState.selectedUnit]().castIconBorder = v
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type = "toggle", label = "Make Icon Part of the Bar",
                  tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                  -- The stock styles count a shown icon as part of the bar
                  -- (their frame art wraps both), so the toggle reads on and locks.
                  disabled = function() return EllesmereUI.BlizzStyle.Get("unitframes") or IconOnPortrait() end,
                  disabledTooltip = function()
                      if EllesmereUI.BlizzStyle.Get("unitframes") then return EllesmereUI.BlizzStyle.Label("unitframes") end
                      return "Show Icon on Portrait"
                  end,
                  requireState = "disabled",
                  get = function()
                      if EllesmereUI.BlizzStyle.Get("unitframes") then return true end
                      if optState.selectedUnit == "player" then
                          return UNIT_DB_MAP.player().playerCastbarIconInWidth ~= false
                      end
                      return UNIT_DB_MAP[optState.selectedUnit]().castbarIconInWidth ~= false
                  end,
                  set = function(v)
                      if optState.selectedUnit == "player" then
                          UNIT_DB_MAP.player().playerCastbarIconInWidth = v
                      else
                          UNIT_DB_MAP[optState.selectedUnit]().castbarIconInWidth = v
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                -- Off: the custom border wraps the bar alone. The wrap
                -- also drops while the icon has an offset.
                { type = "toggle", label = "Border Wraps Icon",
                  tooltip = "Draw the custom cast bar border around the icon and the bar together. An icon with an offset keeps its own border.",
                  disabled = function()
                      local s = UNIT_DB_MAP[optState.selectedUnit]()
                      return EllesmereUI.BlizzStyle.Get("unitframes") or s.castBorderCustom ~= true
                          or not ns.UF_CastIconInWidth(optState.selectedUnit, s)
                  end,
                  disabledTooltip = "This option requires Custom Border Style, Show Icon and Make Icon Part of the Bar, with the EllesmereUI style.",
                  get = function() return UNIT_DB_MAP[optState.selectedUnit]().castBorderWrapIcon == true end,
                  set = function(v)
                      UNIT_DB_MAP[optState.selectedUnit]().castBorderWrapIcon = v
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI.ReapplyMatchPads(optState.selectedUnit .. "Castbar")
                  end },
                -- Solid draws a flat line; a textured style needs its own
                -- divider art (ns.UF_CastIconSeamOK, the runtime's gate).
                { type = "toggle", label = "Vertical Separator",
                  tooltip = "Draw a divider between the integrated icon and the bar, using the cast bar's border appearance.",
                  disabled = function()
                      local s = UNIT_DB_MAP[optState.selectedUnit]()
                      return EllesmereUI.BlizzStyle.Get("unitframes")
                          or not ns.UF_CastIconInWidth(optState.selectedUnit, s)
                          or not ns.UF_CastIconSeamOK(s)
                  end,
                  disabledTooltip = function()
                      local s = UNIT_DB_MAP[optState.selectedUnit]()
                      if EllesmereUI.BlizzStyle.Get("unitframes") or not ns.UF_CastIconInWidth(optState.selectedUnit, s) then
                          return "This option requires Show Icon and Make Icon Part of the Bar, with the EllesmereUI style."
                      end
                      return "This option requires Solid or a border style with divider art, and a Border Size above 0."
                  end,
                  get = function() return UNIT_DB_MAP[optState.selectedUnit]().castIconSeparator == true end,
                  set = function(v)
                      UNIT_DB_MAP[optState.selectedUnit]().castIconSeparator = v
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type = "toggle", label = "Show Icon on Right",
                  tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                  disabled = IconOnPortrait,
                  disabledTooltip = "Show Icon on Portrait",
                  requireState = "disabled",
                  get = function()
                      if optState.selectedUnit == "player" then
                          return UNIT_DB_MAP.player().playerCastbarIconRight == true
                      end
                      return UNIT_DB_MAP[optState.selectedUnit]().castbarIconRight == true
                  end,
                  set = function(v)
                      if optState.selectedUnit == "player" then
                          UNIT_DB_MAP.player().playerCastbarIconRight = v
                      else
                          UNIT_DB_MAP[optState.selectedUnit]().castbarIconRight = v
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                -- Needs a visible portrait and the icon shown; the stock
                -- styles own the icon.
                { type = "toggle", label = "Show Icon on Portrait",
                  tooltip = "Shows the spell icon over the portrait while casting and lets the bar use the full width.",
                  disabled = function()
                      if EllesmereUI.BlizzStyle.Get("unitframes") or not GetShowIcon() then return true end
                      local s = UNIT_DB_MAP[optState.selectedUnit]()
                      return (s.portraitStyle or db.profile.portraitStyle or "attached") == "none"
                          or s.showPortrait == false
                          or (s.portraitMode or db.profile.portraitMode or "2d") == "none"
                  end,
                  disabledTooltip = function()
                      if EllesmereUI.BlizzStyle.Get("unitframes") then return EllesmereUI.BlizzStyle.Label("unitframes") end
                      return "This option requires a visible Portrait and Show Icon."
                  end,
                  rawTooltip = function() return not EllesmereUI.BlizzStyle.Get("unitframes") end,
                  requireState = "disabled",
                  get = function()
                      if optState.selectedUnit == "player" then
                          return UNIT_DB_MAP.player().playerCastbarIconOnPortrait == true
                      end
                      return UNIT_DB_MAP[optState.selectedUnit]().castbarIconOnPortrait == true
                  end,
                  set = function(v)
                      if optState.selectedUnit == "player" then
                          UNIT_DB_MAP.player().playerCastbarIconOnPortrait = v
                      else
                          UNIT_DB_MAP[optState.selectedUnit]().castbarIconOnPortrait = v
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type = "slider", label = "Offset X", min = -50, max = 50, step = 1,
                  disabled = IconOnPortrait,
                  disabledTooltip = "Show Icon on Portrait",
                  requireState = "disabled",
                  get = function()
                      if optState.selectedUnit == "player" then
                          return UNIT_DB_MAP.player().playerCastIconOffsetX or 0
                      end
                      return UNIT_DB_MAP[optState.selectedUnit]().castIconOffsetX or 0
                  end,
                  set = function(v)
                      if optState.selectedUnit == "player" then
                          UNIT_DB_MAP.player().playerCastIconOffsetX = v
                      else
                          UNIT_DB_MAP[optState.selectedUnit]().castIconOffsetX = v
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type = "slider", label = "Offset Y", min = -50, max = 50, step = 1,
                  disabled = IconOnPortrait,
                  disabledTooltip = "Show Icon on Portrait",
                  requireState = "disabled",
                  get = function()
                      if optState.selectedUnit == "player" then
                          return UNIT_DB_MAP.player().playerCastIconOffsetY or 0
                      end
                      return UNIT_DB_MAP[optState.selectedUnit]().castIconOffsetY or 0
                  end,
                  set = function(v)
                      if optState.selectedUnit == "player" then
                          UNIT_DB_MAP.player().playerCastIconOffsetY = v
                      else
                          UNIT_DB_MAP[optState.selectedUnit]().castIconOffsetY = v
                      end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
            },
        })
    end
    -- Inline swatch on Bar Background; defaults to the cast bar's hardcoded black.
    if not EllesmereUI._prebuilding then
        local rgn = castRow2._rightRegion
        local bgSwGet = function()
            local c = UNIT_DB_MAP[optState.selectedUnit]().castBgColor
            if c then return c.r, c.g, c.b end
            return 0, 0, 0
        end
        local bgSwSet = function(r, g, b)
            UNIT_DB_MAP[optState.selectedUnit]().castBgColor = { r=r, g=g, b=b }
            ReloadAndUpdate(); UpdatePreview()
        end
        local bgSw, bgSwUpdate = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
        PP.Point(bgSw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgSw
        RegisterWidgetRefresh(function() bgSwUpdate() end)
    end
    -- Sync icon: Bar Background (right) -- background color + opacity
    if not EllesmereUI._prebuilding then
        local rgn = castRow2._rightRegion
        local function ApplyCastBgTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local bc = src.castBgColor or { r=0, g=0, b=0 }
            local bgA = src.castBgAlpha
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    local d = UNIT_DB_MAP[key]()
                    d.castBgColor = { r=bc.r, g=bc.g, b=bc.b }
                    d.castBgAlpha = bgA
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Background to all Frames",
            onClick = function() ApplyCastBgTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local function colEq(a, b)
                    -- A nil color means "use the hardcoded default (black)", so a
                    -- nil color and an explicit black must compare equal. Without
                    -- this the icon never reads as synced after Apply to All (the
                    -- source stays nil while the targets get an explicit black).
                    local ar, ag, ab = a and a.r or 0, a and a.g or 0, a and a.b or 0
                    local cr, cg, cb = b and b.r or 0, b and b.g or 0, b and b.b or 0
                    return ar == cr and ag == cg and ab == cb
                end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    if not colEq(d.castBgColor, src.castBgColor) then return false end
                    if (d.castBgAlpha or 0.5) ~= (src.castBgAlpha or 0.5) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyCastBgTo(checkedKeys) end,
            },
        })
    end

    -- Row 3: Spell Name (position dropdown + swatch + cog) | Duration (same). Cast
    -- text dropdowns mirror nameplates: Name/Target are None/Left/Right/Center and
    -- may not share a side (setting one bumps the other to None). Duration is
    -- None/Right/Left; "None" sets showCastDuration=false but still reserves a slot,
    -- pushing same-side text. Size/X/Y live in each row's cog. Defaults: Name Left, Target Right, Duration Right.
    local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
    local castTextPosOrder = { "none", "left", "right", "center" }
    castTextRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Spell Name", values=castTextPosValues, order=castTextPosOrder,
          getValue=function() return SValSupported("castSpellNameSide", "left") end,
          setValue=function(v)
            local s = UNIT_DB_MAP[optState.selectedUnit]()
            s.castSpellNameSide = v
            if v ~= "none" and (s.showCastTarget ~= false) and (s.castSpellTargetSide or "right") == v then
                s.showCastTarget = false
            end
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Duration",
          values={ none = "None", right = "Right", left = "Left" },
          order={ "none", "right", "left" },
          getValue=function()
            if SValSupported("showCastDuration", true) == false then return "none" end
            return SValSupported("castDurationSide", "right")
          end,
          setValue=function(v)
            local s = UNIT_DB_MAP[optState.selectedUnit]()
            if v == "none" then
                s.showCastDuration = false
            else
                s.showCastDuration = true
                s.castDurationSide = v
            end
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
          end });  y = y - h
    -- Inline color swatch on Spell Name Size
    if not EllesmereUI._prebuilding then
        local snRgn = castTextRow._leftRegion
        local snSw = EllesmereUI.BuildColorSwatch(snRgn, snRgn:GetFrameLevel() + 5,
            function()
                local c = SGetSupported("castSpellNameColor")
                c = c or { r=1, g=1, b=1 }
                return c.r, c.g, c.b, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().castSpellNameColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        snSw:SetPoint("RIGHT", snRgn._lastInline or snRgn._control, "LEFT", -12, 0)
        snRgn._lastInline = snSw
    end
    -- Inline cog on Spell Name Size: X/Y offsets (+ target/focus combine)
    if not EllesmereUI._prebuilding then
        local snCogRgn = castTextRow._leftRegion
        local snCogRows = {
                { type="slider", label="Size", min=6, max=20, step=1,
                  get=function() return SValSupported("castSpellNameSize", 11) end,
                  set=function(v) SSetSupported("castSpellNameSize", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castSpellNameX", 0) end,
                  set=function(v) SSetSupported("castSpellNameX", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castSpellNameY", 0) end,
                  set=function(v) SSetSupported("castSpellNameY", v); ReloadAndUpdate(); UpdatePreview() end },
        }
        if optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
            snCogRows[#snCogRows + 1] = { type="toggle", label="Combine Spell Name and Target",
                tooltip="Appends the cast target to the spell name (Spell Name - Target), class colored, and disables the separate Spell Target display.",
                get=function() return SValSupported("castCombineNameTarget", false) end,
                set=function(v)
                    SSetSupported("castCombineNameTarget", v)
                    ReloadAndUpdate(); UpdatePreview()
                    -- Grey/ungrey the Spell Name dropdown immediately.
                    EllesmereUI:RefreshPage()
                end }
        end
        EllesmereUI.BuildInlineCog(snCogRgn, {
            title = "Spell Name",
            rows = snCogRows,
        })
    end
    -- Inline color swatch on Duration Size
    if not EllesmereUI._prebuilding then
        local dtRgn = castTextRow._rightRegion
        local dtSw = EllesmereUI.BuildColorSwatch(dtRgn, dtRgn:GetFrameLevel() + 5,
            function()
                local c = SGetSupported("castDurationColor")
                c = c or { r=1, g=1, b=1 }
                return c.r, c.g, c.b, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().castDurationColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        dtSw:SetPoint("RIGHT", dtRgn._lastInline or dtRgn._control, "LEFT", -12, 0)
        dtRgn._lastInline = dtSw
    end
    -- Inline cog on Duration Size: toggle + X/Y offsets
    if not EllesmereUI._prebuilding then
        local dtCogRgn = castTextRow._rightRegion
        EllesmereUI.BuildInlineCog(dtCogRgn, {
            title = "Duration",
            rows = {
                { type="slider", label="Size", min=6, max=20, step=1,
                  get=function() return SValSupported("castDurationSize", 10) end,
                  set=function(v) SSetSupported("castDurationSize", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castDurationX", 0) end,
                  set=function(v) SSetSupported("castDurationX", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castDurationY", 0) end,
                  set=function(v) SSetSupported("castDurationY", v); ReloadAndUpdate(); UpdatePreview() end },
            },
        })
    end

    -- Sync icons: Spell Name Size + Color (left) and Duration Size + Color (right)
    if not EllesmereUI._prebuilding then
        local rgn = castTextRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Spell Name Size and Color to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameSize or 11
                local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    UNIT_DB_MAP[key]().castSpellNameSize = v
                    if c then UNIT_DB_MAP[key]().castSpellNameColor = { r=c.r, g=c.g, b=c.b } end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameSize or 11
                local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().castSpellNameSize or 11) ~= v then return false end
                    local kc = UNIT_DB_MAP[key]().castSpellNameColor
                    if c and kc then
                        if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                    elseif c ~= kc then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameSize or 11
                    local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellNameColor
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().castSpellNameSize = v
                        if c then UNIT_DB_MAP[key]().castSpellNameColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = castTextRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Duration Size and Color to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castDurationSize or 10
                local c = UNIT_DB_MAP[optState.selectedUnit]().castDurationColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    UNIT_DB_MAP[key]().castDurationSize = v
                    if c then UNIT_DB_MAP[key]().castDurationColor = { r=c.r, g=c.g, b=c.b } end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castDurationSize or 10
                local c = UNIT_DB_MAP[optState.selectedUnit]().castDurationColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().castDurationSize or 10) ~= v then return false end
                    local kc = UNIT_DB_MAP[key]().castDurationColor
                    if c and kc then
                        if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                    elseif c ~= kc then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().castDurationSize or 10
                    local c = UNIT_DB_MAP[optState.selectedUnit]().castDurationColor
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().castDurationSize = v
                        if c then UNIT_DB_MAP[key]().castDurationColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 4: Spell Target (position dropdown + swatch + cog) | Reverse Fill
    castTargetRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Spell Target", values=castTextPosValues, order=castTextPosOrder,
          -- Combine Spell Name and Target appends the target to the spell
          -- name string; the separate target display greys out and no-ops
          -- while it is on.
          disabled=function()
              if optState.selectedUnit ~= "target" and optState.selectedUnit ~= "focus" then return false end
              local s = UNIT_DB_MAP[optState.selectedUnit]()
              return (s and s.castCombineNameTarget == true) and true or false
          end,
          disabledTooltip="This option requires Combine Spell Name and Target to be disabled.",
          getValue=function()
            if SValSupported("showCastTarget", true) == false then return "none" end
            return SValSupported("castSpellTargetSide", "right")
          end,
          setValue=function(v)
            local s = UNIT_DB_MAP[optState.selectedUnit]()
            if v == "none" then
                s.showCastTarget = false
            else
                s.showCastTarget = true
                s.castSpellTargetSide = v
                if (s.castSpellNameSide or "left") == v then s.castSpellNameSide = "none" end
            end
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Reverse Fill",
          getValue=function() return SValSupported("castReverseFill", false) end,
          setValue=function(v) SSetSupported("castReverseFill", v); ReloadAndUpdate(); UpdatePreview() end });  y = y - h
    -- Inline color swatch on Spell Target Size
    if not EllesmereUI._prebuilding then
        local trgRgn = castTargetRow._leftRegion
        local trgSw = EllesmereUI.BuildColorSwatch(trgRgn, trgRgn:GetFrameLevel() + 5,
            function()
                local c = SGetSupported("castSpellTargetColor")
                c = c or { r=1, g=1, b=1 }
                return c.r, c.g, c.b, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        trgSw:SetPoint("RIGHT", trgRgn._lastInline or trgRgn._control, "LEFT", -12, 0)
        trgRgn._lastInline = trgSw
    end
    -- Inline cog on Spell Target Size: toggle + X/Y offsets
    if not EllesmereUI._prebuilding then
        local tgCogRgn = castTargetRow._leftRegion
        EllesmereUI.BuildInlineCog(tgCogRgn, {
            title = "Spell Target",
            rows = {
                { type="slider", label="Size", min=6, max=20, step=1,
                  get=function() return SValSupported("castSpellTargetSize", 10) end,
                  set=function(v) SSetSupported("castSpellTargetSize", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castSpellTargetX", 0) end,
                  set=function(v) SSetSupported("castSpellTargetX", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return SValSupported("castSpellTargetY", 0) end,
                  set=function(v) SSetSupported("castSpellTargetY", v); ReloadAndUpdate(); UpdatePreview() end },
            },
        })
    end

    -- Sync icons: Spell Target Size + Color (left)
    if not EllesmereUI._prebuilding then
        local rgn = castTargetRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Spell Target Size and Color to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetSize or 11
                local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    UNIT_DB_MAP[key]().castSpellTargetSize = v
                    if c then UNIT_DB_MAP[key]().castSpellTargetColor = { r=c.r, g=c.g, b=c.b } end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetSize or 11
                local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().castSpellTargetSize or 11) ~= v then return false end
                    local kc = UNIT_DB_MAP[key]().castSpellTargetColor
                    if c and kc then
                        if kc.r ~= c.r or kc.g ~= c.g or kc.b ~= c.b then return false end
                    elseif c ~= kc then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetSize or 11
                    local c = UNIT_DB_MAP[optState.selectedUnit]().castSpellTargetColor
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().castSpellTargetSize = v
                        if c then UNIT_DB_MAP[key]().castSpellTargetColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Custom Border Style rows (the Cast Bar cog's opt-in), inside the Show
    -- Cast Bar gate and ahead of the Classic-only Border Size row.
    if SVal("castBorderCustom", false) == true then
        y = y - ns.UF_CastBorderRows(W, parent, y,
            function() return UNIT_DB_MAP[optState.selectedUnit]() end,
            ReloadAndUpdate,
            optState.selectedUnit .. "Castbar",
            { units = GROUP_UNIT_ORDER, labels = SHORT_LABELS,
              current = function() return optState.selectedUnit end,
              db = function(u) local f = UNIT_DB_MAP[u]; return f and f() end })
    end
    -- Important Cast Glow (target/focus); in Classic WoW UI it fills the Border Size row's free slot.
    local impGlowCfg, impGlowDesc
    if optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
        impGlowDesc = UF_ImpCastGlowDesc(function() return UNIT_DB_MAP[optState.selectedUnit]() end,
            function() ReloadAndUpdate(); UpdatePreview() end)
        impGlowCfg = EllesmereUI.GlowOptions.DropdownSpec(impGlowDesc, "Important Cast Glow",
            "Show a glow on the cast bar when the unit is casting a spell Blizzard marks as important.")
    end
    -- Classic WoW UI: Border Size closes the section (odd last slot).
    local classicH, classicRow = ns.UF_ClassicCastBorderRow(W, parent, y,
        function() return UNIT_DB_MAP[optState.selectedUnit]() end,
        ns.UF_CastClassicKey(optState.selectedUnit),
        function() ReloadAndUpdate(); UpdatePreview() end,
        { units = GROUP_UNIT_ORDER, labels = SHORT_LABELS,
          current = function() return optState.selectedUnit end,
          db = function(u) local f = UNIT_DB_MAP[u]; return f and f() end,
          reload = ReloadAndUpdate },
        optState.selectedUnit .. "Castbar", impGlowCfg)
    y = y - classicH
    if impGlowCfg then
        local impGlowRow, impGlowSide = classicRow, "_rightRegion"
        if not impGlowRow then
            impGlowRow, h = W:DualRow(parent, y, impGlowCfg, { type="label", text="Glow Color" });  y = y - h
            impGlowSide = "_leftRegion"
        end
        if not EllesmereUI._prebuilding then
            local rgn = impGlowRow[impGlowSide]
            -- Color swatches (in the free right half when there is one), the
            -- Pixel Glow cog and a small preview.
            local GO = EllesmereUI.GlowOptions
            GO.AttachInline(rgn, impGlowDesc,
                impGlowSide == "_leftRegion" and impGlowRow._rightRegion or nil)
            local pv = GO.BuildPreview(rgn, impGlowDesc, { width = 40, height = 14,
                anchor = rgn._lastInline or rgn._control, x = -12 })
            if pv then
                pv:SetFrameLevel(rgn:GetFrameLevel() + 5)
                rgn._lastInline = pv
            end

            -- Sync icon: apply glow settings to the other kick unit (target <-> focus)
            local GLOW_KEYS = { "castbarImportantGlow", "castbarImportantGlowStyle",
                "castbarImportantGlowColorMode",
                "castbarImportantGlowLines", "castbarImportantGlowThickness",
                "castbarImportantGlowSpeed", "castbarImportantGlowBackground" }
            local GLOW_COLOR_KEYS = { "castbarImportantGlowColor", "castbarImportantGlowBackgroundColor" }
            local function colEq(a, b)
                if a and b then return a.r == b.r and a.g == b.g and a.b == b.b end
                return a == b
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Important Cast Glow to Target and Focus",
                onClick = function()
                    local src = UNIT_DB_MAP[optState.selectedUnit]()
                    for _, key in ipairs({ "target", "focus" }) do
                        if key ~= optState.selectedUnit then
                            local d = UNIT_DB_MAP[key]()
                            for _, k in ipairs(GLOW_KEYS) do d[k] = src[k] end
                            for _, k in ipairs(GLOW_COLOR_KEYS) do
                                local c = src[k]
                                d[k] = c and { r = c.r, g = c.g, b = c.b } or nil
                            end
                        end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local src = UNIT_DB_MAP[optState.selectedUnit]()
                    for _, key in ipairs({ "target", "focus" }) do
                        local d = UNIT_DB_MAP[key]()
                        for _, k in ipairs(GLOW_KEYS) do
                            if d[k] ~= src[k] then return false end
                        end
                        for _, k in ipairs(GLOW_COLOR_KEYS) do
                            if not colEq(d[k], src[k]) then return false end
                        end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
            })
        end
    end
    end   -- close Cast Bar hidden-while-disabled gate

    return y, sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow
end

function ns.UFO_BuildBuffsDebuffsSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local AttachDebuffModeWarn, DebuffModeDropdownCfg, GROUP_UNIT_ORDER, PP = env.AttachDebuffModeWarn, env.DebuffModeDropdownCfg, env.GROUP_UNIT_ORDER, env.PP
    local RegisterWidgetRefresh, ReloadAndUpdate, SHORT_LABELS, SwapAuraSlot = env.RegisterWidgetRefresh, env.ReloadAndUpdate, env.SHORT_LABELS, env.SwapAuraSlot
    local UF_PurgeGlowDesc, UNIT_DB_MAP, UNIT_LABELS_SUP, UpdatePreview = env.UF_PurgeGlowDesc, env.UNIT_DB_MAP, env.UNIT_LABELS_SUP, env.UpdatePreview
    local buffAnchorOrder, buffAnchorValues, buffGrowthOrder, buffGrowthValues = env.buffAnchorOrder, env.buffAnchorValues, env.buffGrowthOrder, env.buffGrowthValues
    local db, frames, optState = env.db, env.frames, env.optState
    local W, SApplySupport, SDB, SGet = ctx.W, ctx.SApplySupport, ctx.SDB, ctx.SGet
    local SSetSupported, SVal, SValSupported = ctx.SSetSupported, ctx.SVal, ctx.SValSupported
    local _, h

    local sharedBuffDebuffHeader
    -------------------------------------------------------------------
    --  BUFFS AND DEBUFFS
    -------------------------------------------------------------------
    sharedBuffDebuffHeader, h = W:SectionHeader(parent, "BUFFS AND DEBUFFS", y); y = y - h

    -- When Buff/Debuff Display is "none", everything in that column is disabled.
    local function BuffDisabled()
        local s = UNIT_DB_MAP[optState.selectedUnit]()
        if not s then return false end
        -- Anchor Buffs with Debuffs renders buffs inside the debuff stack, so
        -- buff appearance settings stay live while Buff Display reads None (visibility belongs to the merge toggle).
        if s.debuffAnchorBuffs and SValSupported("debuffAnchor", "bottomleft") ~= "none" then
            return false
        end
        return s.showBuffs == false
    end
    local function DebuffDisabled()
        return SValSupported("debuffAnchor", "bottomleft") == "none"
    end

    -- Buff Display gains "Anchor to Debuffs" -- a pure VIEW over the same stored
    -- keys the merge always used (debuffAnchorBuffs=true + showBuffs=false), so old
    -- cog-toggle profiles read back identically. Shared anchor tables serve three other dropdowns, hence the per-site copy.
    local buffDispValues = { ["anchor_debuffs"] = "Anchor to Debuffs" }
    for k, v in pairs(buffAnchorValues) do buffDispValues[k] = v end
    local buffDispOrder = {}
    for i = 1, #buffAnchorOrder do buffDispOrder[i] = buffAnchorOrder[i] end
    buffDispOrder[#buffDispOrder + 1] = "anchor_debuffs"
    buffDispValues._menuOpts = {
        onItemHover = function(key, item)
            if key == "anchor_debuffs" and item then
                EllesmereUI.ShowWidgetTooltip(item, "Buffs join the debuff stack as its first rows; debuffs continue on the next row and move as buff rows change.")
            end
        end,
        onItemLeave = function(key)
            if key == "anchor_debuffs" then EllesmereUI.HideWidgetTooltip() end
        end,
    }

    -- Buffs: Location | Icon Size + inline directions cog (X/Y)
    local sharedAddRow2
    sharedAddRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Buff Display", values=buffDispValues, order=buffDispOrder,
          itemDisabled=function(v)
              return v == "anchor_debuffs" and DebuffDisabled()
          end,
          itemDisabledTooltip=function(v)
              if v == "anchor_debuffs" then return "Requires a Debuff Display" end
          end,
          getValue=function()
              local s = UNIT_DB_MAP[optState.selectedUnit]()
              -- Active merge presents as its own display choice; an inert merge
              -- (Debuff Display None) falls through to the truthful None readout.
              if s.debuffAnchorBuffs and SValSupported("debuffAnchor", "bottomleft") ~= "none" then
                  return "anchor_debuffs"
              end
              if s.showBuffs == false then return "none" end
              return SValSupported("buffAnchor", "topleft")
          end,
          -- DependentSetValue: the Buff Duration/Stack row (and, together
          -- with Debuff Display, the filter row) hides while None; only
          -- the None <-> shown flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return not BuffDisabled() end,
              function(v)
                  local s = UNIT_DB_MAP[optState.selectedUnit]()
                  if v == "anchor_debuffs" then
                      -- Same stored shape the old cog toggle wrote: the
                      -- merge owns visibility, Buff Display stores None.
                      s.debuffAnchorBuffs = true
                      s.showBuffs = false
                  elseif v == "none" then
                      s.showBuffs = false
                      s.debuffAnchorBuffs = nil
                  else
                      s.showBuffs = true
                      SwapAuraSlot(s, "buffAnchor", v)
                      -- Choosing a standalone Buff Display exits the
                      -- merged mode (which forces this dropdown to None).
                      s.debuffAnchorBuffs = nil
                  end
                  ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
              end) },
        { type="slider", text="Buff Size", min=10, max=70, step=1,
          disabled=BuffDisabled, disabledTooltip="Buff Display",
          getValue=function() return SValSupported("buffSize", 22) end,
          setValue=function(v) SSetSupported("buffSize", v) end });  y = y - h
    SApplySupport(sharedAddRow2._leftRegion, "showBuffs")
    -- Sync icon: Buffs Location (left)
    if not EllesmereUI._prebuilding then
        local rgn = sharedAddRow2._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Buffs Location to all Frames",
            onClick = function()
                local s = UNIT_DB_MAP[optState.selectedUnit]()
                local showV = s.showBuffs
                if showV == nil then showV = true end
                local anchorV = s.buffAnchor or "topleft"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    UNIT_DB_MAP[key]().showBuffs = showV
                    if showV then UNIT_DB_MAP[key]().buffAnchor = anchorV end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local s = UNIT_DB_MAP[optState.selectedUnit]()
                local showV = s.showBuffs
                if showV == nil then showV = true end
                local anchorV = s.buffAnchor or "topleft"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local os = UNIT_DB_MAP[key]()
                    local ov = os.showBuffs; if ov == nil then ov = true end
                    if ov ~= showV then return false end
                    if showV and (os.buffAnchor or "topleft") ~= anchorV then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local s = UNIT_DB_MAP[optState.selectedUnit]()
                    local showV = s.showBuffs
                    if showV == nil then showV = true end
                    local anchorV = s.buffAnchor or "topleft"
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().showBuffs = showV
                        if showV then UNIT_DB_MAP[key]().buffAnchor = anchorV end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Cog on Buffs Location (Growth + Max Count)
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedAddRow2._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, { disabled = BuffDisabled, disabledTooltip = "Buff Display",
            title = "Buff Settings",
            rows = {
                { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                  get=function() return SValSupported("buffGrowth", "auto") end,
                  set=function(v) SSetSupported("buffGrowth", v) end },
                { type="slider", label="Max Count", min=1, max=40, step=1,
                  get=function() return SValSupported("maxBuffs", 4) end,
                  set=function(v) SSetSupported("maxBuffs", v) end },
                { type="slider", label="Max Per Row", min=1, max=40, step=1,
                  get=function() return SValSupported("buffMaxPerRow", nil) or SValSupported("maxBuffs", 4) end,
                  set=function(v) SSetSupported("buffMaxPerRow", v) end },
                { type="toggle", label="Cropped Icons",
                  get=function() return SValSupported("buffCropIcons", false) end,
                  set=function(v) SSetSupported("buffCropIcons", v) end },
                { type="slider", label="Icon Zoom", min=0, max=0.20, step=0.01,
                  -- The stock styles draw the whole icon (zoom 0); the active
                  -- style's name is the requirement noun the widget wraps.
                  disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
                  requireState="disabled",
                  get=function() return SValSupported("buffIconZoom", 0.07) end,
                  set=function(v) SSetSupported("buffIconZoom", v) end },
                { type="toggle", label="Dispel Type Borders",
                  disabled=function() return optState.selectedUnit == "player" or EllesmereUI.BlizzStyle.Get("unitframes") end,
                  disabledTooltip=function()
                      if optState.selectedUnit == "player" then return "This option is not available on the player frame" end
                      return "This option requires Blizzard Style to be disabled"
                  end,
                  get=function() return optState.selectedUnit ~= "player" and SValSupported("buffDispelBorder", false) == true end,
                  set=function(v) SSetSupported("buffDispelBorder", v) end },
            },
        })
    end
    -- Directions cog on Buff Icon Size (X/Y offsets)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedAddRow2._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = BuffDisabled, disabledTooltip = "Buff Display",
            title = "Buff Position",
            rows = {
                { type="slider", label="Offset X", min=-1500, max=1500, step=1,
                  get=function() return SValSupported("buffOffsetX", 0) end,
                  set=function(v) SSetSupported("buffOffsetX", v) end },
                { type="slider", label="Offset Y", min=-1500, max=1500, step=1,
                  get=function() return SValSupported("buffOffsetY", 0) end,
                  set=function(v) SSetSupported("buffOffsetY", v) end },
                -- Physical-pixel-perfect gaps between buff icons (X = columns, Y = rows).
                { type="slider", pixel=true, label="Spacing X", min=-1, max=10, step=1,
                  get=function() return SValSupported("buffSpacingX", 1) end,
                  set=function(v) SSetSupported("buffSpacingX", v) end },
                { type="slider", pixel=true, label="Spacing Y", min=-1, max=10, step=1,
                  get=function() return SValSupported("buffSpacingY", 1) end,
                  set=function(v) SSetSupported("buffSpacingY", v) end },
            },
        })
    end

    -- Buffs row 2: Duration Text Size | Stack Size. HIDDEN while Buff Display is
    -- None (DependentSetValue rebuilds). Duration Size is gated by an inline
    -- "Show Cooldown Text" toggle; off disables the slider/cog/label.
    if not BuffDisabled() then
    local buffDurOff = function() return BuffDisabled() or not SValSupported("buffShowCooldownText", false) end
    local buffDurTip = function() return BuffDisabled() and "Buff Display" or "Show Cooldown Text" end
    local sharedBuffRow2
    sharedBuffRow2, h = W:DualRow(parent, y,
        { type="slider", text="Buff Duration Size", min=6, max=100, step=1, trackWidth=120,
          disabled=buffDurOff, disabledTooltip=buffDurTip,
          getValue=function() return SValSupported("buffCooldownTextSize", 10) end,
          setValue=function(v) SSetSupported("buffCooldownTextSize", v) end },
        { type="slider", text="Buff Stack Size", min=6, max=100, step=1,
          disabled=BuffDisabled, disabledTooltip="Buff Display",
          getValue=function() return SValSupported("buffStackTextSize", 14) end,
          setValue=function(v) SSetSupported("buffStackTextSize", v) end });  y = y - h
    -- Directions cog on Buff Duration Size (X/Y offsets) -- disabled with the row
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedBuffRow2._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = buffDurOff, disabledTooltip = buffDurTip,
            title = "Duration Text",
            rows = {
                { type="slider", label="Offset X", min=-100, max=100, step=1,
                  get=function() return SValSupported("buffCooldownTextOffsetX", 0) end,
                  set=function(v) SSetSupported("buffCooldownTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-100, max=100, step=1,
                  get=function() return SValSupported("buffCooldownTextOffsetY", 0) end,
                  set=function(v) SSetSupported("buffCooldownTextOffsetY", v) end },
                { type="slider", label="Precise Below (minutes, 0 = off)", min=0, max=60, step=1,
                  get=function() local v=SValSupported("buffCooldownTextPrecision", nil); return v and v/60 or 0 end,
                  set=function(v) SSetSupported("buffCooldownTextPrecision", v > 0 and v*60 or nil) end },
            },
        })
    end
    -- Inline "Show Cooldown Text" toggle on Buff Duration Size (always enabled)
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildInlineToggle({
        region   = sharedBuffRow2._leftRegion,
        getValue = function() return SValSupported("buffShowCooldownText", false) end,
        setValue = function(v) SSetSupported("buffShowCooldownText", v) end,
        onToggle = function() EllesmereUI:RefreshPage() end,
    })
    end
    -- Directions cog on Buff Stack Size (X/Y offsets)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedBuffRow2._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = BuffDisabled, disabledTooltip = "Buff Display",
            title = "Stack Position",
            rows = {
                { type="dropdown", label="Position",
                  values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                  order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                  get=function() return SValSupported("buffStackTextPosition", "bottomright") end,
                  set=function(v) SSetSupported("buffStackTextPosition", v) end },
                { type="slider", label="Offset X", min=-100, max=100, step=1,
                  get=function() return SValSupported("buffStackTextOffsetX", 0) end,
                  set=function(v) SSetSupported("buffStackTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-100, max=100, step=1,
                  get=function() return SValSupported("buffStackTextOffsetY", 0) end,
                  set=function(v) SSetSupported("buffStackTextOffsetY", v) end },
            },
        })
    end
    end   -- close Buff row 2 hidden-while-None gate

    -- Debuffs: Location | Icon Size + inline directions cog (X/Y)
    local sharedAddRow3
    sharedAddRow3, h = W:DualRow(parent, y,
        { type="dropdown", text="Debuff Display", values=buffAnchorValues, order=buffAnchorOrder,
          getValue=function()
              return SValSupported("debuffAnchor", "bottomleft")
          end,
          -- DependentSetValue: the Debuff Duration/Stack row (and, together
          -- with Buff Display, the filter row) hides while None; only the
          -- None <-> shown flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return not DebuffDisabled() end,
              function(v)
                  SwapAuraSlot(UNIT_DB_MAP[optState.selectedUnit](), "debuffAnchor", v)
                  ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
              end) },
        { type="slider", text="Debuff Size", min=10, max=70, step=1,
          disabled=DebuffDisabled, disabledTooltip="Debuff Display",
          getValue=function() return SValSupported("debuffSize", 22) end,
          setValue=function(v) SSetSupported("debuffSize", v) end });  y = y - h
    -- Cog on Debuffs Location (Growth + Max Count)
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedAddRow3._leftRegion
        local debuffCogRows = {
                { type="dropdown", label="Growth Direction", values=buffGrowthValues, order=buffGrowthOrder,
                  get=function() return SValSupported("debuffGrowth", "auto") end,
                  set=function(v) SSetSupported("debuffGrowth", v) end },
                { type="slider", label="Max Count", min=1, max=20, step=1,
                  get=function() return SValSupported("maxDebuffs", 20) end,
                  set=function(v) SSetSupported("maxDebuffs", v) end },
                { type="slider", label="Max Per Row", min=1, max=20, step=1,
                  get=function() return SValSupported("debuffMaxPerRow", nil) or SValSupported("maxDebuffs", 20) end,
                  set=function(v) SSetSupported("debuffMaxPerRow", v) end },
                { type="toggle", label="Cropped Icons",
                  get=function() return SValSupported("debuffCropIcons", false) end,
                  set=function(v) SSetSupported("debuffCropIcons", v) end },
                { type="slider", label="Icon Zoom", min=0, max=0.20, step=0.01,
                  -- The stock styles draw the whole icon (zoom 0); the active
                  -- style's name is the requirement noun the widget wraps.
                  disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
                  requireState="disabled",
                  get=function() return SValSupported("debuffIconZoom", 0.07) end,
                  set=function(v) SSetSupported("debuffIconZoom", v) end },
                { type="toggle", label="Dispel Type Borders",
                  -- The stock styles always paint the stock per-type border.
                  disabled=function() return EllesmereUI.BlizzStyle.Get("unitframes") end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("unitframes") end,
                  requireState="disabled",
                  get=function() return SValSupported("debuffDispelBorder", false) end,
                  set=function(v) SSetSupported("debuffDispelBorder", v) end },
        }
        -- Player only: the Dispel Colors palette (the Dispel Overlay row's
        -- swatches) tints the player's dispel type borders.
        if optState.selectedUnit == "player" then
            debuffCogRows[#debuffCogRows + 1] = { type="toggle", label="Use Dispel Colors",
                tooltip="Colors the dispel type borders with your Dispel Colors instead of Blizzard's.",
                disabled=function()
                    return EllesmereUI.BlizzStyle.Get("unitframes")
                        or SValSupported("debuffDispelBorder", false) ~= true
                end,
                disabledTooltip=function()
                    if EllesmereUI.BlizzStyle.Get("unitframes") then
                        return EllesmereUI.BlizzStyle.Label("unitframes")
                    end
                    return "This option requires Dispel Type Borders to be enabled."
                end,
                requireState="disabled",
                get=function() return SValSupported("debuffDispelUsePalette", false) == true end,
                -- RefreshPage (fast path) so the Dispel Colors swatches track it.
                set=function(v) SSetSupported("debuffDispelUsePalette", v); EllesmereUI:RefreshPage() end }
        end
        EllesmereUI.BuildInlineCog(leftRgn, { disabled = DebuffDisabled, disabledTooltip = "Debuff Display",
            title = "Debuff Settings",
            rows = debuffCogRows,
        })
    end
    -- Directions cog on Debuff Icon Size (X/Y offsets)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedAddRow3._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = DebuffDisabled, disabledTooltip = "Debuff Display",
            title = "Debuff Position",
            rows = {
                { type="slider", label="Offset X", min=-1500, max=1500, step=1,
                  get=function() return SValSupported("debuffOffsetX", 0) end,
                  set=function(v) SSetSupported("debuffOffsetX", v) end },
                { type="slider", label="Offset Y", min=-1500, max=1500, step=1,
                  get=function() return SValSupported("debuffOffsetY", 0) end,
                  set=function(v) SSetSupported("debuffOffsetY", v) end },
                -- Physical-pixel-perfect gaps between debuff icons (X = columns, Y = rows).
                { type="slider", pixel=true, label="Spacing X", min=-1, max=10, step=1,
                  get=function() return SValSupported("debuffSpacingX", 1) end,
                  set=function(v) SSetSupported("debuffSpacingX", v) end },
                { type="slider", pixel=true, label="Spacing Y", min=-1, max=10, step=1,
                  get=function() return SValSupported("debuffSpacingY", 1) end,
                  set=function(v) SSetSupported("debuffSpacingY", v) end },
            },
        })
    end

    -- Debuffs row 2: Duration Text Size | Stack Size. HIDDEN while Debuff Display
    -- is None (DependentSetValue rebuilds). Duration Size is gated by an inline
    -- "Show Cooldown Text" toggle; off disables the slider/cog/label.
    if not DebuffDisabled() then
    local debuffDurOff = function() return DebuffDisabled() or not SValSupported("debuffShowCooldownText", false) end
    local debuffDurTip = function() return DebuffDisabled() and "Debuff Display" or "Show Cooldown Text" end
    local sharedDebuffRow2
    sharedDebuffRow2, h = W:DualRow(parent, y,
        { type="slider", text="Debuff Duration Size", min=6, max=100, step=1, trackWidth=120,
          disabled=debuffDurOff, disabledTooltip=debuffDurTip,
          getValue=function() return SValSupported("debuffCooldownTextSize", 10) end,
          setValue=function(v) SSetSupported("debuffCooldownTextSize", v) end },
        { type="slider", text="Debuff Stack Size", min=6, max=100, step=1,
          disabled=DebuffDisabled, disabledTooltip="Debuff Display",
          getValue=function() return SValSupported("debuffStackTextSize", 14) end,
          setValue=function(v) SSetSupported("debuffStackTextSize", v) end });  y = y - h
    -- Directions cog on Debuff Duration Size (X/Y offsets) -- disabled with the row
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedDebuffRow2._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = debuffDurOff, disabledTooltip = debuffDurTip,
            title = "Duration Text",
            rows = {
                { type="slider", label="Offset X", min=-100, max=100, step=1,
                  get=function() return SValSupported("debuffCooldownTextOffsetX", 0) end,
                  set=function(v) SSetSupported("debuffCooldownTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-100, max=100, step=1,
                  get=function() return SValSupported("debuffCooldownTextOffsetY", 0) end,
                  set=function(v) SSetSupported("debuffCooldownTextOffsetY", v) end },
                { type="slider", label="Precise Below (minutes, 0 = off)", min=0, max=60, step=1,
                  get=function() local v=SValSupported("debuffCooldownTextPrecision", nil); return v and v/60 or 0 end,
                  set=function(v) SSetSupported("debuffCooldownTextPrecision", v > 0 and v*60 or nil) end },
            },
        })
    end
    -- Inline "Show Cooldown Text" toggle on Debuff Duration Size (always enabled)
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildInlineToggle({
        region   = sharedDebuffRow2._leftRegion,
        getValue = function() return SValSupported("debuffShowCooldownText", false) end,
        setValue = function(v) SSetSupported("debuffShowCooldownText", v) end,
        onToggle = function() EllesmereUI:RefreshPage() end,
    })
    end
    -- Directions cog on Debuff Stack Size (X/Y offsets)
    if not EllesmereUI._prebuilding then
        local rightRgn = sharedDebuffRow2._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = DebuffDisabled, disabledTooltip = "Debuff Display",
            title = "Stack Position",
            rows = {
                { type="dropdown", label="Position",
                  values={ bottomright="Bottom Right", bottomleft="Bottom Left", topright="Top Right", topleft="Top Left", center="Center" },
                  order={ "bottomright", "bottomleft", "topright", "topleft", "center" },
                  get=function() return SValSupported("debuffStackTextPosition", "bottomright") end,
                  set=function(v) SSetSupported("debuffStackTextPosition", v) end },
                { type="slider", label="Offset X", min=-100, max=100, step=1,
                  get=function() return SValSupported("debuffStackTextOffsetX", 0) end,
                  set=function(v) SSetSupported("debuffStackTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-100, max=100, step=1,
                  get=function() return SValSupported("debuffStackTextOffsetY", 0) end,
                  set=function(v) SSetSupported("debuffStackTextOffsetY", v) end },
            },
        })
    end
    end   -- close Debuff row 2 hidden-while-None gate

    -- Built here with the aura section's helpers, but appended only after
    -- all other buff/debuff controls so the border row stays last.
    local function AddAuraBorderSettings()
    if optState.selectedUnit == "player" or optState.selectedUnit == "target" then
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local auraBorderRow
        auraBorderRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Border Style", values=texValues, order=texOrder,
              getValue=function() return SVal("auraBorderTexture", "solid") end,
              setValue=function(v)
                  local color, behind, behindUnitFrame = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  local s = SDB()
                  s.auraBorderTexture = v
                  s.auraBorderTextureOffset = nil; s.auraBorderTextureOffsetY = nil
                  s.auraBorderTextureShiftX = nil; s.auraBorderTextureShiftY = nil
                  s.auraBorderBehind = behind
                  s.auraBorderBehindUnitFrame = behindUnitFrame
                  s.auraBorderR = color.r; s.auraBorderG = color.g; s.auraBorderB = color.b; s.auraBorderA = 1
                  local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                  if defSz then s.auraBorderSize = defSz end
                  -- A style pick returns the icons to their legacy step; clear a
                  -- set exact size (false travels through mirror sync, nil would not).
                  if s.auraBorderSizePx then s.auraBorderSizePx = false end
                  ReloadAndUpdate(); UpdatePreview()
                  -- The Width / Height Offset row exists only under a textured style.
                  EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size", trackWidth=120,
              getStep=function() return SVal("auraBorderSize", 1) end,
              setStep=function(step) SDB().auraBorderSize = step end,
              getTex=function() return SVal("auraBorderTexture", "solid") end,
              getPx=function() return SGet("auraBorderSizePx") end,
              setPx=function(v) SDB().auraBorderSizePx = v end,
              apply=function() ReloadAndUpdate(); UpdatePreview() end }))
        ); y = y - h
        -- Width Offset | Height Offset: a textured aura border's outward offsets
        -- (a Solid border has none).
        do
            local abTex = SVal("auraBorderTexture", "solid")
            if abTex ~= "solid" and abTex ~= "" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "unitframes",
                    getTex = function() return SVal("auraBorderTexture", "solid") end,
                    getStep = function() return SVal("auraBorderSize", 1) end,
                    getSizeKey = function() return SVal("auraBorderSize", 1) end,
                    getPx = function() return SGet("auraBorderSizePx") end,
                    getX = function() return SGet("auraBorderTextureOffset") end,
                    setX = function(v) SDB().auraBorderTextureOffset = v end,
                    getY = function() return SGet("auraBorderTextureOffsetY") end,
                    setY = function(v) SDB().auraBorderTextureOffsetY = v end,
                    apply = function() ReloadAndUpdate(); UpdatePreview() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("unitframes", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("unitframes", ocfgR)); y = y - h
            end
        end

        if not EllesmereUI._prebuilding then
            local rgn = auraBorderRow._leftRegion
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                title="Border Options",
                rows={
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("auraBorderTextureShiftX"); if v ~= nil then return v end
                          local _, _, sx = EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1)); return sx
                      end,
                      set=function(v) SSetSupported("auraBorderTextureShiftX", v == 0 and nil or v) end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                          local v = SGet("auraBorderTextureShiftY"); if v ~= nil then return v end
                          local _, _, _, sy = EllesmereUI.GetBorderDefaults("unitframes", SVal("auraBorderTexture", "solid"), SVal("auraBorderSize", 1)); return sy
                      end,
                      set=function(v) SSetSupported("auraBorderTextureShiftY", v == 0 and nil or v) end },
                    { type="toggle", label="Show Behind",
                      get=function() return SVal("auraBorderBehind", false) end,
                      set=function(v) SSetSupported("auraBorderBehind", v) end },
                    { type="toggle", label="Behind Unit Frame",
                      get=function() return SVal("auraBorderBehindUnitFrame", false) end,
                      set=function(v) SSetSupported("auraBorderBehindUnitFrame", v) end },
                    { type="toggle", label="Textured Dispel Ring",
                      tooltip="Draws the dispel-colored ring in this border style's shape instead of flat lines.",
                      -- Needs a dispel ring to draw: the debuff Dispel Type Borders,
                      -- or on Target the Buff Settings cog's own.
                      disabled=function()
                          return SVal("debuffDispelBorder", false) ~= true
                              and not (optState.selectedUnit ~= "player" and SVal("buffDispelBorder", false) == true)
                      end,
                      disabledTooltip="Dispel Type Borders",
                      get=function() return SVal("auraBorderDispelTextured", false) == true end,
                      set=function(v) SSetSupported("auraBorderDispelTextured", v) end },
                },
            })
            local function UpdateCogVis()
                if SVal("auraBorderTexture", "solid") == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis); UpdateCogVis()
        end

        if not EllesmereUI._prebuilding then
            local rgn = auraBorderRow._rightRegion
            local swatch, refreshSwatch = EllesmereUI.BuildColorSwatch(
                rgn, auraBorderRow:GetFrameLevel() + 3,
                function() return SVal("auraBorderR", 0), SVal("auraBorderG", 0), SVal("auraBorderB", 0), SVal("auraBorderA", 1) end,
                function(r, g, b, a)
                    local s = SDB(); s.auraBorderR = r; s.auraBorderG = g; s.auraBorderB = b; s.auraBorderA = a
                    ReloadAndUpdate(); UpdatePreview()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(refreshSwatch)
        end
    end
    end

    -- Per-unit aura filters (NOT synced). Labels track the selected section.
    -- Buff Filter (and the player frame's Debuff Filter) are multi-select
    -- checkbox dropdowns swapped into the DualRow slots below; the
    -- target/focus Debuff Filter is a native single-select mode dropdown
    -- (DebuffModeDropdownCfg). HIDDEN only when BOTH displays are None
    -- (either dropdown's DependentSetValue rebuilds on its None flip); with
    -- one side shown, the off side just grays out.
    if not (BuffDisabled() and DebuffDisabled()) then
    do
        local buffFilterItems, BUFF_FILTER_KEYS, BUFF_NEG_SKEYS
            -- Two-lane rows: Show narrows the frame to checked classes (legacy
            -- behavior, nothing checked = show everything); Hide removes a class
            -- from whatever shows (s.buffNegClasses, engine ClassNegated).
            -- Non-player buff vocabulary is just these three (the engine gates
            -- every other class off for these units; stale keys from retired
            -- checkboxes stay inert).
            buffFilterItems = {
                -- AND-modifier (engine: ChainFor), not a class: never locks a lane.
                { key = "__hasDuration", label = "Has Duration",
                  tooltip = "Only show buffs that have a duration, excluding permanent ones. Combines with the filters below." },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
                { key = "stealable",         label = "Stealable",          dual = true, tooltip = "Buffs you can spellsteal or purge" },
                { key = "bigDefensive",      label = "Big Defensive",      dual = true, tooltip = "Major defensive cooldowns" },
                { key = "dispellable",       label = "Dispellable",        dual = true, tooltip = "Auras with a dispel type you can dispel" },
            }
            BUFF_FILTER_KEYS   = { ownOnly = "onlyPlayerBuffs",   raidFrames = "buffRaid",   raidInCombat = "buffRaidInCombat",   dispellable = "buffDispellable",   crowdControl = "buffCrowdControl",   bigDefensive = "buffBigDefensive",   externalDefensive = "buffExternalDefensive",   cancelable = "buffCancelable", stealable = "buffStealable" }
            -- Hide-lane storage skeys (per-class entries in s.buffNegClasses);
            -- only dual rows appear here.
            BUFF_NEG_SKEYS   = { stealable = "Stealable", bigDefensive = "BigDefensive", dispellable = "Dispellable" }
        local unitLabel = UNIT_LABELS_SUP[optState.selectedUnit] or "Player"
        -- Right slot: the player frame swaps its checkbox dropdown in below;
        -- target/focus get the mode dropdown here (disabled, with the
        -- requirement tooltip, while Debuff Display is None).
        local debuffSlot
        if optState.selectedUnit == "player" then
            debuffSlot = { type="dropdown", text=unitLabel.." Debuff Filter",
              values={ __placeholder="..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end, setValue=function() end }
        else
            debuffSlot = DebuffModeDropdownCfg(unitLabel.." Debuff Filter", optState.selectedUnit, SDB, ReloadAndUpdate,
              { disabled=DebuffDisabled, disabledTooltip="Debuffs", requireState="displayed" })
        end
        local filterRow
        filterRow, h = W:DualRow(parent, y,
            { type="dropdown", text=unitLabel.." Buff Filter",
              values={ __placeholder="..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end, setValue=function() end },
            debuffSlot);  y = y - h
        -- Gray out + block a CB-dropdown when its column's Display is "none".
        local function ApplyFilterDisabled(cbDD, label, isOff)
            local function refresh()
                local off = isOff()
                cbDD:SetAlpha(off and 0.3 or 1)
                cbDD:EnableMouse(not off)
                if label then label:SetAlpha(off and 0.3 or 1) end
            end
            refresh()
            RegisterWidgetRefresh(refresh)
        end
        -- Left slot: Buff Filter. Player frame runs the Player Aura Bars Filters
        -- model verbatim (keep in sync with BuildAssignedBuffsFields in
        -- EUI_PlayerAuraBars_ManagerPages.lua): pinned All Buffs/Has Duration above
        -- a divider, then shared PAB_Filters entries. Checked filters SUBTRACT
        -- while All Buffs is on, ADD with it off; toggling clears selection. Other units keep the class-checkbox model.
        if not EllesmereUI._prebuilding then
            local rgn = filterRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbRefresh
            if optState.selectedUnit == "player" then
                -- The registry list needs the curated presets present
                -- (idempotent; PAB may be disabled).
                if ns.PAB_ImportBM2Filters then ns.PAB_ImportBM2Filters() end
                local ps = UNIT_DB_MAP[optState.selectedUnit]()
                local ALL_KEY, DUR_KEY = "__allBuffs", "__hasDuration"
                -- Hovering a dimmed Show box explains the dim (the lane is inert
                -- while a broad mode already shows everything), same wording as
                -- the Debuff Filter.
                local lockedTip = EllesmereUI.L("All Buffs or Has Duration is selected, so every buff already shows. Use the red Hide box to exclude these instead.")
                -- Any Show-lane filter, or a direct Extra Spell, counts as a
                -- content source once neither broad mode is on.
                local function OtherContent()
                    if ps.buffFilters and next(ps.buffFilters) then
                        -- WoW Forever: visible filters only (a hidden retail
                        -- preset shows nothing on this client).
                        if not EllesmereUI.IS_FOREVER then return true end
                        for fid in pairs(ps.buffFilters) do
                            if not ns.PAB_HiddenPresetFilter(fid) then return true end
                        end
                    end
                    if ps.buffSpells and #ps.buffSpells > 0 then return true end
                    return false
                end
                local function FilterItems()
                    local items = {
                        { isTopAction = true, label = "Edit Filters", onClick = function()
                            if ns.PABMP_ShowFilterEditor then
                                ns.PABMP_ShowFilterEditor()
                                -- Filter edits change the resolved spell
                                -- sets; refresh the frame when the modal
                                -- closes (the editor is our own frame).
                                local ed = ns._pabFilterEditor
                                if ed and not ed._ufReloadHook then
                                    ed._ufReloadHook = true
                                    ed:HookScript("OnHide", function() ReloadAndUpdate() end)
                                end
                            end
                        end },
                        -- Blacklist editing only matters while broad
                        -- content is on (All Buffs / Has Duration).
                        { isTopAction = true, label = "Edit Blacklist",
                          lockedFn = function()
                              return ps.buffShowAll == false and ps.buffHasDuration ~= true
                          end,
                          lockedTooltip = function() return EllesmereUI.DisabledTooltip("All Buffs or Has Duration", "enabled") end,
                          onClick = function()
                              EllesmereUI.ShowSpellBlacklistPopup({
                                  title = "Buff Blacklist",
                                  get = function() return ps.buffBlacklist end,
                                  add = function(id)
                                      ps.buffBlacklist = ps.buffBlacklist or {}
                                      ps.buffBlacklist[id] = true
                                  end,
                                  remove = function(id)
                                      if ps.buffBlacklist then
                                          ps.buffBlacklist[id] = nil
                                          if not next(ps.buffBlacklist) then ps.buffBlacklist = nil end
                                      end
                                  end,
                                  onChanged = function() ReloadAndUpdate() end,
                              })
                          end },
                        { key = ALL_KEY, label = "All Buffs",
                          tooltip = "Show every buff. Use the Hide lane below to remove specific filters." },
                        { key = DUR_KEY, label = "Has Duration",
                          tooltip = "Show every buff that has a duration (hides permanent buffs). Use the Hide lane below to remove specific filters." },
                        { isHeader = true, label = "Show", rightLabel = "Hide" },
                    }
                    local BroadOn = function()
                        return ps.buffShowAll ~= false or ps.buffHasDuration == true
                    end
                    local list = ns.PAB_Filters and ns.PAB_Filters() or {}
                    -- Buff Manager parity ordering (matches the PAB pages'
                    -- SortFiltersCanonical): presets in curated catalogue
                    -- order (Defensives leads), then user filters in
                    -- creation order.
                    local rank = {}
                    local BP = EllesmereUI.BUFF_PRESETS
                    if BP and BP.filters then
                        for i = 1, #BP.filters do rank[BP.filters[i].name] = i end
                    end
                    local sorted, pos = {}, {}
                    for i = 1, #list do
                        sorted[#sorted + 1] = list[i]
                        pos[list[i]] = i
                    end
                    table.sort(sorted, function(a, b)
                        return (rank[a.name] or (1000 + pos[a])) < (rank[b.name] or (1000 + pos[b]))
                    end)
                    for i = 1, #sorted do
                        items[#items + 1] = { key = sorted[i].id, label = sorted[i].name,
                            dual = true, showLockedFn = BroadOn, showLockedTooltip = lockedTip }
                    end
                    return items
                end
                if ns.UF_EnsurePlayerAuraLanes then ns.UF_EnsurePlayerAuraLanes(ps) end
                local warnClosed
                cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2,
                    FilterItems,
                    function(k, neg)
                        if k == ALL_KEY then return ps.buffShowAll ~= false end
                        if k == DUR_KEY then return ps.buffHasDuration == true end
                        if neg then
                            local nf = ps.buffNegFilters
                            return nf and nf[k] == true
                        end
                        return ps.buffFilters and ps.buffFilters[k] == true
                    end,
                    function(k, v, neg)
                        if k == ALL_KEY then
                            -- Written unconditionally (Player Aura Bars parity): the
                            -- Show lane is locked while a broad mode is on, so a
                            -- no-empty guard here would make the toggle impossible to
                            -- turn off. AttachEmptyFilterWarn below owns the feedback
                            -- for the resulting empty selection instead.
                            ps.buffShowAll = v
                            -- Mutually exclusive with Has Duration (both are broad-content
                            -- modes). Lanes persist across mode flips (the hide lane
                            -- subtracts in both modes).
                            ps.buffHasDuration = nil
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if k == DUR_KEY then
                            ps.buffHasDuration = v or nil
                            -- Mutually exclusive with All Buffs (its own broad-content
                            -- mode); lanes persist.
                            if v then ps.buffShowAll = false end
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                            return
                        end
                        -- Two-lane filter write: checking one lane clears the other;
                        -- emptied lane tables drop to nil (saved-variable hygiene).
                        if neg then
                            ps.buffNegFilters = ps.buffNegFilters or {}
                            ps.buffNegFilters[k] = v or nil
                            if not next(ps.buffNegFilters) then ps.buffNegFilters = nil end
                            if v and ps.buffFilters then ps.buffFilters[k] = nil end
                        else
                            ps.buffFilters = ps.buffFilters or {}
                            ps.buffFilters[k] = v or nil
                            if v and ps.buffNegFilters then
                                ps.buffNegFilters[k] = nil
                                if not next(ps.buffNegFilters) then ps.buffNegFilters = nil end
                            end
                        end
                        if ps.buffFilters and not next(ps.buffFilters) then ps.buffFilters = nil end
                        ReloadAndUpdate()
                        -- Non-force: runs only the registered lightweight refresh
                        -- callbacks (the empty-selection warning below) in place,
                        -- without closing this open dropdown.
                        EllesmereUI:RefreshPage()
                    end,
                    nil, 12, nil, nil, function() if warnClosed then warnClosed() end end)
                -- Empty-selection warning (Player Aura Bars parity): replaces the
                -- old silent block. A Buff Display of None already dims the whole
                -- control, so it is not warned about a second time.
                warnClosed = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD,
                    EllesmereUI.L("You are displaying NO buffs at all."),
                    function() return BuffDisabled() or ps.buffShowAll ~= false or ps.buffHasDuration == true or OtherContent() end)
            else
                cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2, buffFilterItems,
                    function(k, neg)
                        if k == "__hasDuration" then return SDB().buffDurOnly == true end
                        if neg then
                            local m = SDB().buffNegClasses
                            local sk = BUFF_NEG_SKEYS[k]
                            return m ~= nil and sk ~= nil and m[sk] == true
                        end
                        return SValSupported(BUFF_FILTER_KEYS[k], false)
                    end,
                    function(k, v, neg)
                        local db = SDB()
                        if k == "__hasDuration" then
                            -- Not buffHasDuration: that is the player's broad
                            -- mode, which copies can have left on this unit.
                            db.buffDurOnly = v or nil
                            ReloadAndUpdate(); UpdatePreview()
                            return
                        end
                        local sk = BUFF_NEG_SKEYS[k]
                        if neg then
                            if not sk then return end
                            db.buffNegClasses = db.buffNegClasses or {}
                            db.buffNegClasses[sk] = v and true or nil
                            if not next(db.buffNegClasses) then db.buffNegClasses = nil end
                            if v then db[BUFF_FILTER_KEYS[k]] = nil end
                            ReloadAndUpdate(); UpdatePreview()
                            return
                        end
                        if v and sk and db.buffNegClasses then
                            db.buffNegClasses[sk] = nil
                            if not next(db.buffNegClasses) then db.buffNegClasses = nil end
                        end
                        SSetSupported(BUFF_FILTER_KEYS[k], v)
                    end)
            end
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD; rgn._lastInline = nil
            RegisterWidgetRefresh(cbRefresh)
            ApplyFilterDisabled(cbDD, rgn._label, BuffDisabled)

            -- Purgeable Buff Glow (target/focus): inline cog beside the Buff
            -- Filter. The glow styles whichever purgeable buffs the filter
            -- shows; the engine gates it on the character's offensive dispel.
            if optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
                -- Shared glow controls over the unit's own keys. Engine aura
                -- buttons: C-side styles only. Unset color = the suite default (gold).
                local GO = EllesmereUI.GlowOptions
                local pgDesc = UF_PurgeGlowDesc(SDB)
                local pgRows = GO.PopupRows(pgDesc, "Glow Style")
                pgRows[1].tooltip = "Glows the buffs you can purge or spellsteal. Glowing buffs lead the row and have their own Max Buffs count."
                EllesmereUI.BuildInlineCog(rgn, {
                    title = "Purgeable Buffs",
                    tip = "Glow the buffs you can purge or spellsteal",
                    -- Greys out with the Buff Display (None = no buffs to glow).
                    disabled = BuffDisabled,
                    disabledTooltip = "Buffs",
                    rows = pgRows,
                })
            end
        end
        -- Right slot (player frame): the Player Aura Bars debuff Filters model
        -- verbatim (sync with BuildAssignedDebuffsFields): pinned All Debuffs
        -- above a divider, then shared class vocabulary (ns.PAB_ClassItems).
        -- Checked classes SUBTRACT while All Debuffs is on, ADD with it off; class
        -- rows view the SAME legacy per-class keys (s.debuff<SKey>) the old dropdown
        -- wrote. Target/focus built their mode dropdown in the DualRow above.
        if optState.selectedUnit == "player" and not EllesmereUI._prebuilding then
            local rgn = filterRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbRefresh
            do
                local ps = UNIT_DB_MAP[optState.selectedUnit]()
                local ALL_KEY, DUR_KEY = "__allDebuffs", "__debuffHasDuration"
                local function AllOn() return ps.debuffShowAll ~= false end
                -- Hovering a dimmed Show box explains the dim (the lane is inert
                -- while All Debuffs already shows everything), same wording as
                -- Player Aura Bars.
                local lockedTip = EllesmereUI.L("All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead.")
                -- Any Show-lane class counts as a content source -- scanned over the
                -- FULL vocabulary (stale keys from retired checkboxes still render in
                -- add mode, so they legitimately hold content).
                local function AnyShowClass()
                    local function Scan(list)
                        if not list then return false end
                        for i = 1, #list do
                            local class = list[i]
                            if not class.buffOnly and ps["debuff" .. class.skey] == true then return true end
                        end
                        return false
                    end
                    return Scan(ns.UF_TokenClasses) or Scan(ns.UF_CandidateClasses)
                end
                local function FilterItems()
                    -- Match Mode (ps.debuffFilterMatch: nil = Match Any, the
                    -- union; "all" = one group matching every Show pick). A
                    -- radio pair over one scalar, locked while All Debuffs
                    -- makes the Show lane inert (the setting is kept).
                    local matchLockTip = EllesmereUI.L("Uncheck All Debuffs to choose how the Show filters combine.")
                    local items = {
                        { key = ALL_KEY, label = "All Debuffs",
                          tooltip = "Show every debuff. Use the Hide lane below to remove specific filters." },
                        { key = DUR_KEY, label = "Has Duration",
                          tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff." },
                        { isHeader = true, label = "Match Mode" },
                        { key = "__matchAny", label = EllesmereUI.L("Match Any Filter"), isModifier = true,
                          lockedFn = AllOn, lockedTooltip = matchLockTip,
                          tooltip = EllesmereUI.L("Shows debuffs that match any checked Show filter (the default).") },
                        { key = "__matchAll", label = EllesmereUI.L("Match All Filters"), isModifier = true,
                          lockedFn = AllOn, lockedTooltip = matchLockTip,
                          tooltip = EllesmereUI.L("Shows only debuffs that match every checked Show filter (dispel types count as one); opposites like Non-Player Auras with Cast By You show nothing.") },
                        { isHeader = true, label = "Show", rightLabel = "Hide" },
                    }
                    local classItems = ns.PAB_ClassItems and ns.PAB_ClassItems(false) or {}
                    for i = 1, #classItems do
                        local ci = classItems[i]
                        if ci.isHeader then
                            items[#items + 1] = { isHeader = true, label = ci.label }
                        else
                            items[#items + 1] = { key = ci.key, label = ci.label, tooltip = ci.tooltip,
                                dual = true, showLockedFn = AllOn, showLockedTooltip = lockedTip }
                        end
                    end
                    return items
                end
                -- Non-Player / From Any Player share one engine field: a check
                -- in either lane clears the sibling from both lanes.
                local function ClearExclusive(k)
                    local other = ns.PAB_ExclusiveSkey and ns.PAB_ExclusiveSkey[k]
                    if not other then return end
                    ps["debuff" .. other] = nil
                    if ps.debuffNegClasses then
                        ps.debuffNegClasses[other] = nil
                        if not next(ps.debuffNegClasses) then ps.debuffNegClasses = nil end
                    end
                end
                if ns.UF_EnsurePlayerAuraLanes then ns.UF_EnsurePlayerAuraLanes(ps) end
                local warnClosed
                cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rgn, 210, rgn:GetFrameLevel() + 2,
                    FilterItems,
                    function(k, neg)
                        if k == ALL_KEY then return AllOn() end
                        if k == DUR_KEY then return ps.debuffHasDuration == true end
                        if k == "__matchAny" or k == "__matchAll" then
                            return (k == "__matchAll") == (ps.debuffFilterMatch == "all")
                        end
                        if neg then
                            local m = ps.debuffNegClasses
                            return m ~= nil and m[k] == true
                        end
                        return ps["debuff" .. k] == true
                    end,
                    function(k, v, neg)
                        if k == "__matchAny" or k == "__matchAll" then
                            -- Radio: the clicked row wins whatever its checked
                            -- state was (re-clicking the active row keeps it).
                            local want
                            if k == "__matchAll" then want = "all" end
                            if ps.debuffFilterMatch == want then return end
                            ps.debuffFilterMatch = want
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if k == ALL_KEY then
                            -- Written unconditionally (Player Aura Bars parity): the
                            -- Show lane is locked while All Debuffs is on, so a
                            -- no-empty guard here would make the toggle impossible to
                            -- turn off. AttachEmptyFilterWarn below owns the feedback
                            -- for the resulting empty selection instead.
                            -- Lanes persist across mode flips (the hide lane
                            -- subtracts in both modes; the show lane goes dormant
                            -- while All Debuffs is on).
                            ps.debuffShowAll = v
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if k == DUR_KEY then
                            -- AND-modifier (never locks the Show lane): combines
                            -- with All Debuffs or the Show picks; alone it is the
                            -- timed catch-all.
                            ps.debuffHasDuration = v or nil
                            ReloadAndUpdate()
                            EllesmereUI:RefreshPage()
                            return
                        end
                        -- Two-lane class write: checking one lane clears the other.
                        if v then ClearExclusive(k) end
                        if neg then
                            ps.debuffNegClasses = ps.debuffNegClasses or {}
                            ps.debuffNegClasses[k] = v or nil
                            if not next(ps.debuffNegClasses) then ps.debuffNegClasses = nil end
                            if v then ps["debuff" .. k] = nil end
                        else
                            ps["debuff" .. k] = v or nil
                            if v and ps.debuffNegClasses then
                                ps.debuffNegClasses[k] = nil
                                if not next(ps.debuffNegClasses) then ps.debuffNegClasses = nil end
                            end
                        end
                        ReloadAndUpdate()
                        -- Non-force: runs only the registered lightweight refresh
                        -- callbacks (the empty-selection warning below) in place,
                        -- without closing this open dropdown.
                        EllesmereUI:RefreshPage()
                    end,
                    nil, 12, nil, nil, function() if warnClosed then warnClosed() end end,
                    -- Summary joins picks with " & " while Match All combines them.
                    { separatorFn = function()
                        if ps.debuffFilterMatch == "all" and not AllOn() then return " & " end
                        return ", "
                    end })
                -- Empty-selection warning (Player Aura Bars parity): replaces the
                -- old silent block. A Debuff Display of None already dims the whole
                -- control, so it is not warned about a second time. Match All picks
                -- that can never match together count as empty (the engine test).
                warnClosed = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD,
                    EllesmereUI.L("You are displaying NO debuffs at all."),
                    function()
                        return DebuffDisabled() or AllOn()
                            or (ps.debuffHasDuration == true and not AnyShowClass())
                            or (AnyShowClass() and not (ns.UF_DebuffMatchEmpty and ns.UF_DebuffMatchEmpty(ps)))
                    end)
            end
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD; rgn._lastInline = nil
            RegisterWidgetRefresh(cbRefresh)
            ApplyFilterDisabled(cbDD, rgn._label, DebuffDisabled)
        end
        -- Target/focus: Only Tracked Auras with an empty list renders
        -- nothing, so the mode dropdown carries the standard empty warning.
        if optState.selectedUnit ~= "player" and not EllesmereUI._prebuilding then
            AttachDebuffModeWarn(filterRow._rightRegion, SDB, DebuffDisabled)
            -- Has Duration: an AND-modifier on the picked mode (engine:
            -- ChainFor), in the row's cog since the mode dropdown is
            -- single-select.
            EllesmereUI.BuildInlineCog(filterRow._rightRegion, {
                title = "Debuff Filter",
                tip = "Debuff Filter Options",
                disabled = DebuffDisabled,
                disabledTooltip = "Debuffs",
                requireState = "displayed",
                rows = {
                    { type = "toggle", label = "Has Duration",
                      tooltip = "Only show debuffs that have a duration, excluding permanent ones. Tracked Auras always show.",
                      get = function() return SDB().debuffHasDuration == true end,
                      set = function(v)
                          SDB().debuffHasDuration = v or nil
                          ReloadAndUpdate()
                      end },
                },
            })
        end
    end
    end   -- close filter row hidden-while-both-None gate

    -- Dispel Overlay + Dispel Colors (player frame only; settings keys
    -- mirror the Raid Frames dispel system 1:1)
    if optState.selectedUnit == "player" then
        local dispelOverlayValues = {
            none     = "None",
            fill     = "Fill Overlay",
            full     = "Full Overlay",
            gradient = "Gradient Overlay",
            gradient_sharp = "Gradient Sharp",
        }
        local dispelOverlayOrder = { "none", "fill", "full", "gradient", "gradient_sharp" }
        local function DispelRefresh()
            if ns.UpdatePlayerDispelOverlay then ns.UpdatePlayerDispelOverlay() end
            UpdatePreview()
        end
        -- Palette edits: the overlay and border copies (DispelRefresh), and
        -- with Use Dispel Colors on also the player debuff rings, whose
        -- restyle is fingerprint-gated on the palette.
        local function PaletteRefresh()
            DispelRefresh()
            if db.profile.player.debuffDispelUsePalette == true and frames.player then
                ns.UF_ReloadAuraContainers(frames.player, "player")
            end
        end
        -- Color Custom Borders copies the player frame's own border, so it
        -- needs one to copy: the EllesmereUI style, a Border Style other than
        -- Solid and a Border Size above 0 (runtime twin: ns.UF_CustomBorderOn).
        local function CustomBorderOff()
            return not ns.UF_CustomBorderOn(db.profile.player)
        end
        local function CustomBorderOffTip()
            if EllesmereUI.BlizzStyle.Get("unitframes") then
                return EllesmereUI.BlizzStyle.Label("unitframes")
            end
            local tex = db.profile.player.borderTexture
            if tex == nil or tex == "" or tex == "solid" then
                return "This option requires a Border Style other than Solid."
            end
            return "This option requires a Border Size above 0."
        end
        local dispelRow
        dispelRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Dispel Overlay", values=dispelOverlayValues, order=dispelOverlayOrder,
              getValue=function() return db.profile.dispelOverlay or "none" end,
              -- RefreshPage (fast path) so the Dispel Colors disabled
              -- state tracks the overlay selection live.
              setValue=function(v) db.profile.dispelOverlay = v; DispelRefresh(); EllesmereUI:RefreshPage() end },
            { type="multiSwatch", text="Dispel Colors",
              -- The palette also colours the Color Custom Borders copies and,
              -- with Use Dispel Colors, the player debuff rings.
              disabled=function()
                  local p = db.profile
                  return (p.dispelOverlay or "none") == "none"
                      and not (p.dispelCustomBorder == true and ns.UF_CustomBorderOn(p.player))
                      and p.player.debuffDispelUsePalette ~= true
              end,
              disabledTooltip="This option requires a Dispel Overlay, Color Custom Borders or Use Dispel Colors.",
              rawTooltip=true,
              swatches = {
                { tooltip = "Magic", hasAlpha = false,
                  getValue = function() local c = db.profile.dispelColorMagic; if c then return c.r, c.g, c.b end return 0.349, 0.475, 1.0 end,
                  setValue = function(r, g, b) db.profile.dispelColorMagic = { r=r, g=g, b=b }; PaletteRefresh() end },
                { tooltip = "Curse", hasAlpha = false,
                  getValue = function() local c = db.profile.dispelColorCurse; if c then return c.r, c.g, c.b end return 0.636, 0.0, 0.64 end,
                  setValue = function(r, g, b) db.profile.dispelColorCurse = { r=r, g=g, b=b }; PaletteRefresh() end },
                { tooltip = "Disease", hasAlpha = false,
                  getValue = function() local c = db.profile.dispelColorDisease; if c then return c.r, c.g, c.b end return 0.671, 0.384, 0.098 end,
                  setValue = function(r, g, b) db.profile.dispelColorDisease = { r=r, g=g, b=b }; PaletteRefresh() end },
                { tooltip = "Poison", hasAlpha = false,
                  getValue = function() local c = db.profile.dispelColorPoison; if c then return c.r, c.g, c.b end return 0.0, 0.706, 0.286 end,
                  setValue = function(r, g, b) db.profile.dispelColorPoison = { r=r, g=g, b=b }; PaletteRefresh() end },
                { tooltip = "Bleed", hasAlpha = false,
                  getValue = function() local c = db.profile.dispelColorBleed; if c then return c.r, c.g, c.b end return 0.75, 0.15, 0.15 end,
                  setValue = function(r, g, b) db.profile.dispelColorBleed = { r=r, g=g, b=b }; PaletteRefresh() end },
              } });  y = y - h
        -- Inline eyeball: preview a magic dispel overlay on the top player preview.
        if not EllesmereUI._prebuilding then
            local rgn = dispelRow._leftRegion
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
            local function RefreshDispelEye()
                eyeTex:SetTexture(optState.showDispelOverlayPreview and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshDispelEye()
            eyeBtn:SetScript("OnClick", function()
                optState.showDispelOverlayPreview = not optState.showDispelOverlayPreview
                RefreshDispelEye()
                UpdatePreview()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, optState.showDispelOverlayPreview and "Hide dispel overlay preview" or "Show dispel overlay preview")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
        end
        -- Inline cog on Dispel Overlay: Overlay Opacity
        if not EllesmereUI._prebuilding then
            local rgn = dispelRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Dispel Overlay",
                rows = {
                    { type="slider", label="Overlay Opacity", min=5, max=100, step=1,
                      get=function() return db.profile.dispelOverlayOpacity or 100 end,
                      set=function(v) db.profile.dispelOverlayOpacity = v; DispelRefresh() end },
                    { type="toggle", label="Only Dispellable by You",
                      tooltip="Shows the overlay only for debuffs you can currently dispel.",
                      get=function() return db.profile.dispelOverlayByMe == true end,
                      set=function(v) db.profile.dispelOverlayByMe = v and true or false; DispelRefresh() end },
                    { type="toggle", label="Color Custom Borders",
                      tooltip="Recolors the frame border, portrait outer ring and enabled power and portrait separators in the dispel type color while a debuff of that type is shown.",
                      -- Copies the frame's own border: only over a custom border (CustomBorderOff).
                      disabled=CustomBorderOff,
                      disabledTooltip=CustomBorderOffTip,
                      requireState="disabled",
                      get=function() return db.profile.dispelCustomBorder == true end,
                      -- RefreshPage (fast path) so the Dispel Colors disabled state tracks it.
                      set=function(v)
                          db.profile.dispelCustomBorder = v and true or false
                          DispelRefresh(); EllesmereUI:RefreshPage()
                      end },
                },
            })
        end
    end

    AddAuraBorderSettings()

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y, sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3
end
