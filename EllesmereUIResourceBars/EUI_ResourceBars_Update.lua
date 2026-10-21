if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Update.lua
--
--  The update functions of the health, power and class resource bars, the
--  spender tracking, the Ironfur and Ignore Pain bars, visibility and the
--  tickers.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local ceil, min, max = math.ceil, math.min, math.max
local format = string.format
local UnitHealth, UnitHealthMax, UnitPower = UnitHealth, UnitHealthMax, UnitPower
local UnitPowerMax, UnitClass = UnitPowerMax, UnitClass

local CLASS_COLORS, EBON_MIGHT_DURATION = I.CLASS_COLORS, I.EBON_MIGHT_DURATION
local EBON_MIGHT_SPELL_ID, ERB, FRENZIED_REGEN = I.EBON_MIGHT_SPELL_ID, I.ERB, I.FRENZIED_REGEN
local GetIcicleCount, GetPrimaryPowerType = I.GetIcicleCount, I.GetPrimaryPowerType
local GetSpecialization, GUARDIAN_OF_ELUNE, IP = I.GetSpecialization, I.GUARDIAN_OF_ELUNE, I.IP
local IRONFUR_GOE_BONUS, IRONFUR_GOE_WINDOW = I.IRONFUR_GOE_BONUS, I.IRONFUR_GOE_WINDOW
local IRONFUR_SPELL, IronfurBaseDuration = I.IRONFUR_SPELL, I.IronfurBaseDuration
local ironfurTicks, MANGLE_SPELL, POWER_COLORS = I.ironfurTicks, I.MANGLE_SPELL, I.POWER_COLORS
local PT, FindCountBand, GetBarBandCurve = I.PT, I.FindCountBand, I.GetBarBandCurve
local GetBarThresholdCurve, ResolveBandConfig = I.GetBarThresholdCurve, I.ResolveBandConfig
local ResolveThresholdSpecEntry, ApplyBarFlat = I.ResolveThresholdSpecEntry, I.ApplyBarFlat
local ApplyBarGradient, CalcPipGeometry = I.ApplyBarGradient, I.CalcPipGeometry
local IsPowerBarHidden, IsSpecDisabled, pips = I.IsPowerBarHidden, I.IsSpecDisabled, I.pips
local runeFrames, secondaryBarTicks = I.runeFrames, I.secondaryBarTicks
local ApplyResourceBarTicks = I.ApplyResourceBarTicks
local EnsureIronfurOverlay, ironfurTickTex = I.EnsureIronfurOverlay, I.ironfurTickTex
local SetCachedPrimary = I.SetCachedPrimary

local ironfurBaseDur = 7
I.ironfurBaseDurSetters[#I.ironfurBaseDurSetters + 1] = function(v) ironfurBaseDur = v end
local ironfurGoEUntil = 0
I.ironfurGoEUntilSetters[#I.ironfurGoEUntilSetters + 1] = function(v) ironfurGoEUntil = v end
local mainFrame
I.mainFrameSetters[#I.mainFrameSetters + 1] = function(v) mainFrame = v end
local healthBar
I.healthBarSetters[#I.healthBarSetters + 1] = function(v) healthBar = v end
local primaryBar
I.primaryBarSetters[#I.primaryBarSetters + 1] = function(v) primaryBar = v end
local secondaryFrame
I.secondaryFrameSetters[#I.secondaryFrameSetters + 1] = function(v) secondaryFrame = v end
local secondaryBar
I.secondaryBarSetters[#I.secondaryBarSetters + 1] = function(v) secondaryBar = v end
local castBarFrame
I.castBarFrameSetters[#I.castBarFrameSetters + 1] = function(v) castBarFrame = v end
local gcdBarFrame
I.gcdBarFrameSetters[#I.gcdBarFrameSetters + 1] = function(v) gcdBarFrame = v end
local isInCombat = false
I.isInCombatSetters[#I.isInCombatSetters + 1] = function(v) isInCombat = v end
local cachedClass
I.cachedClassSetters[#I.cachedClassSetters + 1] = function(v) cachedClass = v end
local cachedPrimary
I.cachedPrimarySetters[#I.cachedPrimarySetters + 1] = function(v) cachedPrimary = v end
local cachedSecondary
I.cachedSecondarySetters[#I.cachedSecondarySetters + 1] = function(v) cachedSecondary = v end
local _ebonMightExpiry = 0
I.ebonMightExpirySetters[#I.ebonMightExpirySetters + 1] = function(v) _ebonMightExpiry = v end
local UpdateCastBar
I.UpdateCastBarSetters[#I.UpdateCastBarSetters + 1] = function(v) UpdateCastBar = v end
local UpdateGCDBar
I.UpdateGCDBarSetters[#I.UpdateGCDBarSetters + 1] = function(v) UpdateGCDBar = v end

-- Update functions (event-driven)
-- WoW Forever: no health/power number under 10,000 abbreviates
-- (EllesmereUI_NumberFormat.lua). On ns, not a local:
-- the druid mana bar file reads it too.
ns.AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
local function UpdateHealthBar()
    if not healthBar or not healthBar:IsShown() then return end
    local hp = _G._ERB_ResolveHealthCfg()

    local cur = UnitHealth("player")
    local mx = UnitHealthMax("player")
    if not cur or not mx then return end
    if not (issecretvalue and issecretvalue(mx)) and mx <= 0 then return end

    healthBar:SetMinMaxValues(0, mx)

    local curTainted = issecretvalue and issecretvalue(cur)
    -- Percent for text display. UnitHealthPercent may return a secret, but
    -- string.format handles secrets natively (C function): store as-is and only
    -- pass to format/SetFormattedText, NEVER arithmetic.
    local pctRaw
    if UnitHealthPercent then
        pctRaw = UnitHealthPercent("player", true, CurveConstants and CurveConstants.ScaleTo100)
    elseif not curTainted and mx > 0 then
        pctRaw = cur / mx * 100
    else
        pctRaw = 0
    end

    -- Color: threshold via ColorCurve (same as the power bar), from the
    -- per-spec threshold entry.
    local _hpTsEntry = ResolveThresholdSpecEntry(hp)
    local _hpTsEnabled = _hpTsEntry and (_hpTsEntry.thresholdEnabled ~= false) or false
    local _hpBandOn, _hpBands, _hpBandMode, _hpBandRev = ResolveBandConfig(hp, _hpTsEntry)
    if not _hpTsEnabled then _hpTsEntry = nil end
    local ft = healthBar:GetStatusBarTexture()
    local _hpTextInstead = _hpTsEntry and _hpTsEntry.thresholdTextInstead and hp.textFormat ~= "none"
    if (_hpTsEntry or _hpBandOn) and ft and UnitHealthPercent then
        local curve
        local baseR, baseG, baseB
        if hp.customColored then
            baseR, baseG, baseB = hp.fillR, hp.fillG, hp.fillB
        else
            local cc = CLASS_COLORS[cachedClass]
            if cc then baseR, baseG, baseB = cc[1], cc[2], cc[3] else baseR, baseG, baseB = 0.15, 0.75, 0.30 end
        end
        local _bandOn, _bands, _bandMode, _bandRev = _hpBandOn, _hpBands, _hpBandMode, _hpBandRev
		-- Recolor text instead of bar
        if _hpTextInstead then
            local tbR, tbG, tbB
            if hp.textCustomColored == false then
                local tcc = CLASS_COLORS[cachedClass]
                if tcc then tbR, tbG, tbB = tcc[1], tcc[2], tcc[3] else tbR, tbG, tbB = 1, 1, 1 end
            else
                tbR, tbG, tbB = hp.textFillR or 1, hp.textFillG or 1, hp.textFillB or 1
            end
            if _bandOn then
                curve = GetBarBandCurve("health", _bands, _bandMode, mx, tbR, tbG, tbB, _bandRev)
            else
                local tR = _hpTsEntry.thresholdR or hp.thresholdR or 1
                local tG = _hpTsEntry.thresholdG or hp.thresholdG or 0.2
                local tB = _hpTsEntry.thresholdB or hp.thresholdB or 0.2
                curve = GetBarThresholdCurve(tbR, tbG, tbB, tR, tG, tB, _hpTsEntry.thresholdPct or hp.thresholdPct or 30)
            end
            if curve and healthBar._text then
                local ok, colorResult = pcall(UnitHealthPercent, "player", false, curve)
                if ok and colorResult and colorResult.GetRGBA then
                    healthBar._text:SetTextColor(colorResult:GetRGBA())
                end
            end
            -- Fill stays at base color.
            if hp.gradientEnabled then
                ApplyBarGradient(ft, hp.gradientDir or "HORIZONTAL",
                    baseR, baseG, baseB, 1,
                    hp.gradientR, hp.gradientG, hp.gradientB, hp.gradientA)
            else
                ApplyBarFlat(ft, baseR, baseG, baseB, 1)
            end
        else
            if _bandOn then
                curve = GetBarBandCurve("health", _bands, _bandMode, mx, baseR, baseG, baseB, _bandRev)
            else
                local tR = _hpTsEntry.thresholdR or hp.thresholdR or 1
                local tG = _hpTsEntry.thresholdG or hp.thresholdG or 0.2
                local tB = _hpTsEntry.thresholdB or hp.thresholdB or 0.2
                curve = GetBarThresholdCurve(baseR, baseG, baseB, tR, tG, tB, _hpTsEntry.thresholdPct or hp.thresholdPct or 30)
            end
            if curve then
                local ok, colorResult = pcall(UnitHealthPercent, "player", false, curve)
                if ok and colorResult and colorResult.GetRGBA then
                    ft:SetVertexColor(colorResult:GetRGBA())
                end
            end
        end
    elseif ft and not hp.customColored then
        local r, g, b
        local cc = CLASS_COLORS[cachedClass]
        if cc then r, g, b = cc[1], cc[2], cc[3] else r, g, b = 0.15, 0.75, 0.30 end
        if hp.gradientEnabled then
            ApplyBarGradient(ft, hp.gradientDir or "HORIZONTAL",
                r, g, b, 1,
                hp.gradientR, hp.gradientG, hp.gradientB, hp.gradientA)
        else
            ApplyBarFlat(ft, r, g, b, 1)
        end
    end

    -- Fill: the bar's Smooth Bars item decides whether the engine eases toward
    -- the new value (CreateStatusBar's SetValue wrapper), at zero per-frame Lua.
    healthBar:SetValue(cur)

    if hp.textFormat ~= "none" and not _G._ERB_TextHiddenByForm(hp) then
        local fmt = hp.textFormat
        local pctStr = format("%d", pctRaw)
        local curStr = ns.AbbreviateNumbers(cur)
        local txt
        if fmt == "both" then
            txt = curStr .. " | " .. pctStr .. "%"
        elseif fmt == "curhpshort" then
            txt = curStr
        elseif fmt == "curmaxhp" then
            txt = curStr .. " / " .. ns.AbbreviateNumbers(mx)
        elseif fmt == "perhp" then
            txt = pctStr .. "%"
        elseif fmt == "perhpnosign" then
            txt = pctStr
        elseif fmt == "perhpnum" then
            txt = pctStr .. "% | " .. curStr
        else
            txt = pctStr .. "%"
        end
        healthBar._text:SetText(txt)
        healthBar._text:Show()
    else
        healthBar._text:Hide()
    end
end

local function UpdatePrimaryBar()
    if not primaryBar or not primaryBar:IsShown() then return end
    -- Config resolution cache: ResolvePowerCfg/ResolveThresholdSpecEntry/
    -- ResolveBandConfig walk profile tables and only change on a profile edit,
    -- spec swap or form change, but power events fire a dozen times/sec while
    -- casting -- and this pair sat above the "is threshold colouring even on"
    -- branch, so it ran in full for users with the feature off. Resolve once per
    -- config generation (bumped by ApplyAll).
    local pc = ns.PPC
    if not pc or pc.gen ~= ns.CfgGen then
        if not pc then pc = {}; ns.PPC = pc end
        pc.gen = ns.CfgGen
        pc.pp = _G._ERB_ResolvePowerCfg()
        local e = ResolveThresholdSpecEntry(pc.pp)
        -- ResolveBandConfig must see the RAW entry, not the enabled-gated one.
        pc.bandOn, pc.bands, pc.bandMode, pc.bandRev = ResolveBandConfig(pc.pp, e)
        pc.tsEntry = (e and (e.thresholdEnabled ~= false)) and e or nil
        -- Primary power type is spec/form/profile state; every path that can
        -- change it funnels through BuildBars, which bumps CfgGen.
        pc.primary = GetPrimaryPowerType()
        -- WoW Forever mana regen spark: whether this bar shows mana moves
        -- only with the primary power type, so it is reported from here.
        if EllesmereUI.ManaRegenSpark and pc.pp.manaRegenSpark then
            EllesmereUI.ManaRegenSpark.SetMana("erb", pc.primary == PT.MANA)
        end
    end
    local pp = pc.pp

    if cachedPrimary ~= pc.primary then SetCachedPrimary(pc.primary) end
    if not cachedPrimary then return end
    -- Park the engine-slot overlay when the primary is no longer Ebon Might.
    if ns.EMB121_Gate then ns.EMB121_Gate(cachedPrimary == "EBON_MIGHT") end

    -- Ebon Might: aura-based countdown, not a standard power type. The OnUpdate
    -- ticker does the smooth frame-by-frame updates; this path runs on UNIT_AURA
    -- to pick up buff gain/loss/refresh.
    if cachedPrimary == "EBON_MIGHT" then
        if ns.EMB121_Owns then
            -- The engine slot (EUI_ResourceBars_EbonMight121.lua) renders fill and
            -- text -- secrecy makes the numeric path below impossible in combat.
            -- Legacy stays empty underneath; Sync attaches/builds the overlay with
            -- the live bar and settings.
            if ns.EMB121_Sync then
                ns.EMB121_Sync(primaryBar, pp, POWER_COLORS["EBON_MIGHT"])
            end
            primaryBar:SetMinMaxValues(0, EBON_MIGHT_DURATION)
            primaryBar:SetValue(0)
            if ns.EMB121_TextOk and ns.EMB121_TextOk() then
                primaryBar._text:Hide()
                return
            end
            -- Engine text isn't confirmed live yet (build still queued, or its
            -- one-shot FontString attempt failed and won't retry this session)
            -- -- fall through and render the legacy numeric text below instead
            -- of leaving the bar permanently blank.
        end
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(EBON_MIGHT_SPELL_ID)
        -- Ebon Might is secret-flagged: under aura restriction the query returns
        -- nil or carries secret fields, and a secret expirationTime would error in
        -- the numeric chain below. Degrade to an empty bar.
        if aura and issecretvalue(aura.expirationTime) then aura = nil end
        _ebonMightExpiry = (aura and aura.expirationTime) or 0
        local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
        if not ns.EMB121_Owns then
            primaryBar:SetMinMaxValues(0, EBON_MIGHT_DURATION)
            primaryBar:SetValue(remaining)
            -- Color: custom > power color (same priority as standard)
            local ft = primaryBar:GetStatusBarTexture()
            if not pp.customColored then
                local pc = POWER_COLORS["EBON_MIGHT"]
                local r, g, b = 1, 1, 1
                if pc then r, g, b = pc[1], pc[2], pc[3] end
                if pp.gradientEnabled then
                    ApplyBarGradient(ft, pp.gradientDir or "HORIZONTAL", r, g, b, 1,
                        pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
                else
                    ApplyBarFlat(ft, r, g, b, 1)
                end
            end
        end
        if pp.textFormat and pp.textFormat ~= "none" then
            local fmt = pp.textFormat
            local percentSuffix = (pp.showPercent == false) and "" or "%"
            local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
            local timeText = remaining > 0 and format("%.1f", remaining) or "0"
            local txt
            if fmt == "perpp" then txt = pct .. percentSuffix
            elseif fmt == "both" then txt = timeText .. " | " .. pct .. percentSuffix
            else txt = timeText end
            primaryBar._text:SetText(txt)
            primaryBar._text:Show()
        else
            primaryBar._text:Hide()
        end
        return
    end

    local cur = UnitPower("player", cachedPrimary)
    local mx = UnitPowerMax("player", cachedPrimary)
    if not mx or mx <= 0 then return end
    -- Some custom power types (e.g. Devourer Fury) can transiently report a
    -- negative value from the server between spend and the next power sync.
    -- The StatusBar widget itself clamps the *fill* to [0, mx] automatically,
    -- but nothing was clamping the raw number handed to the text formatters
    -- below, so "smart"/"curpp"/"both" text could show a negative number
    -- while the bar visually read empty. Floor it once here, and use the
    -- clamped value everywhere after this point (fill + text) so both stay
    -- consistent. issecretvalue()'d numbers can't be compared, so skip the
    -- floor for those (SetValue's own clamp still protects the fill).
    if not (issecretvalue and issecretvalue(cur)) and cur < 0 then
        cur = 0
    end

    primaryBar:SetMinMaxValues(0, mx)

    local pctRaw = UnitPowerPercent and UnitPowerPercent("player", cachedPrimary, true, CurveConstants and CurveConstants.ScaleTo100) or 0
    local pctTainted = issecretvalue and issecretvalue(pctRaw)
    local pct01 = (not pctTainted) and (pctRaw / 100) or 1

    -- Both allocating stages below (the curve color read returns a color object,
    -- the formatters build strings) are stamped on the value pair, so a repaint
    -- that finds the same value re-derives nothing. A secret value cannot be
    -- compared, so it always rebuilds and drops the stamps (the next clean event
    -- rebuilds too).
    local vmClean = not (issecretvalue and (issecretvalue(cur) or issecretvalue(mx)))
    if not vmClean then primaryBar._colCur = nil; primaryBar._txtCur = nil end

    -- Color: threshold via ColorCurve (secret-safe) for non-mana specs. The
    -- per-spec entry was resolved once per config generation above; pc.tsEntry is
    -- already nil when thresholds are disabled.
    local _ppTsEntry = pc.tsEntry
    local _ppTsEnabled = _ppTsEntry ~= nil
    local _ppBandOn, _ppBands, _ppBandMode, _ppBandRev = pc.bandOn, pc.bands, pc.bandMode, pc.bandRev
    local ft = primaryBar:GetStatusBarTexture()
    local _ppTextInstead = _ppTsEntry and _ppTsEntry.thresholdTextInstead and pp.textFormat ~= "none"
    -- A castable tracked spender outranks threshold and band coloring; Recolor
    -- Text Instead sends it to the text.
    local spOn = ns.PowTracks()
    local spR, spG, spB, spA, spW
    if spOn then spR, spG, spB, spA, spW = ns.PowSpenderColor() end
    local spText = spOn and ns.PTK.entry.thresholdTextInstead and pp.textFormat ~= "none"
    if not spR and primaryBar._ovW then
        if primaryBar._ovTI then
            if pp.textCustomColored == false then
                local tpc = POWER_COLORS[cachedPrimary]
                if tpc then
                    primaryBar._text:SetTextColor(tpc[1], tpc[2], tpc[3], 1)
                else
                    primaryBar._text:SetTextColor(1, 1, 1, 1)
                end
            else
                primaryBar._text:SetTextColor(pp.textFillR or 1, pp.textFillG or 1, pp.textFillB or 1, pp.textFillA or 1)
            end
        end
        primaryBar._ovW, primaryBar._ovGen, primaryBar._ovTI = nil, nil, nil
        primaryBar._colCur, primaryBar._colGen = nil, nil
    end
    if spR then
        if not (primaryBar._ovW == spW and primaryBar._ovGen == ns.CfgGen
                and primaryBar._ovTI == spText) then
            primaryBar._ovW, primaryBar._ovGen, primaryBar._ovTI = spW, ns.CfgGen, spText
            primaryBar._colCur, primaryBar._colGen = nil, nil
            if spText then
                primaryBar._text:SetTextColor(spR, spG, spB, spA or 1)
            elseif ft then
                -- The curve paints raw, so the flat memo may be stale.
                ft._lfOn = nil
                ApplyBarFlat(ft, spR, spG, spB, spA or 1)
            end
        end
    elseif (_ppTsEntry or _ppBandOn) and ft and UnitPowerPercent then
        local curve
        local baseR, baseG, baseB
        if pp.customColored then
            baseR, baseG, baseB = pp.fillR, pp.fillG, pp.fillB
        else
            local pc = POWER_COLORS[cachedPrimary]
            if pc then baseR, baseG, baseB = pc[1], pc[2], pc[3] else baseR, baseG, baseB = 1, 1, 1 end
        end
        local _bandOn, _bands, _bandMode, _bandRev = _ppBandOn, _ppBands, _ppBandMode, _ppBandRev
        local rvR, rvG, rvB = baseR, baseG, baseB
        if _ppTextInstead then
            if pp.textCustomColored == false then
                local tpc = POWER_COLORS[cachedPrimary]
                if tpc then rvR, rvG, rvB = tpc[1], tpc[2], tpc[3] else rvR, rvG, rvB = 1, 1, 1 end
            else
                rvR, rvG, rvB = pp.textFillR or 1, pp.textFillG or 1, pp.textFillB or 1
            end
        end
        if _bandOn then
            curve = GetBarBandCurve("primary", _bands, _bandMode, mx, rvR, rvG, rvB, _bandRev)
        else
            local tR = _ppTsEntry.thresholdR or pp.thresholdR or 1
            local tG = _ppTsEntry.thresholdG or pp.thresholdG or 0.2
            local tB = _ppTsEntry.thresholdB or pp.thresholdB or 0.2
            local tPct = _ppTsEntry.thresholdPct or pp.thresholdPct or 30
            local _ppPartial = _ppTsEntry.thresholdPartialOnly
            if _ppPartial == nil then _ppPartial = pp.thresholdPartialOnly end
            if _ppPartial then
                curve = GetBarThresholdCurve(rvR, rvG, rvB, tR, tG, tB, tPct)
            else
                curve = GetBarThresholdCurve(tR, tG, tB, rvR, rvG, rvB, tPct)
            end
        end
        -- The curve object is the settings identity (rebuilt on any input change),
        -- so (value, max, curve, target) names every input of this color.
        if curve and not (vmClean and primaryBar._colCur == cur and primaryBar._colMx == mx
                          and primaryBar._colCurve == curve and primaryBar._colTI == _ppTextInstead) then
            if vmClean then
                primaryBar._colCur, primaryBar._colMx = cur, mx
                primaryBar._colCurve, primaryBar._colTI = curve, _ppTextInstead
            end
            local ok, colorResult = pcall(UnitPowerPercent, "player", cachedPrimary, false, curve)
            if ok and colorResult and colorResult.GetRGBA then
                if _ppTextInstead then
                    if primaryBar._text then primaryBar._text:SetTextColor(colorResult:GetRGBA()) end
                else
                    ft:SetVertexColor(colorResult:GetRGBA())
                end
            end
        end
        if _ppTextInstead then
            -- Fill stays at base color; static per config generation + power
            -- type, so reapplying it on every power tick was pure churn.
            if primaryBar._colGen ~= ns.CfgGen or primaryBar._colPow ~= cachedPrimary then
                primaryBar._colGen, primaryBar._colPow = ns.CfgGen, cachedPrimary
                if pp.gradientEnabled then
                    ApplyBarGradient(ft, pp.gradientDir or "HORIZONTAL",
                        baseR, baseG, baseB, 1,
                        pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
                else
                    ApplyBarFlat(ft, baseR, baseG, baseB, 1)
                end
            end
        end
    elseif spOn and not spText then
        -- Spender coloring keeps the base flat, as threshold coloring does.
        if primaryBar._colGen ~= ns.CfgGen or primaryBar._colPow ~= cachedPrimary then
            primaryBar._colGen, primaryBar._colPow = ns.CfgGen, cachedPrimary
            local r, g, b
            if pp.customColored then
                r, g, b = pp.fillR, pp.fillG, pp.fillB
            else
                local pc = POWER_COLORS[cachedPrimary]
                if pc then r, g, b = pc[1], pc[2], pc[3] else r, g, b = 1, 1, 1 end
            end
            ApplyBarFlat(ft, r, g, b, 1)
        end
    elseif not pp.customColored then
        -- Static per config generation + power type (same stamp as above).
        if primaryBar._colGen ~= ns.CfgGen or primaryBar._colPow ~= cachedPrimary then
            primaryBar._colGen, primaryBar._colPow = ns.CfgGen, cachedPrimary
            local r, g, b
            local pc = POWER_COLORS[cachedPrimary]
            if pc then r, g, b = pc[1], pc[2], pc[3] else r, g, b = 1, 1, 1 end
            if pp.gradientEnabled then
                ApplyBarGradient(ft, pp.gradientDir or "HORIZONTAL",
                    r, g, b, 1,
                    pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
            else
                ApplyBarFlat(ft, r, g, b, 1)
            end
        end
    end

    -- Fill: eased only while the bar's Smooth Bars item is on (see the health
    -- handler note).
    primaryBar:SetValue(cur)

    if pp.textFormat ~= "none" and not _G._ERB_TextHiddenByForm(pp) then
        -- Stamped only when the text is actually written, so a form-hidden
        -- stretch can never leave a stale string behind for a repeated value.
        if not (vmClean and primaryBar._txtCur == cur and primaryBar._txtMx == mx
                and primaryBar._txtGen == ns.CfgGen and primaryBar._txtPow == cachedPrimary) then
            if vmClean then
                primaryBar._txtCur, primaryBar._txtMx = cur, mx
                primaryBar._txtGen, primaryBar._txtPow = ns.CfgGen, cachedPrimary
            end
            local fmt = pp.textFormat
            local percentSuffix = (pp.showPercent == false) and "" or "%"
            local percentText = format("%d", pctRaw) .. percentSuffix
            local txt
            if fmt == "smart" then
                local isPercent = EllesmereUI.IsSmartPowerPercent and EllesmereUI.IsSmartPowerPercent(cachedPrimary)
                txt = isPercent and percentText or ns.AbbreviateNumbers(cur)
            elseif fmt == "both" then
                txt = ns.AbbreviateNumbers(cur) .. " | " .. percentText
            elseif fmt == "curpp" then
                txt = ns.AbbreviateNumbers(cur)
            elseif fmt == "curmaxpp" then
                txt = ns.AbbreviateNumbers(cur) .. " / " .. ns.AbbreviateNumbers(mx)
            elseif fmt == "perpp" then
                txt = percentText
            else
                txt = ns.AbbreviateNumbers(cur)
            end
            primaryBar._text:SetText(txt)
        end
        primaryBar._text:Show()
    else
        primaryBar._text:Hide()
    end
end

-- Pre-allocated rune sorting buffers to avoid per-tick table creation.
-- Uses parallel arrays instead of tables-of-tables for zero GC pressure.
local _runeOrder = {}       -- [slot] = rune index (1-6)
local _runeRemaining = {}   -- [rune index] = remaining time
local _runeStart = {}       -- [rune index] = cooldown start
local _runeDuration = {}    -- [rune index] = cooldown duration
local _runeReady = {}       -- [rune index] = true/false

-- Evoker Essence recharge state (timer-based, UnitPower partial doesn't work for Essence)
local _essenceNextTick = nil   -- GetTime() when the next pip will be ready
I.essenceNextTickSetters[#I.essenceNextTickSetters + 1] = function(v) _essenceNextTick = v end
local _essenceLastCount = nil  -- last known whole-pip count
I.essenceLastCountSetters[#I.essenceLastCountSetters + 1] = function(v) _essenceLastCount = v end
local _essenceTickDur = 0      -- seconds per pip recharge
I.essenceTickDurSetters[#I.essenceTickDurSetters + 1] = function(v) _essenceTickDur = v end
-- Seconds per Essence pip from the regen rate; the last known duration (5 before
-- any) while the rate reads secret, as it does in combat. On ns.
function ns.EssenceTickDuration()
    if not GetPowerRegenForPowerType then return _essenceTickDur > 0 and _essenceTickDur or 5 end
    local regen = GetPowerRegenForPowerType(PT.ESSENCE)
    if not regen or (issecretvalue and issecretvalue(regen)) then
        return _essenceTickDur > 0 and _essenceTickDur or 5
    end
    return regen > 0 and (1 / regen) or 5
end

-- Cast handler for the Prot Ignore Pain bar's moving hash line: each cast
-- refreshes the buff, so the line resets to the right edge and slides left.
IP.HandleCast = function(spellID)
    if not (cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR") then return end
    if spellID == IP.SPELL then
        IP.hashEndTime = GetTime() + IP.DURATION
        return
    end
    -- Indirect refresh: Shield Slam consuming Violent Outburst. Layered probe --
    -- GetPlayerAuraBySpellID is plain table-or-nil for unflagged ids (returns
    -- NOTHING for restriction-flagged ids, today's law), so the viewer-active
    -- fallback (frames-as-truth, works under restriction when the user tracks
    -- the proc) backs it up. Called at SUCCEEDED: if the proc aura is already
    -- consumed by then BOTH probes can miss -- field question; the escalation
    -- is a SENT-time latch, not a wider guess. A miss leaves a stale tick and,
    -- since the bar fill rides this same window, an early-empty bar; IP.Active
    -- covers both from the tracked-buff icon when the user tracks IP.
    if spellID == IP.SHIELD_SLAM then
        local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and C_UnitAuras.GetPlayerAuraBySpellID(IP.VO_PROC)
        if aura or (IP.BuffActiveViaViewer and IP.BuffActiveViaViewer(IP.VO_PROC)) then
            IP.hashEndTime = GetTime() + IP.DURATION
        end
    end
end

-- Cast handler for the Guardian Ironfur bar. Only tracks while the Ironfur
-- bar is the active class resource so the tick list can't grow unbounded.
local function HandleIronfurCast(spellID)
    if not (cachedSecondary and cachedSecondary.power == "IRONFUR_BAR") then return end
    local now = GetTime()
    if spellID == IRONFUR_SPELL then
        ironfurBaseDur = IronfurBaseDuration()
        local hasGoE = ironfurGoEUntil > 0 and now < ironfurGoEUntil
            and C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE)
        local dur = ironfurBaseDur + (hasGoE and IRONFUR_GOE_BONUS or 0)
        ironfurTicks[#ironfurTicks + 1] = { endTime = now + dur, duration = dur }
        if hasGoE then ironfurGoEUntil = 0 end
    elseif spellID == MANGLE_SPELL then
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(GUARDIAN_OF_ELUNE) then
            ironfurGoEUntil = now + IRONFUR_GOE_WINDOW
        end
    elseif spellID == FRENZIED_REGEN then
        ironfurGoEUntil = 0
    end
end

-- Recolor text instead of bar
local function colorText(on, triggered, tr, tg, tb, baseR, baseG, baseB)
    if not on then return end
    local ct = secondaryFrame and secondaryFrame._countText
    if not ct then return end
    if triggered then ct:SetTextColor(tr, tg, tb, 0.9)
    else ct:SetTextColor(baseR, baseG, baseB, 0.9) end
end

-- Buff-color for the resource bar. Combat procs read Blizzard's Cooldown Viewer
-- active state, so only buffs the Cooldown Manager tracks are found; any ID may
-- still be entered and tried.
local _euiBuffViewers = { "BuffBarCooldownViewer", "BuffIconCooldownViewer" }
-- Spell names never change within a session, so the buff check and its viewer
-- scan read them from here instead of asking the client on every update.
local _euiSpellNames = {}
local function CachedSpellName(spellID)
    local nm = _euiSpellNames[spellID]
    if nm == nil then
        nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or false
        _euiSpellNames[spellID] = nm
    end
    return nm or nil
end
-- Every item frame each viewer's pool has handed out, in plain arrays refreshed
-- only after the pool acquired one (a released item is hidden with its cooldown
-- data cleared, so a shown frame here is exactly a shown active item). The pools
-- are Blizzard's secure pools: walking one builds an iterator closure and makes a
-- secure call per step, too costly for a check that runs on every class-resource update.
-- One table.
local BVI = { items = { {}, {} }, seen = { {}, {} }, dirty = { true, true }, hooked = {} }
function BVI.Items(vi)
    local vf = _G[_euiBuffViewers[vi]]
    local pool = vf and vf.itemFramePool
    if not (pool and pool.EnumerateActive) then return nil end
    local dirty = BVI.dirty
    if BVI.hooked[vi] ~= pool then
        BVI.hooked[vi] = pool
        dirty[vi] = true
        hooksecurefunc(pool, "Acquire", function() dirty[vi] = true end)
    end
    local list = BVI.items[vi]
    if dirty[vi] then
        dirty[vi] = false
        local seen = BVI.seen[vi]
        for frame in pool:EnumerateActive() do
            if not seen[frame] then
                seen[frame] = true
                list[#list + 1] = frame
            end
        end
    end
    return list
end
-- True when any ID the viewer scan compares is secret: Blizzard writes secret
-- values into an item's live cooldownInfo mid-fight (raid encounters), and
-- comparing one from addon code is a hard error.
function BVI.Secret(info)
    if not issecretvalue then return false end
    if issecretvalue(info.spellID) or issecretvalue(info.overrideSpellID) then return true end
    local linked = info.linkedSpellIDs
    if type(linked) == "table" then
        for i = 1, #linked do
            if issecretvalue(linked[i]) then return true end
        end
    end
    return false
end
local function BuffActiveViaCooldownViewer(spellID, wantName)
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    for vi = 1, #_euiBuffViewers do
        local list = BVI.Items(vi)
        if list then
            for li = 1, #list do
                local frame = list[li]
                if frame:IsShown() then    -- shown = the buff is currently up
                    -- The item's own cooldownInfo is the data provider's live
                    -- table (Blizzard updates its override and linked IDs in
                    -- place), so reading it allocates nothing; a
                    -- GetCooldownViewerCooldownInfo call builds a fresh copy per
                    -- item. An item without one, or whose live table holds a
                    -- secret ID, reads that copy instead: its fields are never
                    -- secret (no secret returns in the API docs), and a copy that
                    -- somehow is still secret is skipped rather than compared.
                    local info = frame.cooldownInfo
                    if not info or BVI.Secret(info) then
                        local cdID = frame.cooldownID
                        info = nil
                        if type(cdID) == "number" and not (issecretvalue and issecretvalue(cdID)) then
                            info = gci(cdID)
                            if info and BVI.Secret(info) then info = nil end
                        end
                    end
                    if info then
                        if info.spellID == spellID or info.overrideSpellID == spellID then return true end
                        if info.linkedSpellIDs then
                            for _, lid in ipairs(info.linkedSpellIDs) do
                                if lid == spellID then return true end
                            end
                        end
                        local sid = wantName and info.spellID
                        if sid then
                            local nm = _euiSpellNames[sid]
                            if nm == nil then nm = CachedSpellName(sid) end
                            if nm == wantName then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end
-- Published for IP.HandleCast (defined ABOVE this helper -- a direct upvalue
-- reference there would compile as a nil global; the table field binds late).
IP.BuffActiveViaViewer = BuffActiveViaCooldownViewer

local function PlayerHasBuff(spellID)
    if not spellID or spellID == 0 or not C_UnitAuras then return false end
    local nm = CachedSpellName(spellID)
    -- 1) Exact aura spellId match.
    local byID = C_UnitAuras.GetPlayerAuraBySpellID
    if byID then
        local ok, aura = pcall(byID, spellID)
        if ok and aura ~= nil then return true end
    end
    -- 2) Name match. The APPLIED aura's spellId often differs from the entered
    -- (tooltip) ID (per-spec variants), so match by name. Presence only.
    local byName = C_UnitAuras.GetAuraDataBySpellName
    if byName and nm then
        local ok, aura = pcall(byName, "player", nm, "HELPFUL")
        if ok and aura ~= nil then return true end
    end
    -- 3) Secret rotational procs (Essence Burst etc.) are invisible to both aura
    -- reads; fall back to Blizzard's Cooldown Viewer active state.
    if BuffActiveViaCooldownViewer(spellID, nm) then return true end
    return false
end

-- Buff coloring for the class-resource bar. The 5th return is the winning row's
-- index, which the class-bar value early-out keys on.
local function ActiveBuffColor(entry)
    if not entry or not entry.buffColorEnabled then return nil end
    local list = entry.buffColors
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if e.spellID and PlayerHasBuff(e.spellID) then
            return e.r, e.g, e.b, e.a, i
        end
    end
    return nil
end

-- Config-derived coloring answers for the class-resource bar, rebuilt once per
-- ns.CfgGen (BuildBars and ApplyAll bump it on every option edit and on profile,
-- spec, talent and form changes). entry = the resolved threshold entry while the
-- bar is enabled; buff / spend = that entry colors by buffs / by spenders; ids =
-- the tracked spender spell IDs; w = the winning spender index (nil = not scanned
-- since the bump); oncd = per-spell verdicts ("on a real cooldown"), keyed by the
-- configured spell ID and latched from SPELL_UPDATE_COOLDOWN. The verdicts outlive
-- the bump (a rebuild in combat must not send every spell back to a live read):
-- a spell that leaves the list is pruned, and disarming wipes them all.
ns.STK = { ids = {}, oncd = {} }
-- The Power Bar's counterpart (entry, spend, ids, w, oncd).
ns.PTK = { ids = {}, oncd = {} }

-- True when the entry colors by spenders and at least one row names a spell (a
-- blank "+ Add Spender" row arms nothing). Refills ids (default ns.STK.ids) with
-- those spells.
function ns.SecondaryTracksSpender(e, ids)
    ids = ids or ns.STK.ids
    wipe(ids)
    local list = e and e.spenderColorEnabled and e.spenderColors
    if not list then return false end
    local any = false
    for i = 1, #list do
        local id = list[i].spellID
        if id then ids[id] = true; any = true end
    end
    return any
end

-- The one accessor for those answers. Returns buff, spend.
function ns.SecTracks()
    local t = ns.STK
    if t.gen ~= ns.CfgGen then
        t.gen = ns.CfgGen
        local sp = _G._ERB_ResolveSecondaryCfg()
        local e = sp and sp.enabled ~= false and ResolveThresholdSpecEntry(sp) or nil
        t.entry = e
        t.buff = (e and e.buffColorEnabled and e.buffColors and #e.buffColors > 0) and true or false
        t.spend = ns.SecondaryTracksSpender(e)
        t.w = nil
        -- Nothing latches a spell that left the list, so its verdict would go
        -- stale if it came back later: drop it.
        local oncd, ids = t.oncd, t.ids
        for id in pairs(oncd) do
            if not ids[id] then oncd[id] = nil end
        end
    end
    return t.buff, t.spend
end

-- The Power Bar's counterpart of ns.SecTracks. Returns spend. A Power Bar that
-- cannot show (IsPowerBarHidden: off, hidden in this form or by Hide Power Bar if
-- Resource, no primary power) tracks nothing, so no spender events stay armed.
function ns.PowTracks()
    local t = ns.PTK
    if t.gen ~= ns.CfgGen then
        t.gen = ns.CfgGen
        local pp = _G._ERB_ResolvePowerCfg()
        local e = pp and not IsPowerBarHidden() and ResolveThresholdSpecEntry(pp) or nil
        t.entry = e
        t.spend = ns.SecondaryTracksSpender(e, t.ids)
        t.w = nil
        local oncd, ids = t.oncd, t.ids
        for id in pairs(oncd) do
            if not ids[id] then oncd[id] = nil end
        end
    end
    return t.spend
end

-- Spender coloring: the FIRST castable spell in the entry's list wins. Each spell
-- is read through its current override (transforming spells). Castable means
-- IsSpellUsable (resource, range, known) and not on a real cooldown: IsSpellUsable
-- ignores cooldowns, so a spell that is free under some condition (Void Ray during
-- Void Metamorphosis) would otherwise read castable for its whole cooldown. A
-- charge spell is castable while it holds a charge. Its count is secret in
-- restricted combat: full charges still read from the recharge flag, and a
-- recharging spell falls back to the latched verdict like every other spell. The
-- latch stands in for a live read because isOnGCD is only trustworthy inside
-- SPELL_UPDATE_COOLDOWN; a live read covers a spell only until its first latch.
-- oncd: the bar's verdicts (default ns.STK.oncd). Returns the winning index, 0
-- for none.
function ns.SpenderScan(entry, oncd)
    local list = entry and entry.spenderColorEnabled and entry.spenderColors
    if not list then return 0 end
    local S = C_Spell
    oncd = oncd or ns.STK.oncd
    for i = 1, #list do
        local sid = list[i].spellID
        if sid then
            local id = S.GetOverrideSpell(sid) or sid
            if S.IsSpellUsable(id) then
                local ready
                local ch = S.GetSpellCharges(id)
                local mx = ch and ch.maxCharges
                if mx and mx > 1 then
                    local n = ch.currentCharges
                    if not (issecretvalue and issecretvalue(n)) then
                        ready = n > 0
                    elseif not ch.isActive then
                        ready = true
                    end
                end
                if ready == nil then
                    local oc = oncd[sid]
                    if oc == nil then
                        local cd = S.GetSpellCooldown(id)
                        oc = cd and cd.isActive and not cd.isOnGCD
                    end
                    ready = not oc
                end
                if ready then return i end
            end
        end
    end
    return 0
end

-- Cached winning spender index (0 = none): scanned once after each config bump,
-- then kept current by the spender pass (next to ns.PollTick). Call after
-- ns.SecTracks().
function ns.SpenderWinner()
    local t = ns.STK
    local w = t.w
    if w == nil then
        w = t.spend and ns.SpenderScan(t.entry) or 0
        t.w = w
    end
    return w
end

-- Override color of the cached winning spender. The paints and their 30 Hz and
-- 10 Hz tickers read this; only the spender pass queries the spell APIs.
function ns.ActiveSpenderColor(entry)
    local _, spend = ns.SecTracks()
    if not spend or entry ~= ns.STK.entry then return nil end
    local w = ns.SpenderWinner()
    local e = w > 0 and entry.spenderColors[w]
    if e then return e.r, e.g, e.b, e.a end
    return nil
end

-- The Power Bar's counterpart of ns.SpenderWinner. Call after ns.PowTracks().
function ns.PowSpenderWinner()
    local t = ns.PTK
    local w = t.w
    if w == nil then
        w = t.spend and ns.SpenderScan(t.entry, t.oncd) or 0
        t.w = w
    end
    return w
end

-- The Power Bar's override color and winning index. Separate from
-- ns.ActiveSpenderColor so class-resource paints pay nothing for it.
function ns.PowSpenderColor()
    if not ns.PowTracks() then return nil end
    local w = ns.PowSpenderWinner()
    local e = w > 0 and ns.PTK.entry.spenderColors[w]
    if e then return e.r, e.g, e.b, e.a, w end
    return nil
end

-- Per-frame render for the Guardian Ironfur bar: prune expired ticks, position
-- the moving hash lines (right -> left as each cast decays), and drive the fill
-- to the longest-remaining fraction.
local function UpdateIronfurBar()
    if not (secondaryBar and secondaryBar:IsShown()) then return end
    local sp = _G._ERB_ResolveSecondaryCfg() or ERB.db.profile.secondary
    local now = GetTime()

    -- Prune expired casts
    for i = #ironfurTicks, 1, -1 do
        if ironfurTicks[i].endTime <= now then
            table.remove(ironfurTicks, i)
        end
    end

    local count = #ironfurTicks
    local barW = secondaryBar:GetWidth() or 0
    local barH = secondaryBar:GetHeight() or 0
    local overlay = secondaryBar._ifOverlay
    local showHash = sp.guardianShowHashLines ~= false
    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = PP and (2 * PP.mult) or 2
    local maxFrac = 0
    local shown = 0

    -- Follow bar orientation instead of assuming horizontal.
    local oriSb = secondaryBar._sb
    local vert = (oriSb and oriSb.GetOrientation and oriSb:GetOrientation() == "VERTICAL") or false
    local revFill = (vert and oriSb.GetReverseFill and oriSb:GetReverseFill()) or false

    for i = 1, count do
        local t = ironfurTicks[i]
        local frac = (t.duration > 0) and ((t.endTime - now) / t.duration) or 0
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        if frac > maxFrac then maxFrac = frac end
        if showHash and overlay and barW > 0 and barH > 0 then
            shown = shown + 1
            local tex = ironfurTickTex[shown]
            if not tex then
                tex = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
                ironfurTickTex[shown] = tex
            end
            tex:SetColorTexture(1, 1, 1, 0.9)
            tex:ClearAllPoints()
            if vert then
                local y = frac * barH
                if y > barH - tickW then y = barH - tickW end
                if y < 0 then y = 0 end
                tex:SetSize(barW, tickW)
                if revFill then
                    tex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", 0, -y)
                else
                    tex:SetPoint("BOTTOMLEFT", secondaryBar, "BOTTOMLEFT", 0, y)
                end
            else
                local x = frac * barW
                if x > barW - tickW then x = barW - tickW end
                if x < 0 then x = 0 end
                tex:SetSize(tickW, barH)
                tex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", x, 0)
            end
            tex:Show()
        end
    end

    -- Hide any leftover pooled tick textures
    for i = shown + 1, #ironfurTickTex do ironfurTickTex[i]:Hide() end

    -- Fill color: class/custom/dark base, swapped to the per-spec threshold
    -- color while the active Ironfur stack count is at or above the threshold.
    local r, g, b, a
    if sp.darkTheme then
        local _dfr, _dfg, _dfb = EllesmereUI.GetDarkModeFill()
        r, g, b, a = _dfr, _dfg, _dfb, 1
    elseif sp.classColored ~= false then
        local cc = CLASS_COLORS[cachedClass]
        if cc then r, g, b = cc[1], cc[2], cc[3] else r, g, b = 1, 1, 1 end
        a = 1
    else
        r, g, b, a = sp.fillR, sp.fillG, sp.fillB, 1
    end
    local tsEntry = ResolveThresholdSpecEntry(sp)
    -- Capture "recolor text instead" BEFORE the buff nils tsEntry below so the flag
    -- survives (buff + text-instead => buff colors the count text, fill stays base).
    local _tiWanted = (tsEntry and tsEntry.thresholdTextInstead and sp.showText) and true or false
    -- Buff coloring wins: a tracked buff on this entry overrides the base color and
    -- suppresses the stack-count threshold/bands below.
    local _bfr, _bfg, _bfb, _bfa = ActiveBuffColor(tsEntry)
    -- No tracked buff active: a castable spender supplies the override color instead.
    if not _bfr then _bfr, _bfg, _bfb, _bfa = ns.ActiveSpenderColor(tsEntry) end
    local _buffActive = _bfr ~= nil
    if _buffActive and not _tiWanted then r, g, b, a = _bfr or r, _bfg or g, _bfb or b, _bfa or a end
    -- Ironfur colors by active stack count, NOT the bar's duration fraction, so
    -- both single-threshold and multi-band match against `count`; multi wins when
    -- enabled with bands, else the single stack-count threshold (FindCountBand).
    local bandOn, bands, _bandMode, bandRev = ResolveBandConfig(sp, tsEntry)
    if _buffActive then tsEntry = nil; bandOn = false end
    -- Active (threshold/band) color is computed separately from the base so it can
    -- route to the fill or the count text. `triggered` = the stack count satisfies
    -- the threshold/band.
    local arR, arG, arB, arA = r, g, b, a
    local triggered = false
    if bandOn then
        local band = FindCountBand(bands, count, bandRev)
        if band then
            arR = band.r or r
            arG = band.g or g
            arB = band.b or b
            arA = band.a or a
            triggered = true
        end
    elseif tsEntry and tsEntry.thresholdEnabled ~= false then
        local threshCount = tsEntry.thresholdCount or sp.thresholdCount or 3
        if count >= threshCount then
            arR = tsEntry.thresholdR or sp.thresholdR or r
            arG = tsEntry.thresholdG or sp.thresholdG or g
            arB = tsEntry.thresholdB or sp.thresholdB or b
            arA = tsEntry.thresholdA or sp.thresholdA or a
            triggered = true
        end
    end
    local _spTextInstead = _tiWanted
    local ft = secondaryBar:GetStatusBarTexture()
    if ft then
        if _spTextInstead then ft:SetVertexColor(r, g, b, a)
        else ft:SetVertexColor(arR, arG, arB, arA) end
    end

    -- Fill = longest remaining fraction (min/max is 0..1 here), so the bar depletes
    -- with the longest-lived Ironfur stack. Set directly: this runs from the motion
    -- ticker, which is its own smooth cadence.
    secondaryBar:SetValue(maxFrac)

    if sp.showText and secondaryFrame and secondaryFrame._countText then
        secondaryFrame._countText:SetText(count > 0 and tostring(count) or "")
        -- Buff + text-instead: use the buff color as the text base (there's no
        -- stack-threshold trigger while a buff is up), so colorText paints it.
        local _tbR, _tbG, _tbB = sp.textR or 1, sp.textG or 1, sp.textB or 1
        if _buffActive and _spTextInstead then _tbR, _tbG, _tbB = _bfr, _bfg, _bfb end
        colorText(_spTextInstead, triggered, arR, arG, arB, _tbR, _tbG, _tbB)
    end
end

-- Single moving hash line for the Prot Ignore Pain bar (Ironfur-style): resets to the
-- right edge on each cast, slides left as the buff decays. Reuses the Ironfur overlay
-- host with one pooled texture, driven from the main OnUpdate while the bar is shown.
IP.UpdateHash = function()
    local sp = ERB.db.profile.secondary
    local remain = IP.hashEndTime - GetTime()
    if sp.protIgnorePainHashLine == false or remain <= 0 then
        if IP.hashTex then IP.hashTex:Hide() end
        return
    end
    local barW = secondaryBar:GetWidth() or 0
    local barH = secondaryBar:GetHeight() or 0
    if barW <= 0 then return end
    local overlay = EnsureIronfurOverlay(secondaryBar)
    if not IP.hashTex then
        IP.hashTex = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        IP.hashTex:SetSnapToPixelGrid(false)
        IP.hashTex:SetTexelSnappingBias(0)
        IP.hashTex:SetColorTexture(1, 1, 1, 0.9)
    end
    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = PP and (2 * PP.mult) or 2
    local frac = remain / IP.DURATION
    if frac > 1 then frac = 1 end
    -- Follow bar orientation instead of assuming horizontal.
    local oriSb = secondaryBar._sb
    local vert = (oriSb and oriSb.GetOrientation and oriSb:GetOrientation() == "VERTICAL") or false
    local revFill = (vert and oriSb.GetReverseFill and oriSb:GetReverseFill()) or false
    IP.hashTex:ClearAllPoints()
    if vert then
        local y = frac * barH
        if y > barH - tickW then y = barH - tickW end
        if y < 0 then y = 0 end
        IP.hashTex:SetSize(barW, tickW)
        if revFill then
            IP.hashTex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", 0, -y)
        else
            IP.hashTex:SetPoint("BOTTOMLEFT", secondaryBar, "BOTTOMLEFT", 0, y)
        end
    else
        local x = frac * barW
        if x > barW - tickW then x = barW - tickW end
        if x < 0 then x = 0 end
        IP.hashTex:SetSize(tickW, barH)
        IP.hashTex:SetPoint("TOPLEFT", secondaryBar, "TOPLEFT", x, 0)
    end
    IP.hashTex:Show()
end

-- In-combat text source: the ONLY clean stack number in combat is the one
-- Blizzard's tracked-buff (cooldown viewer) Ignore Pain icon displays, observed
-- via hooksecurefunc on its stack FontString's SetText. Every direct read is
-- secret (absorbs, aura data, bar value, rendered fill rect); no dependency on
-- the EUI CDM module. Degrades gracefully: viewer hidden/IP untracked falls back
-- to the fill-width readback (clean values only) or stays blank.
IP.FrameSpellID = function(frame)
    if frame.GetSpellID then
        local ok, sid = pcall(frame.GetSpellID, frame)
        if ok and sid and not (issecretvalue and issecretvalue(sid)) then return sid end
    end
    local cdID = frame.cooldownID or (frame.cooldownInfo and frame.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local sid = info.spellID
            if sid and not (issecretvalue and issecretvalue(sid)) then return sid end
        end
    end
end

IP.HookViewerFS = function(frame, appFS)
    IP.viewerFrame = frame
    IP.viewerFS = appFS
    if not IP.hookedFS[appFS] then
        IP.hookedFS[appFS] = true
        hooksecurefunc(appFS, "SetText", function(_, val)
            if IP.viewerFS ~= appFS then return end
            -- Pool recycling: this frame may now show another buff
            if IP.FrameSpellID(frame) ~= IP.SPELL then
                IP.viewerFrame = nil
                IP.viewerFS = nil
                IP.value = nil
                -- Recapture next text tick: the pool rebuild that recycled this
                -- frame has already re-homed the IP icon.
                IP.nextScan = 0
                return
            end
            -- Secrets pass through raw (SetText renders them); clean strings
            -- normalize to numbers.
            if issecretvalue and issecretvalue(val) then
                IP.value = val
            elseif type(val) == "number" then
                IP.value = val
            elseif type(val) == "string" then
                IP.value = tonumber(val)
            else
                IP.value = nil
            end
        end)
    end
    -- Seed from whatever the icon currently shows
    local ok, cur = pcall(appFS.GetText, appFS)
    if ok then
        if issecretvalue and issecretvalue(cur) then
            IP.value = cur
        elseif type(cur) == "string" then
            IP.value = tonumber(cur)
        end
    end
end

-- Scan BOTH Blizzard viewers for Ignore Pain. Tracked Buffs carry the stack
-- FontString at frame.Applications.Applications; Tracked Bars at
-- frame.Icon.Applications (same child the EUI CDM buff bars read). Whichever has
-- IP wins. force: rescan even with a capture held (used when the captured FS
-- went invisible, possibly stranded on a released pool frame); a forced scan
-- finding nothing leaves the current capture in place.
IP.ScanViewer = function(force)
    if IP.viewerFrame and not force then return end
    local function scanPool(viewer, resolve)
        if not viewer or not viewer.itemFramePool then return end
        for frame in viewer.itemFramePool:EnumerateActive() do
            if IP.FrameSpellID(frame) == IP.SPELL then
                local fs = resolve(frame)
                if fs then IP.HookViewerFS(frame, fs); return true end
                return
            end
        end
    end
    local hit = scanPool(_G.BuffIconCooldownViewer, function(f)
        return f.Applications and f.Applications.Applications
    end)
    -- Icon viewer wins; the bar viewer is only consulted when the icon scan
    -- captured nothing this pass (a held stale capture must not block it).
    if not hit and (not IP.viewerFrame or force) then
        scanPool(_G.BuffBarCooldownViewer, function(f)
            return f.Icon and f.Icon.Applications
        end)
    end
end

-- Lazy (re)scan for the Blizzard tracked-buff IP icon (2s throttle); also rescan
-- while the captured FS is invisible, since a viewer pool rebuild (tracked buffs
-- proccing/expiring, e.g. Thunder Blast) can strand the capture on a released
-- hidden frame that never fires SetText, while the icon lives on in another pool
-- frame -- otherwise text stays blank until the orphan happens to be reused. Driven
-- from MotionTick, not from UpdateText: the fill gate below reads the capture too,
-- so it has to stay current with the count text switched off.
IP.EnsureViewer = function()
    local staleFS = IP.viewerFS and not IP.viewerFS:IsVisible()
    if (not IP.viewerFrame or staleFS) and GetTime() >= IP.nextScan then
        IP.nextScan = GetTime() + 2
        IP.ScanViewer(staleFS)
    end
end

-- Is Ignore Pain up? Blizzard's tracked-buff icon is the authoritative answer -- it
-- survives a reload, a spec swap and a Violent Outburst refresh the cast handler
-- missed -- but it only exists while the user tracks IP in the CDM, so the
-- cast-driven window backs it up.
IP.Active = function()
    if IP.viewerFS and IP.viewerFS:IsVisible() then return true end
    return IP.hashEndTime > GetTime()
end

-- Per-frame stack text for the IP bar. Preferred source: the exact stack number
-- captured from Blizzard's tracked-buff icon above; fallback: rendered fill width
-- (fill/bar = percent of cap = stacks) when values read clean but the viewer is
-- unavailable. Change-detected; blank with no clean source, empty bar, or text off.
IP.UpdateText = function()
    if not (secondaryFrame and secondaryFrame._countText) then return end
    local sp = ERB.db.profile.secondary
    if not sp.showText then
        if IP.lastTextStacks then
            secondaryFrame._countText:SetText("")
            IP.lastTextStacks = nil
        end
        return
    end
    -- The captured viewer value is usually a SECRET number (type() says "number"
    -- and truthiness works, but comparisons/format error). SetText renders secret
    -- numbers natively -- exactly what Blizzard's own icon does with this value --
    -- so pass it UNTOUCHED: no clamp, no change-detection, no tostring.
    if issecretvalue and issecretvalue(IP.value) then
        if IP.viewerFS and IP.viewerFS:IsVisible() then
            secondaryFrame._countText:SetText(IP.value)
            IP.lastTextStacks = nil  -- secrets cannot be change-detected
        elseif IP.lastTextStacks ~= 0 then
            IP.lastTextStacks = 0
            secondaryFrame._countText:SetText("")
        end
        return
    end
    local stacks = 0
    if IP.value and IP.viewerFS and IP.viewerFS:IsVisible() then
        stacks = IP.value
        if stacks > 100 then stacks = 100 end
        if stacks < 0 then stacks = 0 end
    else
        local ft = secondaryBar.GetStatusBarTexture and secondaryBar:GetStatusBarTexture()
        if ft then
            local okW, fw = pcall(ft.GetWidth, ft)
            local okB, bw = pcall(secondaryBar.GetWidth, secondaryBar)
            if okW and okB and fw and bw
               and not (issecretvalue and (issecretvalue(fw) or issecretvalue(bw)))
               and bw > 0 then
                stacks = math.floor(fw / bw * 100 + 0.5)
                if stacks > 100 then stacks = 100 end
            end
        end
    end
    if stacks == IP.lastTextStacks then return end
    IP.lastTextStacks = stacks
    secondaryFrame._countText:SetText(stacks > 0 and tostring(stacks) or "")
end

local function UpdateSecondaryResource()
    -- Blizzard Class Resource Art stands in: the pips are unseen, paint nothing.
    if ns._erbArtOn then return end
    if not secondaryFrame or not secondaryFrame:IsShown() then return end
    if not cachedSecondary then return end

    local powerType = cachedSecondary.power
    local maxPts = cachedSecondary.max or 5

    if powerType == "IRONFUR_BAR" then
        UpdateIronfurBar()
        return
    end

    -- Value early-out for plain point resources (Holy Power, combo points, soul shards,
    -- chi, ...). Everything below is a pure function of value/max/config, and four
    -- triggers reach this per cast (UNIT_POWER_FREQUENT, UNIT_AURA,
    -- UNIT_SPELLCAST_SUCCEEDED, the 10fps safety poll), most firing with the resource
    -- unchanged (~300 hits/9 misses over 15s casting, profiled 12.2%->2.9%). The
    -- active tracked buff and the winning spender change while the value stands
    -- still, so both are part of the key (the buff is read here; the spender comes
    -- from the cache the spender pass keeps current). The charged-point set is not:
    -- UNIT_POWER_POINT_CHARGE drops the memo instead. Secret values bail out (not
    -- comparable); non-"points" resources never reach this branch. THE GUARD MUST
    -- COMPARE THE VALUE THE RENDER CONSUMES, not the whole-unit count: Destruction
    -- soul shards move in tenths and the partial-pip fill is driven by the fragment
    -- read, so guarding on the whole count would swallow every fragment change. The
    -- unmodified read is never less sensitive -- Affliction/Demonology step in whole
    -- shards. Essence is the other fractional resource and can't use this (UnitPower
    -- has no partial for it), hence its timer exemption below; any future fractional
    -- resource belongs HERE.
    -- The tracked buff this early-out reads is handed to the fill pass below (same
    -- entry, same call), so a redraw scans the buff viewers once, not twice.
    local _ebEntry, _ebR, _ebG, _ebB, _ebA
    if cachedSecondary.type == "points" then
        local _evCur
        if cachedSecondary.frac then
            _evCur = UnitPower("player", powerType, true)
            if _evCur == nil then _evCur = UnitPower("player", powerType) end
        elseif cachedSecondary.onTarget then
            -- WoW Forever: combo points belong to the target, and UnitPower still
            -- reports the previous target's count after a target swap.
            _evCur = GetComboPoints("player", "target") or 0
        else
            _evCur = UnitPower("player", powerType)
        end
        if not (issecretvalue and issecretvalue(_evCur)) then
            local tb, ts = ns.SecTracks()
            local bw, sw = 0, 0
            if tb then
                local i
                _ebEntry = ns.STK.entry
                _ebR, _ebG, _ebB, _ebA, i = ActiveBuffColor(_ebEntry)
                bw = i or 0
            end
            if ts then sw = ns.SpenderWinner() end
            local st = ns.SecSt
            -- Essence recharge exemption: the partial pip refills over several
            -- seconds while UnitPower reads the SAME count, so an in-flight
            -- recharge (_essenceNextTick set) must keep redrawing or this
            -- unchanged-value early-out freezes it.
            if st and st.cur == _evCur and st.max == maxPts and st.gen == ns.CfgGen
               and st.bw == bw and st.sw == sw and not _essenceNextTick then
                return
            end
            if not st then st = {}; ns.SecSt = st end
            st.cur, st.max, st.gen, st.bw, st.sw = _evCur, maxPts, ns.CfgGen, bw, sw
        end
    end

    local sp = _G._ERB_ResolveSecondaryCfg()
	if not sp then return end
    -- Per-spec threshold entry, resolved once per update
    local _tsEntry = ResolveThresholdSpecEntry(sp)
    local _buffEntry = _tsEntry
    -- Per-entry thresholdEnabled (absent field = true, for migrated entries)
    local _tsEnabled = _tsEntry and (_tsEntry.thresholdEnabled ~= false) or false
    local _tsBandOn, _tsBands, _tsBandMode, _tsBandReverse = ResolveBandConfig(sp, _tsEntry)
    if not _tsEnabled then _tsEntry = nil end
    local _tsThreshCount = _tsEntry and _tsEntry.thresholdCount or sp.thresholdCount
    -- Enhance Five Bar needs a threshold of at least 7 (5 pips + overflow). Clamp
    -- the value used this update, and persist a stale entry saved below 7 so it
    -- actually updates (Enhancement entry only).
    if powerType == "MAELSTROM_WEAPON" and sp.enhanceFiveBar and _tsEntry
       and _tsThreshCount and _tsThreshCount < 7 then
        _tsThreshCount = 7
        local _specIdx = GetSpecialization()
        local _specID = _specIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(_specIdx)
        if _specID and _tsEntry.specIDs then
            for _, sid in ipairs(_tsEntry.specIDs) do
                if sid == _specID then _tsEntry.thresholdCount = 7; break end
            end
        end
    end
    local _tsPartialOnly = _tsEntry and _tsEntry.thresholdPartialOnly
    if _tsPartialOnly == nil then _tsPartialOnly = sp.thresholdPartialOnly end
    -- Bar-type only: reverse so the threshold color shows below the value
    local _tsReverse = _tsEntry and _tsEntry.thresholdReverse
    if _tsReverse == nil then _tsReverse = sp.thresholdReverse end
    -- "Only color at/above threshold" (partial pip recolor) is "From"-only --
    -- meaningless under "Up to" (low count = no pips past the threshold), so the
    -- option is greyed there and ignored here.
    if _tsReverse then _tsPartialOnly = false end
    -- Per-entry threshold color (falls back to global sp.thresholdR/G/B/A)
    local _tsR = _tsEntry and _tsEntry.thresholdR or sp.thresholdR
    local _tsG = _tsEntry and _tsEntry.thresholdG or sp.thresholdG
    local _tsB = _tsEntry and _tsEntry.thresholdB or sp.thresholdB
    local _tsA = _tsEntry and _tsEntry.thresholdA or sp.thresholdA
    -- "Recolor text instead of bar": route the threshold/band color to the count
    -- text, fill/pips stay at base. Only when text is shown, else fall back to
    -- fill coloring so the threshold stays visible. Works for every clean
    -- (Lua-comparable) resource -- bar-type, runes, all pips -- except the two
    -- secret-value resources, Ignore Pain and Vengeance soul fragments.
    local _spTextInstead = _buffEntry and _buffEntry.thresholdTextInstead and sp.showText and powerType ~= "IGNOREPAIN_BAR"
    local _spTextBaseR, _spTextBaseG, _spTextBaseB = sp.textR or 1, sp.textG or 1, sp.textB or 1
    local r, g, b, a = 1, 1, 1, 1

    -- Color: dark theme > class colored > custom fill color
    if sp.darkTheme then
        r, g, b = EllesmereUI.GetDarkModeFill()
    elseif sp.resourceColored then
        -- Per-spec resource/power color; falls back to class color.
        local rr, rg, rb = ERB.ResolveSecondaryResourceColor(powerType)
        if rr then r, g, b = rr, rg, rb
        else
            local cc = CLASS_COLORS[cachedClass]
            if cc then r, g, b = cc[1], cc[2], cc[3] end
        end
        a = 1
    elseif sp.classColored ~= false then
        -- Power types in secondary slot use power color; class resources use class color
        local pc = POWER_COLORS[powerType]
        if pc then r, g, b = pc[1], pc[2], pc[3]
        else
            local cc = CLASS_COLORS[cachedClass]
            if cc then r, g, b = cc[1], cc[2], cc[3] end
        end
        a = 1
    else
        -- classColored explicitly false -- custom fill
        r, g, b, a = sp.fillR, sp.fillG, sp.fillB, 1
    end

    -- A tracked buff overrides the fill (buff wins over threshold). With "recolor
    -- text instead" on, the buff colors the count TEXT (done at the end of this
    -- function) and fill/pips stay at their base color.
    local _bfr, _bfg, _bfb, _bfa
    if _ebEntry ~= nil and _ebEntry == _buffEntry then
        _bfr, _bfg, _bfb, _bfa = _ebR, _ebG, _ebB, _ebA
    else
        _bfr, _bfg, _bfb, _bfa = ActiveBuffColor(_buffEntry)
    end
    -- No tracked buff active: a castable spender supplies the override color instead.
    if not _bfr then _bfr, _bfg, _bfb, _bfa = ns.ActiveSpenderColor(_buffEntry) end
    local _buffActive = _bfr ~= nil
    if _buffActive then
        if not _spTextInstead then
            r, g, b, a = _bfr or r, _bfg or g, _bfb or b, _bfa or a
        end
        _tsEntry = nil
        _tsBandOn = false
    end

    -- Points: read once. A secret can't survive the comparison-based points
    -- path, so it routes to the secret overlay renderer (custom branch).
    local _ptsCur, _ptsSecret
    if cachedSecondary.type == "points" then
        if cachedSecondary.onTarget then
            _ptsCur = GetComboPoints("player", "target") or 0
        else
            _ptsCur = UnitPower("player", powerType)
        end
        _ptsSecret = (issecretvalue and issecretvalue(_ptsCur)) and true or false
    end

    if cachedSecondary.type == "runes" then
        local now = GetTime()
        local readyN, cdN = 0, 0
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            _runeStart[i] = start
            _runeDuration[i] = duration
            if ready then
                _runeReady[i] = true
                _runeRemaining[i] = 0
                readyN = readyN + 1
                _runeOrder[readyN] = i
            else
                _runeReady[i] = false
                _runeRemaining[i] = (start and duration and duration > 0)
                    and max(0, start + duration - now) or 999
                cdN = cdN + 1
            end
        end

        -- Threshold: color ready runes differently when enough are available
        local runeUseThresh = _tsEntry and readyN >= _tsThreshCount
        local tr, tg, tb = _tsR, _tsG, _tsB
        -- Multi-band threshold
        if _tsBandOn then
            local band = FindCountBand(_tsBands, readyN, _tsBandReverse)
            if band then
                runeUseThresh = true
                tr, tg, tb = band.r, band.g, band.b
            else
                runeUseThresh = false
            end
        end
        local _runeTI = _spTextInstead and sp.runesSimple
        local _runeTiTrig = runeUseThresh and true or false
        if _runeTI then runeUseThresh = false end

        if sp.runesSimple then
            -- Simple mode: flat pips like Holy Power (active/inactive, no recharge animation)
            local numPips = 6
            local totalW = sp.pipWidth or 214
            local pipSp = sp.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)

            for i = 1, 6 do
                local rf = runeFrames[i]
                if rf and rf:IsShown() then
                    local slot = slots[i]
                    local x0 = slot.x0
                    local w  = slot.x1 - slot.x0
                    local pipOri = sp.pipOrientation or "HORIZONTAL"
                    rf:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, x0)
                        rf:SetHeight(w)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -x0)
                        rf:SetHeight(w)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", x0, 0)
                        rf:SetWidth(w)
                    end

                    local active = (i <= readyN)
                    if active and runeUseThresh then
                        if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                            rf:SetActive(true, r, g, b, a)
                        else
                            rf:SetActive(true, tr, tg, tb)
                        end
                    else
                        rf:SetActive(active, r, g, b, a)
                    end
                    if rf._rechargeBar then rf._rechargeBar:Hide() end
                    if rf._cdText then rf._cdText:SetText("") end
                end
            end

            -- Central count text (like other pip resources)
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(readyN))
                colorText(_runeTI, _runeTiTrig, tr, tg, tb, _spTextBaseR, _spTextBaseG, _spTextBaseB)
            end
        else
            -- Full rune mode: sort ready left, cooling right with recharge animation
            -- Clear central count text (used by simple mode)
            if secondaryFrame._countText then secondaryFrame._countText:SetText("") end
            -- Append cd runes after ready runes in _runeOrder
            local ci = readyN
            for i = 1, 6 do
                if not _runeReady[i] then
                    ci = ci + 1
                    _runeOrder[ci] = i
                end
            end
            -- Insertion-sort the cd portion (indices readyN+1..readyN+cdN) by
            -- remaining time. Max 6 elements so this is faster than table.sort
            -- and avoids creating a comparator closure each tick.
            for i = readyN + 2, readyN + cdN do
                local key = _runeOrder[i]
                local keyRem = _runeRemaining[key]
                local j = i - 1
                while j > readyN and _runeRemaining[_runeOrder[j]] > keyRem do
                    _runeOrder[j + 1] = _runeOrder[j]
                    j = j - 1
                end
                _runeOrder[j + 1] = key
            end
            local totalRunes = readyN + cdN

            -- Compute pixel-snapped pip geometry (spacing guaranteed >= 1 physical pixel)
            local numPips = 6
            local totalW = sp.pipWidth or 214
            local pipSp = sp.pipSpacing or 1
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame)

            for pos = 1, totalRunes do
                local runeIdx = _runeOrder[pos]
                local rf = runeFrames[runeIdx]
                if rf and rf:IsShown() then
                    local slot = slots[pos]
                    local x0 = slot.x0
                    local w  = slot.x1 - slot.x0
                    local pipOri = sp.pipOrientation or "HORIZONTAL"
                    rf:ClearAllPoints()
                    if pipOri == "VERTICAL_UP" then
                        rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, x0)
                        rf:SetHeight(w)
                    elseif pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL" then
                        rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -x0)
                        rf:SetHeight(w)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", x0, 0)
                        rf:SetWidth(w)
                    end

                    if _runeReady[runeIdx] then
                        -- Ready rune: full brightness + restore background, hide recharge overlay
                        rf._bg:SetAlpha(1)
                        if runeUseThresh then
                            if not _tsBandOn and _tsPartialOnly and pos < _tsThreshCount then
                                rf:SetActive(true, r, g, b, a)
                            else
                                rf:SetActive(true, tr, tg, tb)
                            end
                        else
                            rf:SetActive(true, r, g, b, a)
                        end
                        if rf._rechargeBar then rf._rechargeBar:Hide() end
                        if rf._cdText then rf._cdText:SetText("") end
                    else
                        -- Cooling-down rune: hide normal fill, show recharge bar.
                        -- The pip background is zeroed ONLY at full Fill
                        -- Opacity, where the frame-wide backdrop shows through
                        -- and carries the look. Below 100 that backdrop is
                        -- hidden by design and the composited per-pip bg
                        -- (PipBgColor: bar background under the overlay tint)
                        -- is the ONLY background a recharging rune has --
                        -- zeroing it left the un-recharged portion fully
                        -- transparent. SetActive(false) has just restored the
                        -- bg for the Fill Opacity case. Background on individual
                        -- pips stamps _fillOp = 1 for the same reason.
                        rf:SetActive(false, r, g, b, a)
                        if not rf._fillOp then rf._bg:SetAlpha(0) end

                        -- Lazily create a StatusBar overlay for recharge progress
                        if not rf._rechargeBar then
                            local sb = CreateFrame("StatusBar", nil, rf)
                            sb:SetAllPoints(rf)
                            sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                            sb:SetFrameLevel(rf:GetFrameLevel())
                            sb:SetMinMaxValues(0, 1)
                            -- Apply the same bar texture if one is set
                            if rf._texKey then
                                local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, rf._texKey, nil)
                                if path then sb:SetStatusBarTexture(path) end
                            end
                            rf._rechargeBar = sb
                            if rf._blizzMask then ns.ERB_MaskPip(rf, rf._blizzMask) end
                        end

                        -- Recharge fill follows the pip orientation: a lazily
                        -- created StatusBar defaults to HORIZONTAL and persists
                        -- across orientation swaps. Same direction convention
                        -- as ApplyBarOrientation (VERTICAL_DOWN = reverse =
                        -- fills from the top). Change-guarded on the full
                        -- orientation token (up/down differ only in reverse).
                        if rf._rechargeOri ~= pipOri then
                            local vertPip = pipOri ~= "HORIZONTAL"
                            rf._rechargeBar:SetOrientation(vertPip and "VERTICAL" or "HORIZONTAL")
                            rf._rechargeBar:SetRotatesTexture(vertPip)
                            rf._rechargeBar:SetReverseFill(
                                pipOri == "VERTICAL_DOWN" or pipOri == "VERTICAL")
                            rf._rechargeOri = pipOri
                        end

                        -- Compute recharge fraction (0 = just started, 1 = almost ready)
                        local frac = 0
                        local rStart, rDur = _runeStart[runeIdx], _runeDuration[runeIdx]
                        if rStart and rDur and rDur > 0 then
                            local elapsed = now - rStart
                            frac = max(0, min(1, elapsed / rDur))
                        end
                        rf._rechargeBar:SetValue(frac)
                        -- Recharge color: custom color when enabled, otherwise 75%
                        -- brightness (subtle dim), matching threshold color when active
                        if sp.runesCustomRecharge then
                            rf._rechargeBar:SetStatusBarColor(sp.runesRechargeR or 0.5, sp.runesRechargeG or 0.5, sp.runesRechargeB or 0.5, sp.runesRechargeA or 1)
                        elseif runeUseThresh then
                            rf._rechargeBar:SetStatusBarColor(tr * 0.75, tg * 0.75, tb * 0.75, a)
                        else
                            rf._rechargeBar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75, a)
                        end
                        rf._rechargeBar:Show()

                        -- Show duration text if Resource Text is enabled (DK runes use it for cooldown)
                        if rf._cdText then
                            local rem = _runeRemaining[runeIdx]
                            if sp.showText and rem > 0 and rem < 999 then
                                rf._cdText:SetText(format("%d", ceil(rem)))
                            else
                                rf._cdText:SetText("")
                            end
                        end
                    end
                end
            end
        end
    elseif cachedSecondary.type == "bar" then
        -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom, Brewmaster stagger)
        if secondaryBar then
            local cur, maxC = 0, maxPts
            if powerType == "SOUL_FRAGMENTS_DEVOURER" and EllesmereUI and EllesmereUI.GetSoulFragments then
                cur, maxC = EllesmereUI.GetSoulFragments()
                if not maxC or maxC <= 0 then maxC = maxPts end
            elseif powerType == "MAELSTROM_BAR" then
                cur = UnitPower("player", PT.MAELSTROM) or 0
                maxC = UnitPowerMax("player", PT.MAELSTROM) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "INSANITY_BAR" then
                cur = UnitPower("player", PT.INSANITY) or 0
                maxC = UnitPowerMax("player", PT.INSANITY) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "FOCUS_BAR" then
                cur = UnitPower("player", PT.FOCUS) or 0
                maxC = UnitPowerMax("player", PT.FOCUS) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "LUNAR_POWER_BAR" then
                cur = UnitPower("player", PT.LUNAR_POWER) or 0
                maxC = UnitPowerMax("player", PT.LUNAR_POWER) or maxPts
                if issecretvalue and issecretvalue(maxC) then maxC = maxPts end
                if maxC <= 0 then maxC = maxPts end
            elseif powerType == "BREWMASTER_STAGGER" then
                cur = UnitStagger("player") or 0
                maxC = UnitHealthMax("player") or 1
                local curTainted = issecretvalue and issecretvalue(cur)
                local maxTainted = issecretvalue and issecretvalue(maxC)
				-- stagger thresholds
                local staggerPct
                if not curTainted and not maxTainted and maxC > 0 then
                    staggerPct = cur / maxC * 100
                    secondaryBar._staggerPctCache = staggerPct
                else
                    -- Stagger / max health go SECRET intermittently in instanced
                    -- combat: reuse the last clean % so the threshold color PERSISTS
                    -- instead of flickering back to base fill, and re-applies even
                    -- if a rebuild reset the fill in that window.
                    staggerPct = secondaryBar._staggerPctCache
                end
                if _buffActive then
                    local _sft = secondaryBar:GetStatusBarTexture()
                    if _sft then
                        secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = r, g, b
                        _sft:SetVertexColor(r, g, b, a)
                    end
                elseif not sp.darkTheme and staggerPct then
                    local trig, tcr, tcg, tcb = false, r, g, b
                    if _tsBandOn then
                        local band = FindCountBand(_tsBands, staggerPct, _tsBandReverse)
                        if band then trig, tcr, tcg, tcb = true, band.r or r, band.g or g, band.b or b end
                    elseif _tsEntry then
                        local threshVal = _tsThreshCount or 30
                        local over
                        if _tsReverse then over = staggerPct <= threshVal else over = staggerPct >= threshVal end
                        if over then trig, tcr, tcg, tcb = true, _tsR or r, _tsG or g, _tsB or b end
                    else
                        trig = true
                        if staggerPct >= 60 then tcr, tcg, tcb = 1.0, 0.2, 0.2
                        elseif staggerPct >= 30 then tcr, tcg, tcb = 1.0, 0.85, 0.2
                        else tcr, tcg, tcb = 0.2, 0.8, 0.2 end
                    end
                    if _spTextInstead then
                        local lastR, lastG, lastB = secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB
                        if not secondaryBar._atlasFill and (lastR ~= r or lastG ~= g or lastB ~= b) then
                            secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = r, g, b
                            secondaryBar:GetStatusBarTexture():SetVertexColor(r, g, b, a)
                        end
                        colorText(true, trig, tcr, tcg, tcb, _spTextBaseR, _spTextBaseG, _spTextBaseB)
                    else
                        -- Fill = effective color (threshold/band or base), guarded.
                        local fr, fg, fb = r, g, b
                        if trig then fr, fg, fb = tcr, tcg, tcb end
                        local lastR, lastG, lastB = secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB
                        if not secondaryBar._atlasFill and (lastR ~= fr or lastG ~= fg or lastB ~= fb) then
                            secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = fr, fg, fb
                            secondaryBar:GetStatusBarTexture():SetVertexColor(fr, fg, fb, 1)
                        end
                    end
                end
                if maxTainted then maxC = maxPts end
                if not maxTainted and maxC <= 0 then maxC = 1 end
            elseif powerType == "IGNOREPAIN_BAR" then
                -- Prot Ignore Pain. Preferred: the tracked-buff icon's stack count --
                -- IP caps at 30% max health, so 0-100 stacks are percent-of-cap, i.e.
                -- IP's own share with no foreign shield mixed in. It exists only while
                -- the user tracks IP in the CDM, so UnitGetTotalAbsorbs stays as the
                -- fallback: EVERY shield on the player, and secret, so IP cannot be
                -- subtracted out -- gated on IP being up, still over-reads in uptime.
                -- 190456 is restriction-flagged and GetPlayerAuraBySpellID returns
                -- NOTHING for it (field-probed): aura points are not an exact source.
                maxC = UnitHealthMax("player")
                if (issecretvalue and issecretvalue(maxC)) or not maxC or maxC <= 0 then
                    maxC = maxPts
                else
                    maxC = maxC * IP.CAP
                end
                if IP.value and IP.viewerFS and IP.viewerFS:IsVisible() then
                    -- Kept for the value-mode threshold rescale below.
                    IP.stackAxis = maxC
                    cur, maxC = IP.value, 100
                else
                    IP.stackAxis = nil
                    cur = IP.Active() and (UnitGetTotalAbsorbs("player") or 0) or 0
                end
            end
            -- Brewmaster stagger ceiling
            local barMax = maxC
            if powerType == "BREWMASTER_STAGGER" then
                local ceil = sp.staggerCeilingPercent or 100
                if ceil < 1 then ceil = 1 end
                barMax = maxC * ceil / 100
            end
            -- Only call SetMinMaxValues if max actually changed (prevents flicker)
            local maxChanged = secondaryBar._lastMaxC ~= barMax
            if maxChanged then
                secondaryBar._lastMaxC = barMax
                secondaryBar:SetMinMaxValues(0, barMax)
            end
            -- Reapply hash positions on a max change or the first valid layout
            -- (bar width can be 0 at BuildBars time, before layout settles).
            local barW = secondaryBar:GetWidth()
            if barW > 0 and (maxChanged or not secondaryBar._hashApplied) and powerType ~= "IGNOREPAIN_BAR" then
                secondaryBar._hashApplied = true
                local _rtTsEntry = ResolveThresholdSpecEntry(sp)
                local _rtTickStr = (_rtTsEntry and _rtTsEntry.hashValues ~= "") and _rtTsEntry.hashValues or sp.tickValues
                local _rtHW = _rtTsEntry and _rtTsEntry.hashWidth or 1
                local _rtHR = _rtTsEntry and _rtTsEntry.hashColorR or 1
                local _rtHG = _rtTsEntry and _rtTsEntry.hashColorG or 1
                local _rtHB = _rtTsEntry and _rtTsEntry.hashColorB or 1
                local _rtHA = _rtTsEntry and _rtTsEntry.hashColorA or 0.7
                local _rtHPct = _rtTsEntry and _rtTsEntry.hashMode == "percent"
                -- Devourer in Void Meta: hide any hash above 39.
                local _rtHashCap = (powerType == "SOUL_FRAGMENTS_DEVOURER"
                    and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1217607)) and 39 or nil
                ApplyResourceBarTicks(secondaryBar, barMax, _rtTickStr, secondaryBarTicks, _rtHW, _rtHR, _rtHG, _rtHB, _rtHA, _rtHPct, _rtHashCap)
            end
            -- Fill color (dark theme / class colored / custom). Brewmaster stagger
            -- uses threshold colors unless darkTheme is on. Bar-type resources
            -- (Maelstrom, Insanity) trigger at/above thresholdCount as a percent.
            if powerType ~= "BREWMASTER_STAGGER" or sp.darkTheme then
                local ft = secondaryBar:GetStatusBarTexture()
                -- An active atlas fill is NEVER tinted: route every fill
                -- SetVertexColor below into the no-op sink. Text recoloring still
                -- runs; Ignore Pain / Devourer / Stagger can never be atlased.
                if ft and secondaryBar._atlasFill then ft = ns._atlasNoTint end
                if ft then
                    -- Hide Ignore Pain band/threshold overlays by default; the IP
                    -- branch below re-shows exactly the layers it needs.
                    if secondaryBar._ipBandBars then
                        for _i = 1, #secondaryBar._ipBandBars do secondaryBar._ipBandBars[_i]:Hide() end
                    end
                    local pType = (powerType == "MAELSTROM_BAR") and PT.MAELSTROM
                               or (powerType == "INSANITY_BAR") and PT.INSANITY
                               or (powerType == "FOCUS_BAR") and PT.FOCUS
                               or (powerType == "LUNAR_POWER_BAR") and PT.LUNAR_POWER
                               or nil
                    if (_tsEntry or _tsBandOn) and pType and UnitPowerPercent then
                        -- ColorCurve + UnitPowerPercent: WoW evaluates the secret
                        -- value against the curve C-side. Default = threshold color
                        -- above value, fill below (builders warn when high);
                        -- thresholdReverse flips it for spenders (e.g. Hunter Focus)
                        -- that warn when low.
                        local curve
                        local _bandOn, _bands, _bandMode, _bandRev = _tsBandOn, _tsBands, _tsBandMode, _tsBandReverse
                        local _tsThreshPct = _tsThreshCount or 30
                        if _tsEntry and _tsEntry.thresholdMode == "value" and maxC and maxC > 0 then
                            _tsThreshPct = math.min(100, (_tsThreshCount or 30) / maxC * 100)
                        end
                        local rvR, rvG, rvB = r, g, b
                        if _spTextInstead then rvR, rvG, rvB = _spTextBaseR, _spTextBaseG, _spTextBaseB end
                        if _bandOn then
                            curve = GetBarBandCurve("secondary", _bands, _bandMode, maxC, rvR, rvG, rvB, _bandRev)
                        elseif _tsReverse then
                            curve = GetBarThresholdCurve(
                                rvR, rvG, rvB,                          -- fill/text color (above)
                                _tsR or 1, _tsG or 0.2, _tsB or 0.2,   -- threshold color (below)
                                _tsThreshPct)
                        else
                            curve = GetBarThresholdCurve(
                                _tsR or 1, _tsG or 0.2, _tsB or 0.2,   -- threshold color (above)
                                rvR, rvG, rvB,                          -- fill/text color (below)
                                _tsThreshPct)
                        end
                        if _spTextInstead then
                            -- Fill stays at base; the count text carries the curve's
                            -- color (already threshold-above / text-base-below).
                            ft:SetVertexColor(r, g, b, a)
                            if curve then
                                local ok, colorResult = pcall(UnitPowerPercent, "player", pType, false, curve)
                                if ok and colorResult and colorResult.GetRGBA then
                                    local cr, cg, cb = colorResult:GetRGBA()
                                    colorText(true, true, cr, cg, cb)
                                end
                            end
                        elseif curve then
                            local ok, colorResult = pcall(UnitPowerPercent, "player", pType, false, curve)
                            if ok and colorResult and colorResult.GetRGBA then
                                ft:SetVertexColor(colorResult:GetRGBA())
                            else
                                ft:SetVertexColor(r, g, b, a)
                            end
                        else
                            ft:SetVertexColor(r, g, b, a)
                        end
                    elseif _tsEntry and powerType == "SOUL_FRAGMENTS_DEVOURER" then
                        local threshVal = _tsThreshCount or 30
                        if _tsEntry.thresholdMode ~= "value" and maxC and maxC > 0 then
                            threshVal = maxC * threshVal / 100
                        end
                        if _spTextInstead then
                            -- Fill at base; tint the count text when at/over the threshold.
                            ft:SetVertexColor(r, g, b, a)
                            colorText(true, cur >= threshVal, _tsR or 1, _tsG or 0.2, _tsB or 0.2, _spTextBaseR, _spTextBaseG, _spTextBaseB)
                        elseif cur >= threshVal then
                            ft:SetVertexColor(_tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                        else
                            ft:SetVertexColor(r, g, b, a)
                        end
                    elseif powerType == "IGNOREPAIN_BAR" and (_tsEntry or _tsBandOn) and maxC and maxC > 0 then
                        -- Ignore Pain is a bar but not a real power type and its
                        -- absorb value is secret in combat, so use the secret-safe
                        -- StatusBar-overlay technique (as Vengeance pips): the fill
                        -- texture is the "cell", each overlay repaints the visible fill.
                        local function _ipBound(to)
                            if _tsBandMode ~= "value" then return maxC * (to or 0) / 100 end
                            -- A value-mode bound is an absorb amount. On the stack axis
                            -- maxC is 0-100, so rescale it against the absorb-scale cap
                            -- (both clean: user config and max health).
                            if IP.stackAxis and IP.stackAxis > 0 then
                                return (to or 0) / IP.stackAxis * 100
                            end
                            return to or 0
                        end
                        IP.layerN = 0
                        if _tsBandOn and _tsBands and #_tsBands > 0 then
                            if _tsBandReverse then
                                -- "From"
                                IP.push(0, r, g, b, a)
                                for k = 1, #_tsBands do
                                    local bd = _tsBands[k]
                                    IP.push(_ipBound(bd.to), bd.r or 1, bd.g or 1, bd.b or 1, bd.a or a)
                                end
                            else
                                -- "Up to"
                                local b1 = _tsBands[1]
                                IP.push(0, b1.r or 1, b1.g or 1, b1.b or 1, b1.a or a)
                                for k = 1, #_tsBands - 1 do
                                    local nb = _tsBands[k + 1]
                                    IP.push(_ipBound(_tsBands[k].to), nb.r or 1, nb.g or 1, nb.b or 1, nb.a or a)
                                end
                                IP.push(_ipBound(_tsBands[#_tsBands].to), r, g, b, a)
                            end
                        elseif _tsEntry and _tsEntry.thresholdEnabled ~= false and _tsThreshCount then
                            local tv = (_tsEntry.thresholdMode == "value") and _tsThreshCount or (maxC * _tsThreshCount / 100)
                            if _tsReverse then
                                -- threshold color below the value, base fill at/above.
                                IP.push(0, _tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                                IP.push(tv, r, g, b, a)
                            else
                                -- base fill below, threshold color at/above.
                                IP.push(0, r, g, b, a)
                                IP.push(tv, _tsR or 1, _tsG or 0.2, _tsB or 0.2, _tsA or 1)
                            end
                        else
                            IP.push(0, r, g, b, a)
                        end
                        -- Base layer paints the bar's own fill.
                        local _base = IP.layers[1]
                        ft:SetVertexColor(_base.r, _base.g, _base.b, _base.a)
                        local bars = secondaryBar._ipBandBars
                        if not bars then bars = {}; secondaryBar._ipBandBars = bars end
                        local host = secondaryBar._sb or secondaryBar
                        local texKey = ERB.db and ERB.db.profile and ERB.db.profile.general and ERB.db.profile.general.barTexture or "none"
                        local texPath = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
                        local shown = 0
                        for li = 2, IP.layerN do
                            local L = IP.layers[li]
                            if L.step and L.step > 0 then
                                shown = shown + 1
                                local ob = bars[shown]
                                if not ob then
                                    ob = CreateFrame("StatusBar", nil, host)
                                    -- Anchors are constant to the fill texture; set once.
                                    ob:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0)
                                    ob:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 1, 0)
                                    bars[shown] = ob
                                end
                                -- Texture/level change on config/rebuild, not per tick.
                                if ob._texPath ~= texPath then
                                    ob:SetStatusBarTexture(texPath)
                                    local _obt = ob:GetStatusBarTexture()
                                    if _obt then _obt:SetSnapToPixelGrid(false); _obt:SetTexelSnappingBias(0) end
                                    ob._texPath = texPath
                                    -- Blizzard Style: the layer rides the row's bar-shape mask
                                    -- (the bevel overlay sits above it by level).
                                    local rm = secondaryFrame and secondaryFrame._blizzBarMask
                                    if rm and _obt then ns.ERB_MaskTex(_obt, rm) end
                                end
                                local _lvl = host:GetFrameLevel() + shown
                                if ob._lvl ~= _lvl then ob:SetFrameLevel(_lvl); ob._lvl = _lvl end
                                ob:SetMinMaxValues(L.step * 0.999, L.step)
                                ob:SetValue(cur)
                                ob:SetStatusBarColor(L.r, L.g, L.b, L.a)
                                ob:Show()
                            end
                        end
                    else
                        ft:SetVertexColor(r, g, b, a)
                    end
                end
            end
            -- Fill: eased only while the bar's Smooth Bars item is on (see the
            -- health handler note); a secret goes straight to the StatusBar too.
            secondaryBar:SetValue(cur)
            local tainted = issecretvalue and issecretvalue(cur)
            if sp.showText and secondaryFrame._countText then
                local ct = secondaryFrame._countText
                local percentSuffix = (sp.showPercent == false) and "" or "%"
                -- Power-based bar resources treat "Show %" as a value<->percent
                -- switch: OFF (default) = bare current value, ON = percent
                -- (secret-safe via the ScaleTo100 declassifier, capped 0-100 by
                -- nature). Mode is identical in/out of instanced combat -- display
                -- must never flip with taint state. All modes use SetFormattedText,
                -- which renders a secret value's digits engine-side, so no Lua
                -- compare/concat ever touches the secret.
                local pType = (powerType == "MAELSTROM_BAR") and PT.MAELSTROM
                           or (powerType == "INSANITY_BAR") and PT.INSANITY
                           or (powerType == "FOCUS_BAR") and PT.FOCUS
                           or (powerType == "LUNAR_POWER_BAR") and PT.LUNAR_POWER
                           or nil
                if powerType == "BREWMASTER_STAGGER" then
                    -- Stagger always shows a percentage of max health; "Show %"
                    -- only toggles the "%" sign here.
                    if not tainted then
                        local pct = maxC > 0 and (cur / maxC * 100) or 0
                        ct:SetText(format("%d", pct) .. percentSuffix)
                    else
                        local cp = secondaryBar._staggerPctCache
                        if cp then ct:SetText(format("%d", cp) .. percentSuffix) else ct:SetText("") end
                    end
                elseif powerType == "IGNOREPAIN_BAR" then
                    -- Text is driven per-frame by IP.UpdateText. No-op here.
                elseif pType and sp.showPercent and UnitPowerPercent then
                    -- Percent
                    local pct = UnitPowerPercent("player", pType, true, CurveConstants and CurveConstants.ScaleTo100) or 0
                    ct:SetFormattedText("%d%%", pct)
                elseif pType then
                    -- Value: bare current for the power bars (no "/ max").
                    ct:SetFormattedText("%s", cur)
                elseif sp.showMaxStacks == false then
                    -- Current count only (Devourer "Show Max Stacks" off).
                    ct:SetFormattedText("%s", cur)
                else
                    -- Current / max (Devourer default). SetFormattedText renders the
                    -- possibly-secret current alongside the clean max -- never a Lua
                    -- concat of a secret value.
                    ct:SetFormattedText("%s / %s", cur, maxC)
                end
            end
        end
    elseif cachedSecondary.type == "custom" or _ptsSecret then
        local cur, maxC = 0, maxPts
        local isSecret = false
        local _wcEngine = false
        if _ptsSecret then
            cur = _ptsCur
            maxC = maxPts
            isSecret = true
        elseif powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            -- Vengeance DH: GetSpellCastCount returns a SECRET value, uncomparable
            -- in Lua. Pass the raw value to StatusBar widgets embedded in each pip
            -- (SetMinMaxValues(i-1, i) + SetValue(secret)) which fill C-side.
            local rawCur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
            cur = rawCur
            isSecret = true
            maxC = 6
        elseif powerType == "SOUL_FRAGMENTS" and EllesmereUI and EllesmereUI.GetSoulFragments then
            cur, maxC = EllesmereUI.GetSoulFragments()
            if not maxC or maxC <= 0 then maxC = maxPts end
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            cur, maxC = EllesmereUI.GetMaelstromWeapon()
            -- Enhance 5-bar mode: clamp visual to 5 pips
            if sp.enhanceFiveBar and maxC > 5 then maxC = 5 end
        elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
            cur, maxC = EllesmereUI.GetTipOfTheSpear()
        elseif powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES" then
            -- Engine slot owns the display (EllesmereUI_WarriorCharges): the
            -- true count fills the overlay bar C-side. Fall through the shared
            -- color chain below so the fill inherits the exact resolved color;
            -- the handoff before the render paths does the rest. Until the
            -- deferred build lands the row simply shows empty (the cast-count
            -- simulator is retired).
            -- BuildBars still lays the legacy gap-fill strips from the OLD pip
            -- grid (cumulative cell+gap pixels); the engine bar's separator
            -- ticks follow the fill's uniform fractions, so live strips
            -- double-line against them, drifting apart along the bar (worst
            -- with a wide Bar Spacing). These two powers never render pips,
            -- so the strips are never wanted; hide once when present.
            local gf = secondaryFrame._gapFills
            if gf and gf[1] and gf[1]:IsShown() then
                for gi = 1, #gf do gf[gi]:Hide() end
            end
            if ns.WC_EngineOn and ns.WC_EngineOn(powerType) then
                _wcEngine = true
            else
                for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
                return
            end
        elseif powerType == "ICICLES" then
            cur = GetIcicleCount()
            maxC = 5
        end
        -- For pips using class/resource color, prefer the per-spec resource color.
        -- skip only when the buff colors the fill
        if not (_buffActive and not _spTextInstead) then
            if sp.resourceColored and not sp.darkTheme then
                local rr, rg, rb = ERB.ResolveSecondaryResourceColor(powerType)
                if rr then r, g, b = rr, rg, rb end
            elseif sp.classColored ~= false and not sp.darkTheme then
                local pc2 = POWER_COLORS[powerType]
                if pc2 then
                    r, g, b = pc2[1], pc2[2], pc2[3]
                elseif EllesmereUI and EllesmereUI.GetResourceColor then
                    local _, classFile = UnitClass("player")
                    local rc = EllesmereUI.GetResourceColor(classFile)
                    if rc then r, g, b = rc.r, rc.g, rc.b end
                end
            end
        end

        -- Warrior charge powers: hand the module the fully resolved color on
        -- EVERY pass, engine-owned or not. Pre-build passes stash it, so the
        -- creation-window bake paints the painter's exact color -- under
        -- restriction that window is the ONLY legal color write into the slot
        -- subtree. Engine-owned passes then park the legacy pips and legacy
        -- count text (the engine slot carries its own) and stop before any
        -- value read.
        if ns.WC_Recolor and (powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES") then
            ns.WC_Recolor(powerType, r, g, b, a)
            -- Threshold/band settings ride along raw (already resolved above
            -- at this pass's existing cost); the engine module change-gates
            -- and renders them as fill-masked range strips -- no Lua count
            -- exists for these two powers, so this is the only threshold
            -- renderer they have.
            if ns.WC_Thresholds then
                ns.WC_Thresholds(powerType,
                    (_tsEntry and _tsEntry.thresholdMode) or sp.thresholdMode,
                    _tsEntry and _tsThreshCount or nil, _tsR, _tsG, _tsB, _tsA,
                    _tsBandOn, _tsBands, _tsBandReverse, _tsReverse)
            end
        end
        if _wcEngine then
            for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
            if secondaryFrame._countText then secondaryFrame._countText:SetText("") end
            return
        end
        if isSecret then
            -- Secret-value path: each pip is driven by a StatusBar overlay, which
            -- accepts the secret number natively -- a value inside [i-1, i] fills
            -- proportionally, giving a binary active/inactive look for integer
            -- counts. Threshold coloring adds a second overlay per pip.
            local _useThresh = _tsEntry and _tsThreshCount and _tsThreshCount > 0
            -- Multi-band: precompute each band's start count. A band overlay fills
            -- pip i when cur >= max(i, start_k); higher bands sit on higher frame
            -- levels so the topmost filled band wins.
            local _bandStarts
            if _tsBandOn and _tsBands then
                _bandStarts = {}
                if _tsBandReverse then
                    for k = 1, #_tsBands do
                        _bandStarts[k] = (_tsBands[k].to or 0)
                    end
                else
                    local prev = 0
                    for k = 1, #_tsBands do
                        _bandStarts[k] = prev + 1
                        prev = _tsBands[k].to or prev
                    end
                end
            end
            for i = 1, maxC do
                local pip = pips[i]
                if pip and pip:IsShown() then
                    -- Lazily create a StatusBar overlay inside the pip
                    local texKey = ERB.db and ERB.db.profile and ERB.db.profile.general and ERB.db.profile.general.barTexture or "none"
                    local texPath = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
                    if not pip._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pip)
                        sb:SetAllPoints(pip._fill)
                        sb:SetStatusBarTexture(texPath)
                        sb._texPath = texPath
                        sb:SetStatusBarColor(r, g, b, a)
                        sb:SetFrameLevel(pip:GetFrameLevel())
                        pip._secretBar = sb
                        if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                    elseif pip._secretBar._texPath ~= texPath then
                        -- A path swap mints a brand-new inner texture and runs the
                        -- parent's pixel-snap hook: NEVER re-set the current path.
                        pip._secretBar:SetStatusBarTexture(texPath)
                        pip._secretBar._texPath = texPath
                        if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                    end
                    pip._secretBar:SetMinMaxValues(i - 1, i)
                    pip._secretBar:SetValue(cur)
                    pip._secretBar:SetStatusBarColor(r, g, b, a)
                    pip._secretBar:Show()

                    if _tsBandOn and _bandStarts then
                        -- Multi-band overlays: one StatusBar per band, higher bands
                        -- on top -> the topmost reached band colors the whole bar.
                        if not pip._bandBars then pip._bandBars = {} end
                        for k = 1, #_tsBands do
                            local bb = pip._bandBars[k]
                            if not bb then
                                bb = CreateFrame("StatusBar", nil, pip)
                                bb:SetAllPoints(pip._fill)
                                pip._bandBars[k] = bb
                            end
                            -- Texture/level change on config or rebuild, not per
                            -- tick: re-apply only on a real difference, or the hot
                            -- loop fires pips x bands redundant calls.
                            if bb._texPath ~= texPath then
                                bb:SetStatusBarTexture(texPath); bb._texPath = texPath
                                if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                            end
                            local _lvl = pip:GetFrameLevel() + k
                            if bb._lvl ~= _lvl then
                                bb:SetFrameLevel(_lvl); bb._lvl = _lvl
                            end
                            local lo = (i > _bandStarts[k]) and i or _bandStarts[k]
                            bb:SetMinMaxValues(lo - 1, lo)
                            bb:SetValue(cur)
                            local band = _tsBands[k]
                            bb:SetStatusBarColor(band.r or 1, band.g or 1, band.b or 1, a)
                            bb:Show()
                        end
                        for k = #_tsBands + 1, #pip._bandBars do pip._bandBars[k]:Hide() end
                        if not _tsBandReverse then
                            -- "Up to" semantics: above the top band, revert to the base
                            -- fill color. A topmost overlay fills when cur > top band's `to`.
                            local _topTo = _tsBands[#_tsBands] and _tsBands[#_tsBands].to or 0
                            if not pip._bandResetBar then
                                local rb = CreateFrame("StatusBar", nil, pip)
                                rb:SetAllPoints(pip._fill)
                                pip._bandResetBar = rb
                            end
                            if pip._bandResetBar._texPath ~= texPath then
                                pip._bandResetBar:SetStatusBarTexture(texPath)
                                pip._bandResetBar._texPath = texPath
                                if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                            end
                            pip._bandResetBar:SetFrameLevel(pip:GetFrameLevel() + #_tsBands + 1)
                            local _rlo = (i > (_topTo + 1)) and i or (_topTo + 1)
                            pip._bandResetBar:SetMinMaxValues(_rlo - 1, _rlo)
                            pip._bandResetBar:SetValue(cur)
                            pip._bandResetBar:SetStatusBarColor(r, g, b, a)
                            pip._bandResetBar:Show()
                        elseif pip._bandResetBar then
                            -- "From" semantics: base fill below the first boundary is
                            -- handled by the base _secretBar; no reset overlay needed.
                            pip._bandResetBar:Hide()
                        end
                        if pip._secretThreshBar then pip._secretThreshBar:Hide() end
                    else
                        if pip._bandResetBar then pip._bandResetBar:Hide() end
                        if pip._bandBars then
                            for k = 1, #pip._bandBars do pip._bandBars[k]:Hide() end
                        end
                        -- Threshold overlay (drawn on top of the base fill)
                        -- Partial-only: pips below the threshold index never recolor.
                        local showThresh = _useThresh and not (_tsPartialOnly and i < _tsThreshCount)
                        if showThresh then
                            if not pip._secretThreshBar then
                                local tb = CreateFrame("StatusBar", nil, pip)
                                tb:SetAllPoints(pip._fill)
                                tb:SetStatusBarTexture(texPath)
                                tb._texPath = texPath
                                tb:SetFrameLevel(pip:GetFrameLevel() + 1)
                                pip._secretThreshBar = tb
                                if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                            elseif pip._secretThreshBar._texPath ~= texPath then
                                pip._secretThreshBar:SetStatusBarTexture(texPath)
                                pip._secretThreshBar._texPath = texPath
                                if pip._blizzMask then ns.ERB_MaskPip(pip, pip._blizzMask) end
                            end
                            -- Fills only when cur >= max(i, threshCount): the pip is
                            -- active AND the threshold has been reached.
                            local tlo = (i > _tsThreshCount) and i or _tsThreshCount
                            pip._secretThreshBar:SetMinMaxValues(tlo - 1, tlo)
                            pip._secretThreshBar:SetValue(cur)
                            pip._secretThreshBar:SetStatusBarColor(_tsR or 1, _tsG or 0.2, _tsB or 0.2, a)
                            pip._secretThreshBar:Show()
                        elseif pip._secretThreshBar then
                            pip._secretThreshBar:Hide()
                        end
                    end

                    -- Hide the normal fill; the StatusBar replaces it
                    pip._fill:Hide()

                    -- Fill Opacity in secret contexts, same look as the clean path:
                    -- region alpha on the overlay fills + bg anchored to the base
                    -- fill's moving edge so it covers only the empty remainder,
                    -- never reading the secret value. _fillOp is nil at 100.
                    -- Factor 1 (Background on individual pips) keeps the
                    -- colour alpha each SetStatusBarColor above wrote.
                    if pip._fillOp then
                        local _fo = pip._fillOp < 1 and pip._fillOp
                        local _sft = pip._secretBar:GetStatusBarTexture()
                        if _sft then
                            if _fo then _sft:SetAlpha(_fo) end
                            if not pip._sbgAnchored then
                                pip._sbgAnchored = true
                                pip._bg:ClearAllPoints()
                                pip._bg:SetPoint("TOPLEFT", _sft, "TOPRIGHT", 0, 0)
                                pip._bg:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 0, 0)
                                pip._bg:SetAlpha(1)
                            end
                        end
                        local _stb = pip._secretThreshBar
                        if _fo and _stb and _stb:IsShown() then
                            local t = _stb:GetStatusBarTexture()
                            if t then t:SetAlpha(_fo) end
                        end
                        local _srb = pip._bandResetBar
                        if _fo and _srb and _srb:IsShown() then
                            local t = _srb:GetStatusBarTexture()
                            if t then t:SetAlpha(_fo) end
                        end
                        if _fo and pip._bandBars then
                            for k = 1, #pip._bandBars do
                                local bb = pip._bandBars[k]
                                if bb:IsShown() then
                                    local t = bb:GetStatusBarTexture()
                                    if t then t:SetAlpha(_fo) end
                                end
                            end
                        end
                    end
                end
            end
            -- Count text: derive from UnitPowerPercent when it reads clean
            -- (raw secrets don't reliably render); else pass the raw value.
            if sp.showText and secondaryFrame._countText then
                local shown = cur
                if type(powerType) == "number" and UnitPowerPercent and maxC and maxC > 0 then
                    local pct = UnitPowerPercent("player", powerType, true, CurveConstants and CurveConstants.ScaleTo100)
                    if pct and not (issecretvalue and issecretvalue(pct)) then
                        shown = math.floor(pct * maxC / 100 + 0.5)
                    end
                end
                secondaryFrame._countText:SetText(shown)
            end
        else
            -- Clean-value path: normal boolean comparisons
            -- Hide any leftover secret StatusBar overlays
            for i = 1, maxC do
                local p = pips[i]
                if p then
                    if p._secretBar then p._secretBar:Hide() end
                    if p._secretThreshBar then p._secretThreshBar:Hide() end
                    if p._bandResetBar then p._bandResetBar:Hide() end
                    if p._bandBars then for k = 1, #p._bandBars do p._bandBars[k]:Hide() end end
                    -- Leaving a secret Fill Opacity pass: restore the full-pip
                    -- bg anchor (SetActive owns bg visibility from here).
                    if p._sbgAnchored then
                        p._sbgAnchored = nil
                        p._bg:ClearAllPoints()
                        p._bg:SetAllPoints(p)
                    end
                end
            end
            -- Enhance 5-bar overflow: stacks 6-10 recolor pips 1-5
            local _enhFive = sp.enhanceFiveBar and powerType == "MAELSTROM_WEAPON"
            local _enhOverflow = _enhFive and cur > 5
            local _enhOverCount = _enhOverflow and (cur - 5) or 0
            local _enhRealCur = cur  -- preserve for count text
            local _enhOR, _enhOG, _enhOB = sp.enhanceOverflowR or 1, sp.enhanceOverflowG or 0.6, sp.enhanceOverflowB or 0.2
            if _enhOverflow then cur = 5 end  -- all 5 pips active when overflowing

            -- Direction: "From" (>=, default) or "Up to" (<=, thresholdReverse).
            local useThresh = _tsEntry and ((_tsReverse and cur <= _tsThreshCount)
                or ((not _tsReverse) and (cur >= _tsThreshCount or _enhRealCur >= _tsThreshCount)))
            local tr, tg, tb = _tsR, _tsG, _tsB
            -- Multi-band: whole bar takes the color of the band containing `cur`.
            if _tsBandOn and not _enhFive then
                local band = FindCountBand(_tsBands, cur, _tsBandReverse)
                if band then
                    useThresh = true
                    tr, tg, tb = band.r, band.g, band.b
                else
                    useThresh = false
                end
            end
            -- "Recolor text instead of bar": keep pips at base, route to the text.
            local _tiTrig = useThresh and true or false
            if _spTextInstead then useThresh = false end
            for i = 1, maxC do
                if pips[i] and pips[i]:IsShown() then
                    local active = i <= cur
					-- if no threshold just use enhfive color
                    if active and _enhOverflow and i <= _enhOverCount and not useThresh then
                        pips[i]:SetActive(true, _enhOR, _enhOG, _enhOB)
					elseif active and _enhOverflow and i <= _enhOverCount and useThresh then
						-- if partial, make count 5 based
						if _tsPartialOnly and i < (_tsThreshCount - cur) then
							pips[i]:SetActive(true, _enhOR, _enhOG, _enhOB)
                        else
                            pips[i]:SetActive(true, tr, tg, tb)
                        end
                    elseif active and useThresh then
                        if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                            pips[i]:SetActive(true, r, g, b, a)
                        else
                            pips[i]:SetActive(true, tr, tg, tb)
                        end
                    else
                        pips[i]:SetActive(active, r, g, b, a)
                    end
                end
            end
            -- Count text (use real count, not clamped)
            if sp.showText and secondaryFrame._countText then
                secondaryFrame._countText:SetText(tostring(_enhRealCur or cur))
                colorText(_spTextInstead, _tiTrig, tr, tg, tb, _spTextBaseR, _spTextBaseG, _spTextBaseB)
            end
        end
    else
        local cur = _ptsCur or UnitPower("player", powerType)
        -- Hide any secret StatusBar overlays left from a combat update that
        -- routed through the secret pip renderer above.
        for i = 1, maxPts do
            local p = pips[i]
            if p then
                if p._secretBar then p._secretBar:Hide() end
                if p._secretThreshBar then p._secretThreshBar:Hide() end
                if p._bandResetBar then p._bandResetBar:Hide() end
                if p._bandBars then for k = 1, #p._bandBars do p._bandBars[k]:Hide() end end
                -- Leaving a secret Fill Opacity pass: restore the full-pip
                -- bg anchor (SetActive owns bg visibility from here).
                if p._sbgAnchored then
                    p._sbgAnchored = nil
                    p._bg:ClearAllPoints()
                    p._bg:SetAllPoints(p)
                end
            end
        end
        -- Direction: "From" (>=, default) or "Up to" (<=, thresholdReverse).
        local useThresh = _tsEntry and ((_tsReverse and cur <= _tsThreshCount)
            or ((not _tsReverse) and cur >= _tsThreshCount))
        local tr, tg, tb = _tsR, _tsG, _tsB
        -- Multi-band
        if _tsBandOn then
            local band = FindCountBand(_tsBands, cur, _tsBandReverse)
            if band then
                useThresh = true
                tr, tg, tb = band.r, band.g, band.b
            else
                useThresh = false
            end
        end
        local _tiTrig = useThresh and true or false
        if _spTextInstead then useThresh = false end

        -- Fractional resource detection
        local frac = 0
        local preciseCur = cur
        if powerType == PT.SOUL_SHARDS then
            -- Destruction warlock: UnitPower partial values work
            local specIdx = GetSpecialization()
            local specID = specIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specIdx)
            if specID == 267 then
                local raw = UnitPower("player", powerType, true)
                if raw and (not issecretvalue or not issecretvalue(raw)) then
                    preciseCur = raw / 10
                    frac = preciseCur - cur
                end
            end
        elseif powerType == PT.ESSENCE then
            -- Evoker Essence: timer-based recharge (UnitPower partial doesn't work)
            local now = GetTime()
            local maxE = UnitPowerMax("player", PT.ESSENCE) or maxPts
            if issecretvalue and issecretvalue(maxE) then maxE = maxPts end

            -- Detect pip gain/loss and reset the timer
            if _essenceLastCount == nil then _essenceLastCount = cur end
            if cur ~= _essenceLastCount then
                if cur < maxE then
                    _essenceTickDur = ns.EssenceTickDuration()
                    _essenceNextTick = now + _essenceTickDur
                else
                    _essenceNextTick = nil
                end
                _essenceLastCount = cur
            end

            -- If below max and no timer running, start one
            if cur < maxE and not _essenceNextTick then
                _essenceTickDur = ns.EssenceTickDuration()
                _essenceNextTick = now + _essenceTickDur
            end

            -- At max: clear timer
            if cur >= maxE then _essenceNextTick = nil end

            -- Compute fill fraction for the recharging pip
            if _essenceNextTick and _essenceTickDur > 0 then
                local remaining = max(0, _essenceNextTick - now)
                frac = 1 - (remaining / _essenceTickDur)
                frac = max(0, min(1, frac))
                preciseCur = cur + frac
            end
        end

        -- Charged combo points (e.g. Supercharger talent)
        local chargedSet
        if powerType == PT.COMBO then
            local fn = GetUnitChargedPowerPoints
            if fn then
                local pts = fn("player")
                if pts and #pts > 0 then
                    chargedSet = {}
                    for _, idx in ipairs(pts) do chargedSet[idx] = true end
                end
            end
        end
        local cr, cg, cb, ca = sp.chargedR or 0.44, sp.chargedG or 0.77, sp.chargedB or 1.00, sp.chargedA or 1

        for i = 1, maxPts do
            if pips[i] and pips[i]:IsShown() then
                local active = i <= cur
                if chargedSet and chargedSet[i] then
                    if active then
                        pips[i]:SetActive(true, cr, cg, cb, ca)
                    else
                        pips[i]:SetActive(true, cr * 0.5, cg * 0.5, cb * 0.5, ca)
                    end
                elseif active and useThresh then
                    if not _tsBandOn and _tsPartialOnly and i < _tsThreshCount then
                        pips[i]:SetActive(true, r, g, b, a)
                    else
                        pips[i]:SetActive(true, tr, tg, tb)
                    end
                else
                    pips[i]:SetActive(active, r, g, b, a)
                end
                -- Hide any leftover partial-fill overlay on non-fractional pips
                if pips[i]._rechargeBar then pips[i]._rechargeBar:Hide() end
            end
        end

        -- Partial pip fill for fractional resources (reuses DK rune recharge pattern)
        if frac > 0 and cur < maxPts and pips[cur + 1] and pips[cur + 1]:IsShown() then
            local nextPip = pips[cur + 1]
            if not nextPip._rechargeBar then
                local sb = CreateFrame("StatusBar", nil, nextPip)
                sb:SetAllPoints(nextPip)
                sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                sb:SetFrameLevel(nextPip:GetFrameLevel())
                sb:SetMinMaxValues(0, 1)
                if nextPip._texKey then
                    local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, nextPip._texKey, nil)
                    if path then sb:SetStatusBarTexture(path) end
                end
                nextPip._rechargeBar = sb
                if nextPip._blizzMask then ns.ERB_MaskPip(nextPip, nextPip._blizzMask) end
            end
            nextPip._rechargeBar:SetValue(frac)
            -- Partial generator (Evoker/Lock): color the filling pip like the full
            -- ones -- the threshold/band color when it applies to this slot (index
            -- cur+1), else the base color. Optionally dimmed so it still reads
            -- as "recharging" rather than a completed pip.
            local fr, fg, fb = r, g, b
            local fi = cur + 1
            if useThresh and not (not _tsBandOn and _tsPartialOnly and fi < _tsThreshCount) then
                fr, fg, fb = tr, tg, tb
            end
            local shade = sp.darkenPartialPips == false and 1 or 0.75
            nextPip._rechargeBar:SetStatusBarColor(fr * shade, fg * shade, fb * shade, a)
            nextPip._rechargeBar:Show()
        end

        if sp.showText and secondaryFrame._countText then
            if frac > 0 and powerType ~= PT.ESSENCE then
                secondaryFrame._countText:SetText(format("%.1f", preciseCur))
            else
                secondaryFrame._countText:SetText(tostring(cur))
            end
            colorText(_spTextInstead, _tiTrig, tr, tg, tb, _spTextBaseR, _spTextBaseG, _spTextBaseB)
        end
    end
    -- Buff + recolor text instead
    if _buffActive and _spTextInstead and secondaryFrame and secondaryFrame._countText then
        secondaryFrame._countText:SetTextColor(_bfr, _bfg, _bfb, 0.9)
    end
end


-- Visibility & combat fade
local function ShouldShowSecondary()
    local sp = _G._ERB_ResolveSecondaryCfg()
    -- Check visibility options first
    if EllesmereUI.CheckVisibilityOptions(sp) then return false end
    -- Multi-select / dragonriding path (nil = legacy single mode below)
    if EllesmereUI and EllesmereUI.EvalVisibilityExtended then
        local st = ERB._visState
        if not st then st = {}; ERB._visState = st end
        local inRaid = IsInRaid and IsInRaid() or false
        st.inCombat = isInCombat
        st.inRaid = inRaid
        st.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
        local ext = EllesmereUI.EvalVisibilityExtended(sp, "visibility", st, EllesmereUI.VIS_CAPS_DEFAULT)
        if ext ~= nil then return ext end
    end
    local vis = sp.visibility
    if vis == "always" then return true end
    if vis == "never" then return false end
    if vis == "mouseover" then return "mouseover" end
    if vis == "combat" or vis == "in_combat" then return isInCombat end
    if vis == "out_of_combat" then return not isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    if vis == "in_raid" then return IsInRaid and IsInRaid() or false end
    if vis == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return not inRaid and (IsInGroup and IsInGroup() or false)
    end
    if vis == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

local function ShouldShowBar(barProfile)
    -- Check visibility options first
    if EllesmereUI.CheckVisibilityOptions(barProfile) then return false end
    -- Multi-select / dragonriding path (nil = legacy single mode below)
    if EllesmereUI and EllesmereUI.EvalVisibilityExtended then
        local st = ERB._visState
        if not st then st = {}; ERB._visState = st end
        local inRaid = IsInRaid and IsInRaid() or false
        st.inCombat = isInCombat
        st.inRaid = inRaid
        st.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
        local ext = EllesmereUI.EvalVisibilityExtended(barProfile, "visibility", st, EllesmereUI.VIS_CAPS_DEFAULT)
        if ext ~= nil then return ext end
    end
    local vis = barProfile.visibility or "always"
    if vis == "always" then return true end
    if vis == "never" then return false end
    if vis == "mouseover" then return "mouseover" end
    if vis == "combat" or vis == "in_combat" then return isInCombat end
    if vis == "out_of_combat" then return not isInCombat end
    if vis == "target" then return UnitExists("target") and UnitCanAttack("player", "target") end
    if vis == "in_raid" then return IsInRaid and IsInRaid() or false end
    if vis == "in_party" then
        local inRaid = IsInRaid and IsInRaid() or false
        return not inRaid and (IsInGroup and IsInGroup() or false)
    end
    if vis == "solo" then
        return not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup())
    end
    return true
end

-- Shared with EUI_ResourceBars_SwingTimer.lua: the swing timer runs the same
-- Visibility checklist as the class/power/health bars.
ns.ShouldShowBar = ShouldShowBar

-- Show When Missing: a step curve on the engine-side percent reveals a rule-hidden
-- bar below full. The curve result is secret, so it drives a wrapper the bar is
-- parented to (the bar's own alpha stays plain for its other readers, and the
-- Fade Out of Combat alpha still applies). Built on first use. Only resources
-- that rest at full count; rage and the like rest at empty.
local MISSING_POWERS = { [PT.MANA] = true, [PT.ENERGY] = true }

function ns.ERB_MissingWanted(cfg, flag, powerType)
    if not (cfg and flag) then return false end
    if powerType then
        if not MISSING_POWERS[powerType] then return false end
        if powerType == PT.MANA then
            local mx = UnitPowerMax("player", PT.MANA)
            if not mx or issecretvalue(mx) or mx <= 0 then return false end
        end
    end
    return (EllesmereUI.VisOverrideValue(cfg) or cfg.visibility) ~= "never"
end

function ns.ERB_MissingPaint(bar)
    local curve = ns.ERB_MissingCurve
    local pt = bar._missPower
    local a
    if pt then
        a = UnitPowerPercent("player", pt, false, curve)
    else
        a = UnitHealthPercent("player", false, curve)
    end
    bar._missWrap:SetAlpha(a)
end

-- SetParent resets the frame level; the strata follows the new parent (the
-- wrapper takes the bar's own on entry, so an inherited strata is never pinned).
local function MissingRehome(bar, parent)
    local level = bar:GetFrameLevel()
    bar:SetParent(parent)
    bar:SetFrameLevel(level)
end

-- live: reveal active for this bar; powerType nil means the health bar. home:
-- the parent to return to when the reveal ends (nil keeps the wrapper). park:
-- held in the wrapper at alpha 0 instead (the druid strip while the Power Bar
-- is revealed on energy with Show When Mana Missing off).
function ns.ERB_MissingApply(bar, live, powerType, home, park)
    local w = bar._missWrap
    if not live and not park then
        bar._missLive, bar._missParked = nil, nil
        if w then w:SetAlpha(1) end
        local h = bar._missHome
        if h and bar:GetParent() ~= h then MissingRehome(bar, h) end
        return
    end
    if not w then
        w = CreateFrame("Frame", nil, mainFrame)
        w:SetAllPoints(mainFrame)
        bar._missWrap = w
    end
    bar._missHome = home
    if bar:GetParent() ~= w then
        w:SetFrameStrata(bar:GetFrameStrata())
        MissingRehome(bar, w)
    end
    if park then
        bar._missLive, bar._missParked = nil, true
        w:SetAlpha(0)
        return
    end
    bar._missParked = nil
    if not ns.ERB_MissingCurve then
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 1)
        c:AddPoint(1, 0)
        ns.ERB_MissingCurve = c
    end
    bar._missLive = true
    bar._missPower = powerType
    ns.ERB_MissingPaint(bar)
end

-- The druid mana strip (a child of the Power Bar) while the visibility rules hide
-- the Power Bar. mode "mana": revealed on its own mana curve; "park": held out of
-- sight while an energy reveal shows the Power Bar (its anchor edge handed back);
-- nil: back under the Power Bar. Out of its wrapper it no longer inherits the
-- Power Bar's alpha, so the plain bar alpha is applied to it directly.
function ns.ERB_MissingHost(pb, pp, mode)
    local h = mode and ns.FDM_Host() or pb._missHost
    if not h then return end
    pb._missHost = h
    if mode == "mana" then
        ns.ERB_MissingApply(h, true, PT.MANA, pb)
        h:SetAlpha(ns.ResolveBarAlpha(pp))
    elseif mode == "park" then
        ns.ERB_MissingApply(h, false, nil, pb, true)
    elseif h._missLive or h._missParked then
        ns.ERB_MissingApply(h, false)
        h:SetAlpha(1)
    end
    ns.FDM_Parked(mode == "park")
end

-- WoW Forever Spell Cost Prediction host (EllesmereUI_SpellCostPrediction.lua,
-- nil off Forever): the power type the Power Bar shows, the segment's color at
-- the bar's Fill Opacity, and the Blizzard Style bar-shape mask for the
-- segment's fill. The segment sits one level above the inner bar, where the
-- druid mana strip's Inside mode draws: a frame at the inner bar's own level
-- is covered by its fill (see the hash tick overlay). Read on a cast start and
-- by a repeat attach during one, never per power event.
if EllesmereUI.SpellCostPrediction then
    ns.ERB_COST_HOST = {
        PowerType = function() return cachedPrimary end,
        Color = function()
            local pp = _G._ERB_ResolvePowerCfg()
            local r, g, b = EllesmereUI.SpellCostPrediction.Color(pp)
            return r, g, b, ((pp and pp.fillOpacity) or 100) / 100
        end,
        Mask = function()
            return primaryBar and primaryBar._blizzBarMask
        end,
    }
end

local function UpdateVisibility()
    -- Swing timer (Forever only) rides every visibility edge this module sees;
    -- a no-op until the feature is on.
    if ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
    if not mainFrame then return end

    -- Main frame always shown
    mainFrame:Show()
    mainFrame:SetAlpha(1)

    local inVehicle = ERB._inVehicle

    -- Hover-eligibility flags for the shared mouseover poll: a bar evaluating to
    -- "mouseover" stays hidden here and is revealed by the poll proxies
    -- (registered at setup) while the cursor is over it.
    ERB._moEligible = ERB._moEligible or {}

    -- Classic "Border Around All" membership: a bar shown outright and not
    -- riding the cursor (a mouseover bar is revealed on its own, so it keeps
    -- its own frame). Recorded only while the setting is on or the group
    -- still stands.
    local grp = ns._erbGroupOn or ns._erbGroupActive
    if grp then ns._erbGrpH, ns._erbGrpP, ns._erbGrpS = false, false, false end

    -- Health bar visibility
    if healthBar then
        local hp = _G._ERB_ResolveHealthCfg()
        local avail = hp and hp.enabled and not IsSpecDisabled(hp) and not _G._ERB_BarHiddenByForm(hp) and not inVehicle
        local vis = avail and ShouldShowBar(hp)
        ERB._moEligible.health = (vis == "mouseover")
        if grp then ns._erbGrpH = (vis == true) and not healthBar._erbMouseTrack end
        local missing = avail and vis == false and hp.showWhenMissing and ns.ERB_MissingWanted(hp, true)
        if missing or healthBar._missLive then ns.ERB_MissingApply(healthBar, missing) end
        if missing then vis = true end
        if vis == true then
            healthBar:Show()
            EllesmereUI.SetElementVisibility(healthBar, true)
            healthBar:SetAlpha(ns.ResolveBarAlpha(hp))
        else
            EllesmereUI.SetElementVisibility(healthBar, false)
        end
    end

    -- Power bar visibility
    if primaryBar then
        local pp = _G._ERB_ResolvePowerCfg()
        local sp = ERB.db.profile.secondary
        -- cachedPrimary is also checked: specs with no primary power (BM/MM Hunter)
        -- hide the power bar even when it is enabled in settings. "Hide Power Bar if
        -- Resource" applies only while the Class Resource is on: its toggle is greyed
        -- out otherwise, and a WoW Forever druid has combo points in Cat Form alone.
        local hidePower = sp and sp.hidePowerIfResource and sp.enabled ~= false and cachedSecondary
        local avail = not hidePower and pp and pp.enabled ~= false and not IsSpecDisabled(pp) and not _G._ERB_BarHiddenByForm(pp) and cachedPrimary and not inVehicle
        local vis = avail and ShouldShowBar(pp)
        ERB._moEligible.primary = (vis == "mouseover")
        if grp then ns._erbGrpP = (vis == true) and not primaryBar._erbMouseTrack end
        local pt = avail and cachedPrimary
        local ruleHidden = avail and vis == false
        -- One toggle per resource the bar can show; Mana also covers the druid strip below.
        local barFlag
        if pt == PT.MANA then barFlag = pp.showManaWhenMissing else barFlag = pp and pp.showWhenMissing end
        local missing = ruleHidden and barFlag and type(pt) == "number" and ns.ERB_MissingWanted(pp, true, pt)
        if missing or primaryBar._missLive then ns.ERB_MissingApply(primaryBar, missing, pt) end
        if missing then vis = true end
        local strip = ruleHidden and (pp.showManaWhenMissing or missing) and ns.FDM_Host and ns.FDM_Host()
        local hostMode
        if strip and pp.showManaWhenMissing and ns.ERB_MissingWanted(pp, true, PT.MANA) then
            hostMode = "mana"
        elseif strip and missing then
            hostMode = "park"
        end
        if hostMode or primaryBar._missHost then ns.ERB_MissingHost(primaryBar, pp, hostMode) end
        if vis == true then
            primaryBar:Show()
            EllesmereUI.SetElementVisibility(primaryBar, true)
            primaryBar:SetAlpha(ns.ResolveBarAlpha(pp))
        else
            EllesmereUI.SetElementVisibility(primaryBar, false)
        end
        -- WoW Forever mana regen spark (EllesmereUI_ManaRegenSpark.lua): attached
        -- while this bar can show, mouseover included so a hover reveal finds it
        -- running. Every BuildBars is followed by this pass, so attaching here
        -- also lays the spark out from the orientation BuildBars applied.
        if EllesmereUI.ManaRegenSpark then
            if (vis == true or vis == "mouseover") and pp.manaRegenSpark then
                EllesmereUI.ManaRegenSpark.Attach("erb", primaryBar._sb, pp.manaRegenSparkMode == "ticks")
            else
                EllesmereUI.ManaRegenSpark.Detach("erb")
            end
        end
        -- WoW Forever Spell Cost Prediction: attached on the same verdict while
        -- the bar shows mana, so a druid in Bear or Cat Form (or a class with
        -- no mana on a shared profile) hears no cast events. Every form change
        -- refreshes cachedPrimary before this pass.
        if EllesmereUI.SpellCostPrediction then
            if (vis == true or vis == "mouseover") and pp.powerCostPrediction
               and cachedPrimary == PT.MANA then
                EllesmereUI.SpellCostPrediction.Attach("erb", primaryBar._sb, ns.ERB_COST_HOST)
            else
                EllesmereUI.SpellCostPrediction.Detach("erb")
            end
        end
        -- WoW Forever druid mana bar: its mana events follow this verdict.
        if ns.FDM_Visibility then
            local fdmVis = vis
            if hostMode == "mana" then fdmVis = true elseif hostMode == "park" then fdmVis = false end
            ns.FDM_Visibility(fdmVis)
        end
    end

    -- Secondary resource visibility + ooc alpha
    if secondaryFrame then
        local sp = _G._ERB_ResolveSecondaryCfg()
        local vis = sp and sp.enabled ~= false and not IsSpecDisabled(sp) and not _G._ERB_BarHiddenByForm(sp) and cachedSecondary and not inVehicle and ShouldShowSecondary()
        ERB._moEligible.secondary = (vis == "mouseover")
        -- Blizzard Class Resource Art: the host holding Blizzard's frame takes
        -- this visibility; while that frame stands in for the pips the slot
        -- stays at zero alpha and out of the Border Around All group.
        local artOn, artHost = ns._erbArtOn, ns._erbArtHost
        if grp then ns._erbGrpS = (vis == true) and not artOn and not secondaryFrame._erbMouseTrack end
        if artHost then
            if vis == true then
                EllesmereUI.SetElementVisibility(artHost, true)
                artHost:SetAlpha(ns.ResolveBarAlpha(sp))
            else
                EllesmereUI.SetElementVisibility(artHost, false)
            end
        end
        if vis == true and not artOn then
            secondaryFrame:Show()
            EllesmereUI.SetElementVisibility(secondaryFrame, true)
            secondaryFrame:SetAlpha(ns.ResolveBarAlpha(sp))
        else
            EllesmereUI.SetElementVisibility(secondaryFrame, false)
        end
    end

    if grp then ns.ERB_GroupEval() end
end

-- Subsystem tickers. There is NO frame-rate OnUpdate multiplexer:
--  * Value fills (health/primary/secondary) are EVENT-DRIVEN -- handlers call
--    SetValue(v) and, while the bar's Smooth Bars item is on, the engine
--    animates the ease (ERB:ApplySmoothing), zero per-frame Lua.
--    Threshold/band coloring rides the same events; never add a color poll.
--  * Genuinely time-based jobs each ride their own fixed-rate anim ticker
--    (EllesmereUI.Tick.NewAnimTicker): the C engine fires OnLoop at the
--    configured rate and sleeps between fires, so no per-frame dispatch exists;
--    each ticker self-stops the moment its job settles.
--  * ns.ArmTick() (after every event and from ApplyAll) starts whichever
--    tickers the current state needs. Arming is deliberately indiscriminate: a
--    redundant Start is one IsPlaying check, a missed arm is a frozen bar.
-- Frames passed to NewAnimTicker are created HERE at file scope so the engine
-- bills the work to ResourceBars (frame-birth attribution rule).

-- Ebon Might drain (Aug Evoker; the engine slot owns the countdown when present).
-- 20 Hz drain + text; with the Power Bar's Smooth Bars item on, the engine eases
-- the fill between fires.
-- Re-armed by UNIT_AURA via ns.ArmTick.
ns.EMTick = EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()    if ns.EMB121_Owns then return end
    if cachedPrimary ~= "EBON_MIGHT" then return end
    if not (primaryBar and primaryBar:IsShown() and primaryBar:GetAlpha() > 0) then return end
    local remaining = (_ebonMightExpiry > 0) and max(0, _ebonMightExpiry - GetTime()) or 0
    primaryBar:SetValue(remaining)
    local pp = _G._ERB_ResolvePowerCfg()
    if pp and pp.textFormat and pp.textFormat ~= "none" then
        local fmt = pp.textFormat
        local percentSuffix = (pp.showPercent == false) and "" or "%"
        local pct = format("%d", remaining / EBON_MIGHT_DURATION * 100)
        local timeText = remaining > 0 and format("%.1f", remaining) or "0"
        local txt
        if fmt == "perpp" then txt = pct .. percentSuffix
        elseif fmt == "both" then txt = timeText .. " | " .. pct .. percentSuffix
        else txt = timeText end
        primaryBar._text:SetText(txt)
    end
    return remaining > 0
end, 0.05)

-- Guardian Ironfur / Prot Ignore Pain moving-hash motion: the only continuously
-- moving visuals outside the cast bar. 30 Hz keeps it fluid at a seventh of
-- frame-rate cost; both update paths are change-gated internally.
ns.MotionTick = EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()    local cs = cachedSecondary
    if not (cs and secondaryBar and secondaryBar:IsShown() and secondaryBar:GetAlpha() > 0) then return end
    if cs.power == "IRONFUR_BAR" then
        UpdateIronfurBar()
        return true
    elseif cs.power == "IGNOREPAIN_BAR" then
        IP.EnsureViewer()
        IP.UpdateHash()
        IP.UpdateText()
        return true
    end
end, 1 / 30)

-- Secondary-resource poll: DK rune fills and the custom/bar/buff safety poll at
-- 10Hz, Evoker Essence recharge at 20Hz. ONE ticker at a 20Hz base; 10Hz jobs
-- skip every other fire. All paths funnel into UpdateSecondaryResource, whose
-- value early-out makes an unchanged poll nearly free.
ns.PollTick = EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()    local cs = cachedSecondary
    -- Blizzard Class Resource Art stands in: nothing to poll (the ticker stops).
    if not cs or ns._erbArtOn then return end
    local pwr, typ = cs.power, cs.type
    if _essenceNextTick and pwr == PT.ESSENCE then
        UpdateSecondaryResource()
        return true
    end
    ns._pollFlip = not ns._pollFlip
    if ns._pollFlip then return true end
    if typ == "runes" or typ == "custom" or typ == "bar" or cs.frac then
        -- cs.frac (Destruction shard fragments): sub-unit movement, including
        -- out-of-combat decay, has no reliable event. The fragment-aware value
        -- guard costs one UnitPower per fire when nothing moved.
        UpdateSecondaryResource()
        return true
    end
    -- Tracked buffs on an enabled bar: the safety poll behind UNIT_AURA.
    if ns.SecTracks() then
        UpdateSecondaryResource()
        return true
    end
end, 0.05)

-- Spender pass (Class Resource Bar and Power Bar spender coloring). SPELL_UPDATE_USABLE,
-- SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_ICON and each tracked spell's cooldown-end
-- edge only request it: one hidden frame runs it on the next frame (its OnUpdate
-- hides the frame first), scans once and repaints a bar only when its winning spender
-- changed. A cooldown that ends on its own fires no event, so each tracked row
-- gets a hidden Cooldown widget fed the spell's cooldown duration object (GCD
-- ignored; the object is secret-safe) and its OnCooldownDone is the ready edge.
-- SPELL_UPDATE_COOLDOWN and an override swap (SPELL_UPDATE_ICON) re-feed the
-- widgets. They are built on the first pass and cleared on disarm; nothing here
-- runs while spenders are not armed (ns.ArmTick).
do
    local pass = CreateFrame("Frame")
    pass:Hide()
    local host
    local cds = {}
    local feed = false   -- re-feed the widgets on the next pass

    -- Latch each tracked spell's "on a real cooldown" verdict under its configured
    -- ID (read through the current override). isOnGCD is only trustworthy while
    -- answering SPELL_UPDATE_COOLDOWN, so it is read here.
    local function Latch(list, oncd)
        local S = C_Spell
        for i = 1, #list do
            local sid = list[i].spellID
            if sid then
                local cd = S.GetSpellCooldown(S.GetOverrideSpell(sid) or sid)
                oncd[sid] = (cd and cd.isActive and not cd.isOnGCD) and true or false
            end
        end
    end

    local function OnDone(cd)
        if not ns._spenderEvents then return end
        if cd._sid and cd._oncd then cd._oncd[cd._sid] = false end
        pass:Show()
    end

    -- Feeds list's rows into the widgets after position n, tagged with the bar's
    -- verdicts; returns the last position used.
    local function Feed(list, n, oncd)
        if not list then return n end
        if not host then
            host = CreateFrame("Frame")
            host:SetSize(1, 1)
            host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
            host:SetAlpha(0)
        end
        host:Show()
        local S = C_Spell
        for i = 1, #list do
            local k = n + i
            local cd = cds[k]
            if not cd then
                cd = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
                cd:SetAllPoints()
                cd:SetHideCountdownNumbers(true)
                cd:SetDrawBling(false)
                cd:EnableMouse(false)
                cd:SetScript("OnCooldownDone", OnDone)
                cds[k] = cd
            end
            local id = list[i].spellID
            cd._sid = id
            cd._oncd = oncd
            local dur = id and S.GetSpellCooldownDuration(S.GetOverrideSpell(id) or id, true)
            if dur then cd:SetCooldownFromDurationObject(dur) else cd:Clear() end
        end
        return n + #list
    end

    pass:SetScript("OnUpdate", function(self)
        self:Hide()
        local _, spend = ns.SecTracks()
        local pspend = ns.PowTracks()
        spend, pspend = spend and ns._spenderSec, pspend and ns._spenderPow
        if not (spend or pspend) then return end
        local t, pt = ns.STK, ns.PTK
        if feed then
            feed = false
            local n = Feed(spend and t.entry.spenderColors, 0, t.oncd)
            n = Feed(pspend and pt.entry.spenderColors, n, pt.oncd)
            for i = n + 1, #cds do
                cds[i]._sid = nil
                cds[i]._oncd = nil
                cds[i]:Clear()
            end
        end
        if spend then
            local w = ns.SpenderScan(t.entry)
            if w ~= t.w then
                t.w = w
                UpdateSecondaryResource()
            end
        end
        if pspend then
            local w = ns.SpenderScan(pt.entry, pt.oncd)
            if w ~= pt.w then
                pt.w = w
                UpdatePrimaryBar()
            end
        end
    end)

    function ns.SpenderRequest(refeed)
        if refeed then feed = true end
        pass:Show()
    end

    function ns.SpenderEvent(_, event, spellID, baseSpellID, category, recoveryCat)
        if event == "SPELL_UPDATE_COOLDOWN" then
            local _, spend = ns.SecTracks()
            local pspend = ns.PowTracks()
            spend, pspend = spend and ns._spenderSec, pspend and ns._spenderPow
            if not (spend or pspend) then return end
            local t, pt = ns.STK, ns.PTK
            -- A named update for an untracked spell changes nothing here unless it
            -- started the GCD; a nil or unreadable spellID updates every cooldown.
            if not (issecretvalue and issecretvalue(spellID)) and spellID
               and not t.ids[spellID] and not pt.ids[spellID]
               and not (baseSpellID and (t.ids[baseSpellID] or pt.ids[baseSpellID]))
               and recoveryCat ~= Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY then
                return
            end
            if spend then Latch(t.entry.spenderColors, t.oncd) end
            if pspend then Latch(pt.entry.spenderColors, pt.oncd) end
            feed = true
        elseif event == "SPELL_UPDATE_ICON" then
            -- An override appeared or went away: re-feed the widgets from the
            -- current forms.
            feed = true
        end
        pass:Show()
    end

    function ns.SpenderDisarm()
        feed = false
        pass:Hide()
        ns.STK.fedGen = nil
        wipe(ns.STK.oncd)
        wipe(ns.PTK.oncd)
        for i = 1, #cds do cds[i]:Clear() end
        if host then host:Hide() end
    end
end

-- Tick arming. Called after every event (OnEvent tail) and from ApplyAll; starts
-- whichever subsystem tickers the current state needs. Each ticker self-stops
-- when its job settles, so a redundant arm costs one IsPlaying check and a
-- missed arm only freezes until the next event. Cheap field reads only; the
-- config-derived answers (buff and spender tracking) come from ns.SecTracks,
-- cached on ns.CfgGen. Anything time-based added later MUST ride one of the
-- tickers above (with an arm condition here) or be event-driven -- NEVER a
-- per-frame OnUpdate (the spender pass is a one-shot on a hidden frame).
function ns.ArmTick()
    local cs = cachedSecondary
    local tracksBuff, tracksSpender = ns.SecTracks()
    -- Blizzard Class Resource Art stands in for the pips: arm nothing for them.
    if cs and not ns._erbArtOn then
        local pwr, typ = cs.power, cs.type
        if pwr == "IRONFUR_BAR" or pwr == "IGNOREPAIN_BAR" then
            ns.MotionTick.Start()
        end
        if typ == "runes" or typ == "custom" or typ == "bar" or cs.frac
           or (_essenceNextTick and pwr == PT.ESSENCE) or tracksBuff then
            ns.PollTick.Start()
        end
    end
    if cachedPrimary == "EBON_MIGHT" and not ns.EMB121_Owns
       and _ebonMightExpiry > GetTime() then
        ns.EMTick.Start()
    end
    -- Spender coloring: its three events are registered on the addon's own event
    -- frame only while an enabled bar's entry tracks spenders (the class-resource
    -- bar only while its pips are ours to paint). Arming and every config bump
    -- re-feed the spender pass.
    local swant = (tracksSpender and cs and not ns._erbArtOn) and true or false
    local pwant = (ns.PowTracks() and cachedPrimary and cachedPrimary ~= "EBON_MIGHT")
        and true or false
    local want = swant or pwant
    ns._spenderSec, ns._spenderPow = swant, pwant
    if want ~= (ns._spenderEvents or false) then
        ns._spenderEvents = want
        if want then
            ERB:RegisterEvent("SPELL_UPDATE_USABLE", ns.SpenderEvent)
            ERB:RegisterEvent("SPELL_UPDATE_COOLDOWN", ns.SpenderEvent)
            ERB:RegisterEvent("SPELL_UPDATE_ICON", ns.SpenderEvent)
        else
            ERB:UnregisterEvent("SPELL_UPDATE_USABLE")
            ERB:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            ERB:UnregisterEvent("SPELL_UPDATE_ICON")
            ns.SpenderDisarm()
        end
    end
    if want and ns.STK.fedGen ~= ns.CfgGen then
        ns.STK.fedGen = ns.CfgGen
        ns.SpenderRequest(true)
    end
end

-- Cast bar redraw without per-frame dispatch: a looping Animation fires OnLoop at the
-- redraw rate and the C engine sleeps between fires, so an active cast runs ZERO Lua at
-- frame rate (a per-frame accumulator gating the redraw would cost more than the redraw
-- itself: 0.14% floor vs 0.06% body). Host frame and group born HERE at file scope so
-- the work bills ResourceBars (frame-birth attribution). Self-stopping: the loop halts
-- the moment no cast state remains, covering every stop path without Stop calls in each
-- handler, at the cost of at most one no-op fire.
do
    local host = CreateFrame("Frame")
    local ag = host:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local tick = ag:CreateAnimation("Animation")
    -- 20 Hz redraw: the eased SetValue has the engine rendering intermediate fill
    -- positions between redraws, so this rate governs only text/stage/safety
    -- granularity, not fill smoothness.
    tick:SetDuration(1 / 20)
    ag:SetScript("OnLoop", function()
        if castBarFrame and (castBarFrame._casting or castBarFrame._channeling
           or castBarFrame._empowering) then
            UpdateCastBar()
        else
            ag:Stop()
        end
    end)
    -- Idempotent; safe to call from every cast event.
    ns.StartCastTick = function()
        if not ag:IsPlaying() then
            ag:Play()
        end
    end
end

-- Raw-fill writer for Smooth Bar Animation OFF. A plain SetValue lands only
-- at the 20 Hz tick and the engine has no linear interpolation to carry the
-- fill between redraws (Enum.StatusBarInterpolation: Immediate or ease-out
-- only), so raw mode visibly stepped. This frame does the minimal per-frame
-- write -- one time read, one SetValue -- and exists ONLY while a Lua-drawn
-- cast is active with smoothing off: shown by the per-cast constants memo,
-- hidden by ns.ShowIdleCastBar and by its own gate the moment cast state or
-- fill ownership changes. Hidden frame = zero idle cost. Text, stages,
-- spark and safety stay on the 20 Hz tick.
do
    local min, max = math.min, math.max
    local driver = CreateFrame("Frame")
    driver:Hide()
    ns._rawFillDriver = driver
    driver:SetScript("OnUpdate", function(self)
        local f = castBarFrame
        if not f or f._nativeFill or not f._rawFill
           or not (f._casting or f._channeling or f._empowering) then
            self:Hide()
            return
        end
        local dur = f._endTime - f._startTime
        local v
        if f._channeling then
            v = (dur > 0) and ((f._endTime - GetTime()) / dur) or 0
        else
            v = (dur > 0) and ((GetTime() - f._startTime) / dur) or 0
        end
        v = min(max(v, 0), 1)
        local bar = f._bar
        local sb = bar._sb or bar
        sb:SetValue(v)
        if f._gradientFullBar and f._gradClip then
            f._gradClip:SetWidth(max(0.01, bar:GetWidth() * v))
        end
    end)
end

-- GCD bar ticker: 20 Hz; the eased SetValue inside UpdateGCDBar carries the
-- fill between fires. Runs only while a GCD is live, and the final fire
-- renders the idle state before the loop stops itself.
ns.GCDTick = EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), function()
    UpdateGCDBar()
    return gcdBarFrame and gcdBarFrame._gcdStart ~= nil
end, 0.05)

I.HandleIronfurCast, I.ShouldShowBar = HandleIronfurCast, ShouldShowBar
I.ShouldShowSecondary, I.UpdateHealthBar = ShouldShowSecondary, UpdateHealthBar
I.UpdatePrimaryBar, I.UpdateSecondaryResource = UpdatePrimaryBar, UpdateSecondaryResource
I.UpdateVisibility = UpdateVisibility
I.broken = false
