if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarAppearance_Options.lua
--  Action Bars options: the Appearance, Effects, Behavior (and Paging) and
--  Text sections of the Bar Display page. Called by BuildSharedBarSettings
--  for bars that are not visibility-only; returns y and the rows its click
--  navigation maps to. Shared helpers come from ns._ABO_OptEnv, the
--  per-build helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page
-- Options page pool (EllesmereUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local function BuildBarAppearance(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local EAB, EndCapsCtl, GROUP_BAR_ORDER, InCombatLockdown, PP = env.EAB, env.EndCapsCtl, env.GROUP_BAR_ORDER, env.InCombatLockdown, env.PP
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

    -- A row whose items or cog hold settings with labels of their own (a
    -- checklist, a dropdown with a settings cog) registers its search entry
    -- right before the row, as the index keeps the first entry of a label:
    -- those labels, and the labels of the rows it stands in for, are the
    -- entry's search text. barKey (optional) is the bar a hit opens, in place
    -- of the bar being built.
    local function RowSearch(label, words, barKey)
        if not EllesmereUI._RegisterSearchEntry then return end
        local text = {}
        for i = 1, #words do
            local s = words[i]
            text[#text + 1] = s
            local loc = EllesmereUI.L(s)
            if loc ~= s then text[#text + 1] = loc end
        end
        local labelLoc = EllesmereUI.L(label)
        local section = parent._currentSection and parent._currentSection._sectionName
        if type(section) ~= "string" then section = nil end
        local sel = EllesmereUI._buildingSelector
        local setter, selKey = sel and sel.setter, sel and sel.key
        if barKey then setter, selKey = EllesmereUI._setActionBarKey, barKey end
        EllesmereUI._RegisterSearchEntry(label, labelLoc ~= label and labelLoc or nil,
            table.concat(text, " "), EllesmereUI._buildingModule, EllesmereUI._buildingPage,
            section, setter, selKey)
    end
    -- The DualRow half a checklist takes: a stand-in dropdown whose label
    -- carries the row text and its tooltip. Its getter runs `reads`, which
    -- reads every key the checklist writes, so the Spec Overrides gold walk
    -- marks the slot while one of them is overridden.
    local function ChecklistCfg(text, tooltip, reads)
        return { type="dropdown", text=text, tooltip=tooltip,
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function()
              if reads then reads() end
              return "__placeholder"
          end,
          setValue=function() end }
    end
    -- The checklist in `rgn` (a half built from ChecklistCfg). Spec Overrides
    -- see each click as it happens (the slot's capture); onMenuClosed runs
    -- each time its open menu hides. The search prebuild builds none.
    local function BuildChecklist(rgn, items, get, set, onMenuClosed)
        if EllesmereUI._prebuilding then return end
        if rgn._control then rgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 170, rgn:GetFrameLevel() + 2, items, get, set,
            nil, nil, nil, nil, onMenuClosed, { notifyWrites = true, dimLocked = true })
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -------------------------------------------------------------------
    --  APPEARANCE
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
              disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
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
              disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
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
                    disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
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
                anchorTo = rgn._control,
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
          disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
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
          disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
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

    -- Icon Background | Blizzard Icon Background
    local slotBgRow
    slotBgRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("actionbars", { type="slider", text="Icon Background", min=0, max=100, step=1,
          disabled=BlizzStyleOn, disabledTooltip=EllesmereUI.BlizzStyle.Label("actionbars"), requireState="disabled",
          getValue=function()
              local v = EAB.db.profile.slotBgOpacity
              if v == nil then v = 50 end
              return v
          end,
          setValue=function(v)
              EAB.db.profile.slotBgOpacity = v
              EAB:ApplySlotBackgroundColor()
          end }),
        { type="toggle", text="Blizzard Icon Background",
          tooltip="Shows Blizzard's slot art on empty slots.",
          getValue=function() return EAB.db.profile.showBlizzIconBg or false end,
          setValue=function(v)
              EAB.db.profile.showBlizzIconBg = v
              for _, info in ipairs(ns.BAR_CONFIG or {}) do
                  EAB:ApplyIconBackgroundForBar(info.key)
              end
              EllesmereUI:RefreshPage()
          end });  y = y - h
    do
        local rgn = slotBgRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Icon Background",
            anchorTo = rgn._control,
            disabled = function() return not (EAB.db.profile.showBlizzIconBg or false) end,
            disabledTooltip = "Blizzard Icon Background",
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
    --  End Caps | Bar Background close the section, Bar Background's
    --  other rows following it while it is on. Under the WoW Forever look
    --  End Caps sits beside Bar Frame (the frame and dividers behind the
    --  bar's buttons; both on by default on Action Bar 1 only) and Bar
    --  Background starts the next row, beside its Spacing.
    -------------------------------------------------------------------
    local function BarBgSpacingCfg()
        return { type="slider", text="Spacing", min=0, max=20, step=1,
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
          end }
    end
    local function BarBgSpacingSync(region)
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

    -- Bar Background's other rows: Spacing last, unless it sits beside Bar
    -- Background (the WoW Forever look).
    local function BuildBarBackgroundRows(capsForever)
    local function BackgroundOpacity(settings)
        if settings.bgOpacity ~= nil then return settings.bgOpacity end
        local color = settings.bgColor
        return ((color and color.a) or 0.5) * 100
    end

    -- Section gate: these rows are built only while Bar Background is on for
    -- the selected bar (its SectionToggleSetValue rebuilds the page on a flip).
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
            { type="dropdown", text="Background Border Style",
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
            EllesmereUI.BorderPxSliderCfg{ text="Background Border Size",
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

        -- Background Border Width Offset | Height Offset: the textured border's
        -- outward offsets, their own row while a textured style is selected
        -- (Solid has none; the style setter rebuilds the page). Shown = the
        -- override, else the "actionbars" registry default for the thickness
        -- key ApplyBackgroundForBar passes.
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
                ocfgL.text = "Background Border Width Offset"
                ocfgR.text = "Background Border Height Offset"
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
                anchorTo = region._control,
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
        EllesmereUI.BuildInlineCog(region, { anchorTo = region._control,
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
        EllesmereUI.BuildInlineCog(region, { anchorTo = region._control,
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

    if not capsForever then
        local spacingRow
        spacingRow, h = W:DualRow(parent, y, BarBgSpacingCfg(), EllesmereUI.BlankRowCfg());  y = y - h
        BarBgSpacingSync(spacingRow._leftRegion)
    end

    end -- bgEnabled section gate
    end

    do
        -- A change to Action Bar 1's caps also repaints a bar carrying one
        -- of them (the first-install span).
        local CAPS = EndCapsCtl({
            key = SelectedKey, store = SB, label = "End Caps",
            vertical = function() return not EAB:GetOrientationForBar(SelectedKey()) end,
            write = function(k, v)
                if k then
                    SSet(k, v, function(bk) EAB:ApplyPaddingForBar(bk) end)
                    SUpdatePreviewAndResize()
                else
                    EAB:ApplyPaddingForBar(SelectedKey())
                    SUpdatePreviewAndResize()
                    EllesmereUI:RefreshPage()
                end
                if SelectedKey() == "MainBar" then ns.AB_CapsSpanApply() end
            end,
            copyApply = function(key)
                EAB:ApplyPaddingForBar(key)
                if key == "MainBar" then ns.AB_CapsSpanApply() end
            end,
            syncKeys = GROUP_BAR_ORDER, syncLabels = SHORT_LABELS,
        })
        local bgCfg = { type="toggle", text="Bar Background",
          getValue=function() return SVal("bgEnabled", false) end,
          -- Section gate: its other rows are hidden (not grayed) while off; the wrapper forces the page rebuild.
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              SSet("bgEnabled", v, function(k) EAB:ApplyBackgroundForBar(k) end)
              SUpdatePreview()
          end) }
        local capsRow, bgRgn
        RowSearch("Bar Background", { "Enable Bar Background" })
        if CAPS.forever then
            RowSearch("Bar Frame", { "Show the frame and dividers behind the bar's buttons.",
                "Show Bar Background" })
            capsRow, h = W:DualRow(parent, y,
                CAPS.Cfg(),
                { type="toggle", text="Bar Frame",
                  tooltip="Show the frame and dividers behind the bar's buttons.",
                  getValue=function() return ns.AB_ForeverBg(SelectedKey()) end,
                  setValue=function(v)
                      SSet("foreverBarBg", v and true or false, function(k) EAB:ApplyPaddingForBar(k) end)
                      SUpdatePreviewAndResize()
                  end });  y = y - h
            CAPS.Build(capsRow._leftRegion)
            do
                local rgn = capsRow._rightRegion
                local function BgTo(key, v)
                    local d = EAB.db.profile.bars[key]
                    if d then
                        d.foreverBarBg = v
                        EAB:ApplyPaddingForBar(key)
                    end
                end
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Bar Frame to all Bars",
                    onClick = function()
                        local v = ns.AB_ForeverBg(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do BgTo(key, v) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = ns.AB_ForeverBg(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if ns.AB_ForeverBg(key) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = ns.AB_ForeverBg(SelectedKey())
                            for _, key in ipairs(checkedKeys) do BgTo(key, v) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            local bgOn = SVal("bgEnabled", false)
            local bgRow
            bgRow, h = W:DualRow(parent, y, bgCfg,
                bgOn and BarBgSpacingCfg() or EllesmereUI.BlankRowCfg());  y = y - h
            bgRgn = bgRow._leftRegion
            if bgOn then BarBgSpacingSync(bgRow._rightRegion) end
        else
            capsRow, h = W:DualRow(parent, y, CAPS.Cfg(), bgCfg);  y = y - h
            CAPS.Build(capsRow._leftRegion)
            bgRgn = capsRow._rightRegion
        end
        do
            local region = bgRgn
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
        BuildBarBackgroundRows(CAPS.forever)
    end

    -------------------------------------------------------------------
    --  EFFECTS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "EFFECTS", y);  y = y - h

    -- Desaturate on Cooldown | Alpha on Cooldown
    RowSearch("Alpha on Cooldown", { "Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
        "Alpha when on CD" })
    _, h = W:DualRow(parent, y,
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
        { type="slider", text="Alpha on Cooldown", min=0, max=100, step=5,
          tooltip="Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
          getValue=function() return EAB.db.profile.alphaWhenOnCD or 100 end,
          setValue=function(v)
              EAB.db.profile.alphaWhenOnCD = v
              if EAB.ApplyCDAlphaAll then EAB:ApplyCDAlphaAll() end
          end });  y = y - h

    -- Out of Range Coloring | Cooldown Swipe Opacity
    RowSearch("Cooldown Swipe Opacity", { "Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
        "CD Swipe Opacity" })
    local rangeSwipeRow
    rangeSwipeRow, h = W:DualRow(parent, y,
        { type="toggle", text="Out of Range Coloring",
          getValue=function()
              return SGet("outOfRangeColoring") or false
          end,
          setValue=function(v)
              SSet("outOfRangeColoring", v, function() EAB:ApplyRangeColoring() end)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Cooldown Swipe Opacity", min=0, max=100, step=5, trackWidth=120,
          tooltip="Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
          getValue=function() return EAB.db.profile.cdSwipeAlpha or 80 end,
          setValue=function(v)
              EAB.db.profile.cdSwipeAlpha = v
              if EAB.ApplyCooldownSwipeColor then EAB:ApplyCooldownSwipeColor() end
          end });  y = y - h
    do
        local rgn = rangeSwipeRow._leftRegion
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
        local leftRgn = rangeSwipeRow._leftRegion
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
    -- Inline swatch for Cooldown Swipe Opacity (right): colour-only (hasAlpha=false), since alpha lives on the slider.
    do
        local rgn = rangeSwipeRow._rightRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, rangeSwipeRow:GetFrameLevel() + 5,
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
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Set Cooldown Swipe Opacity above 0"))
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

    -- Hide Charge Count at 0 | Item Information: Item Rank (this bar's) and
    -- Equipped Item Color (Blizzard's equipped-item border, kept in our
    -- square art and the item's rarity color; one setting for every bar,
    -- saved false, not nil, as WoW Forever defaults it on; the Blizzard and
    -- Classic styles draw their own, so it locks under them).
    do
        RowSearch("Item Information", { "Item details shown on action buttons.",
            "Item Rank", "Equipped Item Color",
            "Show Item Rank", "Show Equipped Item Color" })
        local itemRow
        itemRow, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Charge Count at 0",
              tooltip="Hide the charge number on action buttons when it reaches 0, instead of showing a 0. The number returns as soon as a charge or item comes back.",
              getValue=function() return EAB.db.profile.hideZeroCount or false end,
              setValue=function(v)
                  EAB.db.profile.hideZeroCount = v or nil
                  if EAB.RefreshAllCounts then EAB:RefreshAllCounts() end
              end },
            ChecklistCfg("Item Information", "Item details shown on action buttons.", function()
                local _ = SB().showRankIcon
                _ = EAB.db.profile.showEquippedBorder
            end));  y = y - h
        BuildChecklist(itemRow._rightRegion, {
            { key = "rank", label = "Item Rank",
              tooltip = "Shows the consumable rank (quality) diamond icon on action buttons." },
            { key = "equipped", label = "Equipped Item Color",
              tooltip = "Equipped items get a rarity color border.",
              lockedFn = BlizzStyleOn,
              lockedTooltip = function()
                  return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("actionbars"), "disabled")
              end },
        }, function(k)
            if k == "rank" then return SGet("showRankIcon") or false end
            return EAB.db.profile.showEquippedBorder or false
        end, function(k, v)
            if k == "rank" then
                SSet("showRankIcon", v)
                if _G._EAB_Apply then _G._EAB_Apply() end
            else
                EAB.db.profile.showEquippedBorder = v and true or false
                EAB:ApplyEquippedBorder()
            end
        end)
        -- The Apply link copies Item Rank alone: Equipped Item Color is one
        -- setting for every bar.
        do
            local rgn = itemRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Item Rank to all Bars",
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
    end

    -- One Button Assist Icon | blank
    local obaRow
    obaRow, h = W:DualRow(parent, y,
        { type="toggle", text="One Button Assist Icon",
          getValue=function() return EAB.db.profile.obaIconEnabled ~= false end,
          setValue=function(v)
              EAB.db.profile.obaIconEnabled = v
              if ns.RefreshAssistSpinners then ns.RefreshAssistSpinners() end
          end },
        EllesmereUI.BlankRowCfg());  y = y - h
    do
        local rgn = obaRow._leftRegion
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

    -------------------------------------------------------------------
    --  BEHAVIOR & PAGING (MainBar and Bars 2-10); BEHAVIOR on the bars
    --  that do not page (Stance Bar, Pet Bar)
    -------------------------------------------------------------------
    do
        local selKey = SelectedKey()
        local _bkp = ns.EAB_VTABLE and ns.EAB_VTABLE.BAR_KEY_TO_PAGE
        local showPaging = selKey and _bkp and _bkp[selKey]
        if showPaging then
            _, h = W:SectionHeader(parent, "BEHAVIOR & PAGING", y);  y = y - h
        else
            _, h = W:SectionHeader(parent, "BEHAVIOR", y);  y = y - h
        end

        -- Click Through | Disable Tooltips
        local behaviorRow
        behaviorRow, h = W:DualRow(parent, y,
            { type="toggle", text="Click Through",
              getValue=function() return SGet("clickThrough") end,
              setValue=function(v)
                  SSet("clickThrough", v, function(k) EAB:ApplyClickThroughForBar(k) end)
                  -- Its Apply link compares this toggle.
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Disable Tooltips",
              getValue=function()
                  return SGet("disableTooltips") or false
              end,
              setValue=function(v)
                  SSet("disableTooltips", v)
              end });  y = y - h
        do
            local rgn = behaviorRow._leftRegion
            local function CopyTo(key, v)
                EAB.db.profile.bars[key].clickThrough = v
                EAB:ApplyClickThroughForBar(key)
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Click Through to all Bars",
                onClick = function()
                    local v = SB().clickThrough or false
                    for _, key in ipairs(GROUP_BAR_ORDER) do CopyTo(key, v) end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = SB().clickThrough or false
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (EAB.db.profile.bars[key].clickThrough or false) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local v = SB().clickThrough or false
                        for _, key in ipairs(checkedKeys) do CopyTo(key, v) end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = behaviorRow._rightRegion
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

        if showPaging then
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

            local isMain = selKey == "MainBar"
            local function RebuildPaging(k)
                if ns.RebuildBarPaging then ns.RebuildBarPaging(k) end
            end

            local function PagingDropdown(stateId, text)
                return { type="dropdown", text=text,
                  values=pagingValues, order=pagingOrder,
                  getValue=function() return GetPagingVal(stateId) end,
                  setValue=function(v) SetPagingVal(stateId, v) end }
            end
            -- modTargetPaging, the switch both groups below follow while their
            -- own key is unset: until set, on while any of the five states
            -- holds a page.
            local function ModTargetOn()
                local v = SGet("modTargetPaging")
                if v ~= nil then return v end
                local paging = SGet("paging")
                if paging then
                    for stateId in pairs(EAB_VT.MOD_TARGET_PAGING) do
                        if paging[stateId] then return true end
                    end
                end
                return false
            end
            -- Modifier Paging (Shift, Ctrl, Alt) and Target Paging (friendly,
            -- hostile target): each its own key, read through ModTargetOn
            -- while unset; modTargetPaging false holds both off whatever they
            -- say (the runtime's rule too). Off hides the group's dropdowns
            -- and the bar stops paging on its states; their picks are kept for
            -- when it is turned back on.
            local function ModifierOn()
                if SGet("modTargetPaging") == false then return false end
                local v = SGet("modifierPaging")
                if v ~= nil then return v and true or false end
                return ModTargetOn() and true or false
            end
            local function TargetOn()
                if SGet("modTargetPaging") == false then return false end
                local v = SGet("targetPaging")
                if v ~= nil then return v and true or false end
                return ModTargetOn() and true or false
            end
            local modOn, targetOn = ModifierOn(), TargetOn()

            -- Paging Options. Form Paging and Skyriding Paging are Action Bar
            -- 1's (the only bar the engine pages off its bonus bar), each the
            -- inverse of its disable key: unchecked suppresses the implicit
            -- swap only, so an explicit page below still applies. No
            -- skyriding on WoW Forever.
            local pagingItems = {}
            if isMain then
                pagingItems[#pagingItems + 1] = { key = "form", label = "Form Paging",
                    tooltip = "While unchecked, this bar keeps its page in any form." }
                if not EllesmereUI.IS_FOREVER then
                    pagingItems[#pagingItems + 1] = { key = "skyriding", label = "Skyriding Paging",
                        tooltip = "While unchecked, this bar keeps its page while skyriding." }
                end
            end
            pagingItems[#pagingItems + 1] = { key = "modifier", label = "Modifier Paging",
                tooltip = "Pages this bar while Shift, Ctrl or Alt is held." }
            pagingItems[#pagingItems + 1] = { key = "target", label = "Target Paging",
                tooltip = "Pages this bar while you have a friendly or hostile target." }
            local function PagingGet(k)
                if k == "form" then return not SGet("disableFormPaging") end
                if k == "skyriding" then return not SGet("disableSkyridingPaging") end
                if k == "modifier" then return ModifierOn() end
                return TargetOn()
            end
            -- Writing one group's key first settles the other group's key to
            -- what it shows. Under modTargetPaging false (both held off),
            -- ticking a group clears it and the other group keeps its off.
            -- While both the other key and modTargetPaging are unset, the other
            -- group falls back to the five states' pages, so a page picked for
            -- one group would otherwise check the other: it is pinned. The
            -- runtime pages that group exactly as before (the pin reads false
            -- only while none of the five states holds a page).
            local function PagingSet(k, v)
                if k == "form" then
                    SSet("disableFormPaging", not v, RebuildPaging)
                elseif k == "skyriding" then
                    SSet("disableSkyridingPaging", not v, RebuildPaging)
                else
                    local s = SB()
                    local mine = (k == "modifier") and "modifierPaging" or "targetPaging"
                    local other = (k == "modifier") and "targetPaging" or "modifierPaging"
                    if s.modTargetPaging == false then
                        if v then
                            s.modTargetPaging = nil
                            s[other] = false
                        end
                    elseif s[other] == nil and s.modTargetPaging == nil then
                        if k == "modifier" then s[other] = TargetOn() else s[other] = ModifierOn() end
                    end
                    SSet(mine, v and true or false, RebuildPaging)
                end
            end
            -- A group's dropdowns exist only while it is on: the page is built
            -- again once the menu closed, never while it is open.
            local function PagingMenuClosed()
                if ModifierOn() ~= modOn or TargetOn() ~= targetOn then
                    EllesmereUI:RefreshPage(true)
                end
            end

            -- Paging Arrows (Action Bar 1): a view over showPagingArrows
            -- (Always) and pagingArrowsWhilePaged (While Paged, the default;
            -- false with the arrows off is Never).
            local function ArrowsMode()
                if SGet("showPagingArrows") then return "always" end
                if SGet("pagingArrowsWhilePaged") == false then return "never" end
                return "paged"
            end

            -- The section's paging slots in order, paired into rows.
            local slots = {}
            slots[#slots + 1] = ChecklistCfg("Paging Options", "What switches this bar to another page.", function()
                local s = SB()
                local _ = s.disableFormPaging
                _ = s.disableSkyridingPaging
                _ = s.modifierPaging
                _ = s.targetPaging
                _ = s.modTargetPaging
            end)
            if isMain then
                slots[#slots + 1] = { type="dropdown", text="Paging Arrows",
                  tooltip="When Action Bar 1's paging arrows show.",
                  values={ never="Never", always="Always", paged="While Paged" },
                  order={ "never", "always", "paged" },
                  getValue=ArrowsMode,
                  setValue=function(v)
                      local s = SB()
                      if v == "always" then
                          s.showPagingArrows = true
                      else
                          s.showPagingArrows = false
                          s.pagingArrowsWhilePaged = (v == "paged")
                      end
                      if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                      SUpdatePreviewAndResize()
                      EllesmereUI:RefreshPage()
                  end }
            end
            if modOn then
                slots[#slots + 1] = PagingDropdown("shift", "Shift Modifier")
                slots[#slots + 1] = PagingDropdown("ctrl", "Ctrl Modifier")
                slots[#slots + 1] = PagingDropdown("alt", "Alt Modifier")
            end
            if targetOn then
                slots[#slots + 1] = PagingDropdown("help", "Friendly Target")
                slots[#slots + 1] = PagingDropdown("harm", "Hostile Target")
            end
            -- Class form dropdowns
            local classStatesLocal = PG_STATES.class and PG_STATES.class[playerClass]
            if classStatesLocal then
                for _, st in ipairs(classStatesLocal) do
                    slots[#slots + 1] = PagingDropdown(st.id, st.label)
                end
            end
            -- Both entries open Action Bar 1, whichever bar is built first:
            -- only its Paging Options lists Form and Skyriding Paging, and
            -- only it has Paging Arrows.
            do
                local words = { "What switches this bar to another page.",
                    "Form Paging", "Disable Form Paging" }
                if not EllesmereUI.IS_FOREVER then
                    words[#words + 1] = "Skyriding Paging"
                    words[#words + 1] = "Disable Skyriding Paging"
                end
                words[#words + 1] = "Modifier Paging"
                words[#words + 1] = "Target Paging"
                words[#words + 1] = "Modifier/Target Paging"
                RowSearch("Paging Options", words, "MainBar")
                RowSearch("Paging Arrows", { "When Action Bar 1's paging arrows show.",
                    "Never", "Always", "While Paged", "Show Arrows on Right",
                    "Skip Visible Bars When Paging", "Show While Paged" }, "MainBar")
            end
            local pagingRow
            for i = 1, #slots, 2 do
                local r
                r, h = W:DualRow(parent, y, slots[i], slots[i + 1] or EllesmereUI.BlankRowCfg());  y = y - h
                pagingRow = pagingRow or r
            end
            BuildChecklist(pagingRow._leftRegion, pagingItems, PagingGet, PagingSet, PagingMenuClosed)

            if isMain then
                local rRgn = pagingRow._rightRegion
                local function RelayoutArrows()
                    if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                end
                -- The cog's settings join the slot's capture, so the Spec
                -- Overrides gold walk marks the slot while one is overridden.
                EllesmereUI.BuildInlineCog(rRgn, {
                    title = "Paging Arrow Settings",
                    anchorTo = rRgn._control,
                    captureRegion = rRgn,
                    rows = {
                        { type="toggle", label="Show Arrows on Right",
                          get=function() return SGet("pagingArrowsRight") or false end,
                          set=function(v)
                              SSet("pagingArrowsRight", v, RelayoutArrows)
                              SUpdatePreviewAndResize()
                          end,
                          disabled=function() return ArrowsMode() == "never" end,
                          disabledTooltip="Paging Arrows" },
                        -- Never greyed: it also steers the next and previous
                        -- page keybinds.
                        { type="toggle", label="Skip Visible Bars When Paging",
                          tooltip="Next and previous page, from the keybinds or the paging arrows, skip the pages your other enabled bars use.",
                          get=function() return SGet("skipVisiblePagingBars") or false end,
                          set=function(v)
                              SSet("skipVisiblePagingBars", v, function() ns.RefreshPagingCycleMacros() end)
                          end },
                    },
                })
            end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  TEXT
    -------------------------------------------------------------------
    textSectionHeader, h = W:SectionHeader(parent, SECTION_TEXT, y);  y = y - h

    -- Each row's left control turns its text on or off. While it is off, the
    -- right half greys out: the size slider, its offsets cog and its colour.
    local TextOff = {
        cooldown = function() return not GetCVarBool("countdownForCooldowns") end,
        -- Charge Numbers with nothing ticked.
        charges = function()
            local s = SB()
            return (s.hideChargeCount and s.hideStackCount and s.hideItemCount) and true or false
        end,
        keybind = function() return SGet("hideKeybind") and true or false end,
        macro = function() return SGet("hideMacroText") and true or false end,
    }

    -- Cooldown Numbers | Cooldown Text Size. Cooldown Numbers LIVE-toggles
    -- Blizzard's countdownForCooldowns CVar and is never stored in our DB;
    -- the CVar is written only on an actual user flip.
    local cdTextRow
    cdTextRow, h = W:DualRow(parent, y,
        { type="toggle", text="Cooldown Numbers",
          tooltip="Toggles Blizzard's cooldown numbers setting.",
          getValue=function() return GetCVarBool("countdownForCooldowns") end,
          setValue=function(v)
              if InCombatLockdown() then return end
              EllesmereUI.SetCVar("countdownForCooldowns", v and "1" or "0", "EllesmereUIActionBars")
              -- Refresh so the cogs and the right half dim/undim with the CVar state.
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Cooldown Text Size", min=6, max=30, step=1, trackWidth=120,
          disabled=TextOff.cooldown, disabledTooltip="Cooldown Numbers",
          getValue=function() return SVal("cooldownFontSize", 12) end,
          setValue=function(v)
              SSet("cooldownFontSize", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
              SUpdatePreview()
          end });  y = y - h
    -- Inline cog: Cooldown Numbers (left). Holds the charge-spell recharge toggle
    -- (our feature, DB-saved); dimmed when the CVar is off, since no numbers show then.
    do
        local rgn = cdTextRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Cooldown Numbers",
            anchorTo = rgn._control,
            disabled = TextOff.cooldown,
            disabledTooltip = "Cooldown Numbers",
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

    do
        local rgn = cdTextRow._rightRegion
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
        local rgn = cdTextRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Cooldown Text",
            disabled = TextOff.cooldown,
            disabledTooltip = "Cooldown Numbers",
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

        EllesmereUI.BuildInlineSwatches(rgn, {
            { getValue = function()
                  local c = SGet("cooldownTextColor")
                  if not c then return 1, 1, 1 end
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  SSetColor("cooldownTextColor", r, g, b, nil, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                  SUpdatePreview()
              end },
        }, { disabled = TextOff.cooldown, disabledTooltip = "Cooldown Numbers" })
    end

    -- Charge Numbers | Charge Text Size. Charge Numbers: which counts this
    -- bar's buttons show, each its own key (true hides that count; unset,
    -- the default, shows it).
    RowSearch("Charge Numbers", { "Which counts show on this bar's buttons.",
        "Charges", "Stacks", "Item Count" })
    RowSearch("Charge Text Size", { "Charges Text Size" })
    chargesRow, h = W:DualRow(parent, y,
        ChecklistCfg("Charge Numbers", "Which counts show on this bar's buttons.", function()
            local s = SB()
            local _ = s.hideChargeCount
            _ = s.hideStackCount
            _ = s.hideItemCount
        end),
        { type="slider", text="Charge Text Size", min=6, max=30, step=1, trackWidth=120,
          disabled=TextOff.charges, disabledTooltip="Charge Numbers",
          getValue=function() return SVal("countFontSize", 12) end,
          setValue=function(v)
              SSet("countFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end });  y = y - h
    BuildChecklist(chargesRow._leftRegion, {
        { key = "hideChargeCount", label = "Charges",
          tooltip = "The charges a spell has left." },
        { key = "hideStackCount", label = "Stacks",
          tooltip = "The count some spells show, such as stacks of a buff they spend." },
        { key = "hideItemCount", label = "Item Count",
          tooltip = "How many of an item you carry, such as potions or a spell's reagent." },
    }, function(k) return not SGet(k) end, function(k, v)
        SSet(k, (not v) and true or nil, function(bk) EAB:RefreshCountVisibility(bk) end)
        SUpdatePreview()
    end)
    do
        local rgn = chargesRow._rightRegion
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
        local rgn = chargesRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Charges Text Offsets",
            disabled = TextOff.charges,
            disabledTooltip = "Charge Numbers",
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

        EllesmereUI.BuildInlineSwatches(rgn, {
            { getValue = function()
                  local c = SGet("countFontColor")
                  if not c then return 1, 1, 1 end
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  SSetColor("countFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                  SUpdatePreview()
              end },
        }, { disabled = TextOff.charges, disabledTooltip = "Charge Numbers" })
    end

    -- Keybind Text | Keybind Text Size
    RowSearch("Keybind Text", { "Hide Keybind Text" })
    row, h = W:DualRow(parent, y,
        { type="toggle", text="Keybind Text",
          -- Shows the inverse of hideKeybind, the stored setting.
          getValue=function()
              return not SGet("hideKeybind")
          end,
          setValue=function(v)
              SSet("hideKeybind", not v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Keybind Text Size", min=6, max=30, step=1, trackWidth=120,
          disabled=TextOff.keybind, disabledTooltip="Keybind Text",
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
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Keybind Text Offsets",
            disabled = TextOff.keybind,
            disabledTooltip = "Keybind Text",
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

        EllesmereUI.BuildInlineSwatches(rgn, {
            { getValue = function()
                  local c = SGet("keybindFontColor")
                  if not c then return 1, 1, 1 end
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  SSetColor("keybindFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                  SUpdatePreview()
              end },
        }, { disabled = TextOff.keybind, disabledTooltip = "Keybind Text" })
    end

    -- Macro Text | Macro Text Size
    RowSearch("Macro Text", { "Hide Macro Text" })
    local macroRow
    macroRow, h = W:DualRow(parent, y,
        { type="toggle", text="Macro Text",
          -- Shows the inverse of hideMacroText, the stored setting.
          getValue=function()
              return not SGet("hideMacroText")
          end,
          setValue=function(v)
              SSet("hideMacroText", not v, function(k) EAB:ApplyFontsForBar(k) end)
              SUpdatePreview()
          end },
        { type="slider", text="Macro Text Size", min=6, max=30, step=1, trackWidth=120,
          disabled=TextOff.macro, disabledTooltip="Macro Text",
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
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Macro Text Offsets",
            disabled = TextOff.macro,
            disabledTooltip = "Macro Text",
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

        EllesmereUI.BuildInlineSwatches(rgn, {
            { getValue = function()
                  local c = SGet("macroFontColor")
                  if not c then return 1, 1, 1 end
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  SSetColor("macroFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                  SUpdatePreview()
              end },
        }, { disabled = TextOff.macro, disabledTooltip = "Macro Text" })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return y, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildBarAppearance = BuildBarAppearance
