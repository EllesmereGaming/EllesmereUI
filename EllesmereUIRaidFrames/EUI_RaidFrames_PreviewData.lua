if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewData.lua
--
--  The sample values and ApplyPreviewData, which paints one preview frame.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local UnitName              = UnitName

local RF = ns._internals -- the table of the Raid Frames chain
local ApplyFont, ApplyRoleIcon, defaults = RF.ApplyFont, RF.ApplyRoleIcon, RF.defaults
local DISPEL_ICON_ATLAS, GetDispelColor = RF.DISPEL_ICON_ATLAS, RF.GetDispelColor
local IsPowerBarEnabled, LayoutTopNameBar = RF.IsPowerBarEnabled, RF.LayoutTopNameBar
local PixelSnap, ResolveHealthTexture = RF.PixelSnap, RF.ResolveHealthTexture

local previewClassTokens, previewRoles = I.previewClassTokens, I.previewRoles

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local PP
RF.PPSetters[#RF.PPSetters + 1] = function(v) PP = v end

ns.previewAbsorbValues = ns.previewAbsorbValues or {}
local previewHealthValues = {}
local previewPowerValues = {}
ns.previewHealAbsorbValues = {}

-- roles, classTokens: the party preview hands in its own tables for this call.
local function ApplyPreviewData(f, index, roles, classTokens)
    local previewRoles = roles or previewRoles
    local previewClassTokens = classTokens or previewClassTokens
    -- The main raid preview is a base "20 Man" mockup: RefreshPreview lays out from the
    -- base frameWidth and CreatePreviewFrame sizes from it too, so per-button sizing here
    -- must also read the base profile. ns._scaledProfile would return the active raid-size
    -- tier override for frameWidth, freezing buttons at override size while layout used
    -- base width (the 20 Man Width slider would re-space without resizing whenever a
    -- custom raid size was active). Party preview passes its own override via
    -- _previewSettingsOverride. The real-preview effective overlay (when active) resolves
    -- captured keys to panel-closed values and is NOT tier-scaled, so this holds.
    local s = ns._previewSettingsOverride or ns._pvOverlayProxy or db.profile
    local compact = ns.RF_ButtonCompact(f, s)
    local classToken = previewClassTokens[index] or ns._PV_CLASS_TOKENS[((index - 1) % #ns._PV_CLASS_TOKENS) + 1]
    local playerSlot = previewRoles._playerSlot or 1
    local name
    if index == playerSlot then
        name = UnitName("player") or "Player"
        if Ambiguate then name = Ambiguate(name, "short") end
    else
        -- Legends roster names are RAID-preview-only (user directive): the
        -- party preview (which sandwiches this fn with _previewSettingsOverride
        -- set and its own class tokens) keeps the generic name pool.
        local legend = not ns._partyPvActive and not ns._previewSettingsOverride
            and ns._pvNames and ns._pvNames[index]
        name = legend or ns._PV_NAMES[((index - 1) % #ns._PV_NAMES) + 1]
    end
    local healthPct = previewHealthValues[index] or (40 + math.random(60))

    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0

    local pvInvert = ns.RF_IsInvertedFill(s)

    f:SetSize(w, h)

    -- Health bar height/anchor + Top Name Bar (helper re-anchors health top to
    -- -topBarH; the per-unit power block below re-sets only the height)
    LayoutTopNameBar(s, h, powerH, f._health, f._topNameBar, f._topNameBarBg, f._topNameBarText, f._power, true)

    -- Health bar
    if f._health then
        f._health:SetStatusBarTexture(ResolveHealthTexture())
        f._health:GetStatusBarTexture():SetHorizTile(false)
        ns.RF_ApplyHealthOrientation(f._health, s)
        f._health:SetMinMaxValues(0, 100)
        -- Preview: honor invert setting by flipping the displayed fill percentage
        local healthBarPct = healthPct
        if pvInvert then healthBarPct = 100 - healthBarPct end
        f._health:SetValue(healthBarPct)
        f._healthPct = healthPct
        f._classToken = classToken

        local mode = s.healthColorMode or "class"
        local fillTex = f._health:GetStatusBarTexture()
        if mode == "dark" then
            local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
            f._health:SetStatusBarColor(dfr, dfg, dfb, 1)
            if fillTex then fillTex:SetAlpha(dfa) end
        elseif mode == "classic" then
            if fillTex then fillTex:SetAlpha(1) end
            local pct = healthPct / 100
            local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
            local g = pct > 0.5 and 1 or (pct * 2)
            f._health:SetStatusBarColor(r, g, 0, (s.healthBarOpacity or 100) / 100)
        elseif mode == "customDynamic" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveDynamicColor(s, healthPct / 100)
            f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        elseif mode == "classReactive" then
            if fillTex then fillTex:SetAlpha(1) end
            local r, g, b = ns.ResolveClassReactiveColor(s, classToken, healthPct / 100)
            f._health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
        elseif mode == "custom" then
            if fillTex then fillTex:SetAlpha(1) end
            local c = s.customFillColor
            f._health:SetStatusBarColor(c.r, c.g, c.b, (s.healthBarOpacity or 100) / 100)
        else
            if fillTex then fillTex:SetAlpha(1) end
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._health:SetStatusBarColor(cc.r, cc.g, cc.b, (s.healthBarOpacity or 100) / 100) end
        end
    end

    -- Top Name Bar text (preview unit name + class/custom color)
    if f._topNameBarText and s.topNameBarEnabled then
        local attach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
        if attach then
            f._topNameBarText:SetFormattedText(attach[1], ns._RFPreviewLevel(), name)
        else
            f._topNameBarText:SetText(name)
        end
        if (s.topNameBarTextColorMode or "class") == "custom" then
            local c = s.topNameBarTextColor or { r = 1, g = 1, b = 1 }
            f._topNameBarText:SetTextColor(c.r, c.g, c.b)
        else
            local cc = EllesmereUI.GetClassColor(classToken)
            if cc then f._topNameBarText:SetTextColor(cc.r, cc.g, cc.b)
            else f._topNameBarText:SetTextColor(1, 1, 1) end
        end
    end

    -- Background
    if f._bg then
        -- BG covers the missing-health portion only (never behind the fill), so
        -- it hangs off the far side of the fill -- its right edge normally, its
        -- top edge on a vertical bar. Mirrors the live UpdateHealthBg.
        local pvVert = ns.RF_IsVerticalFill(s)
        local function AnchorPreviewBg()
            f._bg:ClearAllPoints()
            if pvVert then
                if pvInvert then
                    f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._bg:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                end
            else
                if pvInvert then
                    f._bg:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
                else
                    f._bg:SetPoint("TOPLEFT", f._health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                    f._bg:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
            end
        end
        if s.healthColorMode == "dark" then
            AnchorPreviewBg()
            f._bg:SetColorTexture(EllesmereUI.GetDarkModeBg())
        else
            -- Matches the real-frame themed branch + Dark mode. Keeps the preview
            -- a 1:1 replica for reduced-fill-opacity setups.
            AnchorPreviewBg()
            local bgA = (s.bgDarkness or 50) / 100
            local cc = s.bgClassColored and classToken and EllesmereUI.GetClassColor(classToken)
            if cc then
                f._bg:SetColorTexture(cc.r, cc.g, cc.b, bgA)
            else
                local bgc = s.customBgColor or defaults.customBgColor
                f._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgA)
            end
        end
    end

    -- Absorb shield preview (dual clip-frame: backfill + forward)
    if f._absorbBar then
        local absStyle = s.absorbStyle or "none"
        if ns._indicatorsVisible then absStyle = "none"
        elseif ns._testMode then
            if ns._testAbsorbs == false then absStyle = "none"
            elseif ns._testAbsorbs and absStyle == "none" then absStyle = "striped" end
        elseif not ns._absorbsPreviewVisible then absStyle = "none"
        end
        local absorbAmt = ns.previewAbsorbValues[index] or 0
        local fw = f._absorbBar._forward
        -- Absorb Bar (solid bar above the frame): same preview gating as the
        -- shield styles (indicators / test mode / absorbs eyeball).
        local topBar = f._absorbBar._topBar
        if topBar then
            local barPos = ns.GetAbsorbBarPosition(s)
            local barOn = barPos ~= "none"
            if ns._indicatorsVisible then barOn = false
            elseif ns._testMode then
                if ns._testAbsorbs == false then barOn = false end
            elseif not ns._absorbsPreviewVisible then barOn = false
            end
            if barOn and absorbAmt > 0 then
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                -- (Party Frames kit: laid out on the kit bar and host, as live.)
                ns.ApplyStripBarLayout(topBar, f._absorbBar, ((f.kit or f._health._euiBarArea) and f._health) or f, barPos, s.absorbBarHeight or 4, nil, nil, s.absorbBarGrowDir or "up")
                topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                topBar:SetValue(absorbAmt)
                topBar:Show()
            else
                topBar:Hide()
            end
        end
        -- Heal Absorb Bar preview (mirrors the Absorb Bar; gated on the heal
        -- absorb preview toggles).
        do
            local healTopBarPv = f._absorbBar._healTopBar
            if healTopBarPv then
                local healBarPos = ns.GetHealAbsorbBarPosition(s)
                local healBarOn = healBarPos ~= "none"
                if ns._indicatorsVisible then healBarOn = false
                elseif ns._testMode then
                    if ns._testHealAbsorbs == false then healBarOn = false end
                elseif not ns._absorbsPreviewVisible then healBarOn = false
                end
                local haAmtPv = ns.previewHealAbsorbValues[index] or 0
                if healBarOn and haAmtPv > 0 then
                    local hbc = s.healAbsorbBarColor or { r = 200/255, g = 29/255, b = 29/255 }
                    ns.ApplyStripBarLayout(healTopBarPv, f._absorbBar, ((f.kit or f._health._euiBarArea) and f._health) or f, healBarPos, s.healAbsorbBarHeight or 4, ns.GetAbsorbBarPosition(s), s.absorbBarHeight or 4, s.healAbsorbBarGrowDir or "up")
                    healTopBarPv:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBarPv:SetValue(haAmtPv)
                    healTopBarPv:Show()
                else
                    healTopBarPv:Hide()
                end
            end
        end
        if absStyle ~= "none" and absorbAmt > 0 then
            local modern = (absStyle == "blizzardModern")
            local tex = ns.ResolveAbsorbStyleTex(absStyle, "Interface\\Buttons\\WHITE8X8")
            local alpha = (s.absorbOpacity or 90) / 100
            local tiled = (absStyle == "striped" or absStyle == "stripedReversed" or absStyle == "stripedThick" or absStyle == "stripedThickR" or absStyle == "largeStripes" or absStyle == "largeStripesR" or absStyle == "largeOutlinedStripes" or absStyle == "largeOutlinedStripesR" or absStyle == "pixelsShieldFill")
            -- (the Party Frames kit's health bar is its own rect)
            local hpW = f.kitG and f.kitG.health.w or w
            local hpH = f.kitG and f.kitG.health.h or healthH
            local mask = f._absorbBar._mask
            local ac = s.absorbColor or { r = 1, g = 1, b = 1 }

            f._absorbBar:SetWidth(hpW)
            f._absorbBar:SetHeight(hpH)
            if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end

            if modern then
                -- Forward = modern texture; backfill = flat 10% white overshield (mirrors live).
                if fw then ns.ApplyModernAbsorbBar(fw, mask) end
                ns.HideModernAbsorbBase(f._absorbBar)
                f._absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                f._absorbBar:SetStatusBarColor(1, 1, 1, 0.10)
                local bfFill = f._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(false); bfFill:SetVertTile(false)
                    if mask then ns.RF_AddMaskOnce(bfFill, mask) end
                end
            else
                ns.HideModernAbsorbBase(f._absorbBar)
                if fw then ns.HideModernAbsorbBase(fw) end

                -- Apply style to backfill bar
                f._absorbBar:SetStatusBarTexture(tex)
                f._absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                local bfFill = f._absorbBar:GetStatusBarTexture()
                if bfFill then
                    bfFill:SetDrawLayer("ARTWORK", 1)
                    bfFill:SetHorizTile(tiled)
                    bfFill:SetVertTile(tiled)
                    if mask then ns.RF_AddMaskOnce(bfFill, mask) end
                end

                -- Apply style to forward bar
                if fw then
                    fw:SetStatusBarTexture(tex)
                    fw:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
                    local fwFill = fw:GetStatusBarTexture()
                    if fwFill then
                        fwFill:SetDrawLayer("ARTWORK", 1)
                        fwFill:SetHorizTile(tiled)
                        fwFill:SetVertTile(tiled)
                        if mask then ns.RF_AddMaskOnce(fwFill, mask) end
                    end
                end
            end

            -- Feed both bars with the same absorb value; clip frames do the visual math.
            -- Mirror the live Show Overshield gate: when off (overlay-like modes) feed
            -- the backfill 0 so the overshield does not render in the preview.
            local pvOsm = s.overshieldMode
            if pvOsm == nil then pvOsm = (s.showOvershield == false) and "never" or "always" end
            local pvOvershieldOn = pvOsm ~= "never"
            local pvOverlayLike = modern or (s.absorbEdgeMode or "overlay") == "overlay"
            local pvAbValue = (not pvOvershieldOn and pvOverlayLike) and 0 or absorbAmt
            f._absorbBar:SetMinMaxValues(0, 100)
            f._absorbBar:SetValue(pvAbValue)
            f._absorbBar:Show()
            if fw then
                fw:SetMinMaxValues(0, 100)
                fw:SetValue(absorbAmt)
                fw:Show()
            end

            -- Blizzard Glow Line (mirrors live, placements included; preview values are plain
            -- numbers, so overshield is a normal compare instead of isClamped). Unset follows
            -- the style: on for Default Blizz Frames only. Vertical fill hides it (see live).
            local pvGlowVert = ns.RF_IsVerticalFill(s)
            if modern and fw and not pvGlowVert then
                local fmb = fw._modernBase
                if fmb then fmb:SetAllPoints(fw:GetStatusBarTexture()) end
            end
            local pvGlowSet = s.absorbGlowLine
            local pvEm = s.absorbEdgeMode or "overlay"
            if (pvGlowSet == true or (pvGlowSet == nil and modern)) and fw and not pvGlowVert
                and (modern or pvEm ~= "left") then
                local ge
                if modern then ge = 1
                elseif pvEm == "overlay" then ge = (pvOsm == "fromleft") and 2 or 1
                elseif pvEm == "right" then ge = 5
                else ge = 3 end
                local bft = f._absorbBar:GetStatusBarTexture()
                local previewOver = absorbAmt > (100 - (healthPct or 100))
                local g, sp = fw._edgeGate, fw._edgeSpark
                if g and sp then
                    g:SetHeight(hpH)
                    g:ClearAllPoints()
                    if ge >= 3 then
                        g:SetPoint("CENTER", bft, "LEFT", -1, 0)
                    else
                        g:SetPoint("CENTER", fw, "LEFT", -1, 0)
                    end
                    g:SetValue(absorbAmt)
                    sp:SetAllPoints(g:GetStatusBarTexture())
                    local spOn = true
                    if ge <= 2 then spOn = not previewOver elseif ge == 5 then spOn = previewOver end
                    sp:SetAlpha(spOn and 1 or 0)
                    sp:Show()
                end
                local bsp = fw._bfSpark
                if bsp then
                    if ge <= 2 then
                        bsp:SetSize(16, hpH)
                        bsp:ClearAllPoints()
                        if not pvOvershieldOn then
                            bsp:SetPoint("CENTER", f._absorbBar, "RIGHT", -1, 0)
                        elseif ge == 2 then
                            bsp:SetPoint("CENTER", bft, "RIGHT", 1, 0)
                        else
                            bsp:SetPoint("CENTER", bft, "LEFT", -1, 0)
                        end
                        bsp:SetAlpha(previewOver and 1 or 0)
                        bsp:Show()
                    else
                        bsp:Hide()
                    end
                end
            elseif fw and fw._edgeSpark then
                fw._edgeSpark:Hide()
                if fw._bfSpark then fw._bfSpark:Hide() end
            end
        else
            f._absorbBar:Hide()
            if fw then fw:Hide() end
            ns.HideModernAbsorbBase(f._absorbBar)
            if fw then ns.HideModernAbsorbBase(fw) end
            if fw and fw._edgeSpark then fw._edgeSpark:Hide() end
            if fw and fw._bfSpark then fw._bfSpark:Hide() end
        end
        -- Position clip frames + backfill based on shield absorb placement
        -- (mirrors the live ReanchorAbsorbToFill).
        local cc = f._absorbBar._curClip
        local mc = f._absorbBar._missClip
        if cc and mc and f._health then
            local absorbMode = s.absorbEdgeMode or "overlay"
            -- Overlay Reverse (Full): Overlay Reverse plus the origin-edge forward bar for the
            -- excess (mirrors live; Default Blizz Frames keeps plain Overlay Reverse).
            local pvOrFull = absorbMode == "overlayReverseFull" and s.absorbStyle ~= "blizzardModern"
            -- Vertical fill: same layout with the axis swapped (the fill's right
            -- edge becomes its top edge). Mirrors the live vertical branch.
            local pvAbVert = ns.RF_IsVerticalFill(s)
            local hpA, hpB = ns.RF_HpEdge(pvAbVert, pvInvert)
            local pvAxisBars = { f._absorbBar, fw }
            for i = 1, 2 do
                local b = pvAxisBars[i]
                if b then
                    b:SetOrientation(pvAbVert and "VERTICAL" or "HORIZONTAL")
                    ns.RF_ApplyFillRotation(b)
                end
            end
            if pvAbVert then
                local vfill = f._health:GetStatusBarTexture()
                if absorbMode == "right" or absorbMode == "left" then
                    cc:ClearAllPoints()
                    cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    if absorbMode == "left" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                    if fw then fw:Hide() end
                elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                    -- Whole absorb fills DOWN into the fill from its top edge;
                    -- the filled-region clip masks excess (mirrors live). Full
                    -- draws that excess through the forward bar instead.
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:ClearAllPoints()
                    f._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    f._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    if pvOrFull then
                        mc:ClearAllPoints()
                        mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        mc:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    elseif fw then
                        fw:Hide()
                    end
                else
                    cc:ClearAllPoints()
                    cc:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    cc:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    mc:ClearAllPoints()
                    mc:SetPoint("BOTTOMLEFT", vfill, hpA, 0, -1)
                    mc:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:ClearAllPoints()
                    local pvOsm2 = s.overshieldMode
                    if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                    if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                        f._absorbBar:SetReverseFill(false)
                        f._absorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    else
                        f._absorbBar:SetReverseFill(true)
                        f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    end
                end
                if fw then
                    fw:ClearAllPoints()
                    if pvOrFull then
                        fw:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        fw:SetPoint("BOTTOMLEFT", vfill, hpA, 0, 0)
                        fw:SetPoint("BOTTOMRIGHT", vfill, hpB, 0, 0)
                    end
                end
            elseif absorbMode == "right" or absorbMode == "left" then
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                f._absorbBar:ClearAllPoints()
                if absorbMode == "left" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
                if fw then fw:Hide() end
            elseif absorbMode == "overlayReverse" or absorbMode == "overlayReverseFull" then
                -- Whole absorb backfills from the fill's leading edge INTO the
                -- fill; the filled-region clip masks excess (mirrors live). Full
                -- draws that excess through the forward bar instead.
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                f._absorbBar:SetReverseFill(true)
                f._absorbBar:ClearAllPoints()
                f._absorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                f._absorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                if pvOrFull then
                    mc:ClearAllPoints()
                    mc:SetPoint("TOPLEFT", fill, hpA, 0, 0)
                    mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                elseif fw then
                    fw:Hide()
                end
            else
                local fill = f._health:GetStatusBarTexture()
                cc:ClearAllPoints()
                cc:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                cc:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                mc:ClearAllPoints()
                mc:SetPoint("TOPLEFT", fill, hpA, -1, 0)
                mc:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                -- Overlay backfill: overshield "From Left" mirrors the live
                -- anchors (fill-edge + forward fill); else the classic
                -- right-anchored reverse fill.
                f._absorbBar:ClearAllPoints()
                local pvOsm2 = s.overshieldMode
                if pvOsm2 == nil then pvOsm2 = (s.showOvershield == false) and "never" or "always" end
                if pvOsm2 == "fromleft" and s.absorbStyle ~= "blizzardModern" then
                    f._absorbBar:SetReverseFill(false)
                    f._absorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                else
                    f._absorbBar:SetReverseFill(true)
                    f._absorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._absorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                end
            end
            -- Restore the forward bar's horizontal anchors (the vertical branch
            -- above re-points it, and these are otherwise only set at creation).
            if not pvAbVert and fw then
                local hfill = f._health:GetStatusBarTexture()
                fw:ClearAllPoints()
                if pvOrFull then
                    fw:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    fw:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    fw:SetPoint("TOPLEFT", hfill, hpA, 0, 0)
                    fw:SetPoint("BOTTOMLEFT", hfill, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal absorb preview
    if f._healAbsorbBar then
        local haStyle = s.healAbsorbStyle or "clean"
        if ns._indicatorsVisible then haStyle = "none"
        elseif ns._testMode then
            if ns._testHealAbsorbs == false then haStyle = "none"
            elseif ns._testHealAbsorbs and haStyle == "none" then haStyle = "clean" end
        elseif not ns._absorbsPreviewVisible then haStyle = "none"
        end
        local haAmt = ns.previewHealAbsorbValues[index] or 0
        if haStyle ~= "none" and haAmt > 0 then
            local haTex = ns.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
            local haAlpha = (s.healAbsorbOpacity or 75) / 100
            local hc = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
            if haStyle == "healBlizzModern" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
            local tiled = (haStyle == "striped" or haStyle == "stripedReversed" or haStyle == "stripedThick" or haStyle == "stripedThickR" or haStyle == "largeStripes" or haStyle == "largeStripesR" or haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" or haStyle == "pixelsShieldFill")
            local hpW = f.kitG and f.kitG.health.w or w
            local hpH = f.kitG and f.kitG.health.h or healthH
            local mask = f._healAbsorbBar._mask
            f._healAbsorbBar:SetStatusBarTexture(haTex)
            f._healAbsorbBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, haAlpha)
            f._healAbsorbBar:SetWidth(hpW)
            f._healAbsorbBar:SetHeight(hpH)
            local haFillPv = f._healAbsorbBar:GetStatusBarTexture()
            if haFillPv then
                haFillPv:SetDrawLayer("ARTWORK", 2)
                haFillPv:SetHorizTile(tiled)
                haFillPv:SetVertTile(tiled)
                if mask then ns.RF_AddMaskOnce(haFillPv, mask) end
            end
            f._healAbsorbBar:SetMinMaxValues(0, 100)
            f._healAbsorbBar:SetValue(haAmt)
            f._healAbsorbBar:Show()
            local hbg = f._healAbsorbBar._bg
            if hbg then
                hbg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 25) / 100)
                hbg:SetAllPoints(f._healAbsorbBar:GetStatusBarTexture())
                hbg:Show()
            end
        else
            f._healAbsorbBar:Hide()
        end
        -- Heal absorb placement (independent of shield absorb; mirrors live).
        if f._health then
            local healMode = s.healAbsorbEdgeMode or "overlay"
            -- Vertical fill: same layout, axis swapped (mirrors the live branch).
            local pvHaVert = ns.RF_IsVerticalFill(s)
            local hpA, hpB = ns.RF_HpEdge(pvHaVert, pvInvert)
            f._healAbsorbBar:SetOrientation(pvHaVert and "VERTICAL" or "HORIZONTAL")
            ns.RF_ApplyFillRotation(f._healAbsorbBar)
            if pvHaVert then
                local vfill = f._health:GetStatusBarTexture()
                if f._healClip then
                    f._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._healClip:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                        f._healClip:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                    end
                end
                f._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                elseif healMode == "left" then
                    f._healAbsorbBar:SetReverseFill(false)
                    f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                else
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPLEFT", vfill, hpA, 0, 0)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", vfill, hpB, 0, 0)
                end
            else
                if f._healClip then
                    f._healClip:ClearAllPoints()
                    if healMode == "right" or healMode == "left" then
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                    else
                        f._healClip:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                        f._healClip:SetPoint("BOTTOMRIGHT", f._health:GetStatusBarTexture(), hpB, 0, 0)
                    end
                end
                f._healAbsorbBar:ClearAllPoints()
                if healMode == "right" then
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", f._health, "TOPRIGHT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", f._health, "BOTTOMRIGHT", 0, 0)
                elseif healMode == "left" then
                    f._healAbsorbBar:SetReverseFill(false)
                    f._healAbsorbBar:SetPoint("TOPLEFT", f._health, "TOPLEFT", 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMLEFT", f._health, "BOTTOMLEFT", 0, 0)
                else
                    local fill = f._health:GetStatusBarTexture()
                    f._healAbsorbBar:SetReverseFill(true)
                    f._healAbsorbBar:SetPoint("TOPRIGHT", fill, hpA, 0, 0)
                    f._healAbsorbBar:SetPoint("BOTTOMRIGHT", fill, hpB, 0, 0)
                end
            end
        end
    end

    -- Heal prediction preview
    if f._healPredBar then
        local predAmt = ns.previewHealPredValues and ns.previewHealPredValues[index] or 0
        local wantPred = s.healPrediction
        if ns._indicatorsVisible then wantPred = false
        elseif ns._testMode and ns._testHealPrediction ~= nil then wantPred = ns._testHealPrediction end
        if wantPred and predAmt > 0 then
            local pc = s.healPredColor or { r = 102/255, g = 243/255, b = 102/255 }
            local pAlpha = (s.healPredOpacity or 75) / 100
            f._healPredBar:SetStatusBarColor(pc.r, pc.g, pc.b, pAlpha)
            f._healPredBar:SetWidth(f.kitG and f.kitG.health.w or w)
            f._healPredBar:SetHeight(f.kitG and f.kitG.health.h or healthH)
            -- Grows from the HP edge into the missing health: the fill's right
            -- edge normally, its top edge on a vertical bar. Only set at creation
            -- otherwise, so both axes are re-applied here.
            do
                local pvPredVert = ns.RF_IsVerticalFill(s)
                local pFill = f._health and f._health:GetStatusBarTexture()
                f._healPredBar:SetOrientation(pvPredVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._healPredBar)
                if pFill then
                    local hpA, hpB = ns.RF_HpEdge(pvPredVert, pvInvert)
                    f._healPredBar:ClearAllPoints()
                    if pvPredVert then
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpA, 0, 0)
                        f._healPredBar:SetPoint("BOTTOMRIGHT", pFill, hpB, 0, 0)
                    else
                        f._healPredBar:SetPoint("TOPLEFT", pFill, hpA, 0, 0)
                        f._healPredBar:SetPoint("BOTTOMLEFT", pFill, hpB, 0, 0)
                    end
                end
            end
            f._healPredBar:SetMinMaxValues(0, 100)
            f._healPredBar:SetValue(predAmt)
            f._healPredBar:Show()
        else
            f._healPredBar:Hide()
        end
    end

    -- Reduced max health preview
    if f._reducedMaxHealthBar then
        local rmhAmt = ns.previewReducedMaxHealth and ns.previewReducedMaxHealth[index] or 0
        local rmhStyle = s.maxHealthStyle or "maxHealthStripes"
        -- Show in the Full Preview (Reduced Max Health test toggle) AND in the
        -- Absorbs-section preview (the shield-effects eye), mirroring Heal Absorb.
        local rmhShow = ns._testReducedMaxHealth
            or (not ns._testMode and not ns._indicatorsVisible and ns._absorbsPreviewVisible)
        if rmhShow and rmhAmt > 0 and rmhStyle ~= "none" then
            ns.ApplyMaxHealthStyle(f._reducedMaxHealthBar, rmhStyle, s)
            do  -- eats the far end of the bar: the right edge, or the top when vertical
                local pvRmhVert = ns.RF_IsVerticalFill(s)
                f._reducedMaxHealthBar:SetOrientation(pvRmhVert and "VERTICAL" or "HORIZONTAL")
                ns.RF_ApplyFillRotation(f._reducedMaxHealthBar)
            end
            f._reducedMaxHealthBar:SetValue(rmhAmt)
            local rmhBg = f._reducedMaxHealthBg
            if rmhBg then
                rmhBg:SetColorTexture(0, 0, 0, (s.maxHealthBgOpacity or 100) / 100)
                rmhBg:SetAllPoints(f._reducedMaxHealthBar:GetStatusBarTexture())
            end
            f._reducedMaxHealthBar:Show()
        else
            f._reducedMaxHealthBar:Hide()
        end
    end

    -- Power (filtered by role, hidden if class has no power)
    local role = previewRoles[index] or "DAMAGER"
    local showForRole = (role == "HEALER" and s.powerShowForHealer)
        or (role == "TANK" and s.powerShowForTank)
        or (role == "DAMAGER" and s.powerShowForDPS)
    local hidePower = powerH <= 0 or not showForRole
    -- Party Frames kit: the stock mana bar always shows (the kit pass sizes it).
    if f.kitG then hidePower = false end

    if f._power then
        if not hidePower then
            f._power:SetHeight(powerH)
            f._power:SetStatusBarTexture(ResolveHealthTexture())
            f._power:GetStatusBarTexture():SetHorizTile(false)
            local pwPct = previewPowerValues[index] or (60 + math.random(40))
            f._power:SetMinMaxValues(0, 100)
            f._power:SetValue(pwPct)
            f._powerPct = pwPct
            local pwToken = EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA"
            local pc = EllesmereUI.GetPowerColor(pwToken)
            if pc then
                f._power:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
            else
                f._power:SetStatusBarColor(0, 0.5, 1, 1)
            end
            f._power:Show()
        else
            f._power:Hide()
        end
    end

    -- Expand health to full frame when power is hidden (still reserving the Top
    -- Name Bar's height from the top; its anchor was set by LayoutTopNameBar)
    if f._health then
        if hidePower then
            f._health:SetHeight(h - topBarH)
        else
            f._health:SetHeight(healthH - topBarH)
        end
    end

    if f._powerBg then
        if hidePower then
            f._powerBg:Hide()
        else
            local bgc = EllesmereUI.GetPowerColor and s.powerBgPowerColored
                and EllesmereUI.GetPowerColor(EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA")
            local pf = bgc and EllesmereUI.GetPowerBgDarkenFactor() or 1
            bgc = bgc or s.powerBgColor
            f._powerBg:SetColorTexture(((bgc or {}).r or 0) * pf, ((bgc or {}).g or 0) * pf, ((bgc or {}).b or 0) * pf, (s.powerBgDarkness or 70) / 100)
            f._powerBg:Show()
        end
    end

    -- Power border (Classic WoW UI: the stock divider stands in, drawn with
    -- the frame border below)
    if f._powerBorder and PP then
        if hidePower or f.stockDiv or f.kitG then
            if f._powerBorder._powerArtKey then ns.RF_ClearPowerBorderArt(f._powerBorder) end
            f._powerBorder:Hide()
        elseif not ((s.powerBorderMatchFrame == true or f._powerBorder._powerArtKey)
            and ns.RF_ApplyPowerBorderArt(f._powerBorder, s, true, true)) then
            local pbStyle = s.powerBorderStyle or "eui"
            if pbStyle == "eui" then
                PP.UpdateBorder(f._powerBorder, 1, 1, 1, 1, 0.2)
                f._powerBorder:Show()
                local ppC = PP.GetBorders(f._powerBorder)
                if ppC then
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                    if ppC._top then ppC._top:SetAlpha(0.2) end
                end
            else
                local pbSize = s.powerBorderSize or 1
                if pbSize <= 0 then
                    f._powerBorder:Hide()
                else
                    local pbc = s.powerBorderColor
                    local pba = s.powerBorderAlpha or 1
                    PP.UpdateBorder(f._powerBorder, pbSize, pbc.r, pbc.g, pbc.b, pba)
                    f._powerBorder:Show()
                    local ppC = PP.GetBorders(f._powerBorder)
                    if ppC then
                        if pbStyle == "divider" then
                            if ppC._bottom then ppC._bottom:SetAlpha(0) end
                            if ppC._left then ppC._left:SetAlpha(0) end
                            if ppC._right then ppC._right:SetAlpha(0) end
                            if ppC._top then ppC._top:SetAlpha(pba) end
                        else
                            if ppC._top then ppC._top:SetAlpha(pba) end
                            if ppC._bottom then ppC._bottom:SetAlpha(pba) end
                            if ppC._left then ppC._left:SetAlpha(pba) end
                            if ppC._right then ppC._right:SetAlpha(pba) end
                        end
                    end
                end
            end
        end
    end

    -- Border (style/size/texture/offsets via ApplyBorderStyle, then state recolor)
    if f._border and PP and f.kit then
        -- Party Frames kit: the art stands in for the border.
        f._border:SetFrameLevel(f:GetFrameLevel() + 8)
        EllesmereUI.ApplyBorderStyle(f._border, 0, 0, 0, 0, 0, "solid")
        f._border._hlBorderSize = nil
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    elseif f._border and PP and f.stockEdge then
        f._border:SetFrameLevel(f:GetFrameLevel() + 8)
        EllesmereUI.ApplyBorderStyle(f._border, 0, 0, 0, 0, 0, "solid")
        f._border._hlBorderSize = nil
        ns.RF_StockSeat(f)
        if f.stockDiv and f._power and f._power:IsShown() then ns.RF_StockDivider(f) end
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    elseif f._border and PP and compact then
        EllesmereUI.ApplyBorderStyle(f._border, 0, 0, 0, 0, 0, "solid")
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    elseif f._border and PP then
        local bs = s.borderSize or 1
        local bc = s.borderColor or { r = 0, g = 0, b = 0 }
        local pl = f:GetFrameLevel()
        f._border:SetFrameLevel(s.borderBehind and math.max(0, pl - 1) or (pl + 8))
        EllesmereUI.ApplyBorderStyle(f._border, bs, bc.r, bc.g, bc.b, s.borderAlpha or 1,
            s.borderTexture or "solid", s.borderTextureOffset, s.borderTextureOffsetY,
            s.borderTextureShiftX, s.borderTextureShiftY, "unitframes", bs, nil,
            EllesmereUI.BorderPx(s.borderSizePx, bs, s.borderTexture or "solid"))
        if f._ApplyBorderColor then f._ApplyBorderColor() end
    end
    -- Rounded corners, as on the live cells (stock styles stay square).
    if f._border then
        local radius = (f.kit or f.stockEdge or compact) and 0 or (s.cornerRadius or 0)
        if radius > 0 then
            EllesmereUI.RoundCorners(f, radius, {
                roots = { f._health, f._power, f._topNameBar, f._powerBorder },
                textures = { f._bg },
                border = f._border, style = s.borderTexture or "solid",
                corners = s.cornerMask,
            })
        else
            EllesmereUI.RoundCorners(f, 0)
        end
    end

    -- Indicators visibility (eyeball toggle)
    local indVis = ns._indicatorsVisible ~= false

    -- Threat border (always visible in test mode, otherwise requires animation).
    -- Color Custom Borders recolors the frame border instead of drawing this one
    -- (PvApplyBorderColor), so the slider size does not gate it.
    if f._threatFrame and PP then
        local bs = s.threatBorderSize or 0
        local rc = not compact and s.threatCustomBorder == true and ns.RF_CustomBorderOn(s)
        local wantThreat = bs > 0 or rc
        if ns._testMode and ns._testThreat ~= nil then wantThreat = ns._testThreat end
        local showThreat = wantThreat and (ns._testMode or ns._healthAnimActive) and previewRoles._threatIndex == index
        local agg
        if f.stockHl then
            f._threatFrame:Hide()
            ns.RF_StockAggro(f, showThreat and 3 or nil)
        elseif showThreat and not rc then
            PP.UpdateBorder(f._threatFrame, bs > 0 and bs or 1, 1, 0, 0, 1)
            f._threatFrame:Show()
        else
            f._threatFrame:Hide()
            agg = (showThreat and rc) and true or nil
        end
        if f._pvAggroBdr ~= agg then
            f._pvAggroBdr = agg
            if f._ApplyBorderColor then f._ApplyBorderColor() end
        end
    end

    -- Dispel visuals (border, overlay, icon)
    local dispVis = ns._dispelsVisible ~= false
    local dispelMap = previewRoles._dispelMap
    local dispelType = dispelMap and dispelMap[index]
    local dispelDC = dispelType and GetDispelColor(dispelType, s)
    -- Color Custom Borders: the border takes the type color (PvApplyBorderColor,
    -- below hover/target and aggro), only over a custom border like the real
    -- frames; a change repaints it, the border pass above ran first.
    do
        local bdrC = dispVis and dispelDC and s.dispelCustomBorder == true
            and not compact and (dispelDC.a or 1) > 0 and ns.RF_CustomBorderOn(s) and dispelDC or nil
        if f._pvDispelBdrC ~= bdrC then
            f._pvDispelBdrC = bdrC
            if f._ApplyBorderColor then f._ApplyBorderColor() end
        end
    end
    if dispVis and dispelDC then
        -- Per-type alpha (plain saved value in the preview path)
        local dcA = dispelDC.a or 1
        -- Dispel border (PP.UpdateBorder handles physical pixel sizing internally)
        local dbs = s.dispelBorderSize or 2
        if f._dispelBdrFrame and PP and dbs > 0 then
            PP.UpdateBorder(f._dispelBdrFrame, dbs, dispelDC.r, dispelDC.g, dispelDC.b, dcA)
            f._dispelBdrFrame:Show()
        elseif f._dispelBdrFrame then
            f._dispelBdrFrame:Hide()
        end
        -- Dispel overlay
        local olMode = s.dispelOverlay or "fill"
        if olMode ~= "none" and f._dispelOLTex and f._health then
            local olAlpha = (s.dispelOverlayOpacity or 100) / 100 * dcA
            local olTex = f._dispelOLTex
            olTex:ClearAllPoints()
            -- Reset any prior vertex tint so fill/full render their explicit color cleanly.
            olTex:SetVertexColor(1, 1, 1, 1)
            if olMode == "fill" then
                -- Current health, as on the live frames (the fill, or the rest of
                -- the bar under Inverted Fill), off the bar oriented above.
                ns.RF_AnchorCurHealth(olTex, f._health, f._health:GetStatusBarTexture())
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "full" then
                olTex:SetAllPoints(f._health)
                olTex:SetColorTexture(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            elseif olMode == "gradient" or olMode == "gradient_sharp" then
                -- Same pre-baked gradient textures as the live frames so the preview matches.
                olTex:SetAllPoints(f._health)
                olTex:SetTexture(olMode == "gradient_sharp"
                    and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
                    or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
                olTex:SetVertexColor(dispelDC.r, dispelDC.g, dispelDC.b, olAlpha)
            end
            olTex:Show()
        elseif f._dispelOLTex then
            f._dispelOLTex:Hide()
        end
        -- Dispel type icon (positioned per setting)
        if s.showDispelIcons and f._dispelIcon and f._dispelIconTex then
            local atlas = DISPEL_ICON_ATLAS[dispelType]
            if atlas then f._dispelIconTex:SetAtlas(atlas) end
            f._dispelIcon:ClearAllPoints()
            local diSz = s.dispelIconSize or 16
            f._dispelIcon:SetSize(diSz, diSz)
            local diPos = s.dispelIconPosition or "center"
            local diOX = s.dispelIconOffsetX or 0
            local diOY = s.dispelIconOffsetY or 0
            -- Dispel icon anchors flush to the health bar edge (no 1px inset),
            -- matching the debuff/role icon displays.
            local diHost = ns.RF_AnchorHost(f._health, s)
            if diPos == "topleft" then
                f._dispelIcon:SetPoint("TOPLEFT", diHost, "TOPLEFT", diOX, diOY)
            elseif diPos == "top" then
                f._dispelIcon:SetPoint("TOP", diHost, "TOP", diOX, diOY)
            elseif diPos == "topright" then
                f._dispelIcon:SetPoint("TOPRIGHT", diHost, "TOPRIGHT", diOX, diOY)
            elseif diPos == "left" then
                f._dispelIcon:SetPoint("LEFT", diHost, "LEFT", diOX, diOY)
            elseif diPos == "right" then
                f._dispelIcon:SetPoint("RIGHT", diHost, "RIGHT", diOX, diOY)
            elseif diPos == "bottomleft" then
                f._dispelIcon:SetPoint("BOTTOMLEFT", diHost, "BOTTOMLEFT", diOX, diOY)
            elseif diPos == "bottom" then
                f._dispelIcon:SetPoint("BOTTOM", diHost, "BOTTOM", diOX, diOY)
            elseif diPos == "bottomright" then
                f._dispelIcon:SetPoint("BOTTOMRIGHT", diHost, "BOTTOMRIGHT", diOX, diOY)
            else -- center
                f._dispelIcon:SetPoint("CENTER", diHost, "CENTER", diOX, diOY)
            end
            f._dispelIcon:Show()
        elseif f._dispelIcon then
            f._dispelIcon:Hide()
        end
    else
        if f._dispelBdrFrame then f._dispelBdrFrame:Hide() end
        if f._dispelOLTex then f._dispelOLTex:Hide() end
        if f._dispelIcon then f._dispelIcon:Hide() end
    end

    -- Static dispel debuff icon (shows a fake debuff matching user's debuff settings)
    if f._pvDispelDebuff then
        if dispVis and dispelType and ns._PV_DISPEL_DB_ICONS[dispelType] then
            local ddi = f._pvDispelDebuff
            -- When dispellable debuffs are routed to their own anchor, the
            -- preview icon follows that location, its offsets and its size.
            local dispSplit = (s.dispellableDebuffLocation or "same") ~= "same"
            local dbSz
            if dispSplit then dbSz = ns.RFC_SnapSize(ns.DispellableDebuffSize(s)) else dbSz = ns.RFC_DebuffSize(s) end
            ddi:SetSize(dbSz, dbSz)
            ddi._tex:SetTexture(ns._PV_DISPEL_DB_ICONS[dispelType])
            local _z = s.debuffIconZoom or 0.08
            ddi._tex:SetTexCoord(_z, 1 - _z, _z, 1 - _z)

            -- Position using debuff settings
            ddi:ClearAllPoints()
            local dbPos, dbOX, dbOY
            if dispSplit then
                dbPos = s.dispellableDebuffLocation
                dbOX = s.dispellableDebuffOffsetX or 0
                dbOY = s.dispellableDebuffOffsetY or 0
            else
                dbPos = s.debuffPosition or "bottomright"
                dbOX = s.debuffOffsetX or 0
                dbOY = s.debuffOffsetY or 0
            end
            local ddHost = ns.RF_AnchorHost(f._health, s)
            if dbPos == "topleft" then
                ddi:SetPoint("TOPLEFT", ddHost, "TOPLEFT", dbOX, dbOY)
            elseif dbPos == "top" then
                ddi:SetPoint("TOP", ddHost, "TOP", dbOX, dbOY)
            elseif dbPos == "topright" then
                ddi:SetPoint("TOPRIGHT", ddHost, "TOPRIGHT", dbOX, dbOY)
            elseif dbPos == "left" then
                ddi:SetPoint("LEFT", ddHost, "LEFT", dbOX, dbOY)
            elseif dbPos == "center" then
                ddi:SetPoint("CENTER", ddHost, "CENTER", dbOX, dbOY)
            elseif dbPos == "right" then
                ddi:SetPoint("RIGHT", ddHost, "RIGHT", dbOX, dbOY)
            elseif dbPos == "bottomleft" then
                ddi:SetPoint("BOTTOMLEFT", ddHost, "BOTTOMLEFT", dbOX, dbOY)
            elseif dbPos == "bottom" then
                ddi:SetPoint("BOTTOM", ddHost, "BOTTOM", dbOX, dbOY)
            else -- bottomright
                ddi:SetPoint("BOTTOMRIGHT", ddHost, "BOTTOMRIGHT", dbOX, dbOY)
            end

            -- Border (dispel-type colored)
            local border = ns.RFC_AuraBorder(s, "debuffBorder")
            local dc = GetDispelColor(dispelType, s)
            if border and dc then border[1], border[2], border[3] = dc.r, dc.g, dc.b end
            ns.RFC_ApplyAuraBorder(ddi._borderFrame, ddi._borderFrame, border,
                (ddi._cooldown or ddi):GetFrameLevel())

            if ddi._cooldown then ddi._cooldown:Hide() end
            if ddi._count then ddi._count:SetText("") end
            if ddi._durText then ddi._durText:Hide() end
            ddi:Show()
        else
            f._pvDispelDebuff:Hide()
        end
    end

    -- Hover/target are recolored onto the single border (f._ApplyBorderColor),
    -- applied above with the border style; no separate hover/target frames.

    -- Raid marker (1 random in group 1, 1 random in group 4)
    if f._raidMarker then
        local isMarked = indVis and s.showRaidMarker and
            (index == previewRoles._markerSlot1 or index == previewRoles._markerSlot2)
        if isMarked then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            f._raidMarker:SetSize(rmSz, rmSz)
            -- Use custom marker PNGs
            if index == previewRoles._markerSlot1 then
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            else
                f._raidMarker:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\marker2.png")
                f._raidMarker:SetTexCoord(0, 1, 0, 1)
            end
            -- Anchor based on marker position setting
            f._raidMarker:ClearAllPoints()
            local pos = s.raidMarkerPosition or "center"
            local ox = s.raidMarkerOffsetX or 0
            local oy = s.raidMarkerOffsetY or 0
            local rmHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._raidMarker:SetPoint("TOPLEFT", rmHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._raidMarker:SetPoint("TOP", rmHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._raidMarker:SetPoint("TOPRIGHT", rmHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._raidMarker:SetPoint("LEFT", rmHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._raidMarker:SetPoint("RIGHT", rmHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._raidMarker:SetPoint("BOTTOMLEFT", rmHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._raidMarker:SetPoint("BOTTOM", rmHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._raidMarker:SetPoint("BOTTOMRIGHT", rmHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._raidMarker:SetPoint("CENTER", rmHost, "CENTER", ox, oy)
            end
            f._raidMarker:Show()
        else
            f._raidMarker:Hide()
        end
    end

    -- WoW Forever: Missing Buffs (EUI_RaidFrames_ForeverMissingBuffs.lua).
    if ns.RF_FvMissingPreview then ns.RF_FvMissingPreview(f, index, s, indVis) end

    -- Ready check icon
    if f._readyCheck then
        local rcStatuses = previewRoles._readyCheck
        local rcStatus = rcStatuses and rcStatuses[index]
        local isSummon = rcStatus and rcStatus:sub(1, 6) == "summon"
        local isRez    = rcStatus == "rez"
        local showRC = indVis and rcStatus and (
            (isRez and s.showIncomingRez) or
            (isSummon and s.showSummonPending) or
            (not isSummon and not isRez and s.showReadyCheck)
        )
        if showRC then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            f._readyCheck:SetSize(rcSz, rcSz)
            -- Anchor based on ready-check position setting
            f._readyCheck:ClearAllPoints()
            local pos = s.readyCheckPosition or "center"
            local ox = s.readyCheckOffsetX or 0
            local oy = s.readyCheckOffsetY or 0
            local rcHost = ns.RF_AnchorHost(f._health, s)
            if pos == "topleft" then
                f._readyCheck:SetPoint("TOPLEFT", rcHost, "TOPLEFT", 2 + ox, -2 + oy)
            elseif pos == "top" then
                f._readyCheck:SetPoint("TOP", rcHost, "TOP", ox, -2 + oy)
            elseif pos == "topright" then
                f._readyCheck:SetPoint("TOPRIGHT", rcHost, "TOPRIGHT", -2 + ox, -2 + oy)
            elseif pos == "left" then
                f._readyCheck:SetPoint("LEFT", rcHost, "LEFT", 2 + ox, oy)
            elseif pos == "right" then
                f._readyCheck:SetPoint("RIGHT", rcHost, "RIGHT", -2 + ox, oy)
            elseif pos == "bottomleft" then
                f._readyCheck:SetPoint("BOTTOMLEFT", rcHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            elseif pos == "bottom" then
                f._readyCheck:SetPoint("BOTTOM", rcHost, "BOTTOM", ox, 2 + oy)
            elseif pos == "bottomright" then
                f._readyCheck:SetPoint("BOTTOMRIGHT", rcHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            else -- center
                f._readyCheck:SetPoint("CENTER", rcHost, "CENTER", ox, oy)
            end
            if rcStatus == "ready" then
                f._readyCheck:SetAtlas("UI-LFG-ReadyMark-Raid")
            elseif rcStatus == "notready" then
                f._readyCheck:SetAtlas("UI-LFG-DeclineMark-Raid")
            elseif rcStatus == "pending" then
                f._readyCheck:SetAtlas("UI-LFG-PendingMark-Raid")
            elseif rcStatus == "summon_pending" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonPending")
            elseif rcStatus == "summon_accepted" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonAccepted")
            elseif rcStatus == "summon_declined" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-SummonDeclined")
            elseif rcStatus == "rez" then
                f._readyCheck:SetAtlas("RaidFrame-Icon-Rez")
            end
            f._readyCheck:Show()
        else
            f._readyCheck:Hide()
        end
    end

    -- Name (re-anchor position every refresh, single-point + width constraint)
    if f._nameText then
        -- Text band level: mirrors AnchorNameText on the live buttons ("Show
        -- Above Icons" lifts the carrier over the aura band).
        local pvCarrier = f._nameText:GetParent()
        if pvCarrier and pvCarrier.SetFrameLevel then
            pvCarrier:SetFrameLevel(f:GetFrameLevel()
                + (s.nameTextAboveIcons and (ns.LVL_AURA + 6) or ns.LVL_TEXT))
        end
        f._nameText:ClearAllPoints()
        local pos = s.namePosition or "center"
        if pos == "none" or s.topNameBarEnabled then
            f._nameText:Hide()
        else
        f._nameText:Show()
        local ox = s.nameOffsetX or 0
        local oy = s.nameOffsetY or 0
        f._nameText:SetWidth((s.frameWidth or 72) * ns.RF_NAME_WIDTH_FRACTION)
        f._nameText:SetHeight(0)
        local ntHost = ns.RF_AnchorHost(f._health, s)
        if pos == "topleft" then
            f._nameText:SetPoint("TOPLEFT", ntHost, "TOPLEFT", 2 + ox, -2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "top" then
            f._nameText:SetPoint("TOP", ntHost, "TOP", ox, -2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("TOP")
        elseif pos == "topright" then
            f._nameText:SetPoint("TOPRIGHT", ntHost, "TOPRIGHT", -2 + ox, -2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("TOP")
        elseif pos == "left" then
            f._nameText:SetPoint("LEFT", ntHost, "LEFT", 2 + ox, oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "right" then
            f._nameText:SetPoint("RIGHT", ntHost, "RIGHT", -2 + ox, oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("MIDDLE")
        elseif pos == "bottomleft" then
            f._nameText:SetPoint("BOTTOMLEFT", ntHost, "BOTTOMLEFT", 2 + ox, 2 + oy)
            f._nameText:SetJustifyH("LEFT"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottom" then
            f._nameText:SetPoint("BOTTOM", ntHost, "BOTTOM", ox, 2 + oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("BOTTOM")
        elseif pos == "bottomright" then
            f._nameText:SetPoint("BOTTOMRIGHT", ntHost, "BOTTOMRIGHT", -2 + ox, 2 + oy)
            f._nameText:SetJustifyH("RIGHT"); f._nameText:SetJustifyV("BOTTOM")
        else -- center
            f._nameText:SetPoint("CENTER", ntHost, "CENTER", ox, oy)
            f._nameText:SetJustifyH("CENTER"); f._nameText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        f._nameText:SetText("")
        local attach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
        local pvName = ns.RF_FormatName and ns.RF_FormatName(name, s) or name
        if attach then
            f._nameText:SetFormattedText(attach[1], ns._RFPreviewLevel(), ns.CapName(pvName, s))
        else
            f._nameText:SetText(ns.CapName(pvName, s))
        end
        ApplyFont(f._nameText, s.nameSize or 10)
        f._nameText:SetTextColor(ns.RF_PreviewTextColor(s.nameColorMode or "class",
            s.nameCustomColor, classToken, 1, 1, 1))
        end -- pos ~= "none"
    end

    -- Level text on its own spot (preview): the player's level in the name's colour.
    if f._levelText then
        local lpos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
        if lpos == "none" or ns.RF_LEVEL_ATTACH[lpos] then
            f._levelText:Hide()
        else
            ApplyFont(f._levelText, s.levelTextSize or 10)
            ns.AnchorRFText(f._levelText, ns.RF_BarHost(f._health, s), lpos,
                s.levelTextOffsetX or 0, s.levelTextOffsetY or 0)
            f._levelText:SetFormattedText("%d", ns._RFPreviewLevel())
            f._levelText:SetTextColor(ns.RF_PreviewTextColor(s.nameColorMode or "class",
                s.nameCustomColor, classToken, 1, 1, 1))
            f._levelText:Show()
        end
    end

    -- Dead/offline/AFK states (only when indicators eyeball is on). The rez slot is
    -- a second corpse (dimmed, no "DEAD" text) that shows an incoming-rez icon in
    -- place of the status text -- mirrors the live "hide DEAD while rezzing" behavior.
    local isRezCorpse = indVis and index == previewRoles._rezSlot
    local isDead      = indVis and (index == previewRoles._deadSlot or isRezCorpse)
    local isOffline   = indVis and index == previewRoles._offlineSlot
    -- Mark dead/offline preview frames so the animated-preview ticker skips them
    -- (their health bar is emptied and health text hidden -- never animated).
    f._pvHideHealthText = (isDead or isOffline) or nil
    local isAfk     = indVis and index == previewRoles._afkSlot

    -- Health text
    if f._healthText then
        ApplyFont(f._healthText, s.healthTextSize or 9)
        -- Position
        f._healthText:ClearAllPoints()
        local htPos = s.healthTextPosition or "center"
        local htOX = s.healthTextOffsetX or 0
        local htOY = s.healthTextOffsetY or 0
        local htW = f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75
        f._healthText:SetWidth(htW)
        f._healthText:SetHeight(0)
        local htHost = ns.RF_BarHost(f._health, s)
        if htPos == "topleft" then
            f._healthText:SetPoint("TOPLEFT", htHost, "TOPLEFT", 2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "top" then
            f._healthText:SetPoint("TOP", htHost, "TOP", htOX, -2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "topright" then
            f._healthText:SetPoint("TOPRIGHT", htHost, "TOPRIGHT", -2 + htOX, -2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("TOP")
        elseif htPos == "left" then
            f._healthText:SetPoint("LEFT", htHost, "LEFT", 2 + htOX, htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "right" then
            f._healthText:SetPoint("RIGHT", htHost, "RIGHT", -2 + htOX, htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("MIDDLE")
        elseif htPos == "bottomleft" then
            f._healthText:SetPoint("BOTTOMLEFT", htHost, "BOTTOMLEFT", 2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("LEFT"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottom" then
            f._healthText:SetPoint("BOTTOM", htHost, "BOTTOM", htOX, 2 + htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("BOTTOM")
        elseif htPos == "bottomright" then
            f._healthText:SetPoint("BOTTOMRIGHT", htHost, "BOTTOMRIGHT", -2 + htOX, 2 + htOY)
            f._healthText:SetJustifyH("RIGHT"); f._healthText:SetJustifyV("BOTTOM")
        else
            f._healthText:SetPoint("CENTER", htHost, "CENTER", htOX, htOY)
            f._healthText:SetJustifyH("CENTER"); f._healthText:SetJustifyV("MIDDLE")
        end
        -- Force text re-render (WoW doesn't visually re-layout on JustifyH change alone)
        local htTxt = f._healthText:GetText()
        f._healthText:SetText("")
        f._healthText:SetText(htTxt or "")
        local mode = s.healthTextMode or "none"
        -- Dead and offline sample members keep only the missing amount.
        if (isDead or isOffline) and mode ~= "missing" then mode = "none" end
        if ns.RF_HealthTextInto(f._healthText, mode, healthPct, nil, 12000) then
            -- The preview's classToken stands in for the unit.
            local htr, htg, htb = ns.RF_PreviewTextColor(s.healthTextColorMode or "custom",
                s.healthTextCustomColor, classToken, 1, 1, 1)
            f._healthText:SetTextColor(htr, htg, htb, 0.9)
        end
    end

    -- Heal absorb text (preview): a representative value so the user can see
    -- and position it.
    if f._healAbsorbText then
        local haMode = s.healAbsorbTextMode or "none"
        ApplyFont(f._healAbsorbText, s.healAbsorbTextSize or 9)
        ns.AnchorRFText(f._healAbsorbText, ns.RF_BarHost(f._health, s), s.healAbsorbTextPosition or "center",
            s.healAbsorbTextOffsetX or 0, s.healAbsorbTextOffsetY or 0,
            f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75)
        if haMode ~= "none" and not isDead and not isOffline then
            ns.FormatHealAbsorbInto(f._healAbsorbText, math.floor(healthPct * 3000), haMode)
            local hr, hg, hb = ns.RF_PreviewTextColor(s.healAbsorbTextColorMode or "custom",
                s.healAbsorbTextCustomColor, classToken, 1, 0.3, 0.3)
            f._healAbsorbText:SetTextColor(hr, hg, hb, 0.9)
        else
            f._healAbsorbText:SetText("")
        end
    end

    -- Power text (preview): the sample member's bar value, only where its power bar shows and
    -- (as Health Text) not on the dead or offline sample members.
    -- f._pwtMode / f._pwtPer (mode and made-up amount per percent, nil = hidden) let the
    -- Power Bar section's animated preview keep the text in step with the bar.
    if f._powerText then
        local pwtMode = s.powerTextMode or "none"
        if hidePower or pwtMode == "none" or isDead or isOffline then
            f._powerText:Hide()
            f._pwtMode = nil
        else
            ApplyFont(f._powerText, s.powerTextSize or 8)
            ns.AnchorRFText(f._powerText, ns.RF_BarHost(f._health, s), s.powerTextPosition or "bottom",
                s.powerTextOffsetX or 0, s.powerTextOffsetY or 0,
                f.kitG and f.kitG.health.w or (s.frameWidth or 72) * 0.75)
            local pwtTok = EllesmereUI.CLASS_POWER_MAP[classToken] or "MANA"
            f._pwtPer = (pwtTok == "MANA") and 2500 or 1
            ns.RF_PowerTextInto(f._powerText, pwtMode, f._powerPct or 100, nil, nil, f._pwtPer)
            local pr, pg, pb = ns.RF_PreviewTextColor(s.powerTextColorMode or "custom",
                s.powerTextCustomColor, classToken, 1, 1, 1, pwtTok)
            f._powerText:SetTextColor(pr, pg, pb, 0.9)
            f._powerText:Show()
            f._pwtMode = pwtMode
        end
    end

    -- Status text (DEAD / OFFLINE / AFK)
    if f._statusText then
        local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
        ApplyFont(f._statusText, s.statusTextSize or 14)
        f._statusText:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
        f._statusText:ClearAllPoints()
        local stPos = s.statusTextPosition or "center"
        local stOX = s.statusTextOffsetX or 0
        local stOY = s.statusTextOffsetY or 0
        local stHost = ns.RF_BarHost(f._health, s)
        if stPos == "topleft" then
            f._statusText:SetPoint("TOPLEFT", stHost, "TOPLEFT", 2 + stOX, -2 + stOY)
        elseif stPos == "top" then
            f._statusText:SetPoint("TOP", stHost, "TOP", stOX, -2 + stOY)
        elseif stPos == "topright" then
            f._statusText:SetPoint("TOPRIGHT", stHost, "TOPRIGHT", -2 + stOX, -2 + stOY)
        elseif stPos == "left" then
            f._statusText:SetPoint("LEFT", stHost, "LEFT", 2 + stOX, stOY)
        elseif stPos == "right" then
            f._statusText:SetPoint("RIGHT", stHost, "RIGHT", -2 + stOX, stOY)
        elseif stPos == "bottomleft" then
            f._statusText:SetPoint("BOTTOMLEFT", stHost, "BOTTOMLEFT", 2 + stOX, 2 + stOY)
        elseif stPos == "bottom" then
            f._statusText:SetPoint("BOTTOM", stHost, "BOTTOM", stOX, 2 + stOY)
        elseif stPos == "bottomright" then
            f._statusText:SetPoint("BOTTOMRIGHT", stHost, "BOTTOMRIGHT", -2 + stOX, 2 + stOY)
        else
            f._statusText:SetPoint("CENTER", stHost, "CENTER", stOX, stOY)
        end
        if stPos == "none" then
            -- Status text display is turned off
            f._statusText:Hide()
        elseif isRezCorpse then
            -- Being resurrected: the rez icon takes this spot, so no DEAD text.
            f._statusText:Hide()
        elseif isDead then
            f._statusText:SetText(EllesmereUI.L("DEAD"))
            f._statusText:Show()
        elseif isOffline then
            f._statusText:SetText(EllesmereUI.L("OFFLINE"))
            f._statusText:Show()
        elseif isAfk then
            f._statusText:SetText(EllesmereUI.L("AFK"))
            f._statusText:Show()
        else
            -- No status to show
            f._statusText:Hide()
        end
    end

    -- Dead/DC overlay (mirror the live-frame status tint: full-cover bg)
    if isDead then
        if f._health then
            -- Emptied under Inverted Fill too (a full missing-health bar), so the
            -- current-health area the dispel wash covers stays empty, as live.
            f._health:SetValue(pvInvert and 100 or 0)
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorDead or { r = 0x24/255, g = 0x17/255, b = 0x17/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
        -- Hide shield on dead players
        if f._absorbBar then
            f._absorbBar:Hide()
            if f._absorbBar._forward then f._absorbBar._forward:Hide() end
            if f._absorbBar._topBar then f._absorbBar._topBar:Hide() end
        end
    elseif isOffline then
        if f._health then
            f._health:SetValue(pvInvert and 100 or 0)  -- see the dead branch
            local ft = f._health:GetStatusBarTexture()
            if ft then ft:SetAlpha(0) end
        end
        if f._bg then
            local c = s.statusColorOffline or { r = 0x66/255, g = 0x66/255, b = 0x66/255 }
            f._bg:ClearAllPoints(); f._bg:SetAllPoints(f._health)
            f._bg:SetColorTexture(c.r, c.g, c.b, 1)
        end
    end

    -- Role icon (not affected by indicators toggle)
    if f._roleIcon then
        if f._roleIcon._roleText then f._roleIcon._roleText:Hide() end
        local style = s.roleIconStyle or "modern"
        if s.roleText or style ~= "none" then
            local role = previewRoles[index] or "DAMAGER"
            local showForRole = (role == "TANK" and s.showRoleForTank)
                or (role == "HEALER" and s.showRoleForHealer)
                or (role == "DAMAGER" and s.showRoleForDPS)
            if showForRole ~= false and (s.roleText or ApplyRoleIcon(f._roleIcon, role, style)) then
                local riSz = PixelSnap(s.roleIconSize or 14)
                f._roleIcon:SetSize(riSz, riSz)
                -- Mirror the live carrier's "Show Behind Border" level (see AnchorRoleIcon).
                local rc = f._roleIcon:GetParent()
                if rc then
                    rc:SetFrameLevel(f:GetFrameLevel()
                        + (s.roleIconBehindBorder and ns.LVL_ROLE_BEHIND or (ns.LVL_AURA - 1)))
                end
                f._roleIcon:ClearAllPoints()
                local pos = (s.roleIconPosition or "bottomleft"):upper()
                f._roleIcon:SetPoint(pos, ns.RF_AnchorHost(f._health, s), pos, s.roleIconOffsetX or 0, s.roleIconOffsetY or 0)
                f._roleIcon:Show()
                if s.roleText then ns.ApplyRoleText(f._roleIcon, role, s) end
            else
                f._roleIcon:Hide()
            end
        else
            f._roleIcon:Hide()
        end
    end

    -- Leader icon: show on slot 1 (player = leader in preview)
    if f._leaderIcon then
        if s.showLeaderIcon and index == 1 then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            f._leaderIcon:SetSize(liSz, liSz)
            f._leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            f._leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(f._health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            f._leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            f._leaderIcon:Show()
        else
            f._leaderIcon:Hide()
        end
    end

    -- Combat icon: on live alive members when the indicators eyeball is on.
    if f._combatIcon then
        if indVis and s.showCombatIndicator and not isDead and not isOffline then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            f._combatIcon:SetSize(cciSz, cciSz)
            f._combatIcon:ClearAllPoints()
            local ciPos = (s.combatIndicatorPosition or "right"):upper()
            f._combatIcon:SetPoint(ciPos, ns.RF_AnchorHost(f._health, s), ciPos, s.combatIndicatorOffsetX or 0, s.combatIndicatorOffsetY or 0)
            local style = s.combatIndicatorStyle or "standard"
            local MEDIA = ns._COMBAT_MEDIA
            if style:find("^combat%d") then
                f._combatIcon:SetTexture(MEDIA .. style .. ".tga")
                f._combatIcon:SetTexCoord(0, 1, 0, 1)
                if f._combatIcon.SetDesaturated then f._combatIcon:SetDesaturated(false) end
                f._combatIcon:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and ns._COMBAT_CLASS_COORDS[classToken]
                    if coords then f._combatIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    else f._combatIcon:SetTexCoord(0, 1, 0, 1) end
                else
                    f._combatIcon:SetTexture(MEDIA .. "combat-indicator-custom.png")
                    f._combatIcon:SetTexCoord(0, 1, 0, 1)
                end
                local colorMode = s.combatIndicatorColor or "custom"
                if colorMode == "classcolor" then
                    local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                else
                    local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    f._combatIcon:SetVertexColor(cc.r, cc.g, cc.b, 1)
                end
            end
            f._combatIcon:Show()
        else
            f._combatIcon:Hide()
        end
    end

    -- Buff manager indicators only shown on the BM page preview, not here

    -- Debuff/defensive preview icons managed by PvAuraTicker (cycling system)

    f:Show()
end

ns._previewInitialized = false

local function InitPreviewHealthValues()
    if ns._previewInitialized then return end
    ns._previewInitialized = true
    for i = 1, 20 do
        previewHealthValues[i] = 40 + math.random(60)
        previewPowerValues[i] = 50 + math.random(50)
        ns.previewAbsorbValues[i] = 0
        ns.previewHealAbsorbValues[i] = 0
    end
    -- Assign shields: at least 1 per group of 5, plus a few random extras
    for g = 0, 3 do
        -- Guaranteed 1 per group
        local slot = g * 5 + math.random(5)
        ns.previewAbsorbValues[slot] = 5 + math.random(25)
        -- 50% chance of a second in the group
        if math.random() > 0.5 then
            local slot2 = g * 5 + math.random(5)
            if ns.previewAbsorbValues[slot2] == 0 then
                ns.previewAbsorbValues[slot2] = 3 + math.random(15)
            end
        end
    end
    -- Assign heal absorbs: 2 random slots
    local haPool = {}
    for i = 2, 20 do haPool[#haPool + 1] = i end
    for i = #haPool, 2, -1 do
        local j = math.random(i)
        haPool[i], haPool[j] = haPool[j], haPool[i]
    end
    ns.previewHealAbsorbValues[haPool[1]] = 20 + math.random(20)
    ns.previewHealAbsorbValues[haPool[2]] = 20 + math.random(20)

    -- Assign heal prediction: 2 random slots (non-full-health frames)
    ns.previewHealPredValues = {}
    for i = 1, 20 do ns.previewHealPredValues[i] = 0 end
    local hpPool = {}
    for i = 1, 20 do
        if previewHealthValues[i] < 95 then hpPool[#hpPool + 1] = i end
    end
    for i = #hpPool, 2, -1 do
        local j = math.random(i)
        hpPool[i], hpPool[j] = hpPool[j], hpPool[i]
    end
    if hpPool[1] then ns.previewHealPredValues[hpPool[1]] = 10 + math.random(20) end
    if hpPool[2] then ns.previewHealPredValues[hpPool[2]] = 10 + math.random(20) end

    -- Reduced max health: 2 random slots with 10-25% health loss
    ns.previewReducedMaxHealth = {}
    for i = 1, 20 do ns.previewReducedMaxHealth[i] = 0 end
    local rmhPool = {}
    for i = 2, 20 do rmhPool[#rmhPool + 1] = i end
    for i = #rmhPool, 2, -1 do
        local j = math.random(i)
        rmhPool[i], rmhPool[j] = rmhPool[j], rmhPool[i]
    end
    ns.previewReducedMaxHealth[rmhPool[1]] = 0.10 + math.random() * 0.15
    ns.previewReducedMaxHealth[rmhPool[2]] = 0.10 + math.random() * 0.15
end

I.ApplyPreviewData, I.InitPreviewHealthValues = ApplyPreviewData, InitPreviewHealthValues
I.previewHealthValues, I.previewPowerValues = previewHealthValues, previewPowerValues
I.broken = false
