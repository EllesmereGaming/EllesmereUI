if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\ClassResourceSection_Options.lua
--  Resource Bars options: CLASS RESOURCE BAR section builder. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page
-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

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
-- relevant spec (global storage). The Hide-Power cog is Simple-only. The Threshold &
-- Hash Lines row hosts the shared editor (env.BuildThresholdSettingsButton).
function ns.ERB_BuildClassResourceSection(parent, y, ctx)
    local env = ns._ERB_OptEnv
    local DB, PP, SmoothRefresh, RefreshClass = env.DB, env.PP, env.SmoothRefresh, env.RefreshClass
    local RebuildClass, RebuildPower, AddFormBarBtn, AddFormTextBtn = env.RebuildClass, env.RebuildPower, env.AddFormBarBtn, env.AddFormTextBtn
    local BuildThresholdSettingsButton, BAND_REPLACES_TIP, STAGGER_PCT_TIP = env.BuildThresholdSettingsButton, env.BAND_REPLACES_TIP, env.STAGGER_PCT_TIP
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
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = EllesmereUI.BuildSectionUnlockJump(hdr, { key = "ERB_ClassResource", disabled = classOff, disabledTooltip = "Class Resource" })

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
        local function _IsBrewmasterMonk()
            local _, cf = UnitClass("player")
            if cf ~= "MONK" then return false end
            local s = C_SpecializationInfo.GetSpecialization()
            local sid = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return sid == 268
        end
        if _IsBrewmasterMonk() then
            local ES_LABEL = "Brewmaster Monk Extended Stagger Bar"
            local ES_MAX = ns.EXT_STAGGER_MAX_SCALE or 6
            local function esOff() local p = DB(); return not (p and p.secondary.brewExtendedStaggerBar) end
            local function esScale()
                local p = DB(); if not p then return 4 end
                return ns.ExtStaggerScale and ns.ExtStaggerScale(p.secondary) or (p.secondary.brewExtendedStaggerScale or 4)
            end
            local esRow
            esRow, h = W:DualRow(parent, y,
                { type = "toggle", text = ES_LABEL,
                  tooltip = "Lets the stagger bar run past 100% of your max health. The bar spans Scale steps of 100%, each with its own fill color and an optional divider line. While on, the step colors replace threshold and multi-band coloring, and Scale replaces \"Stagger Full %\".",
                  getValue = function() local p = DB(); return p and p.secondary.brewExtendedStaggerBar end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.brewExtendedStaggerBar = v; RefreshClass()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Scale", min = ns.EXT_STAGGER_MIN_SCALE or 2, max = ES_MAX, step = 1,
                  tooltip = "How many 100% stagger steps the bar spans. Scale 4 fills the bar at 400% and puts divider lines at 100%, 200% and 300%.",
                  disabled = esOff,
                  disabledTooltip = ES_LABEL,
                  getValue = esScale,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.brewExtendedStaggerScale = v; RefreshClass()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
            -- Divider lines sit on Scale: Scale positions them
            if not EllesmereUI._prebuilding then
                local function divOff()
                    local p = DB()
                    return esOff() or not (p and p.secondary.brewExtendedStaggerDividers ~= false)
                end
                EllesmereUI.BuildInlineCog(esRow._rightRegion, {
                    disabled = esOff,
                    disabledTooltip = ES_LABEL,
                    title = "Scale Dividers",
                    rows = {
                        { type = "toggle", label = "Show Divider Lines",
                          get = function() local p = DB(); return p and p.secondary.brewExtendedStaggerDividers ~= false end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.brewExtendedStaggerDividers = v; RefreshClass()
                          end },
                        { type = "slider", label = "Line Thickness", min = 1, max = 4, step = 1,
                          disabled = divOff,
                          disabledTooltip = "Show Divider Lines",
                          get = function() local p = DB(); return p and p.secondary.brewExtendedStaggerDividerWidth or 1 end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.brewExtendedStaggerDividerWidth = v; RefreshClass()
                          end },
                        { type = "colorpicker", label = "Line Color", hasAlpha = true,
                          disabled = divOff,
                          disabledTooltip = "Show Divider Lines",
                          get = function()
                              local p = DB(); if not p then return 0, 0, 0, 1 end
                              local c = p.secondary
                              return c.brewExtendedStaggerDividerR or 0, c.brewExtendedStaggerDividerG or 0,
                                     c.brewExtendedStaggerDividerB or 0, c.brewExtendedStaggerDividerA or 1
                          end,
                          set = function(r, g, b, a)
                              local p = DB(); if not p then return end
                              local c = p.secondary
                              c.brewExtendedStaggerDividerR, c.brewExtendedStaggerDividerG = r, g
                              c.brewExtendedStaggerDividerB, c.brewExtendedStaggerDividerA = b, a
                              RefreshClass()
                          end },
                    },
                })
            end
            -- One swatch per fixed 100% step; steps above the current Scale lock
            local esStepTips = {
                "Step 1: 0% - 100%", "Step 2: 100% - 200%", "Step 3: 200% - 300%",
                "Step 4: 300% - 400%", "Step 5: 400% - 500%", "Step 6: 500%+",
            }
            local esSwatches = {}
            for i = 1, ES_MAX do
                local step = i
                esSwatches[step] = {
                    tooltip = esStepTips[step], hasAlpha = false,
                    disabled = function() return step > esScale() end,
                    disabledTooltip = function()
                        if esOff() then return ES_LABEL end
                        return "This step is above the current Scale."
                    end,
                    rawTooltip = function() return not esOff() end,
                    getValue = function()
                        local p = DB()
                        local t = p and p.secondary.brewExtendedStaggerColors
                        local c = t and t[step]
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        local d = ns.EXT_STAGGER_COLORS and ns.EXT_STAGGER_COLORS[step]
                        if d then return d[1], d[2], d[3] end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        local p = DB(); if not p then return end
                        local t = p.secondary.brewExtendedStaggerColors
                        if not t then t = {}; p.secondary.brewExtendedStaggerColors = t end
                        t[step] = { r = r, g = g, b = b }
                        RefreshClass()
                    end,
                }
            end
            _, h = W:DualRow(parent, y,
                { type = "multiSwatch", text = "Scale Colors",
                  tooltip = "Fill color per 100% stagger step, lowest step first. Steps above the current Scale are unused.",
                  disabled = esOff,
                  disabledTooltip = ES_LABEL,
                  swatches = esSwatches },
                EllesmereUI.BlankRowCfg()
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
    -- Class Resource cog: Simple only (Hide Power Bar if Resource is a row of
    -- the Bar Display page's BAR SHIFTING section)
    if not ctx.advanced then
        if not EllesmereUI._prebuilding then
            local rgn = classEnableRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = classOff,
                disabledTooltip = "Class Resource",
                title = "Class Resource",
                rows = {
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
    -- Chains left of the Class Resource cog in Simple mode (rgn._lastInline), or of the toggle itself in Advanced
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
            rgn._lastInline = borderSwatch  -- the Corner Radius cog chains left of the swatch
            -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
            -- border size control. The stock styles keep the bars square.
            if not EllesmereUI._prebuilding then
                EllesmereUI.BuildInlineCog(classBsRow._rightRegion, {
                    title = "Corner Radius", tip = "Corner Radius",
                    disabled = function()
                        if classOff() or EllesmereUI.BlizzStyle.Get("resourcebars") then return true end
                        local c = cfg(); return not EllesmereUI.RoundedStyleOK(c and c.borderTexture)
                    end,
                    disabledTooltip = function()
                        if EllesmereUI.BlizzStyle.Get("resourcebars") then return EllesmereUI.BlizzStyle.Label("resourcebars") end
                        if classOff() then return "Class Resource" end
                        return "This option requires the Solid, Glow or Shadow border style."
                    end,
                    requireState = function() return EllesmereUI.BlizzStyle.Get("resourcebars") and "disabled" or "enabled" end,
                    rows = EllesmereUI.RoundedCornerRows({
                        { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                          get = function() local c = cfg(); return c and c.cornerRadius or 0 end,
                          set = function(v) local c = cfg(); if not c then return end; c.cornerRadius = v; RebuildClass() end },
                    }, function() local c = cfg(); return c and c.cornerMask end,
                       function(v) local c = cfg(); if not c then return end; c.cornerMask = v; RebuildClass() end),
                })
            end
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
                    -- Border extensions: the full-bar border only, which pip and
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
                    { type = "slider", label = "Extend Left", min = 0, max = 300, step = 1,
                      tooltip = "Grows the border past the bar's left edge on screen without resizing the bar.",
                      disabled = function() local c = cfg(); return (c and c.borderOnPips and not ns.IsBarTypeSecondary()) and true or false end,
                      disabledTooltip = "This option can't be used while Border on individual pips is enabled.", rawTooltip = true,
                      get = function() local c = cfg(); return c and c.borderExtendLeft or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendLeft = v; RebuildClass(); EllesmereUI:RefreshPage()
                      end },
                    { type = "slider", label = "Extend Right", min = 0, max = 300, step = 1,
                      tooltip = "Grows the border past the bar's right edge on screen without resizing the bar.",
                      disabled = function() local c = cfg(); return (c and c.borderOnPips and not ns.IsBarTypeSecondary()) and true or false end,
                      disabledTooltip = "This option can't be used while Border on individual pips is enabled.", rawTooltip = true,
                      get = function() local c = cfg(); return c and c.borderExtendRight or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.borderExtendRight = v; RebuildClass(); EllesmereUI:RefreshPage()
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
                    local cr, cm = p.secondary.cornerRadius or 0, p.secondary.cornerMask
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz; p.primary.borderTexture = bt; p.primary.cornerRadius = cr; p.primary.cornerMask = cm
                    ns.ERB_CopyBorderPx(p.primary, p.secondary)
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz; p.health.borderTexture = bt; p.health.cornerRadius = cr; p.health.cornerMask = cm
                    ns.ERB_CopyBorderPx(p.health, p.secondary)
                    SmoothRefresh(); EllesmereUI:RefreshPage(ns.ERB_TexturedBars(p) ~= was)
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA, p.secondary.borderSize or 1
                    local sbt, scr, scm = p.secondary.borderTexture or "solid", p.secondary.cornerRadius or 0, p.secondary.cornerMask or 15
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt and (t.cornerRadius or 0) == scr and (t.cornerMask or 15) == scm and ns.ERB_SameBorderPx(t, p.secondary) end
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
    }, { size = 20, disabled = function() local c = cfg(); return (not c) or (not c.enabled) or c.darkTheme end,
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

    -- Resource Text and the Hunter Focus row below touch only the class-resource
    -- (secondary) config. DB() is shadowed in this scope so DB().secondary resolves to
    -- cfg() without rewriting every access path; it returns nil while cfg() does, so the
    -- `if not p` guards short-circuit.
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
    -- Threshold & Hash Lines (row 5 slot 2): the shared editor, given the class resource's own rules
    if not EllesmereUI._prebuilding then
        local settingsRgn = classColorRow._rightRegion
        -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
        EllesmereUI.SpecOverrides_AttachEditLock(settingsRgn,
            "Thresholds have their own per-spec system and can't be edited while editing a spec group")

        -- Vengeance soul fragments and the Prot Ignore Pain bar are SECRET values, so recoloring text cannot work there
        local ES_CEILING_TIP = "Brewmaster Monk Extended Stagger Bar is on: its Scale decides how far the bar fills."
        local TI_BLOCK_TIP = "Not available for this spec: Vengeance soul fragments and the Protection Ignore Pain bar use secret values that can't be read into a text color, so recoloring the text would have no effect."
        local function HasSpec(ent, id)
            local ids = ent and ent.specIDs
            if ids then
                for i = 1, #ids do
                    if ids[i] == id then return true end
                end
            end
            return false
        end

        BuildThresholdSettingsButton({
            parentRgn = settingsRgn,
            getBarData = cfg,
            -- The page appends an "Anchor to Cursor" row after this section, so the editor covers one row more
            pageParent = parent, pageTopY = _advTop, pageBotY = function() return y end, pageBotExtra = 50,
            refreshFn = RefreshClass,
            rebuildFn = RebuildClass,
            swatchRefreshFn = SmoothRefresh,
            disabledFn = classOff,
            disabledTip = "Class Resource",
            defaultR = 0x0c/255, defaultG = 0xd2/255, defaultB = 0x9d/255, defaultA = 1,
            thresholdField = "thresholdCount",
            hashModeDefault = "value",
            hashWidthMax = 4,
            hashValueHint = EllesmereUI.L("(Ex: 25,50,75)"),
            showBuffs = true,
            showSpenders = true,
            -- Brewmaster stagger ceiling: the stagger bar fills to this % of max health (lower = fills
            -- sooner); the color % thresholds still use REAL max health
            barInput = { label = "Stagger Full %", field = "staggerCeilingPercent", min = 1, max = 500, default = 100, letters = 3 },

            -- A count threshold: 30 (%) for bar-type resources, 3 for pips, 7 for the Enhance five-bar style
            newEntry = function(ids, c)
                local isBar = ns.IsSpecBarType(ids[1])
                local enhAdd = false
                if c.enhanceFiveBar then
                    for _, sid in ipairs(ids) do if sid == 263 then enhAdd = true; break end end
                end
                local newEntry = {
                    specIDs = ids,
                    hashValues = "",
                    hashWidth = 1,
                    hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                    thresholdEnabled = true,
                    thresholdCount = enhAdd and 7 or (isBar and 30 or 3),
                    thresholdPartialOnly = false,
                    thresholdR = c.thresholdR or 0x0c/255,
                    thresholdG = c.thresholdG or 0xd2/255,
                    thresholdB = c.thresholdB or 0x9d/255,
                    thresholdA = c.thresholdA or 1,
                }
                -- Default for "Threshold color below value": the only bar-type spender class resource is Hunter
                -- Focus, so it starts ON (warn when low); builders (Maelstrom/Insanity/Astral) start OFF.
                -- Only when the entry covers the current spec (resource readable).
                if isBar then
                    local curIdx = C_SpecializationInfo.GetSpecialization()
                    local curSpecID = curIdx and C_SpecializationInfo.GetSpecializationInfo(curIdx)
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
                return newEntry
            end,

            -- Threshold options cog: per-entry gating mirrors the detail pane so Threshold as / Direction / Only color at-above grey correctly
            thresholdCog = { title = "Threshold Options", minWidth = 320, rows = function(cur, redraw)
                local function isBar() local e = cur(); return (e and ns.IsEntryBarType(e)) and true or false end
                local function isStagger() return HasSpec(cur(), 268) end
                local function isEnhance()
                    local c = cfg()
                    return (c and c.enhanceFiveBar == true and HasSpec(cur(), 263)) and true or false
                end
                local function enabled()
                    local e = cur(); if not e then return false end
                    local v = e.thresholdEnabled
                    if v == nil then v = true end
                    return v
                end
                local function multiOn() local e = cur(); return (e and e.multiBandEnabled and not isEnhance()) and true or false end
                local function usable() return enabled() and not multiOn() end
                local function offTip() if multiOn() then return BAND_REPLACES_TIP end return "Enable the Threshold toggle to use these options." end
                local function isUpTo() local e = cur(); return (e and e.thresholdReverse) and true or false end
                local function isWarrCharge()
                    -- Arms/Fury class-bar thresholds render on the engine-fed
                    -- Whirlwind/Sweeping Strikes charge bar, whose only
                    -- threshold display is range coloring at/above the count
                    -- (no Lua count exists to flip the whole fill).
                    if (select(2, UnitClass("player"))) ~= "WARRIOR" then return false end
                    local e = cur()
                    local ids = e and e.specIDs
                    if not ids then return false end
                    for i = 1, #ids do
                        local id = ids[i]
                        if id == 0 or id == 71 or id == 72 then return true end
                    end
                    return false
                end
                local function changed() RefreshClass(); redraw() end
                return {
                    { type = "segmented", label = "Threshold as",
                        keys = { "percent", "value" }, labels = { percent = "Percent", value = "Value" }, rawTooltip = true,
                        disabled = function() return (not usable()) or (not isBar()) or isStagger() end,
                        disabledTooltip = function()
                            if not usable() then return offTip() end
                            if not isBar() then return "This option applies to bar-type resources only (pips use stack counts)." end
                            return STAGGER_PCT_TIP
                        end,
                        get = function() local e = cur(); return (e and e.thresholdMode) or "percent" end,
                        set = function(v) local e = cur(); if not e then return end e.thresholdMode = v; changed() end },
                    { type = "segmented", label = "Direction",
                        keys = { "upto", "from" }, labels = { upto = "Up to", from = "From" }, rawTooltip = true,
                        disabled = function() return (not usable()) or isWarrCharge() end,
                        disabledTooltip = function()
                            if isWarrCharge() and usable() then return "Whirlwind and Sweeping Strikes thresholds only support the 'From' direction." end
                            return offTip()
                        end,
                        get = function() if isWarrCharge() then return "from" end local e = cur(); return (e and e.thresholdReverse) and "upto" or "from" end,
                        set = function(v) local e = cur(); if not e then return end e.thresholdReverse = (v == "upto"); changed() end },
                    { type = "toggle", label = "Only color at/above threshold", rawTooltip = true,
                        disabled = function() return (not usable()) or isBar() or isUpTo() or isWarrCharge() end,
                        disabledTooltip = function()
                            if isWarrCharge() and usable() then return "Always on for Whirlwind and Sweeping Strikes charges: range coloring at/above the threshold is the only way these bars can display thresholds." end
                            if not usable() then return offTip() end
                            if isBar() then return "This option applies to pip-type resources only." end
                            return "Only available with the 'From' direction -- it highlights the pips at/above the threshold."
                        end,
                        get = function() if isWarrCharge() then return true end local e = cur(); return (e and e.thresholdPartialOnly) and true or false end,
                        set = function(v) local e = cur(); if not e then return end e.thresholdPartialOnly = v; changed() end },
                }
            end },

            -- Per-entry rules, keyed off the SELECTED entry's specs rather than the live spec, so
            -- editing another spec's entry while playing that spec stays unlocked
            entryRules = function(ent, r, c)
                local isBar = ns.IsEntryBarType(ent)
                local isGuardian, isIgnorePain, isVengeance, isStagger, isEnhance
                if ent.specIDs then
                    for _, s in ipairs(ent.specIDs) do
                        -- WoW Forever: the Druid class resource there is combo points, which
                        -- draw the card's hash lines, so the Ironfur bar exception is retail only.
                        -- Retail keeps the row while the card holds hash lines, so lines saved
                        -- on WoW Forever can be cleared.
                        if s == 104 and not EllesmereUI.IS_FOREVER and (ent.hashValues == nil or ent.hashValues == "") then isGuardian = true end
                        if s == 73 then isIgnorePain = true end
                        if s == 581 then isVengeance = true end
                        if s == 268 then isStagger = true end
                        if s == 263 and c.enhanceFiveBar == true then isEnhance = true end
                    end
                end
                -- Brewmaster stagger reads its threshold as a percent only
                if isStagger and ent.thresholdMode == "value" then ent.thresholdMode = "percent" end
                -- Bar-type reads the threshold as % (max 100) or an absolute value (higher cap); pips count stacks
                local isValue = isBar and not isStagger and ent.thresholdMode == "value"
                r.pips = not isBar
                -- The Guardian Ironfur and Prot Ignore Pain bars draw their own hash lines
                r.hideHash = (isGuardian or isIgnorePain) and true or false
                r.thrMin = isEnhance and 7 or 1
                r.thrMax = isStagger and 500 or (isBar and (isValue and 1000 or 100) or 20)
                r.thrDef = isEnhance and 7 or (isBar and 30 or 3)
                r.thrLabel = EllesmereUI.L("Threshold") .. ((isBar and not isValue) and " %" or "")
                if isEnhance then
                    r.thrTip = EllesmereUI.L("Enhance 5 Bar minimum is %d (if you want less just change 5 bar color)"):format(7)
                    r.multiBlock = EllesmereUI.L("Unavailable with Enhancement 5-bar style.")
                end
                r.bandPctCap = isStagger and 500 or nil
                -- "Recolor text instead" no-ops for secret resources (Vengeance soul fragments, Prot Ignore Pain bar)
                if isVengeance or (isIgnorePain and c.protIgnorePainBar) then r.textBlock = EllesmereUI.L(TI_BLOCK_TIP) end
                r.barInput = isStagger
                -- Extended Stagger's Scale owns the ceiling; the stored value returns when it is off
                if isStagger and c.brewExtendedStaggerBar then r.barBlock = EllesmereUI.L(ES_CEILING_TIP) end
            end,
        })
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
    return y, hdr, classEnableRow, classColorRow, unlockJump
end
--- [class resource end]
