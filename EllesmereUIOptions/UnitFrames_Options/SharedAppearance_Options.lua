if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedAppearance_Options.lua
--  Unit Frames options: Display, Portrait, Text Bar and Extras sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
--  EUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end  -- module disabled: no options page

function ns.UFO_BuildDisplaySection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local AttachFrameSourceCog, BuildBarTexDropdown, BuildInactiveNotice, CLASS_FULL_COORDS = env.AttachFrameSourceCog, env.BuildBarTexDropdown, env.BuildInactiveNotice, env.CLASS_FULL_COORDS
    local CLASS_FULL_SPRITE_BASE, GROUP_UNIT_ORDER, PP, PromptReloadIfUnspawned = env.CLASS_FULL_SPRITE_BASE, env.GROUP_UNIT_ORDER, env.PP, env.PromptReloadIfUnspawned
    local ReloadAndUpdate, SHORT_LABELS, UNIT_DB_MAP, UpdatePreview = env.ReloadAndUpdate, env.SHORT_LABELS, env.UNIT_DB_MAP, env.UpdatePreview
    local db, frames, optState, portraitArtValues = env.db, env.frames, env.optState, env.portraitArtValues
    local W, SDB, SGet, SSet = ctx.W, ctx.SDB, ctx.SGet, ctx.SSet
    local SVal = ctx.SVal
    local _, h

    -------------------------------------------------------------------
    --  DISPLAY
    -------------------------------------------------------------------
    local sharedDisplayHeader
    sharedDisplayHeader, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "unitframes")

    -- Wire class theme subnav callbacks (per-unit context)
    do
        local sn = portraitArtValues["class"].subnav
        sn.onSelect = function(styleKey)
            local d = UNIT_DB_MAP[optState.selectedUnit]()
            d.portraitMode = "class"
            d.classThemeStyle = styleKey
            d.showPortrait = true
            -- The Art Style's leave-3D resets: Shape None and the Inside
            -- positions are 3D-only.
            if d.detachedPortraitShape == "none" then d.detachedPortraitShape = "portrait" end
            local side = d.portraitSide
            if side == "insideleft" or side == "insideright" or side == "insidecenter" then
                d.portraitSide = "left"
            end
            ReloadAndUpdate(); UpdatePreview()
            C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for ri = 1, #rl do rl[ri]() end end end)
        end
        sn.icon = function(styleKey)
            local _, classToken = UnitClass("player")
            if not classToken then return nil end
            local coords = CLASS_FULL_COORDS[classToken]
            if not coords then return nil end
            return CLASS_FULL_SPRITE_BASE .. styleKey .. ".tga", coords[1], coords[2], coords[3], coords[4]
        end
    end

    -- Row 1: Visibility | Visibility Options. Group-axis check for the legacy
    -- showInRaid/showInParty/showSolo trio: only group items constrain it
    -- (unconstrained = true), matching ToggleFrame's group gating for multi-select.
    local function GroupAxisPasses(vm, inRaid, inParty)
        -- A checked Hide lane vetoes whatever the Show lanes say, in both match
        -- modes; both lanes of one row at once counts as unconstrained.
        if (vm.hide_in_raid and not vm.in_raid and inRaid)
            or (vm.hide_in_party and not vm.in_party and inParty)
            or (vm.hide_solo and not vm.solo and not inRaid and not inParty) then
            return false
        end
        local g1, g2, g3 = vm.in_raid, vm.in_party, vm.solo
        if not (g1 or g2 or g3) or (g1 and g2 and g3) then return true end
        if g1 and inRaid then return true end
        if g2 and inParty then return true end
        if g3 and not inRaid and not inParty then return true end
        return false
    end
    -- Keeps the boolean trio in sync with the effective selection; the legacy
    -- branch leaves the trio untouched for in_combat/out_of_combat/mouseover.
    local function SyncUnitVisBooleans(s)
        local vm = s.visibilityModes
        if type(vm) == "table" and next(vm) then
            s.showInRaid  = GroupAxisPasses(vm, true, false)
            s.showInParty = GroupAxisPasses(vm, false, true)
            s.showSolo    = GroupAxisPasses(vm, false, false)
            return
        end
        local v = s.barVisibility or "always"
        if v == "always" then
            s.showInRaid = true; s.showInParty = true; s.showSolo = true
        elseif v == "never" then
            s.showInRaid = false; s.showInParty = false; s.showSolo = false
        elseif v == "in_raid" then
            s.showInRaid = true; s.showInParty = false; s.showSolo = false
        elseif v == "in_party" then
            s.showInRaid = false; s.showInParty = true; s.showSolo = false
        elseif v == "solo" then
            s.showInRaid = false; s.showInParty = false; s.showSolo = true
        end
    end
    local visRow
    visRow, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = function() return UNIT_DB_MAP[optState.selectedUnit]() end,
          legacyKey = "barVisibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true },
          refreshPageArg = true,
          -- Visibility is a RUNTIME axis and never touches enabledFrames: that
          -- key decides whether the frame is built at all, once, at login, so a
          -- Spec Override carrying "never" used to leave the frame uncreated for
          -- the session with no way back but a /reload. "never" is hidden by the
          -- visibility pass instead (ns.UpdateFrameVisibility), which reverses.
          applyScalarFn = function(s, mode)
              s.barVisibility = mode
          end,
          onChanged = function()
              local s = UNIT_DB_MAP[optState.selectedUnit]()
              SyncUnitVisBooleans(s)
              if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
              ReloadAndUpdate()
              -- Un-hiding a frame whose EUI frame isn't spawned this session
              -- (source was Blizzard/Hidden at login) needs a /reload. The EFFECTIVE
              -- value decides: an override replaces the shared scalar, so an override
              -- of Always on a unit whose shared value is "never" un-hides it too.
              local visOv = EllesmereUI.VisOverrideValue(s)
              if (visOv or s.barVisibility or "always") ~= "never" then PromptReloadIfUnspawned({ optState.selectedUnit }) end
          end,
          onOptionChanged = function()
              if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
          end },
        -- Show Nicknames moved up from the section's old trailing half-row into the
        -- slot the Visibility Options dropdown left behind, so neither row is half
        -- empty. ONE global toggle for all main frames (default OFF, not per-unit,
        -- hence db.profile). Gates ns.ResolveUnitNickname: off = raw names, on =
        -- provider nicknames.
        { type="toggle", text="Show Nicknames",
          tooltip="Show player nicknames from supported addons instead of character names on your main frames.",
          getValue=function() return db.profile.showNicknames or false end,
          setValue=function(v)
              db.profile.showNicknames = v
              if ns.RefreshAllUnitNames then ns.RefreshAllUnitNames() end
          end });  y = y - h

    -- Inline cog on Visibility: ONE popup hosting Frame Source (EllesmereUI /
    -- Blizzard Default) plus Out of Combat fade. Hiding stays on the Visibility
    -- dropdown ("Never Show"). Fade dims the frame via ns.ResolveFrameAlpha in
    -- UpdateFrameVisibility (reacts to the regen path); reuses CDM fade strings
    -- for consistency. Fade rows appear only for the EllesmereUI source.
    local _visSrcIsEui = ns.GetUnitFrameSource(optState.selectedUnit) == "eui"
    if not EllesmereUI._prebuilding then
    AttachFrameSourceCog(visRow._leftRegion, optState.selectedUnit, {
        title = _visSrcIsEui and "Frame Source & Visibility" or "Frame Source",
        cogTooltip = _visSrcIsEui and "Frame Source & Visibility" or "Frame Source",
        extraRows = _visSrcIsEui and {
            { type = "toggle", label = "Show When Health Missing",
              tooltip = "Shows the frame while this unit is below full health; while enabled, a frame hidden by its visibility setting can still be clicked.",
              disabled = function() return InCombatLockdown() end,
              disabledTooltip = "Change health visibility out of combat",
              get = function() return SVal("showWhenHealthMissing", false) == true end,
              set = function(v)
                  SSet("showWhenHealthMissing", v)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
              end },
            { type = "toggle", label = "Fade Out of Combat",
              tooltip = "Fades the entire frame (portrait, health and power bars, text) while out of combat.",
              get = function() return SVal("oocFadeEnabled", false) == true end,
              set = function(v)
                  SSet("oocFadeEnabled", v)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
              end },
            { type = "slider", label = "Out of Combat Alpha", min = 0, max = 100, step = 1,
              disabled = function() return not SVal("oocFadeEnabled", false) end,
              disabledTooltip = "Enable Fade Out of Combat first",
              get = function() return math.floor((SVal("oocAlpha", 0.5)) * 100 + 0.5) end,
              set = function(v)
                  SSet("oocAlpha", v / 100)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
              end },
        },
    })
    end

    -- Non-EUI source: no EUI frame spawned, so nothing below applies. Keep the
    -- Visibility row (hosts the Frame Source cog + "Never Show" way back), grey
    -- it for Blizzard source, and show a one-line notice in place of settings.
    if not EllesmereUI._prebuilding then
        local srcNow = ns.GetUnitFrameSource(optState.selectedUnit)
        if srcNow ~= "eui" then
            -- The right slot used to hold this unit's Visibility Options and was hidden
            -- here because it is meaningless for a Blizzard frame. It now holds the
            -- profile-wide Show Nicknames toggle, which stays live for every source.
            if srcNow == "blizzard" then
                -- Visibility modes only drive the EUI frame: block the dropdown
                -- (the cog stays live to switch back).
                local ctl = visRow._leftRegion._control
                if visRow._leftRegion._label then visRow._leftRegion._label:SetAlpha(0.3) end
                local dis = CreateFrame("Frame", nil, visRow)
                dis:SetPoint("TOPLEFT", ctl, "TOPLEFT", -2, 2)
                dis:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", 2, -2)
                dis:SetFrameLevel(visRow:GetFrameLevel() + 10)
                dis:EnableMouse(true)
                local disTex = dis:CreateTexture(nil, "OVERLAY")
                disTex:SetAllPoints()
                disTex:SetColorTexture(0.077, 0.068, 0.058, 0.7)
                dis:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("the Frame Source to be EllesmereUI"))
                end)
                dis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            return BuildInactiveNotice(parent, y, srcNow), true
        end
    end

    -- ONE sync icon now that both halves share a control: set-aware for correct
    -- multi-selection compare/copy, and VisFullCopy carries the option booleans too,
    -- plus each target's boolean-trio derivation.
    if not EllesmereUI._prebuilding then
        local rgn = visRow._leftRegion
        local function CopyVisToUnit(key)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local dst = UNIT_DB_MAP[key]()
            if dst == src then return end
            EllesmereUI.VisFullCopy(dst, src, "barVisibility", nil, function(t, mode)
                t.barVisibility = mode
            end)
            SyncUnitVisBooleans(dst)
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Visibility to all Frames",
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if not EllesmereUI.VisFullEquals(src, "barVisibility", UNIT_DB_MAP[key](), "barVisibility") then return false end
                end
                return true
            end,
            onClick = function()
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    CopyVisToUnit(key)
                end
                if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                ReloadAndUpdate(); EllesmereUI:RefreshPage(true)
                local v = UNIT_DB_MAP[optState.selectedUnit]().barVisibility or "always"
                if v ~= "never" then PromptReloadIfUnspawned(GROUP_UNIT_ORDER) end
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do
                        CopyVisToUnit(key)
                    end
                    if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage(true)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().barVisibility or "always"
                    if v ~= "never" then PromptReloadIfUnspawned(checkedKeys) end
                end,
            },
        })
    end

    -- Row 2: Bar Texture (per-unit + sync) | Dark Mode. healthBarTexture is
    -- per-unit (drives health/power/cast/absorb); db.profile.healthBarTexture is the fallback when unset.
    local barTexRow
    local hbtValues, hbtOrder = BuildBarTexDropdown()
    barTexRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
              getValue=function() return SVal("healthBarTexture", db.profile.healthBarTexture or "none") end,
              setValue=function(v)
                  SSet("healthBarTexture", v)
                  UpdatePreview(); EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Dark Mode",
              getValue=function() return db.profile.darkTheme end,
              setValue=function(v)
                  db.profile.darkTheme = v
                  ReloadAndUpdate(); UpdatePreview()
                  -- Dark Mode feeds the conditional-override condition.
                  EllesmereUI.Conditions_Recheck()
                  EllesmereUI:RefreshPage()
              end });  y = y - h
    -- This toggle IS the Dark Mode condition's input: lock it while a Dark Mode
    -- conditional is edited, or the override could capture a value flipping its own condition.
    if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
        EllesmereUI.SpecOverrides_AttachEditLock(barTexRow._rightRegion,
            "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
            EllesmereUI.SpecOverrides_DarkCondEditActive)
    end
    -- Sync icon: Bar Texture (left region) -- pushes this unit's texture to frames
    if not EllesmereUI._prebuilding then
        local rgn = barTexRow._leftRegion
        local function ApplyTexTo(keys)
            local src = UNIT_DB_MAP[optState.selectedUnit]()
            local tex = src.healthBarTexture or db.profile.healthBarTexture or "none"
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    UNIT_DB_MAP[key]().healthBarTexture = tex
                end
            end
            ReloadAndUpdate(); UpdatePreview(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Texture to all Frames",
            onClick = function() ApplyTexTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local g = db.profile.healthBarTexture or "none"
                local srcTex = UNIT_DB_MAP[optState.selectedUnit]().healthBarTexture or g
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().healthBarTexture or g) ~= srcTex then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyTexTo(checkedKeys) end,
            },
        })
    end

    -- Row 3: Border Style (+ cog) | Border (slider + double inline swatches)
    local sharedScaleBorderRow
    local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
    sharedScaleBorderRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Border Style",
          values=texValues, order=texOrder,
          getValue=function() return SGet("borderTexture") or "solid" end,
          setValue=function(v)
              SSet("borderTexture", v)
              SSet("borderTextureOffset", nil)
              SSet("borderTextureOffsetY", nil)
              SSet("borderTextureShiftX", nil)
              SSet("borderTextureShiftY", nil)
              local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
              SSet("borderColor", _bcol)
              SSet("borderAlpha", 1)
              SSet("borderBehind", _bbehind)
              local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
              if defSz then SSet("borderSize", defSz) end
              -- A style pick returns the frame to its legacy step; clear a set
              -- exact size (false travels through mirror sync, nil would not).
              if SGet("borderSizePx") then SDB().borderSizePx = false end
              ReloadAndUpdate()
              -- The Width / Height Offset row exists only under a textured style.
              EllesmereUI:RefreshPage(true)
          end }),
        EllesmereUI.BlizzStyle.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size", trackWidth=120,
          getStep=function() return SVal("borderSize", 1) end,
          setStep=function(step) SDB().borderSize = step end,
          getTex=function() return SGet("borderTexture") or "solid" end,
          getPx=function() return SGet("borderSizePx") end,
          setPx=function(v) SDB().borderSizePx = v end,
          apply=ReloadAndUpdate })));  y = y - h
    -- Width Offset | Height Offset: a textured style's outward offsets (a Solid
    -- border has none). The row shows what is drawn: the stored override, else
    -- the texture's default for this size, which keeps seeding until a real edit.
    do
        local bTex = SGet("borderTexture") or "solid"
        if bTex ~= "solid" and bTex ~= "" then
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function() return SGet("borderTexture") or "solid" end,
                getStep = function() return SVal("borderSize", 1) end,
                getSizeKey = function() return SVal("borderSize", 1) end,
                getPx = function() return SGet("borderSizePx") end,
                getX = function() return SGet("borderTextureOffset") end,
                setX = function(v) SDB().borderTextureOffset = v end,
                getY = function() return SGet("borderTextureOffsetY") end,
                setY = function(v) SDB().borderTextureOffsetY = v end,
                apply = ReloadAndUpdate,
            })
            _, h = W:DualRow(parent, y,
                EllesmereUI.BlizzStyle.Gate("unitframes", ocfgL),
                EllesmereUI.BlizzStyle.Gate("unitframes", ocfgR));  y = y - h
        end
    end
    -- Inline cog for border shift / layering (left region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedScaleBorderRow._leftRegion
        local cogBtn = EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Border Options",
            rows = {
                { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                  get = function()
                      local v = SGet("borderTextureShiftX")
                      if v then return v end
                      local tex = SGet("borderTexture") or "solid"
                      local sz = SVal("borderSize", 1)
                      local _, _, dsx = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                      return dsx
                  end,
                  set = function(v)
                      SSet("borderTextureShiftX", v == 0 and nil or v); ReloadAndUpdate()
                  end },
                { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                  get = function()
                      local v = SGet("borderTextureShiftY")
                      if v then return v end
                      local tex = SGet("borderTexture") or "solid"
                      local sz = SVal("borderSize", 1)
                      local _, _, _, dsy = EllesmereUI.GetBorderDefaults("unitframes", tex, sz)
                      return dsy
                  end,
                  set = function(v)
                      SSet("borderTextureShiftY", v == 0 and nil or v); ReloadAndUpdate()
                  end },
                { type = "toggle", label = "Show Behind",
                  get = function() return SVal("borderBehind", false) end,
                  set = function(v) SSet("borderBehind", v); ReloadAndUpdate(); EllesmereUI:RefreshPage() end },
                -- The style's separator art along the health / power join
                -- (ns.UpdatePowerSeam); only a style with seam art has one.
                { type = "toggle", label = "Power Bar Seam",
                  tooltip = "Draws the border style's seam art between the health bar and an attached power bar.",
                  disabled = function()
                      local pos = SVal("powerPosition", "below")
                      return not (EllesmereUI.GetBorderCompanion(SGet("borderTexture") or "solid", "sepH")
                          and SVal("borderSize", 1) > 0 and (pos == "above" or pos == "below")
                          and SVal("powerHeight", 6) > 0)
                  end,
                  disabledTooltip = "This option requires an attached Power Bar, a Border Size above 0 and a border style with seam art.",
                  rawTooltip = true,
                  get = function() return SVal("borderPowerSeam", false) == true end,
                  set = function(v) SSet("borderPowerSeam", v) end },
            },
        })
        local function UpdateCogVis()
            local tex = SGet("borderTexture") or "solid"
            if tex == "solid" or EllesmereUI.BlizzStyle.Get("unitframes") then cogBtn:Hide() else cogBtn:Show() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end
    -- Sync icon: Border Style (left region - dropdown)
    if not EllesmereUI._prebuilding then
        local bsLeftRgn = sharedScaleBorderRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = bsLeftRgn,
            tooltip = "Apply Border Style to all Frames",
            onClick = function()
                local bt = SGet("borderTexture") or "solid"
                local ox = SGet("borderTextureOffset")
                local oy = SGet("borderTextureOffsetY")
                local sx = SGet("borderTextureShiftX")
                local sy = SGet("borderTextureShiftY")
                local bh = SGet("borderBehind")
                local bc = SGet("borderColor")
                local ba = SGet("borderAlpha")
                local ps = SGet("borderPowerSeam")
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then
                        UNIT_DB_MAP[key]().borderTexture = bt
                        UNIT_DB_MAP[key]().borderTextureOffset = ox
                        UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                        UNIT_DB_MAP[key]().borderTextureShiftX = sx
                        UNIT_DB_MAP[key]().borderTextureShiftY = sy
                        UNIT_DB_MAP[key]().borderBehind = bh
                        if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                        UNIT_DB_MAP[key]().borderAlpha = ba
                        UNIT_DB_MAP[key]().borderPowerSeam = ps
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local bt = SGet("borderTexture") or "solid"
                local ox = SGet("borderTextureOffset")
                local oy = SGet("borderTextureOffsetY")
                local sx = SGet("borderTextureShiftX")
                local sy = SGet("borderTextureShiftY")
                local bh = SGet("borderBehind") or false
                local ps = SGet("borderPowerSeam") == true
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().borderTexture or "solid") ~= bt then return false end
                    if UNIT_DB_MAP[key]().borderTextureOffset ~= ox then return false end
                    if UNIT_DB_MAP[key]().borderTextureOffsetY ~= oy then return false end
                    if UNIT_DB_MAP[key]().borderTextureShiftX ~= sx then return false end
                    if UNIT_DB_MAP[key]().borderTextureShiftY ~= sy then return false end
                    if (UNIT_DB_MAP[key]().borderBehind or false) ~= bh then return false end
                    if (UNIT_DB_MAP[key]().borderPowerSeam == true) ~= ps then return false end
                end
                return true
            end,
            flashTargets = function() return { bsLeftRgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local bt = SGet("borderTexture") or "solid"
                    local ox = SGet("borderTextureOffset")
                    local oy = SGet("borderTextureOffsetY")
                    local sx = SGet("borderTextureShiftX")
                    local sy = SGet("borderTextureShiftY")
                    local bh = SGet("borderBehind")
                    local bc = SGet("borderColor")
                    local ba = SGet("borderAlpha")
                    local ps = SGet("borderPowerSeam")
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().borderTexture = bt
                        UNIT_DB_MAP[key]().borderTextureOffset = ox
                        UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                        UNIT_DB_MAP[key]().borderTextureShiftX = sx
                        UNIT_DB_MAP[key]().borderTextureShiftY = sy
                        UNIT_DB_MAP[key]().borderBehind = bh
                        if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                        UNIT_DB_MAP[key]().borderAlpha = ba
                        UNIT_DB_MAP[key]().borderPowerSeam = ps
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Sync icon: Border (right region - border slider)
    if not EllesmereUI._prebuilding then
        local rgn = sharedScaleBorderRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Border to all Frames",
            onClick = function()
                local bs = SVal("borderSize", 1)
                local bpx = SGet("borderSizePx")
                local bc = SGet("borderColor")
                local ba = SGet("borderAlpha")
                local bt = SGet("borderTexture") or "solid"
                local hc = SGet("highlightColor")
                local ha = SGet("highlightAlpha")
                local ox = SGet("borderTextureOffset")
                local oy = SGet("borderTextureOffsetY")
                local sx = SGet("borderTextureShiftX")
                local sy = SGet("borderTextureShiftY")
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then
                        UNIT_DB_MAP[key]().borderSize = bs
                        -- Verbatim (string / false / nil): the value only counts beside the same step and texture.
                        do
                            -- A source with no exact size clears a set one with
                            -- false (nil would not travel through mirror sync).
                            local t = UNIT_DB_MAP[key]()
                            local v = bpx
                            if v == nil and t.borderSizePx ~= nil then v = false end
                            t.borderSizePx = v
                        end
                        if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                        if ba then UNIT_DB_MAP[key]().borderAlpha = ba end
                        UNIT_DB_MAP[key]().borderTexture = bt
                        UNIT_DB_MAP[key]().borderTextureOffset = ox
                        UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                        UNIT_DB_MAP[key]().borderTextureShiftX = sx
                        UNIT_DB_MAP[key]().borderTextureShiftY = sy
                        if hc then UNIT_DB_MAP[key]().highlightColor = { r=hc.r, g=hc.g, b=hc.b } end
                        if ha then UNIT_DB_MAP[key]().highlightAlpha = ha end
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local bs = SVal("borderSize", 1)
                local bt = SGet("borderTexture") or "solid"
                -- Exact sizes compare as rendered (a cleared or stale value equals none).
                local bpx = EllesmereUI.BorderPx(SGet("borderSizePx"), bs, bt)
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().borderSize or 1) ~= bs then return false end
                    if (UNIT_DB_MAP[key]().borderTexture or "solid") ~= bt then return false end
                    if EllesmereUI.BorderPx(UNIT_DB_MAP[key]().borderSizePx, bs, bt) ~= bpx then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local bs = SVal("borderSize", 1)
                    local bpx = SGet("borderSizePx")
                    local bc = SGet("borderColor")
                    local ba = SGet("borderAlpha")
                    local bt = SGet("borderTexture") or "solid"
                    local hc = SGet("highlightColor")
                    local ha = SGet("highlightAlpha")
                    local ox = SGet("borderTextureOffset")
                    local oy = SGet("borderTextureOffsetY")
                    local sx = SGet("borderTextureShiftX")
                    local sy = SGet("borderTextureShiftY")
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().borderSize = bs
                        do
                            -- A source with no exact size clears a set one with
                            -- false (nil would not travel through mirror sync).
                            local t = UNIT_DB_MAP[key]()
                            local v = bpx
                            if v == nil and t.borderSizePx ~= nil then v = false end
                            t.borderSizePx = v
                        end
                        if bc then UNIT_DB_MAP[key]().borderColor = { r=bc.r, g=bc.g, b=bc.b } end
                        if ba then UNIT_DB_MAP[key]().borderAlpha = ba end
                        UNIT_DB_MAP[key]().borderTexture = bt
                        UNIT_DB_MAP[key]().borderTextureOffset = ox
                        UNIT_DB_MAP[key]().borderTextureOffsetY = oy
                        UNIT_DB_MAP[key]().borderTextureShiftX = sx
                        UNIT_DB_MAP[key]().borderTextureShiftY = sy
                        if hc then UNIT_DB_MAP[key]().highlightColor = { r=hc.r, g=hc.g, b=hc.b } end
                        if ha then UNIT_DB_MAP[key]().highlightAlpha = ha end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Inline Border color swatch; Highlight lives on "Hover Borders" below
    -- (same highlightColor var).
    if not EllesmereUI._prebuilding then
        local leftRgn = sharedScaleBorderRow._rightRegion
        local ctrl = leftRgn._control
        local PP = EllesmereUI.PP

        -- Border color (with alpha)
        local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
            leftRgn, sharedScaleBorderRow:GetFrameLevel() + 3,
            function()
                local c = SGet("borderColor") or { r = 0, g = 0, b = 0 }
                return c.r, c.g, c.b, SVal("borderAlpha", 1)
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().borderColor = { r=r, g=g, b=b }
                UNIT_DB_MAP[optState.selectedUnit]().borderAlpha = a
                ReloadAndUpdate()
            end,
            true, 20)
        PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        borderSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(borderSwatch, "Border")
        end)
        borderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
    end

    -- Row 4: Show Tooltip For (checkbox-dropdown) | Frame Strata. "Show Tooltip
    -- For" is a pure VIEW over per-unit showUnitTooltip/showAuraTooltips (zero
    -- migration); both setters write EVERY unit key, including boss.
    local ufStrataValues = EllesmereUI.FRAME_STRATA_LABELS
    local ufStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
    local tipStrataRow
    tipStrataRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Show Tooltip For",
          tooltip="Choose which tooltips appear on hover. Affects all unit frames, including boss frames.",
          values={ ["_placeholder"]="..." }, order={ "_placeholder" },
          getValue=function() return "_placeholder" end,
          setValue=function() end },
        { type="dropdown", text="Frame Strata",
          tooltip="Controls the order that overlapping elements display in. Set higher to show above other elements.",
          values = ufStrataValues, order = ufStrataOrder,
          getValue=function() return SGet("frameStrata") or db.profile.frameStrata or "MEDIUM" end,
          setValue=function(v) SSet("frameStrata", v) end });  y = y - h

    -- Show Tooltip For checkbox-dropdown (left region)
    if not EllesmereUI._prebuilding then
        local rgn = tipStrataRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local tipItems = {
            { key = "unit",  label = "Unit Frame",
              tooltip = "Show the unit's tooltip when hovering the frame itself." },
            { key = "auras", label = "Main Frames Auras",
              tooltip = "Show aura tooltips when hovering buff and debuff icons on all unit frames except boss frames." },
            { key = "bossauras", label = "Boss Frames Auras",
              tooltip = "Show aura tooltips when hovering buff and debuff icons on boss frames." },
        }
        -- Both aura items view the same per-unit showAuraTooltips key the runtime
        -- reads per element; they differ only in which units the setter fans to.
        local ALL_UNITS  = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
        local MAIN_UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet" }
        local PP = EllesmereUI.PP
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 210, rgn:GetFrameLevel() + 2,
            tipItems,
            function(k)
                if k == "unit" then return SVal("showUnitTooltip", true) end
                if k == "auras" then return SVal("showAuraTooltips", true) end
                if k == "bossauras" then
                    return UNIT_DB_MAP["boss"]().showAuraTooltips ~= false
                end
                return false
            end,
            function(k, v)
                if k == "unit" then
                    for _, key in ipairs(ALL_UNITS) do
                        UNIT_DB_MAP[key]().showUnitTooltip = v
                    end
                elseif k == "auras" then
                    for _, key in ipairs(MAIN_UNITS) do
                        UNIT_DB_MAP[key]().showAuraTooltips = v
                    end
                elseif k == "bossauras" then
                    UNIT_DB_MAP["boss"]().showAuraTooltips = v
                else
                    return
                end
                ReloadAndUpdate()
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Cog on Frame Strata: custom bar stratas for detached power/text bar
    if not EllesmereUI._prebuilding then
        local strataRgn = tipStrataRow
        if strataRgn and strataRgn._rightRegion then strataRgn = strataRgn._rightRegion end
        local barStrataValues = EllesmereUI.FRAME_STRATA_LABELS
        local barStrataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
        if strataRgn then EllesmereUI.BuildInlineCog(strataRgn, {
            title = "Detached Bar Stratas",
            rows = {
                { type="toggle", label="Custom Bar Stratas",
                  get=function() return db.profile.enableCustomBarStratas or false end,
                  set=function(v) db.profile.enableCustomBarStratas = v; ReloadAndUpdate() end },
                { type="dropdown", label="Detached Power Bar", values=barStrataValues, order=barStrataOrder,
                  get=function() return db.profile.detachedPowerStrata or "HIGH" end,
                  set=function(v) db.profile.detachedPowerStrata = v; ReloadAndUpdate() end },
                { type="dropdown", label="Detached Text Bar", values=barStrataValues, order=barStrataOrder,
                  get=function() return db.profile.detachedTextBarStrata or "DIALOG" end,
                  set=function(v) db.profile.detachedTextBarStrata = v; ReloadAndUpdate() end },
            },
        }) end
    end

    -- Sync icon: Frame Strata (right region) -- pushes this unit's strata to
    -- the other main frames. Each frame keeps its own value; unset frames
    -- fall back to the profile-wide default.
    if not EllesmereUI._prebuilding then
        local rgn = tipStrataRow._rightRegion
        local function CurStrata(key)
            return UNIT_DB_MAP[key]().frameStrata or db.profile.frameStrata or "MEDIUM"
        end
        local function ApplyStrataTo(keys)
            local strata = CurStrata(optState.selectedUnit)
            for _, key in ipairs(keys) do
                if key ~= optState.selectedUnit then
                    UNIT_DB_MAP[key]().frameStrata = strata
                end
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Frame Strata to all Frames",
            onClick = function() ApplyStrataTo(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local cur = CurStrata(optState.selectedUnit)
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if CurStrata(key) ~= cur then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys) ApplyStrataTo(checkedKeys) end,
            },
        })
    end

    -- Show Decimal on Health Text (global): one decimal on health value (240.5k)
    -- and health percent (77.3%) for every unit. Default off.
    local decRow
    decRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Decimal on Health Text",
          tooltip="Show one decimal place on health text: health values like 240.5k and health percent like 77.3%. Power text is unaffected. Off by default.",
          getValue=function() return db.profile.showDecimalOnText end,
          setValue=function(v)
              db.profile.showDecimalOnText = v
              if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
              ReloadAndUpdate(); UpdatePreview()
              EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Hover Borders",
          values={ __placeholder = "All" }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end });  y = y - h
    -- Dimmed "(Applies to All Units)" subtitle next to the label (CDM subtitle pattern).
    do
        local suffix = decRow._leftRegion:CreateFontString(nil, "OVERLAY")
        suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
        suffix:SetTextColor(1, 1, 1, 0.35)
        suffix:SetText(EllesmereUI.L("(Applies to All Units)"))
        local lbl
        local regions = { decRow._leftRegion:GetRegions() }
        for i = 1, #regions do
            local reg = regions[i]
            if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Show Decimal on Health Text" then
                lbl = reg; break
            end
        end
        if lbl then
            suffix:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
        else
            suffix:SetPoint("LEFT", decRow._leftRegion, "LEFT", 120, 0)
        end
    end

    -- Inline cog: extra decimal options. "Show 2 for Boss" (default on) gives boss
    -- frames a second decimal. Greyed out while the master decimal toggle is off.
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(decRow._leftRegion, {
            disabled = function() return not db.profile.showDecimalOnText end,
            disabledTooltip = "Show Decimal on Health Text",
            title = "Health Text Decimals",
            rows = {
                { type="toggle", label="Only Show for % Health",
                  get=function() return db.profile.showDecimalPercentOnly == true end,
                  set=function(v)
                      db.profile.showDecimalPercentOnly = v
                      if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type="toggle", label="Show 2 for Boss",
                  get=function() return db.profile.showDecimalBoss2 ~= false end,
                  set=function(v)
                      db.profile.showDecimalBoss2 = v
                      if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
                { type="toggle", label="Hide Trailing Zeros",
                  get=function() return db.profile.showDecimalTrimZeros == true end,
                  set=function(v)
                      db.profile.showDecimalTrimZeros = v
                      if ns.ApplyTextDecimalGlobals then ns.ApplyTextDecimalGlobals() end
                      ReloadAndUpdate(); UpdatePreview()
                  end },
            },
        })
    end

    -- Hover Borders dropdown (mirrors Raid Frames): Highlight (per-unit hover
    -- border) + Player Threat (player frame only, global). Inline swatches:
    -- Highlight / Has Aggro / Close to Aggro.
    if not EllesmereUI._prebuilding then
        local rightRgn = decRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local isPlayer = (optState.selectedUnit == "player")
        local hbItems = { { key = "highlight", label = "Highlight" } }
        if isPlayer then
            hbItems[#hbItems + 1] = {
                key = "playerThreat",
                label = "Player Threat (Non-Tank)",
                tooltip = "Adds a Shadow border to your player frame when you pull or hold threat as a non-tank. Only active in dungeons, raids and delves.",
            }
        end
        local UpdateHBSwatchVis  -- forward declare; assigned after swatches
        local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 170, rightRgn:GetFrameLevel() + 2,
            hbItems,
            function(k)
                -- Highlight is shared across all 3 main frames; read the player copy.
                if k == "highlight" then return UNIT_DB_MAP.player().highlightEnabled ~= false end
                if k == "playerThreat" then return db.profile.playerThreatBorderEnabled or false end
                return false
            end,
            function(k, v)
                if k == "highlight" then
                    -- Shared across all 3 main frames; threat stays player-only below.
                    for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().highlightEnabled = v end
                    ReloadAndUpdate()
                elseif k == "playerThreat" then
                    db.profile.playerThreatBorderEnabled = v
                    if ns.SetPlayerThreatEnabled then ns.SetPlayerThreatEnabled(v) end
                end
                if UpdateHBSwatchVis then UpdateHBSwatchVis() end
            end)
        PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil

        local lvl = decRow:GetFrameLevel() + 3
        -- Highlight swatch (per-unit), nearest the dropdown.
        local hlSwatch, updHl = EllesmereUI.BuildColorSwatch(
            rightRgn, lvl,
            function()
                local c = UNIT_DB_MAP.player().highlightColor or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b, UNIT_DB_MAP.player().highlightAlpha or 1
            end,
            function(r, g, b, a)
                -- Shared across all 3 main frames (see Highlight enable above).
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    d.highlightColor = { r=r, g=g, b=b }
                    d.highlightAlpha = a
                end
                ReloadAndUpdate()
            end, true, 20)
        hlSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hlSwatch
        hlSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hlSwatch, "Highlight") end)
        hlSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        local hasSwatch, updHas, nearSwatch, updNear
        if isPlayer then
            -- Has Aggro swatch (global), left of Highlight.
            hasSwatch, updHas = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = db.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    db.profile.playerThreatHasAggroColor = { r=r, g=g, b=b }
                    if ns.UpdatePlayerThreatBorder then ns.UpdatePlayerThreatBorder() end
                end, false, 20)
            hasSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = hasSwatch
            hasSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hasSwatch, "Has Aggro") end)
            hasSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Close to Aggro swatch (global), left of Has Aggro.
            nearSwatch, updNear = EllesmereUI.BuildColorSwatch(
                rightRgn, lvl,
                function()
                    local c = db.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 }
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    db.profile.playerThreatNearAggroColor = { r=r, g=g, b=b }
                    if ns.UpdatePlayerThreatBorder then ns.UpdatePlayerThreatBorder() end
                end, false, 20)
            nearSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = nearSwatch
            nearSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(nearSwatch, "Close to Aggro") end)
            nearSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end

        -- Gray a swatch when its toggle is off (still clickable to pre-set).
        UpdateHBSwatchVis = function()
            hlSwatch:SetAlpha(UNIT_DB_MAP.player().highlightEnabled ~= false and 1 or 0.3)
            if hasSwatch then
                local on = db.profile.playerThreatBorderEnabled
                hasSwatch:SetAlpha(on and 1 or 0.3)
                nearSwatch:SetAlpha(on and 1 or 0.3)
            end
        end
        EllesmereUI.RegisterWidgetRefresh(function()
            updHl(); if updHas then updHas() end; if updNear then updNear() end; UpdateHBSwatchVis()
        end)
        UpdateHBSwatchVis()
    end

    -- Threat % text (WoW Forever only): one profile-wide setting for both
    -- frames, drawn on the EllesmereUI frames only. Built before the
    -- half-empty Blizz header row so its blank stays the last slot.
    if EllesmereUI.IS_FOREVER and (optState.selectedUnit == "target" or optState.selectedUnit == "focus") then
        local NO_FRAMES = "This option requires an EllesmereUI Target or Focus frame."
        local function noFrames() return not (frames.target or frames.focus) end
        local function pctOff() return noFrames() or not db.profile.threatPctEnabled end
        local function pctOffTip()
            if noFrames() then return NO_FRAMES end
            return "Show Threat % on Target"
        end
        local function PctSet(key, v)
            db.profile[key] = v
            ns.RefreshThreatPct()
        end
        local function PctSlider(key, label, lo, hi)
            return { type="slider", label=label, min=lo, max=hi, step=1,
              get=function() return db.profile[key] end,
              set=function(v) PctSet(key, v) end }
        end
        local pctRow
        pctRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Threat % on Target",
              tooltip="Shows your threat percentage on the target frame while you are in combat with it. The cog adds the focus frame.",
              disabled=function() return noFrames() and not db.profile.threatPctEnabled end,
              disabledTooltip=NO_FRAMES,
              getValue=function() return db.profile.threatPctEnabled end,
              setValue=function(v)
                  db.profile.threatPctEnabled = v
                  ns.SetThreatPctEnabled(v)
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Threat % Position",
              values=ns._threatPctPositions, order=ns._threatPctPositionOrder,
              disabled=pctOff, disabledTooltip=pctOffTip,
              getValue=function() return db.profile.threatPctPosition end,
              setValue=function(v) PctSet("threatPctPosition", v) end });  y = y - h
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(pctRow._leftRegion, {
                title = "Threat % Units",
                disabled = pctOff,
                disabledTooltip = pctOffTip,
                rows = {
                    { type="toggle", label="Show on Focus",
                      get=function() return db.profile.threatPctFocus end,
                      set=function(v) PctSet("threatPctFocus", v) end },
                },
            })
            EllesmereUI.BuildInlineCog(pctRow._rightRegion, {
                title = "Threat %",
                disabled = pctOff,
                disabledTooltip = pctOffTip,
                rows = {
                    { type="toggle", label="Color by Threat",
                      tooltip="Colors the number by threat status. Off shows it in white.",
                      get=function() return db.profile.threatPctColorByThreat end,
                      set=function(v) PctSet("threatPctColorByThreat", v) end },
                    PctSlider("threatPctSize", "Size", 6, 20),
                    PctSlider("threatPctXOffset", "X Offset", -100, 100),
                    PctSlider("threatPctYOffset", "Y Offset", -100, 100),
                },
            })
        end
    end

    -- Blizzard Style, target frame: the coloured strip behind the name,
    -- or an uncoloured header matching the player frame.
    if optState.selectedUnit == "target" and EllesmereUI.BlizzStyle.Active("unitframes") == "blizzard" then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Blizz Colored Target Header",
              tooltip="Colors the strip behind the target's name by its reaction.",
              getValue=function() return UNIT_DB_MAP.target().blizzColoredHeader ~= false end,
              setValue=function(v)
                  if v then
                      UNIT_DB_MAP.target().blizzColoredHeader = nil
                  else
                      UNIT_DB_MAP.target().blizzColoredHeader = false
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end },
            { type="label", text="" });  y = y - h
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y
end

function ns.UFO_BuildPortraitSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, ReloadAndUpdate, SHORT_LABELS, UNIT_DB_MAP = env.GROUP_UNIT_ORDER, env.ReloadAndUpdate, env.SHORT_LABELS, env.UNIT_DB_MAP
    local UpdatePreview, db, detPortraitShapeOrder, detPortraitShapeValues = env.UpdatePreview, env.db, env.detPortraitShapeOrder, env.detPortraitShapeValues
    local optState, portraitArtOrder, portraitArtValues, portraitModeOrder2 = env.optState, env.portraitArtOrder, env.portraitArtValues, env.portraitModeOrder2
    local portraitModeValues2, portraitNonPlayerOrder, portraitNonPlayerValues = env.portraitModeValues2, env.portraitNonPlayerOrder, env.portraitNonPlayerValues
    local W, SDB, SGet, SSet = ctx.W, ctx.SDB, ctx.SGet, ctx.SSet
    local SVal = ctx.SVal
    local _, h

    -------------------------------------------------------------------
    --  PORTRAIT
    -------------------------------------------------------------------
    local sharedPortraitHeader
    sharedPortraitHeader, h = W:SectionHeader(parent, "PORTRAIT", y); y = y - h

    -- Forward declarations for cross-row updates
    local sharedDetShapeRow
    local sharedDetSizeRow

    -- Row 1: Portrait Mode + Art Style
    local sharedPortraitModeRow
    sharedPortraitModeRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Portrait Mode", values=portraitModeValues2, order=portraitModeOrder2,
          getValue=function()
              -- Blizzard Style always renders the attached portrait.
              if EllesmereUI.BlizzStyle.Get("unitframes") then return "attached" end
              return SVal("portraitStyle", "attached")
          end,
          setValue=function(v)
              -- Any mode change flips row visibility below (Size/Position and the
              -- dragon row hidden at None, Shape detached-only), so a real
              -- change forces a rebuild.
              local prevStyle = SVal("portraitStyle", "attached")
              SSet("portraitStyle", v)
              -- Auto-set shape to "none" when entering detached + 3D
              if v == "detached" and SVal("portraitMode", "2d") == "3d" then
                  UNIT_DB_MAP[optState.selectedUnit]().detachedPortraitShape = "none"
              end
              -- Reset detached-only settings when leaving detached mode
              if v ~= "detached" then
                  UNIT_DB_MAP[optState.selectedUnit]().portraitSize = 0
                  local side = UNIT_DB_MAP[optState.selectedUnit]().portraitSide
                  if side == "top" or side == "insideleft" or side == "insideright" or side == "insidecenter" then
                      UNIT_DB_MAP[optState.selectedUnit]().portraitSide = "left"
                  end
              end
              UNIT_DB_MAP[optState.selectedUnit]().showPortrait = (v ~= "none")
              UpdatePreview()
              if v ~= prevStyle then
                  EllesmereUI:RefreshPage(true)
                  return
              end
              C_Timer.After(0, function() local rl = EllesmereUI._widgetRefreshList; if rl then for i = 1, #rl do rl[i]() end end end)
          end }),
        { type="dropdown", text="Art Style", values=portraitArtValues, order=portraitArtOrder,
          -- Blizzard Style renders the portrait whatever the saved mode says.
          disabled=function() return not EllesmereUI.BlizzStyle.Get("unitframes") and SVal("portraitStyle", "attached") == "none" end,
          disabledTooltip="Portrait Mode is set to None", rawTooltip=true,
          -- Blizzard Style masks the 2D art; a 3D model cannot be masked.
          itemDisabled=function(val) return val == "3d" and EllesmereUI.BlizzStyle.Get("unitframes") end,
          -- The active style's name as the requirement noun; the widget
          -- wraps and translates it once ("... to be disabled").
          itemDisabledTooltip=function(val)
              if val == "3d" then return EllesmereUI.BlizzStyle.Label("unitframes") end
          end,
          itemRequireState="disabled",
          getValue=function()
              local v = SGet("portraitMode")
              if v == "class" then return SVal("classThemeStyle", "modern") end
              return v or "2d"
          end,
          setValue=function(v)
              local settings = SDB()
              local function ApplyArt()
                  settings.portraitMode = v
                  settings.showPortrait = true
                  -- Auto-set shape to "none" when entering 3D + detached
                  if v == "3d" and settings.portraitStyle == "detached" then
                      settings.detachedPortraitShape = "none"
                  end
                  -- 3D-only options: reset when leaving 3D
                  if v ~= "3d" then
                      if settings.detachedPortraitShape == "none" then
                          settings.detachedPortraitShape = "portrait"
                      end
                      local side = settings.portraitSide
                      if side == "insideleft" or side == "insideright" or side == "insidecenter" then
                          settings.portraitSide = "left"
                      end
                  end
                  ReloadAndUpdate(); UpdatePreview()
              end
              local function ConfirmArt()
                  ApplyArt()
                  EllesmereUI:RefreshPage(true)
              end
              if v == "3d" and SVal("portraitMode", "2d") ~= "3d"
                  and ns.UF_Ask3DPortraits(ConfirmArt) then return end
              if v == "2d" and SVal("portraitMode", "2d") ~= "2d"
                  and settings.portraitMirror and not EllesmereUI.BlizzStyle.Get("unitframes")
                  and ns.UF_Ask2DMirroredPortraits(ConfirmArt) then return end
              ApplyArt()
          end });  y = y - h
    -- Sync icon: Portrait Mode (Style)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPortraitModeRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Portrait Mode to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitStyle or "attached"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then
                        UNIT_DB_MAP[key]().portraitStyle = v
                        UNIT_DB_MAP[key]().showPortrait = (v ~= "none")
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitStyle or "attached"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().portraitStyle or "attached") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().portraitStyle or "attached"
                    for _, key in ipairs(checkedKeys) do
                        UNIT_DB_MAP[key]().portraitStyle = v
                        UNIT_DB_MAP[key]().showPortrait = (v ~= "none")
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Portrait settings; the separator is offered only for attached portraits.
    if not EllesmereUI._prebuilding then
        local rows = {
            { type="toggle", label="Custom Non-Player Portrait",
              tooltip="Pick what NPCs show in Class art instead of their 2D portrait.",
              get=function() return SVal("portraitNonPlayerOn", false) end,
              set=function(v)
                  SSet("portraitNonPlayerOn", v or nil)
                  EllesmereUI:RefreshPage(true)
              end },
        }
        if SVal("portraitStyle", "attached") == "attached" then
            rows[#rows + 1] = { type="toggle", label="Vertical Border Separator",
                tooltip="Draws the selected border style between the attached portrait and the bars.",
                disabled=function()
                    return SVal("borderSize", 1) <= 0
                        or not EllesmereUI.GetBorderCompanion(SGet("borderTexture") or "solid", "sepV")
                end,
                disabledTooltip="This option requires a border style with divider art and a Border Size above 0.",
                rawTooltip=true,
                get=function() return SVal("portraitSeparator", false) end,
                set=function(v) SSet("portraitSeparator", v or nil) end,
            }
        end
        EllesmereUI.BuildInlineCog(sharedPortraitModeRow._leftRegion, {
            title = "Portrait Settings",
            disabled = function()
                return EllesmereUI.BlizzStyle.Get("unitframes") or SVal("portraitStyle", "attached") == "none"
            end,
            disabledTooltip = function()
                if EllesmereUI.BlizzStyle.Get("unitframes") then return EllesmereUI.BlizzStyle.Label("unitframes") end
                return "Portrait Mode is set to None"
            end,
            rawTooltip = function() return not EllesmereUI.BlizzStyle.Get("unitframes") end,
            requireState = "disabled",
            rows = rows,
        })
    end
    -- Sync icon: Portrait Mode (Art Style)
    if not EllesmereUI._prebuilding then
        local rgn = sharedPortraitModeRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Art Style to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitMode
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().portraitMode = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitMode or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().portraitMode or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().portraitMode
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitMode = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 1b: Non-Player Portrait (right half blank), built only while the
    -- Portrait Mode cog's opt-in is on and the portrait shows (Portrait
    -- Mode's setValue rebuilds the page on any mode change).
    if SVal("portraitNonPlayerOn", false) and SVal("portraitStyle", "attached") ~= "none" then
    local nonPlayerRow
    nonPlayerRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("unitframes", { type="dropdown", text="Non-Player Portrait",
          values=portraitNonPlayerValues, order=portraitNonPlayerOrder,
          disabled=function() return SVal("portraitMode", "2d") ~= "class" end,
          disabledTooltip="This option requires Art Style to be set to Class", rawTooltip=true,
          -- A 3D model cannot be masked: a Detached shape keeps NPCs on 2D.
          itemDisabled=function(v)
              return v == "3d" and SVal("portraitStyle", "attached") == "detached"
                  and SVal("detachedPortraitShape", "portrait") ~= "none"
          end,
          itemDisabledTooltip=function(v) if v == "3d" then return "Attached Portrait Mode" end end,
          getValue=function() return SVal("portraitNonPlayer", "2d") end,
          setValue=function(v)
              if v == "3d" and SVal("portraitNonPlayer", "2d") ~= "3d" and ns.UF_Ask3DPortraits(function()
                      SSet("portraitNonPlayer", "3d"); EllesmereUI:RefreshPage()
                  end) then
                  return
              end
              SSet("portraitNonPlayer", v)
          end }),
        EllesmereUI.BlankRowCfg());  y = y - h
    -- Sync icon: carries the opt-in with the choice.
    if not EllesmereUI._prebuilding then
        local rgn = nonPlayerRow._leftRegion
        local function ApplyNonPlayer(keys)
            local on, v = SVal("portraitNonPlayerOn", nil), SVal("portraitNonPlayer", "2d")
            for _, key in ipairs(keys) do
                local d = UNIT_DB_MAP[key]()
                d.portraitNonPlayerOn = on
                d.portraitNonPlayer = v
            end
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Non-Player Portrait to all Frames",
            onClick = function() ApplyNonPlayer(GROUP_UNIT_ORDER) end,
            isSynced = function()
                local on, v = SVal("portraitNonPlayerOn", false), SVal("portraitNonPlayer", "2d")
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    if (d.portraitNonPlayerOn or false) ~= on or (d.portraitNonPlayer or "2d") ~= v then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = ApplyNonPlayer,
            },
        })
    end
    end   -- close Non-Player Portrait opt-in gate

    -- Row 2: Size + Position. HIDDEN entirely while Portrait Mode is None
    -- (the mode dropdown's setValue forces the rebuild on any mode change).
    -- Blizzard Style always shows the portrait, so the row stays.
    if EllesmereUI.BlizzStyle.Get("unitframes") or SVal("portraitStyle", "attached") ~= "none" then
    local portraitLocationValues = {
        ["left"] = "Left", ["right"] = "Right", ["top"] = "Top",
        ["insideleft"] = "Inside Left", ["insideright"] = "Inside Right", ["insidecenter"] = "Inside Center",
    }
    local portraitLocationOrder = { "left", "right", "top", "insideleft", "insideright", "insidecenter" }
    local sharedSizePosRow
    sharedSizePosRow, h = W:DualRow(parent, y,
        { type="slider", text="Size", min=-50, max=100, step=1,
          disabled=function()
              local style = SVal("portraitStyle", "attached")
              local side = SVal("portraitSide", "left")
              local isInside = side == "insideleft" or side == "insideright" or side == "insidecenter"
              return style ~= "detached" and not isInside
          end,
          disabledTooltip="Only available in Detached or Inside modes", rawTooltip=true,
          getValue=function() return SVal("portraitSize", 0) end,
          setValue=function(v) SSet("portraitSize", v); UpdatePreview() end },
        { type="dropdown", text="Position", values=portraitLocationValues, order=portraitLocationOrder,
          itemDisabled=function(v)
              local pStyle = SVal("portraitStyle", "attached")
              if v == "top" and pStyle == "attached" then return true end
              if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                  if SVal("portraitMode", "2d") ~= "3d" then return true end
                  if pStyle ~= "detached" then return true end
              end
              return false
          end,
          itemDisabledTooltip=function(v)
              if v == "top" then return "Top position is only available in Detached mode" end
              if v == "insideleft" or v == "insideright" or v == "insidecenter" then
                  if SVal("portraitMode", "2d") ~= "3d" then return "Inside positions require 3D Art Style" end
                  return "Inside positions require Detached mode"
              end
          end,
          getValue=function() return SVal("portraitSide", "left") end,
          setValue=function(v) SSet("portraitSide", v); UpdatePreview() end });  y = y - h
    -- Sync icons: Portrait Size (left) and Portrait Side (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedSizePosRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Portrait Size to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSize or 0
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().portraitSize = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSize or 0
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().portraitSize or 0) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSize or 0
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
        -- Zoom cog on Size slider
        local _, zoomShow
        _, zoomShow = EllesmereUI.BuildInlineCog(rgn, {
            title = "Portrait Zoom",
            rows = {
                { type="slider", label="2D Zoom", min=50, max=100, step=1,
                  get=function() return SVal("portraitArtScale", 100) end,
                  set=function(v) SSet("portraitArtScale", v); UpdatePreview() end },
                { type="slider", label="3D Zoom", min=100, max=300, step=1,
                  get=function() return SVal("portrait3dZoom", 100) end,
                  set=function(v) SSet("portrait3dZoom", v); UpdatePreview() end },
                { type="slider", label="Class Zoom", min=50, max=200, step=1,
                  disabled=function()
                      return EllesmereUI.BlizzStyle.Get("unitframes") or SVal("portraitMode", "2d") ~= "class"
                  end,
                  disabledTooltip=function()
                      if EllesmereUI.BlizzStyle.Get("unitframes") then
                          return EllesmereUI.BlizzStyle.Label("unitframes")
                      end
                      return "This option requires the Class Art Style."
                  end,
                  requireState="disabled",
                  get=function() return SVal("portraitClassZoom", 100) end,
                  set=function(v) SSet("portraitClassZoom", v); UpdatePreview() end },
                -- The stock styles keep their full art.
                { type="toggle", label="Mirror Portrait",
                  tooltip="Mirrors playable-race portraits in 2D and 3D. Always flips class art horizontally.",
                  disabled=function()
                      return EllesmereUI.BlizzStyle.Get("unitframes")
                  end,
                  disabledTooltip=function()
                      return EllesmereUI.BlizzStyle.Label("unitframes")
                  end,
                  requireState="disabled",
                  get=function() return SVal("portraitMirror", false) end,
                  set=function(v)
                      local unitKey, settings = optState.selectedUnit, SDB()
                      local function ApplyMirror()
                          settings.portraitMirror = v
                          ns.UF_RefreshPortraitMirror(unitKey)
                          UpdatePreview()
                      end
                      if v and not settings.portraitMirror and SVal("portraitMode", "2d") == "2d"
                          and ns.UF_Ask2DMirroredPortraits(function()
                              ApplyMirror()
                              EllesmereUI:RefreshPage()
                          end) then
                          if zoomShow and zoomShow._popupFrame then zoomShow._popupFrame:Hide() end
                          return
                      end
                      ApplyMirror()
                  end },
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedSizePosRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Portrait Position to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSide or "left"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().portraitSide = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSide or "left"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().portraitSide or "left") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().portraitSide or "left"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().portraitSide = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    sharedDetSizeRow = sharedSizePosRow
    -- Cog on Position for X/Y offsets
    if not EllesmereUI._prebuilding then
        local posRgn = sharedSizePosRow._rightRegion
        EllesmereUI.BuildInlineCog(posRgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() return SVal("portraitStyle", "attached") ~= "detached" end,
            disabledTooltip = "This option requires Portrait Mode to be set to Detached.",
            title = "Portrait Position Offsets",
            rows = {
                { type="slider", label="X Offset", min=-100, max=100, step=1,
                  get=function() return SVal("portraitX", 0) end,
                  set=function(v) SSet("portraitX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-100, max=100, step=1,
                  get=function() return SVal("portraitY", 0) end,
                  set=function(v) SSet("portraitY", v); UpdatePreview() end },
            },
        })
    end
    end   -- close Size/Position hidden-at-None gate

    -- Row 3: Shape + Shape Border (swatch + cog). HIDDEN unless Portrait Mode is
    -- Detached; the mode dropdown's setValue forces the rebuild on any change.
    if SVal("portraitStyle", "attached") == "detached" then
    local sharedShapeBorderRow
    sharedShapeBorderRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Shape", values=detPortraitShapeValues, order=detPortraitShapeOrder,
          itemDisabled=function(v) return v == "none" and SVal("portraitMode", "2d") ~= "3d" end,
          itemDisabledTooltip=function(v) if v == "none" then return "None shape requires 3D Art Style" end end,
          getValue=function() return SVal("detachedPortraitShape", "portrait") end,
          setValue=function(v)
              SSet("detachedPortraitShape", v); UpdatePreview()
          end },
        { type="multiSwatch", text="Shape Border",
          swatches = {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = SGet("detachedPortraitBorderColor")
                  c = c or { r=0, g=0, b=0 }
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  UNIT_DB_MAP[optState.selectedUnit]().detachedPortraitBorderColor = { r=r, g=g, b=b }
                  ReloadAndUpdate(); UpdatePreview()
              end,
              onClick = function(self)
                  if SVal("detachedPortraitClassColor", true) then
                      SSet("detachedPortraitClassColor", false)
                      ReloadAndUpdate(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SVal("detachedPortraitClassColor", true) and 0.3 or 1
              end },
            { tooltip = "Class Colored",
              hasAlpha = false,
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
                  SSet("detachedPortraitClassColor", true)
                  ReloadAndUpdate(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("detachedPortraitClassColor", true) and 1 or 0.3
              end },
          } });  y = y - h
    -- Cog on Shape Border for border settings
    if not EllesmereUI._prebuilding then
        local borderRgn = sharedShapeBorderRow._rightRegion
        local borderCog = {
            disabled = function() return SVal("portraitStyle", "attached") ~= "detached" end,
            disabledTooltip = "This option is only available when Portrait Mode is Detached.",
            title = "Shape Border Settings",
            rows = {
                { type="slider", label="Size", min=1, max=7, step=1,
                  get=function() return SVal("detachedPortraitBorderSize", 7) end,
                  set=function(v) SSet("detachedPortraitBorderSize", v); UpdatePreview() end },
                { type="slider", label="Opacity", min=0, max=100, step=1,
                  get=function() return SVal("detachedPortraitBorderOpacity", 100) end,
                  set=function(v) SSet("detachedPortraitBorderOpacity", v); UpdatePreview() end },
                { type="toggle", label="Unit Color in Dark Mode",
                  tooltip="Keeps the unit's class or reaction color on the ring in Dark Mode instead of your own class color.",
                  disabled=function()
                      return not (SVal("detachedPortraitClassColor", true) and db.profile.darkTheme)
                  end,
                  disabledTooltip="This option requires the Class Colored Shape Border and Dark Mode.",
                  rawTooltip=true,
                  get=function() return SVal("detachedPortraitUnitColorDark", false) end,
                  set=function(v) SSet("detachedPortraitUnitColorDark", v); UpdatePreview() end },
                { type="dropdown", label="Outer Ring",
                  values={
                      ["none"]                   = "None",
                      ["border"]                 = "Match Frame Border",
                      ["pixels"]                 = "Pixels Ring",
                      ["pixels-textured"]        = "Pixels Textured Ring",
                      ["pixels-shadow"]          = "Pixels Ring Shadow",
                      ["pixels-textured-shadow"] = "Pixels Textured Ring Shadow",
                      ["thin-border"]            = "Naowh Thin Circle",
                  },
                  order={ "none", "border", "pixels", "pixels-textured", "pixels-shadow", "pixels-textured-shadow", "thin-border" },
                  -- "Pixels Textured Ring Shadow" needs more than the 130px default.
                  ddWidth=190,
                  tooltip="Adds a second ring around a round portrait; Match Frame Border follows your frame border style.",
                  disabled=function() return not ns.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")] end,
                  disabledTooltip="This option requires a Circle or Pixels Circle Shape.",
                  rawTooltip=true,
                  get=function() return SVal("detachedPortraitOuterRing", "none") end,
                  set=function(v) SSet("detachedPortraitOuterRing", v); UpdatePreview() end },
                { type="slider", label="Outer Ring Size", min=100, max=140, step=1,
                  tooltip="Size of the outer ring relative to the portrait.",
                  disabled=function()
                      return not ns.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")]
                          or SVal("detachedPortraitOuterRing", "none") == "none"
                  end,
                  disabledTooltip=function()
                      if not ns.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")] then
                          return "This option requires a Circle or Pixels Circle Shape."
                      end
                      return "This option requires an Outer Ring other than None."
                  end,
                  rawTooltip=true,
                  get=function() return SVal("detachedPortraitOuterRingScale", 118) end,
                  set=function(v) SSet("detachedPortraitOuterRingScale", v); UpdatePreview() end },
                -- The 3D model draws over the shadow texture, so 2D and class art only.
                { type="toggle", label="Inner Shadow",
                  tooltip="Adds a soft shadow inside a round portrait.",
                  disabled=function()
                      return not ns.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")]
                          or SVal("portraitMode", "2d") == "3d"
                  end,
                  disabledTooltip=function()
                      if not ns.UF_ROUND_SHAPES[SVal("detachedPortraitShape", "portrait")] then
                          return "This option requires a Circle or Pixels Circle Shape."
                      end
                      return "This option requires a 2D Portrait or Class Art Style."
                  end,
                  rawTooltip=true,
                  get=function() return SVal("detachedPortraitInnerShadow", false) end,
                  set=function(v) SSet("detachedPortraitInnerShadow", v); UpdatePreview() end },
            },
        }
        EllesmereUI.BuildInlineCog(borderRgn, borderCog)
    end
    -- Sync icons: Shape (left) and Shape Border (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedShapeBorderRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Portrait Shape to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().detachedPortraitShape or "portrait"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().detachedPortraitShape = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().detachedPortraitShape or "portrait"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().detachedPortraitShape or "portrait") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().detachedPortraitShape or "portrait"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().detachedPortraitShape = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedShapeBorderRow._rightRegion
        -- The cog's ring rows travel with the sync (key = its default).
        local SB_EXTRAS = {
            detachedPortraitUnitColorDark = false, detachedPortraitOuterRing = "none",
            detachedPortraitOuterRingScale = 118, detachedPortraitInnerShadow = false,
        }
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Shape Border to all Frames",
            onClick = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local bc = src.detachedPortraitBorderColor
                local bo = src.detachedPortraitBorderOpacity
                local bs = src.detachedPortraitBorderSize
                local cc = src.detachedPortraitClassColor
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then
                        local d = UNIT_DB_MAP[key]()
                        if bc then d.detachedPortraitBorderColor = { r=bc.r, g=bc.g, b=bc.b }
                        else d.detachedPortraitBorderColor = nil end
                        d.detachedPortraitBorderOpacity = bo
                        d.detachedPortraitBorderSize = bs
                        d.detachedPortraitClassColor = cc
                        for k in pairs(SB_EXTRAS) do d[k] = src[k] end
                    end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local src = UNIT_DB_MAP[optState.selectedUnit]()
                local cc = src.detachedPortraitClassColor
                if cc == nil then cc = true end
                local bs = src.detachedPortraitBorderSize or 7
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[key]()
                    local dcc = d.detachedPortraitClassColor
                    if dcc == nil then dcc = true end
                    if dcc ~= cc then return false end
                    if (d.detachedPortraitBorderSize or 7) ~= bs then return false end
                    for k, def in pairs(SB_EXTRAS) do
                        local sv, dv = src[k], d[k]
                        if sv == nil then sv = def end
                        if dv == nil then dv = def end
                        if sv ~= dv then return false end
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
                    local src = UNIT_DB_MAP[optState.selectedUnit]()
                    local bc = src.detachedPortraitBorderColor
                    local bo = src.detachedPortraitBorderOpacity
                    local bs = src.detachedPortraitBorderSize
                    local cc = src.detachedPortraitClassColor
                    for _, key in ipairs(checkedKeys) do
                        local d = UNIT_DB_MAP[key]()
                        if bc then d.detachedPortraitBorderColor = { r=bc.r, g=bc.g, b=bc.b }
                        else d.detachedPortraitBorderColor = nil end
                        d.detachedPortraitBorderOpacity = bo
                        d.detachedPortraitBorderSize = bs
                        d.detachedPortraitClassColor = cc
                        for k in pairs(SB_EXTRAS) do d[k] = src[k] end
                    end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    end   -- close Shape/Shape Border detached-only gate

    -- Row 4: Portrait Dragon toggle | Dragon Size (+ cog with the rest). Any
    -- shape, on player, target and focus: the Player Frame Dragon always shows,
    -- the Elite Enemy Dragon marks elite/boss (gold) and rare (silver) enemies.
    -- HIDDEN while Portrait Mode is None (the mode dropdown rebuilds the page);
    -- a stock style gates both slots, which drops the row. Values read through
    -- ns.UF_DragonSettings (the "wingless" Elite/Rare style shows its own
    -- values); every setter pins that view first (ns.UF_PinLegacyDragon).
    if SVal("portraitStyle", "attached") ~= "none" then
        local playerDragon = optState.selectedUnit == "player"
        local dragonName = playerDragon and "Player Frame Dragon" or "Elite Enemy Dragon"
        local function DVal(k) return ns.UF_DragonSettings(optState.selectedUnit, SDB())[k] end
        local function DSet(key, v)
            ns.UF_PinLegacyDragon(SDB())
            SSet(key, v)
        end
        local function dragonOff() return not DVal("on") end
        local dragonRow
        dragonRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="toggle",
              text=playerDragon and "Enable Player Frame Dragon" or "Enable Elite Enemy Dragon",
              tooltip=playerDragon and "Curls Blizzard's gold dragon around the portrait."
                  or "Curls a gold dragon around the portrait of elite and boss enemies, and a silver one around rares.",
              getValue=function() return DVal("on") end,
              setValue=function(v)
                  DSet("detachedPortraitWinglessDragon", v)
                  EllesmereUI:RefreshPage()
              end }),
            EllesmereUI.BlizzStyle.Gate("unitframes", { type="slider", text="Dragon Size", min=50, max=200, step=1,
              tooltip="Size of the dragon, as a percent of its fit around the portrait.",
              disabled=dragonOff, disabledTooltip=dragonName,
              getValue=function() return DVal("scale") end,
              setValue=function(v) DSet("detachedPortraitWinglessDragonScale", v) end }));  y = y - h
        if not EllesmereUI._prebuilding then
            local rows = {
                { type="slider", label="X Offset", min=-100, max=100, step=1,
                  get=function() return DVal("x") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonX", v) end },
                { type="slider", label="Y Offset", min=-100, max=100, step=1,
                  get=function() return DVal("y") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonY", v) end },
                { type="toggle", label="Flip Dragon",
                  tooltip="Turns the dragon to face the other way around the portrait.",
                  get=function() return DVal("flip") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonFlip", v) end },
                { type="toggle", label="Use Class Color",
                  tooltip=playerDragon and "Tints the dragon with your class color instead of gold."
                      or "Tints the dragon with your class color instead of gold or silver.",
                  get=function() return DVal("classColor") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonClassColor", v) end },
                { type="dropdown", label="Dragon Strata",
                  values=ns._ufDragonStrataValues, order=ns._ufDragonStrataOrder,
                  tooltip="Match Frame draws the dragon with the portrait. A higher strata draws it over the rest of the frame, border included.",
                  get=function() return DVal("strata") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonStrata", v) end },
                { type="slider", label="Dragon Frame Level", min=1, max=30, step=1,
                  tooltip="Raises the dragon within its strata. Higher values draw it over more of the frame.",
                  get=function() return DVal("level") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonLevel", v) end },
            }
            -- The enemy dragon keeps the Elite/Rare Indicator's instance rule.
            if not playerDragon then
                rows[#rows + 1] = { type="toggle", label="Show in Instances",
                  tooltip="Also show the dragon in dungeons and raids, where most enemies are elite.",
                  get=function() return DVal("instances") end,
                  set=function(v) DSet("detachedPortraitWinglessDragonInstances", v) end }
            end
            EllesmereUI.BuildInlineCog(dragonRow._rightRegion, {
                title = dragonName,
                disabled = dragonOff, disabledTooltip = dragonName,
                rows = rows,
            })
        end
    end   -- close dragon row hidden-at-None gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    return y, sharedPortraitHeader, sharedPortraitModeRow
end

function ns.UFO_BuildTextBarSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local GROUP_UNIT_ORDER, PP, RegisterWidgetRefresh, ReloadAndUpdate = env.GROUP_UNIT_ORDER, env.PP, env.RegisterWidgetRefresh, env.ReloadAndUpdate
    local SHORT_LABELS, UNIT_DB_MAP, UpdatePreview, btbPositionOrder = env.SHORT_LABELS, env.UNIT_DB_MAP, env.UpdatePreview, env.btbPositionOrder
    local btbPositionValues, btbTextOrder, btbTextValues, classIconLocOrder = env.btbPositionValues, env.btbTextOrder, env.btbTextValues, env.classIconLocOrder
    local classIconLocValues, classIconOrder, classIconValues, optState = env.classIconLocValues, env.classIconOrder, env.classIconValues, env.optState
    local W, SGet, SSet, SVal = ctx.W, ctx.SGet, ctx.SSet, ctx.SVal
    local _, h

    -------------------------------------------------------------------
    --  TEXT BAR
    -------------------------------------------------------------------
    -- Blizzard Style hides the text bar, so the whole section goes; the
    -- row locals stay declared for the element-nav map.
    local sharedBtbHeader
    local _sharedBtbWidthRgn
    local sharedBtbToggleRow
    if not EllesmereUI.BlizzStyle.Get("unitframes") then
    _, h = W:Spacer(parent, y, 20); y = y - h
    sharedBtbHeader, h = W:SectionHeader(parent, "TEXT BAR", y); y = y - h

    -- Row 1: Enable Text Bar + Position
    sharedBtbToggleRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Text Bar",
          getValue=function() return SVal("bottomTextBar", false) end,
          -- DependentSetValue: Rows 2-4 below are hidden while the Text
          -- Bar is off; the flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return SVal("bottomTextBar", false) end,
              function(v) SSet("bottomTextBar", v); UpdatePreview(); EllesmereUI:RefreshPage() end) },
        { type="dropdown", text="Position", values=btbPositionValues, order=btbPositionOrder,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("btbPosition", "bottom") end,
          setValue=function(v)
              SSet("btbPosition", v); UpdatePreview()
              if _sharedBtbWidthRgn then
                  local isDet = (v == "detached_top" or v == "detached_bottom")
                  if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
                      _sharedBtbWidthRgn._control:SetEnabled(isDet)
                  end
              end
          end });  y = y - h
    -- Sync icon: Enable Text Bar
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbToggleRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Enable Text Bar to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBar or false
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().bottomTextBar = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBar or false
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().bottomTextBar or false) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBar or false
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().bottomTextBar = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Sync icon: Text Bar Position (right region)
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbToggleRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Position to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbPosition or "bottom"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if key ~= optState.selectedUnit then UNIT_DB_MAP[key]().btbPosition = v end
                end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbPosition or "bottom"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbPosition or "bottom") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbPosition or "bottom"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbPosition = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    -- Inline color swatch for BTB background on Enable Text Bar
    if not EllesmereUI._prebuilding then
        local btbRgn = sharedBtbToggleRow._leftRegion
        local sw = EllesmereUI.BuildColorSwatch(btbRgn, btbRgn:GetFrameLevel() + 5,
            function()
                local c = SGet("btbBgColor")
                c = c or { r=0.2, g=0.2, b=0.2 }
                local a = SGet("btbBgOpacity")
                return c.r, c.g, c.b, a or 1.0
            end,
            function(r, g, b, a)
                UNIT_DB_MAP[optState.selectedUnit]().btbBgColor = { r=r, g=g, b=b }
                UNIT_DB_MAP[optState.selectedUnit]().btbBgOpacity = a
                ReloadAndUpdate(); UpdatePreview()
            end, true, 20)
        sw:SetPoint("RIGHT", btbRgn._lastInline or btbRgn._control, "LEFT", -12, 0)
        btbRgn._lastInline = sw
        -- Disabled state for swatch when text bar is off
        local function UpdateBtbSwatchState()
            local btbOn = SVal("bottomTextBar", false)
            if not btbOn then
                sw:SetAlpha(0.15); sw:Disable()
                sw._disabledTooltip = "Text Bar"
            else
                sw:SetAlpha(1); sw:Enable()
                sw._disabledTooltip = nil
            end
        end
        UpdateBtbSwatchState()
        RegisterWidgetRefresh(UpdateBtbSwatchState)
        sw:HookScript("OnEnter", function(self)
            if self._disabledTooltip then
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(self._disabledTooltip))
            end
        end)
        sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end
    -- Cog on Position for X/Y offsets
    if not EllesmereUI._prebuilding then
        local posRgn = sharedBtbToggleRow._rightRegion
        EllesmereUI.BuildInlineCog(posRgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() local pos = SVal("btbPosition", "bottom"); return not SVal("bottomTextBar", false) or (pos ~= "detached_top" and pos ~= "detached_bottom") end,
            disabledTooltip = function() return not SVal("bottomTextBar", false) and "Text Bar" or "This option requires a detached position to be active." end,
            title = "Detached Position Offsets",
            rows = {
                { type="slider", label="X Offset", min=-200, max=200, step=1,
                  get=function() return SVal("btbX", 0) end,
                  set=function(v) SSet("btbX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                  get=function() return SVal("btbY", 0) end,
                  set=function(v) SSet("btbY", v); UpdatePreview() end },
            },
        })
    end
    end   -- close Blizzard Style text bar gate

    -- Rows 2-4 are HIDDEN while Enable Text Bar is off (DependentSetValue rebuilds
    -- on flips) and under Blizzard Style. Row locals referenced by the element-nav
    -- map are hoisted above the gate so the map never reads nil globals.
    local sharedBtbTextRow, sharedBtbCenterRow
    if SVal("bottomTextBar", false) and not EllesmereUI.BlizzStyle.Get("unitframes") then
    -- Row 2: Height + Width
    local sharedBtbHeightRow
    sharedBtbHeightRow, h = W:DualRow(parent, y,
        { type="slider", text="Height", min=0, max=100, step=1,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("bottomTextBarHeight", 16) end,
          setValue=function(v) SSet("bottomTextBarHeight", v); UpdatePreview() end },
        { type="slider", text="Width", min=0, max=400, step=1,
          disabled=function()
              if not SVal("bottomTextBar", false) then return true end
              local pos = SVal("btbPosition", "bottom")
              return pos ~= "detached_top" and pos ~= "detached_bottom"
          end,
          disabledTooltip=function()
              if not SVal("bottomTextBar", false) then return "Text Bar" end
              return "This option requires the position setting to be detached"
          end,
          getValue=function() return SVal("btbWidth", 0) end,
          setValue=function(v) SSet("btbWidth", v); UpdatePreview() end });  y = y - h
    _sharedBtbWidthRgn = sharedBtbHeightRow._rightRegion
    do
        local pos = SVal("btbPosition", "bottom")
        local isDet = (pos == "detached_top" or pos == "detached_bottom")
        if _sharedBtbWidthRgn._control and _sharedBtbWidthRgn._control.SetEnabled then
            _sharedBtbWidthRgn._control:SetEnabled(isDet)
        end
    end
    -- Sync icons: BTB Height (left) and BTB Width (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbHeightRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Height to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBarHeight or 16
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().bottomTextBarHeight = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBarHeight or 16
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().bottomTextBarHeight or 16) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().bottomTextBarHeight or 16
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().bottomTextBarHeight = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbHeightRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Width to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbWidth or 0
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbWidth = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbWidth or 0
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbWidth or 0) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbWidth or 0
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbWidth = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 3: Left Text + Right Text
    sharedBtbTextRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Left Text", values=btbTextValues, order=btbTextOrder,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("btbLeftContent", "none") end,
          setValue=function(v)
              SSet("btbLeftContent", v)
              if v ~= "none" then
                  if SGet("btbRightContent") == v then SSet("btbRightContent", "none") end
                  if SGet("btbCenterContent") == v then SSet("btbCenterContent", "none") end
              end
              ReloadAndUpdate(); UpdatePreview()
          end },
        { type="dropdown", text="Right Text", values=btbTextValues, order=btbTextOrder,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("btbRightContent", "none") end,
          setValue=function(v)
              SSet("btbRightContent", v)
              if v ~= "none" then
                  if SGet("btbLeftContent") == v then SSet("btbLeftContent", "none") end
                  if SGet("btbCenterContent") == v then SSet("btbCenterContent", "none") end
              end
              ReloadAndUpdate(); UpdatePreview()
          end });  y = y - h
    -- Inline color swatches on BTB Left Text: Custom + Class (CDM Border Size
    -- pattern). Power Color stays in the cog; the three modes are mutually exclusive.
    if not EllesmereUI._prebuilding then
        local btbLRgn = sharedBtbTextRow._leftRegion
        local function blOff() return SVal("btbLeftContent", "none") == "none" or not SVal("bottomTextBar", false) end
        local blClassSwatch, blUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            btbLRgn, btbLRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(blClassSwatch, "RIGHT", btbLRgn._lastInline or btbLRgn._control, "LEFT", -8, 0)
        blClassSwatch:SetScript("OnClick", function()
            if blOff() then return end
            SSet("btbLeftClassColor", true); SSet("btbLeftPowerColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        blClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blClassSwatch, "Class Colored") end)
        blClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local blSwGet = function()
            return SVal("btbLeftColorR", 1), SVal("btbLeftColorG", 1), SVal("btbLeftColorB", 1)
        end
        local blSwSet = function(r, g, b)
            SSet("btbLeftColorR", r); SSet("btbLeftColorG", g); SSet("btbLeftColorB", b)
            UpdatePreview()
        end
        local blSwatch, blUpdateSwatch = EllesmereUI.BuildColorSwatch(btbLRgn, btbLRgn:GetFrameLevel() + 5, blSwGet, blSwSet, nil, 20)
        PP.Point(blSwatch, "RIGHT", blClassSwatch, "LEFT", -8, 0)
        btbLRgn._lastInline = blSwatch
        local blOrigClick = blSwatch:GetScript("OnClick")
        blSwatch:SetScript("OnClick", function(self, ...)
            if blOff() then return end
            if SVal("btbLeftClassColor", false) or SVal("btbLeftPowerColor", false) then
                SSet("btbLeftClassColor", false); SSet("btbLeftPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if blOrigClick then blOrigClick(self, ...) end
        end)
        blSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blSwatch, "Custom Colored") end)
        blSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- Power Color swatch: shows the player's current power color; click to
        -- select power-colored mode. Same per-unit power resolution as the power
        -- bar text (white fallback when the power token can't resolve).
        local blPowerSwatch, blUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
            btbLRgn, btbLRgn:GetFrameLevel() + 5,
            function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                if info then return info.r, info.g, info.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(blPowerSwatch, "RIGHT", blSwatch, "LEFT", -8, 0)
        btbLRgn._lastInline = blPowerSwatch
        blPowerSwatch:SetScript("OnClick", function()
            if blOff() then return end
            SSet("btbLeftPowerColor", true); SSet("btbLeftClassColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        blPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(blPowerSwatch, "Power Colored") end)
        blPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBlSwatches()
            local off = blOff()
            local isClass = SVal("btbLeftClassColor", false)
            local isPower = SVal("btbLeftPowerColor", false)
            blSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
            blClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
            blPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() blUpdateSwatch(); blUpdateClassSwatch(); blUpdatePowerSwatch(); UpdateBlSwatches() end)
        UpdateBlSwatches()
    end
    -- Cogwheel on BTB Left Text
    if not EllesmereUI._prebuilding then
        local btbLRgn = sharedBtbTextRow._leftRegion
        EllesmereUI.BuildInlineCog(btbLRgn, {
            disabled = function() return not SVal("bottomTextBar", false) or SVal("btbLeftContent", "none") == "none" end,
            disabledTooltip = function() return not SVal("bottomTextBar", false) and "Text Bar" or "This option requires a text selection other than none." end,
            title = "BTB Left Text Settings",
            rows = ns.UF_NameFormatRows("btbLeft", "none", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("btbLeftSize", 11) end,
                  set=function(v) SSet("btbLeftSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SVal("btbLeftX", 0) end,
                  set=function(v) SSet("btbLeftX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return SVal("btbLeftY", 0) end,
                  set=function(v) SSet("btbLeftY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("btbLeftWidthPct", 100) end,
                  set=function(v) SSet("btbLeftWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() return SVal("btbLeftContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("btbLeftTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("btbLeftTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("btbLeftTargetSepClassColor", false) then
                              SSet("btbLeftTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("btbLeftTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("btbLeftTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("btbLeftTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("btbLeftTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("btbLeftTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("btbLeftContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected." },
                                }),
        })
    end
    -- Inline color swatches on BTB Right Text: Custom + Class (Power Color stays in
    -- the cog; the three modes are mutually exclusive).
    if not EllesmereUI._prebuilding then
        local btbRRgn = sharedBtbTextRow._rightRegion
        local function brOff() return SVal("btbRightContent", "none") == "none" or not SVal("bottomTextBar", false) end
        local brClassSwatch, brUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            btbRRgn, btbRRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(brClassSwatch, "RIGHT", btbRRgn._lastInline or btbRRgn._control, "LEFT", -8, 0)
        brClassSwatch:SetScript("OnClick", function()
            if brOff() then return end
            SSet("btbRightClassColor", true); SSet("btbRightPowerColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        brClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brClassSwatch, "Class Colored") end)
        brClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local brSwGet = function()
            return SVal("btbRightColorR", 1), SVal("btbRightColorG", 1), SVal("btbRightColorB", 1)
        end
        local brSwSet = function(r, g, b)
            SSet("btbRightColorR", r); SSet("btbRightColorG", g); SSet("btbRightColorB", b)
            UpdatePreview()
        end
        local brSwatch, brUpdateSwatch = EllesmereUI.BuildColorSwatch(btbRRgn, btbRRgn:GetFrameLevel() + 5, brSwGet, brSwSet, nil, 20)
        PP.Point(brSwatch, "RIGHT", brClassSwatch, "LEFT", -8, 0)
        btbRRgn._lastInline = brSwatch
        local brOrigClick = brSwatch:GetScript("OnClick")
        brSwatch:SetScript("OnClick", function(self, ...)
            if brOff() then return end
            if SVal("btbRightClassColor", false) or SVal("btbRightPowerColor", false) then
                SSet("btbRightClassColor", false); SSet("btbRightPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if brOrigClick then brOrigClick(self, ...) end
        end)
        brSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brSwatch, "Custom Colored") end)
        brSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- Power Color swatch: shows the player's current power color; click to
        -- select power-colored mode. Same per-unit power resolution as the power
        -- bar text (white fallback when the power token can't resolve).
        local brPowerSwatch, brUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
            btbRRgn, btbRRgn:GetFrameLevel() + 5,
            function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                if info then return info.r, info.g, info.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(brPowerSwatch, "RIGHT", brSwatch, "LEFT", -8, 0)
        btbRRgn._lastInline = brPowerSwatch
        brPowerSwatch:SetScript("OnClick", function()
            if brOff() then return end
            SSet("btbRightPowerColor", true); SSet("btbRightClassColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        brPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(brPowerSwatch, "Power Colored") end)
        brPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBrSwatches()
            local off = brOff()
            local isClass = SVal("btbRightClassColor", false)
            local isPower = SVal("btbRightPowerColor", false)
            brSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
            brClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
            brPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() brUpdateSwatch(); brUpdateClassSwatch(); brUpdatePowerSwatch(); UpdateBrSwatches() end)
        UpdateBrSwatches()
    end
    -- Cogwheel on BTB Right Text
    if not EllesmereUI._prebuilding then
        local btbRRgn = sharedBtbTextRow._rightRegion
        EllesmereUI.BuildInlineCog(btbRRgn, {
            disabled = function() return not SVal("bottomTextBar", false) or SVal("btbRightContent", "none") == "none" end,
            disabledTooltip = function() return not SVal("bottomTextBar", false) and "Text Bar" or "This option requires a text selection other than none." end,
            title = "BTB Right Text Settings",
            rows = ns.UF_NameFormatRows("btbRight", "none", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("btbRightSize", 11) end,
                  set=function(v) SSet("btbRightSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SVal("btbRightX", 0) end,
                  set=function(v) SSet("btbRightX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return SVal("btbRightY", 0) end,
                  set=function(v) SSet("btbRightY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("btbRightWidthPct", 100) end,
                  set=function(v) SSet("btbRightWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() return SVal("btbRightContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("btbRightTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("btbRightTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("btbRightTargetSepClassColor", false) then
                              SSet("btbRightTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("btbRightTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("btbRightTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("btbRightTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("btbRightTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("btbRightTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("btbRightContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected." },
                                }),
        })
    end
    -- Sync icons: BTB Left Text (left) and BTB Right Text (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbTextRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Left Text to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbLeftContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbLeftContent = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbLeftContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbLeftContent or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbLeftContent or "none"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbLeftContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbTextRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Right Text to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbRightContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbRightContent = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbRightContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbRightContent or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbRightContent or "none"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbRightContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Row 4: Center Text + Class Icon
    sharedBtbCenterRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Center Text", values=btbTextValues, order=btbTextOrder,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("btbCenterContent", "none") end,
          setValue=function(v)
              SSet("btbCenterContent", v)
              if v ~= "none" then
                  SSet("btbLeftContent", "none")
                  SSet("btbRightContent", "none")
              end
              ReloadAndUpdate(); UpdatePreview()
          end },
        { type="dropdown", text="Class Icon", values=classIconValues, order=classIconOrder,
          disabled=function() return not SVal("bottomTextBar", false) end,
          disabledTooltip="Text Bar",
          getValue=function() return SVal("btbClassIcon", "none") end,
          setValue=function(v) SSet("btbClassIcon", v); UpdatePreview() end });  y = y - h
    -- Inline color swatches on BTB Center Text: Custom + Class (Power Color stays in
    -- the cog; the three modes are mutually exclusive).
    if not EllesmereUI._prebuilding then
        local btbCRgn = sharedBtbCenterRow._leftRegion
        local function bcOff() return SVal("btbCenterContent", "none") == "none" or not SVal("bottomTextBar", false) end
        local bcClassSwatch, bcUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            btbCRgn, btbCRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(bcClassSwatch, "RIGHT", btbCRgn._lastInline or btbCRgn._control, "LEFT", -8, 0)
        bcClassSwatch:SetScript("OnClick", function()
            if bcOff() then return end
            SSet("btbCenterClassColor", true); SSet("btbCenterPowerColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        bcClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcClassSwatch, "Class Colored") end)
        bcClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local bcSwGet = function()
            return SVal("btbCenterColorR", 1), SVal("btbCenterColorG", 1), SVal("btbCenterColorB", 1)
        end
        local bcSwSet = function(r, g, b)
            SSet("btbCenterColorR", r); SSet("btbCenterColorG", g); SSet("btbCenterColorB", b)
            UpdatePreview()
        end
        local bcSwatch, bcUpdateSwatch = EllesmereUI.BuildColorSwatch(btbCRgn, btbCRgn:GetFrameLevel() + 5, bcSwGet, bcSwSet, nil, 20)
        PP.Point(bcSwatch, "RIGHT", bcClassSwatch, "LEFT", -8, 0)
        btbCRgn._lastInline = bcSwatch
        local bcOrigClick = bcSwatch:GetScript("OnClick")
        bcSwatch:SetScript("OnClick", function(self, ...)
            if bcOff() then return end
            if SVal("btbCenterClassColor", false) or SVal("btbCenterPowerColor", false) then
                SSet("btbCenterClassColor", false); SSet("btbCenterPowerColor", false)
                UpdatePreview(); EllesmereUI:RefreshPage(); return
            end
            if bcOrigClick then bcOrigClick(self, ...) end
        end)
        bcSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcSwatch, "Custom Colored") end)
        bcSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        -- Power Color swatch: shows the player's current power color; click to
        -- select power-colored mode. Same per-unit power resolution as the power
        -- bar text (white fallback when the power token can't resolve).
        local bcPowerSwatch, bcUpdatePowerSwatch = EllesmereUI.BuildColorSwatch(
            btbCRgn, btbCRgn:GetFrameLevel() + 5,
            function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                if info then return info.r, info.g, info.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(bcPowerSwatch, "RIGHT", bcSwatch, "LEFT", -8, 0)
        btbCRgn._lastInline = bcPowerSwatch
        bcPowerSwatch:SetScript("OnClick", function()
            if bcOff() then return end
            SSet("btbCenterPowerColor", true); SSet("btbCenterClassColor", false)
            UpdatePreview(); EllesmereUI:RefreshPage()
        end)
        bcPowerSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bcPowerSwatch, "Power Colored") end)
        bcPowerSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBcSwatches()
            local off = bcOff()
            local isClass = SVal("btbCenterClassColor", false)
            local isPower = SVal("btbCenterPowerColor", false)
            bcSwatch:SetAlpha((isClass or isPower or off) and 0.3 or 1)
            bcClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
            bcPowerSwatch:SetAlpha((isPower and not off) and 1 or 0.3)
        end
        RegisterWidgetRefresh(function() bcUpdateSwatch(); bcUpdateClassSwatch(); bcUpdatePowerSwatch(); UpdateBcSwatches() end)
        UpdateBcSwatches()
    end
    -- Cogwheel on BTB Center Text
    if not EllesmereUI._prebuilding then
        local btbCRgn = sharedBtbCenterRow._leftRegion
        EllesmereUI.BuildInlineCog(btbCRgn, {
            disabled = function() return not SVal("bottomTextBar", false) or SVal("btbCenterContent", "none") == "none" end,
            disabledTooltip = function() return not SVal("bottomTextBar", false) and "Text Bar" or "This option requires a text selection other than none." end,
            title = "BTB Center Text Settings",
            rows = ns.UF_NameFormatRows("btbCenter", "none", SVal, SSet, {
                { type="slider", label="Size", min=8, max=100, step=1,
                  get=function() return SVal("btbCenterSize", 11) end,
                  set=function(v) SSet("btbCenterSize", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SVal("btbCenterX", 0) end,
                  set=function(v) SSet("btbCenterX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-30, max=30, step=1,
                  get=function() return SVal("btbCenterY", 0) end,
                  set=function(v) SSet("btbCenterY", v); UpdatePreview() end },
                { type="slider", label="Width %", min=20, max=200, step=5,
                  get=function() return SVal("btbCenterWidthPct", 100) end,
                  set=function(v) SSet("btbCenterWidthPct", v); UpdatePreview() end },
                { type="multiswatch", label="Indicator Color",
                  disabled=function() return SVal("btbCenterContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected.",
                  swatches = {
                    { tooltip = "Custom Colored", hasAlpha = false,
                      getValue = function() local c = SVal("btbCenterTargetSepColor", nil) if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end return 1, 1, 1 end,
                      setValue = function(r, g, b) SSet("btbCenterTargetSepColor", { r=r, g=g, b=b }); UpdatePreview() end,
                      onClick = function(self)
                          if SVal("btbCenterTargetSepClassColor", false) then
                              SSet("btbCenterTargetSepClassColor", false); UpdatePreview()
                              return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function() return SVal("btbCenterTargetSepClassColor", false) and 0.3 or 1 end },
                    { tooltip = "Class Colored", hasAlpha = false,
                      getValue = function()
                          local _, ct = UnitClass("player")
                          local cc = ct and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[ct]
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function() SSet("btbCenterTargetSepClassColor", true); UpdatePreview() end,
                      refreshAlpha = function() return SVal("btbCenterTargetSepClassColor", false) and 1 or 0.3 end },
                  } },
                { type="input", label="Separator", inputWidth=60,
                  get=function() return SVal("btbCenterTargetSep", ">") end,
                  set=function(v)
                      v = tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                      if v == "" then v = ">" end
                      SSet("btbCenterTargetSep", v); UpdatePreview()
                  end,
                  disabled=function() return SVal("btbCenterContent","none") ~= "nametotarget" end,
                  disabledTooltip="Only applies when Name > Target is selected." },
                                }),
        })
    end
    -- Cogwheel on Class Icon for size/location/x/y
    if not EllesmereUI._prebuilding then
        local ciRgn = sharedBtbCenterRow._rightRegion
        EllesmereUI.BuildInlineCog(ciRgn, {
            disabled = function() return not SVal("bottomTextBar", false) or SVal("btbClassIcon", "none") == "none" end,
            disabledTooltip = function() return not SVal("bottomTextBar", false) and "Text Bar" or "This option requires a Class Icon other than None." end,
            title = "Class Icon Settings",
            rows = {
                { type="slider", label="Size", min=8, max=60, step=1,
                  get=function() return SVal("btbClassIconSize", 14) end,
                  set=function(v) SSet("btbClassIconSize", v); UpdatePreview() end },
                { type="dropdown", label="Location", values=classIconLocValues, order=classIconLocOrder,
                  get=function() return SVal("btbClassIconLocation", "left") end,
                  set=function(v) SSet("btbClassIconLocation", v); UpdatePreview() end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return SVal("btbClassIconX", 0) end,
                  set=function(v) SSet("btbClassIconX", v); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return SVal("btbClassIconY", 0) end,
                  set=function(v) SSet("btbClassIconY", v); UpdatePreview() end },
            },
        })
    end
    -- Sync icons: BTB Center Text (left) and Class Icon (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbCenterRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Center Text to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbCenterContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbCenterContent = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbCenterContent or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbCenterContent or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbCenterContent or "none"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbCenterContent = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedBtbCenterRow._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Text Bar Class Icon to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbClassIcon or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().btbClassIcon = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().btbClassIcon or "none"
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().btbClassIcon or "none") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().btbClassIcon or "none"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().btbClassIcon = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    end   -- close Text Bar hidden-while-disabled gate

    return y, sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow
end

function ns.UFO_BuildExtrasSection(parent, y, ctx)
    local env = ns._UFO_OptEnv
    local CLASS_FULL_COORDS, GROUP_UNIT_ORDER, RegisterWidgetRefresh, ReloadAndUpdate = env.CLASS_FULL_COORDS, env.GROUP_UNIT_ORDER, env.RegisterWidgetRefresh, env.ReloadAndUpdate
    local SHORT_LABELS, UNIT_DB_MAP, UpdatePreview, db = env.SHORT_LABELS, env.UNIT_DB_MAP, env.UpdatePreview, env.db
    local optState = env.optState
    local W, SApplySupport, SDB, SGetSupported = ctx.W, ctx.SApplySupport, ctx.SDB, ctx.SGetSupported
    local SSetSupported, SValSupported, SVisible = ctx.SSetSupported, ctx.SValSupported, ctx.SVisible
    local h

    local sharedAddHeader
    -------------------------------------------------------------------
    --  EXTRAS
    -------------------------------------------------------------------
    sharedAddHeader, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

    -- Row 1: Combat Indicator (absorb settings live in the ABSORBS section above)
    -- Declared outside the gate: the click-mapping table at the bottom of
    -- this function references it (a block-local would be nil there).
    local sharedAddRow1
    local _showAbsorbsCombat = (optState.selectedUnit == "player" or optState.selectedUnit == "target" or optState.selectedUnit == "focus")
    if _showAbsorbsCombat then
    local COMBAT_MEDIA_P = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"
    local combatIndValues = {
        ["none"]="None", ["standard"]="Standard", ["class"]="Class Theme",
        _menuOpts = { itemHeight = 32, icon = function(key)
            if key == "none" then return nil end
            if key == "class" then
                local _, ct = UnitClass("player")
                if not ct then return nil end
                local coords = CLASS_FULL_COORDS[ct]
                if not coords then return nil end
                return COMBAT_MEDIA_P .. "combat-indicator-class-custom.png", coords[1], coords[2], coords[3], coords[4]
            elseif key == "standard" then
                return COMBAT_MEDIA_P .. "combat-indicator-custom.png", 0, 1, 0, 1
            else
                -- New full-colour combat icons (combat0..combat5), shown as-is.
                return COMBAT_MEDIA_P .. key .. ".tga", 0, 1, 0, 1
            end
        end },
    }
    local combatIndOrder = { "none", "standard", "class" }
    -- combat0..2 (Arcade/Dungeoneer/Classic) are shown as-is (non-colorable);
    -- combat3..5 (Cross/Circle/Square) are colorable like Standard/Class Theme.
    local _combatNames = { [0] = "Arcade", [1] = "Dungeoneer", [2] = "Classic", [3] = "Cross", [4] = "Circle", [5] = "Square" }
    for _i = 0, 5 do
        combatIndValues["combat" .. _i] = _combatNames[_i]
        combatIndOrder[#combatIndOrder + 1] = "combat" .. _i
    end
    -- Enemy Colors helper: custom reaction colors for non-player units.
    -- Global (one set shared by all frames); empty entries fall back to
    -- Blizzard defaults. Consumed by the Enemy Colors multiSwatch in slot 2.
    local function enemySwatch(key, defIdx, dr, dg, dbb, tip)
        return {
            tooltip = tip,
            getValue = function()
                local ec = db.profile.enemyColors or {}
                local c = ec[key]
                if c then return c.r, c.g, c.b end
                local f = defIdx and FACTION_BAR_COLORS[defIdx]
                if f then return f.r, f.g, f.b end
                return dr, dg, dbb
            end,
            setValue = function(r, g, b)
                db.profile.enemyColors = db.profile.enemyColors or {}
                db.profile.enemyColors[key] = { r = r, g = g, b = b }
                if ns.ApplyEnemyColors then ns.ApplyEnemyColors() end
            end,
        }
    end
    sharedAddRow1, h = W:DualRow(parent, y,
        { type="dropdown", text="Combat Indicator", values=combatIndValues, order=combatIndOrder,
          -- Target ships disabled ("none"): opt-in, no change for existing users.
          getValue=function() return SValSupported("combatIndicatorStyle", optState.selectedUnit == "player" and "class" or "none") end,
          setValue=function(v) SSetSupported("combatIndicatorStyle", v); ReloadAndUpdate(); UpdatePreview() end },
        { type = "multiSwatch", text = "Enemy Colors",
          swatches = {
              enemySwatch("hostile",  2,   0.78, 0.25, 0.25, "Hostile"),
              enemySwatch("neutral",  4,   0.85, 0.77, 0.36, "Neutral"),
              enemySwatch("friendly", 5,   0.29, 0.68, 0.30, "Friendly NPC"),
              enemySwatch("tapped",   nil, 0.6,  0.6,  0.6,  "Tapped"),
          } });  y = y - h
    if not EllesmereUI._prebuilding then
    SApplySupport(sharedAddRow1._leftRegion, "combatIndicatorStyle",
        "The Combat Indicator is not available for the Focus frame.")
    end
    -- Sync icon: Combat Indicator (player + target only -- focus has none)
    if SVisible("combatIndicatorStyle") and not EllesmereUI._prebuilding then
        local rgn = sharedAddRow1._leftRegion
        local ciSyncUnits = { "player", "target" }
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Combat Indicator Style to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().combatIndicatorStyle or "class"
                for _, key in ipairs(ciSyncUnits) do UNIT_DB_MAP[key]().combatIndicatorStyle = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().combatIndicatorStyle or "class"
                for _, key in ipairs(ciSyncUnits) do
                    if (UNIT_DB_MAP[key]().combatIndicatorStyle or "class") ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = ciSyncUnits,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().combatIndicatorStyle or "class"
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().combatIndicatorStyle = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- Eyeball toggle + cog + swatch on combat indicator dropdown
    -- (player + target only -- the focus row is dimmed with a tooltip)
    if SVisible("combatIndicatorStyle") and not EllesmereUI._prebuilding then
        local ciRgn = sharedAddRow1._leftRegion
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", nil, ciRgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", ciRgn._lastInline or ciRgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(ciRgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        ciRgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshCombatEye()
            eyeTex:SetTexture(optState.showCombatIndicatorPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshCombatEye()
        eyeBtn:SetScript("OnClick", function()
            optState.showCombatIndicatorPreview = not optState.showCombatIndicatorPreview
            RefreshCombatEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, optState.showCombatIndicatorPreview and "Hide combat indicator preview" or "Show combat indicator preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)

        -- Inline color swatch for custom color. Same order and spacing as
        -- the Heal Absorb Style row above: eye, swatch, cog at -8 gaps,
        -- with the swatch dimmed + click-blocked (never hidden, so the
        -- inline chain keeps its spacing) when the color doesn't apply.
        local combatSwatch = EllesmereUI.BuildColorSwatch(ciRgn, ciRgn:GetFrameLevel() + 5,
            function()
                local cc = SGetSupported("combatIndicatorCustomColor")
                cc = cc or { r=1, g=1, b=1 }
                return cc.r, cc.g, cc.b, 1
            end,
            function(r, g, b)
                UNIT_DB_MAP[optState.selectedUnit]().combatIndicatorCustomColor = { r=r, g=g, b=b }
                ReloadAndUpdate(); UpdatePreview()
            end, false, 20)
        combatSwatch:SetPoint("RIGHT", ciRgn._lastInline or ciRgn._control, "LEFT", -8, 0)
        ciRgn._lastInline = combatSwatch
        local combatSwatchBlock = CreateFrame("Frame", nil, combatSwatch)
        combatSwatchBlock:SetAllPoints()
        combatSwatchBlock:SetFrameLevel(combatSwatch:GetFrameLevel() + 10)
        combatSwatchBlock:EnableMouse(true)
        combatSwatchBlock:Hide()
        local function UpdateSwatchVisibility()
            local colorMode = SValSupported("combatIndicatorColor", "custom")
            local style = SValSupported("combatIndicatorStyle", "class")
            -- All custom combat icons (combat0..5) are shown as-is, so the custom-
            -- color swatch doesn't apply to them.
            local isRawIcon = style:find("^combat%d") and true or false
            local usable = colorMode == "custom" and style ~= "none" and not isRawIcon
            combatSwatch:SetAlpha(usable and 1 or 0.3)
            if usable then combatSwatchBlock:Hide() else combatSwatchBlock:Show() end
        end
        UpdateSwatchVisibility()
        RegisterWidgetRefresh(UpdateSwatchVisibility)

        -- Cog popup for combat indicator settings
        -- "healthbar" is the long-standing stored value for centered-on-health-bar,
        -- shown as "Center". "center" (briefly stored by 8.4.9-era builds) maps to it.
        local combatPosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["healthbar"]="Center", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["textbar"]="Text Bar", ["portrait"]="Portrait" }
        local combatPosOrder = { "topleft", "topright", "healthbar", "bottomleft", "bottomright", "textbar", "portrait" }

        EllesmereUI.BuildInlineCog(ciRgn, {
            title = "Combat Indicator Settings",
            rows = {
                { type="toggle", label="Class Colored",
                  -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/
                  -- Square = combat0..5) are shown as-is, so class coloring doesn't
                  -- apply to them.
                  disabled=function()
                      local st = SValSupported("combatIndicatorStyle", "class")
                      return st:find("^combat%d") and true or false
                  end,
                  disabledTooltip="Not available for this combat indicator style.", rawTooltip=true,
                  get=function() return SValSupported("combatIndicatorColor", "custom") == "classcolor" end,
                  set=function(v) SSetSupported("combatIndicatorColor", v and "classcolor" or "custom"); ReloadAndUpdate(); UpdatePreview() end },
                { type="dropdown", label="Position", values=combatPosValues, order=combatPosOrder,
                  get=function()
                      local pos = SValSupported("combatIndicatorPosition", "healthbar")
                      if pos == "center" then pos = "healthbar" end
                      return combatPosValues[pos] and pos or "healthbar"
                  end,
                  set=function(v) SSetSupported("combatIndicatorPosition", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Size", min=8, max=64, step=1,
                  get=function() return SValSupported("combatIndicatorSize", 22) end,
                  set=function(v) SSetSupported("combatIndicatorSize", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="X Offset", min=-200, max=200, step=1,
                  get=function() return SValSupported("combatIndicatorX", 0) end,
                  set=function(v) SSetSupported("combatIndicatorX", v); ReloadAndUpdate(); UpdatePreview() end },
                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                  get=function() return SValSupported("combatIndicatorY", 0) end,
                  set=function(v) SSetSupported("combatIndicatorY", v); ReloadAndUpdate(); UpdatePreview() end },
            },
        })
    end
    end -- _showAbsorbsCombat

    -- Preview eye for an indicator row, like the Combat Indicator's: toggles
    -- ns._ufPvEyes[key], which the preview reads. The raid marker picks a
    -- random marker each time it is switched on. (Module-namespace fields,
    -- not locals: this builder is long.)
    ns._ufPvEyes = ns._ufPvEyes or {}
    ns._ufAddPvEye = function(rgn, key, what)
        if EllesmereUI._prebuilding or not rgn then return end
        if optState.selectedUnit ~= "player" and optState.selectedUnit ~= "target" then return end
        local eyes = ns._ufPvEyes
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        rgn._lastInline = eyeBtn
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshEye()
            eyeTex:SetTexture(eyes[key] and EllesmereUI.EYE_INVISIBLE_ICON or EllesmereUI.EYE_VISIBLE_ICON)
        end
        RefreshEye()
        eyeBtn:SetScript("OnClick", function()
            eyes[key] = not eyes[key]
            if key == "raid" and eyes[key] then eyes.raidIndex = math.random(1, 8) end
            RefreshEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, (eyes[key] and "Hide " or "Show ") .. what .. " preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
    end

    -- Row 4: Raid Marker toggle | Icon Size slider + inline directions cog (X/Y)
    local function raidMarkerOff()
        return SValSupported("raidMarkerEnabled", false) == false
    end
    local sharedAddRow4
    sharedAddRow4, h = W:DualRow(parent, y,
        { type="toggle", text="Raid Marker",
          getValue=function() return SValSupported("raidMarkerEnabled", false) end,
          setValue=function(v)
              SSetSupported("raidMarkerEnabled", v)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Marker Size", min=12, max=64, step=1,
          disabled=raidMarkerOff, disabledTooltip="Raid Marker",
          getValue=function() return SValSupported("raidMarkerSize", 28) end,
          setValue=function(v) SSetSupported("raidMarkerSize", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = sharedAddRow4._rightRegion
        local rmPosValues = { ["left"]="Left", ["center"]="Center", ["right"]="Right" }
        local rmPosOrder  = { "left", "center", "right" }
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON, disabled = raidMarkerOff, disabledTooltip = "Raid Marker",
            title = "Raid Marker Settings",
            rows = {
                { type="dropdown", label="Position", values=rmPosValues, order=rmPosOrder,
                  get=function() return SValSupported("raidMarkerAlign", "right") end,
                  set=function(v) SSetSupported("raidMarkerAlign", v) end },
                { type="slider", label="X Offset", min=-200, max=200, step=1,
                  get=function() return SValSupported("raidMarkerX", 0) end,
                  set=function(v) SSetSupported("raidMarkerX", v) end },
                { type="slider", label="Y Offset", min=-200, max=200, step=1,
                  get=function() return SValSupported("raidMarkerY", 0) end,
                  set=function(v) SSetSupported("raidMarkerY", v) end },
            },
        })
    end
    -- Sync icons: Raid Marker (left) and Marker Size (right)
    if not EllesmereUI._prebuilding then
        local rgn = sharedAddRow4._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Raid Marker to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerEnabled
                if v == nil then v = false end
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().raidMarkerEnabled = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerEnabled
                if v == nil then v = false end
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    local ov = UNIT_DB_MAP[key]().raidMarkerEnabled
                    if ov == nil then ov = false end
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
                    local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerEnabled
                    if v == nil then v = false end
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().raidMarkerEnabled = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end
    if not EllesmereUI._prebuilding then
        local rgn = sharedAddRow4._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Marker Size to all Frames",
            onClick = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerSize or 28
                for _, key in ipairs(GROUP_UNIT_ORDER) do UNIT_DB_MAP[key]().raidMarkerSize = v end
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerSize or 28
                for _, key in ipairs(GROUP_UNIT_ORDER) do
                    if (UNIT_DB_MAP[key]().raidMarkerSize or 28) ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return optState.selectedUnit end,
                onApply       = function(checkedKeys)
                    local v = UNIT_DB_MAP[optState.selectedUnit]().raidMarkerSize or 28
                    for _, key in ipairs(checkedKeys) do UNIT_DB_MAP[key]().raidMarkerSize = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    ns._ufAddPvEye(sharedAddRow4._leftRegion, "raid", "raid marker")

    -- Row 5: Leader Indicator toggle | Leader Icon Size slider + inline directions cog (X/Y)
    -- Visible for player and target.
    local sharedAddRow5, BuildLeaderSync
    local function leaderIndOff()
        return SValSupported("leaderIndicatorEnabled", true) == false
    end
    local function leaderIndSupported()
        return optState.selectedUnit == "player" or optState.selectedUnit == "target"
    end
    if leaderIndSupported() then
        local leaderSyncUnits = { "player", "target" }
        sharedAddRow5, h = W:DualRow(parent, y,
            { type="toggle", text="Leader Indicator",
              getValue=function() return SValSupported("leaderIndicatorEnabled", true) end,
              setValue=function(v)
                  SSetSupported("leaderIndicatorEnabled", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Leader Icon Size", min=8, max=48, step=1,
              disabled=leaderIndOff, disabledTooltip="Leader Indicator",
              getValue=function() return SValSupported("leaderIndicatorSize", 16) end,
              setValue=function(v) SSetSupported("leaderIndicatorSize", v) end });  y = y - h
        SApplySupport(sharedAddRow5._leftRegion, "leaderIndicatorEnabled")
        SApplySupport(sharedAddRow5._rightRegion, "leaderIndicatorSize")
        if not EllesmereUI._prebuilding then
            local rgn = sharedAddRow5._rightRegion
            local leaderPosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["portrait"]="Portrait" }
            local leaderPosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            EllesmereUI.BuildInlineCog(rgn, { disabled = leaderIndOff, disabledTooltip = "Leader Indicator",
                title = "Leader Indicator Settings",
                rows = {
                    { type="dropdown", label="Icon Style",
                      tooltip="Art used for the leader crown and the assistant icon.",
                      values={ blizzard = "Blizzard", pixels = "Pixels" }, order={ "blizzard", "pixels" },
                      get=function() return SValSupported("leaderIndicatorStyle", "blizzard") end,
                      set=function(v) SSetSupported("leaderIndicatorStyle", v) end },
                    { type="dropdown", label="Position", values=leaderPosValues, order=leaderPosOrder,
                      get=function() return SValSupported("leaderIndicatorPosition", "topleft") end,
                      set=function(v) SSetSupported("leaderIndicatorPosition", v) end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("leaderIndicatorX", 0) end,
                      set=function(v) SSetSupported("leaderIndicatorX", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("leaderIndicatorY", 0) end,
                      set=function(v) SSetSupported("leaderIndicatorY", v) end },
                },
            })
        end
        -- Player + target sync link; the Faction Indicator row below reuses it.
        BuildLeaderSync = function(rgn, key, default, tooltip)
            local function GetValue(unit)
                local v = UNIT_DB_MAP[unit]()[key]
                if v == nil then return default end
                return v
            end
            EllesmereUI.BuildSyncIcon({
                region = rgn,
                tooltip = tooltip,
                onClick = function()
                    local v = GetValue(optState.selectedUnit)
                    for _, unit in ipairs(leaderSyncUnits) do UNIT_DB_MAP[unit]()[key] = v end
                    ReloadAndUpdate(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = GetValue(optState.selectedUnit)
                    for _, unit in ipairs(leaderSyncUnits) do
                        if GetValue(unit) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys = leaderSyncUnits,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return optState.selectedUnit end,
                    onApply = function(checkedKeys)
                        local v = GetValue(optState.selectedUnit)
                        for _, unit in ipairs(checkedKeys) do UNIT_DB_MAP[unit]()[key] = v end
                        ReloadAndUpdate(); EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        if not EllesmereUI._prebuilding then
        BuildLeaderSync(sharedAddRow5._leftRegion, "leaderIndicatorEnabled", true,
            "Apply Leader Indicator to all Frames")
        BuildLeaderSync(sharedAddRow5._rightRegion, "leaderIndicatorSize", 16,
            "Apply Leader Icon Size to all Frames")
        end
    end

    if sharedAddRow5 then
        ns._ufAddPvEye(sharedAddRow5._leftRegion, "leader", "leader indicator")
    end

    -- Row 5b: Elite/Rare Indicator (+ Show-in-Instances cog) | Icon Size (+ X/Y
    -- cog). Target only (classification is a property of the unit being looked at);
    -- same controls as Leader Indicator above, badge atlases match nameplates.
    if optState.selectedUnit == "target" then
        -- A table on the "wingless" style belongs to the Portrait Dragon
        -- (ns.UF_DragonLegacy): the indicator reads as off and as Badge, and
        -- every setter pins that view over first.
        local function eliteLegacy() return ns.UF_DragonLegacy(SDB()) end
        local function eliteSet(key, v)
            ns.UF_PinLegacyDragon(SDB())
            SSetSupported(key, v)
        end
        local function eliteIndOff()
            return SValSupported("eliteIndicatorEnabled", false) ~= true or eliteLegacy()
        end
        -- The Pixels Dragon style sits on the portrait: Size, Position and the
        -- X/Y offsets apply to the Badge style only. The stock styles always
        -- draw the Badge.
        local function eliteDragon()
            return not eliteLegacy() and SValSupported("eliteIndicatorStyle", "badge") ~= "badge"
                and not EllesmereUI.BlizzStyle.Get("unitframes")
        end
        local eliteRow
        eliteRow, h = W:DualRow(parent, y,
            { type="toggle", text="Elite/Rare Indicator",
              tooltip="Marks elite, rare elite and rare targets; the Pixels Dragon style also marks players.",
              getValue=function() return not eliteIndOff() end,
              setValue=function(v)
                  eliteSet("eliteIndicatorEnabled", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Elite Icon Size", min=8, max=48, step=1,
              disabled=function() return eliteIndOff() or eliteDragon() end,
              disabledTooltip=function()
                  if eliteIndOff() then return "Elite/Rare Indicator" end
                  return "This option only applies to the Badge style."
              end,
              getValue=function() return SValSupported("eliteIndicatorSize", 16) end,
              setValue=function(v) eliteSet("eliteIndicatorSize", v) end });  y = y - h
        SApplySupport(eliteRow._leftRegion, "eliteIndicatorEnabled")
        SApplySupport(eliteRow._rightRegion, "eliteIndicatorSize")
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(eliteRow._leftRegion, { disabled = eliteIndOff, disabledTooltip = "Elite/Rare Indicator",
                title = "Elite/Rare Indicator",
                rows = {
                    { type="toggle", label="Show in Instances",
                      tooltip="Also show the badge in dungeons and raids, where most enemies are elite.",
                      get=function() return SValSupported("eliteIndicatorShowInInstances", false) == true end,
                      set=function(v) eliteSet("eliteIndicatorShowInInstances", v) end },
                },
            })
        end
        if not EllesmereUI._prebuilding then
            local elitePosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["portrait"]="Portrait" }
            local elitePosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            local function stockStyle() return EllesmereUI.BlizzStyle.Get("unitframes") end
            local function stockStyleTip() return EllesmereUI.BlizzStyle.Label("unitframes") end
            local badgeOnly = "This option only applies to the Badge style."
            EllesmereUI.BuildInlineCog(eliteRow._rightRegion, { disabled = eliteIndOff, disabledTooltip = "Elite/Rare Indicator",
                title = "Elite/Rare Indicator Settings",
                rows = {
                    { type="dropdown", label="Style",
                      tooltip="Badge shows a small icon; Pixels Dragon wraps the portrait in classification art.",
                      values={ badge = "Badge", pixelsDragon = "Pixels Dragon" },
                      order={ "badge", "pixelsDragon" },
                      disabled=stockStyle, disabledTooltip=stockStyleTip, requireState="disabled",
                      get=function()
                          if eliteLegacy() then return "badge" end
                          return SValSupported("eliteIndicatorStyle", "badge")
                      end,
                      -- Only dims or lifts the Badge-only controls.
                      set=function(v)
                          eliteSet("eliteIndicatorStyle", v)
                          EllesmereUI:RefreshPage()
                      end },
                    { type="dropdown", label="Position", values=elitePosValues, order=elitePosOrder,
                      disabled=eliteDragon, disabledTooltip=badgeOnly, rawTooltip=true,
                      get=function() return SValSupported("eliteIndicatorPosition", "topleft") end,
                      set=function(v) eliteSet("eliteIndicatorPosition", v) end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      disabled=eliteDragon, disabledTooltip=badgeOnly, rawTooltip=true,
                      get=function() return SValSupported("eliteIndicatorX", 0) end,
                      set=function(v) eliteSet("eliteIndicatorX", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      disabled=eliteDragon, disabledTooltip=badgeOnly, rawTooltip=true,
                      get=function() return SValSupported("eliteIndicatorY", 0) end,
                      set=function(v) eliteSet("eliteIndicatorY", v) end },
                },
            })
        end
        ns._ufAddPvEye(eliteRow._leftRegion, "elite", "elite/rare indicator")
        parent._ufEliteRow = eliteRow
    end

    -- Row 5c: Faction Indicator (mode + filters cog) | Icon Size (+ position cog).
    -- Player and target. On the player frame it is a PvP-flagged indicator
    -- (PvP Flag defaults to Flagged Only there); Opposite Faction and Players
    -- Only are target-only.
    if optState.selectedUnit == "player" or optState.selectedUnit == "target" then
        local isTarget = optState.selectedUnit == "target"
        local function factionIndOff()
            return SValSupported("factionIndicatorMode", "off") == "off"
        end
        local modeValues, modeOrder
        if isTarget then
            modeValues = { off = "Off", always = "Always", opposite = "Opposite Faction" }
            modeOrder = { "off", "always", "opposite" }
        else
            modeValues = { off = "Off", always = "On" }
            modeOrder = { "off", "always" }
        end
        local factionRow
        factionRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Faction Indicator", values=modeValues, order=modeOrder,
              getValue=function()
                  local v = SValSupported("factionIndicatorMode", "off")
                  if not isTarget and v == "opposite" then v = "always" end
                  return v
              end,
              setValue=function(v)
                  SSetSupported("factionIndicatorMode", v)
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Faction Icon Size", min=8, max=48, step=1,
              disabled=factionIndOff, disabledTooltip="Faction Indicator",
              getValue=function() return SValSupported("factionIndicatorSize", 18) end,
              setValue=function(v) SSetSupported("factionIndicatorSize", v) end });  y = y - h
        SApplySupport(factionRow._leftRegion, "factionIndicatorMode")
        SApplySupport(factionRow._rightRegion, "factionIndicatorSize")
        if not EllesmereUI._prebuilding then
            local pvpValues = { dim = "Dim Unflagged", only = "Flagged Only", ignore = "Ignore" }
            local pvpOrder = { "dim", "only", "ignore" }
            local pvpDefault = isTarget and "dim" or "only"
            local rows = {
                { type="dropdown", label="PvP Flag", values=pvpValues, order=pvpOrder,
                  get=function() return SValSupported("factionIndicatorPvP", pvpDefault) end,
                  set=function(v) SSetSupported("factionIndicatorPvP", v) end },
            }
            if isTarget then
                rows[#rows + 1] = { type="toggle", label="Players Only",
                  tooltip="Hide the faction badge on faction NPCs such as guards.",
                  get=function() return SValSupported("factionIndicatorPlayersOnly", false) == true end,
                  set=function(v) SSetSupported("factionIndicatorPlayersOnly", v) end }
            end
            EllesmereUI.BuildInlineCog(factionRow._leftRegion, { disabled = factionIndOff, disabledTooltip = "Faction Indicator",
                title = "Faction Indicator",
                rows = rows,
            })
        end
        if not EllesmereUI._prebuilding then
            local factionPosValues = { ["topleft"]="Top Left", ["topright"]="Top Right", ["bottomleft"]="Bottom Left", ["bottomright"]="Bottom Right", ["portrait"]="Portrait" }
            local factionPosOrder = { "topleft", "topright", "bottomleft", "bottomright", "portrait" }
            EllesmereUI.BuildInlineCog(factionRow._rightRegion, { disabled = factionIndOff, disabledTooltip = "Faction Indicator",
                title = "Faction Indicator Settings",
                rows = {
                    { type="dropdown", label="Icon Style",
                      values=EllesmereUI.FACTION_ART_LABELS, order=EllesmereUI.FACTION_ART_ORDER,
                      get=function() return SValSupported("factionIndicatorStyle", "pvp") end,
                      set=function(v) SSetSupported("factionIndicatorStyle", v) end },
                    { type="dropdown", label="Position", values=factionPosValues, order=factionPosOrder,
                      get=function() return SValSupported("factionIndicatorPosition", "topright") end,
                      set=function(v) SSetSupported("factionIndicatorPosition", v) end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("factionIndicatorX", 0) end,
                      set=function(v) SSetSupported("factionIndicatorX", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return SValSupported("factionIndicatorY", 0) end,
                      set=function(v) SSetSupported("factionIndicatorY", v) end },
                },
            })
        end
        -- Size only: the player's mode list (Off/On) differs from the target's
        -- (with Opposite Faction), so the mode has no clean cross-frame copy.
        if not EllesmereUI._prebuilding then
            BuildLeaderSync(factionRow._rightRegion, "factionIndicatorSize", 18,
                "Apply Faction Icon Size to all Frames")
        end
        ns._ufAddPvEye(factionRow._leftRegion, "faction", "faction indicator")
        parent._ufFactionRow = factionRow
    end

    return y, sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5
end
