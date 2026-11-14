if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayBars_Options.lua
--  Nameplates options: the Health and Cast Bar, Cast Colors and Effects, Class
--  Resource and General Text sections of the Display page. Called by
--  BuildDisplayPage after DisplayLayout_Options.lua; returns y and the rows
--  its click navigation maps to. Shared helpers come from ns._NPO_OptEnv, the
--  per-build helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- The options page frame pool (EllesmereUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local function BuildDisplayBars(parent, y, ctx)
    local env = ns._NPO_OptEnv
    local BAR_W, DB, DBColor, DBVal = env.BAR_W, env.DB, env.DBColor, env.DBVal
    local defaults, displayCastIcons, npImpCastGlowDesc, optState = env.defaults, env.displayCastIcons, env.npImpCastGlowDesc, env.optState
    local pairs, plates, PP, RefreshAllPlates = env.pairs, env.plates, env.PP, env.RefreshAllPlates
    local SECTION_CASTBAR, UpdatePreview, npCastTargetGlowDesc = env.SECTION_CASTBAR, env.UpdatePreview, env.npCastTargetGlowDesc
    local asFallback, atFallback, AuraDurationVal, CogPopupOpen = ctx.asFallback, ctx.atFallback, ctx.AuraDurationVal, ctx.CogPopupOpen
    local LiveApplyAuraText, ShowCogPopup = ctx.LiveApplyAuraText, ctx.ShowCogPopup
    local timerPosOrder, timerPosValues = ctx.timerPosOrder, ctx.timerPosValues
    local W = ctx.W
    local _, h

    -----------------------------------------------------------------------
    --  HEALTH BAR
    -----------------------------------------------------------------------
    local healthBarHeader
    healthBarHeader, h = W:SectionHeader(parent, "HEALTH AND CAST BAR", y);  y = y - h

    local healthBarHeightRow
    healthBarHeightRow, h = W:DualRow(parent, y,
        { type="slider", text="Health Bar Width", min=100, max=BAR_W+100, step=1,
          getValue=function() return BAR_W + DBVal("healthBarWidth") end,
          setValue=function(v)
            local extra = v - BAR_W
            DB().healthBarWidth = extra
            -- Classic WoW UI: the cast bar's width and shift are derived
            -- from the footprint so the two borders stay edge to edge, so
            -- it re-lays out rather than taking the raw width.
            local classic = ns.NP_Classic and ns.NP_Classic()
            -- Pooled plates re-run their appearance pass at next spawn.
            ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
            for _, plate in pairs(plates) do
                PP.Width(plate.health, v)
                PP.Width(plate.absorb, v)
                PP.Width(plate.absorbForward, v)
                if classic then
                    ns.LayoutCastBar(plate, v, ns.GetCastBarHeight())
                else
                    PP.Width(plate.cast, v)
                end
                plate:UpdateNameWidth()
            end
            if ns.ApplyNamePlateClickArea then ns.ApplyNamePlateClickArea() end
            UpdatePreview()
          end },
        { type="slider", text="Health Bar Height", min=6, max=50, step=1,
          getValue=function() return DBVal("healthBarHeight") end,
          setValue=function(v)
            DB().healthBarHeight = v
            -- Classic WoW UI: the border scales with the bar, and the cast
            -- bar's drop and width are derived from the health bar's
            -- height, so both re-run here.
            local classic = ns.NP_Classic and ns.NP_Classic()
            local forever = ns.NP_Forever()
            -- Pooled plates re-run their appearance pass (and with it
            -- the border and level box) at next spawn.
            ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
            for _, plate in pairs(plates) do
                PP.Height(plate.health, v)
                if classic then
                    ns.NP_ApplyClassicHealthArt(plate, v)
                    ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), ns.GetCastBarHeight())
                elseif forever then
                    -- WoW Forever: the level box follows the bar's height.
                    ns.NP_ApplyForeverLevelBox(plate, v)
                end
            end
            if ns.ApplyNamePlateClickArea then ns.ApplyNamePlateClickArea() end
            UpdatePreview()
          end });  y = y - h

    local function castIconOff() return DB() and DB().showCastIcon == false end

    local castBarHeightRow
    castBarHeightRow, h = W:DualRow(parent, y,
        { type="slider", text="Cast Bar Height", min=10, max=40, step=1,
          getValue=function() return DBVal("castBarHeight") or defaults.castBarHeight end,
          setValue=function(v)
            DB().castBarHeight = v
            local barW = ns.GetHealthBarWidth()
            for _, plate in pairs(plates) do
                ns.LayoutCastBar(plate, barW, v)
                ns.LayoutCastIcon(plate, v)
                plate.castSpark:SetHeight(v)
            end
            UpdatePreview()
          end },
        { type="toggle", text="Spell Icon",
          getValue=function()
            local db = DB()
            if db and db.showCastIcon ~= nil then return db.showCastIcon end
            return defaults.showCastIcon
          end,
          setValue=function(v)
            DB().showCastIcon = v
            ns.RefreshAllSettings()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end });  y = y - h
    local showCastIconRow = castBarHeightRow

    -- Inline cog on Spell Icon (right region) for Scale
    if not EllesmereUI._prebuilding then
        local rightRgn = castBarHeightRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            anchorTo = rightRgn._control,
            disabled = castIconOff,
            disabledTooltip = "Spell Icon",
            title = "Spell Icon Settings",
            rows = {
                -- Classic WoW UI seats the icon in the vanilla border's own plate:
                -- size, side, in-width and full-size are the art's (offsets stay).
                { type="slider", label="Scale", min=0.5, max=2, step=0.1,
                  disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
                  requireState="disabled",
                  get=function() return DBVal("castIconScale") or defaults.castIconScale end,
                  set=function(v)
                    DB().castIconScale = v
                    if not (DB() and DB().castIconFullSize) then
                        for _, plate in pairs(plates) do
                            plate.castIconFrame:SetScale(v)
                            -- a cast glow art showing on the plate goes around the resized icon
                            ns.NP_PlaceCastGlowArt(plate)
                        end
                    end
                    UpdatePreview()
                  end },
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return DBVal("castIconOffsetX") or defaults.castIconOffsetX or 0 end,
                  set=function(v)
                    DB().castIconOffsetX = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                  get=function() return DBVal("castIconOffsetY") or defaults.castIconOffsetY or 0 end,
                  set=function(v)
                    DB().castIconOffsetY = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="toggle", label="Make Icon Part of the Bar",
                  tooltip="This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                  disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
                  requireState="disabled",
                  get=function()
                    local db = DB()
                    if db and db.castbarIconInWidth ~= nil then return db.castbarIconInWidth end
                    return defaults.castbarIconInWidth
                  end,
                  set=function(v)
                    DB().castbarIconInWidth = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="toggle", label="Icon on Right",
                  tooltip="Place the cast bar spell icon on the right side of the bars instead of the left.",
                  disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
                  requireState="disabled",
                  get=function()
                    local db = DB()
                    if db and db.castIconOnRight ~= nil then return db.castIconOnRight end
                    return defaults.castIconOnRight
                  end,
                  set=function(v)
                    DB().castIconOnRight = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="toggle", label="Full Sized (Health + Cast Bar)",
                  tooltip="Make the spell icon a large square the combined height of the health bar plus the cast bar, flush with the top of the health bar and the bottom of the cast bar.",
                  disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
                  disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
                  requireState="disabled",
                  get=function()
                    local db = DB()
                    if db and db.castIconFullSize ~= nil then return db.castIconFullSize end
                    return defaults.castIconFullSize
                  end,
                  set=function(v)
                    DB().castIconFullSize = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="toggle", label="Hide Border",
                  tooltip="Hide the 1-pixel border around the cast bar spell icon.",
                  disabled=function() return EllesmereUI.BlizzStyle.Get("nameplates") end,
                  get=function()
                    local db = DB()
                    if db and db.hideCastIconBorder ~= nil then return db.hideCastIconBorder and true or false end
                    return false
                  end,
                  set=function(v)
                    DB().hideCastIconBorder = v and true or false
                    ns.RefreshAllSettings()
                    UpdatePreview()
                  end },
                { type="toggle", label="Use Target Border Color",
                  tooltip="Colors your target's custom spell icon border, or a full-size wrapped 1-pixel one, with the target border color.",
                  get=function()
                    local db = DB()
                    if db and db.castIconTargetBorder ~= nil then return db.castIconTargetBorder end
                    return defaults.castIconTargetBorder
                  end,
                  set=function(v)
                    DB().castIconTargetBorder = v
                    ns.ApplyBorderWrapToAll()
                    -- The custom spell icon border (Icon Borders cog) takes the tint too.
                    if DBVal("castIconCustomBorder") == true then
                        for _, plate in pairs(plates) do ns.ApplyCastIconBorder(plate) end
                    end
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Cast Background Opacity (+ swatch) | Cast Bar Border (+ swatch)
    local castBgRow
    castBgRow, h = W:DualRow(parent, y,
        ns.NP_BlizzOnlyGate({ type="slider", text="Cast Background", min=0, max=100, step=1,
          getValue=function()
            return math.floor(((DBVal("castBgAlpha") or defaults.castBgAlpha) * 100) + 0.5)
          end,
          setValue=function(v)
            DB().castBgAlpha = v / 100
            local c = (DB() and DB().castBgColor) or defaults.castBgColor
            for _, plate in pairs(plates) do
                plate.castBG:SetColorTexture(c.r, c.g, c.b, v / 100)
            end
            UpdatePreview()
          end }),
        EllesmereUI.BlizzStyle.Gate("nameplates", { type="slider", text="Cast Bar Border", min=0, max=4, step=1,
          tooltip="Pixel-perfect border around the cast bar. Set to 0 for no border.",
          getValue=function() return DBVal("castBorderSize") or defaults.castBorderSize end,
          setValue=function(v)
            DB().castBorderSize = v
            ns.RefreshCastBorder()
            UpdatePreview()
          end }));  y = y - h
    if not EllesmereUI._prebuilding then
        local leftRgn = castBgRow._leftRegion
        local castBgColorGet = function()
            local c = (DB() and DB().castBgColor) or defaults.castBgColor
            return c.r, c.g, c.b
        end
        local castBgColorSet = function(r, g, b)
            DB().castBgColor = { r = r, g = g, b = b }
            local a = DBVal("castBgAlpha") or defaults.castBgAlpha
            for _, plate in pairs(plates) do
                plate.castBG:SetColorTexture(r, g, b, a)
            end
            UpdatePreview()
        end
        local castBgSwatch, castBgUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, castBgColorGet, castBgColorSet, nil, 20)
        PP.Point(castBgSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = castBgSwatch
        EllesmereUI.RegisterWidgetRefresh(function() castBgUpdateSwatch() end)
        if ns.NP_BlizzOnly() then EllesmereUI.BlizzStyle.BlockInline("nameplates", castBgSwatch) end
    end
    -- Inline color swatch on Cast Bar Border (right region)
    if not EllesmereUI._prebuilding then
        local rightRgn = castBgRow._rightRegion
        local castBorderColorGet = function()
            local c = (DB() and DB().castBorderColor) or defaults.castBorderColor
            return c.r, c.g, c.b
        end
        local castBorderColorSet = function(r, g, b)
            DB().castBorderColor = { r = r, g = g, b = b }
            ns.RefreshCastBorderColor()
            UpdatePreview()
        end
        local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, castBorderColorGet, castBorderColorSet, nil, 20)
        PP.Point(cbSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        rightRgn._lastInline = cbSwatch
        EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        EllesmereUI.BlizzStyle.BlockInline("nameplates", cbSwatch)
    end

    -- Cast Timer: position dropdown (None/Right/Left), styled like the duration dropdowns. "None" hides it; Right/Left choose the side (reserving space, pushing shared-side cast text); Size/X/Y live in the inline cog.
    local castTimerRow
    castTimerRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Cast Timer",
          values={ none = "None", right = "Right", left = "Left" },
          order={ "none", "right", "left" },
          getValue=function()
            local db = DB()
            local shown = defaults.showCastTimer
            if db and db.showCastTimer ~= nil then shown = db.showCastTimer end
            if not shown then return "none" end
            return (db and db.castTimerSide) or defaults.castTimerSide
          end,
          setValue=function(v)
            if v == "none" then
                DB().showCastTimer = false
            else
                DB().showCastTimer = true
                DB().castTimerSide = v
            end
            ns.RefreshAllSettings()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Cast Bar Y Offset", min=-25, max=75, step=1,
          tooltip="Nudge the cast bar up or down from its default spot under the health bar.",
          getValue=function() return DBVal("castBarOffsetY") or defaults.castBarOffsetY end,
          setValue=function(v)
            DB().castBarOffsetY = v
            ns.NP_RelayoutCastBars()
            UpdatePreview()
          end });  y = y - h
    if not EllesmereUI._prebuilding then
        local leftRgn = castTimerRow._leftRegion
        local ctColorGet = function()
            local c = (DB() and DB().castTimerColor) or defaults.castTimerColor
            return c.r, c.g, c.b
        end
        local ctColorSet = function(r, g, b)
            DB().castTimerColor = { r = r, g = g, b = b }
            for _, plate in pairs(plates) do
                if plate.castTimer then plate.castTimer:SetTextColor(r, g, b, 1) end
            end
            UpdatePreview()
        end

        -- Inline cog for Cast Timer Size / X / Y
        EllesmereUI.BuildInlineCog(leftRgn, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = EllesmereUI.L("Cast Timer Settings"),
                    xGet = function() return DBVal("castTimerOffsetX") or defaults.castTimerOffsetX end,
                    xSet = function(v) DB().castTimerOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    yGet = function() return DBVal("castTimerOffsetY") or defaults.castTimerOffsetY end,
                    ySet = function(v) DB().castTimerOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeGet = function() return DBVal("castTimerSize") or defaults.castTimerSize end,
                    sizeSet = function(v) DB().castTimerSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                    sizeFirst = true,
                })
            end,
        })
        local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ctColorGet, ctColorSet, nil, 20)
        PP.Point(ctSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = ctSwatch
        EllesmereUI.RegisterWidgetRefresh(function() ctUpdateSwatch() end)

        -- Inline cog on Cast Bar Y Offset (right region) for X Offset. The offset stands
        -- down only while the wrap can draw: with no border to wrap (a stock style, Border
        -- None), a saved Wrap Around Castbar holds nothing back and the cog stays live.
        local rightRgn = castTimerRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            anchorTo = rightRgn._control,
            disabled = function() return ns.NP_WrapCanDraw() end,
            disabledTooltip = "Wrap Around Castbar",
            requireState = "disabled",
            title = EllesmereUI.L("Cast Bar Position"),
            rows = {
                { type="slider", label="X Offset", min=-50, max=50, step=1,
                  get=function() return DBVal("castBarOffsetX") or defaults.castBarOffsetX end,
                  set=function(v)
                    DB().castBarOffsetX = v
                    ns.NP_RelayoutCastBars()
                    UpdatePreview()
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CAST COLORS AND EFFECTS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_CASTBAR, y);  y = y - h

    -- Cast Color ---- Kick Ready Mid-Cast Hint
    local kickHintValues = { none = "None", tick = "Tick", tickbar = "Tick + Bar" }
    local kickHintOrder = { "none", "tick", "tickbar" }
    local castColorRow
    castColorRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Cast Color",
          swatches = {
            ns.NP_BlizzOnlyGate({ tooltip = "Interruptible Cast",
              getValue = function() return DBColor("castBar") end,
              setValue = function(r, g, b)
                DB().castBar = { r = r, g = g, b = b }
                RefreshAllPlates(); UpdatePreview()
              end }),
            { tooltip = "Interrupt on CD",
              getValue = function() return DBColor("interruptReady") end,
              setValue = function(r, g, b)
                DB().interruptReady = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            ns.NP_BlizzOnlyGate({ tooltip = "Uninterruptible Cast",
              getValue = function() return DBColor("castBarUninterruptible") end,
              setValue = function(r, g, b)
                DB().castBarUninterruptible = { r = r, g = g, b = b }
                RefreshAllPlates()
              end }),
            { tooltip = "Important Cast",
              getValue = function() return DBColor("castBarImportant") end,
              setValue = function(r, g, b)
                DB().castBarImportant = { r = r, g = g, b = b }
                RefreshAllPlates()
              end,
              disabled = function()
                local db = DB()
                local on = db and db.importantCastColorEnabled
                if on == nil then on = defaults.importantCastColorEnabled end
                return not on
              end,
              disabledTooltip = "Important Cast Color" },
          } },
        { type="dropdown", text="Kick Ready Mid-Cast Hint",
          values=kickHintValues, order=kickHintOrder,
          tooltip="Shows where your interrupt will be ready during an enemy cast. \"Tick\" marks the exact spot on the cast bar; \"Tick + Bar\" also colours the window during which your interrupt will be available.",
          getValue=function()
            -- View over two underlying toggles (kickTickEnabled + interruptMidCastEnabled) so nothing migrates: tick off -> None, tick on -> Tick, tick+bar on -> Tick + Bar. Tick defaults true, so a fresh user reads "Tick".
            local db = DB()
            local tick = true
            if db and db.kickTickEnabled ~= nil then tick = db.kickTickEnabled end
            local bar = defaults.interruptMidCastEnabled
            if db and db.interruptMidCastEnabled ~= nil then bar = db.interruptMidCastEnabled end
            if not tick then return "none" end
            if bar then return "tickbar" end
            return "tick"
          end,
          setValue=function(v)
            local db = DB()
            if v == "none" then
                db.kickTickEnabled = false
                db.interruptMidCastEnabled = false
            elseif v == "tickbar" then
                db.kickTickEnabled = true
                db.interruptMidCastEnabled = true
            else
                db.kickTickEnabled = true
                db.interruptMidCastEnabled = false
            end
            ns.RefreshAllSettings()
            -- Rebuild so the inline mid-cast colour swatch greys/ungreys.
            C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
          end });  y = y - h

    -- Inline mid-cast colour swatch on the Hint dropdown; greys out unless "Tick + Bar" is selected, since the colour only applies to the bar.
    if not EllesmereUI._prebuilding then
        local rightRgn = castColorRow._rightRegion
        local ctrl = rightRgn and rightRgn._control
        if ctrl and EllesmereUI.BuildColorSwatch then
            local function midColorOff()
                local db = DB()
                local on = db and db.interruptMidCastEnabled
                if on == nil then on = defaults.interruptMidCastEnabled end
                return not on
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rightRgn, castColorRow:GetFrameLevel() + 3,
                function()
                    local c = DB().interruptMidCastColor or defaults.interruptMidCastColor
                    return c.r, c.g, c.b
                end,
                function(r, g, b)
                    DB().interruptMidCastColor = { r = r, g = g, b = b }
                    ns.RefreshAllSettings()
                end, nil, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
            rightRgn._lastInline = swatch
            swatch:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, "Interrupt Ready Mid-Cast") end)
            swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = midColorOff()
                swatch:SetAlpha(off and 0.15 or 1)
                swatch:EnableMouse(not off)
                updateSwatch()
            end)
            swatch:SetAlpha(midColorOff() and 0.15 or 1)
            swatch:EnableMouse(not midColorOff())
        end
    end

    -- Inline cog beside the Cast Color swatches: Show Shield Icon
    if not EllesmereUI._prebuilding then
        local rgn = castColorRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            tip = "Cast Color Settings",
            title = "Cast Color",
            rows = {
                { type = "toggle", label = "Show Shield Icon",
                  tooltip = "Show a shield icon on the cast bar when an enemy's cast cannot be interrupted.",
                  get = function()
                    local db = DB()
                    if db and db.castBarShieldEnabled ~= nil then return db.castBarShieldEnabled end
                    return defaults.castBarShieldEnabled
                  end,
                  set = function(v)
                    DB().castBarShieldEnabled = v
                    RefreshAllPlates()
                  end },
                { type = "toggle", label = "Show Spark",
                  tooltip = "Show the bright spark at the leading edge of the cast bar fill.",
                  get = function()
                    local db = DB()
                    if db and db.castBarSparkEnabled ~= nil then return db.castBarSparkEnabled end
                    return defaults.castBarSparkEnabled ~= false
                  end,
                  set = function(v)
                    DB().castBarSparkEnabled = v
                    for _, plate in pairs(plates) do
                        if plate.castSpark then plate.castSpark:SetShown(v ~= false) end
                    end
                    UpdatePreview()
                  end },
                { type = "toggle", label = "Important Cast Color",
                  tooltip = "Tint the cast bar with the Important colour when the enemy casts a spell the game flags as important.",
                  get = function()
                    local db = DB()
                    if db and db.importantCastColorEnabled ~= nil then return db.importantCastColorEnabled end
                    return defaults.importantCastColorEnabled
                  end,
                  set = function(v)
                    DB().importantCastColorEnabled = v
                    RefreshAllPlates()
                    EllesmereUI:RefreshPage()
                  end },
                { type = "toggle", label = "Interruptible While Kick Ready",
                  tooltip = "While your interrupt is ready, important casts keep the Interruptible color.",
                  get = function()
                    local db = DB()
                    if db and db.importantCastKickReadyAsInterruptible ~= nil then return db.importantCastKickReadyAsInterruptible end
                    return defaults.importantCastKickReadyAsInterruptible
                  end,
                  set = function(v)
                    DB().importantCastKickReadyAsInterruptible = v
                    RefreshAllPlates()
                  end,
                  disabled = function()
                    local db = DB()
                    local on = db and db.importantCastColorEnabled
                    if on == nil then on = defaults.importantCastColorEnabled end
                    return not on
                  end,
                  disabledTooltip = "Important Cast Color" },
            },
        })
    end

    -- Important Cast Glow | Cast Targets You Glow: shared glow controls (cast bar = bar
    -- host) + preview
    do
        local GO = EllesmereUI.GlowOptions
        local impDesc = npImpCastGlowDesc

        local impGlowRow
        impGlowRow, h = W:DualRow(parent, y,
            GO.DropdownSpec(impDesc, "Important Cast Glow",
                "Show a glow on the cast bar when the enemy is casting a spell Blizzard marks as important."),
            GO.DropdownSpec(npCastTargetGlowDesc, "Cast Targets You Glow",
                "Show a glow on the cast bar when the enemy's cast is targeting you."));  y = y - h

        if not EllesmereUI._prebuilding then
            -- Icon-sized preview in each inline chain; -12: the widest FlipBook
            -- styles overhang ~8px per side.
            local function AttachGlow(rgn, desc)
                GO.AttachInline(rgn, desc)
                local pv = GO.BuildPreview(rgn, desc, {
                    bar = false, width = 26, height = 26,
                    icon = function() return displayCastIcons[optState._previewCastIconIdx or 1] end,
                    anchor = rgn._lastInline, x = -12,
                })
                if pv then
                    pv:SetFrameLevel(rgn:GetFrameLevel() + 5)
                    rgn._lastInline = pv
                end
            end
            AttachGlow(impGlowRow._leftRegion, impDesc)
            AttachGlow(impGlowRow._rightRegion, npCastTargetGlowDesc)
        end
    end

    -- Row 3: Focus Text Reminders (CDM only, left) | Show Interrupted Flash Effect (always present, a core cast bar setting): when CDM is loaded, Focus Text Reminders fills the left slot and flash takes the right; otherwise flash takes the left slot itself.
    -- Casts In Front of Nameplates follows in the next free slot.
    do
        local inFrontCfg = { type="toggle", text="Casts In Front of Nameplates",
            tooltip="Forces all casts to be shown in front of nameplates for visual clarity",
            getValue=function() return DBVal("castOverlayEnabled") == true end,
            setValue=function(v)
                DB().castOverlayEnabled = v
                ns.RefreshAllSettings()
            end }
        local function flashOff()
            local db = DB()
            local on = db and db.interruptedFlashEnabled
            if on == nil then on = defaults.interruptedFlashEnabled end
            return not on
        end
        local flashCfg = {
            type = "toggle", text = "Show Interrupted Flash Effect",
            tooltip = "Flash the enemy's cast bar and show \"Interrupted\" for a moment when their cast is interrupted. Use the swatch to change the flash colour.",
            getValue = function()
                local db = DB()
                if db and db.interruptedFlashEnabled ~= nil then return db.interruptedFlashEnabled end
                return defaults.interruptedFlashEnabled
            end,
            setValue = function(v)
                DB().interruptedFlashEnabled = v
                RefreshAllPlates()
                -- Rebuild so the inline flash colour swatch greys/ungreys.
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
            end,
        }

        local row3, swatchRegion
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager") then
            -- Access the FocusKick bar config in CDM's profile data
            local function GetFocusKickBar()
                local cdmDb = _G._ECME_AceDB
                local p = cdmDb and cdmDb.profile
                local bars = p and p.cdmBars and p.cdmBars.bars
                if not bars then return nil end
                for _, b in ipairs(bars) do
                    if b.key == "focuskick" then return b end
                end
                return nil
            end
            row3, h = W:DualRow(parent, y,
                { type="toggle", text="Focus Text Reminders",
                  tooltip = "Display the word \"FOCUS\" below caster/miniboss mobs in M+ if you have not set your focus. This is the same setting as in the FocusKick bar options. Disabled for specs with no kick.",
                  getValue = function()
                      local fk = GetFocusKickBar()
                      return fk and fk.focusReminderEnabled == true
                  end,
                  setValue = function(v)
                      local fk = GetFocusKickBar()
                      if fk then fk.focusReminderEnabled = v end
                      if _G._ECME_RefreshFocusReminders then
                          _G._ECME_RefreshFocusReminders()
                      end
                      EllesmereUI:RefreshPage()
                  end },
                flashCfg
            );  y = y - h
            swatchRegion = row3._rightRegion
            _, h = W:DualRow(parent, y, inFrontCfg, EllesmereUI.BlankRowCfg());  y = y - h
        else
            row3, h = W:DualRow(parent, y,
                flashCfg,
                inFrontCfg
            );  y = y - h
            swatchRegion = row3._leftRegion
        end

        -- Inline flash colour swatch on the Show Interrupted Flash Effect toggle; greys out when disabled.
        if not EllesmereUI._prebuilding then
            local rgn = swatchRegion
            local ctrl = rgn and rgn._control
            if ctrl and EllesmereUI.BuildColorSwatch then
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, row3:GetFrameLevel() + 3,
                    function()
                        local c = DB().interruptedFlashColor or defaults.interruptedFlashColor
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        DB().interruptedFlashColor = { r = r, g = g, b = b }
                        RefreshAllPlates()
                    end, nil, 20)
                PP.Point(swatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -12, 0)
                rgn._lastInline = swatch
                swatch:SetScript("OnEnter", function(s) EllesmereUI.ShowWidgetTooltip(s, "Interrupted Flash Colour") end)
                swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                -- Blizzard Style uses the stock interrupted fill art, so the flash colour is
                -- inert there: the build and every refresh grey the swatch out alike.
                local function ApplyFlashSwatchState()
                    local off = flashOff() or ns.NP_BlizzOnly()
                    swatch:SetAlpha(off and 0.15 or 1)
                    swatch:EnableMouse(not off)
                end
                EllesmereUI.RegisterWidgetRefresh(function()
                    ApplyFlashSwatchState()
                    updateSwatch()
                end)
                ApplyFlashSwatchState()
            end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CLASS RESOURCE
    -----------------------------------------------------------------------
    local classResourceHeader
    classResourceHeader, h = W:SectionHeader(parent, "CLASS RESOURCE", y);  y = y - h

    local function classPowerDisabled() return DBVal("showClassPower") ~= true end

    local classResourceSectionTop = y  -- track top of content rows

    local classResourceToggleRow
    classResourceToggleRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Class Resource",
          getValue=function() return DBVal("showClassPower") == true end,
          -- DependentSetValue: Rows 2-4 below are hidden while class resource is off; the flip forces the full rebuild.
          setValue=EllesmereUI.DependentSetValue(
              function() return DBVal("showClassPower") == true end,
              function(v)
                DB().showClassPower = v
                ns.ApplyClassPowerSetting(); UpdatePreview()
                EllesmereUI:RefreshPage()
              end) },
        { type="multiSwatch", text="Fill Color",
          disabled=classPowerDisabled,
          disabledTooltip="Show Class Resource",
          swatches = {
            { tooltip = "Custom Color",
              disabled = classPowerDisabled,
              disabledTooltip = "Show Class Resource",
              getValue = function()
                  local c = (DB() and DB().classPowerCustomColor) or defaults.classPowerCustomColor
                  return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                  DB().classPowerCustomColor = { r = r, g = g, b = b }
                  ns.RefreshClassPower(); UpdatePreview()
              end,
              onClick = function(self)
                  local v = DBVal("classPowerClassColors")
                  if v == nil then v = defaults.classPowerClassColors end
                  if v then
                      DB().classPowerClassColors = false
                      ns.RefreshClassPower(); UpdatePreview()
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local v = DBVal("classPowerClassColors")
                  if v == nil then v = defaults.classPowerClassColors end
                  return v and 0.3 or 1
              end },
            { tooltip = "Class Color",
              disabled = classPowerDisabled,
              disabledTooltip = "Show Class Resource",
              getValue = function()
                  local _, ct = UnitClass("player")
                  if ct and RAID_CLASS_COLORS[ct] then
                      local cc = RAID_CLASS_COLORS[ct]
                      return cc.r, cc.g, cc.b, 1
                  end
                  return 1, 1, 1, 1
              end,
              setValue = function() end,
              onClick = function()
                  DB().classPowerClassColors = true
                  ns.RefreshClassPower(); UpdatePreview()
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local v = DBVal("classPowerClassColors")
                  if v == nil then v = defaults.classPowerClassColors end
                  return v and 1 or 0.3
              end },
          } });  y = y - h

    -- Rows 2-4 are HIDDEN entirely while Show Class Resource is off (the toggle's DependentSetValue forces the rebuild on flips).
    if not classPowerDisabled() then
    -- Row 2: Position (with inline cog for X/Y) | Size
    local classResourceRow2
    classResourceRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Position",
          values={ top = "Top", bottom = "Bottom" },
          getValue=function() return DBVal("classPowerPos") or defaults.classPowerPos end,
          setValue=function(v)
            DB().classPowerPos = v
            ns.RefreshClassPower(); UpdatePreview()
          end, order={ "top", "bottom" } },
        { type="slider", text="Size", min=0.5, max=4.0, step=0.1,
          getValue=function() return DBVal("classPowerScale") or defaults.classPowerScale end,
          setValue=function(v)
            DB().classPowerScale = v
            ns.RefreshClassPower(); UpdatePreview()
          end });  y = y - h

    -- Inline cog on Position dropdown (X/Y offset settings)
    if not EllesmereUI._prebuilding then
        local leftRgn = classResourceRow2._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, {
            anchorTo = leftRgn._control,
            disabled = classPowerDisabled,
            disabledTooltip = "Show Class Resource",
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = "Position Settings",
                    xGet = function() return DBVal("classPowerXOffset") or defaults.classPowerXOffset end,
                    xSet = function(v) DB().classPowerXOffset = v; ns.RefreshClassPower(); UpdatePreview() end,
                    yGet = function() return DBVal("classPowerYOffset") or defaults.classPowerYOffset end,
                    ySet = function(v) DB().classPowerYOffset = v; ns.RefreshClassPower(); UpdatePreview() end,
                })
            end,
        })
    end

    -- Row 3: Bar Spacing + Background Color (with alpha)
    local classResourceRow3
    classResourceRow3, h = W:DualRow(parent, y,
        { type="slider", pixel=true, text="Bar Spacing", min=-5, max=10, step=1,
          getValue=function() return DBVal("classPowerGap") or defaults.classPowerGap end,
          setValue=function(v)
            DB().classPowerGap = v
            ns.RefreshClassPower(); UpdatePreview()
          end },
        { type="colorpicker", text="Background Color", hasAlpha=true,
          getValue=function()
            local c = (DB() and DB().classPowerBgColor) or defaults.classPowerBgColor
            return c.r, c.g, c.b, c.a
          end,
          setValue=function(r, g, b, a)
            DB().classPowerBgColor = { r=r, g=g, b=b, a=a }
            ns.RefreshClassPower(); UpdatePreview()
          end });  y = y - h

    -- Row 4: Shape | Border (inline thickness cog + color swatch on Border)
    local classResourceRow4
    classResourceRow4, h = W:DualRow(parent, y,
        { type="dropdown", text="Shape",
          values={ rectangle="Rectangle", square="Square", circle="Circle",
                   diamond="Diamond", hexagon="Hexagon", shield="Shield",
                   rune="Rune", holypower="Holy Power", shard="Soul Shard",
                   combo="Combo Points", chi="Chi", arcane="Arcane Charges",
                   essence="Essence" },
          order={ "rectangle", "square", "circle", "diamond", "hexagon", "shield",
                  "rune", "holypower", "shard", "combo", "chi", "arcane", "essence" },
          getValue=function() return DBVal("classPowerShape") or defaults.classPowerShape end,
          setValue=function(v)
            DB().classPowerShape = v
            ns.RefreshClassPower(); UpdatePreview()
          end },
        { type="toggle", text="Border",
          getValue=function() return DBVal("classPowerBorder") == true end,
          setValue=function(v)
            DB().classPowerBorder = v
            ns.RefreshClassPower(); UpdatePreview()
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline thickness cog + border color swatch on the Border toggle
    if not EllesmereUI._prebuilding then
        local rgn = classResourceRow4._rightRegion
        local function borderOff()
            return classPowerDisabled() or DBVal("classPowerBorder") ~= true
        end
        local colorGet = function()
            local c = (DB() and DB().classPowerBorderColor) or defaults.classPowerBorderColor
            return c.r, c.g, c.b
        end
        local colorSet = function(r, g, b)
            DB().classPowerBorderColor = { r = r, g = g, b = b, a = 1 }
            ns.RefreshClassPower(); UpdatePreview()
        end

        EllesmereUI.BuildInlineCog(rgn, {
            disabled = borderOff,
            disabledTooltip = "Border",
            title = "Border Settings",
            rows = {
                { type="slider", label="Thickness", min=1, max=4, step=1,
                  get=function() return DBVal("classPowerBorderSize") or defaults.classPowerBorderSize end,
                  set=function(v) DB().classPowerBorderSize = v; ns.RefreshClassPower(); UpdatePreview() end },
            },
        })

        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = borderOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = borderOff()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end
    end   -- close Class Resource hidden-while-disabled gate

    -- Invisible frame spanning the entire CLASS RESOURCE section for glow targeting
    -- (none in the search pre-build, which wires no click navigation)
    local classResourceSection
    if not EllesmereUI._prebuilding then
        classResourceSection = CreateFrame("Frame", nil, parent)
        local crPad = EllesmereUI.CONTENT_PAD or 20
        classResourceSection:SetPoint("TOPLEFT", parent, "TOPLEFT", crPad, classResourceSectionTop)
        classResourceSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -crPad, classResourceSectionTop)
        classResourceSection:SetHeight(math.abs(classResourceSectionTop - y))
        classResourceSection._isSpacer = true  -- hide from search layout
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  GENERAL TEXT
    -----------------------------------------------------------------------
    local generalTextHeader
    generalTextHeader, h = W:SectionHeader(parent, "GENERAL TEXT", y);  y = y - h

    -- Duration controls are per aura type. "None" is the show/hide switch.
    local auraDurPosRow
    local auraTimerStackRow
    do
        local durationTypes = {
            debuff = { text = "Debuff Duration", title = "Debuff Duration Settings", key = "debuffTimerPosition" },
            buff = { text = "Buff Duration", title = "Buff Duration Settings", key = "buffTimerPosition" },
            cc = { text = "CC Duration", title = "CC Duration Settings", key = "ccTimerPosition" },
        }
        local function DurationDropdown(kind)
            local cfg = durationTypes[kind]
            return { type="dropdown", text=cfg.text, values=timerPosValues,
              getValue=function() return DBVal(cfg.key) or atFallback end,
              setValue=function(v)
                DB()[cfg.key] = v
                LiveApplyAuraText()
                UpdatePreview()
              end, order=timerPosOrder }
        end
        local function RefreshDuration()
            LiveApplyAuraText()
            UpdatePreview()
        end
        local function AttachDurationTools(region, kind)
            local cfg = durationTypes[kind]
            local colorGet = function()
                local c = AuraDurationVal(kind, "Color")
                return c.r, c.g, c.b
            end
            local colorSet = function(r, g, b)
                DB()[kind .. "DurationTextColor"] = { r = r, g = g, b = b }
                RefreshDuration()
            end

            EllesmereUI.BuildInlineCog(region, {
                title = cfg.title,
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return AuraDurationVal(kind, "Size") end,
                      set=function(v) DB()[kind .. "DurationTextSize"] = v; RefreshDuration() end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return AuraDurationVal(kind, "X") end,
                      set=function(v) DB()[kind .. "DurationTextX"] = v; RefreshDuration() end },
                    { type="slider", label="Y", min=-50, max=50, step=1,
                      get=function() return AuraDurationVal(kind, "Y") end,
                      set=function(v) DB()[kind .. "DurationTextY"] = v; RefreshDuration() end },
                },
            })
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
            PP.Point(swatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
        end

        local durationRow1
        durationRow1, h = W:DualRow(parent, y, DurationDropdown("debuff"), DurationDropdown("buff")); y = y - h
        auraDurPosRow = durationRow1
        if not EllesmereUI._prebuilding then
        AttachDurationTools(durationRow1._leftRegion, "debuff")
        AttachDurationTools(durationRow1._rightRegion, "buff")
        end

        local durationRow2
        durationRow2, h = W:DualRow(parent, y,
            DurationDropdown("cc"),
            { type="dropdown", text="Aura Stacks", values=timerPosValues,
              getValue=function() return DBVal("auraStackTextPosition") or asFallback end,
              setValue=function(v)
                DB().auraStackTextPosition = v
                LiveApplyAuraText()
                UpdatePreview()
              end, order=timerPosOrder }); y = y - h
        auraTimerStackRow = durationRow2
        if not EllesmereUI._prebuilding then
        AttachDurationTools(durationRow2._leftRegion, "cc")
        end

        if not EllesmereUI._prebuilding then
        -- RIGHT: Aura Stacks inline color swatch
        local rightRgn = durationRow2._rightRegion
        local asColorGet = function()
            local c = (DB() and DB().auraStackTextColor) or defaults.auraStackTextColor
            return c.r, c.g, c.b
        end
        local asColorSet = function(r, g, b)
            DB().auraStackTextColor = { r = r, g = g, b = b }
            LiveApplyAuraText()
            UpdatePreview()
        end

        -- RIGHT: Aura Stacks inline cog (Size / X / Y)
        EllesmereUI.BuildInlineCog(rightRgn, {
            title = "Aura Stacks Settings",
            rows = {
                { type="slider", label="Size", min=6, max=20, step=1,
                  get=function() return DBVal("auraStackTextSize") or defaults.auraStackTextSize end,
                  set=function(v)
                    DB().auraStackTextSize = v
                    LiveApplyAuraText()
                    UpdatePreview()
                  end },
                { type="slider", label="X", min=-50, max=50, step=1,
                  get=function() return DBVal("auraStackTextX") or defaults.auraStackTextX end,
                  set=function(v)
                    DB().auraStackTextX = v
                    LiveApplyAuraText()
                    UpdatePreview()
                  end },
                { type="slider", label="Y", min=-50, max=50, step=1,
                  get=function() return DBVal("auraStackTextY") or defaults.auraStackTextY end,
                  set=function(v)
                    DB().auraStackTextY = v
                    LiveApplyAuraText()
                    UpdatePreview()
                  end },
            },
        })
        local asSwatch, asUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, asColorGet, asColorSet, nil, 20)
        PP.Point(asSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = asSwatch
        EllesmereUI.RegisterWidgetRefresh(function() asUpdateSwatch() end)
        end
    end

    -- Spell Name | Spell Target: position dropdowns (None/Left/Right/Center), styled like the duration dropdowns. Name and target can't share a side (setting one onto the other's side bumps it to None); Size/X/Y live in each row's inline cog.
    local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
    local castTextPosOrder = { "none", "left", "right", "center" }
    local spellNameRow
    spellNameRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Spell Name", values=castTextPosValues, order=castTextPosOrder,
          getValue=function() return (DB() and DB().castNameSide) or defaults.castNameSide end,
          setValue=function(v)
            DB().castNameSide = v
            if v ~= "none" then
                local ts = (DB() and DB().castTargetSide) or defaults.castTargetSide
                if ts == v then DB().castTargetSide = "none" end
            end
            ns.RefreshAllSettings()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Spell Target", values=castTextPosValues, order=castTextPosOrder,
          disabled=function() return DBVal("castCombineNameTarget") == true end,
          disabledTooltip="This option requires Combine Spell Name and Target to be disabled.",
          getValue=function() return (DB() and DB().castTargetSide) or defaults.castTargetSide end,
          setValue=function(v)
            DB().castTargetSide = v
            if v ~= "none" then
                local nss = (DB() and DB().castNameSide) or defaults.castNameSide
                if nss == v then DB().castNameSide = "none" end
            end
            ns.RefreshAllSettings()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end })
    if not EllesmereUI._prebuilding then
        -- LEFT: Spell Name inline color swatch
        local leftRgn = spellNameRow._leftRegion
        local snColorGet = function() return DBColor("castNameColor") end
        local snColorSet = function(r, g, b)
            DB().castNameColor = { r = r, g = g, b = b }
            for _, plate in pairs(plates) do
                if plate.castName then plate.castName:SetTextColor(r, g, b, 1) end
            end
            UpdatePreview()
        end

        -- LEFT: Spell Name inline cog for X/Y offset
        EllesmereUI.BuildInlineCog(leftRgn, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = EllesmereUI.L("Spell Name Settings"),
                    xGet = function() return DBVal("castNameOffsetX") or defaults.castNameOffsetX end,
                    xSet = function(v) DB().castNameOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    yGet = function() return DBVal("castNameOffsetY") or defaults.castNameOffsetY end,
                    ySet = function(v) DB().castNameOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeGet = function() return DBVal("castNameSize") or defaults.castNameSize end,
                    sizeSet = function(v) DB().castNameSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                    sizeFirst = true,
                    -- Combined text has its own width; the name's applies while separate.
                    widthGet = function()
                        if DBVal("castCombineNameTarget") == true then
                            return DBVal("castCombinedWidthPct") or defaults.castCombinedWidthPct
                        end
                        return DBVal("castNameWidthPct") or defaults.castNameWidthPct
                    end,
                    widthSet = function(v)
                        if DBVal("castCombineNameTarget") == true then
                            DB().castCombinedWidthPct = v
                        else
                            DB().castNameWidthPct = v
                        end
                        ns.RefreshAllSettings(); UpdatePreview()
                    end,
                    wrapGet = function() return DBVal("castNameWrap") == true end,
                    wrapSet = function(v) DB().castNameWrap = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    toggleLabel = "Combine Spell Name and Target",
                    toggleGet = function() return DBVal("castCombineNameTarget") == true end,
                    toggleSet = function(v)
                        DB().castCombineNameTarget = v
                        ns.RefreshAllSettings()
                        UpdatePreview()
                        EllesmereUI:RefreshPage()
                    end,
                })
            end,
        })
        local snSwatch, snUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, snColorGet, snColorSet, nil, 20)
        PP.Point(snSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = snSwatch
        EllesmereUI.RegisterWidgetRefresh(function() snUpdateSwatch() end)

        -- RIGHT: Spell Target inline double swatch (custom + class colored)
        local rightRgn = spellNameRow._rightRegion
        local ctrl = rightRgn._control

        -- RIGHT: Spell Target inline cog for X/Y offset
        EllesmereUI.BuildInlineCog(rightRgn, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = EllesmereUI.L("Spell Target Settings"),
                    xGet = function() return DBVal("castTargetOffsetX") or defaults.castTargetOffsetX end,
                    xSet = function(v) DB().castTargetOffsetX = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    yGet = function() return DBVal("castTargetOffsetY") or defaults.castTargetOffsetY end,
                    ySet = function(v) DB().castTargetOffsetY = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeGet = function() return DBVal("castTargetSize") or defaults.castTargetSize end,
                    sizeSet = function(v) DB().castTargetSize = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    sizeMin = 6, sizeMax = 20, sizeLabel = EllesmereUI.L("Size"),
                    sizeFirst = true,
                    widthGet = function() return DBVal("castTargetWidthPct") or defaults.castTargetWidthPct end,
                    widthSet = function(v) DB().castTargetWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end,
                    wrapGet = function() return DBVal("castTargetWrap") == true end,
                    wrapSet = function(v) DB().castTargetWrap = v; ns.RefreshAllSettings(); UpdatePreview() end,
                })
            end,
        })

        -- Class colored swatch (beside the cog)
        local ccGet = function()
            local _, ct = UnitClass("player")
            if ct and RAID_CLASS_COLORS[ct] then
                local cc = RAID_CLASS_COLORS[ct]
                return cc.r, cc.g, cc.b
            end
            return 1, 1, 1
        end
        local ccSwatch, ccUpdate = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, ccGet, function() end, nil, 20)
        PP.Point(ccSwatch, "RIGHT", rightRgn._lastInline or ctrl, "LEFT", -8, 0)
        ccSwatch:SetScript("OnClick", function()
            DB().castTargetClassColor = true
            for _, plate in pairs(plates) do plate:UpdateHealth() end
            UpdatePreview()
            EllesmereUI:RefreshPage()
        end)
        ccSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(ccSwatch, "Class Color") end)
        ccSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        -- Custom color swatch (to the left of class swatch)
        local stColorGet = function() return DBColor("castTargetColor") end
        local stColorSet = function(r, g, b)
            DB().castTargetColor = { r = r, g = g, b = b }
            for _, plate in pairs(plates) do plate:UpdateHealth() end
            UpdatePreview()
        end
        local stSwatch, stUpdate = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, stColorGet, stColorSet, nil, 20)
        PP.Point(stSwatch, "RIGHT", ccSwatch, "LEFT", -9, 0)
        rightRgn._lastInline = stSwatch
        stSwatch._eabOrigClick = stSwatch:GetScript("OnClick")
        stSwatch:SetScript("OnClick", function(self)
            local db = DB()
            local cc = db and db.castTargetClassColor
            if cc == nil then cc = defaults.castTargetClassColor end
            if cc then
                DB().castTargetClassColor = false
                for _, plate in pairs(plates) do plate:UpdateHealth() end
                UpdatePreview()
                EllesmereUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        stSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(stSwatch, "Custom Color") end)
        stSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        EllesmereUI.RegisterWidgetRefresh(function()
            local db = DB()
            local isCC = db and db.castTargetClassColor
            if isCC == nil then isCC = defaults.castTargetClassColor end
            stSwatch:SetAlpha(isCC and 0.3 or 1)
            ccSwatch:SetAlpha(isCC and 1 or 0.3)
            stUpdate()
            ccUpdate()
        end)
        local isCC = (DB() and DB().castTargetClassColor)
        if isCC == nil then isCC = defaults.castTargetClassColor end
        stSwatch:SetAlpha(isCC and 0.3 or 1)
        ccSwatch:SetAlpha(isCC and 1 or 0.3)
    end
    y = y - h

    return y, healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow,
        classResourceHeader, classResourceSection, generalTextHeader,
        auraDurPosRow, auraTimerStackRow, spellNameRow
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildDisplayBars = BuildDisplayBars
