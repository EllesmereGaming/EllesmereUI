if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\ClassResourceSection_Options.lua
--  Resource Bars options: CLASS RESOURCE BAR section builder. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Blizzard Class Resource Art stands in for the class resource bar: the CLASS
-- RESOURCE BAR controls that only style our own bar (texture, colours, pips,
-- text, borders) grey out and are blocked with a disabled tooltip while it
-- does; the ones that still drive the art or its slot stay live (see the
-- keep-list in ns.ERB_BuildClassResourceSection). One block per half-row region
-- (the Unit Frames Dark Mode block pattern), so blocks ride their rows through
-- the inline search. Built on the first active state only and tracked live by
-- one widget refresh per call (the toggle refreshes without a rebuild).
ns.ERB_BlizzArtBlockRegions = function(regions)
    if EllesmereUI._prebuilding or not regions or #regions == 0 then return end
    local blocks
    local function Update()
        local on = (ns.ERB_BlizzArtActiveNow and ns.ERB_BlizzArtActiveNow()) and true or false
        if on and not blocks then
            blocks = {}
            for i = 1, #regions do
                local rgn = regions[i]
                local b = CreateFrame("Frame", nil, rgn)
                b:SetAllPoints()
                b:SetFrameLevel(rgn:GetFrameLevel() + 50)
                b:EnableMouse(true)
                b:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(b, EllesmereUI.DisabledTooltip("Blizzard Class Resource Art", "disabled"))
                end)
                b:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                blocks[#blocks + 1] = b
            end
        end
        if not blocks then return end
        for i = 1, #blocks do
            local b = blocks[i]
            b:GetParent():SetAlpha(on and 0.3 or 1)
            b:SetShown(on)
        end
    end
    Update()
    EllesmereUI.RegisterWidgetRefresh(Update)
end

-- Shared, context-aware CLASS RESOURCE (secondary) section builder. ctx.cfg() ->
-- secondary table. The Guardian/Prot special-bar rows show in both modes for the
-- relevant spec (global storage). The Hide-Power cog is Simple-only. Threshold
-- (bespoke popup) is appended in a later chunk.
function ns.ERB_BuildClassResourceSection(parent, y, ctx)
    local env = ns._ERB_OptEnv
    local DB, PP, SmoothRefresh, RefreshClass = env.DB, env.PP, env.SmoothRefresh, env.RefreshClass
    local RebuildClass, RebuildPower, AddFormBarBtn, AddFormTextBtn = env.RebuildClass, env.RebuildPower, env.AddFormBarBtn, env.AddFormTextBtn
    local AttachThresholdNotice, ShowBandEditor, ShowBuffEditor, ShowSpenderEditor = env.AttachThresholdNotice, env.ShowBandEditor, env.ShowBuffEditor, env.ShowSpenderEditor
    local SkinCardButton = env.SkinCardButton
    local BAND_HELP_TIP, BAND_REPLACES_TIP, BUFF_HELP_TIP, SPENDER_HELP_TIP = env.BAND_HELP_TIP, env.BAND_REPLACES_TIP, env.BUFF_HELP_TIP, env.SPENDER_HELP_TIP
    local STAGGER_PCT_TIP, CLASS_COLORS, SIDE_PAD, THR_BORDER_WHITE = env.STAGGER_PCT_TIP, env.CLASS_COLORS, env.SIDE_PAD, env.THR_BORDER_WHITE
    local PAGE_DISPLAY = env.PAGE_DISPLAY
    -- Every half-row this section builds is recorded (a thin wrapper over the
    -- widget factory) so Blizzard Class Resource Art can block the controls
    -- that only style our own bar while it stands in (ns.ERB_BlizzArtBlockRegions).
    -- Kept live: showing the resource at all (with its per-form and power-bar
    -- controls), the slot size, the opacity and fade the art follows, and the
    -- special bars that pick which resource is drawn.
    local artKeep = {
        ["Show Class Resource"] = true, ["Height"] = true, ["Width"] = true, ["Opacity"] = true,
        ["Guardian Druid Ironfur Bar"] = true, ["Show Hash Lines"] = true,
        ["Prot Warrior Ignore Pain Bar"] = true, ["Show Hash Line"] = true,
        ["Arms Warrior Sweeping Strikes Bar"] = true,
    }
    local artRegions = {}
    local W = setmetatable({
        DualRow = function(_, p, yy, l, r, ...)
            local row, rh = EllesmereUI.Widgets:DualRow(p, yy, l, r, ...)
            if row then
                if l and l.text and l.text ~= "" and not artKeep[l.text] and row._leftRegion then
                    artRegions[#artRegions + 1] = row._leftRegion
                end
                if r and r.text and r.text ~= "" and not artKeep[r.text] and row._rightRegion then
                    artRegions[#artRegions + 1] = row._rightRegion
                end
            end
            return row, rh
        end,
    }, { __index = EllesmereUI.Widgets })

    local _, h
    local function cfg() return ctx.cfg() end
    local function classOff() local c = cfg(); return not (c and c.enabled) end

    local hdr
    hdr, h = W:SectionHeader(parent, "CLASS RESOURCE BAR", y);  y = y - h

    local _advTop = y  -- content top; also used by the Simple override overlay
    -- Guardian Ironfur + Prot Ignore Pain special bars stay global at runtime (stored on
    -- DB().secondary, not per-spec); the row shows for the active spec.
    -- Retail only: WoW Forever has none of these specs.
    if not EllesmereUI.IS_FOREVER then
        local function _IsGuardianDruid()
            local _, cf = UnitClass("player")
            if cf ~= "DRUID" then return false end
            local s = C_SpecializationInfo.GetSpecialization()
            local sid = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return sid == 104
        end
        if _IsGuardianDruid() then
            local _ifOff = function() local p = DB(); return p and not p.secondary.guardianIronfurBar end
            local _, hh = W:DualRow(parent, y,
                { type = "toggle", text = "Guardian Druid Ironfur Bar",
                  tooltip = "Replaces the class resource bar with an Ironfur tracker. Each Ironfur cast adds a hash line that slides from right to left as its buff decays. Duration is talent-aware (Ursoc's Endurance and Guardian of Elune).",
                  getValue = function() local p = DB(); return p and p.secondary.guardianIronfurBar end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.guardianIronfurBar = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", text = "Show Hash Lines",
                  disabled = _ifOff,
                  disabledTooltip = "Guardian Druid Ironfur Bar",
                  getValue = function() local p = DB(); return p and p.secondary.guardianShowHashLines ~= false end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.guardianShowHashLines = v; SmoothRefresh()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - hh
        end
        local function _IsProtWarrior()
            local _, cf = UnitClass("player")
            if cf ~= "WARRIOR" then return false end
            local s = C_SpecializationInfo.GetSpecialization()
            local sid = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return sid == 73
        end
        if _IsProtWarrior() then
            -- Translated in halves so the CDM sentence keeps its existing locale
            -- entries; ShowWidgetTooltip L()s the joined string, a harmless miss.
            -- The first half stays a variable: its escaped quotes would come back
            -- truncated from the static key extractor.
            local ipBarTipCDM = "Creates a class resource bar for Ignore Pain tracking. To see stack text, you must have Ignore Pain tracked in your Blizzard CDM \"Tracked Buffs\" or \"Tracked Bars\" section."
            local ipBarTip = EllesmereUI.L(ipBarTipCDM) .. " " .. EllesmereUI.L("Tracking it also makes the fill show Ignore Pain alone; without it the fill shows your total absorb, so other shields can add to it.")
            local ipHashTip = "Draws a hash line that resets to the right edge when you cast Ignore Pain and slides left as the buff runs out."
            local ipRow
            ipRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Prot Warrior Ignore Pain Bar",
                  tooltip = ipBarTip,
                  getValue = function() local p = DB(); return p and p.secondary.protIgnorePainBar end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.protIgnorePainBar = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", text = "Show Hash Line",
                  tooltip = ipHashTip,
                  disabled = function() local p = DB(); return not (p and p.secondary.protIgnorePainBar) end,
                  disabledTooltip = "Prot Warrior Ignore Pain Bar",
                  getValue = function() local p = DB(); return p and p.secondary.protIgnorePainHashLine ~= false end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.protIgnorePainHashLine = v
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
            local function IPControlTip(rgn, tip)
                local c = rgn and rgn._control
                if not c or not c.HookScript then return end
                c:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tip) end)
                c:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            IPControlTip(ipRow._leftRegion, ipBarTip)
            IPControlTip(ipRow._rightRegion, ipHashTip)
        end
        local function _IsArmsWarrior()
            local _, cf = UnitClass("player")
            if cf ~= "WARRIOR" then return false end
            local s = C_SpecializationInfo.GetSpecialization()
            local sid = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return sid == 71
        end
        if _IsArmsWarrior() then
            local ssBarTip = "Shows Sweeping Strikes charges on the resource bar; Unit Frames and the personal Nameplate show them regardless."
            local ssRow
            ssRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Arms Warrior Sweeping Strikes Bar",
                  tooltip = ssBarTip,
                  getValue = function() local p = DB(); return p and p.secondary.armsSweepingStrikesBar end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.armsSweepingStrikesBar = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "label", text = "" }
            );  y = y - h
        end
    end

    -- Row 1: Show Class Resource | Orientation
    local classEnableRow
    classEnableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Class Resource",
          getValue = function() local c = cfg(); return c and c.enabled end,
          -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
          setValue = EllesmereUI.DependentSetValue(
              function() local c = cfg(); return c and c.enabled end,
              function(v)
                  local c = cfg(); if not c then return end
                  c.enabled = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end) },
        { type = "dropdown", text = "Orientation",
          disabled = classOff,
          disabledTooltip = "Class Resource",
          values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
          order  = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
          getValue = function()
              local c = cfg(); if not c then return "HORIZONTAL" end
              local v = c.pipOrientation or "HORIZONTAL"
              if v == "VERTICAL" then v = "VERTICAL_DOWN" end
              return v
          end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.pipOrientation = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    -- Hide-Power cog: Simple only
    if not ctx.advanced then
        if not EllesmereUI._prebuilding then
            local rgn = classEnableRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = classOff,
                disabledTooltip = "Class Resource",
                title = "Class Resource",
                rows = {
                    { type = "toggle", label = "Hide Power Bar if Resource",
                      get = function() local c = cfg(); return c and c.hidePowerIfResource end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.hidePowerIfResource = v; RebuildClass()
                      end },
                    -- Draw Above Other Bars: the class resource slot above the health,
                    -- power and GCD borders (ns.ERB_ClassRaise).
                    { type = "toggle", label = "Draw Above Other Bars",
                      tooltip = "Draws the class resource bar above the health, power and GCD bar borders.",
                      get = function() local c = cfg(); return c and c.raiseLevel or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.raiseLevel = v and true or false; RebuildClass()
                      end },
                },
            })
        end
        -- Per-spec class-resource enables live in Spec Overrides: "Show Class Resource" is captured while editing as a group.
    end
    -- Chains left of the Hide-Power cog in Simple mode (rgn._lastInline), or of the toggle itself in Advanced
    if not EllesmereUI._prebuilding then
    AddFormBarBtn(classEnableRow._leftRegion, cfg, RebuildClass)
    end

    -- Everything below Row 1 is hidden entirely while the bar is off. classColorRow is
    -- hoisted above the gate: the section returns it for the Simple page's count-text
    -- click mapping (nil while hidden).
    local classColorRow
    if not classOff() then
    -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only).
    -- Orientation-aware: this bar has its OWN orientation key and its renderer treats
    -- anything not HORIZONTAL as vertical, so the value is normalized before the shared helper sees it.
    local function classOri()
        local c = cfg()
        local o = (c and c.pipOrientation) or "HORIZONTAL"
        return o ~= "HORIZONTAL" and "VERTICAL_UP" or "HORIZONTAL"
    end
    local function classGuard(propKey)
        return ns.OrientedMatchGuard("ERB_ClassResource", propKey, classOri, classOff, "Class Resource")
    end
    local chDis, chTip, chRaw = classGuard("Height")
    local cwDis, cwTip, cwRaw = classGuard("Width")
    local classSizeRow
    classSizeRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Height",
          min = 1, max = 60, step = 1,
          disabled = chDis, disabledTooltip = chTip, rawTooltip = chRaw,
          getValue = function() local c = cfg(); return c and c.pipHeight or 20 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.pipHeight = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Width",
          min = 10, max = 800, step = 1,
          disabled = cwDis, disabledTooltip = cwTip, rawTooltip = cwRaw,
          getValue = function() local c = cfg(); return c and c.pipWidth or 214 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.pipWidth = v; SmoothRefresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if not ctx.advanced and ctx.syncRows then
        ctx.syncRows.classHeight = classSizeRow._leftRegion
        ctx.syncRows.classWidth  = classSizeRow._rightRegion
        if not EllesmereUI._prebuilding then
            local rgn = classSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.secondary.pipHeight or 20
                    p.primary.height = v; p.health.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.secondary.pipHeight or 20
                    return (p.primary.height or 16) == v and (p.health.height or 20) == v
                end,
                flashTargets = function() return { ctx.syncRows.classHeight, ctx.syncRows.powerHeight, ctx.syncRows.healthHeight } end,
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = classSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local totalW = p.secondary.pipWidth or 214
                    p.primary.width = totalW; p.health.width = totalW
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local totalW = p.secondary.pipWidth or 214
                    return (p.primary.width or 220) == totalW and (p.health.width or 220) == totalW
                end,
                flashTargets = function() return { ctx.syncRows.classWidth, ctx.syncRows.powerWidth, ctx.syncRows.healthWidth } end,
            })
        end
    end

    -- Border Style dropdown + inline offset cog
    do
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local classBsRow
        classBsRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("resourcebars", { type="dropdown", text="Border Style",
              disabled = classOff,
              disabledTooltip = "Class Resource",
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
                  RebuildClass(); EllesmereUI:RefreshPage(true)
              end }),
            ns.ERB_ClassicBorderRow() and ns.ERB_ClassicBorderSizeCfg(cfg, classOff, "Class Resource", RebuildClass, "ERB_ClassResource") or
            EllesmereUI.BlizzStyle.Gate("resourcebars", EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = classOff,
              disabledTooltip = "Class Resource",
              getStep = function() local c = cfg(); return c and c.borderSize or 1 end,
              setStep = function(v) local c = cfg(); if c then c.borderSize = v end end,
              getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
              getPx = function() local c = cfg(); return c and c.borderSizePx end,
              setPx = function(v) local c = cfg(); if c then c.borderSizePx = v end end,
              apply = function() RebuildClass(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
        do
            local c = cfg()
            local tex = c and c.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step() local c = cfg(); return c and c.borderSize or 1 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = classOff,
                    disabledTooltip = "Class Resource",
                    getTex = function() local c = cfg(); return c and c.borderTexture or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local c = cfg(); return c and c.borderSizePx end,
                    getX = function() local c = cfg(); return c and c.borderTextureOffset end,
                    setX = function(v) local c = cfg(); if c then c.borderTextureOffset = v end end,
                    getY = function() local c = cfg(); return c and c.borderTextureOffsetY end,
                    setY = function(v) local c = cfg(); if c then c.borderTextureOffsetY = v end end,
                    apply = function() RebuildClass(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("resourcebars", ocfgR));  y = y - h
            end
        end
        if not ctx.advanced and ctx.syncRows then ctx.syncRows.classBorder = classBsRow._rightRegion end
        if not EllesmereUI._prebuilding and not ns.ERB_ClassicBorderRow() then
            local rgn = classBsRow._rightRegion
            local ctrl = rgn._control
            local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                rgn, classBsRow:GetFrameLevel() + 3,
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
        end
        if not EllesmereUI._prebuilding then
            local rgn = classBsRow._leftRegion
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
                          c.borderTextureShiftX = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
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
                          c.borderTextureShiftY = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local c = cfg(); return c and c.borderBehind or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderBehind = v == false and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    -- Extend Top / Extend Bottom: the full-bar border only, which pip and
                    -- rune resources drop under Border on individual pips (bar types keep it).
                    { type = "slider", label = "Extend Top", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                      disabled = function() local c = cfg(); return (c and c.borderOnPips and not ns.IsBarTypeSecondary()) and true or false end,
                      disabledTooltip = "This option can't be used while Border on individual pips is enabled.", rawTooltip = true,
                      get = function() local c = cfg(); return c and c.borderExtendTop or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendTop = v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Extend Bottom", min = 0, max = 50, step = 1,
                      tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                      disabled = function() local c = cfg(); return (c and c.borderOnPips and not ns.IsBarTypeSecondary()) and true or false end,
                      disabledTooltip = "This option can't be used while Border on individual pips is enabled.", rawTooltip = true,
                      get = function() local c = cfg(); return c and c.borderExtendBottom or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendBottom = v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    -- Separators: None = off (edgeSep false); an art entry turns them on
                    -- with that art. The rows below pick its lines; Bar Spacing and the
                    -- gap colour stay the user's own (never written here).
                    { type = "dropdown", label = "Separators", values = sepValues, order = sepOrder,
                      tooltip = "Draws separator lines along the bar edge and between the pips.",
                      get = function()
                          local c = cfg(); if not (c and c.edgeSep) then return "none" end
                          return c.edgeSepArt or "match"
                      end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          if v == "none" then c.edgeSep = false else c.edgeSep = true; c.edgeSepArt = v end
                          RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Horizontal Separator",
                      tooltip = "Draws the line along the bar's bottom edge.",
                      disabled = function() local c = cfg(); return not (c and c.edgeSep) end,
                      disabledTooltip = "Separators",
                      get = function() local c = cfg(); return c and c.edgeSepH ~= false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.edgeSepH = v and true or false; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Separator Y Offset", min = -50, max = 50, step = 1,
                      disabled = function() local c = cfg(); return not (c and c.edgeSep and c.edgeSepH ~= false) end,
                      disabledTooltip = function() local c = cfg(); return (c and c.edgeSep) and "Horizontal Separator" or "Separators" end,
                      get = function() local c = cfg(); return c and c.edgeSepY or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.edgeSepY = v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", label = "Vertical Separators",
                      tooltip = "Draws a line in each gap between the pips.",
                      disabled = function() local c = cfg(); return (not (c and c.edgeSep)) or ns.IsBarTypeSecondary() end,
                      disabledTooltip = function()
                          local c = cfg(); if not (c and c.edgeSep) then return "Separators" end
                          return "This option applies to pip and rune resources only."
                      end,
                      rawTooltip = function() local c = cfg(); return (c and c.edgeSep) and true or false end,
                      get = function() local c = cfg(); return c and c.edgeSepV ~= false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.edgeSepV = v and true or false; RebuildClass(); EllesmereUI:RefreshPage()
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
        -- Cross-bar sync icons: Simple page only
        if not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding and ns.ERB_ClassicBorderRow() then
            ns.ERB_ClassicBorderSync(classBsRow._rightRegion, DB, "secondary", SmoothRefresh,
                function() return { ctx.syncRows.classBorder, ctx.syncRows.powerBorder, ctx.syncRows.healthBorder } end)
        elseif not ctx.advanced and ctx.syncRows and not EllesmereUI._prebuilding then
            -- Border Style: class -> primary + health
            EllesmereUI.BuildSyncIcon({
                region  = classBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local s = p.secondary
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                        ns.ERB_CopyBorderPx(t, s)
                        t.borderBehind = s.borderBehind
                    end
                    apply(p.primary); apply(p.health)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.secondary.borderTexture or "solid"
                    local bh = p.secondary.borderBehind or false
                    return (p.primary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                        and (p.primary.borderBehind or false) == bh and (p.health.borderBehind or false) == bh
                end,
                flashTargets = function() return { classBsRow._leftRegion } end,
            })
            -- Border: right region of the Border Style row
            EllesmereUI.BuildSyncIcon({
                region  = classBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local was = ns.ERB_TexturedBars(p)
                    local r, g, b, a = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA
                    local sz = p.secondary.borderSize or 1
                    local bt = p.secondary.borderTexture or "solid"
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz; p.primary.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.primary, p.secondary)
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz; p.health.borderTexture = bt
                    ns.ERB_CopyBorderPx(p.health, p.secondary)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA, p.secondary.borderSize or 1
                    local sbt = p.secondary.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt and ns.ERB_SameBorderPx(t, p.secondary) end
                    return eq(p.primary) and eq(p.health)
                end,
                flashTargets = function() return { ctx.syncRows.classBorder, ctx.syncRows.powerBorder, ctx.syncRows.healthBorder } end,
            })
        end

        -- Pip Border cog on Border Style (left region): per-pip borders
        -- instead of one border around the whole bar.
        if not EllesmereUI._prebuilding then
            local rgn = classBsRow._leftRegion
            local lastInline = rgn._lastInline or rgn._control
            local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.COGS_ICON,
                title = "Pip Border",
                rows = {
                    { type = "toggle", label = "Border on individual pips",
                      tooltip = "Draws a border around each pip instead of the bar as a whole.",
                      get = function() local c = cfg(); return c and c.borderOnPips end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderOnPips = v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    -- Background on individual pips: each pip's own backdrop in place of
                    -- the full-bar one, so the gaps stay clear (pip and rune resources;
                    -- Blizzard Style stands it down at runtime).
                    { type = "toggle", label = "Background on individual pips",
                      tooltip = "Draws the class resource background inside each pip so the gaps between pips stay clear.",
                      disabled = function()
                          local c = cfg()
                          return (not (c and c.borderOnPips)) or ns.IsBarTypeSecondary()
                      end,
                      disabledTooltip = function()
                          if ns.IsBarTypeSecondary() then return "This option applies to pip and rune resources only." end
                          return "Border on individual pips"
                      end,
                      rawTooltip = function() return ns.IsBarTypeSecondary() and true or false end,
                      get = function() local c = cfg(); return c and c.pipBgOnPips or false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.pipBgOnPips = v and true or false; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                },
            })

            cogBtn:Show()

            -- Position only: the texture-style dropdown adds/removes its own
            -- inline elements, so the cog re-seats beside whichever is last.
            local function UpdateCogPos()
                local c = cfg()
                local tex = c and c.borderTexture or "solid"
                if tex == "solid" then
                    PP.Point(cogBtn, "RIGHT", rgn._control, "LEFT", -8, 0)
                else
                    PP.Point(cogBtn, "RIGHT", lastInline, "LEFT", -8, 0)
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogPos)
            UpdateCogPos()
        end
    end

    -- Row: Bar Spacing | Empty Bar Overlay. Empty Bar Overlay exposes bgR/G/B/A, the
    -- overlay tint on empty pip backgrounds. Bar Spacing's color is opt-in: the inline
    -- gapColorEnabled toggle activates a gap-only fill layer (gapR/G/B/A).
    do
        local classGapRow
        classGapRow, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "Bar Spacing", min = 0, max = 20, step = 1,
              disabled = classOff,
              disabledTooltip = "Class Resource",
              getValue = function() local c = cfg(); return c and c.pipSpacing or 3 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.pipSpacing = v; SmoothRefresh()
              end },
            { type = "slider", text = "Empty Bar Overlay", min = 0, max = 100, step = 5,
              disabled = classOff,
              disabledTooltip = "Class Resource",
              getValue = function() local c = cfg(); return math.floor(((c and c.bgA) or 0.1) * 100 + 0.5) end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.bgA = v / 100; RefreshClass()
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- Bar Spacing inline enable toggle + gap-color swatch
        if not EllesmereUI._prebuilding then
            local rgn = classGapRow._leftRegion
            local ctrl = rgn._control
            local gapSwatch, updateGapSwatch = EllesmereUI.BuildColorSwatch(
                rgn, classGapRow:GetFrameLevel() + 3,
                function()
                    local c = cfg()
                    return (c and c.gapR or 0), (c and c.gapG or 0),
                           (c and c.gapB or 0), (c and c.gapA or 1)
                end,
                function(r, g, b, a)
                    local c = cfg(); if not c then return end
                    c.gapR, c.gapG, c.gapB, c.gapA = r, g, b, a
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                true, 20)
            PP.Point(gapSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = gapSwatch
            EllesmereUI.RegisterWidgetRefresh(function() updateGapSwatch() end)
            local gapBlock = CreateFrame("Frame", nil, gapSwatch)
            gapBlock:SetAllPoints()
            gapBlock:SetFrameLevel(gapSwatch:GetFrameLevel() + 10)
            gapBlock:EnableMouse(true)
            gapBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(gapSwatch, "Enable the toggle to set a custom gap color")
            end)
            gapBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateGapSwatchState()
                local c = cfg()
                if c and c.gapColorEnabled then
                    gapSwatch:SetAlpha(1); gapBlock:Hide()
                else
                    gapSwatch:SetAlpha(0.3); gapBlock:Show()
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateGapSwatchState)
            UpdateGapSwatchState()
            EllesmereUI.BuildInlineToggle({
                region = rgn,
                getValue = function() local c = cfg(); return c and c.gapColorEnabled end,
                setValue = function(v)
                    local c = cfg(); if not c then return end
                    c.gapColorEnabled = v and true or nil
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
            })
        end
        -- Empty Bar Overlay inline color swatch (RGB only)
        if not EllesmereUI._prebuilding then
            local rgn = classGapRow._rightRegion
            local ctrl = rgn._control
            local ovSwatch, updateOvSwatch = EllesmereUI.BuildColorSwatch(
                rgn, classGapRow:GetFrameLevel() + 3,
                function()
                    local c = cfg()
                    return (c and c.bgR or 1), (c and c.bgG or 1),
                           (c and c.bgB or 1), 1
                end,
                function(r, g, b)
                    local c = cfg(); if not c then return end
                    c.bgR, c.bgG, c.bgB = r, g, b
                    RefreshClass(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(ovSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() updateOvSwatch() end)
        end
    end

    -- Row 4: (Sync) Opacity | Fill Color
    local classBorderRow
    classBorderRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Opacity",
          min = 0, max = 100, step = 5,
          disabled = classOff,
          disabledTooltip = "Class Resource",
          getValue = function() local c = cfg(); return math.floor(((c and c.barAlpha) or 1) * 100 + 0.5) end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.barAlpha = v / 100; RefreshClass()
              EllesmereUI:RefreshPage()
          end },
        { type = "slider", text = "Fill Color", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the resource fill; below 100 the world shows through the fill instead of the background.",
          disabled = classOff,
          disabledTooltip = "Class Resource",
          getValue = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
          setValue = function(v)
              local c = cfg(); if not c then return end
              c.fillOpacity = v; RebuildClass(); SmoothRefresh()
          end }
    );  y = y - h
    -- Fill Color inline swatches: custom / class / resource
    if not EllesmereUI._prebuilding then
    EllesmereUI.BuildInlineSwatches(classBorderRow._rightRegion, {
            { tooltip = "Custom Colored",
              hasAlpha = false,
              getValue = function()
                  local c = cfg()
                  if not c then return 0xDB/255, 0xCF/255, 0x37/255, 1 end
                  return c.fillR, c.fillG, c.fillB, 1
              end,
              setValue = function(r, g, b)
                  local c = cfg(); if not c then return end
                  c.fillR, c.fillG, c.fillB = r, g, b
                  RebuildClass(); SmoothRefresh()
              end,
              onClick = function(self)
                  local c = cfg(); if not c then return end
                  local inCustom = (not c.resourceColored) and (c.classColored == false)
                  if not inCustom then
                      -- false, never nil: a removed key harvests into
                      -- spec overrides as a key-removal marker the apply
                      -- guard can never re-apply (the soul-bar colour
                      -- revert); the runtime only tests truthiness, so
                      -- false is behaviourally identical.
                      c.resourceColored = false
                      c.classColored = false; RebuildClass()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local inCustom = c and (not c.resourceColored) and (c.classColored == false)
                  return inCustom and 1 or 0.3
              end },
            { tooltip = "Class Colored",
              getValue = function()
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b, 1 end
                  return 1, 0.82, 0, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.resourceColored = false   -- false, never nil (see Custom swatch)
                  c.classColored = true; RebuildClass()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  local isClassMode = c and (not c.resourceColored) and (c.classColored ~= false)
                  return isClassMode and 1 or 0.3
              end },
            { tooltip = "Class Resource Color",
              getValue = function()
                  local gsr = _G._ERB_GetSecondaryResource
                  local rslv = _G._ERB_ResolveSecondaryResourceColor
                  if gsr and rslv then
                      local info = gsr()
                      if info and info.power ~= nil then
                          local rr, rg, rb = rslv(info.power)
                          if rr then return rr, rg, rb, 1 end
                      end
                  end
                  local _, classFile = UnitClass("player")
                  local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                  if cc then return cc.r, cc.g, cc.b, 1 end
                  return 1, 0.82, 0, 1
              end,
              setValue = function() end,
              onClick = function()
                  local c = cfg(); if not c then return end
                  c.resourceColored = true
                  c.classColored = true; RebuildClass()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = cfg()
                  return (c and c.resourceColored) and 1 or 0.3
              end },
    }, { disabled = function() local c = cfg(); return (not c) or (not c.enabled) or c.darkTheme end,
         disabledTooltip = function()
             local c = cfg()
             if c and c.darkTheme then return "This option requires Class Resource Bar Dark Mode to be off. Dark Mode colors can be adjusted in Global Settings -> Colors." end
             return "Class Resource"
         end })
    -- Fill Color inline cog: Charged Combo Point color
    end
    if not EllesmereUI._prebuilding then
        local rgn = classBorderRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = classOff,
            disabledTooltip = "Class Resource",
            title = "Fill Settings",
            rows = {
                { type = "toggle", label = "Darken Partially Filled Resources",
                  tooltip = "Makes partially filled Soul Shards and Essence darker than completed ones.",
                  get = function()
                      local c = cfg()
                      return c and c.darkenPartialPips ~= false
                  end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.darkenPartialPips = v; RefreshClass()
                  end },
                { type = "colorpicker", label = "Charged Color", hasAlpha = false,
                  get = function()
                      local c = cfg()
                      if not c then return 0.44, 0.77, 1.00, 1 end
                      return c.chargedR or 0.44, c.chargedG or 0.77,
                             c.chargedB or 1.00, c.chargedA or 1
                  end,
                  set = function(cr, cg, cb, ca)
                      local c = cfg(); if not c then return end
                      c.chargedR, c.chargedG = cr, cg
                      c.chargedB, c.chargedA = cb, ca
                      RebuildClass(); SmoothRefresh()
                  end },
            },
            footer = false,
        })
    end
    if not ctx.advanced and ctx.syncRows then
        ctx.syncRows.classOpacity = classBorderRow._leftRegion
        if not EllesmereUI._prebuilding then
            local rgn = classBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.secondary.barAlpha or 1
                    p.primary.barAlpha = v; p.health.barAlpha = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.secondary.barAlpha or 1
                    return (p.primary.barAlpha or 1) == v and (p.health.barAlpha or 1) == v
                end,
                flashTargets = function() return { ctx.syncRows.classOpacity, ctx.syncRows.powerOpacity, ctx.syncRows.healthOpacity } end,
            })
        end
    end

    -- Out of Combat Opacity cog: dims the Class Resource bar to this alpha out of combat (100 = no fade); applied by ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat.
    if not EllesmereUI._prebuilding then
        local rgn = classBorderRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = function() local c = cfg(); return c and not c.enabled end,
            disabledTooltip = "Class Resource",
            title = "Out of Combat Opacity",
            rows = {
                { type = "toggle", label = "Fade Out of Combat",
                  get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocFadeEnabled = v; RefreshClass()
                  end },
                { type = "slider", label = "Opacity",
                  min = 0, max = 100, step = 1,
                  disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                  get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                  set = function(v)
                      local c = cfg(); if not c then return end
                      c.oocAlpha = v / 100; RefreshClass()
                  end },
            },
        })
    end

    -- Resource Text and the threshold popup below touch only the class-resource
    -- (secondary) config. DB() is shadowed in this scope so DB().secondary resolves to
    -- cfg() (global secondary on Simple, per-spec override on Advanced) without rewriting
    -- every access path. Returns nil when synced (cfg()==nil) so `if not p` guards
    -- short-circuit; the synced overlay covers these controls anyway.
    local DB = function()
        local c = cfg()
        if not c then return nil end
        return { secondary = c }
    end

    -- Row 5: Resource Text | Threshold & Hash Lines
    classColorRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Resource Text",
          disabled = classOff,
          disabledTooltip = "Class Resource",
          getValue = function() local p = DB(); return p and p.secondary.showText end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.secondary.showText = v; RebuildClass()
              EllesmereUI:RefreshPage()
          end },
        { type = "label", text = "Threshold & Hash Lines" }
    );  y = y - h
    -- Resource Text inline color swatch
    if not EllesmereUI._prebuilding then
        local rgn = classColorRow._leftRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, classColorRow:GetFrameLevel() + 3,
            function()
                local p = DB()
                if not p then return 1, 1, 1, 1 end
                return p.secondary.textR or 1, p.secondary.textG or 1, p.secondary.textB or 1, 1
            end,
            function(r, g, b)
                local p = DB(); if not p then return end
                p.secondary.textR, p.secondary.textG, p.secondary.textB = r, g, b
                RefreshClass()
            end,
            false, 20)
        PP.Point(swatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local swatchDis = CreateFrame("Frame", nil, swatch)
        swatchDis:SetAllPoints(); swatchDis:SetFrameLevel(swatch:GetFrameLevel() + 10); swatchDis:EnableMouse(true)
        swatchDis:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Resource Text"))
        end)
        swatchDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateSwatchDis()
            updateSwatch()
            local p = DB()
            local off = not p or not p.secondary.enabled or not p.secondary.showText
            if off then swatch:SetAlpha(0.3); swatchDis:Show() else swatch:SetAlpha(1); swatchDis:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateSwatchDis)
        UpdateSwatchDis()
    end
    -- Resource Text inline cog: size + position
    if not EllesmereUI._prebuilding then
        local rgn = classColorRow._leftRegion
        local resTextRows = {
            { type = "toggle", label = "Show %",
              get = function()
                  local p = DB()
                  return (not p) or p.secondary.showPercent ~= false
              end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.showPercent = v; RefreshClass()
              end },
            { type = "toggle", label = "Only if Power Bar Hidden",
              tooltip = "Show the resource text only while the power bar is hidden - disabled, filtered off for this spec, a spec with no power, or hidden by \"Hide Power Bar if Resource\". Off = always show the text.",
              get = function() local p = DB(); return p and p.secondary.showTextOnlyIfNoPower end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.showTextOnlyIfNoPower = v; RebuildClass()
              end },
            { type = "slider", label = "Size", min = 8, max = 24, step = 1,
              get = function() local p = DB(); return p and p.secondary.textSize or 11 end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.textSize = v; RefreshClass()
              end },
            { type = "dropdown", label = "Anchor",
              values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
              order = { "LEFT", "CENTER", "RIGHT" },
					tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
              get = function() local p = DB(); return p and p.secondary.textAnchor or "CENTER" end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.textAnchor = v; RefreshClass()
              end },
            { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
              get = function() local p = DB(); return p and p.secondary.textXOffset or 0 end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.textXOffset = v; RefreshClass()
              end },
            { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
              get = function() local p = DB(); return p and p.secondary.textYOffset or 0 end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.textYOffset = v; RefreshClass()
              end },
        }
        -- Devourer (DH soul fragments) only: hides the "/ max" suffix on the count text; inserted above "Show %"
        do
            local gsr = _G._ERB_GetSecondaryResource
            local secInfo = gsr and gsr()
            if secInfo and secInfo.power == "SOUL_FRAGMENTS_DEVOURER" then
                table.insert(resTextRows, 1, {
                    type = "toggle", label = "Show Max Stacks",
                    get = function()
                        local p = DB()
                        return (not p) or p.secondary.showMaxStacks ~= false
                    end,
                    set = function(v)
                        local p = DB(); if not p then return end
                        p.secondary.showMaxStacks = v; RefreshClass()
                    end })
            end
        end
        local cogBtn = EllesmereUI.BuildInlineCog(rgn, {
            disabled = function()
                local p = DB(); return not p or not p.secondary.enabled or not p.secondary.showText
            end,
            disabledTooltip = "Resource Text",
            title = "Resource Text",
            rows = resTextRows,
            footer = false,
        })
        AddFormTextBtn(rgn, cogBtn, function() return DB() and DB().secondary end, RefreshClass)
    end

		-- class settings [start]
    -- Settings button + popup on Threshold & Hash Lines (row 5 slot 2)
    do
        local settingsRgn = classColorRow._rightRegion
        -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
        EllesmereUI.SpecOverrides_AttachEditLock(settingsRgn,
            "Thresholds have their own per-spec system and can't be edited while editing a spec group")

        -- Advanced: this popup edits the per-spec override cfg(), which only applies while
        -- playing ctx.specID. The spec-assignment chrome (dropdown + Add Specs) is dropped
        -- and a single implied-spec card set (base card plus talent variants) is re-tagged
        -- to specIDs={0}; talent variants still work via the per-card "+" button.
        local advSingle = (ctx.advanced and ctx.specID) and true or nil
        if advSingle then
            local c = cfg()
            if c then
                local ts = c.thresholdSpecs
                -- Normalized means every card carries specIDs == {0}
                local normalized = ts and #ts > 0
                if ts then
                    for _, e in ipairs(ts) do
                        if not (e.specIDs and #e.specIDs == 1 and e.specIDs[1] == 0) then
                            normalized = false; break
                        end
                    end
                end
                if not normalized then
                    -- Keep only cards relevant to this spec (its own plus any All-Specs cards and their talent variants), re-tagged.
                    local kept = {}
                    if ts then
                        for _, e in ipairs(ts) do
                            local rel = false
                            if e.specIDs then
                                for _, sid in ipairs(e.specIDs) do
                                    if sid == 0 or sid == ctx.specID then rel = true; break end
                                end
                            end
                            if rel then e.specIDs = { 0 }; kept[#kept + 1] = e end
                        end
                    end
                    if #kept == 0 then
                        kept[1] = {
                            specIDs = { 0 },
                            hashValues = "", hashWidth = 1,
                            hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                            thresholdEnabled = false,
                            thresholdCount = (ctx.specID == 263 and c.enhanceFiveBar) and 7 or 3,
                            thresholdPartialOnly = false,
                            thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
                        }
                    end
                    c.thresholdSpecs = kept
                end
            end
        end
        local CLOSE_ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
        local POPUP_W = 480
        local POPUP_PAD = 14
        local ROW_GAP = 6
        local EG = EllesmereUI.ELLESMERE_GREEN

        -- Deep copy a thresholdSpecs entry (scalars + nested arrays like specIDs/bands) so a duplicated variant shares no tables.
        local function CopyThresholdEntry(src)
            local out = {}
            for k, v in pairs(src) do
                if type(v) == "table" then
                    local t = {}
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" then
                            local r = {}
                            for k3, v3 in pairs(v2) do r[k3] = v3 end
                            t[k2] = r
                        else
                            t[k2] = v2
                        end
                    end
                    out[k] = t
                else
                    out[k] = v
                end
            end
            return out
        end

        -- Settings Button
        local BTN_W, BTN_H = 140, 30
        local settingsBtn = CreateFrame("Button", nil, settingsRgn)
        PP.Size(settingsBtn, BTN_W, BTN_H)
        PP.Point(settingsBtn, "RIGHT", settingsRgn, "RIGHT", -20, 0)
        settingsBtn:SetFrameLevel(settingsRgn:GetFrameLevel() + 2)
        local btnBg = EllesmereUI.SolidTex(settingsBtn, "BACKGROUND",
            EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        btnBg:SetAllPoints()
        settingsBtn._border = EllesmereUI.MakeBorder(settingsBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local btnLbl = EllesmereUI.MakeFont(settingsBtn, 13, nil, 1, 1, 1)
        btnLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        btnLbl:SetPoint("CENTER")
        btnLbl:SetText(EllesmereUI.L("Settings"))
        settingsBtn:SetScript("OnEnter", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], 0.3)
            end
        end)
        settingsBtn:SetScript("OnLeave", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], EllesmereUI.DD_BRD_A)
            end
        end)
        local btnDis = CreateFrame("Frame", nil, settingsRgn)
        btnDis:SetAllPoints(settingsBtn)
        btnDis:SetFrameLevel(settingsBtn:GetFrameLevel() + 5)
        btnDis:EnableMouse(true)
        btnDis:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip("Class Resource"))
        end)
        btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBtnDis()
            local p = DB()
            -- In Advanced, DB() is nil when the override doesn't exist (no spec selected/customised): nothing to configure, disable.
            if not p or not p.secondary.enabled then btnDis:Show() else btnDis:Hide() end
        end
        settingsBtn:HookScript("OnShow", UpdateBtnDis)
        EllesmereUI.RegisterWidgetRefresh(UpdateBtnDis)
        UpdateBtnDis()

        -- Threshold notice badge; re-run from the popup's two refreshers below,
        -- which cover every card edit (RefreshDetail) and every add/delete/spec
        -- change (RefreshSpecEntries).
        local _thrNoticeC = AttachThresholdNotice(settingsBtn, cfg, advSingle and ctx.specID or nil)

        -- Popup Frame (lazy-created)
			local thrPage
			local specContainer
			local contentHalfSize
			local totalW
			local halfW
			local totalH
        local _entryFrames = {}  -- pool of entry UI frames
        local _addNewBtn         -- empty-state "Add Threshold" button (Advanced only)
        local _tempSpecSel = {}  -- transient dropdown selection
        local _specDDRefresh     -- set after dropdown creation
        local _selectedIdx       -- selected threshold entry; drives the right pane
        local RefreshDetail      -- right-pane refresher, assigned in BuildFrame

        local CR_ROLE_HEALERS = -1
        local CR_ROLE_TANKS   = -2
        local CR_ROLE_DPS     = -3
        local _crRoleCache = {}

        local function BuildSpecItems()
            local items = {}
            items[#items + 1] = { key = 0, label = "All Specs", isAction = true, lockedFn = ns.HasCRAllSpecs }
            -- WoW Forever: one row per class, keyed by its class token, standing for
            -- every retail spec of the class (the getter and setter expand it). A row
            -- locks while any spec of its class is claimed.
            if EllesmereUI.IS_FOREVER then
                local classes = EllesmereUI.ForeverClasses()
                for n = 1, #classes do
                    local token = classes[n]
                    local ids = EllesmereUI.ForeverClassSpecIDs(token)
                    items[#items + 1] = { key = token, label = EllesmereUI.ForeverClassName(token), lockedFn = function()
                        for i = 1, #ids do
                            if ns.IsCRSpecClaimed(ids[i]) then return true end
                        end
                        return false
                    end }
                end
                return items
            end

            local classList = {}
            for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
                local className, classFile = GetClassInfo(classID)
                if className then
                    classList[#classList + 1] = { classID = classID, className = className }
                end
            end
            table.sort(classList, function(a, b) return a.className < b.className end)

            local healers, tanks, dps = {}, {}, {}
            for _, cls in ipairs(classList) do
                items[#items + 1] = { isHeader = true, label = cls.className }
                local numSpecs = GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(cls.classID) or 0
                for specIndex = 1, numSpecs do
                    local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
                    if specID and specName then
                        local sid = specID
                        items[#items + 1] = { key = specID, label = specName, lockedFn = function() return ns.IsCRSpecClaimed(sid) end }
                        if role == "HEALER" then healers[#healers + 1] = specID
                        elseif role == "TANK" then tanks[#tanks + 1] = specID
                        else dps[#dps + 1] = specID end
                    end
                end
            end
            _crRoleCache[CR_ROLE_HEALERS] = healers
            _crRoleCache[CR_ROLE_TANKS] = tanks
            _crRoleCache[CR_ROLE_DPS] = dps
            return items
        end

        local RefreshSpecEntries  -- forward decl

        local function BuildFrame(args)
				local hdrH     = 40
				local PP       = EllesmereUI.PanelPP or EllesmereUI.PP
				local SIDE_PAD = 20
				local CPAD     = EllesmereUI.CONTENT_PAD or 45
				local INNERPAD = 10
				local ROW_H          = 50
				local defR           = 1
				local defG           = 0.2
				local defB           = 0.2
				local defA           = 1
				local BORDER_R       = EllesmereUI.BORDER_R
				local BORDER_G       = EllesmereUI.BORDER_G
				local BORDER_B       = EllesmereUI.BORDER_B
				local EG             = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
				local CLASS_COLORS_L = CLASS_COLORS

				-- Bottom = the section's actual final Y (args.botY) so the overlay covers exactly the built height. Simple mode appends an "Anchor to Cursor" row after this section, so extend one row down there.
				local thrPageBotY    = args.botY - ((ctx and ctx.advanced) and 0 or ROW_H)
				thrPage = CreateFrame("Frame", nil, parent)
				PP.Point(thrPage, "TOPLEFT", parent, "TOPLEFT", CPAD, args.topY)
				PP.Point(thrPage, "TOPRIGHT", parent, "TOPRIGHT", -CPAD, args.topY)
				PP.Point(thrPage, "BOTTOMLEFT", parent, "TOPLEFT", CPAD, thrPageBotY)
				-- The unlock-mode cycle can leave this lazily-built frame with an undefined rect, so capture the resolved anchors: ToggleFrame re-asserts them before every Show to force a rect recompute.
				local _thrPts = {}
				for p = 1, thrPage:GetNumPoints() do _thrPts[p] = { thrPage:GetPoint(p) } end
				thrPage._reanchor = function()
					thrPage:ClearAllPoints()
					for p = 1, #_thrPts do thrPage:SetPoint(unpack(_thrPts[p])) end
				end
				thrPage:SetFrameLevel(parent:GetFrameLevel() + 50)
				thrPage:EnableMouse(true)
				local obg = thrPage:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
				obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 1)
				-- 1px center divider in the global BORDER style
				local div = thrPage:CreateTexture(nil, "ARTWORK")
				div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
				div:SetWidth(1)
				div:SetPoint("TOP", thrPage, "TOP", 0, 0)
				div:SetPoint("BOTTOM", thrPage, "BOTTOM", 0, 0)

				totalW             = thrPage:GetWidth()
				halfW              = thrPage:GetWidth() / 2
				contentHalfSize    = math.floor(halfW - (SIDE_PAD * 2))
				totalH             = thrPage:GetHeight()
				local curY               = -INNERPAD
				local BUTTON_W, BUTTON_H = 80, 29
				local MEDIA              = "Interface\\AddOns\\EllesmereUI\\media\\"

				local backBtn            = CreateFrame("Button", nil, thrPage)
				PP.Size(backBtn, BUTTON_W, BUTTON_H)
				PP.Point(backBtn, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, curY)
				backBtn:SetFrameLevel(thrPage:GetFrameLevel() + 2)
				local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
				backBg:SetAllPoints()
				backBg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
				local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

				local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
				backIcon:SetSize(14, 14)
				PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
				backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
				backIcon:SetVertexColor(EG.r, EG.g, EG.b)
				backIcon:SetAlpha(0.6)
				if backIcon.SetSnapToPixelGrid then
					backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0)
				end

				local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
				PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
				backLbl:SetText(EllesmereUI.L("Back"))

				backBtn:SetScript("OnEnter", function()
					backBg:SetColorTexture(0.119, 0.111, 0.104, 0.50)
					backBrd:SetColor(1, 1, 1, 0.22)
					backIcon:SetAlpha(0.85)
					backLbl:SetAlpha(0.85)
				end)
				backBtn:SetScript("OnLeave", function()
					backBg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
					backBrd:SetColor(1, 1, 1, 0.12)
					backIcon:SetAlpha(0.6)
					backLbl:SetAlpha(0.55)
				end)
				backBtn:SetScript("OnClick", function()
					thrPage:Hide()
				end)


            -- Spec-assignment chrome (dropdown + Add Specs): Simple only; in Advanced the card set is implicitly this spec (see advSingle).
				local specDDHost
            if not advSingle then
					local ADD_W, GAP_L = 90, 10
					local DD_W = contentHalfSize - (INNERPAD * 2) - BUTTON_W - ADD_W
					local rowW = DD_W + GAP_L + ADD_W
					local ddRow = CreateFrame("Frame", nil, backBtn)
					ddRow:SetSize(DD_W, BUTTON_H)
					ddRow:SetPoint("TOPLEFT", backBtn, "TOPRIGHT", 10, 0)
					ddRow:SetFrameLevel(thrPage:GetFrameLevel() + 2)

					-- Spec dropdown (checkbox multi-select with search)
					local specItems = BuildSpecItems()
					specDDHost = CreateFrame("Frame", nil, ddRow)
					specDDHost:SetSize(DD_W, BUTTON_H)
					specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
					specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

					local cbDD, cbDDRefresh  -- forward decl for closure access
					cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
						specDDHost, DD_W, specDDHost:GetFrameLevel() + 2,
						specItems,
						function(key)
							if key == CR_ROLE_HEALERS or key == CR_ROLE_TANKS or key == CR_ROLE_DPS then return false end
							-- WoW Forever class row: checked while every spec of the class is selected
							local fvIDs = EllesmereUI.IS_FOREVER and EllesmereUI.ForeverClassSpecIDs(key)
							if fvIDs then
								for i = 1, #fvIDs do
									if not _tempSpecSel[fvIDs[i]] then return false end
								end
								return true
							end
							return _tempSpecSel[key] or false
						end,
						function(key, val)
							local crRoleSpecs = _crRoleCache[key]
							if crRoleSpecs then
								wipe(_tempSpecSel)
								for _, sid in ipairs(crRoleSpecs) do _tempSpecSel[sid] = true end
								cbDD:Click()
								if cbDDRefresh then cbDDRefresh() end
								return
							end
							if key == 0 then
								wipe(_tempSpecSel)
								_tempSpecSel[0] = true
								cbDD:Click()
								if cbDDRefresh then cbDDRefresh() end
								return
							end
							-- WoW Forever class row: selects or clears every spec of the class
							local fvIDs = EllesmereUI.IS_FOREVER and EllesmereUI.ForeverClassSpecIDs(key)
							if fvIDs then
								if val then _tempSpecSel[0] = nil end
								for i = 1, #fvIDs do _tempSpecSel[fvIDs[i]] = val and true or nil end
								if cbDDRefresh then cbDDRefresh() end
								return
							end
							if val then
								_tempSpecSel[0] = nil
								_tempSpecSel[key] = true
							else
								_tempSpecSel[key] = nil
							end
							if cbDDRefresh then cbDDRefresh() end
						end,
						nil, 10, true
					)
					PP.Point(cbDD, "LEFT", specDDHost, "LEFT", 0, 0)
					-- Dropdown label font 11px instead of the default 13
					for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
						if rgn2.SetFont and rgn2.GetText then
							local f, _, fl = rgn2:GetFont(); if f then rgn2:SetFont(f, 11, fl or "") end; break
						end
					end

					-- Replace "None" with placeholder text on the dropdown label
					local _origRefresh = cbDDRefresh
					local function WrappedRefresh()
						_origRefresh()
						local regions = { cbDD:GetRegions() }
						for _, rgn2 in ipairs(regions) do
							if rgn2.GetText and EllesmereUI.EnKey(rgn2:GetText()) == "None" then
								rgn2:SetText(EllesmereUI.L("Select a Spec..."))
								break
							end
						end
					end
					_specDDRefresh = WrappedRefresh
					WrappedRefresh()

					local addBtn = CreateFrame("Button", nil, ddRow)
					PP.Size(addBtn, ADD_W, BUTTON_H)
					addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
					addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
					local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.069, 0.058, 0.047, 0.92)
					addBg:SetAllPoints()
					addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
					local addLbl = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1)
					addLbl:SetAlpha(0.5)
					addLbl:SetPoint("CENTER")
					addLbl:SetText(EllesmereUI.L("Add Specs"))
					addBtn:SetScript("OnEnter", function()
						addLbl:SetAlpha(0.7)
						if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.6) end
					end)
					addBtn:SetScript("OnLeave", function()
						addLbl:SetAlpha(0.5)
						if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.4) end
					end)
					addBtn:SetScript("OnClick", function()
						local p = DB(); if not p then return end
						local ids = {}
						if _tempSpecSel[0] then
							ids[1] = 0
						else
							for sid in pairs(_tempSpecSel) do
								if sid ~= 0 then ids[#ids + 1] = sid end
							end
						end
						if #ids == 0 then return end
						if not p.secondary.thresholdSpecs then p.secondary.thresholdSpecs = {} end
						local isBar = ns.IsSpecBarType(ids[1])
						local _enhAdd = false
						if p.secondary.enhanceFiveBar then
							for _, sid in ipairs(ids) do if sid == 263 then _enhAdd = true; break end end
						end
						local p2 = p.secondary
						local newEntry = {
							specIDs = ids,
							hashValues = "",
							hashWidth = 1,
							hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
							thresholdEnabled = true,
							thresholdCount = _enhAdd and 7 or (isBar and 30 or 3),
							thresholdPartialOnly = false,
							thresholdR = p2.thresholdR or 0x0c/255,
							thresholdG = p2.thresholdG or 0xd2/255,
							thresholdB = p2.thresholdB or 0x9d/255,
							thresholdA = p2.thresholdA or 1,
						}
						-- Default for "Threshold color below value": the only bar-type spender class resource is Hunter
						-- Focus, so it starts ON (warn when low); builders (Maelstrom/Insanity/Astral) start OFF.
						-- Only when the entry covers the current spec (resource readable).
						if isBar then
							local curIdx = C_SpecializationInfo.GetSpecialization()
							local curSpecID = curIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(curIdx)
							-- WoW Forever: the entry covers the player when it names a spec of the class.
							if curSpecID or EllesmereUI.IS_FOREVER then
								for _, sid in ipairs(ids) do
									if sid == curSpecID or (EllesmereUI.IS_FOREVER and EllesmereUI.IsPlayerSpec(sid)) then
										local gsr = _G._ERB_GetSecondaryResource
										local info = gsr and gsr()
										if info and info.power == "FOCUS_BAR" then
											newEntry.thresholdReverse = true
										end
										break
									end
								end
							end
						end
						p.secondary.thresholdSpecs[#p.secondary.thresholdSpecs + 1] = newEntry
						_selectedIdx = #p.secondary.thresholdSpecs
						wipe(_tempSpecSel)
						if WrappedRefresh then WrappedRefresh() end
						RefreshSpecEntries()
						if RefreshDetail then RefreshDetail() end
						RefreshClass()
					end)

					curY = curY - 36
            end  -- not advSingle (spec dropdown + Add hidden in Advanced)

            -- Scrollable entry container
				curY = curY - BUTTON_H - INNERPAD
            local headerH = math.abs(curY)  -- consumed by title+dropdown row

				-- total region less 3x inner padding and the button height
				local specContainerH = totalH - (INNERPAD * 3) - BUTTON_H
				specContainer = CreateFrame("Frame", nil, backBtn)
				specContainer:SetFrameStrata("DIALOG")
				specContainer:SetFrameLevel(200)
				PP.Point(specContainer, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -ROW_H)
				PP.Size(specContainer, contentHalfSize, specContainerH)

				local bg = specContainer:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(0.077, 0.068, 0.058, 0.95)
				PP.CreateBorder(specContainer, 1, 1, 1, 0.15, 1, "BORDER", 7)

				local headerH = math.abs(curY)

				local scrollFrame = CreateFrame("ScrollFrame", nil, specContainer)
				scrollFrame:SetPoint("TOPLEFT", specContainer, "TOPLEFT", 1, -2)
				scrollFrame:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -1, -2)
				scrollFrame:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -1, 1)
				scrollFrame:SetFrameLevel(specContainer:GetFrameLevel() + 1)

				local scrollChild = CreateFrame("Frame", nil, scrollFrame)
				scrollChild:SetWidth(contentHalfSize)
				scrollFrame:SetScrollChild(scrollChild)

            -- Thin scrollbar track + thumb
				local scrollBar = CreateFrame("Frame", nil, specContainer)
            scrollBar:SetWidth(4)
				scrollBar:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -3, -4)
				scrollBar:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -3, 4)
				scrollBar:SetFrameLevel(specContainer:GetFrameLevel() + 10)
            scrollBar:Hide()
            local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
            scrollTrack:SetAllPoints()
            scrollTrack:SetColorTexture(1, 1, 1, 0.04)
            local scrollThumb = scrollBar:CreateTexture(nil, "OVERLAY")
            scrollThumb:SetWidth(4)
            scrollThumb:SetColorTexture(1, 1, 1, 0.15)
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            scrollThumb:SetHeight(30)

            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local cur = self:GetVerticalScroll()
                local step = 30
                self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * step)))
            end)
            scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
                if not yRange or yRange <= 0 then
                    scrollBar:Hide()
                    return
                end
                scrollBar:Show()
                local barH = scrollBar:GetHeight()
                if barH <= 0 then return end
                local thumbH = math.max(20, barH * (self:GetHeight() / (self:GetHeight() + yRange)))
                scrollThumb:SetHeight(thumbH)
            end)
            scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local barH = scrollBar:GetHeight()
                local thumbH = scrollThumb:GetHeight()
                local travel = barH - thumbH
                local frac = offset / maxScroll
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -travel * frac)
            end)

            specContainer._scrollFrame = scrollFrame
            specContainer._scrollChild = scrollChild
            specContainer._headerH = headerH
				specContainer._maxH = specContainerH

				-- Right detail pane: config for the selected entry
				local detailC = CreateFrame("Frame", nil, thrPage)
				detailC:SetFrameStrata("DIALOG")
				detailC:SetFrameLevel(200)
				-- The right side has no header row, so it starts at the top
				PP.Point(detailC, "TOPRIGHT", thrPage, "TOPRIGHT", -SIDE_PAD, -INNERPAD)
				PP.Size(detailC, contentHalfSize, specContainerH + (ROW_H - INNERPAD))
				local dBg = detailC:CreateTexture(nil, "BACKGROUND")
				dBg:SetAllPoints()
				dBg:SetColorTexture(0.077, 0.068, 0.058, 0.95)
				PP.CreateBorder(detailC, 1, 1, 1, 0.15, 1, "BORDER", 7)
				detailC:EnableMouse(true)

				local DPAD  = 16
				local DLVL  = detailC:GetFrameLevel() + 2
				local ROWH  = 26
				local ROWGAP = 12
				local INW   = contentHalfSize - DPAD * 2  -- inner content width
				local MEDIAF = EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"

				-- Shown when nothing is selected
				local dPlaceholder = EllesmereUI.MakeFont(detailC, 13, nil, 1, 1, 1)
				dPlaceholder:SetAlpha(0.4)
				dPlaceholder:SetPoint("CENTER")
				dPlaceholder:SetText(EllesmereUI.L("Select or add an entry"))

				-- The live currently-selected threshold card, or nil
				local function CurEntry()
					local pp = DB(); if not pp then return nil end
					local sp = pp.secondary
					if not sp or not sp.thresholdSpecs then return nil end
					return _selectedIdx and sp.thresholdSpecs[_selectedIdx] or nil
				end

				local _allRows = {}
				-- Labeled row frame, registered for the layout pass
				local function DRow(labelText, h)
					local rf = CreateFrame("Frame", nil, detailC)
					rf:SetFrameLevel(DLVL)
					rf._rawH = h or ROWH  -- design-space height for the layout pass
					PP.Height(rf, rf._rawH)
					if labelText then
						local lbl = EllesmereUI.MakeFont(rf, 13, nil, 1, 1, 1)
						lbl:SetAlpha(0.6)
						lbl:SetPoint("LEFT", rf, "LEFT", 0, 0)
						lbl:SetText(EllesmereUI.L(labelText))
						rf._lbl = lbl
					end
					_allRows[#_allRows + 1] = rf
					return rf
				end

				-- Value edit boxes (hash / threshold)
				local function MakeInput(parent, w, numeric)
					local ib = CreateFrame("EditBox", nil, parent)
					PP.Size(ib, w, 22)
					ib:SetFrameLevel(parent:GetFrameLevel() + 3)
					ib:SetAutoFocus(false)
					ib:SetFont(MEDIAF, 12, "")
					ib:SetTextColor(1, 1, 1, 0.75)
					ib:SetJustifyH("CENTER")
					if numeric then ib:SetNumeric(true) end
					local ibg = ib:CreateTexture(nil, "BACKGROUND")
					ibg:SetAllPoints()
					ibg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
					EllesmereUI.MakeBorder(ib, 1, 1, 1, 0.08, PP)
					return ib
				end

				-- Row: Talent gate (single-spec cards only)
				local talentRow = DRow("Talent", ROWH)
				talentRow._talentValues = { _menuOpts = { searchable = true, parent = thrPage } }
				talentRow._talentOrder = {}
				local talentDD = EllesmereUI.BuildDropdownControl(
					talentRow, 170, talentRow:GetFrameLevel() + 2,
					talentRow._talentValues, talentRow._talentOrder,
					function()
						local ent = CurEntry(); if not ent then return 0 end
						return ent.talentSpellID or 0
					end,
					function(key)
						local ent = CurEntry(); if not ent then return end
						if key == 0 then
							ent.talentSpellID = nil; ent.talentName = nil
						else
							ent.talentSpellID = key
							ent.talentName = talentRow._talentValues[key]
						end
						RebuildClass()
						if talentRow._talentDD and talentRow._talentDD._refreshLabel then
							talentRow._talentDD._refreshLabel()
						end
						-- The dropdown lives in the detail pane, not inside a list frame, so rebuilding the list cannot churn the open menu: refresh to relabel + re-dim duplicate cards live.
						RefreshSpecEntries()
					end,
					function(key)
						local ent = CurEntry(); if not ent then return false end
						local pp = DB(); if not pp then return false end
						local specs = pp.secondary.thresholdSpecs; if not specs then return false end
						local wantGate = (key ~= 0) and key or nil
						for i, other in ipairs(specs) do
							if i ~= _selectedIdx then
								local og = other.talentSpellID
								local sameGate = (wantGate == nil and og == nil)
									or (wantGate ~= nil and og == wantGate)
								if sameGate and ns.SpecsConflict(ent.specIDs, other.specIDs) then
									return EllesmereUI.L("Already used by another card for this spec")
								end
							end
						end
						return false
					end
				)
				talentDD:SetHeight(22)
				talentDD:SetPoint("RIGHT", talentRow, "RIGHT", 0, 0)
				talentRow._talentDD = talentDD
				-- Keep the menu above the cog popups
				talentDD:HookScript("OnClick", function()
					local m = talentDD._ddMenu
					if m then m:SetFrameStrata("TOOLTIP") end
				end)
				talentDD:HookScript("OnHide", function()
					talentDD._invalidateMenu()
				end)
				-- Greys the picker for a spec of a class the player is not playing (its talents are not in the loadout); toggled in RefreshDetail
				local talentDis = CreateFrame("Frame", nil, talentRow)
				talentDis:SetPoint("TOPLEFT", talentDD, "TOPLEFT", 0, 0)
				talentDis:SetPoint("BOTTOMRIGHT", talentDD, "BOTTOMRIGHT", 0, 0)
				talentDis:SetFrameLevel(talentDD:GetFrameLevel() + 10)
				talentDis:EnableMouse(true)
				local talentDisTex = talentDis:CreateTexture(nil, "OVERLAY")
				talentDisTex:SetAllPoints()
				talentDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.6)
				talentDis:SetScript("OnEnter", function()
					EllesmereUI.ShowWidgetTooltip(talentDis, EllesmereUI.L("Talent gating is only available while playing this spec's class"))
				end)
				talentDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				talentDis:Hide()
				talentRow._dis = talentDis

				-- Row: Hash values ("Hash at X" + input + hint)
				local hashRow = DRow(nil, ROWH)
				local hashLbl = EllesmereUI.MakeFont(hashRow, 13, nil, 1, 1, 1)
				hashLbl:SetAlpha(0.6)
				hashLbl:SetPoint("LEFT", hashRow, "LEFT", 0, 0)
				hashRow._lbl2 = hashLbl
				local hashCog, hashCogShow = EllesmereUI.BuildCogPopup({
					title = "Hash Line Style", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
					rows = {
						{ type = "toggle", label = "Position by percent",
						  disabled = function()
						      local ent = CurEntry(); return not (ent and ns.IsEntryBarType(ent))
						  end,
						  disabledTooltip = "Bar-type resources only (pips use stack counts)",
						  get = function() local ent = CurEntry(); return (ent and ent.hashMode == "percent") and true or false end,
						  set = function(v)
						      local ent = CurEntry(); if not ent then return end
						      ent.hashMode = v and "percent" or "value"
						      RebuildClass()
						      if RefreshDetail then RefreshDetail() end
						  end },
						{ type = "slider", label = "Hash Width", min = 1, max = 4, step = 1,
						  get = function() local ent = CurEntry(); return ent and ent.hashWidth or 1 end,
						  set = function(v) local ent = CurEntry(); if ent then ent.hashWidth = v; RebuildClass() end end },
					},
				})
				local hashCogBtn = CreateFrame("Button", nil, hashRow)
				hashCogBtn:SetSize(20, 20)
				hashCogBtn:SetPoint("RIGHT", hashRow, "RIGHT", 0, 0)
				hashCogBtn:SetFrameLevel(hashRow:GetFrameLevel() + 5)
				hashCogBtn:SetAlpha(0.5)
				local hashCogTex = hashCogBtn:CreateTexture(nil, "OVERLAY")
				hashCogTex:SetAllPoints(); hashCogTex:SetTexture(EllesmereUI.COGS_ICON)
				hashCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
				hashCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
				hashCogBtn:SetScript("OnClick", function(self) hashCogShow(self) end)
				local hashSwatch, hashSwatchSnap = EllesmereUI.BuildColorSwatch(
					hashRow, hashRow:GetFrameLevel() + 4,
					function()
						local ent = CurEntry(); if not ent then return 1, 1, 1, 0.7 end
						return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
					end,
					function(r, g, b, a)
						local ent = CurEntry(); if not ent then return end
						ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
						RebuildClass()
					end, true, 19)
				hashSwatch:SetPoint("RIGHT", hashCogBtn, "LEFT", -8, 0)
				hashRow._swatchSnap = hashSwatchSnap
				local hashInput = MakeInput(hashRow, 120, false)
				hashInput:SetPoint("RIGHT", hashSwatch, "LEFT", -8, 0)
				local hashHint = EllesmereUI.MakeFont(hashRow, 10, nil, 1, 1, 1)
				hashHint:SetAlpha(0.35)
				hashHint:SetPoint("RIGHT", hashInput, "LEFT", -8, 0)
				hashRow._hint = hashHint
				local function _hashCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local ent = CurEntry(); if not ent then return end
					ent.hashValues = self:GetText()
					RebuildClass()
				end
				hashInput:SetScript("OnEditFocusLost", _hashCommit)
				hashInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				hashInput:SetScript("OnEscapePressed", function(self)
					self._cancelCommit = true
					local ent = CurEntry()
					self:SetText(ent and ent.hashValues or "")
					self:ClearFocus()
				end)
				hashRow._input = hashInput

				-- Row: Threshold (input + swatch + enable toggle)
				local threshRow = DRow("Threshold", ROWH)
				-- Threshold options cog: per-entry gating mirrors RefreshDetail so Threshold as / Direction / Only color at-above grey correctly.
				local function _thrEnt() return CurEntry() end
				local function _thrIsBar() local e=_thrEnt(); return (e and ns.IsEntryBarType(e)) and true or false end
				local function _thrIsStagger()
					local e=_thrEnt(); if not e then return false end
					if advSingle then return ctx.specID == 268 end
					if e.specIDs then for _, sp in ipairs(e.specIDs) do if sp == 268 then return true end end end
					return false
				end
				local function _thrIsEnhance()
					local e=_thrEnt(); if not e then return false end
					local pp = DB(); if not (pp and pp.secondary.enhanceFiveBar == true) then return false end
					if advSingle then return ctx.specID == 263 end
					if e.specIDs then for _, sp in ipairs(e.specIDs) do if sp == 263 then return true end end end
					return false
				end
				local function _thrEnabled() local e=_thrEnt(); if not e then return false end local v=e.thresholdEnabled; if v==nil then v=true end return v end
				local function _thrMultiOn() local e=_thrEnt(); return (e and e.multiBandEnabled and not _thrIsEnhance()) and true or false end
				local function _thrOptUsable() return _thrEnabled() and not _thrMultiOn() end
				local function _thrOffTip() if _thrMultiOn() then return BAND_REPLACES_TIP end return "Enable the Threshold toggle to use these options." end
				local function _thrIsUpTo() local e=_thrEnt(); return (e and e.thresholdReverse) and true or false end
				local function _thrIsWarrCharge()
					-- Arms/Fury class-bar thresholds render on the engine-fed
					-- Whirlwind/Sweeping Strikes charge bar, whose only
					-- threshold display is range coloring at/above the count
					-- (no Lua count exists to flip the whole fill).
					if (select(2, UnitClass("player"))) ~= "WARRIOR" then return false end
					local e = _thrEnt()
					local ids = e and e.specIDs
					if not ids then return false end
					for i = 1, #ids do
						local id = ids[i]
						if id == 0 or id == 71 or id == 72 then return true end
					end
					return false
				end
				local threshCog, threshCogShow = EllesmereUI.BuildCogPopup({
					title = "Threshold Options", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500, minWidth = 320,
					rows = {
						{ type = "segmented", label = "Threshold as",
							keys = { "percent", "value" }, labels = { percent = "Percent", value = "Value" }, rawTooltip = true,
							disabled = function() return (not _thrOptUsable()) or (not _thrIsBar()) or _thrIsStagger() end,
							disabledTooltip = function()
								if not _thrOptUsable() then return _thrOffTip() end
								if not _thrIsBar() then return "This option applies to bar-type resources only (pips use stack counts)." end
								return STAGGER_PCT_TIP
							end,
							get = function() local e=_thrEnt(); return (e and e.thresholdMode) or "percent" end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdMode=v; RefreshClass(); if RefreshDetail then RefreshDetail() end end },
						{ type = "segmented", label = "Direction",
							keys = { "upto", "from" }, labels = { upto = "Up to", from = "From" }, rawTooltip = true,
							disabled = function() return (not _thrOptUsable()) or _thrIsWarrCharge() end,
							disabledTooltip = function()
								if _thrIsWarrCharge() and _thrOptUsable() then return "Whirlwind and Sweeping Strikes thresholds only support the 'From' direction." end
								return _thrOffTip()
							end,
							get = function() if _thrIsWarrCharge() then return "from" end local e=_thrEnt(); return (e and e.thresholdReverse) and "upto" or "from" end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdReverse=(v=="upto"); RefreshClass(); if RefreshDetail then RefreshDetail() end end },
						{ type = "toggle", label = "Only color at/above threshold", rawTooltip = true,
							disabled = function() return (not _thrOptUsable()) or _thrIsBar() or _thrIsUpTo() or _thrIsWarrCharge() end,
							disabledTooltip = function()
								if _thrIsWarrCharge() and _thrOptUsable() then return "Always on for Whirlwind and Sweeping Strikes charges: range coloring at/above the threshold is the only way these bars can display thresholds." end
								if not _thrOptUsable() then return _thrOffTip() end
								if _thrIsBar() then return "This option applies to pip-type resources only." end
								return "Only available with the 'From' direction -- it highlights the pips at/above the threshold."
							end,
							get = function() if _thrIsWarrCharge() then return true end local e=_thrEnt(); return (e and e.thresholdPartialOnly) and true or false end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdPartialOnly=v; RefreshClass(); if RefreshDetail then RefreshDetail() end end },
					},
				})
				local threshCogBtn = CreateFrame("Button", nil, threshRow)
				threshCogBtn:SetSize(20, 20)
				threshCogBtn:SetPoint("RIGHT", threshRow, "RIGHT", 0, 0)
				threshCogBtn:SetFrameLevel(threshRow:GetFrameLevel() + 5)
				threshCogBtn:SetAlpha(0.5)
				local threshCogTex = threshCogBtn:CreateTexture(nil, "OVERLAY")
				threshCogTex:SetAllPoints(); threshCogTex:SetTexture(EllesmereUI.COGS_ICON)
				threshCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
				threshCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
				threshCogBtn:SetScript("OnClick", function(self) threshCogShow(self) end)
				local threshEnable, _, threshEnableSnap = EllesmereUI.BuildToggleControl(
					threshRow, DLVL + 4,
					function()
						local ent = CurEntry(); if not ent then return false end
						if ent.thresholdEnabled == nil then return true end
						return ent.thresholdEnabled
					end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.thresholdEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				local threshSwatch, threshSwatchSnap = EllesmereUI.BuildColorSwatch(
					threshRow, threshRow:GetFrameLevel() + 4,
					function()
						local ent = CurEntry()
						local pp = DB()
						local base = pp and pp.secondary
						if not ent then return 0x0c/255, 0xd2/255, 0x9d/255, 1 end
						return ent.thresholdR or (base and base.thresholdR) or 0x0c/255,
							ent.thresholdG or (base and base.thresholdG) or 0xd2/255,
							ent.thresholdB or (base and base.thresholdB) or 0x9d/255,
							ent.thresholdA or (base and base.thresholdA) or 1
					end,
					function(r, g, b, a)
						local ent = CurEntry(); if not ent then return end
						ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a
						SmoothRefresh()
					end, true, 19)
				threshSwatch:SetPoint("RIGHT", threshCogBtn, "LEFT", -8, 0)
				local threshInput = MakeInput(threshRow, 50, true)
				threshInput:SetPoint("RIGHT", threshSwatch, "LEFT", -8, 0)
				threshEnable:SetPoint("RIGHT", threshInput, "LEFT", -8, 0)
				local function _threshCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local ent = CurEntry(); if not ent then return end
					local mn, mx, df = self._min or 1, self._max or 100, self._def or 3
					local val = tonumber(self:GetText())
					if not val then self:SetText(tostring(ent.thresholdCount or df)); return end
					val = math.max(mn, math.min(mx, math.floor(val + 0.5)))
					self:SetText(tostring(val))
					ent.thresholdCount = val
					RefreshClass()
				end
				threshInput:SetScript("OnEditFocusLost", _threshCommit)
				threshInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				threshInput:SetScript("OnEscapePressed", function(self)
					self._cancelCommit = true
					local ent = CurEntry()
					self:SetText(tostring((ent and ent.thresholdCount) or self._def or 3))
					self:ClearFocus()
				end)
				threshRow._input = threshInput
				threshRow._enableSnap = threshEnableSnap
				threshRow._swatchSnap = threshSwatchSnap
				-- Greys the threshold input + swatch (label kept) while the threshold is off or replaced by multi-band
				local threshDis = CreateFrame("Frame", nil, threshRow)
				threshDis:SetPoint("TOPLEFT", threshInput, "TOPLEFT", -2, 3)
				threshDis:SetPoint("BOTTOMRIGHT", threshSwatch, "BOTTOMRIGHT", 3, -3)
				threshDis:SetFrameLevel(threshRow:GetFrameLevel() + 6)
				threshDis:EnableMouse(true)
				local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
				threshDisTex:SetAllPoints()
				threshDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
				threshDis:SetScript("OnEnter", function()
					local tip = (threshRow._disTip == "MULTI") and BAND_REPLACES_TIP
						or EllesmereUI.DisabledTooltip("Threshold Color")
					EllesmereUI.ShowWidgetTooltip(threshDis, tip)
				end)
				threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				threshRow._dis = threshDis

				-- Row: Multi-band (toggle + Bands editor button)
				local multiRow = DRow("Multi-band Coloring", ROWH)
				local bandsBtn = CreateFrame("Button", nil, multiRow)
				PP.Size(bandsBtn, 60, 22)
				bandsBtn:SetPoint("RIGHT", multiRow, "RIGHT", 0, 0)
				bandsBtn:SetFrameLevel(multiRow:GetFrameLevel() + 4)
				SkinCardButton(bandsBtn, EllesmereUI.L("Bands"), BAND_HELP_TIP)
				bandsBtn:SetScript("OnClick", function(self)
					local ent = CurEntry(); if not ent then return end
					local isStag
					if advSingle then isStag = (ctx.specID == 268)
					elseif ent.specIDs then
						for _, s in ipairs(ent.specIDs) do if s == 268 then isStag = true end end
					end
					ShowBandEditor({
						getBarData = function() local pp = DB(); return pp and pp.secondary end,
						refreshFn = function() RefreshClass() end,
						entryIdx = _selectedIdx, anchor = self,
						countBased = not ns.IsEntryBarType(ent),
						lockPercent = isStag, percentMax = isStag and 500 or nil,
						defR = 0x0c/255, defG = 0xd2/255, defB = 0x9d/255, defA = 1,
					})
				end)
				multiRow._bandsBtn = bandsBtn
				local multiToggle, _, multiSnap = EllesmereUI.BuildToggleControl(
					multiRow, DLVL + 4,
					function()
						local ent = CurEntry(); return ent and ent.multiBandEnabled or false
					end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.multiBandEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -10, 0)
				multiRow._toggle = multiToggle
				multiRow._snap = multiSnap
				multiToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP) end)
				multiToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

				-- Covers the toggle + Bands button when multi-band cannot apply (Enhance 5-bar style)
				local multiDis = CreateFrame("Frame", nil, multiRow)
				multiDis:SetPoint("TOPLEFT", multiToggle, "TOPLEFT", -3, 3)
				multiDis:SetPoint("BOTTOMRIGHT", bandsBtn, "BOTTOMRIGHT", 3, -3)
				multiDis:SetFrameLevel(multiRow:GetFrameLevel() + 8)
				multiDis:EnableMouse(true)
				local multiDisTex = multiDis:CreateTexture(nil, "OVERLAY")
				multiDisTex:SetAllPoints()
				multiDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
				multiDis:SetScript("OnEnter", function()
					EllesmereUI.ShowWidgetTooltip(multiDis, EllesmereUI.L("Unavailable with Enhancement 5-bar style."))
				end)
				multiDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				multiDis:Hide()
				multiRow._dis = multiDis

				-- Row: Buff colors (per-entry list). "Buffs" opens the editor, the toggle enables applying them. First active buff wins and overrides threshold coloring.
				local buffRow = DRow("Buff Colors", ROWH)
				local buffsBtn = CreateFrame("Button", nil, buffRow)
				PP.Size(buffsBtn, 60, 22)
				buffsBtn:SetPoint("RIGHT", buffRow, "RIGHT", 0, 0)
				buffsBtn:SetFrameLevel(buffRow:GetFrameLevel() + 4)
				SkinCardButton(buffsBtn, EllesmereUI.L("Buffs"), BUFF_HELP_TIP)
				buffsBtn:SetScript("OnClick", function(self)
					local ent = CurEntry(); if not ent then return end
					ShowBuffEditor({
						getBarData = function() local pp = DB(); return pp and pp.secondary end,
						refreshFn = function() RefreshClass() end,
						entryIdx = _selectedIdx, anchor = self,
					})
				end)
				buffRow._buffsBtn = buffsBtn
				local buffToggle, _, buffSnap = EllesmereUI.BuildToggleControl(
					buffRow, DLVL + 4,
					function() local ent = CurEntry(); return ent and ent.buffColorEnabled or false end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.buffColorEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				buffToggle:SetPoint("RIGHT", buffsBtn, "LEFT", -10, 0)
				buffRow._toggle = buffToggle
				buffRow._snap = buffSnap
				buffToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BUFF_HELP_TIP) end)
				buffToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

				-- Row: Spender colors (per-entry list). "Spenders" opens the editor, the toggle enables applying them. First castable spell wins; an active tracked buff takes priority.
				local spenderRow = DRow("Spender Colors", ROWH)
				local spendersBtn = CreateFrame("Button", nil, spenderRow)
				PP.Size(spendersBtn, 60, 22)
				spendersBtn:SetPoint("RIGHT", spenderRow, "RIGHT", 0, 0)
				spendersBtn:SetFrameLevel(spenderRow:GetFrameLevel() + 4)
				SkinCardButton(spendersBtn, EllesmereUI.L("Spenders"), SPENDER_HELP_TIP)
				spendersBtn:SetScript("OnClick", function(self)
					local ent = CurEntry(); if not ent then return end
					ShowSpenderEditor({
						getBarData = function() local pp = DB(); return pp and pp.secondary end,
						refreshFn = function() RefreshClass() end,
						entryIdx = _selectedIdx, anchor = self,
					})
				end)
				spenderRow._spendersBtn = spendersBtn
				local spenderToggle, _, spenderSnap = EllesmereUI.BuildToggleControl(
					spenderRow, DLVL + 4,
					function() local ent = CurEntry(); return ent and ent.spenderColorEnabled or false end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.spenderColorEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				spenderToggle:SetPoint("RIGHT", spendersBtn, "LEFT", -10, 0)
				spenderRow._toggle = spenderToggle
				spenderRow._snap = spenderSnap
				spenderToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, SPENDER_HELP_TIP) end)
				spenderToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

				-- Row: Recolor text instead of bar. Bar-wide section-level field, not per-entry: shown once at the bottom of the pane, only for resources where it applies (continuous bars + Guardian Ironfur)
				local textInsteadRow = DRow("Recolor Text Instead Of Bar", ROWH)
				local textInsteadToggle, _, textInsteadSnap = EllesmereUI.BuildToggleControl(
					textInsteadRow, DLVL + 4,
					function() local ent = CurEntry(); return ent and ent.thresholdTextInstead or false end,
					function(v) local ent = CurEntry(); if not ent then return end
						ent.thresholdTextInstead = v; RefreshClass() end,
					{ sizeRatio = 0.95 }
				)
				textInsteadToggle:SetPoint("RIGHT", textInsteadRow, "RIGHT", 0, 0)
				textInsteadRow._toggle = textInsteadToggle
				textInsteadRow._snap = textInsteadSnap
				-- Vengeance soul fragments and the Prot Ignore Pain bar are SECRET values, so recoloring text cannot work there; toggled per-entry in RefreshDetail
				local TI_BLOCK_TIP = "Not available for this spec: Vengeance soul fragments and the Protection Ignore Pain bar use secret values that can't be read into a text color, so recoloring the text would have no effect."
				local textInsteadDis = CreateFrame("Frame", nil, textInsteadRow)
				textInsteadDis:SetPoint("TOPLEFT", textInsteadRow, "TOPLEFT", -2, 3)
				textInsteadDis:SetPoint("BOTTOMRIGHT", textInsteadToggle, "BOTTOMRIGHT", 3, -3)
				textInsteadDis:SetFrameLevel(textInsteadRow:GetFrameLevel() + 6)
				textInsteadDis:EnableMouse(true)
				local textInsteadDisTex = textInsteadDis:CreateTexture(nil, "OVERLAY")
				textInsteadDisTex:SetAllPoints()
				textInsteadDisTex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
				textInsteadDis:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(textInsteadDis, EllesmereUI.L(TI_BLOCK_TIP)) end)
				textInsteadDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				textInsteadDis:Hide()
				textInsteadRow._dis = textInsteadDis
				-- Row: Stagger ceiling % (Brewmaster only). The stagger bar fills to this % of max
				-- health (lower = fills sooner); the color % thresholds still use REAL max health.
				-- Bar-wide (DB().secondary), placed only for stagger.
				local ceilingRow = DRow("Stagger Full %", ROWH)
				local ceilingInput = MakeInput(ceilingRow, 50, true)
				ceilingInput:SetPoint("RIGHT", ceilingRow, "RIGHT", 0, 0)
				ceilingInput:SetMaxLetters(3)
				local function ceilingSnap()
					local p = DB()
					ceilingInput:SetText(tostring((p and p.secondary.staggerCeilingPercent) or 100))
				end
				local function CeilingCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local p = DB(); if not p then return end
					local v = tonumber(self:GetText())
					if v then
						v = math.max(1, math.min(500, math.floor(v + 0.5)))
						p.secondary.staggerCeilingPercent = v
						RefreshClass()
					end
					ceilingSnap()
				end
				ceilingInput:SetScript("OnEditFocusLost", CeilingCommit)
				ceilingInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				ceilingInput:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); ceilingSnap() end)

				-- RefreshDetail: repaint the pane for the selected entry
				RefreshDetail = function()
					if _thrNoticeC then _thrNoticeC() end
					local ent = CurEntry()
					if not ent then
						for _, rf in ipairs(_allRows) do rf:Hide() end
						dPlaceholder:Show()
						return
					end
					dPlaceholder:Hide()

					local isBar = ns.IsEntryBarType(ent)
					local isGuardian, isIgnorePain, isVengeance
					if advSingle then
						isGuardian = (ctx.specID == 104)
						isIgnorePain = (ctx.specID == 73)
						isVengeance = (ctx.specID == 581)
					else
						if ent.specIDs then
							for _, s in ipairs(ent.specIDs) do
								-- WoW Forever: the Druid class resource there is combo points, which
								-- draw the card's hash lines, so the Ironfur bar exception is retail only.
								-- Retail keeps the row while the card holds hash lines, so lines saved
								-- on WoW Forever can be cleared.
								if s == 104 and not EllesmereUI.IS_FOREVER and (ent.hashValues == nil or ent.hashValues == "") then isGuardian = true end
								if s == 73 then isIgnorePain = true end
								if s == 581 then isVengeance = true end
							end
						end
					end
					-- "Recolor text instead" no-ops for secret resources (Vengeance soul fragments, Prot Ignore Pain bar): grey those entries
					local _tiPP = DB()
					local tiBlocked = (isVengeance or (isIgnorePain and _tiPP and _tiPP.secondary.protIgnorePainBar)) and true or false
					textInsteadRow._dis:SetShown(tiBlocked)
					if textInsteadRow._lbl then textInsteadRow._lbl:SetAlpha(tiBlocked and 0.3 or 0.6) end
					-- Brewmaster only, keyed off the SELECTED entry's spec rather than the live spec, so editing another spec's entry while playing Brewmaster stays unlocked
					local isStagger
					if advSingle then isStagger = (ctx.specID == 268)
					elseif ent.specIDs then
						for _, s in ipairs(ent.specIDs) do if s == 268 then isStagger = true end end
					end
					if isStagger and ent.thresholdMode == "value" then ent.thresholdMode = "percent" end

					-- Talent gate is single-spec only
					local allowTalent
					if advSingle then
						allowTalent = true
					else
						local ids = ent.specIDs
						allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
					end

					-- Refill talent options from the active loadout plus the entry's saved gate, even if off-spec/off-loadout
					if allowTalent then
						local loadoutTalents = (ns.GetLoadoutTalents()) or {}
						local vals, ord = talentRow._talentValues, talentRow._talentOrder
						wipe(ord)
						for k in pairs(vals) do if k ~= "_menuOpts" then vals[k] = nil end end
						vals[0] = EllesmereUI.L("No talent"); ord[#ord + 1] = 0
						for _, t in ipairs(loadoutTalents) do
							if vals[t.spellID] == nil then ord[#ord + 1] = t.spellID end
							vals[t.spellID] = t.name
						end
						if ent.talentSpellID and vals[ent.talentSpellID] == nil then
							vals[ent.talentSpellID] = ent.talentName
								or (C_Spell.GetSpellName and C_Spell.GetSpellName(ent.talentSpellID))
								or ("Spell " .. ent.talentSpellID)
							ord[#ord + 1] = ent.talentSpellID
						end
						if talentDD._invalidateMenu then talentDD._invalidateMenu() end
						if talentDD._refreshLabel then talentDD._refreshLabel() end
					end

					-- Hash row text
					local hashWord
					if isBar then
						hashWord = (ent.hashMode == "percent") and EllesmereUI.L("Percent") or EllesmereUI.L("Value")
					else
						hashWord = EllesmereUI.L("Stack")
					end
					hashRow._lbl2:SetText(EllesmereUI.Lf("Hash at %1$s", hashWord))
					hashRow._hint:SetText(isBar and EllesmereUI.L("(Ex: 25,50,75)") or EllesmereUI.L("(Ex: 2,4)"))
					hashRow._input:SetText(ent.hashValues or "")

					-- Threshold input bounds (Enhance five-bar minimum). Bar-type reads the threshold as % (max 100) or an absolute value (higher cap)
					local threshIsValue = isBar and not isStagger and ent.thresholdMode == "value"
					local threshMax = isStagger and 500 or (isBar and (threshIsValue and 1000 or 100) or 20)
					local entryIsEnhance = false
					local pp = DB()
					if pp and pp.secondary.enhanceFiveBar == true then
						if advSingle then
							entryIsEnhance = (ctx.specID == 263)
						elseif ent.specIDs then
							for _, s in ipairs(ent.specIDs) do
								if s == 263 then entryIsEnhance = true; break end
							end
						end
					end
					local threshMin = entryIsEnhance and 7 or 1
					local threshDef = entryIsEnhance and 7 or (isBar and 30 or 3)
					threshInput._min, threshInput._max, threshInput._def = threshMin, threshMax, threshDef
					threshInput:SetText(tostring(ent.thresholdCount or threshDef))
					if entryIsEnhance then
						threshInput:SetScript("OnEnter", function(self)
							EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Enhance 5 Bar minimum is %d (if you want less just change 5 bar color)"):format(threshMin))
						end)
						threshInput:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
					else
						threshInput:SetScript("OnEnter", nil)
						threshInput:SetScript("OnLeave", nil)
					end
					threshRow._lbl:SetText(EllesmereUI.L("Threshold") .. ((isBar and not threshIsValue) and " %" or ""))

					-- Talents come from the player's own loadout, so block the picker for other classes' specs
					local talentClassOK = true
					if allowTalent then
						local specID = advSingle and ctx.specID or (ent.specIDs and ent.specIDs[1])
						if specID and specID ~= 0 and GetSpecializationInfoByID then
							local _, _, _, _, _, classFile = GetSpecializationInfoByID(specID)
							local _, playerClass = UnitClass("player")
							talentClassOK = (classFile == playerClass)
						elseif specID and specID ~= 0 and EllesmereUI.IS_FOREVER then
							talentClassOK = (EllesmereUI.SpecClassOf(specID) == select(2, UnitClass("player")))
						end
						talentRow._dis:SetShown(not talentClassOK)
					end

					-- Snap the toggles / swatches to the entry
					if talentDD._refreshLabel then talentDD._refreshLabel() end
					hashRow._swatchSnap()
					threshEnableSnap(); threshSwatchSnap(); multiSnap(); buffSnap(); textInsteadSnap(); ceilingSnap()
					spenderSnap()

					-- Single threshold and multi-band are independent toggles
					local entEnabled = ent.thresholdEnabled
					if entEnabled == nil then entEnabled = true end
					local multiOn = (ent.multiBandEnabled and not entryIsEnhance) and true or false
					if entryIsEnhance then
						multiToggle:SetAlpha(0.35); multiToggle:SetEnabled(false)
						bandsBtn:SetAlpha(0.35); bandsBtn:SetEnabled(false)
						if multiRow._lbl then multiRow._lbl:SetAlpha(0.3) end
						multiRow._dis:Show()
					else
						multiToggle:SetAlpha(1); multiToggle:SetEnabled(true)
						bandsBtn:SetAlpha(multiOn and 1 or 0.35); bandsBtn:SetEnabled(multiOn)
						if multiRow._lbl then multiRow._lbl:SetAlpha(0.6) end
						multiRow._dis:Hide()
					end
					if multiOn then
						threshRow._disTip = "MULTI"; threshDis:Show()
					elseif not entEnabled then
						threshRow._disTip = nil; threshDis:Show()
					else
						threshDis:Hide()
					end

					-- Layout pass: place visible rows top-to-bottom
					for _, rf in ipairs(_allRows) do rf:Hide() end
					local yy = -DPAD
					local function place(rf)
						rf:ClearAllPoints()
						PP.Point(rf, "TOPLEFT", detailC, "TOPLEFT", DPAD, yy)
						PP.Point(rf, "TOPRIGHT", detailC, "TOPRIGHT", -DPAD, yy)
						rf:Show()
						yy = yy - (rf._rawH or ROWH) - ROWGAP
					end
					if allowTalent then place(talentRow) end
					if not isGuardian and not isIgnorePain then place(hashRow) end
					place(threshRow)
					place(multiRow)
					place(buffRow)
					place(spenderRow)
					-- Bar-wide text-instead toggle always gets a row (no visible effect for pip resources / Ignore Pain, whose render path keeps its own coloring)
					place(textInsteadRow)
					if isStagger then place(ceilingRow) end
				end
				thrPage:Hide();
        end -- BuildFrame

			-- BuildFrame runs lazily on the first ToggleFrame open, not here

        -- Build/Refresh dynamic entry frames
        RefreshSpecEntries = function(scrollToSel)
            if _thrNoticeC then _thrNoticeC() end
            local p = DB(); if not p then return end
            local sp = p.secondary
            if not sp.thresholdSpecs then sp.thresholdSpecs = {} end
            local entries = sp.thresholdSpecs
            local PP = EllesmereUI.PanelPP or EllesmereUI.PP

            -- The entry the resolver actually picks in-game right now; seeds the default selection so it opens pre-selected
            local activeIdx
            do
                local resolved = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp)
                if resolved then
                    for i = 1, #entries do
                        if entries[i] == resolved then activeIdx = i; break end
                    end
                end
            end

            -- Resolve/clamp the selection: active entry, else the first
            if #entries == 0 then
                _selectedIdx = nil
            else
                if _selectedIdx and _selectedIdx > #entries then _selectedIdx = #entries end
                if not _selectedIdx or _selectedIdx < 1 then _selectedIdx = activeIdx or 1 end
            end

            local scrollChild = specContainer._scrollChild
            local curY = 0
            local ENTRY_W = contentHalfSize - 6
            local ENTRY_H = 32

            -- Paints one row's bg/accent for the current selection state
            local function PaintRow(f)
                local sel = (f._entryIdx ~= nil) and (_selectedIdx == f._entryIdx)
                f._selected = sel
                f._accent:SetShown(sel)
                -- Re-apply the live theme accent each paint; the creation-time color goes stale after a theme change
                f._accent:SetColorTexture(EG.r, EG.g, EG.b, 1)
                if sel then
                    f._bg:SetColorTexture(EG.r, EG.g, EG.b, 0.10)
                else
                    f._bg:SetColorTexture(1, 1, 1, 0.02)
                end
            end

            for i = 1, #_entryFrames do
                if _entryFrames[i] then _entryFrames[i]:Hide() end
            end

            for idx, entry in ipairs(entries) do
                local ef = _entryFrames[idx]
                if not ef then
                    ef = CreateFrame("Button", nil, scrollChild)
                    ef:SetFrameLevel(thrPage:GetFrameLevel() + 2)
                    ef:RegisterForClicks("LeftButtonUp")
                    _entryFrames[idx] = ef

                    local entBg = ef:CreateTexture(nil, "BACKGROUND")
                    entBg:SetAllPoints()
                    entBg:SetColorTexture(1, 1, 1, 0.02)
                    ef._bg = entBg

                    -- Selection accent: left theme-accent bar
                    local accent = ef:CreateTexture(nil, "ARTWORK")
                    accent:SetPoint("TOPLEFT", ef, "TOPLEFT", 0, 0)
                    accent:SetPoint("BOTTOMLEFT", ef, "BOTTOMLEFT", 0, 0)
                    accent:SetWidth(3)
                    accent:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    accent:Hide()
                    ef._accent = accent

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetSize(14, 14)
                    delBtn:SetPoint("RIGHT", ef, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetAllPoints()
                    delIcon:SetTexture(CLOSE_ICON_PATH)
                    delIcon:SetAlpha(0.4)
                    delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                    delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                    ef._delBtn = delBtn

                    -- Add-variant duplicates this entry as a talent-gated sibling for the same spec; sits left of the delete X
                    local varBtn = CreateFrame("Button", nil, ef)
                    PP.Size(varBtn, 84, 20)
                    varBtn:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
                    varBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local varBg = varBtn:CreateTexture(nil, "BACKGROUND")
                    varBg:SetAllPoints()
                    varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    varBtn._border = EllesmereUI.MakeBorder(varBtn, 1, 1, 1, 0.08, PP)
                    local varLbl = EllesmereUI.MakeFont(varBtn, 11, nil, 1, 1, 1)
                    varLbl:SetText(EllesmereUI.L("Add Variant"))
                    varLbl:SetAlpha(0.65)
                    varLbl:SetPoint("CENTER")
                    varBtn:SetScript("OnEnter", function(self)
                        varBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                        varLbl:SetAlpha(0.9)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Add a talent variant of this entry"))
                    end)
                    varBtn:SetScript("OnLeave", function()
                        varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        varLbl:SetAlpha(0.65)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    varBtn:SetScript("OnClick", function()
                        if not ef._entryIdx then return end
                        local p2 = DB(); if not p2 then return end
                        local specs = p2.secondary.thresholdSpecs
                        local src = specs and specs[ef._entryIdx]; if not src then return end
                        local copy = CopyThresholdEntry(src)
                        copy.talentSpellID = nil
                        copy.talentName = nil
                        table.insert(specs, ef._entryIdx + 1, copy)
                        _selectedIdx = ef._entryIdx + 1
                        RefreshSpecEntries()
                        if RefreshDetail then RefreshDetail() end
                        RebuildClass()
                    end)
                    ef._varBtn = varBtn

                    -- Spec/talent group label (class-colored)
                    local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                    specLbl:SetAlpha(0.85)
                    specLbl:SetPoint("LEFT", ef, "LEFT", 12, 0)
                    specLbl:SetPoint("RIGHT", varBtn, "LEFT", -8, 0)
                    specLbl:SetJustifyH("LEFT")
                    specLbl:SetWordWrap(false)
                    ef._specLbl = specLbl

                    -- Whole row selects this entry: repaint + refresh the detail pane with no list rebuild, so the scroll never jumps
                    ef:SetScript("OnClick", function(self)
                        if not self._entryIdx then return end
                        _selectedIdx = self._entryIdx
                        for i = 1, #_entryFrames do
                            local f = _entryFrames[i]
                            if f and f:IsShown() then PaintRow(f) end
                        end
                        if RefreshDetail then RefreshDetail() end
                    end)
                    ef:SetScript("OnEnter", function(self)
                        if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                    end)
                    ef:SetScript("OnLeave", function(self)
                        if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.02) end
                    end)
                end -- end entry frame creation

                ef._entryIdx = idx
                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, curY)
                ef._yOffset = -curY

                -- In Advanced the spec is implicit, so the card is labelled by its talent gate ("Default" for the base card)
                if advSingle then
                    ef._specLbl:SetText(entry.talentName or EllesmereUI.L("Default"))
                else
                    ef._specLbl:SetText(ns.EntryLabel(entry))
                end
                -- Class-color the label from the first specID
                do
                    local firstSID = entry.specIDs and entry.specIDs[1]
                    local classFile
                    if firstSID == 0 then
                        local _, cf = UnitClass("player")
                        classFile = cf
                    elseif firstSID and GetSpecializationInfoByID then
                        local _, _, _, _, _, cf = GetSpecializationInfoByID(firstSID)
                        classFile = cf
                    elseif firstSID and EllesmereUI.IS_FOREVER then
                        classFile = EllesmereUI.SpecClassOf(firstSID)
                    end
                    local cc = classFile and CLASS_COLORS[classFile]
                    if cc then
                        ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                    else
                        ef._specLbl:SetTextColor(1, 1, 1, 1)
                    end
                end

                -- Talent variants are single-spec only: "All Specs"/multi-spec cards span specs, so a talent gate is meaningless. Hide the "Add variant" button there and strip any stale gate.
                local _allowTalent
                if advSingle then
                    _allowTalent = true
                else
                    local ids = entry.specIDs
                    _allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
                end
                if ef._varBtn then ef._varBtn:SetShown(_allowTalent) end
                if not _allowTalent and entry.talentSpellID then
                    entry.talentSpellID = nil
                    entry.talentName = nil
                    RebuildClass()
                end

                ef._delBtn:SetScript("OnClick", function()
                    local p2 = DB(); if not p2 then return end
                    table.remove(p2.secondary.thresholdSpecs, idx)
                    local n = #p2.secondary.thresholdSpecs
                    if n == 0 then _selectedIdx = nil
                    elseif _selectedIdx and _selectedIdx > n then _selectedIdx = n end
                    RefreshSpecEntries()
                    if RefreshDetail then RefreshDetail() end
                    RefreshClass()
                end)

                -- Selection highlight; duplicates the resolver can never reach are shadow-dimmed
                PaintRow(ef)
                ef:SetAlpha(ns._ERB_IsThresholdCardShadowed(entries, idx) and 0.45 or 1)

                ef:Show()
                curY = curY - ENTRY_H - ROW_GAP
            end

            -- Empty-state add, Advanced only: the spec-assignment chrome is hidden there, so deleting the last card would strand the user. Cards replace this button once one exists.
            if advSingle and #entries == 0 then
                if not _addNewBtn then
                    local b = CreateFrame("Button", nil, scrollChild)
                    PP.Size(b, contentHalfSize - 12, 30)
                    local bbg = EllesmereUI.SolidTex(b, "BACKGROUND", 0.069, 0.058, 0.047, 0.92)
                    bbg:SetAllPoints()
                    b._border = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.4, PP)
                    local blbl = EllesmereUI.MakeFont(b, 12, nil, 1, 1, 1)
                    blbl:SetAlpha(0.5); blbl:SetPoint("CENTER")
                    blbl:SetText(EllesmereUI.L("Add Threshold"))
                    b:SetScript("OnEnter", function()
                        blbl:SetAlpha(0.7)
                        if b._border and b._border.SetColor then b._border:SetColor(1, 1, 1, 0.6) end
                    end)
                    b:SetScript("OnLeave", function()
                        blbl:SetAlpha(0.5)
                        if b._border and b._border.SetColor then b._border:SetColor(1, 1, 1, 0.4) end
                    end)
                    b:SetScript("OnClick", function()
                        local p2 = DB(); if not p2 then return end
                        local sp2 = p2.secondary; if not sp2 then return end
                        if not sp2.thresholdSpecs then sp2.thresholdSpecs = {} end
                        local isBar = ns.IsSpecBarType(ctx.specID)
                        sp2.thresholdSpecs[#sp2.thresholdSpecs + 1] = {
                            specIDs = { 0 },
                            hashValues = "", hashWidth = 1,
                            hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                            thresholdEnabled = true,
                            thresholdCount = (ctx.specID == 263 and sp2.enhanceFiveBar) and 7 or (isBar and 30 or 3),
                            thresholdPartialOnly = false,
                            thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
                        }
                        _selectedIdx = #sp2.thresholdSpecs
                        RefreshSpecEntries()
                        if RefreshDetail then RefreshDetail() end
                        RebuildClass()
                    end)
                    _addNewBtn = b
                end
                _addNewBtn:ClearAllPoints()
                _addNewBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -6)
                _addNewBtn:Show()
                curY = -(6 + 30)
            elseif _addNewBtn then
                _addNewBtn:Hide()
            end

            local contentH = math.abs(curY) + SIDE_PAD
            scrollChild:SetSize(contentHalfSize, math.max(1, contentH))

            -- Clamp scroll-frame height to the container minus the header
            local headerH = specContainer._headerH or 0
            local scrollH = math.min(contentH, specContainer._maxH - headerH)
            scrollH = math.max(scrollH, SIDE_PAD)
            specContainer._scrollFrame:SetHeight(scrollH)

            -- Scroll the list to the selected row (on open / add)
            if scrollToSel and _selectedIdx and _entryFrames[_selectedIdx] then
                local sf = specContainer._scrollFrame
                local viewH = sf:GetHeight()
                local range = math.max(0, contentH - viewH)
                local target = math.max(0, math.min(range, (_entryFrames[_selectedIdx]._yOffset or 0) - 8))
                sf:SetVerticalScroll(target)
            end
        end
			-- No immediate populate: the first ToggleFrame open builds the frame and calls RefreshSpecEntries.

        -- Show/Hide popup
        local function ToggleFrame(anchor)
            -- Nothing to configure with no config (Advanced, no spec selected/customised). The disabled overlay already blocks this, but the open path is guarded too.
            if not DB() then return end
            if not thrPage then BuildFrame({topY = _advTop, botY = y}) end
				if thrPage:IsShown() then
					-- Unlock cycle: forces a correct redraw
					if thrPage:GetLeft() ~= nil then
						thrPage:Hide()
						return
					end
					thrPage:Hide()
				end
            wipe(_tempSpecSel)
            if _specDDRefresh then _specDDRefresh() end
            -- Re-pick the resolver's active entry each open, then scroll to it
            _selectedIdx = nil
            RefreshSpecEntries(true)
            if RefreshDetail then RefreshDetail() end
				if thrPage._reanchor then thrPage._reanchor() end
				thrPage:Show()
        end

        settingsBtn:SetScript("OnClick", function(self) ToggleFrame(self) end)

        -- Close on page switch or main panel close
        settingsBtn:HookScript("OnHide", function()
            if thrPage and thrPage:IsShown() then thrPage:Hide() end
        end)

        -- Spec/talent changes move which entry the resolver picks and change the available loadout
        -- talents, so refresh the open popup live while KEEPING the current selection (never yank the
        -- user mid-edit). The event frame + accent callback MUST be module-level singletons: this section
        -- builder re-runs on every options rebuild (Simple/Advanced, sync toggles, spec add/remove), so
        -- per-build creation would leak a permanently-registered frame and a permanent accent entry each
        -- time. They read the popup via ns._thrCtx, refreshed here.
        ns._thrCtx = { page = thrPage, entryFrames = _entryFrames,
                       refresh = RefreshSpecEntries, refreshDetail = RefreshDetail }
        if not ns._thrEventsFrame then
            local ev = CreateFrame("Frame")
            ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
            ev:RegisterEvent("PLAYER_TALENT_UPDATE")
            ev:SetScript("OnEvent", function(_, event)
                local c = ns._thrCtx
                if c and c.page and c.page:IsShown() then
                    -- Popup open: in-place refresh only; a full page rebuild would tear the open popup down
                    if c.refresh then c.refresh() end
                    if c.refreshDetail then c.refreshDetail() end
                elseif (event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED")
                       and EllesmereUI:IsShown() and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                    -- Display page (Simple/Advanced) open: redraw on spec swap
                    C_Timer.After(0, function()
                        if EllesmereUI:IsShown() and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                            EllesmereUI:RefreshPage(true)
                        end
                    end)
                end
            end)
            ns._thrEventsFrame = ev
            -- The selection highlight follows the live theme accent
            EllesmereUI.RegAccent({ type = "callback", fn = function(r, g, b)
                local c = ns._thrCtx
                if not (c and c.page and c.page:IsShown()) then return end
                local ef = c.entryFrames
                for i = 1, #ef do
                    local f = ef[i]
                    if f and f:IsShown() then
                        f._accent:SetColorTexture(r, g, b, 1)
                        if f._selected then f._bg:SetColorTexture(r, g, b, 0.10) end
                    end
                end
            end })
        end
    end
		-- class settings [end]
    -- Class-specific rows: DK runes, Shaman Enhance, Hunter Focus. DK rune and Shaman enhance fields
    -- resolve per-spec at runtime, so they route through cfg(). Hunter "Focus as Power" is read
    -- globally (power-type resolution), so it stays a Simple-page global toggle.
    do
        local _, playerClass = UnitClass("player")
        if playerClass == "DEATHKNIGHT" then
            local simpleRuneRow
            simpleRuneRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Custom Recharge Color",
                  tooltip = "Choose the color of recharging runes instead of a dimmed version of the rune color.",
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  getValue = function() local c = cfg(); return c and c.runesCustomRecharge end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.runesCustomRecharge = v
                      RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", text = "Simple Runes",
                  tooltip = "Show rune count in center and remove recharge text/animation",
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  getValue = function() local c = cfg(); return c and c.runesSimple end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.runesSimple = v
                      RebuildClass()
                  end }); y = y - h
            -- Custom recharge color inline swatch
            if not EllesmereUI._prebuilding then
                local rgn = simpleRuneRow._leftRegion
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, simpleRuneRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg(); if not c then return 0.5, 0.5, 0.5, 1 end
                        return c.runesRechargeR or 0.5, c.runesRechargeG or 0.5, c.runesRechargeB or 0.5, c.runesRechargeA or 1
                    end,
                    function(r, g, b, a)
                        local c = cfg(); if not c then return end
                        c.runesRechargeR = r
                        c.runesRechargeG = g
                        c.runesRechargeB = b
                        c.runesRechargeA = a
                        SmoothRefresh()
                    end, true, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                local swatchBlock = CreateFrame("Frame", nil, swatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Custom Recharge Color"))
                end)
                swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateRechargeSwatch()
                    local c = cfg()
                    local off = not (c and c.enabled) or not c.runesCustomRecharge
                    if off then swatch:SetAlpha(0.3); swatchBlock:Show() else swatch:SetAlpha(1); swatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() if updateSwatch then updateSwatch() end; UpdateRechargeSwatch() end)
                UpdateRechargeSwatch()
            end
        end
        -- Retail only: WoW Forever hunters use mana and have no BM/MM specs.
        if playerClass == "HUNTER" and not ctx.advanced and not EllesmereUI.IS_FOREVER then
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Show Focus as Power Bar (BM/MM)",
                  tooltip = "When enabled, BM and MM specs show Focus as the standard power bar instead of a class resource bar.",
                  getValue = function()
                      local p = DB(); if not p then return false end
                      return p.secondary.hunterFocusAsPower or false
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.hunterFocusAsPower = v
                      RebuildPower(); RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "label", text = "" }); y = y - h
        end
        -- Retail only: WoW Forever has no Enhancement spec.
        if playerClass == "SHAMAN" and not EllesmereUI.IS_FOREVER then
            -- Enhance 5-bar applies to Enhancement (specID 263) only, gated on the active spec
            local function _enhSpecOK()
                return C_SpecializationInfo.GetSpecialization() == 2
            end
            local enhRow
            enhRow, h = W:DualRow(parent, y,
                { type = "toggle", text = "Enhance 5 Bar Style",
                  disabled = function()
                      local c = cfg()
                      return not (c and c.enabled) or not _enhSpecOK()
                  end,
                  disabledTooltip = "Requires Enhancement Shaman with Class Resource enabled.", rawTooltip = true,
                  getValue = function() local c = cfg(); return c and c.enhanceFiveBar end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.enhanceFiveBar = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "label", text = "" }); y = y - h
            -- Overflow color inline swatch
            if not EllesmereUI._prebuilding then
                local rgn = enhRow._leftRegion
                local swatch = EllesmereUI.BuildColorSwatch(
                    rgn, enhRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg(); if not c then return 1, 0.6, 0.2, 1 end
                        return c.enhanceOverflowR or 1, c.enhanceOverflowG or 0.6, c.enhanceOverflowB or 0.2, 1
                    end,
                    function(r, g, b)
                        local c = cfg(); if not c then return end
                        c.enhanceOverflowR = r
                        c.enhanceOverflowG = g
                        c.enhanceOverflowB = b
                        SmoothRefresh()
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                local function UpdateEnhSwatchVis()
                    local c = cfg()
                    local off = not (c and c.enabled) or not c.enhanceFiveBar or not _enhSpecOK()
                    swatch:SetAlpha(off and 0.3 or 1)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateEnhSwatchVis)
                UpdateEnhSwatchVis()
            end
        end
    end
    end   -- close Class Resource hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides the Class Resource in Advanced, so edits here aren't silently ignored.
    if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "secondary") end

    -- Blizzard Class Resource Art stands in for this bar: block the styling rows above.
    ns.ERB_BlizzArtBlockRegions(artRegions)

    -- Header + row frames go back so the Simple page can wire its preview click-mappings (classSection/classEnableRow, and the Resource Text row for the count-text overlay).
    return y, hdr, classEnableRow, classColorRow
end
--- [class resource end]
