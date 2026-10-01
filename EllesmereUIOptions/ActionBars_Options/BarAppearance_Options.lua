if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarAppearance_Options.lua
--  Action Bars options: the Bar Background, Icon Appearance, Icon Effects,
--  Paging and Text sections of the Bar Display page. Called by
--  BuildSharedBarSettings for bars that are not visibility-only; returns y and
--  the rows its click navigation maps to. Shared helpers come from
--  ns._ABO_OptEnv, the per-build helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local function BuildBarAppearance(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local EAB, GROUP_BAR_ORDER, InCombatLockdown, PP = env.EAB, env.GROUP_BAR_ORDER, env.InCombatLockdown, env.PP
    local SB, SECTION_ICON_APPEARANCE, SECTION_TEXT, SelectedKey = env.SB, env.SECTION_ICON_APPEARANCE, env.SECTION_TEXT, env.SelectedKey
    local SHORT_LABELS, ShownBorderDefaults, TEXT_ANCHOR_DROPDOWN_ORDER, TEXT_ANCHOR_LABELS = env.SHORT_LABELS, env.ShownBorderDefaults, env.TEXT_ANCHOR_DROPDOWN_ORDER, env.TEXT_ANCHOR_LABELS
    local BgDisabled, SGet, SSeedTextOffsets, SSet = ctx.BgDisabled, ctx.SGet, ctx.SSeedTextOffsets, ctx.SSet
    local SSetColor, SUpdatePreview, SUpdatePreviewAndResize, SVal = ctx.SSetColor, ctx.SUpdatePreview, ctx.SUpdatePreviewAndResize, ctx.SVal
    local W = ctx.W
    local _, h
    local row
    -- Row / section references for click-navigation (returned to BuildSharedBarSettings)
    local iconsSectionHeader, textSectionHeader
    local keybindRow, chargesRow

    -- Called later, directly below ICON EFFECTS; defined here to share the page helpers (ctx) instead of duplicating them.
    local function BuildBarBackgroundSection()
    -------------------------------------------------------------------
    --  BAR BACKGROUND
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BAR BACKGROUND", y);  y = y - h

    local bgOptionsRow
    bgOptionsRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Bar Background",
          getValue=function() return SVal("bgEnabled", false) end,
          -- Section gate: rows below are hidden (not grayed) while off; the wrapper forces the page rebuild.
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              SSet("bgEnabled", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreview()
          end) },
        { type="slider", text="Spacing", min=0, max=20, step=1,
          disabled=BgDisabled,
          disabledTooltip="Bar Background",
          getValue=function()
              local v = SGet("bgPadding")
              if v ~= nil then return v end
              return math.max(SVal("bgPadX", 0), SVal("bgPadY", 0))
          end,
          setValue=function(v)
              SB().bgPadX, SB().bgPadY = nil, nil
              SSet("bgPadding", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreview()
          end });  y = y - h

    do
        local region = bgOptionsRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region=region,
            tooltip="Apply Bar Background Enable to all Bars",
            onClick=function()
                local enabled = SVal("bgEnabled", false)
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].bgEnabled = enabled
                    EAB:ApplyBackgroundForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced=function()
                local enabled = SVal("bgEnabled", false)
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].bgEnabled or false) ~= enabled then return false end
                end
                return true
            end,
            flashTargets=function() return { region } end,
            multiApply={
                elementKeys=GROUP_BAR_ORDER,
                elementLabels=SHORT_LABELS,
                getCurrentKey=function() return SelectedKey() end,
                onApply=function(checkedKeys)
                    local enabled = SVal("bgEnabled", false)
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].bgEnabled = enabled
                        EAB:ApplyBackgroundForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local region = bgOptionsRow._rightRegion
        local function CurrentSpacing(settings)
            if settings.bgPadding ~= nil then return settings.bgPadding end
            return math.max(settings.bgPadX or 0, settings.bgPadY or 0)
        end
        local function ApplySpacingTo(key)
            local target = EAB.db.profile.bars[key]
            target.bgPadding = CurrentSpacing(SB())
            target.bgPadX = nil
            target.bgPadY = nil
            EAB:ApplyBackgroundForBar(key)
        end
        EllesmereUI.BuildSyncIcon({
            region=region,
            tooltip="Apply Bar Background Spacing to all Bars",
            onClick=function()
                for _, key in ipairs(GROUP_BAR_ORDER) do ApplySpacingTo(key) end
                EllesmereUI:RefreshPage()
            end,
            isSynced=function()
                local spacing = CurrentSpacing(SB())
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if CurrentSpacing(EAB.db.profile.bars[key]) ~= spacing then return false end
                end
                return true
            end,
            flashTargets=function() return { region } end,
            multiApply={
                elementKeys=GROUP_BAR_ORDER,
                elementLabels=SHORT_LABELS,
                getCurrentKey=function() return SelectedKey() end,
                onApply=function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do ApplySpacingTo(key) end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    local function BackgroundOpacity(settings)
        if settings.bgOpacity ~= nil then return settings.bgOpacity end
        local color = settings.bgColor
        return ((color and color.a) or 0.5) * 100
    end

    -- Section gate: everything below the master row is built only while Bar Background is
    -- enabled for the selected bar (Enable toggle's SectionToggleSetValue rebuilds on flip).
    if SVal("bgEnabled", false) then

    local bgColorRow
    bgColorRow, h = W:DualRow(parent, y,
        { type="colorpicker", text="Background Color", hasAlpha=false,
          disabled=BgDisabled,
          disabledTooltip="Bar Background",
          getValue=function()
              local c = SGet("bgColor") or { r=0, g=0, b=0, a=0.5 }
              return c.r, c.g, c.b, 1
          end,
          setValue=function(r, g, b)
              local old = SGet("bgColor") or { a=0.5 }
              SSetColor("bgColor", r, g, b, old.a or 0.5,
                  function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Background Opacity", min=0, max=100, step=1,
          disabled=BgDisabled,
          disabledTooltip="Bar Background",
          getValue=function() return BackgroundOpacity(SB()) end,
          setValue=function(v)
              SSet("bgOpacity", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreview()
          end });  y = y - h

    do
        local region = bgColorRow._leftRegion
        local function ApplyColorTo(key)
            local source = SGet("bgColor") or { r=0, g=0, b=0, a=0.5 }
            local target = EAB.db.profile.bars[key]
            local old = target.bgColor
            target.bgColor = { r=source.r, g=source.g, b=source.b,
                a=(old and old.a) or source.a or 0.5 }
            EAB:ApplyBackgroundForBar(key)
        end
        EllesmereUI.BuildSyncIcon({
            region=region,
            tooltip="Apply Background Color to all Bars",
            onClick=function()
                for _, key in ipairs(GROUP_BAR_ORDER) do ApplyColorTo(key) end
                EllesmereUI:RefreshPage()
            end,
            isSynced=function()
                local color = SGet("bgColor") or { r=0, g=0, b=0 }
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local target = EAB.db.profile.bars[key].bgColor or { r=0, g=0, b=0 }
                    if target.r ~= color.r or target.g ~= color.g or target.b ~= color.b then
                        return false
                    end
                end
                return true
            end,
            flashTargets=function() return { region } end,
            multiApply={
                elementKeys=GROUP_BAR_ORDER,
                elementLabels=SHORT_LABELS,
                getCurrentKey=function() return SelectedKey() end,
                onApply=function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do ApplyColorTo(key) end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local region = bgColorRow._rightRegion
        local function ApplyOpacityTo(key)
            local target = EAB.db.profile.bars[key]
            target.bgOpacity = BackgroundOpacity(SB())
            EAB:ApplyBackgroundForBar(key)
        end
        EllesmereUI.BuildSyncIcon({
            region=region,
            tooltip="Apply Background Opacity to all Bars",
            onClick=function()
                for _, key in ipairs(GROUP_BAR_ORDER) do ApplyOpacityTo(key) end
                EllesmereUI:RefreshPage()
            end,
            isSynced=function()
                local opacity = BackgroundOpacity(SB())
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if BackgroundOpacity(EAB.db.profile.bars[key]) ~= opacity then return false end
                end
                return true
            end,
            flashTargets=function() return { region } end,
            multiApply={
                elementKeys=GROUP_BAR_ORDER,
                elementLabels=SHORT_LABELS,
                getCurrentKey=function() return SelectedKey() end,
                onApply=function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do ApplyOpacityTo(key) end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local bgBorderRow
        bgBorderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              disabled=BgDisabled,
              disabledTooltip="Bar Background Border",
              values=texValues, order=texOrder,
              getValue=function() return SVal("bgBorderTexture", "solid") end,
              setValue=function(v)
                  local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  SSet("bgBorderTexture", v, function(k)
                      local settings = EAB.db.profile.bars[k]
                      settings.bgBorderOffsetX = nil
                      settings.bgBorderOffsetY = nil
                      settings.bgBorderShiftX = nil
                      settings.bgBorderShiftY = nil
                      -- A style pick resets the border: a set exact size goes with it (false travels, nil would not).
                      if settings.bgBorderThicknessPx then settings.bgBorderThicknessPx = false end
                      settings.bgBorderBehind = behind
                      settings.bgBorderColor = { r=color.r, g=color.g, b=color.b, a=1 }
                      EAB:ApplyBackgroundForBar(k)
                  end)
                  SUpdatePreview()
                  -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                  EllesmereUI:RefreshPage(true)
              end },
            EllesmereUI.BorderPxSliderCfg{ text="Border Size",
              disabled=BgDisabled,
              disabledTooltip="Bar Background Border",
              -- The step ApplyBackgroundForBar renders with: a thickness with no
              -- entry (unknown, or the number an old SharedMedia pick stored) is 0, hidden.
              getStep=function()
                  local entry = ns.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                  return entry and entry.regular or 0
              end,
              setStep=function(step) SB().bgBorderThickness = EllesmereUI.BORDER_LABEL_OF_STEP[step] end,
              getTex=function() return SVal("bgBorderTexture", "solid") end,
              getPx=function() return SGet("bgBorderThicknessPx") end,
              setPx=function(v) SB().bgBorderThicknessPx = v end,
              apply=function()
                  EAB:ApplyBackgroundForBar(SelectedKey())
                  EllesmereUI:RefreshPage()
                  SUpdatePreview()
              end });  y = y - h

        -- Width Offset | Height Offset: the textured border's outward offsets, their
        -- own row while a textured style is selected (Solid has none; the style
        -- setter rebuilds the page). Shown = the override, else the "actionbars"
        -- registry default for the thickness key ApplyBackgroundForBar passes.
        do
            local bgTex = SVal("bgBorderTexture", "solid")
            if bgTex ~= "" and bgTex ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                    addonKey="actionbars",
                    disabled=BgDisabled,
                    disabledTooltip="Bar Background Border",
                    getTex=function() return SVal("bgBorderTexture", "solid") end,
                    getStep=function()
                        local entry = ns.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                        return entry and entry.regular or 0
                    end,
                    getSizeKey=function() return SVal("bgBorderThickness", "none") end,
                    getPx=function() return SGet("bgBorderThicknessPx") end,
                    getX=function() return SGet("bgBorderOffsetX") end,
                    setX=function(v) SB().bgBorderOffsetX = v end,
                    getY=function() return SGet("bgBorderOffsetY") end,
                    setY=function(v) SB().bgBorderOffsetY = v end,
                    apply=function()
                        EAB:ApplyBackgroundForBar(SelectedKey())
                        EllesmereUI:RefreshPage()
                        SUpdatePreview()
                    end }
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end

        do
            local region = bgBorderRow._rightRegion
            local borderSwatch, refreshBorder = EllesmereUI.BuildColorSwatch(region, region:GetFrameLevel() + 5,
                function()
                    local c = SGet("bgBorderColor") or { r=0, g=0, b=0, a=1 }
                    return c.r, c.g, c.b, c.a
                end,
                function(r, g, b, a)
                    SSetColor("bgBorderColor", r, g, b, a, function(k) EAB:ApplyBackgroundForBar(k) end)
                    SUpdatePreview()
            end, true, 20)
            PP.Point(borderSwatch, "RIGHT", region._control, "LEFT", -12, 0)
            region._lastInline = borderSwatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local disabled = BgDisabled() or SVal("bgBorderThickness", "none") == "none"
                borderSwatch:SetAlpha(disabled and 0.15 or 1)
                refreshBorder()
            end)
        end

        do
            local region = bgBorderRow._rightRegion
            local function ApplySizeTo(key)
                local source = SB()
                local target = EAB.db.profile.bars[key]
                target.bgBorderThickness = source.bgBorderThickness
                do
                    local v = source.bgBorderThicknessPx
                    if v == nil and target.bgBorderThicknessPx ~= nil then v = false end
                    target.bgBorderThicknessPx = v
                end
                local color = source.bgBorderColor
                if color then
                    target.bgBorderColor = { r=color.r, g=color.g, b=color.b, a=color.a }
                end
                EAB:ApplyBackgroundForBar(key)
            end
            EllesmereUI.BuildSyncIcon({
                region=region,
                tooltip="Apply Background Border Size and Color to all Bars",
                onClick=function()
                    for _, key in ipairs(GROUP_BAR_ORDER) do ApplySizeTo(key) end
                    EllesmereUI:RefreshPage()
                end,
                isSynced=function()
                    local thickness = SVal("bgBorderThickness", "none")
                    local thicknessPx = SGet("bgBorderThicknessPx") or false   -- nil and false render alike
                    local color = SGet("bgBorderColor") or { r=0, g=0, b=0, a=1 }
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local target = EAB.db.profile.bars[key]
                        if (target.bgBorderThickness or "none") ~= thickness then return false end
                        if (target.bgBorderThicknessPx or false) ~= thicknessPx then return false end
                        local targetColor = target.bgBorderColor or { r=0, g=0, b=0, a=1 }
                        if targetColor.r ~= color.r or targetColor.g ~= color.g
                            or targetColor.b ~= color.b or targetColor.a ~= color.a then return false end
                    end
                    return true
                end,
                flashTargets=function() return { region } end,
                multiApply={
                    elementKeys=GROUP_BAR_ORDER,
                    elementLabels=SHORT_LABELS,
                    getCurrentKey=function() return SelectedKey() end,
                    onApply=function(checkedKeys)
                        for _, key in ipairs(checkedKeys) do ApplySizeTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        do
            local region = bgBorderRow._leftRegion
            -- The offsets/shifts the background border renders with when none is
            -- set: its registry defaults (looked up as before), scaled to an exact
            -- size when one is set, as ApplyBackgroundForBar draws them.
            local function BgBorderDefaults()
                local texture = SVal("bgBorderTexture", "solid")
                local thickness = SVal("bgBorderThickness", "thin")
                local entry = ns.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                local step = entry and entry.regular or 0
                local px = EllesmereUI.BorderPx(SGet("bgBorderThicknessPx"), step, texture)
                return ShownBorderDefaults(texture, thickness, step, px)
            end
            local offsetButton = EllesmereUI.BuildInlineCog(region, {
                icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = region._control,
                title="Border Options",
                captureRegion=region,
                rows={
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                          local value = SGet("bgBorderShiftX")
                          if value ~= nil then return value end
                          local _, _, defaultX = BgBorderDefaults()
                          return defaultX
                      end,
                      set=function(v)
                          -- The shift shown by default stores nil (follow the style again).
                          local _, _, defaultX = BgBorderDefaults()
                          if v == math.floor(defaultX + 0.5) then v = nil end
                          SSet("bgBorderShiftX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                          SUpdatePreview()
                      end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                          local value = SGet("bgBorderShiftY")
                          if value ~= nil then return value end
                          local _, _, _, defaultY = BgBorderDefaults()
                          return defaultY
                      end,
                      set=function(v)
                          local _, _, _, defaultY = BgBorderDefaults()
                          if v == math.floor(defaultY + 0.5) then v = nil end
                          SSet("bgBorderShiftY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                          SUpdatePreview()
                      end },
                    { type="toggle", label="Show Behind",
                      get=function() return SVal("bgBorderBehind", false) end,
                      set=function(v)
                          SSet("bgBorderBehind", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                          SUpdatePreview()
                      end },
                },
            })
            if offsetButton then
                local function UpdateOffsetButton()
                    offsetButton:SetShown(not BgDisabled())
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateOffsetButton)
                UpdateOffsetButton()
            end
        end

        do
            local region = bgBorderRow._leftRegion
            local function ApplyStyleTo(key)
                local source = SB()
                local target = EAB.db.profile.bars[key]
                target.bgBorderTexture = source.bgBorderTexture
                target.bgBorderOffsetX = source.bgBorderOffsetX
                target.bgBorderOffsetY = source.bgBorderOffsetY
                target.bgBorderShiftX = source.bgBorderShiftX
                target.bgBorderShiftY = source.bgBorderShiftY
                target.bgBorderBehind = source.bgBorderBehind
                EAB:ApplyBackgroundForBar(key)
            end
            EllesmereUI.BuildSyncIcon({
                region=region,
                tooltip="Apply Background Border Style to all Bars",
                onClick=function()
                    for _, key in ipairs(GROUP_BAR_ORDER) do ApplyStyleTo(key) end
                    EllesmereUI:RefreshPage()
                end,
                isSynced=function()
                    local source = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local target = EAB.db.profile.bars[key]
                        if (target.bgBorderTexture or "solid") ~= (source.bgBorderTexture or "solid") then return false end
                        if target.bgBorderOffsetX ~= source.bgBorderOffsetX then return false end
                        if target.bgBorderOffsetY ~= source.bgBorderOffsetY then return false end
                        if target.bgBorderShiftX ~= source.bgBorderShiftX then return false end
                        if target.bgBorderShiftY ~= source.bgBorderShiftY then return false end
                        if (target.bgBorderBehind or false) ~= (source.bgBorderBehind or false) then return false end
                    end
                    return true
                end,
                flashTargets=function() return { region } end,
                multiApply={
                    elementKeys=GROUP_BAR_ORDER,
                    elementLabels=SHORT_LABELS,
                    getCurrentKey=function() return SelectedKey() end,
                    onApply=function(checkedKeys)
                        for _, key in ipairs(checkedKeys) do ApplyStyleTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
    end

    local bgMultiplierRow
    bgMultiplierRow, h = W:DualRow(parent, y,
        { type="slider", text="Multiplier X", min=1, max=4, step=1,
          disabled=BgDisabled,
          disabledTooltip="Bar Background",
          getValue=function() return SVal("bgMultiplierX", 1) end,
          setValue=function(v)
              SSet("bgMultiplierX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreviewAndResize()
          end },
        { type="slider", text="Multiplier Y", min=1, max=4, step=1,
          disabled=BgDisabled,
          disabledTooltip="Bar Background",
          getValue=function() return SVal("bgMultiplierY", 1) end,
          setValue=function(v)
              SSet("bgMultiplierY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreviewAndResize()
          end });  y = y - h

    do
        local region = bgMultiplierRow._leftRegion
        EllesmereUI.BuildInlineCog(region, { icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = region._control,
            title="Multiplier X Settings",
            captureRegion=region,
            rows={{ type="dropdown", label="Growth Direction",
                values={ left="Left", right="Right" }, order={ "left", "right" },
                get=function() return SVal("bgExpandDirectionX", "right") end,
                set=function(v)
                    SSet("bgExpandDirectionX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                    SUpdatePreviewAndResize()
                end }},
        })
    end

    do
        local region = bgMultiplierRow._rightRegion
        EllesmereUI.BuildInlineCog(region, { icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = region._control,
            title="Multiplier Y Settings",
            captureRegion=region,
            rows={{ type="dropdown", label="Growth Direction",
                values={ up="Up", down="Down" }, order={ "up", "down" },
                get=function() return SVal("bgExpandDirectionY", "up") end,
                set=function(v)
                    SSet("bgExpandDirectionY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                    SUpdatePreviewAndResize()
                end }},
        })
    end

    end -- bgEnabled section gate
    end

    -------------------------------------------------------------------
    --  ICON APPEARANCE
    -------------------------------------------------------------------
    iconsSectionHeader, h = W:SectionHeader(parent, SECTION_ICON_APPEARANCE, y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "actionbars")

    -- Stock mode (Blizzard Style or Classic WoW UI): the shared gate.
    local function BlizzStyleOn()
        return EllesmereUI.BlizzStyle.Get("actionbars")
    end

    -- "No custom shape" also covers "cropped" and unset.
    local function ShapeIsNone()
        local v = SGet("buttonShape")
        return v == "none" or v == "cropped" or v == nil
    end
    local function ShapeIsCustom()
        return not ShapeIsNone()
    end

    local SHAPE_VALUES = {
        none     = "None",
        cropped  = "Cropped",
        square   = "Square",
        circle   = "Circle",
        csquare  = "Curved Square",
        diamond  = "Diamond",
        hexagon  = "Hexagon",
        portrait = "Portrait",
        shield   = "Shield",
    }
    local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

    local abBsRow
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        -- Border Size: a custom shape's ring is on/off, so it keeps the None/Strong
        -- dropdown; every other shape gets the pixel slider over the same key and
        -- its borderThicknessPx companion. The shape setter rebuilds the page so the
        -- slot follows the shape; a bar switch already rebuilds.
        local sizeCfg
        if ShapeIsCustom() then
            sizeCfg = { type="dropdown", text="Border Size",
              disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
              values=ns.BORDER_THICKNESS_LABELS, order=ns.BORDER_THICKNESS_ORDER,
              itemDisabled=function(val)
                  if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then return true end
                  return false
              end,
              itemDisabledTooltip=function(val)
                  if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then
                      return "This option requires a non-custom shape to be selected"
                  end
              end,
              getValue=function()
                  local v = SGet("borderThickness")
                  return v or "thin"
              end,
              setValue=function(v)
                  SSet("borderThickness", v, function(k)
                      local entry = ns.BORDER_THICKNESS[v]
                      if entry then
                          local shape = EAB.db.profile.bars[k].buttonShape or "none"
                          if shape ~= "none" and shape ~= "cropped" then
                              EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                              EAB.db.profile.bars[k].shapeBorderEnabled = entry.shape > 0
                          else
                              EAB.db.profile.bars[k].borderSize = entry.regular
                              EAB.db.profile.bars[k].borderEnabled = entry.regular > 0
                          end
                      end
                      EAB:ApplyBordersForBar(k)
                      EAB:ApplyShapesForBar(k)
                  end)
                  SUpdatePreview()
              end }
        else
            sizeCfg = EllesmereUI.BorderPxSliderCfg{ text="Border Size",
              disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
              -- The step the buttons render with (ResolveBorderThickness's regular
              -- column): an unknown or numeric thickness is thin.
              getStep=function()
                  local entry = ns.BORDER_THICKNESS[SGet("borderThickness") or "thin"] or ns.BORDER_THICKNESS.thin
                  return entry.regular
              end,
              -- Exactly what the dropdown wrote for a non-custom shape: the label and its mirrors.
              setStep=function(step)
                  local s = SB()
                  local label = EllesmereUI.BORDER_LABEL_OF_STEP[step]
                  s.borderThickness = label
                  local entry = ns.BORDER_THICKNESS[label]
                  if entry then
                      s.borderSize = entry.regular
                      s.borderEnabled = entry.regular > 0
                  end
              end,
              getTex=function() return SGet("borderTexture") or "solid" end,
              getPx=function() return SGet("borderThicknessPx") end,
              setPx=function(v) SB().borderThicknessPx = v end,
              apply=function()
                  local k = SelectedKey()
                  EAB:ApplyBordersForBar(k)
                  EAB:ApplyShapesForBar(k)
                  EllesmereUI:RefreshPage()
                  SUpdatePreview()
              end }
        end
        abBsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("actionbars", { type="dropdown", text="Border Style",
              disabled=function() return BlizzStyleOn() or ShapeIsCustom() end,
              disabledTooltip=function() if ShapeIsCustom() then return "This option requires a non-custom button shape" end return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled") end,
              rawTooltip=true,
              values=texValues, order=texOrder,
              getValue=function() return SGet("borderTexture") or "solid" end,
              setValue=function(v)
                  local defTh = EllesmereUI.GetBorderDefaultSize("actionbars", v)
                  -- An unregistered SharedMedia border answers the NUMBER 1; this key stores labels.
                  if type(defTh) == "number" then defTh = EllesmereUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                  SSet("borderTexture", v, function(k)
                      EAB.db.profile.bars[k].borderTextureOffset = nil
                      EAB.db.profile.bars[k].borderTextureOffsetY = nil
                      EAB.db.profile.bars[k].borderTextureShiftX = nil
                      EAB.db.profile.bars[k].borderTextureShiftY = nil
                      -- A style pick resets the size to the style's default: a set exact size goes with it (false travels, nil would not).
                      if EAB.db.profile.bars[k].borderThicknessPx then EAB.db.profile.bars[k].borderThicknessPx = false end
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      EAB.db.profile.bars[k].borderColor = { r = _bcol.r, g = _bcol.g, b = _bcol.b, a = 1 }
                      EAB.db.profile.bars[k].borderClassColor = false
                      EAB.db.profile.bars[k].borderBehind = _bbehind
                      if defTh then
                          EAB.db.profile.bars[k].borderThickness = defTh
                          local entry = ns.BORDER_THICKNESS[defTh]
                          if entry then
                              local shape = EAB.db.profile.bars[k].buttonShape or "none"
                              if shape ~= "none" and shape ~= "cropped" then
                                  EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                                  EAB.db.profile.bars[k].shapeBorderEnabled = entry.shape > 0
                              else
                                  EAB.db.profile.bars[k].borderSize = entry.regular
                                  EAB.db.profile.bars[k].borderEnabled = entry.regular > 0
                              end
                          end
                      end
                      EAB:ApplyBordersForBar(k)
                      EAB:ApplyShapesForBar(k)
                  end)
                  SUpdatePreview()
                  -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                  EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("actionbars", sizeCfg));  y = y - h
        -- Width Offset | Height Offset: the textured border's outward offsets, their
        -- own row while a textured style is selected (Solid has none; the style
        -- setter rebuilds the page). Shown = the override, else the "actionbars"
        -- registry default for the step and thickness key ApplyBordersForBar and the
        -- shape repaint pass (ResolveBorderThickness), scaled to an exact size as drawn.
        do
            local btnTex = SGet("borderTexture") or "solid"
            if btnTex ~= "" and btnTex ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                    addonKey="actionbars",
                    disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
                    getTex=function() return SGet("borderTexture") or "solid" end,
                    getStep=function() return (ns.ResolveBorderThickness(SB())) end,
                    getSizeKey=function() return SGet("borderThickness") or "thin" end,
                    getPx=function() return SGet("borderThicknessPx") end,
                    getX=function() return SGet("borderTextureOffset") end,
                    setX=function(v) SB().borderTextureOffset = v end,
                    getY=function() return SGet("borderTextureOffsetY") end,
                    setY=function(v) SB().borderTextureOffsetY = v end,
                    apply=function()
                        EAB:ApplyBordersForBar(SelectedKey())
                        EllesmereUI:RefreshPage()
                        SUpdatePreview()
                    end }
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("actionbars", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("actionbars", ocfgR));  y = y - h
            end
        end
        do
            local rgn = abBsRow._leftRegion
            -- The offsets/shifts the buttons render with when none is set: the
            -- step's registry defaults (looked up as before), scaled to an exact
            -- size when one is set, as ApplyButtonBorders draws them.
            local function ButtonBorderDefaults()
                local tex = SGet("borderTexture") or "solid"
                local th = SGet("borderThickness") or "thin"
                local step, px = ns.ResolveBorderThickness(SB())
                return ShownBorderDefaults(tex, th, step, px)
            end
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
                icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = rgn._control,
                title = "Border Options",
                captureRegion = rgn,
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureShiftX")
                          if v then return v end
                          local _, _, dsx = ButtonBorderDefaults()
                          return dsx
                      end,
                      set = function(v)
                          -- The shift shown by default stores nil (follow the style again).
                          local _, _, dsx = ButtonBorderDefaults()
                          if v == math.floor(dsx + 0.5) then v = nil end
                          SSet("borderTextureShiftX", v, function(k)
                              EAB:ApplyBordersForBar(k)
                          end)
                          SUpdatePreview()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = SGet("borderTextureShiftY")
                          if v then return v end
                          local _, _, _, dsy = ButtonBorderDefaults()
                          return dsy
                      end,
                      set = function(v)
                          local _, _, _, dsy = ButtonBorderDefaults()
                          if v == math.floor(dsy + 0.5) then v = nil end
                          SSet("borderTextureShiftY", v, function(k)
                              EAB:ApplyBordersForBar(k)
                          end)
                          SUpdatePreview()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() return SGet("borderBehind") or false end,
                      set = function(v)
                          SSet("borderBehind", v == false and nil or v, function(k)
                              EAB:ApplyBordersForBar(k)
                          end)
                          SUpdatePreview(); EllesmereUI:RefreshPage()
                      end },
                    -- The inverse of Show Behind, which wins: the runtime
                    -- ignores this flag while Show Behind is on.
                    { type = "toggle", label = "Border Above Effects",
                      tooltip = "Draws this bar's button borders over proc glows, the assisted highlight and the cooldown swipe.",
                      disabled = function()
                          return BlizzStyleOn() or ShapeIsCustom() or (SGet("borderBehind") and true or false)
                      end,
                      disabledTooltip = function()
                          if BlizzStyleOn() then return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled") end
                          if ShapeIsCustom() then return "This option requires a non-custom button shape" end
                          return EllesmereUI.DisabledTooltip("Show Behind", "disabled")
                      end,
                      rawTooltip = true,
                      get = function() return SGet("borderAboveEffects") or false end,
                      set = function(v)
                          SSet("borderAboveEffects", v and true or false, function(k)
                              EAB:ApplyBordersForBar(k)
                          end)
                          SUpdatePreview()
                      end },
                },
            })
            if cogBtn then
                local function UpdateCogVis()
                    cogBtn:SetShown((SGet("borderTexture") or "solid") ~= "solid")
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end
        local bsLeftRgn = abBsRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = bsLeftRgn,
            tooltip = "Apply Border Style to all Bars",
            onClick = function()
                local bt = SB().borderTexture or "solid"
                local ox = SB().borderTextureOffset
                local oy = SB().borderTextureOffsetY
                local sx = SB().borderTextureShiftX
                local sy = SB().borderTextureShiftY
                local bh = SB().borderBehind
                local ba = SB().borderAboveEffects
                local bc = SB().borderColor
                local bcc = SB().borderClassColor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].borderTexture = bt
                    EAB.db.profile.bars[key].borderTextureOffset = ox
                    EAB.db.profile.bars[key].borderTextureOffsetY = oy
                    EAB.db.profile.bars[key].borderTextureShiftX = sx
                    EAB.db.profile.bars[key].borderTextureShiftY = sy
                    EAB.db.profile.bars[key].borderBehind = bh
                    EAB.db.profile.bars[key].borderAboveEffects = ba
                    if bc then EAB.db.profile.bars[key].borderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                    EAB.db.profile.bars[key].borderClassColor = bcc
                    EAB:ApplyBordersForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local bt = SB().borderTexture or "solid"
                local ox = SB().borderTextureOffset
                local oy = SB().borderTextureOffsetY
                local sx = SB().borderTextureShiftX
                local sy = SB().borderTextureShiftY
                local bh = SB().borderBehind or false
                local ba = SB().borderAboveEffects or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].borderTexture or "solid") ~= bt then return false end
                    if EAB.db.profile.bars[key].borderTextureOffset ~= ox then return false end
                    if EAB.db.profile.bars[key].borderTextureOffsetY ~= oy then return false end
                    if EAB.db.profile.bars[key].borderTextureShiftX ~= sx then return false end
                    if EAB.db.profile.bars[key].borderTextureShiftY ~= sy then return false end
                    if (EAB.db.profile.bars[key].borderBehind or false) ~= bh then return false end
                    if (EAB.db.profile.bars[key].borderAboveEffects or false) ~= ba then return false end
                end
                return true
            end,
            flashTargets = function() return { bsLeftRgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local bt = SB().borderTexture or "solid"
                    local ox = SB().borderTextureOffset
                    local oy = SB().borderTextureOffsetY
                    local sx = SB().borderTextureShiftX
                    local sy = SB().borderTextureShiftY
                    local bh = SB().borderBehind
                    local ba = SB().borderAboveEffects
                    local bc = SB().borderColor
                    local bcc = SB().borderClassColor
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].borderTexture = bt
                        EAB.db.profile.bars[key].borderTextureOffset = ox
                        EAB.db.profile.bars[key].borderTextureOffsetY = oy
                        EAB.db.profile.bars[key].borderTextureShiftX = sx
                        EAB.db.profile.bars[key].borderTextureShiftY = sy
                        EAB.db.profile.bars[key].borderBehind = bh
                        EAB.db.profile.bars[key].borderAboveEffects = ba
                        if bc then EAB.db.profile.bars[key].borderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                        EAB.db.profile.bars[key].borderClassColor = bcc
                        EAB:ApplyBordersForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rightRgn = abBsRow._rightRegion
        local ctrl = rightRgn._control

        local classBorderSwatch, updateClassBorderSwatch = EllesmereUI.BuildColorSwatch(
            rightRgn, abBsRow:GetFrameLevel() + 3,
            function()
                local _, ct = UnitClass("player")
                local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end,
            false, 20)
        PP.Point(classBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        classBorderSwatch:SetScript("OnClick", function()
            SSet("borderClassColor", true, function(k)
                EAB:ApplyBordersForBar(k)
                EAB:ApplyShapesForBar(k)
            end)
            SUpdatePreview()
            EllesmereUI:RefreshPage()
        end)
        classBorderSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(classBorderSwatch, "Class Colored")
        end)
        classBorderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        local customSwatch, updateCustomSwatch = EllesmereUI.BuildColorSwatch(
            rightRgn, abBsRow:GetFrameLevel() + 3,
            function()
                local c = SGet("borderColor")
                if not c then return 0, 0, 0 end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("borderColor", r, g, b, nil, function(k)
                    EAB:ApplyBordersForBar(k)
                    EAB:ApplyShapesForBar(k)
                end)
                SSetColor("shapeBorderColor", r, g, b, nil, function(k)
                    EAB:ApplyShapesForBar(k)
                end)
                SUpdatePreview()
            end,
            false, 20)
        PP.Point(customSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
        customSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
        end)
        customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        -- Click the dimmed custom swatch to switch back from class color (no block overlay)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if SGet("borderClassColor") then
                SSet("borderClassColor", false, function(k)
                    EAB:ApplyBordersForBar(k)
                    EAB:ApplyShapesForBar(k)
                end)
                SUpdatePreview()
                EllesmereUI:RefreshPage()
                return
            end
            -- No border selected: allow swapping boxes but do not open the color picker
            if (SGet("borderThickness") or "thin") == "none" then return end
            if origClick then origClick(self, ...) end
        end)

        local function UpdateBorderSwatchState()
            local isClassColored = SGet("borderClassColor")
            local isNone = (SGet("borderThickness") or "thin") == "none"
            customSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
            classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
        end
        EllesmereUI.RegisterWidgetRefresh(function() updateCustomSwatch(); updateClassBorderSwatch(); UpdateBorderSwatchState() end)
        UpdateBorderSwatchState()
    end

    do
        local rgn = abBsRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Border Size and Color to all Bars",
            onClick = function()
                local th = SB().borderThickness
                local thPx = SB().borderThicknessPx   -- copied as is (string, false or nil)
                local c = SB().borderColor
                local cc = SB().borderClassColor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].borderThickness = th
                    do
                        local t = EAB.db.profile.bars[key]
                        local v = thPx
                        if v == nil and t.borderThicknessPx ~= nil then v = false end
                        t.borderThicknessPx = v
                    end
                    local entry = ns.BORDER_THICKNESS[th]
                    if entry then
                        local shape = EAB.db.profile.bars[key].buttonShape or "none"
                        if shape ~= "none" and shape ~= "cropped" then
                            EAB.db.profile.bars[key].shapeBorderSize = entry.shape
                            EAB.db.profile.bars[key].shapeBorderEnabled = entry.shape > 0
                        else
                            EAB.db.profile.bars[key].borderSize = entry.regular
                            EAB.db.profile.bars[key].borderEnabled = entry.regular > 0
                        end
                    end
                    if c then
                        EAB.db.profile.bars[key].borderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                        EAB.db.profile.bars[key].shapeBorderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                    end
                    EAB.db.profile.bars[key].borderClassColor = cc
                    EAB:ApplyBordersForBar(key)
                    EAB:ApplyShapesForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local th = SB().borderThickness or "thin"
                local thPx = SB().borderThicknessPx or false   -- nil and false render alike
                local cc = SB().borderClassColor or false
                local c = SB().borderColor
                local cr, cg, cb, ca = c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 1
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].borderThickness or "thin") ~= th then return false end
                    if (EAB.db.profile.bars[key].borderThicknessPx or false) ~= thPx then return false end
                    if (EAB.db.profile.bars[key].borderClassColor or false) ~= cc then return false end
                    local bc = EAB.db.profile.bars[key].borderColor
                    if (bc and bc.r or 0) ~= cr or (bc and bc.g or 0) ~= cg or (bc and bc.b or 0) ~= cb or (bc and bc.a or 1) ~= ca then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local th = SB().borderThickness
                    local thPx = SB().borderThicknessPx   -- copied as is (string, false or nil)
                    local c = SB().borderColor
                    local cc = SB().borderClassColor
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].borderThickness = th
                        do
                        local t = EAB.db.profile.bars[key]
                        local v = thPx
                        if v == nil and t.borderThicknessPx ~= nil then v = false end
                        t.borderThicknessPx = v
                    end
                        local entry = ns.BORDER_THICKNESS[th]
                        if entry then
                            local shape = EAB.db.profile.bars[key].buttonShape or "none"
                            if shape ~= "none" and shape ~= "cropped" then
                                EAB.db.profile.bars[key].shapeBorderSize = entry.shape
                                EAB.db.profile.bars[key].shapeBorderEnabled = entry.shape > 0
                            else
                                EAB.db.profile.bars[key].borderSize = entry.regular
                                EAB.db.profile.bars[key].borderEnabled = entry.regular > 0
                            end
                        end
                        if c then
                            EAB.db.profile.bars[key].borderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                            EAB.db.profile.bars[key].shapeBorderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                        end
                        EAB.db.profile.bars[key].borderClassColor = cc
                        EAB:ApplyBordersForBar(key)
                        EAB:ApplyShapesForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    local classColorBorderRow
    classColorBorderRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("actionbars", { type="dropdown", text="Custom Button Shape",
          disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
          values=SHAPE_VALUES, order=SHAPE_ORDER,
          itemDisabled=function(val)
              if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then return true end
              return false
          end,
          itemDisabledTooltip=function(val)
              if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then
                  return "This option requires the Border Style to be set to Solid"
              end
          end,
          getValue=function()
              local v = SGet("buttonShape")
              return v or "none"
          end,
          setValue=function(v)
              -- Set icon zoom BEFORE shapes: ApplyShapesForBar -> ApplyShapeToButton reads the new value.
              SSet("iconZoom", ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5)
              SSet("buttonShape", v, function(k)
                  -- Reset border thickness to the default for the new shape mode
                  if v ~= "none" and v ~= "cropped" then
                      EAB.db.profile.bars[k].borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                      local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                      EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                      EAB.db.profile.bars[k].shapeBorderEnabled = true
                  else
                      EAB.db.profile.bars[k].borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                      local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                      EAB.db.profile.bars[k].borderSize = entry.regular
                      EAB.db.profile.bars[k].borderEnabled = true
                  end
                  -- Default keybind/count text for cropped vs normal (offsets keep a
                  -- positioned text's corner spacing)
                  if v == "cropped" then
                      EAB.db.profile.bars[k].keybindFontSize = 11
                      EAB.db.profile.bars[k].countFontSize = 11
                      EAB.ApplyShapeTextOffsets(EAB.db.profile.bars[k], 0, 1, 0, -1)
                  else
                      EAB.db.profile.bars[k].keybindFontSize = 12
                      EAB.db.profile.bars[k].countFontSize = 12
                      EAB.ApplyShapeTextOffsets(EAB.db.profile.bars[k], 0, 0, 0, 0)
                  end
                  EAB:ApplyShapesForBar(k)
                  EAB:ApplyPaddingForBar(k)
                  EAB:ApplyBordersForBar(k)
                  EAB:ApplyFontsForBar(k)
                  EAB:ApplyIconBackgroundForBar(k)
              end)
              EAB:RefreshProcGlows()
              SUpdatePreview()
              -- Full rebuild: the Border Size slot is a dropdown for a custom shape
              -- and the pixel slider otherwise, and only a rebuild swaps it.
              EllesmereUI:RefreshPage(true)
          end }),
        EllesmereUI.BlizzStyle.Gate("actionbars", { type="slider", text="Icon Zoom", min=0, max=10, step=0.5,
          disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
          getValue=function() return SVal("iconZoom", EAB.db.profile.iconZoom or 5.5) end,
          setValue=function(v)
              SSet("iconZoom", v, function(k)
                  EAB:ApplyBordersForBar(k)
                  EAB:ApplyShapesForBar(k)
              end)
              SUpdatePreview()
          end }));  y = y - h
    do
        local rgn = classColorBorderRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Custom Button Shape to all Bars",
            onClick = function()
                local v = SGet("buttonShape") or "none"
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local bs = EAB.db.profile.bars[key]
                    bs.iconZoom = ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5
                    bs.buttonShape = v
                    if v ~= "none" and v ~= "cropped" then
                        bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                        local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                        bs.shapeBorderSize = entry.shape
                        bs.shapeBorderEnabled = true
                    else
                        bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                        local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                        bs.borderSize = entry.regular
                        bs.borderEnabled = true
                    end
                    if v == "cropped" then
                        bs.keybindFontSize = 11; bs.countFontSize = 11
                        EAB.ApplyShapeTextOffsets(bs, 0, 1, 0, -1)
                    else
                        bs.keybindFontSize = 12; bs.countFontSize = 12
                        EAB.ApplyShapeTextOffsets(bs, 0, 0, 0, 0)
                    end
                    EAB:ApplyShapesForBar(key)
                    EAB:ApplyPaddingForBar(key)
                    EAB:ApplyBordersForBar(key)
                    EAB:ApplyFontsForBar(key)
                end
                EAB:RefreshProcGlows()
                SUpdatePreview()
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SGet("buttonShape") or "none"
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].buttonShape or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SGet("buttonShape") or "none"
                    for _, key in ipairs(checkedKeys) do
                        local bs = EAB.db.profile.bars[key]
                        bs.iconZoom = ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5
                        bs.buttonShape = v
                        if v ~= "none" and v ~= "cropped" then
                            bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                            local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                            bs.shapeBorderSize = entry.shape
                            bs.shapeBorderEnabled = true
                        else
                            bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                            local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                            bs.borderSize = entry.regular
                            bs.borderEnabled = true
                        end
                        if v == "cropped" then
                            bs.keybindFontSize = 11; bs.countFontSize = 11
                            EAB.ApplyShapeTextOffsets(bs, 0, 1, 0, -1)
                        else
                            bs.keybindFontSize = 12; bs.countFontSize = 12
                            EAB.ApplyShapeTextOffsets(bs, 0, 0, 0, 0)
                        end
                        EAB:ApplyShapesForBar(key)
                        EAB:ApplyPaddingForBar(key)
                        EAB:ApplyBordersForBar(key)
                        EAB:ApplyFontsForBar(key)
                    end
                    EAB:RefreshProcGlows()
                    SUpdatePreview()
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rgn = classColorBorderRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Icon Zoom to all Bars",
            onClick = function()
                local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].iconZoom = v
                    EAB:ApplyBordersForBar(key)
                    EAB:ApplyShapesForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].iconZoom or EAB.db.profile.iconZoom or 5.5) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].iconZoom = v
                        EAB:ApplyBordersForBar(key)
                        EAB:ApplyShapesForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- "Show Cooldown Numbers" LIVE-toggles Blizzard's countdownForCooldowns CVar and is never
    -- stored in our DB; the CVar is written only on an actual user flip.
    local zoomIbgRow
    zoomIbgRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Blizzard Icon Background",
          tooltip="Shows Blizzard's default icon slot background texture behind empty action bar slots.",
          getValue=function() return EAB.db.profile.showBlizzIconBg or false end,
          setValue=function(v)
              EAB.db.profile.showBlizzIconBg = v
              for _, info in ipairs(ns.BAR_CONFIG or {}) do
                  EAB:ApplyIconBackgroundForBar(info.key)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Show Cooldown Numbers",
          tooltip="Toggles Blizzard's Show Numbers for Cooldowns setting, which will show number text on any spells that are on cooldown on your action bars.",
          getValue=function() return GetCVarBool("countdownForCooldowns") end,
          setValue=function(v)
              if InCombatLockdown() then return end
              SetCVar("countdownForCooldowns", v and "1" or "0")
              -- Refresh so the inline cog dims/undims with the CVar state.
              EllesmereUI:RefreshPage()
          end });  y = y - h
    do
        local rgn = zoomIbgRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Icon Background",
            anchorTo = rgn._control,
            disabled = function() return not (EAB.db.profile.showBlizzIconBg or false) end,
            disabledTooltip = "Show Blizzard Icon Background",
            rows = {
                { type="slider", label="Opacity", min=0, max=100, step=1,
                  tooltip="Controls the opacity of the Blizzard icon slot background texture.",
                  get=function() return math.floor((EAB.db.profile.blizzIconBgAlpha or 1) * 100 + 0.5) end,
                  set=function(v)
                      EAB.db.profile.blizzIconBgAlpha = v / 100
                      for _, info in ipairs(ns.BAR_CONFIG or {}) do
                          EAB:ApplyIconBackgroundForBar(info.key)
                      end
                  end },
            },
        })
    end
    -- Inline cog: Show Cooldown Numbers (right). Holds the charge-spell recharge toggle
    -- (our feature, DB-saved); dimmed when the CVar is off, since no numbers show then.
    do
        local rgn = zoomIbgRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Cooldown Numbers",
            anchorTo = rgn._control,
            disabled = function() return not GetCVarBool("countdownForCooldowns") end,
            disabledTooltip = "Show Cooldown Numbers",
            rows = {
                { type="toggle", label="Charge Recharge Numbers",
                  tooltip="Show the recharge countdown on charge spells while a charge is still banked. When off, the recharge timer only appears at 0 charges (Blizzard default).",
                  get=function() return EAB.db.profile.showChargeRechargeNumbers ~= false end,
                  set=function(v)
                      EAB.db.profile.showChargeRechargeNumbers = v
                      EAB:RefreshChargeRechargeNumbers()
                  end },
            },
        })
    end

    local slotBgRow
    slotBgRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("actionbars", { type="slider", text="Icon Background", min=0, max=100, step=1,
          tooltip="Controls the opacity of the flat color background behind action button icons.",
          disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
          getValue=function()
              local v = EAB.db.profile.slotBgOpacity
              if v == nil then v = 50 end
              return v
          end,
          setValue=function(v)
              EAB.db.profile.slotBgOpacity = v
              EAB:ApplySlotBackgroundColor()
          end }),
        { type="toggle", text="One Button Assist Icon",
          tooltip="Shows the rotation-helper ring on the button holding the One Button Assist action.",
          getValue=function() return EAB.db.profile.obaIconEnabled ~= false end,
          setValue=function(v)
              EAB.db.profile.obaIconEnabled = v
              if ns.RefreshAssistSpinners then ns.RefreshAssistSpinners() end
          end });  y = y - h
    do
        local rgn = slotBgRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, { anchorTo = rgn._control,
            title = "One Button Assist Icon",
            rows = {
                { type="slider", label="Icon Outset", min=0, max=30, step=1,
                  get=function() return EAB.db.profile.obaIconOutset or 9 end,
                  set=function(v)
                      EAB.db.profile.obaIconOutset = v
                      if ns.RefreshAssistSpinners then ns.RefreshAssistSpinners() end
                  end },
            },
        })
    end
    -- Inline swatch: icon background color (left). Dimmed while a stock style is on (no slot background exists) or at 0 opacity.
    do
        local rgn = slotBgRow._leftRegion
        local function SbgOff()
            if BlizzStyleOn() then return true end
            local v = EAB.db.profile.slotBgOpacity
            if v == nil then v = 50 end
            return v == 0
        end
        local sbgSwatch, sbgUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, slotBgRow:GetFrameLevel() + 3,
            function()
                local c = EAB.db.profile.slotBgColor or { r=0.15, g=0.15, b=0.15 }
                return c.r, c.g, c.b, 1
            end,
            function(r, g, b)
                EAB.db.profile.slotBgColor = { r = r, g = g, b = b }
                EAB:ApplySlotBackgroundColor()
            end,
            false, 20)
        PP.Point(sbgSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
        rgn._lastInline = sbgSwatch
        sbgSwatch:SetAlpha(SbgOff() and 0.15 or 1)
        local sbgOrigClick = sbgSwatch:GetScript("OnClick")
        sbgSwatch:SetScript("OnClick", function(self, ...)
            if SbgOff() then return end
            if sbgOrigClick then sbgOrigClick(self, ...) end
        end)
        sbgSwatch:SetScript("OnEnter", function(self)
            if SbgOff() then
                if BlizzStyleOn() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled"))
                else
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Set Icon Background above 0"))
                end
            end
        end)
        sbgSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            sbgSwatch:SetAlpha(SbgOff() and 0.15 or 1)
            sbgUpdateSwatch()
        end)
    end
    -------------------------------------------------------------------
    --  ICON EFFECTS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "ICON EFFECTS", y);  y = y - h

    local dtRow
    dtRow, h = W:DualRow(parent, y,
        { type="toggle", text="Desaturate on Cooldown",
          -- setValue runs a one-shot catch-up sweep: cooldown repaints happen on edges only, so an icon grey at uncheck time would stay grey.
          tooltip="Desaturates (grays out) action button icons while the ability is on cooldown. GCD-only cooldowns are excluded.",
          getValue=function() return EAB.db.profile.desaturateOnCooldown or false end,
          setValue=function(v)
              local p = EAB.db.profile
              local was = p.desaturateOnCooldown or false
              p.desaturateOnCooldown = v
              if was ~= (v or false) and EAB._DesatSettingChanged then
                  EAB._DesatSettingChanged(v and true or false)
              end
          end },
        { type="toggle", text="Disable Tooltips",
          getValue=function()
              return SGet("disableTooltips") or false
          end,
          setValue=function(v)
              SSet("disableTooltips", v)
          end });  y = y - h
    do
        local rgn = dtRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Disable Tooltips to all Bars",
            onClick = function()
                local v = SB().disableTooltips or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].disableTooltips = v
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().disableTooltips or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].disableTooltips or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().disableTooltips or false
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].disableTooltips = v
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    local rangeRankRow
    rangeRankRow, h = W:DualRow(parent, y,
        { type="toggle", text="Out of Range Coloring",
          getValue=function()
              return SGet("outOfRangeColoring") or false
          end,
          setValue=function(v)
              SSet("outOfRangeColoring", v, function() EAB:ApplyRangeColoring() end)
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Show Item Rank",
          tooltip="Shows the consumable rank (quality) diamond icon on action buttons.",
          getValue=function() return SGet("showRankIcon") or false end,
          setValue=function(v)
              SSet("showRankIcon", v)
              if _G._EAB_Apply then _G._EAB_Apply() end
          end });  y = y - h
    do
        local rgn = rangeRankRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Range Coloring to all Bars",
            onClick = function()
                local v = SB().outOfRangeColoring or false
                local c = SB().outOfRangeColor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].outOfRangeColoring = v
                    if c then EAB.db.profile.bars[key].outOfRangeColor = { r=c.r, g=c.g, b=c.b } end
                end
                EAB:ApplyRangeColoring(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().outOfRangeColoring or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].outOfRangeColoring or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().outOfRangeColoring or false
                    local c = SB().outOfRangeColor
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].outOfRangeColoring = v
                        if c then EAB.db.profile.bars[key].outOfRangeColor = { r=c.r, g=c.g, b=c.b } end
                    end
                    EAB:ApplyRangeColoring(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    do
        local leftRgn = rangeRankRow._leftRegion
        local rangeColorGet = function()
            local c = SGet("outOfRangeColor")
            if not c then return 0.7, 0.2, 0.2 end
            return c.r, c.g, c.b
        end
        local rangeColorSet = function(r, g, b)
            SSetColor("outOfRangeColor", r, g, b, nil, function() EAB:ApplyRangeColoring() end)
        end
        local rangeSwatch, rangeUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, rangeColorGet, rangeColorSet, false, 20)
        PP.Point(rangeSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = rangeSwatch

        local function RangeDisabled()
            return not SGet("outOfRangeColoring")
        end

        EllesmereUI.RegisterWidgetRefresh(function()
            local off = RangeDisabled()
            rangeSwatch:SetAlpha(off and 0.3 or 1)
            rangeUpdateSwatch()
        end)
        rangeSwatch:SetAlpha(RangeDisabled() and 0.3 or 1)

        local rangeBlock = CreateFrame("Frame", nil, rangeSwatch)
        rangeBlock:SetAllPoints()
        rangeBlock:SetFrameLevel(rangeSwatch:GetFrameLevel() + 10)
        rangeBlock:EnableMouse(true)
        rangeBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(rangeSwatch, EllesmereUI.DisabledTooltip("Out of Range Coloring"))
        end)
        rangeBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            rangeBlock:SetShown(RangeDisabled())
        end)
        rangeBlock:SetShown(RangeDisabled())
    end
    do
        local rgn = rangeRankRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Show Item Rank to all Bars",
            onClick = function()
                local v = SB().showRankIcon or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].showRankIcon = v
                end
                if _G._EAB_Apply then _G._EAB_Apply() end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().showRankIcon or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].showRankIcon or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().showRankIcon or false
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].showRankIcon = v
                    end
                    if _G._EAB_Apply then _G._EAB_Apply() end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    local cdEffectsRow
    cdEffectsRow, h = W:DualRow(parent, y,
        { type="slider", text="Alpha when on CD", min=0, max=100, step=5,
          tooltip="Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
          getValue=function() return EAB.db.profile.alphaWhenOnCD or 100 end,
          setValue=function(v)
              EAB.db.profile.alphaWhenOnCD = v
              if EAB.ApplyCDAlphaAll then EAB:ApplyCDAlphaAll() end
          end },
        { type="slider", text="CD Swipe Opacity", min=0, max=100, step=5,
          tooltip="Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
          getValue=function() return EAB.db.profile.cdSwipeAlpha or 80 end,
          setValue=function(v)
              EAB.db.profile.cdSwipeAlpha = v
              if EAB.ApplyCooldownSwipeColor then EAB:ApplyCooldownSwipeColor() end
          end });  y = y - h
    -- Inline swatch for CD Swipe Opacity (right): colour-only (hasAlpha=false), since alpha lives on the slider.
    do
        local rgn = cdEffectsRow._rightRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, cdEffectsRow:GetFrameLevel() + 5,
            function()
                local c = EAB.db.profile.cdSwipeColor or {}
                return c.r or 0, c.g or 0, c.b or 0
            end,
            function(r, g, b)
                EAB.db.profile.cdSwipeColor = { r = r, g = g, b = b }
                if EAB.ApplyCooldownSwipeColor then EAB:ApplyCooldownSwipeColor() end
            end,
            false, 20)
        PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- Canonical inline-swatch pattern: auto-disable at 0 opacity (invisible swipe has no visible colour).
        local function SwipeDisabled()
            return (EAB.db.profile.cdSwipeAlpha or 80) == 0
        end
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10); block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Set CD Swipe Opacity above 0"))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            updateSwatch()
            local off = SwipeDisabled()
            swatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end)
        local off0 = SwipeDisabled()
        swatch:SetAlpha(off0 and 0.3 or 1)
        block:SetShown(off0)
    end

    -- Row: Hide Count at 0 | Show Equipped Border (Blizzard's green border on
    -- an equipped item's button, kept in our square art; the Blizzard and
    -- Classic styles draw their own, so it locks under them).
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Charge Count at 0",
          tooltip="Hide the charge number on action buttons when it reaches 0, instead of showing a 0. The number returns as soon as a charge or item comes back.",
          getValue=function() return EAB.db.profile.hideZeroCount or false end,
          setValue=function(v)
              EAB.db.profile.hideZeroCount = v or nil
              if EAB.RefreshAllCounts then EAB:RefreshAllCounts() end
          end },
        { type="toggle", text="Show Equipped Border",
          tooltip="Shows Blizzard's green border on action buttons that hold an equipped item, such as your trinkets.",
          disabled=function() return ns.AB_Style() ~= "eui" end,
          disabledTooltip="The Blizzard and Classic styles show their own equipped border.",
          rawTooltip=true,
          getValue=function() return EAB.db.profile.showEquippedBorder or false end,
          setValue=function(v)
              EAB.db.profile.showEquippedBorder = v or nil
              EAB:ApplyEquippedBorder()
          end });  y = y - h

    BuildBarBackgroundSection()

    -------------------------------------------------------------------
    --  PAGING (MainBar + Bars 2-8 only, not Stance/Pet/Micro/Bag)
    -------------------------------------------------------------------
    do
        local selKey = SelectedKey()
        local _bkp = ns.EAB_VTABLE and ns.EAB_VTABLE.BAR_KEY_TO_PAGE
        local showPaging = selKey and _bkp and _bkp[selKey]
        if showPaging then
            _, h = W:SectionHeader(parent, "PAGING", y);  y = y - h

            local _, playerClass = UnitClass("player")
            local EAB_VT = ns.EAB_VTABLE or {}
            local PG_STATES = EAB_VT.PAGING_STATES or {}
            local BKP = EAB_VT.BAR_KEY_TO_PAGE or {}

            local pagingValues = { none = "Default" }
            local pagingOrder = { "none" }
            local barList = {
                { key = "MainBar", label = "Action Bar 1 (Main)" },
                { key = "Bar2",    label = "Action Bar 2" },
                { key = "Bar3",    label = "Action Bar 3" },
                { key = "Bar4",    label = "Action Bar 4" },
                { key = "Bar5",    label = "Action Bar 5" },
                { key = "Bar6",    label = "Action Bar 6" },
                { key = "Bar7",    label = "Action Bar 7" },
                { key = "Bar8",    label = "Action Bar 8" },
                { key = "Bar9",    label = "Action Bar 9" },
                { key = "Bar10",   label = "Action Bar 10" },
            }
            for _, bl in ipairs(barList) do
                -- Skip self (can't page a bar to itself)
                if bl.key ~= selKey then
                    local pg = BKP[bl.key]
                    if pg then
                        pagingValues[tostring(pg)] = bl.label
                        pagingOrder[#pagingOrder + 1] = tostring(pg)
                    end
                end
            end

            local function GetPagingVal(stateId)
                local paging = SGet("paging")
                if not paging then return "none" end
                local v = paging[stateId]
                if not v then return "none" end
                return tostring(v)
            end
            local function SetPagingVal(stateId, val)
                local bars = EAB.db.profile.bars[selKey]
                if not bars.paging then bars.paging = {} end
                if val == "none" then
                    -- nil, not false: the driver builder reads nil as "unconfigured -> native
                    -- form fallback", while false would suppress the form's bonusbar swap.
                    bars.paging[stateId] = nil
                else
                    bars.paging[stateId] = tonumber(val)
                end
                -- Clean up: if all values are false (all disabled), reset
                local anySet = false
                for _, v in pairs(bars.paging) do
                    if v then anySet = true; break end
                end
                if not anySet then bars.paging = {} end
                if ns.RebuildBarPaging then ns.RebuildBarPaging(selKey) end
            end

            -- Row 0: Auto-paging opt-outs (MainBar only -- the only bar the engine pages off
            -- bonusbar). Suppresses implicit swaps only; an explicit page below still applies.
            if selKey == "MainBar" then
                local function SetAutoPageOptOut(key, v)
                    SSet(key, v, function(k)
                        if ns.RebuildBarPaging then ns.RebuildBarPaging(k) end
                    end)
                end
                _, h = W:DualRow(parent, y,
                    { type="toggle", text="Disable Form Paging",
                      getValue=function() return SGet("disableFormPaging") or false end,
                      setValue=function(v) SetAutoPageOptOut("disableFormPaging", v) end,
                      tooltip="Keep Action Bar 1 on its current page when you shapeshift, stealth, or change stance, instead of swapping to that form's bar.\n\nKeybinds follow what the bar shows, so the key always casts the icon you see. Press-and-hold repeat casting is turned off on Action Bar 1 while this is enabled." },
                    { type="toggle", text="Disable Skyriding Paging",
                      getValue=function() return SGet("disableSkyridingPaging") or false end,
                      setValue=function(v) SetAutoPageOptOut("disableSkyridingPaging", v) end,
                      tooltip="Keep Action Bar 1 on its current page while skyriding, instead of swapping to the skyriding bar.\n\nYour skyriding abilities live on that bar, so put them on another bar before enabling this. Press-and-hold repeat casting is turned off on Action Bar 1 while this is enabled." });  y = y - h
            end

            local pagingArrowsWidget
            if selKey == "MainBar" then
                pagingArrowsWidget = { type="toggle", text="Show Paging Arrows",
                  getValue=function() return SGet("showPagingArrows") or false end,
                  setValue=function(v)
                      SSet("showPagingArrows", v, function()
                          if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                      end)
                      EllesmereUI:RefreshPage()
                  end,
                  tooltip="Show page up/down arrows next to Action Bar 1 for cycling through action bar pages 1-6." }
            else
                pagingArrowsWidget = { type="label", text="" }
            end
            local pagingRow
            pagingRow, h = W:DualRow(parent, y,
                pagingArrowsWidget,
                { type="dropdown", text="Shift Modifier",
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal("shift") end,
                  setValue=function(v) SetPagingVal("shift", v) end });  y = y - h

            if selKey == "MainBar" then
                local lRgn = pagingRow._leftRegion
                local pagingOff = function() return not (SGet("showPagingArrows") or false) end
                EllesmereUI.BuildInlineCog(lRgn, {
                    title = "Paging Arrow Settings",
                    anchorTo = lRgn._control,
                    disabled = pagingOff, disabledTooltip = "Show Paging Arrows",
                    rows = {
                        { type="toggle", label="Show Arrows on Right",
                          get=function() return SGet("pagingArrowsRight") or false end,
                          set=function(v)
                              SSet("pagingArrowsRight", v, function()
                                  if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                              end)
                          end },
                    },
                })
            end

            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Ctrl Modifier",
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal("ctrl") end,
                  setValue=function(v) SetPagingVal("ctrl", v) end },
                { type="dropdown", text="Alt Modifier",
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal("alt") end,
                  setValue=function(v) SetPagingVal("alt", v) end });  y = y - h

            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Friendly Target",
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal("help") end,
                  setValue=function(v) SetPagingVal("help", v) end },
                { type="dropdown", text="Hostile Target",
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal("harm") end,
                  setValue=function(v) SetPagingVal("harm", v) end });  y = y - h

            -- Class form dropdowns (paired into DualRows)
            local classStatesLocal = PG_STATES.class and PG_STATES.class[playerClass]
            if classStatesLocal then
                for i = 1, #classStatesLocal, 2 do
                    local left = classStatesLocal[i]
                    local right = classStatesLocal[i + 1]
                    local rightWidget
                    if right then
                        rightWidget = { type="dropdown", text=right.label,
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal(right.id) end,
                          setValue=function(v) SetPagingVal(right.id, v) end }
                    else
                        rightWidget = { type="label", text="" }
                    end
                    _, h = W:DualRow(parent, y,
                        { type="dropdown", text=left.label,
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal(left.id) end,
                          setValue=function(v) SetPagingVal(left.id, v) end },
                        rightWidget);  y = y - h
                end
            end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  TEXT
    -------------------------------------------------------------------
    textSectionHeader, h = W:SectionHeader(parent, SECTION_TEXT, y);  y = y - h

    row, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Keybind Text",
          getValue=function()
              return SGet("hideKeybind")
          end,
          setValue=function(v)
              SSet("hideKeybind", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Keybind Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return SVal("keybindFontSize", 12) end,
          setValue=function(v)
              SSet("keybindFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end });  y = y - h
    keybindRow = row
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Keybind Visibility to all Bars",
            onClick = function()
                local v = SB().hideKeybind
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].hideKeybind = v
                    EAB:ApplyFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().hideKeybind or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].hideKeybind or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().hideKeybind
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].hideKeybind = v
                        EAB:ApplyFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    do
        local rgn = keybindRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Keybind Text Settings to all Bars",
            onClick = function()
                local s = SB()
                local c = s.keybindFontColor
                local sz = s.keybindFontSize or 12
                local ox = s.keybindOffsetX or 0
                local oy = s.keybindOffsetY or 0
                local an = s.keybindAnchor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if c then EAB.db.profile.bars[key].keybindFontColor = { r=c.r, g=c.g, b=c.b } end
                    EAB.db.profile.bars[key].keybindFontSize = sz
                    EAB.db.profile.bars[key].keybindOffsetX = ox
                    EAB.db.profile.bars[key].keybindOffsetY = oy
                    EAB.db.profile.bars[key].keybindAnchor = an or false
                    EAB:ApplyFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local s = SB()
                local sz = s.keybindFontSize or 12
                local c = s.keybindFontColor
                local ox = s.keybindOffsetX or 0
                local oy = s.keybindOffsetY or 0
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local b = EAB.db.profile.bars[key]
                    if (b.keybindFontSize or 12) ~= sz then return false end
                    if (b.keybindOffsetX or 0) ~= ox then return false end
                    if (b.keybindOffsetY or 0) ~= oy then return false end
                    if (b.keybindAnchor or nil) ~= (s.keybindAnchor or nil) then return false end
                    if c then
                        local bc = b.keybindFontColor
                        if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local s = SB()
                    local c = s.keybindFontColor
                    local sz = s.keybindFontSize or 12
                    local ox = s.keybindOffsetX or 0
                    local oy = s.keybindOffsetY or 0
                    local an = s.keybindAnchor
                    for _, key in ipairs(checkedKeys) do
                        if c then EAB.db.profile.bars[key].keybindFontColor = { r=c.r, g=c.g, b=c.b } end
                        EAB.db.profile.bars[key].keybindFontSize = sz
                        EAB.db.profile.bars[key].keybindOffsetX = ox
                        EAB.db.profile.bars[key].keybindOffsetY = oy
                        EAB.db.profile.bars[key].keybindAnchor = an or false
                        EAB:ApplyFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rgn = keybindRow._rightRegion
        local ctrl = rgn._control
        local kbSwatch, kbUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, keybindRow:GetFrameLevel() + 3,
            function()
                local c = SGet("keybindFontColor")
                if not c then return 1, 1, 1 end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("keybindFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                SUpdatePreview()
            end,
            false, 20)
        PP.Point(kbSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = kbSwatch
        EllesmereUI.RegisterWidgetRefresh(function() kbUpdateSwatch() end)

        EllesmereUI.BuildInlineCog(rgn, { anchorTo = kbSwatch, icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Keybind Text Offsets",
            rows = {
                { type="dropdown", label="Position",
                  values=TEXT_ANCHOR_LABELS, order=TEXT_ANCHOR_DROPDOWN_ORDER,
                  get=function() return SVal("keybindAnchor", "default") end,
                  set=function(v)
                      local anchor = v ~= "default" and v or nil
                      SSeedTextOffsets("keybind", "keybindAnchor", "keybindOffsetX", "keybindOffsetY", anchor)
                      -- Default is stored false, not nil: profile sync copies only keys that exist.
                      SSet("keybindAnchor", anchor or false, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("keybindOffsetX", 0) end,
                  set=function(v)
                      SSet("keybindOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("keybindOffsetY", 0) end,
                  set=function(v)
                      SSet("keybindOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
            },
        })
    end

    local macroRow
    macroRow, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Macro Text",
          getValue=function()
              return SGet("hideMacroText")
          end,
          setValue=function(v)
              SSet("hideMacroText", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Macro Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return SVal("macroFontSize", 12) end,
          setValue=function(v)
              SSet("macroFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end });  y = y - h
    do
        local rgn = macroRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Macro Text Visibility to all Bars",
            onClick = function()
                local v = SB().hideMacroText
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].hideMacroText = v
                    EAB:ApplyFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = SB().hideMacroText or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if (EAB.db.profile.bars[key].hideMacroText or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().hideMacroText
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].hideMacroText = v
                        EAB:ApplyFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    do
        local rgn = macroRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Macro Text Settings to all Bars",
            onClick = function()
                local s = SB()
                local c = s.macroFontColor
                local sz = s.macroFontSize or 12
                local ox = s.macroOffsetX or 0
                local oy = s.macroOffsetY or 0
                local an = s.macroAnchor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if c then EAB.db.profile.bars[key].macroFontColor = { r=c.r, g=c.g, b=c.b } end
                    EAB.db.profile.bars[key].macroFontSize = sz
                    EAB.db.profile.bars[key].macroOffsetX = ox
                    EAB.db.profile.bars[key].macroOffsetY = oy
                    EAB.db.profile.bars[key].macroAnchor = an or false
                    EAB:ApplyFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local s = SB()
                local sz = s.macroFontSize or 12
                local c = s.macroFontColor
                local ox = s.macroOffsetX or 0
                local oy = s.macroOffsetY or 0
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local b = EAB.db.profile.bars[key]
                    if (b.macroFontSize or 12) ~= sz then return false end
                    if (b.macroOffsetX or 0) ~= ox then return false end
                    if (b.macroOffsetY or 0) ~= oy then return false end
                    if (b.macroAnchor or nil) ~= (s.macroAnchor or nil) then return false end
                    if c then
                        local bc = b.macroFontColor
                        if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local s = SB()
                    local c = s.macroFontColor
                    local sz = s.macroFontSize or 12
                    local ox = s.macroOffsetX or 0
                    local oy = s.macroOffsetY or 0
                    local an = s.macroAnchor
                    for _, key in ipairs(checkedKeys) do
                        if c then EAB.db.profile.bars[key].macroFontColor = { r=c.r, g=c.g, b=c.b } end
                        EAB.db.profile.bars[key].macroFontSize = sz
                        EAB.db.profile.bars[key].macroOffsetX = ox
                        EAB.db.profile.bars[key].macroOffsetY = oy
                        EAB.db.profile.bars[key].macroAnchor = an or false
                        EAB:ApplyFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rgn = macroRow._rightRegion
        local ctrl = rgn._control
        local mcSwatch, mcUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, macroRow:GetFrameLevel() + 3,
            function()
                local c = SGet("macroFontColor")
                if not c then return 1, 1, 1 end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("macroFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                SUpdatePreview()
            end,
            false, 20)
        PP.Point(mcSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = mcSwatch
        EllesmereUI.RegisterWidgetRefresh(function() mcUpdateSwatch() end)

        EllesmereUI.BuildInlineCog(rgn, { anchorTo = mcSwatch, icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Macro Text Offsets",
            rows = {
                { type="dropdown", label="Position",
                  values=TEXT_ANCHOR_LABELS, order=TEXT_ANCHOR_DROPDOWN_ORDER,
                  get=function() return SVal("macroAnchor", "default") end,
                  set=function(v)
                      local anchor = v ~= "default" and v or nil
                      SSeedTextOffsets("macro", "macroAnchor", "macroOffsetX", "macroOffsetY", anchor)
                      SSet("macroAnchor", anchor or false, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("macroOffsetX", 0) end,
                  set=function(v)
                      SSet("macroOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("macroOffsetY", 0) end,
                  set=function(v)
                      SSet("macroOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
            },
        })
    end

    chargesRow, h = W:DualRow(parent, y,
        { type="slider", text="Charges Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return SVal("countFontSize", 12) end,
          setValue=function(v)
              SSet("countFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Cooldown Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return SVal("cooldownFontSize", 12) end,
          setValue=function(v)
              SSet("cooldownFontSize", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
              SUpdatePreview()
          end });  y = y - h
    do
        local rgn = chargesRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Charges Text Settings to all Bars",
            onClick = function()
                local s = SB()
                local c = s.countFontColor
                local sz = s.countFontSize or 12
                local ox = s.countOffsetX or 0
                local oy = s.countOffsetY or 0
                local an = s.countAnchor
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if c then EAB.db.profile.bars[key].countFontColor = { r=c.r, g=c.g, b=c.b } end
                    EAB.db.profile.bars[key].countFontSize = sz
                    EAB.db.profile.bars[key].countOffsetX = ox
                    EAB.db.profile.bars[key].countOffsetY = oy
                    EAB.db.profile.bars[key].countAnchor = an or false
                    EAB:ApplyFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local s = SB()
                local sz = s.countFontSize or 12
                local c = s.countFontColor
                local ox = s.countOffsetX or 0
                local oy = s.countOffsetY or 0
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local b = EAB.db.profile.bars[key]
                    if (b.countFontSize or 12) ~= sz then return false end
                    if (b.countOffsetX or 0) ~= ox then return false end
                    if (b.countOffsetY or 0) ~= oy then return false end
                    if (b.countAnchor or nil) ~= (s.countAnchor or nil) then return false end
                    if c then
                        local bc = b.countFontColor
                        if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local s = SB()
                    local c = s.countFontColor
                    local sz = s.countFontSize or 12
                    local ox = s.countOffsetX or 0
                    local oy = s.countOffsetY or 0
                    local an = s.countAnchor
                    for _, key in ipairs(checkedKeys) do
                        if c then EAB.db.profile.bars[key].countFontColor = { r=c.r, g=c.g, b=c.b } end
                        EAB.db.profile.bars[key].countFontSize = sz
                        EAB.db.profile.bars[key].countOffsetX = ox
                        EAB.db.profile.bars[key].countOffsetY = oy
                        EAB.db.profile.bars[key].countAnchor = an or false
                        EAB:ApplyFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rgn = chargesRow._leftRegion
        local ctrl = rgn._control
        local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, chargesRow:GetFrameLevel() + 3,
            function()
                local c = SGet("countFontColor")
                if not c then return 1, 1, 1 end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("countFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                SUpdatePreview()
            end,
            false, 20)
        PP.Point(ctSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = ctSwatch
        EllesmereUI.RegisterWidgetRefresh(function() ctUpdateSwatch() end)

        EllesmereUI.BuildInlineCog(rgn, { anchorTo = ctSwatch, icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Charges Text Offsets",
            rows = {
                { type="dropdown", label="Position",
                  values=TEXT_ANCHOR_LABELS, order=TEXT_ANCHOR_DROPDOWN_ORDER,
                  get=function() return SVal("countAnchor", "default") end,
                  set=function(v)
                      local anchor = v ~= "default" and v or nil
                      SSeedTextOffsets("count", "countAnchor", "countOffsetX", "countOffsetY", anchor)
                      SSet("countAnchor", anchor or false, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("countOffsetX", 0) end,
                  set=function(v)
                      SSet("countOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("countOffsetY", 0) end,
                  set=function(v)
                      SSet("countOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
            },
        })
    end

    do
        local rgn = chargesRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Cooldown Text Settings to all Bars",
            onClick = function()
                local s = SB()
                local c = s.cooldownTextColor
                local sz = s.cooldownFontSize or 12
                local ox = s.cooldownTextXOffset or 0
                local oy = s.cooldownTextYOffset or 0
                local ft = s.cooldownFontFit or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if c then EAB.db.profile.bars[key].cooldownTextColor = { r=c.r, g=c.g, b=c.b } end
                    EAB.db.profile.bars[key].cooldownFontSize = sz
                    EAB.db.profile.bars[key].cooldownTextXOffset = ox
                    EAB.db.profile.bars[key].cooldownTextYOffset = oy
                    EAB.db.profile.bars[key].cooldownFontFit = ft
                    EAB:ApplyCooldownFontsForBar(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local s = SB()
                local sz = s.cooldownFontSize or 12
                local c = s.cooldownTextColor
                local ox = s.cooldownTextXOffset or 0
                local oy = s.cooldownTextYOffset or 0
                local ft = s.cooldownFontFit or false
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local b = EAB.db.profile.bars[key]
                    if (b.cooldownFontSize or 12) ~= sz then return false end
                    if (b.cooldownTextXOffset or 0) ~= ox then return false end
                    if (b.cooldownTextYOffset or 0) ~= oy then return false end
                    if (b.cooldownFontFit or false) ~= ft then return false end
                    if c then
                        local bc = b.cooldownTextColor
                        if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local s = SB()
                    local c = s.cooldownTextColor
                    local sz = s.cooldownFontSize or 12
                    local ox = s.cooldownTextXOffset or 0
                    local oy = s.cooldownTextYOffset or 0
                    local ft = s.cooldownFontFit or false
                    for _, key in ipairs(checkedKeys) do
                        if c then EAB.db.profile.bars[key].cooldownTextColor = { r=c.r, g=c.g, b=c.b } end
                        EAB.db.profile.bars[key].cooldownFontSize = sz
                        EAB.db.profile.bars[key].cooldownTextXOffset = ox
                        EAB.db.profile.bars[key].cooldownTextYOffset = oy
                        EAB.db.profile.bars[key].cooldownFontFit = ft
                        EAB:ApplyCooldownFontsForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    do
        local rgn = chargesRow._rightRegion
        local ctrl = rgn._control
        local cdSwatch, cdUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, chargesRow:GetFrameLevel() + 3,
            function()
                local c = SGet("cooldownTextColor")
                if not c then return 1, 1, 1 end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("cooldownTextColor", r, g, b, nil, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                SUpdatePreview()
            end,
            false, 20)
        PP.Point(cdSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = cdSwatch
        EllesmereUI.RegisterWidgetRefresh(function() cdUpdateSwatch() end)

        EllesmereUI.BuildInlineCog(rgn, { anchorTo = cdSwatch, icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Cooldown Text",
            rows = {
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return SVal("cooldownTextXOffset", 0) end,
                  set=function(v)
                      SSet("cooldownTextXOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return SVal("cooldownTextYOffset", 0) end,
                  set=function(v)
                      SSet("cooldownTextYOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="toggle", label="Fit Size to Button",
                  tooltip="Caps the countdown size so it cannot spill outside small buttons.",
                  get=function() return SVal("cooldownFontFit", false) end,
                  set=function(v)
                      SSet("cooldownFontFit", v and true or false, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return y, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildBarAppearance = BuildBarAppearance
