if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\VisualBars_Options.lua
--  Raid Frames options: the Health Bar, Absorbs, Power Bar and Text Display
--  sections of the raid and party pages. Called by BuildVisualSections; returns
--  y and the Health Bar custom-border gates Dispels reuses. Shared helpers come
--  from ns._RFO_OptEnv.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]
if not ns then return end  -- module disabled: no options page

local function BuildVisualBars(parent, y, W, onSection, EYE)
    local env = ns._RFO_OptEnv
    local AbbreviateNumbers, absorbStyleOrder, absorbStyleValues, db = env.AbbreviateNumbers, env.absorbStyleOrder, env.absorbStyleValues, env.db
    local hbtOrder, hbtValues, healAbsorbStyleOrder, healthColorOrder = env.hbtOrder, env.hbtValues, env.healAbsorbStyleOrder, env.healthColorOrder
    local healthColorValues, healthTextOrder, healthTextValues, IsPreviewOff = env.healthColorValues, env.healthTextOrder, env.healthTextValues, env.IsPreviewOff
    local maxHealthStyleOrder, namePositionOrder, namePositionOrderName, namePositionValues = env.maxHealthStyleOrder, env.namePositionOrder, env.namePositionOrderName, env.namePositionValues
    local namePositionValuesName, optState, PP, ReloadAndUpdate = env.namePositionValuesName, env.optState, env.PP, env.ReloadAndUpdate
    local SGet, SGetPx, SSet, SVal = env.SGet, env.SGetPx, env.SSet, env.SVal
    local SWrite = env.SWrite
    local _, h
    local row
    local _secY  -- section start tracker
    -------------------------------------------------------------------
    --  HEALTH BAR
    -------------------------------------------------------------------
    _secY = y
    local healthHeader
    healthHeader, h = W:SectionHeader(parent, "HEALTH BAR", y); y = y - h

    -- Eyeball: animate health bars (damage/healing simulation); built on raid + party pages, reads the active frame set via ns.PvActiveFrames().
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        -- State lives on ns (single shared ticker) so raid and party eyeball builds drive one animation and start/stop works across both. ns._healthAnimActive is the truth the renderer reads.
        ns._healthAnimState = ns._healthAnimState or {}

        local function StopHealthAnim()
            if ns._healthAnimTicker then
                ns._healthAnimTicker:Cancel()
                ns._healthAnimTicker = nil
            end
            ns._healthAnimActive = false
            -- Pause: persist animated values so they stay on screen.
            local phv = ns.PvHealthValues()
            if phv then
                for i, st in ipairs(ns._healthAnimState) do
                    phv[i] = st.current
                end
            end
        end
        -- Exposed for onModuleLeave below.
        ns.StopHealthAnim = StopHealthAnim

        local function StartHealthAnim()
            if ns._healthAnimTicker then return end
            ns._healthAnimActive = true
            wipe(ns._healthAnimState)

            local frames = ns.PvActiveFrames()
            for i = 1, 20 do
                local f = frames[i]
                if f and f._health then
                    ns._healthAnimState[i] = {
                        frame = f,
                        current = f._healthPct or (40 + math.random(60)),
                        target = 20 + math.random(80),
                        snapTimer = math.random() * 2,
                        nextSnap = 1.2 + math.random() * 1.6,
                    }
                end
            end

            local smoothInterp = Enum and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            ns._healthAnimTicker = C_Timer.NewTicker(0.1, function()
                if not ns._healthAnimActive then return end
                -- Real preview contract: ticks must render effective-overlay values only, never the panel view's swapped values.
                local s = ns.PvSettings()
                local smooth = s.smoothBars
                local invert = ns.RF_IsInvertedFill(s)

                for i, st in ipairs(ns._healthAnimState) do
                    local f = st.frame
                    if f and f._health and not f._pvHideHealthText then
                        -- Per-unit staggered timer, same cadence smooth or not.
                        st.snapTimer = st.snapTimer + 0.1
                        if st.snapTimer < st.nextSnap then
                        else
                            st.snapTimer = 0
                            st.nextSnap = 1.2 + math.random() * 1.6
                            st.current = st.target
                            st.target = 15 + math.random(85)

                            local barPct = invert and (100 - st.current) or st.current
                            if smooth and smoothInterp then
                                f._health:SetValue(barPct, smoothInterp)
                            else
                                f._health:SetValue(barPct)
                            end

                            if f._healthText then
                                local mode = s.healthTextMode or "none"
                                if mode == "percent" then
                                    f._healthText:SetFormattedText("%d%%", st.current)
                                elseif mode == "percentNoSign" then
                                    f._healthText:SetFormattedText("%d", st.current)
                                elseif mode == "number" then
                                    local fakeHP = st.current * 12000
                                    if AbbreviateNumbers then
                                        f._healthText:SetText(AbbreviateNumbers(fakeHP))
                                    end
                                elseif mode == "numberPercent" then
                                    local fakeHP = st.current * 12000
                                    local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
                                    f._healthText:SetFormattedText("%s | %d%%", numStr, st.current)
                                elseif mode == "percentNumber" then
                                    local fakeHP = st.current * 12000
                                    local numStr = AbbreviateNumbers and AbbreviateNumbers(fakeHP) or tostring(fakeHP)
                                    f._healthText:SetFormattedText("%d%% | %s", st.current, numStr)
                                elseif mode == "missing" then
                                    local fakeHP = (100 - st.current) * 12000
                                    f._healthText:SetText(C_StringUtil.TruncateWhenZero(fakeHP))
                                    if f._healthText:GetText() then
                                        if AbbreviateNumbers then
                                            f._healthText:SetText(AbbreviateNumbers(fakeHP))
                                        end
                                    end
                                end
                            end

                            -- Fill color only moves in gradient modes.
                            if s.healthColorMode == "classic" then
                                local pct = st.current / 100
                                local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
                                local g = pct > 0.5 and 1 or (pct * 2)
                                f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
                            elseif s.healthColorMode == "customDynamic" then
                                local r, g, b = ns.ResolveDynamicColor(s, st.current / 100)
                                f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
                            elseif s.healthColorMode == "classReactive" then
                                local r, g, b = ns.ResolveClassReactiveColor(s, f._classToken, st.current / 100)
                                f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
                            end
                        end -- snapTimer ready
                    end
                end
            end)
        end

        -- Eye button anchors to the section header's label FontString.
        local headerLabel
        for _, rgn in ipairs({ healthHeader:GetRegions() }) do
            if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "HEALTH BAR" then
                headerLabel = rgn; break
            end
        end
        local eyeBtn = CreateFrame("Button", nil, healthHeader)
        eyeBtn:SetSize(24, 24)
        if headerLabel then
            eyeBtn:SetPoint("LEFT", headerLabel, "RIGHT", 5, 0)
        else
            eyeBtn:SetPoint("LEFT", healthHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeBtn:SetFrameLevel(healthHeader:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshHealthEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                eyeBtn:SetAlpha(0.15)
                return
            end
            eyeTex:SetTexture(ns._healthAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
            eyeBtn:SetAlpha(0.4)
        end
        RefreshHealthEye()
        EYE.refreshHealthEye = RefreshHealthEye
        ns._stopHealthAnim = StopHealthAnim
        ns._startHealthAnim = StartHealthAnim
        eyeBtn:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            if ns._healthAnimActive then
                StopHealthAnim()
            else
                if ns._indicatorsVisible then
                    ns._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
                StartHealthAnim()
            end
            RefreshHealthEye()
            if ns.PvRefresh then ns.PvRefresh() end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._healthAnimActive and "Stop health bar effects" or "Preview health bar effects")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then self:SetAlpha(0.4) end
            EllesmereUI.HideWidgetTooltip()
        end)

        EllesmereUI:RegisterOnHide(function()
            if ns._healthAnimActive then StopHealthAnim(); RefreshHealthEye() end
        end)

        -- One-time eyeball hint, raid/main page only.
        if not optState._partyCtx and not (EllesmereUIDB and EllesmereUIDB.rfEyeHintSeen) then
            local TIP_W, TIP_H = 310, 82
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
            local ar, ag, ab = EG.r, EG.g, EG.b

            -- On the panel body like the other panel tips: it hides with the
            -- window when it collapses and rides the panel scale.
            local tip = CreateFrame("Frame", nil, EllesmereUI._panelBody)
            tip:SetFrameStrata("FULLSCREEN_DIALOG")
            tip:SetFrameLevel(200)
            if PP then PP.Size(tip, TIP_W, TIP_H) end
            tip:SetSize(TIP_W, TIP_H)
            tip:EnableMouse(true)
            tip:SetPoint("TOP", eyeBtn, "BOTTOM", 0, -14)

            local tipBg = tip:CreateTexture(nil, "BACKGROUND")
            tipBg:SetAllPoints()
            tipBg:SetColorTexture(0.06, 0.08, 0.10, 0.95)

            EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25, PP)

            -- Arrow pointing up (clipped diamond)
            local ARROW_SZ = 16
            local arrowClip = CreateFrame("Frame", nil, tip)
            arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
            arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
            arrowClip:SetClipsChildren(true)
            arrowClip:SetSize(ARROW_SZ * 2, ARROW_SZ)
            arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

            local arrowFrame = CreateFrame("Frame", nil, arrowClip)
            arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
            arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
            arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

            local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
            arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
            arrowBorder:SetPoint("CENTER")
            arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
            arrowBorder:SetRotation(math.rad(45))
            if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

            local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
            arrowFill:SetPoint("CENTER")
            arrowFill:SetColorTexture(0.06, 0.08, 0.10, 0.95)
            arrowFill:SetRotation(math.rad(45))
            if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

            local msg = EllesmereUI.MakeFont(tip, 10, nil, 1, 1, 1, 0.85)
            msg:SetPoint("TOP", tip, "TOP", 0, -12)
            msg:SetWidth(TIP_W - 24)
            msg:SetJustifyH("CENTER")
            msg:SetSpacing(4)
            msg:SetText(EllesmereUI.L("Click this eye icon to preview live\nhealth bar effects like absorbs and healing."))

            local okBtn = CreateFrame("Button", nil, tip)
            okBtn:SetSize(70, 22)
            okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 10)
            EllesmereUI.MakeStyledButton(okBtn, "Okay", 10,
                EllesmereUI.RB_COLOURS, function()
                    tip:Hide()
                    ns._rfEyeHintTip = nil
                    EllesmereUIDB = EllesmereUIDB or {}
                    EllesmereUIDB.rfEyeHintSeen = true
                end)

            ns._rfEyeHintTip = tip

            tip:SetAlpha(0)
            tip:Show()
            local fadeIn = 0
            tip:SetScript("OnUpdate", function(self, dt)
                fadeIn = fadeIn + dt
                if fadeIn >= 0.3 then
                    self:SetAlpha(1)
                    self:SetScript("OnUpdate", nil)
                    return
                end
                self:SetAlpha(fadeIn / 0.3)
            end)
        end
    end  -- close do (health eyeball)

    local texRow
    texRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Health Bar Texture", values=hbtValues, order=hbtOrder,
          getValue=function() return SVal("healthBarTexture", "atrocity") end,
          setValue=function(v) SSet("healthBarTexture", v) end },
        { type="slider", text="Fill Opacity", min=0, max=100, step=1,
          disabled=function() return SVal("healthColorMode", "class") == "dark" end,
          disabledTooltip="Not available in Dark Mode", rawTooltip=true,
          getValue=function() return SVal("healthBarOpacity", 100) end,
          setValue=function(v) SSet("healthBarOpacity", v) end });
    -- Vertical Fill cog lives in the Health Bar party-sync section, so an unsynced party tab keeps its own value.
    if not EllesmereUI._prebuilding then
        local lrgn = texRow._leftRegion
        EllesmereUI.BuildInlineCog(lrgn, {
            title = "Health Bar Fill",
            rows = {
                ns.RF_PartyKitGate({ type="toggle", label="Vertical Fill",
                  tooltip="Fill the health bar bottom-to-top instead of left-to-right. Absorbs, heal prediction and the bar background follow the same axis.",
                  get=function() return SVal("healthVerticalFill", false) end,
                  -- RefreshPage re-labels Absorbs Placement for the new axis; cog popups bake labels in on first build.
                  set=function(v) SSet("healthVerticalFill", v); EllesmereUI:RefreshPage() end }),
                ns.RF_PartyKitGate({ type="toggle", label="Fill Missing Health",
                  tooltip="The bar fills with missing health, growing as the unit takes damage.",
                  get=function() return SVal("healthInvertFill", false) end,
                  set=function(v) SSet("healthInvertFill", v) end }),
            },
        })
    end
    y = y - h

    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Fill Color", values=healthColorValues, order=healthColorOrder,
          tooltip="Custom Dynamic Colors: the health bar smoothly blends between three colors you pick -- one for full health (100%), one for half (50%), and one for empty (0%) -- shifting through them as the unit takes damage or is healed.",
          getValue=function() return SVal("healthColorMode", "class") end,
          setValue=function(v)
              SSet("healthColorMode", v)
              -- "dark" feeds the Dark Mode conditional-override condition.
              EllesmereUI.Conditions_Recheck()
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Background", min=0, max=100, step=1,
          disabled=function() return SVal("healthColorMode", "class") == "dark" end,
          disabledTooltip="Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Fonts & Colors.", rawTooltip=true,
          getValue=function() return SVal("bgDarkness", 50) end,
          setValue=function(v) SSet("bgDarkness", v) end });  y = y - h
    -- Fill Color's "dark" choice IS the Dark Mode condition's input, so lock the dropdown while a Dark Mode conditional is being edited -- else the override could capture a mode change that flips its own condition.
    if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
        EllesmereUI.SpecOverrides_AttachEditLock(row._leftRegion,
            "Fill Color's Dark Mode choice drives a Dark Mode override condition, so it can't be changed while editing an override",
            EllesmereUI.SpecOverrides_DarkCondEditActive)
    end
    -- Custom fill swatch plus the three Custom Dynamic stop swatches (100/50/0%) share one inline slot; the Fill Color mode decides which set is interactive.
    if not EllesmereUI._prebuilding then
        local rgn = row._leftRegion

        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local c = SGet("customFillColor")
                if c then return c.r, c.g, c.b, 1 end
                return 37/255, 193/255, 29/255, 1
            end,
            function(r, g, b)
                SWrite("customFillColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- Blocking overlay: non-clickable + tooltip unless Fill Color is Custom.
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints()
        block:SetFrameLevel(swatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, "Only available with Custom fill color") end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        -- Three gradient-stop swatches, built right-to-left so the visual order reads 100% | 50% | 0%; tooltips carry the pct.
        local dynDefs = {
            { key = "dynamicColor100", def = { r = 0, g = 1, b = 0 }, label = "100%", tip = "Health bar color at full (100%) health" },
            { key = "dynamicColor50",  def = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }, label = "50%",  tip = "Health bar color at half (50%) health" },
            { key = "dynamicColor0",   def = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }, label = "0%",   tip = "Health bar color at empty (0%) health" },
        }
        local dynSwatches = {}
        local prevAnchor = rgn._control
        for i = #dynDefs, 1, -1 do
            local dd = dynDefs[i]
            local sw = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3,
                function()
                    local c = SGet(dd.key) or dd.def
                    return c.r, c.g, c.b, 1
                end,
                function(r, g, b)
                    SWrite(dd.key, { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 18)
            sw:SetPoint("RIGHT", prevAnchor, "LEFT", (prevAnchor == rgn._control) and -8 or -6, 0)
            sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, dd.tip) end)
            sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            dynSwatches[i] = sw
            prevAnchor = sw
        end

        local function UpdateSwatchVis()
            local mode = SVal("healthColorMode", "class")
            local isDynamic = mode == "customDynamic"
            -- Class Reactive shares the dynamic stops but its 100% color IS
            -- the class color: only the 0%/50% swatches apply there.
            local isClassReactive = mode == "classReactive"
            -- Single custom swatch: live only in Custom mode, dimmed+blocked in other modes, fully HIDDEN in Dynamic/Class Reactive modes so it doesn't sit behind the dynamic swatches.
            if isDynamic or isClassReactive then
                swatch:Hide(); block:Hide()
            else
                swatch:Show()
                if mode == "custom" then swatch:SetAlpha(1); block:Hide()
                else swatch:SetAlpha(0.3); block:Show() end
            end
            for i, sw in ipairs(dynSwatches) do
                -- dynSwatches[1] = the 100% stop (class-driven in Class Reactive).
                if isDynamic or (isClassReactive and i > 1) then sw:Show() else sw:Hide() end
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateSwatchVis)
        UpdateSwatchVis()
    end
    -- Background Custom + Class swatch pair: clicking either toggles bgClassColored, the inactive one dims (mirrors the fill picker).
    do
        local rgn = row._rightRegion
        -- Class swatch shows the player's class color and is not editable.
        local bgClassSwatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local _, ct = UnitClass("player")
                local cc = ct and EllesmereUI.GetClassColor(ct)
                if cc then return cc.r, cc.g, cc.b, 1 end
                return 1, 1, 1, 1
            end,
            function() end, false, 20)
        bgClassSwatch:SetScript("OnClick", function()
            SSet("bgClassColored", true)
            ReloadAndUpdate(); EllesmereUI:RefreshPage()
        end)
        bgClassSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgClassSwatch, "Class Colored Background") end)
        bgClassSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgClassSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgClassSwatch

        local bgSwatch = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local c = SGet("customBgColor")
                if c then return c.r, c.g, c.b, 1 end
                return 17/255, 17/255, 17/255, 1
            end,
            function(r, g, b)
                SWrite("customBgColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if SVal("bgClassColored", false) then
                SSet("bgClassColored", false)
                ReloadAndUpdate(); EllesmereUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        bgSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Custom Background Color") end)
        bgSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgSwatch
        -- Blocking overlay spans BOTH swatches: Dark Mode has no background.
        local bgBlock = CreateFrame("Frame", nil, rgn)
        bgBlock:SetPoint("TOPLEFT", bgSwatch, "TOPLEFT", 0, 0)
        bgBlock:SetPoint("BOTTOMRIGHT", bgClassSwatch, "BOTTOMRIGHT", 0, 0)
        bgBlock:SetFrameLevel(bgClassSwatch:GetFrameLevel() + 10)
        bgBlock:EnableMouse(true)
        bgBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Fonts & Colors.") end)
        bgBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBgSwatchVis()
            if SVal("healthColorMode", "class") == "dark" then
                bgSwatch:SetAlpha(0.3); bgClassSwatch:SetAlpha(0.3); bgBlock:Show()
            else
                bgBlock:Hide()
                local classOn = SVal("bgClassColored", false)
                bgSwatch:SetAlpha(classOn and 0.3 or 1)
                bgClassSwatch:SetAlpha(classOn and 1 or 0.3)
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatchVis)
        UpdateBgSwatchVis()
    end

    ns._editTargets = ns._editTargets or {}

    local healPredRow
    healPredRow, h = W:DualRow(parent, y,
        { type="toggle", text="Heal Prediction",
          getValue=function() return SVal("healPrediction", false) end,
          setValue=function(v) SSet("healPrediction", v); EllesmereUI:RefreshPage() end },
        { type="slider", text="Prediction Opacity", min=5, max=100, step=1,
          disabled=function() return not SVal("healPrediction", false) end,
          disabledTooltip="Heal Prediction",
          getValue=function() return SVal("healPredOpacity", 75) end,
          setValue=function(v) SSet("healPredOpacity", v) end });  y = y - h
    ns._editTargets.healPrediction = healPredRow
    if not EllesmereUI._prebuilding then
        local rgn = healPredRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, healPredRow:GetFrameLevel() + 3,
            function()
                local c = SGet("healPredColor")
                if c then return c.r, c.g, c.b, 1 end
                return 102/255, 243/255, 102/255, 1
            end,
            function(r, g, b)
                SWrite("healPredColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local function UpdateHealPredSwatchVis()
            swatch:SetAlpha(SVal("healPrediction", false) and 1 or 0.3)
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateHealPredSwatchVis)
        UpdateHealPredSwatchVis()
    end

    -- Color Custom Borders (the Threat Borders and Dispel Border cogs) recolors the
    -- frame's own border, so it needs one to recolor: the EllesmereUI style, a Border
    -- Style other than Solid and a Border Size above 0 (runtime twin:
    -- ns.RF_CustomBorderOn). Cog rows re-check this on every open.
    local function CustomBorderOff()
        if ns.RF_Stock and ns.RF_Stock() then return true end
        local tex = SGet("borderTexture")
        return tex == nil or tex == "" or tex == "solid" or SVal("borderSize", 1) <= 0
    end
    local function CustomBorderOffTip()
        if ns.RF_Stock and ns.RF_Stock() then
            return EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Label("raidframes")
        end
        local tex = SGet("borderTexture")
        if tex == nil or tex == "" or tex == "solid" then
            return "This option requires a Border Style other than Solid."
        end
        return "This option requires a Border Size above 0."
    end

    local smoothThreatRow
    smoothThreatRow, h = W:DualRow(parent, y,
        { type="toggle", text="Smooth Health Bars",
          getValue=function() return SVal("smoothBars", true) end,
          setValue=function(v) SSet("smoothBars", v) end },
        { type="slider", text="Threat Borders", min=0, max=4, step=1,
          getValue=function() return SVal("threatBorderSize", 2) end,
          setValue=function(v) SSet("threatBorderSize", v) end });  y = y - h
    ns._editTargets.threat = smoothThreatRow
    ns._editTargets.animateBars = smoothThreatRow
    -- Cog on Threat Borders: Color Custom Borders recolors the frame's own border in
    -- the threat color on aggro, drawn instead of the inner border (the slider's
    -- size still applies whenever the recolor cannot).
    if not EllesmereUI._prebuilding then
        local rgn = smoothThreatRow._rightRegion
        -- Its only row needs a custom border: dimmed, with the reason, until there is one.
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = CustomBorderOff, disabledTooltip = CustomBorderOffTip, requireState = "disabled",
            title = "Threat Borders",
            rows = {
                { type="toggle", label="Color Custom Borders",
                  tooltip="Recolors the frame border in the threat color while the unit has aggro instead of drawing a separate border.",
                  disabled=CustomBorderOff,
                  disabledTooltip=CustomBorderOffTip,
                  requireState="disabled",
                  get=function() return SVal("threatCustomBorder", false) end,
                  set=function(v) SSet("threatCustomBorder", v) end },
            },
        })
    end

    -------------------------------------------------------------------
    --  ABSORBS
    --  Own party-sync section ("absorbs"); pre-split profiles inherit the
    --  Health Bar sync state via ns._NormalizePartySyncSections.
    -------------------------------------------------------------------
    local absorbsHeader
    if onSection then onSection("healthBar", _secY, y) end; _secY = y
    absorbsHeader, h = W:SectionHeader(parent, "ABSORBS", y); y = y - h

    -- Eyeball: toggle shield/heal-absorb effects on the preview frames.
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON

        local abLabel
        for _, rgn in ipairs({ absorbsHeader:GetRegions() }) do
            if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "ABSORBS" then
                abLabel = rgn; break
            end
        end
        local eyeBtn = CreateFrame("Button", nil, absorbsHeader)
        eyeBtn:SetSize(24, 24)
        if abLabel then
            eyeBtn:SetPoint("LEFT", abLabel, "RIGHT", 5, 0)
        else
            eyeBtn:SetPoint("LEFT", absorbsHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeBtn:SetFrameLevel(absorbsHeader:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        -- On ns so the preview renderer can read it.
        if ns._absorbsPreviewVisible == nil then ns._absorbsPreviewVisible = false end

        local function RefreshAbsorbEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                eyeBtn:SetAlpha(0.15)
                return
            end
            eyeTex:SetTexture(ns._absorbsPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
            eyeBtn:SetAlpha(0.4)
        end
        EYE.refreshAbsorbEye = RefreshAbsorbEye
        RefreshAbsorbEye()
        eyeBtn:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            ns._absorbsPreviewVisible = not ns._absorbsPreviewVisible
            -- Indicators suppress bar effects, so clear them.
            if ns._absorbsPreviewVisible and ns._indicatorsVisible then
                ns._indicatorsVisible = false
                if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
            end
            RefreshAbsorbEye()
            if ns.PvRefresh then ns.PvRefresh() end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._absorbsPreviewVisible and "Hide shield effects on preview" or "Show shield effects on preview")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then self:SetAlpha(0.4) end
            EllesmereUI.HideWidgetTooltip()
        end)
    end  -- close do (absorbs eyeball)

    local absorbRow
    absorbRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
          getValue=function() return SVal("absorbStyle", "none") end,
          setValue=function(v)
              -- Blizzard Glow Line follows the pick: on with Default Blizz Frames, off when
              -- leaving it, else kept. A set value is stored explicitly, so a party that
              -- starts keeping its own style here keeps the line it showed; an unset one
              -- stays unset and keeps following the style.
              local was = SVal("absorbStyle", "none")
              local glow = SGetPx("absorbGlowLine", "absorbStyle")
              if v == "blizzardModern" then
                  glow = true
              elseif was == "blizzardModern" then
                  glow = false
              end
              if glow ~= nil then SWrite("absorbGlowLine", glow == true) end
              SSet("absorbStyle", v)
              if v == "clean" then
                  SSet("absorbOpacity", 30)
              elseif v ~= "blizzardModern" then
                  -- Blizzard (Modern) hardcodes color+opacity in the renderer; leave saved opacity untouched.
                  SSet("absorbOpacity", 90)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Absorb Opacity", min=5, max=100, step=1,
          disabled=function()
              local st = SVal("absorbStyle", "none")
              return st == "none" or st == "blizzardModern"
          end,
          disabledTooltip="Absorb Style",
          getValue=function() return SVal("absorbOpacity", 90) end,
          setValue=function(v) SSet("absorbOpacity", v) end });  y = y - h
    ns._editTargets.absorbs = absorbRow
    if not EllesmereUI._prebuilding then
        local rgn = absorbRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, absorbRow:GetFrameLevel() + 3,
            function()
                local c = SGet("absorbColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b)
                SWrite("absorbColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- BuildColorSwatch has no disabled state, so a mouse-enabled frame on top eats clicks when the color isn't user-editable (no absorb, or hardcoded-color "Blizzard (Modern)").
        local swatchBlock = CreateFrame("Frame", nil, swatch)
        swatchBlock:SetAllPoints()
        swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
        swatchBlock:EnableMouse(true)
        swatchBlock:Hide()
        local function UpdateAbsorbSwatchVis()
            local st = SVal("absorbStyle", "none")
            local off = (st == "none" or st == "blizzardModern")
            swatch:SetAlpha(off and 0.3 or 1)
            if off then swatchBlock:Show() else swatchBlock:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
        UpdateAbsorbSwatchVis()
    end
    -- Inline cog: absorb placement (overlay / right edge / left edge)
    do
        local rgn = absorbRow._leftRegion
        -- Placement labels follow the FILL AXIS: saved values stay right/left (meaning the FAR/NEAR end of the fill), worded top/bottom on a vertical bar.
        -- MUTATE IN PLACE, never rebuild this table: RefreshPage's fast path skips a full rebuild and the cog popup is built once then cached, so a fresh table would never reach the widget. The popup re-reads values[get()] every show; _invalidateMenu makes an already-built menu re-read entries from this same table on next click.
        local absorbEdgeLabels = { overlay = "Overlay", overlayReverse = "Overlay Reverse", overlayReverseFull = "Overlay Reverse (Full)" }
        local absorbEdgeLabelsVert  -- last applied axis; nil until first sync
        -- (The Party Frames kit's bar always fills horizontally; decided at build.)
        local kitPage = ns.RF_OptPartyKit()
        -- Returns true ONLY when the axis flipped, so callers skip _invalidateMenu on unrelated refreshes -- it nils the cached menu and would break an open menu's wired click.
        local function SyncAbsorbEdgeLabels()
            local vert = (not kitPage) and SVal("healthVerticalFill", false) and true or false
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
                  disabled = function() return SVal("absorbStyle", "none") == "blizzardModern" end,
                  disabledTooltip = "Default Blizz Frames uses a fixed placement",
                  rawTooltip = true,
                  get=function() SyncAbsorbEdgeLabels(); return SVal("absorbEdgeMode", "overlay") end,
                  set=function(v) SSet("absorbEdgeMode", v) end },
                { type="dropdown", label="Show Overshield",
                  tooltip="Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                  values = { never = "Never", always = "Always", fromleft = "From Left" },
                  order = { "never", "always", "fromleft" },
                  -- From Left only exists in the plain Overlay placement:
                  -- edge modes have no overshield, Overlay Reverse
                  -- already clamps the whole absorb inside the fill and
                  -- its Full variant draws the excess from the origin edge.
                  itemDisabled=function(v)
                      return v == "fromleft" and SVal("absorbEdgeMode", "overlay") ~= "overlay"
                  end,
                  get=function()
                      -- Legacy boolean fallback: profiles saved before the
                      -- dropdown keep their toggle's meaning.
                      local m = SVal("overshieldMode", nil)
                      if m == nil then m = (SVal("showOvershield", true) == false) and "never" or "always" end
                      return m
                  end,
                  set=function(v)
                      -- Mirror the legacy boolean so pre-dropdown readers
                      -- (incl. the live-client profile) track Never/Always.
                      SSet("showOvershield", v ~= "never")
                      SSet("overshieldMode", v)
                  end },
                { type="toggle", label="Blizzard Glow Line",
                  tooltip="Adds the Default Blizz Frames glow line where the shield meets current health.",
                  disabled = function()
                      if (not kitPage) and SVal("healthVerticalFill", false) == true then return true end
                      return SVal("absorbEdgeMode", "overlay") == "left" and SVal("absorbStyle", "none") ~= "blizzardModern"
                  end,
                  disabledTooltip = "The glow line is not shown on a vertical fill or with the From Left Edge placement",
                  rawTooltip = true,
                  get=function()
                      -- Unset follows the style: on for Default Blizz Frames only.
                      local g = SGetPx("absorbGlowLine", "absorbStyle")
                      if g == nil then return SVal("absorbStyle", "none") == "blizzardModern" end
                      return g == true
                  end,
                  set=function(v) SSet("absorbGlowLine", v and true or false) end },
            },
        })
        -- Re-label on page refresh (Vertical Fill fires one) and drop any built menu so its entries rebuild with the new wording.
        EllesmereUI.RegisterWidgetRefresh(function()
            if not SyncAbsorbEdgeLabels() then return end
            local pf = cogShow and cogShow._popupFrame
            if pf and pf.GetChildren then
                for _, child in ipairs({ pf:GetChildren() }) do
                    if child._invalidateMenu then child._invalidateMenu() end
                end
            end
        end)
    end

    local function CurAbsorbBarPos()
        local p = SGet("absorbBarPosition")
        if p then return p end
        return SVal("absorbBarEnabled", false) and "aboveRight" or "none"
    end
    local absorbBarRow
    absorbBarRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Absorb Bar",
          values={ none="None", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", rightVertical="Right Edge (Vertical)", leftVertical="Left Edge (Vertical)" },
          order={ "none", "aboveRight", "aboveLeft", "topRight", "topLeft", "rightVertical", "leftVertical" },
          getValue=function() return CurAbsorbBarPos() end,
          setValue=function(v)
              SWrite("absorbBarEnabled", v ~= "none")  -- keep legacy flag in sync
              SSet("absorbBarPosition", v)
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Bar Height", min=1, max=20, step=1,
          disabled=function() return CurAbsorbBarPos() == "none" end,
          disabledTooltip="Absorb Bar",
          getValue=function() return SVal("absorbBarHeight", 4) end,
          setValue=function(v) SSet("absorbBarHeight", v) end });  y = y - h
    if not EllesmereUI._prebuilding then
        local rgn = absorbBarRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            -- Vertical Grow, its only setting, has no effect off the vertical positions.
            disabled = function()
                local p = CurAbsorbBarPos()
                return p ~= "rightVertical" and p ~= "leftVertical"
            end,
            disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
            rawTooltip = true,
            title = "Absorb Bar Rendering",
            rows = {
                { type="dropdown", label="Vertical Grow",
                  values = { up = "Up", down = "Down" },
                  order = { "up", "down" },
                  disabled = function()
                      local p = CurAbsorbBarPos()
                      return p ~= "rightVertical" and p ~= "leftVertical"
                  end,
                  disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                  rawTooltip = true,
                  get=function() return SVal("absorbBarGrowDir", "up") end,
                  set=function(v) SSet("absorbBarGrowDir", v) end },
            },
        })
    end
    -- The size slider reads as width for the vertical positions; retitle live.
    do
        local lbl = absorbBarRow._rightRegion._label
        local function UpdateAbsorbBarSizeLabel()
            local p = CurAbsorbBarPos()
            local vertical = p == "rightVertical" or p == "leftVertical"
            lbl:SetText(EllesmereUI.L(vertical and "Bar Width" or "Bar Height"))
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbBarSizeLabel)
        UpdateAbsorbBarSizeLabel()
    end
    if not EllesmereUI._prebuilding then
        local rgn = absorbBarRow._rightRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, absorbBarRow:GetFrameLevel() + 3,
            function()
                local c = SGet("absorbBarColor")
                if c then return c.r, c.g, c.b, c.a or 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b, a)
                SWrite("absorbBarColor", { r=r, g=g, b=b, a=a })
                ReloadAndUpdate()
            end, true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local function UpdateAbsorbBarSwatchVis()
            swatch:SetAlpha(CurAbsorbBarPos() ~= "none" and 1 or 0.3)
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
        UpdateAbsorbBarSwatchVis()
    end

    local healAbsorbRow
    healAbsorbRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Heal Absorb Style", values=absorbStyleValues, order=healAbsorbStyleOrder,
          getValue=function() return SVal("healAbsorbStyle", "clean") end,
          setValue=function(v)
              SSet("healAbsorbStyle", v)
              if v == "clean" then
                  SSet("healAbsorbOpacity", 50)
              else
                  SSet("healAbsorbOpacity", 75)
              end
              EllesmereUI:RefreshPage()
          end },
        { type="slider", text="Heal Absorb Opacity", min=5, max=100, step=1,
          disabled=function() return SVal("healAbsorbStyle", "clean") == "none" end,
          disabledTooltip="Heal Absorb Style",
          getValue=function() return SVal("healAbsorbOpacity", 75) end,
          setValue=function(v) SSet("healAbsorbOpacity", v) end });  y = y - h
    ns._editTargets.healAbsorbs = healAbsorbRow
    if not EllesmereUI._prebuilding then
        local rgn = healAbsorbRow._leftRegion
        local swatch = EllesmereUI.BuildColorSwatch(
            rgn, healAbsorbRow:GetFrameLevel() + 3,
            function()
                local c = SGet("healAbsorbColor")
                if c then return c.r or 0.8, c.g or 0.15, c.b or 0.15, 1 end
                return 0.8, 0.15, 0.15, 1
            end,
            function(r, g, b)
                SWrite("healAbsorbColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        -- Blocked for "none" and the pre-colored heal styles (healBlizzModern is hardcoded white).
        local swatchBlock = CreateFrame("Frame", nil, swatch)
        swatchBlock:SetAllPoints()
        swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
        swatchBlock:EnableMouse(true)
        swatchBlock:Hide()
        local function UpdateHealAbsorbSwatchVis()
            local st = SVal("healAbsorbStyle", "clean")
            local off = (st == "none" or st == "healBlizzModern" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
            swatch:SetAlpha(off and 0.3 or 1)
            if off then swatchBlock:Show() else swatchBlock:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
        UpdateHealAbsorbSwatchVis()
    end
    -- Inline cog: heal absorb placement (independent of shield absorb)
    do
        local rgn = healAbsorbRow._leftRegion
        -- Same axis-labelling contract as the shield absorb cog above (MUTATE IN PLACE; return true only on a real axis flip).
        local healAbsorbEdgeLabels = { overlay = "Overlay" }
        local healAbsorbEdgeLabelsVert  -- last applied axis; nil until first sync
        local kitPage = ns.RF_OptPartyKit()
        local function SyncHealAbsorbEdgeLabels()
            local vert = (not kitPage) and SVal("healthVerticalFill", false) and true or false
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
                  get=function() SyncHealAbsorbEdgeLabels(); return SVal("healAbsorbEdgeMode", "overlay") end,
                  set=function(v) SSet("healAbsorbEdgeMode", v) end },
                { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                  get=function() return SVal("healAbsorbBgOpacity", 25) end,
                  set=function(v) SSet("healAbsorbBgOpacity", v) end },
                { type="toggle", label="Show Over Dispels",
                  get=function() return SVal("healAbsorbOverDispel", false) == true end,
                  set=function(v) SSet("healAbsorbOverDispel", v) end },
            },
        })
        EllesmereUI.RegisterWidgetRefresh(function()
            if not SyncHealAbsorbEdgeLabels() then return end
            local pf = cogShow and cogShow._popupFrame
            if pf and pf.GetChildren then
                for _, child in ipairs({ pf:GetChildren() }) do
                    if child._invalidateMenu then child._invalidateMenu() end
                end
            end
        end)
    end

    do
        local function CurHealAbsorbBarPos()
            return SGet("healAbsorbBarPosition") or "none"
        end
        local healAbsorbBarRow
        healAbsorbBarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Heal Absorb Bar",
              values={ none="None", belowAbsorb="Below Absorb Bar", aboveRight="Above Frame Right", aboveLeft="Above Frame Left", topRight="Top Right", topLeft="Top Left", rightVertical="Right Edge (Vertical)", leftVertical="Left Edge (Vertical)" },
              order={ "none", "belowAbsorb", "aboveRight", "aboveLeft", "topRight", "topLeft", "rightVertical", "leftVertical" },
              getValue=function() return CurHealAbsorbBarPos() end,
              setValue=function(v) SSet("healAbsorbBarPosition", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Bar Height", min=1, max=20, step=1,
              disabled=function() return CurHealAbsorbBarPos() == "none" end,
              disabledTooltip="Heal Absorb Bar",
              getValue=function() return SVal("healAbsorbBarHeight", 4) end,
              setValue=function(v) SSet("healAbsorbBarHeight", v) end });  y = y - h
        if not EllesmereUI._prebuilding then
            local rgn = healAbsorbBarRow._rightRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, healAbsorbBarRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("healAbsorbBarColor")
                    if c then return c.r, c.g, c.b, c.a or 1 end
                    return 200/255, 29/255, 29/255, 1
                end,
                function(r, g, b, a)
                    SWrite("healAbsorbBarColor", { r=r, g=g, b=b, a=a })
                    ReloadAndUpdate()
                end, true, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local function UpdateHealAbsorbBarSwatchVis()
                swatch:SetAlpha(CurHealAbsorbBarPos() ~= "none" and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
            UpdateHealAbsorbBarSwatchVis()
        end
        if not EllesmereUI._prebuilding then
            local rgn = healAbsorbBarRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                -- Vertical Grow is inert off the vertical positions.
                disabled = function()
                    local p = CurHealAbsorbBarPos()
                    return p ~= "rightVertical" and p ~= "leftVertical"
                end,
                disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                rawTooltip = true,
                title = "Heal Absorb Bar Rendering",
                rows = {
                    { type="dropdown", label="Vertical Grow",
                      values = { up = "Up", down = "Down" },
                      order = { "up", "down" },
                      disabled = function()
                          local p = CurHealAbsorbBarPos()
                          return p ~= "rightVertical" and p ~= "leftVertical"
                      end,
                      disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                      rawTooltip = true,
                      get=function() return SVal("healAbsorbBarGrowDir", "up") end,
                      set=function(v) SSet("healAbsorbBarGrowDir", v) end },
                },
            })
        end
        -- The size slider reads as width for the vertical positions; retitle live.
        do
            local lbl = healAbsorbBarRow._rightRegion._label
            local function UpdateHealAbsorbBarSizeLabel()
                local p = CurHealAbsorbBarPos()
                local vertical = p == "rightVertical" or p == "leftVertical"
                lbl:SetText(EllesmereUI.L(vertical and "Bar Width" or "Bar Height"))
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSizeLabel)
            UpdateHealAbsorbBarSizeLabel()
        end
    end

    -- Max Health Texture (+swatch+cog) | Max Health Opacity. Styles mirror Heal Absorb plus "Max Health Stripes" first; no placement control, overlay is always right-anchored.
    do
        local maxHealthRow
        maxHealthRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Max Health Style", values=absorbStyleValues,
              order=maxHealthStyleOrder,
              getValue=function() return SVal("maxHealthStyle", "maxHealthStripes") end,
              setValue=function(v) SSet("maxHealthStyle", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Max Health Opacity", min=5, max=100, step=1,
              disabled=function() return SVal("maxHealthStyle", "maxHealthStripes") == "none" end,
              disabledTooltip="Max Health Style",
              getValue=function() return SVal("maxHealthOpacity", 100) end,
              setValue=function(v) SSet("maxHealthOpacity", v) end });  y = y - h
        -- Swatch tints the max health texture.
        if not EllesmereUI._prebuilding then
            local rgn = maxHealthRow._leftRegion
            local swatch = EllesmereUI.BuildColorSwatch(
                rgn, maxHealthRow:GetFrameLevel() + 3,
                function()
                    local c = SGet("maxHealthColor")
                    if c then return c.r or 0.7, c.g or 0.1, c.b or 0.1, 1 end
                    return 0.7, 0.1, 0.1, 1
                end,
                function(r, g, b)
                    SWrite("maxHealthColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch
            -- Blocked for "none" and the pre-colored styles.
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:Hide()
            local function UpdateMaxHealthSwatchVis()
                local st = SVal("maxHealthStyle", "maxHealthStripes")
                local off = (st == "none" or st == "healBlizzModern" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR")
                swatch:SetAlpha(off and 0.3 or 1)
                if off then swatchBlock:Show() else swatchBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateMaxHealthSwatchVis)
            UpdateMaxHealthSwatchVis()
        end
        -- Cog carries backing opacity only; placement is fixed right-side.
        if not EllesmereUI._prebuilding then
            local rgn = maxHealthRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Max Health Rendering",
                rows = {
                    { type="slider", label="Backing Opacity", min=0, max=100, step=1,
                      get=function() return SVal("maxHealthBgOpacity", 100) end,
                      set=function(v) SSet("maxHealthBgOpacity", v) end },
                },
            })
        end
    end

    -------------------------------------------------------------------
    --  POWER BAR
    -------------------------------------------------------------------
    local powerHeader
    if onSection then onSection("absorbs", _secY, y) end; _secY = y
    powerHeader, h = W:SectionHeader(parent, "POWER BAR", y); y = y - h

    -- Power bar animation: same pattern as health, serves raid + party.
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        -- On ns: single ticker, resolves the active preview at call time.
        ns._powerAnimState = ns._powerAnimState or {}

        local function StopPowerAnim()
            if ns._powerAnimTicker then
                ns._powerAnimTicker:Cancel()
                ns._powerAnimTicker = nil
            end
            ns._powerAnimActive = false
            local ppv = ns.PvPowerValues()
            if ppv then
                for i, st in ipairs(ns._powerAnimState) do
                    ppv[i] = st.current
                end
            end
        end
        -- Exposed for onModuleLeave below.
        ns.StopPowerAnim = StopPowerAnim

        local function StartPowerAnim()
            if ns._powerAnimTicker then return end
            ns._powerAnimActive = true
            wipe(ns._powerAnimState)

            local frames = ns.PvActiveFrames()
            for i = 1, 20 do
                local f = frames[i]
                if f and f._power and f._power:IsShown() then
                    local cur = f._powerPct or (50 + math.random(50))
                    ns._powerAnimState[i] = {
                        frame = f,
                        current = cur,
                        target = math.max(10, math.min(100, cur + math.random(-8, 8))),
                        snapTimer = math.random() * 3,
                        nextSnap = 1.8 + math.random() * 2.3,
                    }
                end
            end

            local pwSmoothInterp = Enum and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            ns._powerAnimTicker = C_Timer.NewTicker(0.1, function()
                if not ns._powerAnimActive then return end
                -- Effective overlay; see the health ticker note above.
                local smooth = ((ns.PvEffectiveProfile and ns.PvEffectiveProfile())
                    or db.profile).smoothPowerBars

                for i, st in pairs(ns._powerAnimState) do
                    local f = st.frame
                    if f and f._power then
                        st.snapTimer = st.snapTimer + 0.1
                        if st.snapTimer < st.nextSnap then
                        else
                            st.snapTimer = 0
                            st.nextSnap = 2.5 + math.random() * 3
                            st.current = st.target
                            st.target = math.max(10, math.min(100, st.current + math.random(-8, 8)))

                            if smooth and pwSmoothInterp then
                                f._power:SetValue(st.current, pwSmoothInterp)
                            else
                                f._power:SetValue(st.current)
                            end
                            -- Power Text follows the animated value (ApplyPreviewData sets f._pwtMode; nil = hidden).
                            if f._pwtMode then ns.RF_PowerTextInto(f._powerText, f._pwtMode, st.current, nil, nil, f._pwtPer) end
                        end
                    end
                end
            end)
        end

        local pwLabel
        for _, rgn in ipairs({ powerHeader:GetRegions() }) do
            if rgn.GetText and EllesmereUI.EnKey(rgn:GetText()) == "POWER BAR" then
                pwLabel = rgn; break
            end
        end
        local eyeBtn = CreateFrame("Button", nil, powerHeader)
        eyeBtn:SetSize(24, 24)
        if pwLabel then
            eyeBtn:SetPoint("LEFT", pwLabel, "RIGHT", 5, 0)
        else
            eyeBtn:SetPoint("LEFT", powerHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeBtn:SetFrameLevel(powerHeader:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshPowerEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                eyeBtn:SetAlpha(0.15)
                return
            end
            eyeTex:SetTexture(ns._powerAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
            eyeBtn:SetAlpha(0.4)
        end
        EYE.refreshPowerEye = RefreshPowerEye
        ns._stopPowerAnim = StopPowerAnim
        RefreshPowerEye()
        eyeBtn:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            if ns._powerAnimActive then
                StopPowerAnim()
            else
                if ns._indicatorsVisible then
                    ns._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
                StartPowerAnim()
            end
            RefreshPowerEye()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, ns._powerAnimActive and "Stop power animation" or "Animate power bars")
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then self:SetAlpha(0.4) end
            EllesmereUI.HideWidgetTooltip()
        end)

        EllesmereUI:RegisterOnHide(function()
            if ns._powerAnimActive then StopPowerAnim(); RefreshPowerEye() end
        end)
    end  -- close do (power eyeball)

    -- Power bar is off when no role is selected.
    -- The Party Frames kit's mana bar always shows. Decided at build time:
    -- the page being built is only known then, and this runs on refreshes.
    local IsPowerOff = ns.RF_OptPartyKit() and function() return false end or function()
        return not SVal("powerShowForHealer", true) and not SVal("powerShowForTank", true) and not SVal("powerShowForDPS", false)
    end

    do
        local showForItems = {
            { key = "healer", label = "Healers" },
            { key = "tank",   label = "Tanks" },
            { key = "dps",    label = "DPS" },
        }
        local showForKeyMap = { healer = "powerShowForHealer", tank = "powerShowForTank", dps = "powerShowForDPS" }
        -- Party Frames kit: the stock mana bar always shows at the stock
        -- size, so this row (and its cog) hides on the Party page.
        row, h = W:DualRow(parent, y,
            ns.RF_PartyKitGate({ type="dropdown", text="Show Power Bar For",
              values={ __placeholder = "Healers, Tanks" }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end }),
            ns.RF_PartyKitGate({ type="slider", text="Power Height", min=1, max=20, step=1,
              disabled=function() return IsPowerOff() end,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerHeight", 4) end,
              setValue=function(v) SSet("powerHeight", v) end }));  y = y - h
        -- Cog: uniform icon anchoring. Greyed + blocked while no role shows a power bar (nothing to ignore then).
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = IsPowerOff, disabledTooltip = "Show Power Bar For",
                title = "Power Height",
                rows = {
                    { type="toggle", label="Icons Ignore Power Bar",
                      tooltip="Anchor icons and text as if no power bar existed, so frames with and without one line up identically.",
                      get=function() return SVal("powerUniformAnchors", false) end,
                      set=function(v) SSet("powerUniformAnchors", v) end },
                    { type="toggle", label="Extend Health Bar Behind Power",
                      tooltip="Health bar spans the full frame height and the power bar draws on top of it.",
                      get=function() return SVal("extendHealthBehindPower", false) end,
                      set=function(v) SSet("extendHealthBehindPower", v) end },
                },
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 170, rgn:GetFrameLevel() + 2,
                showForItems,
                function(k) return SVal(showForKeyMap[k], true) end,
                function(k, v)
                    SSet(showForKeyMap[k], v)
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
        end
    end

    local pwBorderStyleValues = {
        eui     = "EllesmereUI",
        divider = "Divider",
        border  = "Border",
    }
    local pwBorderStyleOrder = { "eui", "divider", "border" }
    -- Classic WoW UI draws the stock health/power divider in place of the
    -- power border (Blizzard Style has none, so the row stays there).
    local function PwClassicGate(cfg)
        if EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Active("raidframes") == "classic" then
            return EllesmereUI.BlizzStyle.Gate("raidframes", cfg)
        end
        return cfg
    end
    local pwBdrRow
    local function CanMatchPowerBorder()
        local key = SGet("borderTexture")
        return not EllesmereUI.BlizzStyle.Get("raidframes") and (key == "pixels" or key == "pixels-textured")
    end
    local function MatchingPowerBorder()
        return SVal("powerBorderMatchFrame", false) and CanMatchPowerBorder() and SVal("powerBorderStyle", "eui") ~= "eui"
    end
    local pwSizeCfg
    if MatchingPowerBorder() then
        pwSizeCfg = EllesmereUI.BorderPxSliderCfg({
            getStep=function() return SVal("borderSize", 1) end,
            setStep=function() end,
            getTex=function() return SGet("borderTexture") end,
            getPx=function() return SGetPx("borderSizePx", "borderSize") end,
            setPx=function() end,
            disabled=function() return true end,
            disabledTooltip="Size and color follow the frame border while Match Frame Border is enabled.",
            rawTooltip=true,
        })
    else
        pwSizeCfg = { type="slider", text="Border Size", min=0, max=4, step=1,
            disabled=function() return IsPowerOff() or SVal("powerBorderStyle", "eui") == "eui" end,
            disabledTooltip="Show Power Bar For",
            getValue=function() return SVal("powerBorderSize", 1) end,
            setValue=function(v) SSet("powerBorderSize", v) end }
    end
    pwBdrRow, h = W:DualRow(parent, y,
        ns.RF_PartyKitGate(PwClassicGate({ type="dropdown", text="Border Style", values=pwBorderStyleValues, order=pwBorderStyleOrder,
          disabled=function() return IsPowerOff() end,
          disabledTooltip="Show Power Bar For",
          getValue=function() return SVal("powerBorderStyle", "divider") end,
          setValue=function(v)
              SSet("powerBorderStyle", v)
              EllesmereUI:RefreshPage(SVal("powerBorderMatchFrame", false) and CanMatchPowerBorder())
          end })),
        ns.RF_PartyKitGate(PwClassicGate(pwSizeCfg)));  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(pwBdrRow._leftRegion, {
            disabled=function() return IsPowerOff() or not CanMatchPowerBorder() end,
            disabledTooltip=function() return IsPowerOff() and "Show Power Bar For" or "Pixels or Pixels Textured Border Style" end,
            title="Power Border Options",
            rows={
                { type="toggle", label="Match Frame Border",
                  tooltip="Divider and Border follow the frame's Pixels style, size, color and transparency. Divider is hidden below Power Height 4. EllesmereUI keeps its fixed white line.",
                  get=function() return SVal("powerBorderMatchFrame", false) end,
                  set=function(v) SSet("powerBorderMatchFrame", v); EllesmereUI:RefreshPage(true) end },
                { type="toggle", label="Match Highlight Colors",
                  tooltip="Divider follows the frame border's highlight colors and transparency, including hover and target. When off, it keeps the normal frame border color.",
                  disabled=function() return not MatchingPowerBorder() or SVal("powerBorderStyle", "eui") ~= "divider" end,
                  disabledTooltip="Requires Match Frame Border and Divider.",
                  rawTooltip=true,
                  get=function() return SVal("powerBorderMatchColor", false) end,
                  set=function(v) SSet("powerBorderMatchColor", v) end },
            },
        })
        local rgn = pwBdrRow._rightRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, pwBdrRow:GetFrameLevel() + 3,
            function()
                if MatchingPowerBorder() then
                    local c = SGet("borderColor")
                    return c and c.r or 0, c and c.g or 0, c and c.b or 0, SVal("borderAlpha", 1)
                end
                local c = SGet("powerBorderColor")
                if c then return c.r, c.g, c.b, SVal("powerBorderAlpha", 1) end
                return 0, 0, 0, 1
            end,
            function(r, g, b, a)
                SWrite("powerBorderColor", { r=r, g=g, b=b })
                SWrite("powerBorderAlpha", a)
                ReloadAndUpdate()
            end, true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10); block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, MatchingPowerBorder()
                and "Size and color follow the frame border while Match Frame Border is enabled."
                or EllesmereUI.DisabledTooltip("Border Style"))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdatePwBdrSwatchState()
            local off = IsPowerOff() or SVal("powerBorderSize", 1) == 0 or SVal("powerBorderStyle", "eui") == "eui" or MatchingPowerBorder()
            if off then swatch:SetAlpha(0.3); block:Show() else swatch:SetAlpha(1); block:Hide() end
        end
        EllesmereUI.RegisterWidgetRefresh(function() if updateSwatch then updateSwatch() end; UpdatePwBdrSwatchState() end)
        UpdatePwBdrSwatchState()
    end

    local pwBgRow
    pwBgRow, h = W:DualRow(parent, y,
        { type="toggle", text="Smooth Power Bars",
          disabled=function() return IsPowerOff() end,
          disabledTooltip="Show Power Bar For",
          getValue=function() return SVal("smoothPowerBars", true) end,
          setValue=function(v) SSet("smoothPowerBars", v) end },
        { type="slider", text="Background", min=0, max=100, step=1,
          disabled=function() return IsPowerOff() end,
          disabledTooltip="Show Power Bar For",
          getValue=function() return SVal("powerBgDarkness", 70) end,
          setValue=function(v) SSet("powerBgDarkness", v) end });  y = y - h
    -- Power bg Custom + Power Colored swatch pair: clicking either toggles powerBgPowerColored, the inactive one dims (mirrors the health bg).
    do
        local rgn = pwBgRow._rightRegion
        -- Power swatch shows the player's power color and is not editable.
        local bgPwrSwatch = EllesmereUI.BuildColorSwatch(
            rgn, pwBgRow:GetFrameLevel() + 3,
            function()
                local _, pToken = UnitPowerType("player")
                local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                if info then return info.r * f, info.g * f, info.b * f, 1 end
                return 0, 0.5 * f, f, 1
            end,
            function() end, false, 20)
        bgPwrSwatch:SetScript("OnClick", function()
            SSet("powerBgPowerColored", true)
            EllesmereUI:RefreshPage()
        end)
        bgPwrSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgPwrSwatch, "Power Colored Background. Power colors can be adjusted in Global Settings -> Fonts & Colors.") end)
        bgPwrSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgPwrSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgPwrSwatch

        local bgSwatch = EllesmereUI.BuildColorSwatch(
            rgn, pwBgRow:GetFrameLevel() + 3,
            function()
                local c = SGet("powerBgColor")
                if c then return c.r, c.g, c.b, 1 end
                return 0, 0, 0, 1
            end,
            function(r, g, b)
                SWrite("powerBgColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if SVal("powerBgPowerColored", false) then
                SSet("powerBgPowerColored", false)
                EllesmereUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        bgSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(bgSwatch, "Custom Colored Background") end)
        bgSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        bgSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = bgSwatch

        local function UpdatePwBgSwatchVis()
            local pwrOn = SVal("powerBgPowerColored", false)
            bgSwatch:SetAlpha(pwrOn and 0.3 or 1)
            bgPwrSwatch:SetAlpha(pwrOn and 1 or 0.3)
        end
        EllesmereUI.RegisterWidgetRefresh(UpdatePwBgSwatchVis)
        UpdatePwBgSwatchVis()
    end

    -------------------------------------------------------------------
    --  TEXT DISPLAY
    -------------------------------------------------------------------
    if onSection then onSection("powerBar", _secY, y) end; _secY = y
    _, h = W:SectionHeader(parent, "TEXT DISPLAY", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type="slider", text="Name Size", min=6, max=26, step=1,
          getValue=function() return SVal("nameSize", 10) end,
          setValue=function(v) SSet("nameSize", v) end },
        { type="multiSwatch", text="Name Color",
          swatches = {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = SGet("nameCustomColor")
                  if c then return c.r, c.g, c.b end
                  return 1, 1, 1
              end,
              setValue = function(r, g, b)
                  SWrite("nameCustomColor", { r=r, g=g, b=b })
                  ReloadAndUpdate()
              end,
              onClick = function(self)
                  if SVal("nameColorMode", "class") ~= "custom" then
                      SSet("nameColorMode", "custom")
                      EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  return SVal("nameColorMode", "class") == "custom" and 1 or 0.3
              end },
            { tooltip = "Class Color",
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
                  SSet("nameColorMode", "class")
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("nameColorMode", "class") == "class" and 1 or 0.3
              end },
            { tooltip = "Accent Color",
              hasAlpha = false,
              getValue = function()
                  return EllesmereUI.ResolveActiveAccent()
              end,
              setValue = function() end,
              onClick = function()
                  SSet("nameColorMode", "accent")
                  EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  return SVal("nameColorMode", "class") == "accent" and 1 or 0.3
              end },
          } });  y = y - h
    -- Name char cap + text stacking cog, on the Name Size slider. WoW Forever
    -- heads it with Name Format (the character name's first or last word; First
    -- and Last is the default). "full" is stored, not nil: a party section's nil
    -- would fall through to the raid value.
    do
        local rgn = row._leftRegion
        local nameRows = {
            { type="slider", label="Max Characters (0=off)", min=0, max=30, step=1,
              get=function() return SVal("nameMaxLength", 15) end,
              set=function(v) SSet("nameMaxLength", v) end },
            { type="toggle", label="Show Above Icons",
              tooltip="Render the name and health text above buff and debuff icons.",
              get=function() return SVal("nameTextAboveIcons", false) end,
              set=function(v) SSet("nameTextAboveIcons", v) end },
        }
        if EllesmereUI.IS_FOREVER then
            table.insert(nameRows, 1, { type="dropdown", label="Name Format",
                values={ first = "First Name", last = "Last Name", full = "First and Last" },
                order={ "first", "last", "full" },
                get=function() return SVal("nameFormat", "full") end,
                set=function(v) SSet("nameFormat", v) end })
        end
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Name Text",
            rows = nameRows,
        })
    end

    -- Party Frames kit: the name has the stock spot (its offsets stay on
    -- the cog), so the dropdown only chooses shown or None.
    row, h = W:DualRow(parent, y,
        ns.RF_OptPartyKit() and { type="dropdown", text="Name Position",
          values={ kit = "Party Frame", none = "None" }, order={ "kit", "none" },
          getValue=function() return (SVal("namePosition", "center") == "none") and "none" or "kit" end,
          setValue=function(v)
              if v == "none" then SSet("namePosition", "none")
              elseif SVal("namePosition", "center") == "none" then SSet("namePosition", "topleft") end
          end }
        or { type="dropdown", text="Name Position", values=namePositionValuesName, order=namePositionOrderName,
          getValue=function() return SVal("namePosition", "center") end,
          setValue=function(v) SSet("namePosition", v) end },
        { type="dropdown", text="Health Text", values=healthTextValues, order=healthTextOrder,
          getValue=function() return SVal("healthTextMode", "none") end,
          -- Rebuilds the page on the None <-> not-None flip so the Position/Size row below appears/vanishes.
          setValue=EllesmereUI.DependentSetValue(
              function() return SVal("healthTextMode", "none") ~= "none" end,
              function(v) SSet("healthTextMode", v) end) });  y = y - h
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Name Offset",
            rows = {
                { type="slider", label="Offset X", min=-500, max=500, step=1,
                  get=function() return SVal("nameOffsetX", 0) end,
                  set=function(v) SSet("nameOffsetX", v) end },
                { type="slider", label="Offset Y", min=-500, max=500, step=1,
                  get=function() return SVal("nameOffsetY", 0) end,
                  set=function(v) SSet("nameOffsetY", v) end },
            },
        })
    end
    -- Health Text color swatches (custom/class/accent), mirroring the Name Color triple. Custom is added FIRST so the _lastInline chain places it next to the dropdown, matching Name Color.
    if not EllesmereUI._prebuilding then
        local rgn = row._rightRegion
        local function AddHTSwatch(getColor, setColor, mode, opensPicker, tooltip)
            local sw = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = sw
            -- Preserve the picker-opening click, then switch mode on click (same technique multiSwatch uses for Name Color).
            sw._eabOrigClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self)
                if SVal("healthTextColorMode", "custom") ~= mode then
                    SSet("healthTextColorMode", mode)
                    EllesmereUI:RefreshPage()
                    return
                end
                if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
            end)
            -- HookScript so BuildColorSwatch's own hover stays intact.
            if tooltip then
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            local function vis()
                sw:SetAlpha(SVal("healthTextColorMode", "custom") == mode and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(vis)
            vis()
        end
        -- Custom (rightmost): editable, opens the picker when active.
        AddHTSwatch(
            function()
                local c = SGet("healthTextCustomColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 1, 1, 1
            end,
            function(r, g, b)
                SWrite("healthTextCustomColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, "custom", true, "Custom Color")
        AddHTSwatch(
            function()
                local _, ct = UnitClass("player")
                if ct and RAID_CLASS_COLORS[ct] then
                    local cc = RAID_CLASS_COLORS[ct]
                    return cc.r, cc.g, cc.b, 1
                end
                return 1, 1, 1, 1
            end,
            function() end, "class", false, "Class Color")
        -- Accent (leftmost).
        AddHTSwatch(
            function()
                local r, g, b = EllesmereUI.ResolveActiveAccent()
                return r or 1, g or 1, b or 1, 1
            end,
            function() end, "accent", false, "Accent Color")
    end

    -- Health Text Position (+ cog for X/Y) | Health Text Size. Hidden entirely while Health Text is None.
    if SVal("healthTextMode", "none") ~= "none" then
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Health Text Position", values=namePositionValues, order=namePositionOrder,
          getValue=function() return SVal("healthTextPosition", "center") end,
          setValue=function(v) SSet("healthTextPosition", v) end },
        { type="slider", text="Health Text Size", min=6, max=26, step=1,
          getValue=function() return SVal("healthTextSize", 9) end,
          setValue=function(v) SSet("healthTextSize", v) end });  y = y - h
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Health Text Offset",
            rows = {
                { type="slider", label="Offset X", min=-150, max=150, step=1,
                  get=function() return SVal("healthTextOffsetX", 0) end,
                  set=function(v) SSet("healthTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-75, max=75, step=1,
                  get=function() return SVal("healthTextOffsetY", 0) end,
                  set=function(v) SSet("healthTextOffsetY", v) end },
            },
        })
    end
    end   -- close Health Text dependent-row gate

    -- Level Position (+ offset cog) | Level Size: the unit's level in front of the name inside
    -- the name text ("Attach to Name", the WoW Forever default, None on retail: "60 Name"; "(Divider)": "60 | Name"; both
    -- follow the Name Size), or in the name's colour on its own spot. None = off.
    do
        local levelPosValues = { name = "Attach to Name", nameDiv = "Attach to Name (Divider)" }
        for k, v in pairs(namePositionValuesName) do levelPosValues[k] = v end
        local levelPosOrder = { "name", "nameDiv", "topleft", "top", "topright", "left", "center",
            "right", "bottomleft", "bottom", "bottomright", "none" }
        local function LvlPos() return SVal("levelTextPosition", ns.RF_LEVEL_DEFAULT) end
        local function LvlAttached() return ns.RF_LEVEL_ATTACH[LvlPos()] ~= nil end
        local function LvlSpotOff() return LvlPos() == "none" or LvlAttached() end
        local function LvlReq()
            return LvlAttached() and "Attached to the name, the level uses the Name Size." or "Level Position"
        end
        local function LvlCogReq()
            return LvlAttached() and "Attached to the name, the level follows the name's position." or "Level Position"
        end
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Level Position", values=levelPosValues, order=levelPosOrder,
              getValue=LvlPos,
              setValue=function(v) SSet("levelTextPosition", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Level Size", min=6, max=26, step=1,
              disabled=LvlSpotOff, disabledTooltip=LvlReq, rawTooltip=LvlAttached,
              getValue=function() return SVal("levelTextSize", 10) end,
              setValue=function(v) SSet("levelTextSize", v) end });  y = y - h
        EllesmereUI.BuildInlineCog(row._leftRegion, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = LvlSpotOff, disabledTooltip = LvlCogReq, rawTooltip = LvlAttached,
            title = "Level Offset",
            rows = {
                { type="slider", label="Offset X", min=-500, max=500, step=1,
                  get=function() return SVal("levelTextOffsetX", 0) end,
                  set=function(v) SSet("levelTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-500, max=500, step=1,
                  get=function() return SVal("levelTextOffsetY", 0) end,
                  set=function(v) SSet("levelTextOffsetY", v) end },
            },
        })
    end

    -- Power Text (+ Custom/Class/Accent/Power swatches) | Power Text Size (+ position cog). Shows only on frames whose power bar shows, so everything greys while no role shows one.
    do
        local function PTOff() return IsPowerOff() or SVal("powerTextMode", "none") == "none" end
        local function PTReq() return IsPowerOff() and "Show Power Bar For" or "Power Text" end
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Power Text",
              values={ ["none"]="None", ["percent"]="Percent", ["percentNoSign"]="Percent (No Sign)",
                       ["number"]="Number", ["numberPercent"]="Number | Percent", ["percentNumber"]="Percent | Number" },
              order={ "none", "percent", "percentNoSign", "number", "numberPercent", "percentNumber" },
              disabled=IsPowerOff,
              disabledTooltip="Show Power Bar For",
              getValue=function() return SVal("powerTextMode", "none") end,
              setValue=function(v) SSet("powerTextMode", v); EllesmereUI:RefreshPage() end },
            { type="slider", text="Power Text Size", min=6, max=26, step=1,
              disabled=PTOff,
              disabledTooltip=PTReq,
              getValue=function() return SVal("powerTextSize", 8) end,
              setValue=function(v) SSet("powerTextSize", v) end });  y = y - h
        -- Swatches: Custom is added FIRST so the _lastInline chain places it next to the dropdown; Power (leftmost) shows the player's power color and is not editable. Each dims and blocks while Power Text is None or power is off.
        if not EllesmereUI._prebuilding then
            local rgn = row._leftRegion
            local function AddPTSwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw, updateSw = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
                sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = sw
                -- Preserve the picker-opening click, then switch mode on click (same technique as the Health Text swatches).
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal("powerTextColorMode", "custom") ~= mode then
                        SSet("powerTextColorMode", mode)
                        EllesmereUI:RefreshPage()
                        return
                    end
                    if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
                end)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local block = CreateFrame("Frame", nil, sw)
                block:SetAllPoints(); block:SetFrameLevel(sw:GetFrameLevel() + 10); block:EnableMouse(true)
                block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, EllesmereUI.DisabledTooltip(PTReq())) end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function vis()
                    updateSw()
                    if PTOff() then
                        sw:SetAlpha(0.3); block:Show()
                    else
                        sw:SetAlpha(SVal("powerTextColorMode", "custom") == mode and 1 or 0.3); block:Hide()
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(vis)
                vis()
            end
            -- Custom (rightmost): editable, opens the picker when active.
            AddPTSwatch(
                function()
                    local c = SGet("powerTextCustomColor")
                    if c then return c.r, c.g, c.b, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    SWrite("powerTextCustomColor", { r=r, g=g, b=b })
                    ReloadAndUpdate()
                end, "custom", true, "Custom Color")
            AddPTSwatch(
                function()
                    local _, ct = UnitClass("player")
                    if ct and RAID_CLASS_COLORS[ct] then
                        local cc = RAID_CLASS_COLORS[ct]
                        return cc.r, cc.g, cc.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                function() end, "class", false, "Class Color")
            AddPTSwatch(
                function()
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end,
                function() end, "accent", false, "Accent Color")
            -- Power (leftmost): each frame's own power-type color at runtime.
            AddPTSwatch(
                function()
                    local _, pToken = UnitPowerType("player")
                    local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                    if info then return info.r, info.g, info.b, 1 end
                    return 0, 0.5, 1, 1
                end,
                function() end, "power", false, "Power Colored Text")
        end
        -- Position + offset cog on the Power Text Size slider.
        EllesmereUI.BuildInlineCog(row._rightRegion, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = PTOff,
            disabledTooltip = PTReq,
            title = "Power Text Position",
            rows = {
                { type="dropdown", label="Position", values=namePositionValues, order=namePositionOrder,
                  get=function() return SVal("powerTextPosition", "bottom") end,
                  set=function(v) SSet("powerTextPosition", v) end },
                { type="slider", label="Offset X", min=-150, max=150, step=1,
                  get=function() return SVal("powerTextOffsetX", 0) end,
                  set=function(v) SSet("powerTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-75, max=75, step=1,
                  get=function() return SVal("powerTextOffsetY", 0) end,
                  set=function(v) SSet("powerTextOffsetY", v) end },
            },
        })
    end

    -- Heal Absorb Text (+swatches) | Heal Absorb Text Position (+offset cog); Heal Absorb Text Size row is 1:1 with Health Text. Shows the heal-absorb shield amount (short/full), hidden at zero.
    row, h = W:DualRow(parent, y,
        { type="dropdown", text="Heal Absorb Text",
          values={ ["none"]="None", ["short"]="Short (240k)", ["amount"]="Amount" },
          order={ "none", "short", "amount" },
          getValue=function() return SVal("healAbsorbTextMode", "none") end,
          -- Rebuilds the page on the None <-> not-None flip so the Text Size row below appears/vanishes.
          setValue=EllesmereUI.DependentSetValue(
              function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
              function(v) SSet("healAbsorbTextMode", v); EllesmereUI:RefreshPage() end) },
        { type="dropdown", text="Heal Absorb Text Position", values=namePositionValues, order=namePositionOrder,
          disabled=function() return SVal("healAbsorbTextMode", "none") == "none" end,
          disabledTooltip="Heal Absorb Text",
          getValue=function() return SVal("healAbsorbTextPosition", "center") end,
          setValue=function(v) SSet("healAbsorbTextPosition", v) end });  y = y - h
    -- Heal Absorb Text swatches (custom/class/accent), same pattern as the Health Text triple above.
    if not EllesmereUI._prebuilding then
        local rgn = row._leftRegion
        local function AddHASwatch(getColor, setColor, mode, opensPicker, tooltip)
            local sw = EllesmereUI.BuildColorSwatch(
                rgn, row:GetFrameLevel() + 3, getColor, setColor, false, 20)
            sw:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = sw
            sw._eabOrigClick = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self)
                if SVal("healAbsorbTextColorMode", "custom") ~= mode then
                    SSet("healAbsorbTextColorMode", mode)
                    EllesmereUI:RefreshPage()
                    return
                end
                if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
            end)
            if tooltip then
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            local function vis()
                sw:SetAlpha(SVal("healAbsorbTextColorMode", "custom") == mode and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(vis)
            vis()
        end
        -- Custom (rightmost): editable, opens the picker when active.
        AddHASwatch(
            function()
                local c = SGet("healAbsorbTextCustomColor")
                if c then return c.r, c.g, c.b, 1 end
                return 1, 0.3, 0.3, 1
            end,
            function(r, g, b)
                SWrite("healAbsorbTextCustomColor", { r=r, g=g, b=b })
                ReloadAndUpdate()
            end, "custom", true, "Custom Color")
        AddHASwatch(
            function()
                local _, ct = UnitClass("player")
                if ct and RAID_CLASS_COLORS[ct] then
                    local cc = RAID_CLASS_COLORS[ct]
                    return cc.r, cc.g, cc.b, 1
                end
                return 1, 1, 1, 1
            end,
            function() end, "class", false, "Class Color")
        -- Accent (leftmost).
        AddHASwatch(
            function()
                local r, g, b = EllesmereUI.ResolveActiveAccent()
                return r or 1, g or 1, b or 1, 1
            end,
            function() end, "accent", false, "Accent Color")
    end
    -- Offset cog on the Heal Absorb Text Position region.
    do
        local rgn = row._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = function() return SVal("healAbsorbTextMode", "none") == "none" end,
            disabledTooltip = "Heal Absorb Text",
            title = "Heal Absorb Text Offset",
            rows = {
                { type="slider", label="Offset X", min=-150, max=150, step=1,
                  get=function() return SVal("healAbsorbTextOffsetX", 0) end,
                  set=function(v) SSet("healAbsorbTextOffsetX", v) end },
                { type="slider", label="Offset Y", min=-75, max=75, step=1,
                  get=function() return SVal("healAbsorbTextOffsetY", 0) end,
                  set=function(v) SSet("healAbsorbTextOffsetY", v) end },
            },
        })
    end
    -- Row 5: Heal Absorb Text Size | (blank odd last slot). Hidden entirely
    -- while Heal Absorb Text is None.
    if SVal("healAbsorbTextMode", "none") ~= "none" then
        row, h = W:DualRow(parent, y,
            { type="slider", text="Heal Absorb Text Size", min=6, max=26, step=1,
              getValue=function() return SVal("healAbsorbTextSize", 9) end,
              setValue=function(v) SSet("healAbsorbTextSize", v) end },
            { type="label", text="" });  y = y - h
    end
    if onSection then onSection("textDisplay", _secY, y) end; _secY = y
    return y, CustomBorderOff, CustomBorderOffTip
end

-- Used by EUI_RaidFrames_Options.lua
ns.RFO_BuildVisualBars = BuildVisualBars
