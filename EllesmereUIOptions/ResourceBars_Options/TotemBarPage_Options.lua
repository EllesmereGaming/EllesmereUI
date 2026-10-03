if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\TotemBarPage_Options.lua
--  Resource Bars options: Totem Bar page ("Totem Bars" on WoW Forever, where a
--  shaman's Call Totem Bar section follows the active totem bar's). Both sections
--  come from one builder over their own settings table. Definitions only; the
--  shared helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- One totem bar section. S: title, key (the profile table), unlockKey, off()
-- (the section's controls grey while it returns true) with its disabled
-- tooltip (req, raw), and enableRow(y, sizeCfg, RefreshTotem) -> row, h: the
-- first row, whose left slot turns the bar on and whose right slot is sizeCfg
-- (Icon Size).
local function BuildTotemSection(parent, y, S)
    local env = ns._ERB_OptEnv
    local DB = env.DB
    local W = EllesmereUI.Widgets
    local _, h

    local function T()
        local p = DB()
        return p and p[S.key]
    end

    local function RefreshTotem()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized(S.unlockKey)
        end
    end

    local totemOff = S.off
    local timerOff = function()
        local t = T()
        return totemOff() or (t and not t.showTimer)
    end
    local req, raw = S.req, S.raw

    _, h = W:SectionHeader(parent, S.title, y);  y = y - h

    -- Row 1: the section's on switch | Icon Size (+ spacing cog)
    local row1
    row1, h = S.enableRow(y, { type = "slider", text = "Icon Size",
          min = 16, max = 60, step = 1,
          disabled = totemOff,
          disabledTooltip = req, rawTooltip = raw,
          getValue = function() local t = T(); return t and (t.iconSize or 30) end,
          setValue = function(v)
              local t = T(); if not t then return end
              t.iconSize = v; RefreshTotem()
          end }, RefreshTotem);  y = y - h

    -- Spacing cog on Icon Size (right region)
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row1._rightRegion, {
            title = "Icon Settings",
            rows = {
                { type = "slider", pixel = true, label = "Spacing", min = 0, max = 20, step = 1,
                  get = function() local t = T(); return t and (t.spacing or 2) end,
                  set = function(v)
                      local t = T(); if not t then return end
                      t.spacing = v; RefreshTotem()
                  end },
            },
        })
    end

    -- Row 2: Timer Size | Show Timer
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Timer Size",
          min = 6, max = 24, step = 1,
          disabled = timerOff,
          disabledTooltip = "Show Timer",
          getValue = function() local t = T(); return t and (t.timerSize or 11) end,
          setValue = function(v)
              local t = T(); if not t then return end
              t.timerSize = v; RefreshTotem()
          end },
        { type = "toggle", text = "Show Timer",
          disabled = totemOff,
          disabledTooltip = req, rawTooltip = raw,
          getValue = function() local t = T(); return t and t.showTimer ~= false end,
          setValue = function(v)
              local t = T(); if not t then return end
              t.showTimer = v; RefreshTotem()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    -- Row 3: Border Style | Border Size (+ inline swatch + offset cog)
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Border Style",
              disabled = totemOff,
              disabledTooltip = req, rawTooltip = raw,
              values = texValues, order = texOrder,
              getValue = function() local t = T(); return t and (t.borderTexture or "solid") end,
              setValue = function(v)
                  local t = T(); if not t then return end
                  t.borderTexture = v
                  t.borderTextureOffset = nil; t.borderTextureOffsetY = nil
                  t.borderTextureShiftX = nil; t.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  t.borderR = _bcol.r; t.borderG = _bcol.g; t.borderB = _bcol.b; t.borderA = 1
                  t.borderBehind = _bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then t.borderSize = defSz end
                  if t.borderSizePx then t.borderSizePx = false end
                  RefreshTotem(); EllesmereUI:RefreshPage(true)
              end },
            EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = totemOff,
              disabledTooltip = req, rawTooltip = raw,
              getStep = function() local t = T(); return t and (t.borderSize or 0) or 0 end,
              setStep = function(v) local t = T(); if t then t.borderSize = v end end,
              getTex = function() local t = T(); return t and (t.borderTexture or "solid") or "solid" end,
              getPx = function() local t = T(); return t and t.borderSizePx end,
              setPx = function(v) local t = T(); if t then t.borderSizePx = v end end,
              apply = function() RefreshTotem(); EllesmereUI:RefreshPage() end,
            })
        );  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local t = T()
            local tex = t and t.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local t2 = T(); return t2 and (t2.borderSize or 0) or 0 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = totemOff,
                    disabledTooltip = req, rawTooltip = raw,
                    getTex = function() local t2 = T(); return t2 and (t2.borderTexture or "solid") or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local t2 = T(); return t2 and t2.borderSizePx end,
                    getX = function() local t2 = T(); return t2 and t2.borderTextureOffset end,
                    setX = function(v) local t2 = T(); if t2 then t2.borderTextureOffset = v end end,
                    getY = function() local t2 = T(); return t2 and t2.borderTextureOffsetY end,
                    setY = function(v) local t2 = T(); if t2 then t2.borderTextureOffsetY = v end end,
                    apply = function() RefreshTotem(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end

        -- Inline border color swatch on Border Size slider
        do
            local rgn = bsRow._rightRegion
            local ctrl = rgn._control
            local PP = EllesmereUI.PP
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bsRow:GetFrameLevel() + 3,
                function()
                    local t = T()
                    return (t and t.borderR or 0), (t and t.borderG or 0),
                           (t and t.borderB or 0), (t and t.borderA or 1)
                end,
                function(r, g, b, a)
                    local t = T(); if not t then return end
                    t.borderR = r; t.borderG = g; t.borderB = b; t.borderA = a
                    RefreshTotem(); EllesmereUI:RefreshPage()
                end,
                true, 20)
            PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            -- Disable swatch when border size is 0
            local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
            borderSwatchBlock:SetAllPoints()
            borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
            borderSwatchBlock:EnableMouse(true)
            borderSwatchBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
            end)
            borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderSwatchState()
                local t = T()
                local noBorder = not t or (t.borderSize or 0) == 0
                if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateBorderSwatchState() end)
            UpdateBorderSwatchState()
        end

        -- Border Options cog on Border Style (left region): hidden for "solid",
        -- disabled with the section's controls while the bar is off
        if not EllesmereUI._prebuilding then
            local rgn = bsRow._leftRegion
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = totemOff, disabledTooltip = req, rawTooltip = raw,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local t = T(); if not t then return 0 end
                          local v = t.borderTextureShiftX
                          if v then return v end
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", t.borderTexture or "solid", t.borderSize or 0)
                          return dsx
                      end,
                      set = function(v)
                          local t = T(); if not t then return end
                          t.borderTextureShiftX = v == 0 and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local t = T(); if not t then return 0 end
                          local v = t.borderTextureShiftY
                          if v then return v end
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", t.borderTexture or "solid", t.borderSize or 0)
                          return dsy
                      end,
                      set = function(v)
                          local t = T(); if not t then return end
                          t.borderTextureShiftY = v == 0 and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local t = T(); return t and t.borderBehind or false end,
                      set = function(v)
                          local t = T(); if not t then return end
                          t.borderBehind = v == false and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                      end },
                },
            })
            local function UpdateCogVis()
                local t = T()
                local tex = t and t.borderTexture or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row 4: Frame Strata | Orientation
    local tmStrataValues = EllesmereUI.FRAME_STRATA_LABELS
    local tmStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          disabled = totemOff,
          disabledTooltip = req, rawTooltip = raw,
          values = tmStrataValues, order = tmStrataOrder,
          getValue = function()
              local t = T(); return t and t.frameStrata or "MEDIUM"
          end,
          setValue = function(v)
              local t = T(); if not t then return end
              t.frameStrata = v; RefreshTotem()
          end },
        { type = "dropdown", text = "Orientation",
          disabled = totemOff,
          disabledTooltip = req, rawTooltip = raw,
          values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
          order = { "HORIZONTAL", "VERTICAL" },
          getValue = function() local t = T(); return t and (t.orientation or "HORIZONTAL") end,
          setValue = function(v)
              local t = T(); if not t then return end
              t.orientation = v; RefreshTotem()
          end }
    );  y = y - h

    return y
end

-- Totem Bar options page
function ns.ERB_BuildTotemBarPage(pageName, parent, yOffset)
    local env = ns._ERB_OptEnv
    local DB, PP, _clickMappings = env.DB, env.PP, env._clickMappings
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local forever = EllesmereUI.IS_FOREVER

    parent._showRowDivider = true

    EllesmereUI:HideContentHeader()

    -- Shared live table; never wiped from a hidden pre-build (see the matching guard in BuildBarDisplayPage).
    if not EllesmereUI._prebuilding then
        wipe(_clickMappings)
    end

    -- Blizzard's active totems (every class list). On WoW Forever it is the first
    -- of two totem bar sections.
    y = BuildTotemSection(parent, y, {
        title = forever and "ACTIVE TOTEM BAR" or "LAYOUT",
        key = "totemBar", unlockKey = "ERB_TotemBar",
        off = function()
            local p = DB()
            return p and not p.totemBar.enabledClasses
        end,
        req = "Select a class above", raw = true,
        -- Enabled Classes dropdown (built over a blank label slot)
        enableRow = function(ry, sizeCfg, RefreshTotem)
            local ALL_CLASSES = EllesmereUI.CLASS_TOKEN_ORDER
            local classItems = {}
            classItems[#classItems + 1] = { key = "NONE", label = EllesmereUI.L("None (Disabled)") }
            -- WoW Forever lists only the classes that client has.
            local foreverOnly = forever and EllesmereUI.FOREVER_CLASS_SPEC
            for _, cf in ipairs(ALL_CLASSES) do
                if not foreverOnly or foreverOnly[cf] then
                    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
                    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf])
                        or (cf:sub(1, 1):upper() .. cf:sub(2):lower())
                    local hex = color and color.colorStr or "ffffffff"
                    classItems[#classItems + 1] = { key = cf, label = "|c" .. hex .. name .. "|r" }
                end
            end

            local row1, rh = W:DualRow(parent, ry, { type = "label", text = "Enabled Classes" }, sizeCfg)

            -- Class dropdown on left region
            if not EllesmereUI._prebuilding then
            local leftRgn = row1._leftRegion
            local cbDD, cbDDRefresh
            cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                classItems,
                function(key)
                    local p = DB()
                    if not p then return false end
                    if key == "NONE" then return not p.totemBar.enabledClasses end
                    return p.totemBar.enabledClasses and p.totemBar.enabledClasses[key] or false
                end,
                function(key, v)
                    local p = DB()
                    if not p then return end
                    if key == "NONE" then
                        p.totemBar.enabledClasses = nil
                    else
                        if not p.totemBar.enabledClasses then
                            p.totemBar.enabledClasses = {}
                        end
                        p.totemBar.enabledClasses[key] = v or nil
                        if not next(p.totemBar.enabledClasses) then
                            p.totemBar.enabledClasses = nil
                        end
                    end
                    local ddMenu = cbDD._ddMenu
                    if ddMenu then
                        for _, sf in ipairs({ ddMenu:GetChildren() }) do
                            local sc = sf.GetScrollChild and sf:GetScrollChild()
                            if sc then
                                for _, row in ipairs({ sc:GetChildren() }) do
                                    if row._updateCheck then row._updateCheck() end
                                end
                            end
                        end
                    end
                    RefreshTotem()
                    EllesmereUI:RefreshPage()
                end, nil, 8, false)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            return row1, rh
        end,
    })

    -- WoW Forever: Blizzard's call totem bar (Call of the Elements, the four
    -- element slots, Totemic Recall), reskinned and owned by Unlock Mode.
    -- Shamans only (the runtime file loads for no other class).
    if forever and select(2, UnitClass("player")) == "SHAMAN" then
        _, h = W:Spacer(parent, y, 16);  y = y - h
        y = BuildTotemSection(parent, y, {
            title = "CALL TOTEM BAR",
            key = "callTotemBar", unlockKey = "ERB_CallTotemBar",
            off = function()
                local p = DB()
                local c = p and p.callTotemBar
                return not (c and c.enabled)
            end,
            req = "Call Totem Bar",
            enableRow = function(ry, sizeCfg, RefreshTotem)
                return W:DualRow(parent, ry,
                    { type = "toggle", text = "Enable Call Totem Bar",
                      tooltip = "Reskins Blizzard's call totem bar in this look and moves it with Unlock Mode instead of Edit Mode.",
                      getValue = function()
                          local p = DB()
                          local c = p and p.callTotemBar
                          return c and c.enabled == true or false
                      end,
                      setValue = function(v)
                          local p = DB()
                          local c = p and p.callTotemBar
                          if not c then return end
                          c.enabled = v
                          RefreshTotem()
                          EllesmereUI:RefreshPage()
                      end },
                    sizeCfg)
            end,
        })
    end

    return math.abs(y)
end
