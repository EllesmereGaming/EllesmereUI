if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayBars_Options.lua
--  Nameplates options: the Health and Cast Bar, Cast Colors and Effects,
--  Target/Focus/Hover Effects, Class Resource and General Text sections of the
--  Display page. Called by BuildDisplayPage after DisplayLayout_Options.lua;
--  returns y and the rows its click navigation maps to. Shared helpers come
--  from ns._NPO_OptEnv, the per-build helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

local function BuildDisplayBars(parent, y, ctx)
    local env = ns._NPO_OptEnv
    local BAR_W, DB, DBColor, DBVal = env.BAR_W, env.DB, env.DBColor, env.DBVal
    local defaults, displayCastIcons, hbtOrder, hbtValues = env.defaults, env.displayCastIcons, env.hbtOrder, env.hbtValues
    local LazyColorPreviewBar, npImpCastGlowDesc, optState, pairs = env.LazyColorPreviewBar, env.npImpCastGlowDesc, env.optState, env.pairs
    local plates, PP, RefreshAllPlates, SECTION_CASTBAR = env.plates, env.PP, env.RefreshAllPlates, env.SECTION_CASTBAR
    local SetFSFont, UpdatePreview = env.SetFSFont, env.UpdatePreview
    local asFallback, atFallback, AuraDurationVal, CogPopupOpen = ctx.asFallback, ctx.atFallback, ctx.AuraDurationVal, ctx.CogPopupOpen
    local LiveApplyStackPos, LiveApplyTimerPos, RefreshAllTextures, ShowCogPopup = ctx.LiveApplyStackPos, ctx.LiveApplyTimerPos, ctx.RefreshAllTextures, ctx.ShowCogPopup
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
            icon = EllesmereUI.RESIZE_ICON,
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
            local barW = ns.GetHealthBarWidth()
            local castH = ns.GetCastBarHeight()
            for _, plate in pairs(plates) do
                ns.LayoutCastBar(plate, barW, castH)
            end
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
        local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ctColorGet, ctColorSet, nil, 20)
        PP.Point(ctSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = ctSwatch
        EllesmereUI.RegisterWidgetRefresh(function() ctUpdateSwatch() end)

        -- Inline cog for Cast Timer Size / X / Y
        EllesmereUI.BuildInlineCog(leftRgn, {
            anchorTo = ctSwatch, gap = 6,
            icon = EllesmereUI.RESIZE_ICON,
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
                  tooltip = "Tint the cast bar with the Important colour when the enemy casts a spell the game flags as important. Overrides the Interruptible Cast colour; your interrupt being on cooldown still takes priority.",
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
            },
        })
    end

    -- Important Cast Glow: shared glow controls (cast bar = bar host) + preview
    do
        local GO = EllesmereUI.GlowOptions
        local impDesc = npImpCastGlowDesc

        local impGlowRow
        impGlowRow, h = W:DualRow(parent, y,
            GO.DropdownSpec(impDesc, "Important Cast Glow",
                "Show a glow on the cast bar when the enemy is casting a spell Blizzard marks as important."),
            { type="toggle", text="Casts In Front of Nameplates",
              tooltip="Forces all casts to be shown in front of nameplates for visual clarity",
              getValue=function() return DBVal("castOverlayEnabled") == true end,
              setValue=function(v)
                DB().castOverlayEnabled = v
                ns.RefreshAllSettings()
              end });  y = y - h

        if not EllesmereUI._prebuilding then
            local leftRgn = impGlowRow._leftRegion
            GO.AttachInline(leftRgn, impDesc)
            -- Icon-sized preview in the inline chain (the right half is a real
            -- setting); -12: the widest FlipBook styles overhang ~8px per side.
            local pv = GO.BuildPreview(leftRgn, impDesc, {
                bar = false, width = 26, height = 26,
                icon = function() return displayCastIcons[optState._previewCastIconIdx or 1] end,
                anchor = leftRgn._lastInline, x = -12,
            })
            if pv then
                pv:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                leftRgn._lastInline = pv
            end
        end
    end

    -- Row 3: Focus Text Reminders (CDM only, left) | Show Interrupted Flash Effect (always present, a core cast bar setting): when CDM is loaded, Focus Text Reminders fills the left slot and flash takes the right; otherwise flash takes the left slot itself.
    do
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
        else
            row3, h = W:DualRow(parent, y,
                flashCfg,
                { type = "label", text = "" }
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
                -- Blizzard Style uses the stock interrupted fill art, so the flash colour is inert there.
                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = flashOff() or ns.NP_BlizzOnly()
                    swatch:SetAlpha(off and 0.15 or 1)
                    swatch:EnableMouse(not off)
                    updateSwatch()
                end)
                swatch:SetAlpha(flashOff() and 0.15 or 1)
                swatch:EnableMouse(not flashOff())
            end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  TARGET, FOCUS & HOVER EFFECTS
    -----------------------------------------------------------------------
    local tfxHeader
    tfxHeader, h = W:SectionHeader(parent, "TARGET, FOCUS & HOVER EFFECTS", y);  y = y - h

    local targetGlowRow
    -- Build the arrow-style dropdown options from the shared style table.
    local arrowVals = { none = "None" }
    local arrowOrd = { "none" }
    for _, k in ipairs(ns.TARGET_ARROW_ORDER) do
        arrowVals[k] = ns.TARGET_ARROW_STYLES[k].label
        arrowOrd[#arrowOrd + 1] = k
    end
    -- Preview the right-arrow texture on the right of each dropdown row.
    arrowVals._menuOpts = {
        itemHeight = 26,
        icon = function(key)
            local st = ns.TARGET_ARROW_STYLES[key]
            if not st then return nil end  -- "none" has no preview
            return ns.TARGET_ARROW_DIR .. st.l .. ".png"
        end,
        iconWidth = function(key)
            local st = ns.TARGET_ARROW_STYLES[key]
            if not st then return nil end
            -- Match in-game aspect: drawn width is st.w at height 16, icon slot is itemHeight(32)-8=24 tall, so scale width by 24/16.
            return math.floor(st.w * 24 / 16 + 0.5)
        end,
    }
    targetGlowRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Target Effect",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end },
        { type="dropdown", text="Target Arrows",
          values=arrowVals,
          order=arrowOrd,
          getValue=function()
            if DBVal("showTargetArrows") ~= true then return "none" end
            return DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
          end,
          setValue=function(v)
            if v == "none" then
                DB().showTargetArrows = false
            else
                DB().showTargetArrows = true
                DB().targetArrowStyle = v
            end
            for _, plate in pairs(plates) do
                plate:ApplyTarget()
            end
            UpdatePreview()
          end });  y = y - h

    -- Target Effect: multi-select checkbox dropdown (EUI Glow/Border Color/Highlight), independent toggles; data model live-converts from the legacy targetGlowStyle string (see ns.GetTargetGlow* in the core file).
    local refreshTargetBorderSwatch  -- fwd decl; assigned when the swatch builds
    local refreshTargetGlowSwatch    -- fwd decl; assigned when the glow swatch builds
    local refreshTargetHighlightCog  -- fwd decl; assigned when the cog builds
    if not EllesmereUI._prebuilding then
        local leftRgn = targetGlowRow._leftRegion
        if leftRgn._control then leftRgn._control:Hide() end
        local glowItems = {
            { key = "ellesmereui", label = "EUI Glow" },
            { key = "borderColor", label = "Border Color" },
            { key = "highlight",   label = "Highlight" },
            { key = "borderSize",  label = "Border Size",
              tooltip = "Change Size in the Cogwheel" },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            leftRgn, 170, leftRgn:GetFrameLevel() + 2,
            glowItems,
            function(k)
                if k == "ellesmereui" then return ns.GetTargetGlowEllesmereUI() end
                if k == "borderColor" then return ns.GetTargetGlowBorderColor() end
                if k == "highlight"   then return ns.GetTargetGlowHighlight() end
                if k == "borderSize"  then return ns.GetTargetGlowBorderSize() end
                return false
            end,
            function(k, v)
                if k == "ellesmereui" then DB().targetGlowEllesmereUI = v
                elseif k == "borderColor" then DB().targetGlowBorderColor = v
                elseif k == "highlight" then DB().targetGlowHighlight = v
                elseif k == "borderSize" then
                    DB().targetGlowBorderSize = v
                    -- First-enable snapshot: seed the cog slider with the user's CURRENT border size, so enabling changes nothing until they move it (one-time, never re-snapshots later).
                    if v and DB().targetBorderSizeValue == nil then
                        if ns.IsCustomBorderEnabled() then
                            DB().targetBorderSizeValue = DBVal("customBorderSize") or defaults.customBorderSize
                        else
                            DB().targetBorderSizeValue = DBVal("borderSize") or defaults.borderSize
                        end
                    end
                end
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                UpdatePreview()
                if refreshTargetBorderSwatch then refreshTargetBorderSwatch() end
                if refreshTargetGlowSwatch then refreshTargetGlowSwatch() end
                if refreshTargetHighlightCog then refreshTargetHighlightCog() end
            end)
        PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        leftRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Inline Border Color swatch: edits targetBorderColor (default white), tints the custom border; dimmed+non-interactive unless Border Color is checked.
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function() local c = ns.GetTargetBorderColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetBorderColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                UpdatePreview()
            end, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = swatch
        -- Tooltip so the swatch's purpose is clear (shown while interactive, i.e. Border Color on).
        swatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, "Border Color") end)
        swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshTargetBorderSwatch = function()
            local off = not ns.GetTargetGlowBorderColor()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshTargetBorderSwatch)
        refreshTargetBorderSwatch()

        -- Inline Glow Color swatch: edits targetGlowColor (default the signature blue), tints the EUI background glow; dimmed+non-interactive unless EUI Glow is checked.
        local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function() local c = ns.GetTargetGlowColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetGlowColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview()
            end, nil, 20)
        PP.Point(glowSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = glowSwatch
        glowSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(glowSwatch, "Glow Color") end)
        glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshTargetGlowSwatch = function()
            local off = not ns.GetTargetGlowEllesmereUI()
            glowSwatch:SetAlpha(off and 0.15 or 1)
            glowSwatch:EnableMouse(not off)
            updateGlowSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshTargetGlowSwatch)
        refreshTargetGlowSwatch()

        -- Inline cog "More Effects": Highlight color/opacity + Glow opacity; enabled when Highlight OR EUI Glow is on (Glow Opacity reachable whenever the glow is active).
        do
            local function highlightCogOff()
                return not (ns.GetTargetGlowHighlight() or ns.GetTargetGlowEllesmereUI()
                    or ns.GetTargetGlowBorderSize())
            end
            local highlightCogBtn = EllesmereUI.BuildInlineCog(leftRgn, {
                disabled = highlightCogOff,
                disabledTooltip = "a Target Effect",
                title = "More Effects",
                rows = {
                    { type="colorpicker", label="Highlight Color", hasAlpha=false,
                      get=function() local c = ns.GetTargetHighlightColor(); return c.r, c.g, c.b end,
                      set=function(r, g, b)
                        DB().targetHighlightColor = { r = r, g = g, b = b }
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Highlight Opacity", min=0, max=100, step=1,
                      get=function() return math.floor((ns.GetTargetHighlightAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().targetHighlightAlpha = v / 100
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Glow Opacity", min=0, max=100, step=1,
                      get=function() return math.floor((ns.GetTargetGlowAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().targetGlowAlpha = v / 100
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Border Size", min=0, max=4, step=1,
                      get=function()
                        local v = DBVal("targetBorderSizeValue")
                        if v ~= nil then return v end
                        -- Not snapshotted yet: show the current border size.
                        if ns.IsCustomBorderEnabled() then
                            return DBVal("customBorderSize") or defaults.customBorderSize
                        end
                        return DBVal("borderSize") or defaults.borderSize
                      end,
                      set=function(v)
                        DB().targetBorderSizeValue = v
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                        UpdatePreview()
                      end,
                      disabled=function() return not ns.GetTargetGlowBorderSize() end,
                      disabledTooltip="Border Size Target Effect" },
                },
            })
            refreshTargetHighlightCog = highlightCogBtn and highlightCogBtn._euiCogState
        end
    end

    -- Inline Custom + Class color swatches on Target Arrows (custom adjacent to the control, class to its left); click to switch, inactive swatch dims, both gray out when arrows off.
    do
        local rightRgn = targetGlowRow._rightRegion
        local arrowOff = function() return DBVal("showTargetArrows") ~= true end
        local customSwatch, updateCustom, classSwatch, updateClass
        local function refreshArrowSwatches()
            if updateCustom then updateCustom() end
            if updateClass then updateClass() end
            local off = arrowOff()
            local useClass = DBVal("targetArrowClassColor") == true
            customSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
            classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
            customSwatch:SetMouseClickEnabled(not off)
            classSwatch:SetMouseClickEnabled(not off)
        end
        customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = DBVal("targetArrowColor") or defaults.targetArrowColor; return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetArrowColor = { r = r, g = g, b = b }
                DB().targetArrowClassColor = false
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview(); refreshArrowSwatches()
            end, nil, 20)
        PP.Point(customSwatch, "RIGHT", rightRgn._control, "LEFT", -8, 0)
        local origCustomClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if arrowOff() then return end
            if DBVal("targetArrowClassColor") == true then
                DB().targetArrowClassColor = false
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview(); refreshArrowSwatches()
                return
            end
            if origCustomClick then origCustomClick(self, ...) end
        end)
        customSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color") end)
        customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        classSwatch, updateClass = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local _, ct = UnitClass("player"); local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct); if cc then return cc.r, cc.g, cc.b end return 1, 1, 1 end,
            function() end, nil, 20)
        PP.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        rightRgn._lastInline = classSwatch
        classSwatch:SetScript("OnClick", function()
            if arrowOff() then return end
            DB().targetArrowClassColor = true
            for _, plate in pairs(plates) do plate:ApplyTarget() end
            UpdatePreview(); refreshArrowSwatches()
        end)
        classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
        classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(refreshArrowSwatches)
        refreshArrowSwatches()
    end

    -- Inline cog (arrow scale), to the left of the swatches
    do
        local rightRgn = targetGlowRow._rightRegion
        local arrowOff = function() return DBVal("showTargetArrows") ~= true end
        EllesmereUI.BuildInlineCog(rightRgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = arrowOff,
            disabledTooltip = "Target Arrows",
            title = "Arrow Scale",
            rows = {
                { type="slider", label="Scale", min=0.5, max=3.0, step=0.1,
                  get=function() return DBVal("targetArrowScale") or defaults.targetArrowScale or 1.0 end,
                  set=function(v)
                    DB().targetArrowScale = v
                    local _scKey = DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
                    local _scW = (ns.TARGET_ARROW_STYLES[_scKey] or ns.TARGET_ARROW_STYLES.simple).w
                    for _, plate in pairs(plates) do
                        local sc = v
                        local aw = math.floor(_scW * sc + 0.5)
                        local ah = math.floor(16 * sc + 0.5)
                        if plate.leftArrow then PP.Size(plate.leftArrow, aw, ah) end
                        if plate.rightArrow then PP.Size(plate.rightArrow, aw, ah) end
                    end
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Eye icon to the left of the Target Glow Style dropdown to toggle glow on preview
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local leftRgn = targetGlowRow._leftRegion
        local eyeBtn = CreateFrame("Button", nil, leftRgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshTargetGlowEye()
            if optState.showTargetGlowPreview then
                eyeTex:SetTexture(EYE_INVISIBLE)
            else
                eyeTex:SetTexture(EYE_VISIBLE)
            end
        end
        RefreshTargetGlowEye()
        eyeBtn:SetScript("OnClick", function()
            optState.showTargetGlowPreview = not optState.showTargetGlowPreview
            RefreshTargetGlowEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
    end

    -- Enable Target Color ---- Target Texture
    local isTargetColorDisabled = function()
        local db = DB()
        if db and db.targetColorEnabled ~= nil then return not db.targetColorEnabled end
        return not defaults.targetColorEnabled
    end
    local isTargetTextureNone = function()
        return (DBVal("targetOverlayTexture") or defaults.targetOverlayTexture) == "none"
    end
    -- No Tint: the target texture pattern becomes the bar's own fill texture (SetStatusBarTexture) instead of a tinted overlay, so the color swatch/opacity below stop applying.
    local isTargetNoTint = function()
        local v = DBVal("targetOverlayNoTint")
        if v == nil then return defaults.targetOverlayNoTint end
        return v
    end
    local isFocusColorDisabled = function()
        local db = DB()
        if db and db.focusColorEnabled ~= nil then return not db.focusColorEnabled end
        return not defaults.focusColorEnabled
    end
    local isFocusTextureNone = function()
        return (DBVal("focusOverlayTexture") or defaults.focusOverlayTexture) == "none"
    end
    local isFocusNoTint = function()
        local v = DBVal("focusOverlayNoTint")
        if v == nil then return defaults.focusOverlayNoTint end
        return v
    end

    local targetPrev, focusPrev
    local function RefreshFocusPreview()
        RefreshAllPlates()
        if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
    end

    local targetColorRow
    targetColorRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Target Color",
          getValue=function()
            local db = DB()
            if db and db.targetColorEnabled ~= nil then return db.targetColorEnabled end
            return defaults.targetColorEnabled
          end,
          setValue=function(v)
            DB().targetColorEnabled = v
            RefreshAllPlates()
            if targetPrev then
                if v then
                    targetPrev.SetColorOverride(nil)
                else
                    targetPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
                end
                targetPrev.UpdateColor()
                targetPrev.SetDisabled(not v)
            end
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Enable Focus Color",
          getValue=function()
            local db = DB()
            if db and db.focusColorEnabled ~= nil then return db.focusColorEnabled end
            return defaults.focusColorEnabled
          end,
          setValue=function(v)
            DB().focusColorEnabled = v
            RefreshAllPlates()
            if focusPrev then
                if v then
                    focusPrev.SetColorOverride(nil)
                else
                    focusPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
                end
                focusPrev.UpdateColor()
                focusPrev.SetDisabled(not v)
            end
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline Target Color swatch
    if not EllesmereUI._prebuilding then
        local leftRgn = targetColorRow._leftRegion
        local targetColorGet = function() return DBColor("target") end
        local targetColorSet = function(r, g, b)
            DB().target = { r = r, g = g, b = b }
            RefreshAllPlates()
            if targetPrev then targetPrev.UpdateColor() end
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, targetColorGet, targetColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isTargetColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetColorDisabled()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline Focus Color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = targetColorRow._rightRegion
        local focusColorGet = function() return DBColor("focus") end
        local focusColorSet = function(r, g, b)
            DB().focus = { r = r, g = g, b = b }
            RefreshAllPlates()
            if focusPrev then focusPrev.UpdateColor() end
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, focusColorGet, focusColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isFocusColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusColorDisabled()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Target Texture ---- Focus Texture
    -- Both dropdowns list the special stripe overlays first, then the full bar texture set (EUI + SharedMedia) shared with the main Bar Texture dropdown; stripe keys resolve to nameplate Media, bar keys resolve through the health-bar lookup at render time (ns.ResolveOverlayTexPath).
    local ovtValues, ovtOrder = {}, {}
    do
        local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
        }
        for _, k in ipairs(STRIPE_ORDER) do ovtValues[k] = STRIPE_NAMES[k]; ovtOrder[#ovtOrder + 1] = k end
        ovtOrder[#ovtOrder + 1] = "---"
        for _, k in ipairs(hbtOrder) do
            ovtOrder[#ovtOrder + 1] = k
            if k ~= "---" then ovtValues[k] = hbtValues[k] end
        end
        ovtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then return nil end
                if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                end
                return ns.healthBarTextures and ns.healthBarTextures[key]
            end,
        }
    end
    local textureDualRow
    textureDualRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Target Texture",
          values=ovtValues,
          getValue=function() return DBVal("targetOverlayTexture") or defaults.targetOverlayTexture end,
          setValue=function(v)
            DB().targetOverlayTexture = v
            RefreshAllPlates()
            if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
            EllesmereUI:RefreshPage()
          end,
          order=ovtOrder },
        { type="dropdown", text="Focus Texture",
          values=ovtValues,
          getValue=function() return DBVal("focusOverlayTexture") or defaults.focusOverlayTexture end,
          setValue=function(v)
            DB().focusOverlayTexture = v
            RefreshAllPlates()
            if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
            EllesmereUI:RefreshPage()
          end,
          order=ovtOrder });  y = y - h

    -- Inline Target Texture color swatch
    if not EllesmereUI._prebuilding then
        local leftRgn = textureDualRow._leftRegion
        local targetTexColorGet = function()
            local c = (DB() and DB().targetOverlayColor) or defaults.targetOverlayColor
            return c.r, c.g, c.b
        end
        local targetTexColorSet = function(r, g, b)
            DB().targetOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, targetTexColorGet, targetTexColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isTargetTextureNone() or isTargetNoTint()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetTextureNone() or isTargetNoTint()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline Target Texture cog (Opacity + No Tint), to the left of the swatch
    if not EllesmereUI._prebuilding then
        local leftRgn = textureDualRow._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = isTargetTextureNone,
            disabledTooltip = "a Target Texture",
            title = "Target Texture",
            rows = {
                { type="slider", label="Opacity", min=5, max=100, step=1,
                  get=function() return math.floor(((DBVal("targetOverlayAlpha") or defaults.targetOverlayAlpha) * 100) + 0.5) end,
                  set=function(v)
                    DB().targetOverlayAlpha = v / 100
                    RefreshAllPlates()
                    if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                  end },
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("targetOverlayFullBgAlpha")
                    if v == nil then return defaults.targetOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().targetOverlayFullBgAlpha = v
                    RefreshAllPlates()
                    if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                  end },
                { type="toggle", label="Don't tint (keep bar's own color)",
                  tooltip="Tints the pattern with the bar's current color instead of the custom overlay color.",
                  get=isTargetNoTint,
                  set=function(v)
                    DB().targetOverlayNoTint = v
                    RefreshAllTextures()
                    if targetPrev and targetPrev.UpdateOverlay then targetPrev.UpdateOverlay() end
                  end },
            },
        })
    end

    -- Inline Focus Texture color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = textureDualRow._rightRegion
        local focusTexColorGet = function()
            local c = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
            return c.r, c.g, c.b
        end
        local focusTexColorSet = function(r, g, b)
            DB().focusOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            if focusPrev and focusPrev.UpdateOverlay then focusPrev.UpdateOverlay() end
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, focusTexColorGet, focusTexColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        rightRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isFocusTextureNone() or isFocusNoTint()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusTextureNone() or isFocusNoTint()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline Focus Texture cog (Opacity + No Tint), to the left of the swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = textureDualRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            disabled = isFocusTextureNone,
            disabledTooltip = "a Focus Texture",
            title = "Focus Texture",
            rows = {
                { type="slider", label="Opacity", min=5, max=100, step=1,
                  get=function() return math.floor(((DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha) * 100) + 0.5) end,
                  set=function(v)
                    DB().focusOverlayAlpha = v / 100
                    RefreshFocusPreview()
                  end },
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("focusOverlayFullBgAlpha")
                    if v == nil then return defaults.focusOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().focusOverlayFullBgAlpha = v
                    RefreshFocusPreview()
                  end },
                { type="toggle", label="Don't tint (keep bar's own color)",
                  tooltip="Tints the pattern with the bar's current color instead of the custom overlay color.",
                  get=isFocusNoTint,
                  set=function(v)
                    DB().focusOverlayNoTint = v
                    RefreshAllTextures()
                    RefreshFocusPreview()
                  end },
            },
        })
    end

    -- Target Preview ---- Focus Preview
    local previewDualRow
    previewDualRow, h = W:DualRow(parent, y,
        { type="label", text="Target Preview" },
        { type="label", text="Focus Preview" });  y = y - h

    if not EllesmereUI._prebuilding then
    targetPrev = LazyColorPreviewBar(previewDualRow, "health", "target", previewDualRow._leftRegion)
    do
        local function RepositionTargetBar()
            local rgn = previewDualRow._leftRegion
            for _, child in ipairs({ previewDualRow:GetChildren() }) do
                if child.GetNumPoints and child:GetNumPoints() > 0 then
                    local _, rel = child:GetPoint(1)
                    if rel == rgn then
                        child:ClearAllPoints()
                        PP.Point(child, "RIGHT", rgn, "RIGHT", -20, 0)
                        return
                    end
                end
            end
        end
        previewDualRow:HookScript("OnShow", RepositionTargetBar)
        C_Timer.After(0, RepositionTargetBar)
    end
    if isTargetColorDisabled() then
        targetPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
    end
    targetPrev.SetDisabled(isTargetColorDisabled())
    targetPrev.UpdateColor()
    end

    if not EllesmereUI._prebuilding then
    focusPrev = LazyColorPreviewBar(previewDualRow, "health", "focus", previewDualRow._rightRegion)
    do
        local function RepositionFocusBar()
            local rgn = previewDualRow._rightRegion
            for _, child in ipairs({ previewDualRow:GetChildren() }) do
                if child.GetNumPoints and child:GetNumPoints() > 0 then
                    local _, rel = child:GetPoint(1)
                    if rel == rgn then
                        child:ClearAllPoints()
                        PP.Point(child, "RIGHT", rgn, "RIGHT", -20, 0)
                        return
                    end
                end
            end
        end
        previewDualRow:HookScript("OnShow", RepositionFocusBar)
        C_Timer.After(0, RepositionFocusBar)
    end
    if isFocusColorDisabled() then
        focusPrev.SetColorOverride(function() return DBColor("enemyInCombat") end)
    end
    focusPrev.SetDisabled(isFocusColorDisabled())
    focusPrev.UpdateColor()
    end

    -- Hover Texture (+ Hover Effect opacity slider + color swatch): the mouseover highlight overlay and its opacity/color, at the bottom of this section.
    local hoverOverlayValues, hoverOverlayOrder = {}, {}
    do
        local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
        }
        hoverOverlayValues.none = "None"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "none"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, k in ipairs(STRIPE_ORDER) do hoverOverlayValues[k] = STRIPE_NAMES[k]; hoverOverlayOrder[#hoverOverlayOrder + 1] = k end
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, k in ipairs(hbtOrder) do
            -- "none" is already prepended above; skip the copy from hbtOrder (which starts with "none") so it shows only once.
            if k ~= "none" then
                hoverOverlayOrder[#hoverOverlayOrder + 1] = k
                if k ~= "---" then hoverOverlayValues[k] = hbtValues[k] end
            end
        end
        hoverOverlayValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then return nil end
                if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                end
                return ns.healthBarTextures and ns.healthBarTextures[key]
            end,
        }
    end
    do
        local hoverRow
        hoverRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Hover Texture",
              tooltip="Uses the Hover Effect color and opacity. Set to None for the flat hover highlight.",
              values=hoverOverlayValues, order=hoverOverlayOrder,
              getValue=function() return DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture end,
              setValue=function(v)
                DB().hoverOverlayTexture = v
                ns.RefreshHoverEffect()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Hover Effect",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h
        if not EllesmereUI._prebuilding then
        -- Hover Effect: the Target Effect model copied onto mouseover
        -- (user-directed 2026-08-16, no preview integration). Highlight is
        -- the only default-on channel and rides the legacy
        -- hoverColor/hoverAlpha keys, so every profile keeps its exact
        -- pre-rework hover visuals until other channels are opted in.
        local rightRgn = hoverRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local refreshHoverBorderSwatch
        local refreshHoverGlowSwatch
        local refreshHoverCog
        local hoverItems = {
            { key = "ellesmereui", label = "EUI Glow" },
            { key = "borderColor", label = "Border Color" },
            { key = "highlight",   label = "Highlight" },
            { key = "borderSize",  label = "Border Size",
              tooltip = "Change Size in the Cogwheel" },
        }
        local hvDD, hvDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 170, rightRgn:GetFrameLevel() + 2,
            hoverItems,
            function(k)
                if k == "ellesmereui" then return ns.GetHoverGlowEllesmereUI() end
                if k == "borderColor" then return ns.GetHoverGlowBorderColor() end
                if k == "highlight"   then return ns.GetHoverGlowHighlight() end
                if k == "borderSize"  then return ns.GetHoverGlowBorderSize() end
                return false
            end,
            function(k, v)
                if k == "ellesmereui" then DB().hoverGlowEllesmereUI = v
                elseif k == "borderColor" then DB().hoverGlowBorderColor = v
                elseif k == "highlight" then DB().hoverGlowHighlight = v
                elseif k == "borderSize" then
                    DB().hoverGlowBorderSize = v
                    -- First-enable snapshot: seed the cog slider with the user's
                    -- CURRENT border size, so enabling changes nothing until they
                    -- move it (one-time, never re-snapshots later).
                    if v and DB().hoverBorderSizeValue == nil then
                        if ns.IsCustomBorderEnabled() then
                            DB().hoverBorderSizeValue = DBVal("customBorderSize") or defaults.customBorderSize
                        else
                            DB().hoverBorderSizeValue = DBVal("borderSize") or defaults.borderSize
                        end
                    end
                end
                ns.RefreshHoverEffect()
                if refreshHoverBorderSwatch then refreshHoverBorderSwatch() end
                if refreshHoverGlowSwatch then refreshHoverGlowSwatch() end
                if refreshHoverCog then refreshHoverCog() end
            end)
        PP.Point(hvDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = hvDD
        rightRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(hvDDRefresh)

        -- Inline Border Color swatch: dimmed unless Border Color is checked.
        local hvBSwatch, hvUpdateBSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = ns.GetHoverBorderColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().hoverBorderColor = { r = r, g = g, b = b }
                ns.RefreshHoverEffect()
            end, nil, 20)
        PP.Point(hvBSwatch, "RIGHT", rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hvBSwatch
        hvBSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hvBSwatch, "Border Color") end)
        hvBSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshHoverBorderSwatch = function()
            local off = not ns.GetHoverGlowBorderColor()
            hvBSwatch:SetAlpha(off and 0.15 or 1)
            hvBSwatch:EnableMouse(not off)
            hvUpdateBSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshHoverBorderSwatch)
        refreshHoverBorderSwatch()

        -- Inline Glow Color swatch: dimmed unless EUI Glow is checked.
        local hvGSwatch, hvUpdateGSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = ns.GetHoverGlowColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().hoverGlowColor = { r = r, g = g, b = b }
                ns.RefreshHoverEffect()
            end, nil, 20)
        PP.Point(hvGSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hvGSwatch
        hvGSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hvGSwatch, "Glow Color") end)
        hvGSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshHoverGlowSwatch = function()
            local off = not ns.GetHoverGlowEllesmereUI()
            hvGSwatch:SetAlpha(off and 0.15 or 1)
            hvGSwatch:EnableMouse(not off)
            hvUpdateGSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshHoverGlowSwatch)
        refreshHoverGlowSwatch()

        -- Inline cog "More Effects": Highlight color/opacity (the legacy
        -- hoverColor/hoverAlpha keys) + Glow Opacity + Border Size.
        do
            local function hoverCogOff()
                return not (ns.GetHoverGlowHighlight() or ns.GetHoverGlowEllesmereUI()
                    or ns.GetHoverGlowBorderSize())
            end
            local hoverCogBtn = EllesmereUI.BuildInlineCog(rightRgn, {
                disabled = hoverCogOff,
                disabledTooltip = "a Hover Effect",
                title = "More Effects",
                rows = {
                    { type="colorpicker", label="Highlight Color", hasAlpha=false,
                      get=function()
                        local c = (DB() and DB().hoverColor) or defaults.hoverColor
                        return c.r, c.g, c.b
                      end,
                      set=function(r, g, b)
                        DB().hoverColor = { r = r, g = g, b = b }
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                    { type="slider", label="Highlight Opacity", min=0, max=100, step=1,
                      get=function()
                        return math.floor(((DBVal("hoverAlpha") or defaults.hoverAlpha) * 100) + 0.5)
                      end,
                      set=function(v)
                        DB().hoverAlpha = v / 100
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                    { type="slider", label="Glow Opacity", min=0, max=100, step=1,
                      get=function() return math.floor((ns.GetHoverGlowAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().hoverGlowAlpha = v / 100
                        ns.RefreshHoverEffect()
                      end },
                    { type="slider", label="Border Size", min=0, max=4, step=1,
                      get=function()
                        local v = DBVal("hoverBorderSizeValue")
                        if v ~= nil then return v end
                        if ns.IsCustomBorderEnabled() then
                            return DBVal("customBorderSize") or defaults.customBorderSize
                        end
                        return DBVal("borderSize") or defaults.borderSize
                      end,
                      set=function(v)
                        DB().hoverBorderSizeValue = v
                        ns.RefreshHoverEffect()
                      end,
                      disabled=function() return not ns.GetHoverGlowBorderSize() end,
                      disabledTooltip="Border Size Hover Effect" },
                },
            })
            refreshHoverCog = hoverCogBtn and hoverCogBtn._euiCogState
        end

        -- Inline Hover Texture cog (Full alpha on empty part of bar), left of the dropdown; disabled while set to None.
        local leftRgn = hoverRow._leftRegion
        local isHoverTextureNone = function()
            return (DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture) == "none"
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = isHoverTextureNone,
            disabledTooltip = "a Hover Texture",
            title = "Hover Texture",
            rows = {
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("hoverOverlayFullBgAlpha")
                    if v == nil then return defaults.hoverOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().hoverOverlayFullBgAlpha = v
                    ns.RefreshHoverEffect()
                    UpdatePreview()
                  end },
            },
        })
    end
        end

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
            icon = EllesmereUI.DIRECTIONS_ICON,
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

    -- Row 4: Shape | Border (inline color swatch + thickness cog on Border)
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

    -- Inline border color swatch + thickness cog on the Border toggle
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
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
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

        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON, gap = 9,
            disabled = borderOff,
            disabledTooltip = "Border",
            title = "Border Settings",
            rows = {
                { type="slider", label="Thickness", min=1, max=4, step=1,
                  get=function() return DBVal("classPowerBorderSize") or defaults.classPowerBorderSize end,
                  set=function(v) DB().classPowerBorderSize = v; ns.RefreshClassPower(); UpdatePreview() end },
            },
        })
    end
    end   -- close Class Resource hidden-while-disabled gate

    -- Invisible frame spanning the entire CLASS RESOURCE section for glow targeting
    local classResourceSection = CreateFrame("Frame", nil, parent)
    local crPad = EllesmereUI.CONTENT_PAD or 20
    classResourceSection:SetPoint("TOPLEFT", parent, "TOPLEFT", crPad, classResourceSectionTop)
    classResourceSection:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -crPad, classResourceSectionTop)
    classResourceSection:SetHeight(math.abs(classResourceSectionTop - y))
    classResourceSection._isSpacer = true  -- hide from search layout

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
            debuff = { text = "Debuff Duration", title = "Debuff Duration Settings", key = "debuffTimerPosition", count = 4, frames = function(p, i) return p.debuffs[i] end },
            buff = { text = "Buff Duration", title = "Buff Duration Settings", key = "buffTimerPosition", count = 4, frames = function(p, i) return p.buffs[i] end },
            cc = { text = "CC Duration", title = "CC Duration Settings", key = "ccTimerPosition", count = 2, frames = function(p, i) return p.cc[i] end },
        }
        local function DurationDropdown(kind)
            local cfg = durationTypes[kind]
            return { type="dropdown", text=cfg.text, values=timerPosValues,
              getValue=function() return DBVal(cfg.key) or atFallback end,
              setValue=function(v)
                DB()[cfg.key] = v
                LiveApplyTimerPos(cfg.frames, cfg.count, v, kind)
                UpdatePreview()
              end, order=timerPosOrder }
        end
        local function CurrentDurationPos(cfg)
            return DBVal(cfg.key) or atFallback
        end
        local function RefreshDuration(kind)
            local cfg = durationTypes[kind]
            LiveApplyTimerPos(cfg.frames, cfg.count, CurrentDurationPos(cfg), kind)
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
                RefreshDuration(kind)
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
            PP.Point(swatch, "RIGHT", region._control, "LEFT", -12, 0)
            region._lastInline = swatch
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)

            EllesmereUI.BuildInlineCog(region, {
                icon = EllesmereUI.RESIZE_ICON, gap = 9,
                title = cfg.title,
                rows = {
                    { type="slider", label="Size", min=6, max=20, step=1,
                      get=function() return AuraDurationVal(kind, "Size") end,
                      set=function(v) DB()[kind .. "DurationTextSize"] = v; RefreshDuration(kind) end },
                    { type="slider", label="X", min=-50, max=50, step=1,
                      get=function() return AuraDurationVal(kind, "X") end,
                      set=function(v) DB()[kind .. "DurationTextX"] = v; RefreshDuration(kind) end },
                    { type="slider", label="Y", min=-50, max=50, step=1,
                      get=function() return AuraDurationVal(kind, "Y") end,
                      set=function(v) DB()[kind .. "DurationTextY"] = v; RefreshDuration(kind) end },
                },
            })
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
                LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, v)
                LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, v)
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
            for _, plate in pairs(plates) do
                for i = 1, 4 do
                    if plate.debuffs[i] and plate.debuffs[i].count then
                        plate.debuffs[i].count:SetTextColor(r, g, b, 1)
                    end
                    if plate.buffs[i] and plate.buffs[i].count then
                        plate.buffs[i].count:SetTextColor(r, g, b, 1)
                    end
                end
            end
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end -- 12.1 containers
            UpdatePreview()
        end
        local asSwatch, asUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, asColorGet, asColorSet, nil, 20)
        PP.Point(asSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        rightRgn._lastInline = asSwatch
        EllesmereUI.RegisterWidgetRefresh(function() asUpdateSwatch() end)

        -- RIGHT: Aura Stacks inline cog (Size / X / Y)
        EllesmereUI.BuildInlineCog(rightRgn, {
            icon = EllesmereUI.RESIZE_ICON, gap = 9,
            title = "Aura Stacks Settings",
            rows = {
                { type="slider", label="Size", min=6, max=20, step=1,
                  get=function() return DBVal("auraStackTextSize") or defaults.auraStackTextSize end,
                  set=function(v)
                    DB().auraStackTextSize = v
                    for _, plate in pairs(plates) do
                        for i = 1, 4 do
                            if plate.debuffs[i] and plate.debuffs[i].count then
                                SetFSFont(plate.debuffs[i].count, v, "OUTLINE, SLUG")
                            end
                            if plate.buffs[i] and plate.buffs[i].count then
                                SetFSFont(plate.buffs[i].count, v, "OUTLINE, SLUG")
                            end
                        end
                    end
                    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end -- 12.1 containers
                    UpdatePreview()
                  end },
                { type="slider", label="X", min=-50, max=50, step=1,
                  get=function() return DBVal("auraStackTextX") or defaults.auraStackTextX end,
                  set=function(v)
                    DB().auraStackTextX = v
                    LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                    LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                    UpdatePreview()
                  end },
                { type="slider", label="Y", min=-50, max=50, step=1,
                  get=function() return DBVal("auraStackTextY") or defaults.auraStackTextY end,
                  set=function(v)
                    DB().auraStackTextY = v
                    LiveApplyStackPos(function(p, i) return p.debuffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                    LiveApplyStackPos(function(p, i) return p.buffs[i] end, 4, DBVal("auraStackTextPosition") or asFallback)
                    UpdatePreview()
                  end },
            },
        })
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
        local snSwatch, snUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, snColorGet, snColorSet, nil, 20)
        PP.Point(snSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function() snUpdateSwatch() end)

        -- LEFT: Spell Name inline cog for X/Y offset
        EllesmereUI.BuildInlineCog(leftRgn, {
            chain = false, anchorTo = snSwatch, gap = 6,
            icon = EllesmereUI.RESIZE_ICON,
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
                    widthGet = function() return DBVal("castNameWidthPct") or defaults.castNameWidthPct end,
                    widthSet = function(v) DB().castNameWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end,
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

        -- RIGHT: Spell Target inline double swatch (custom + class colored)
        local rightRgn = spellNameRow._rightRegion
        local ctrl = rightRgn._control

        -- Class colored swatch (rightmost)
        local ccGet = function()
            local _, ct = UnitClass("player")
            if ct and RAID_CLASS_COLORS[ct] then
                local cc = RAID_CLASS_COLORS[ct]
                return cc.r, cc.g, cc.b
            end
            return 1, 1, 1
        end
        local ccSwatch, ccUpdate = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, ccGet, function() end, nil, 20)
        PP.Point(ccSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
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

        -- RIGHT: Spell Target inline cog for X/Y offset
        EllesmereUI.BuildInlineCog(rightRgn, {
            chain = false, anchorTo = stSwatch, gap = 6,
            icon = EllesmereUI.RESIZE_ICON,
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
    end
    y = y - h

    return y, healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow,
        tfxHeader, targetGlowRow, classResourceHeader, classResourceSection, generalTextHeader,
        auraDurPosRow, auraTimerStackRow, spellNameRow
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildDisplayBars = BuildDisplayBars
