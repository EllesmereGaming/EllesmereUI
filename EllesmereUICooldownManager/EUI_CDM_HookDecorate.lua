if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookDecorate.lua
--
--  DecorateFrame and CategorizeFrame.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local GetCDMFont = ns.GetCDMFont
local _ecmeFC = ns._ecmeFC
local FC = ns.FC
local _, _playerClass = UnitClass("player")

local hookFrameData, ResolveCDIDToBar = I.hookFrameData, I.ResolveCDIDToBar
local ResolveFrameSpellID, ResolveSpellSettings = I.ResolveFrameSpellID, I.ResolveSpellSettings
local ApplyCdmChargeStyle, ApplyCdmEdge = I.ApplyCdmChargeStyle, I.ApplyCdmEdge
local ApplyMaxStacksGlow, CdmChargeInfoFor = I.ApplyMaxStacksGlow, I.CdmChargeInfoFor
local CdmFrameIsActive, CdmStaleLinkedSpell = I.CdmFrameIsActive, I.CdmStaleLinkedSpell
local EvalMaxStacksFrame = I.EvalMaxStacksFrame
local HideBlizzardDecorations = I.HideBlizzardDecorations
local WatchMaxStacksFrame, ApplyCustomIcon = I.WatchMaxStacksFrame, I.ApplyCustomIcon
local ApplyOnlyNumbers, ArmCdStateEval = I.ApplyOnlyNumbers, I.ArmCdStateEval
local TryHookSwiftmend = I.TryHookSwiftmend

-------------------------------------------------------------------------------
--  DecorateFrame
--  Add our visual overlays to a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function DecorateFrame(frame, barData)
    -- Empty Slot: deliberately undecorated (true blank grid space, no texture/
    -- cooldown/border/glowOverlay). Never register it in hookFrameData -- every
    -- _getFD(icon) lookup then reads nil and every fd-driven pass (bar-wide
    -- glow/border/background included) already no-ops on a nil fd.
    if frame._isEmptySlotFrame then return end
    local fd = hookFrameData[frame]
    if not fd then fd = {}; hookFrameData[frame] = fd end

    -- Border + background track the CURRENT bar's settings on EVERY call, not just the
    -- first: Blizzard recycles one icon-frame pool across bars/spells, so a frame
    -- decorated under another bar's style must pick this bar's up on every (re)claim.
    -- For hooked default bars (Essential/Utility) this is the ONLY re-style path
    -- (RefreshCDMIconAppearance is skipped for them); structural creation stays
    -- one-time via the fd.borderFrame/fd.bg guards, only styling is unconditional.
    -- Frame levels are relative to the icon's LIVE level (never cached at first
    -- decoration) so a reclaimed pooled frame stays correctly layered.
    local baseLvl = frame:GetFrameLevel()

    -- Blizzard Style (Global Settings > Style): no EUI background or border;
    -- the viewer's rounded mask stays and ns.CdmApplyBlizzIconArt draws the
    -- ring. Stamped on fd so the swipe hooks read one flag per push.
    local blizzArt = ns.CdmBlizzIcons()
    fd._blizzArt = blizzArt or nil

    if blizzArt then
        if fd.bg then fd.bg:Hide() end
    else
        if not fd.bg then
            local bg = frame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            fd.bg = bg
        end
        fd.bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08,
            barData.bgB or 0.08, barData.bgA or 0.6)
    end

    -- Show Cooldown Edge: stamped per (re)claim so the cooldown hooks read one
    -- flag instead of chasing frame -> bar -> settings on every push. Toggling
    -- rebuilds bars, so the stamp always tracks the live setting; on the
    -- on -> off transition drop a mid-sweep edge now instead of waiting for
    -- Blizzard's next cooldown push.
    local edgeOn = barData.showCooldownEdge or nil
    if fd._edgeFeatureOn and not edgeOn and fd.cooldown and fd.cooldown.SetDrawEdge then
        fd._isProcessingOverride = true
        fd.cooldown:SetDrawEdge(false)
        fd._isProcessingOverride = false
        fd._edgeApplied = nil
    end
    fd._edgeFeatureOn = edgeOn

    -- Custom-shape bars own their border: ApplyShapeToCDMIcon draws the ring on
    -- shapeBorder and hides the square border. Re-applying the square style here
    -- would force it back on unchanged reanchors (no shape re-apply follows those),
    -- so keep it hidden -- newly (re)claimed frames land in an iconsChanged refresh
    -- that re-applies the shape. Active-state tint on shaped icons rides
    -- shapeBorder, never the square border, so both re-asserts below are square-only.
    local shapeKey = barData.iconShape
    if blizzArt then
        -- Blizzard Style: the ring overlay is the frame; no square border.
        if fd.borderFrame then
            EllesmereUI.PP.HideBorder(fd.borderFrame)
            local bdFrame = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[fd.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
    elseif shapeKey and shapeKey ~= "none" and shapeKey ~= "cropped" then
        if fd.borderFrame then
            EllesmereUI.PP.HideBorder(fd.borderFrame)
            local bdFrame = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[fd.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
    else
        if not fd.borderFrame then
            local bf = CreateFrame("Frame", nil, frame)
            bf:SetAllPoints(frame)
            fd.borderFrame = bf
        end
        local brdR, brdG, brdB = barData.borderR or 0, barData.borderG or 0, barData.borderB or 0
        if barData.borderClassColor then
            local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
            if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
        end
        local textureKey = barData.borderTexture or "solid"
        local brdSize = barData.borderSize or 1
        EllesmereUI.ApplyBorderStyle(fd.borderFrame,
            brdSize,
            brdR, brdG, brdB, barData.borderA or 1,
            textureKey, barData.borderTextureOffset, barData.borderTextureOffsetY,
            barData.borderTextureShiftX, barData.borderTextureShiftY,
            "cdm", barData.borderThickness or "thin", true,
            EllesmereUI.BorderPx(barData.borderSizePx, brdSize, textureKey))
        -- ApplyBorderStyle always paints the bar's BASE color, so re-assert the
        -- active-state tint if engaged (fd._activeBorderOn, set by
        -- ApplyActiveOverlays off Blizzard's SetSwipeColor) or a reanchor mid-proc flashes it back to base.
        if fd._activeBorderOn and EllesmereUI.SetBorderStyleColor then
            local fcA = _ecmeFC[frame]
            local sidA, bkA = fcA and fcA.spellID, fcA and fcA.barKey
            local ss = sidA and ResolveSpellSettings(frame, sidA, ns.GetBarSpellData(bkA))
            local abR = (ss and ss.activeBorderR) or 1
            local abG = (ss and ss.activeBorderG) or 0.776
            local abB = (ss and ss.activeBorderB) or 0.376
            local abA = (ss and ss.activeBorderA) or 1
            EllesmereUI.SetBorderStyleColor(fd.borderFrame, abR, abG, abB, abA)
        end
    end
    -- "Show Behind": +13 draws the border in front of the icon, level-1 behind it.
    if fd.borderFrame then
        fd.borderFrame:SetFrameLevel(barData.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 13))
    end
    if fd.glowOverlay then fd.glowOverlay:SetFrameLevel(baseLvl + 16) end
    -- Blackout (solid-fill Cooldown State glow) sits BELOW frame.Cooldown
    -- (icon+14), unlike every other glow style on glowOverlay (icon+16): a
    -- fill above it would hide the swipe and countdown. Made by
    -- ns.StartCdGlow on the icon's first Blackout start.
    if fd.blackoutOverlay then fd.blackoutOverlay:SetFrameLevel(baseLvl + 12) end
    if fd.textOverlay then fd.textOverlay:SetFrameLevel(baseLvl + 23) end
    if blizzArt then ns.CdmApplyBlizzIconArt(frame) end

    if fd.decorated then
        -- Late retry: the style block already ran; skip one-time decoration.
        TryHookSwiftmend(frame, fd)
        ApplyCustomIcon(frame, fd)
        ApplyOnlyNumbers(frame, fd, barData)
        return fd
    end
    fd.decorated = true

    -- A HOSTED buff frame is a Blizzard buff-viewer frame on a CD/util bar: its
    -- swipe is the AURA DURATION, so the cd-style swipe hooks below (Suppress-GCD,
    -- active-state override, charge logic) must NEVER touch it or they blank the
    -- duration swipe every GCD. viewerFrame is stable per pooled frame: flag once.
    fd._isBuffViewerFrame = (frame.viewerFrame == _G.BuffIconCooldownViewer
        or frame.viewerFrame == _G.BuffBarCooldownViewer) or nil

    local iconWidget = frame.Icon
    if iconWidget and not iconWidget.GetTexture then
        if iconWidget.Icon then iconWidget = iconWidget.Icon end
    end
    fd.tex = iconWidget
    fd.cooldown = frame.Cooldown

    -- Swiftmend brightness (druid only; retried from the decorated early-return).
    TryHookSwiftmend(frame, fd)

    -- First decoration: fd.tex is now available, so Custom Icon can stamp.
    ApplyCustomIcon(frame, fd)
    ApplyOnlyNumbers(frame, fd, barData)

    HideBlizzardDecorations(frame)

    -- Per-icon Audio on Buff Gain/Loss: hook one-time here, before the frame is ever
    -- active, so the first activation is not missed. Buff-family only;
    -- EnsureBuffSoundHook self-guards on TriggerAuraAppliedAlert presence, so
    -- injected-custom/non-aura frames are no-ops.
    if (barData and (barData.barType == "buffs" or barData.key == "buffs"))
       and ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then
        ns.EnsureBuffSoundHook(frame)
    end

    -- Hook SetPoint: when Blizzard repositions this frame (Layout,
    -- RefreshLayout, internal updates), force it back to the stored CDM anchor.
    if not fd._setPointHooked then
        fd._setPointHooked = true
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo)
            local anchor = fd._cdmAnchor
            if not anchor then
                -- Not yet claimed by our bar system: re-blank so it does not flash at
                -- the viewer's position before CollectAndReanchor claims it.
                if fd.decorated then
                    frame:SetAlpha(0)
                    -- Re-park CD/utility frames offscreen (buff pools stay hands-off):
                    -- alpha alone cannot keep an unclaimed frame invisible -- the
                    -- engine re-raises item alpha through paths no SetAlpha hook can
                    -- see (SetAlphaFromBoolean, alpha animations) on cooldown/aura
                    -- changes (druid form swaps). Position enforcement is immune to
                    -- every alpha path, and a later re-claim SetPoints absolutely. The
                    -- TOPLEFT keyword MUST match LayoutCDMBar's claim SetPoint (which
                    -- does not ClearAllPoints): same-keyword SetPoint REPLACES the park
                    -- point, a different one accumulates a conflicting anchor.
                    if not fd._isBuffViewerFrame and not fd._parkGuard then
                        fd._parkGuard = true
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                        fd._parkGuard = nil
                    end
                end
                return
            end
            -- relativeTo == our bar container: our own LayoutCDMBar SetPoint.
            if relativeTo == anchor[2] then return end
            -- Blizzard is trying to move us. Force back to CDM position.
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end


    -- Per-icon active state hooks installed lazily during CollectAndReanchor,
    -- ONLY for spells with custom active state settings.

    -- Overlay creation is one-time; frame levels re-applied at the top.
    if not fd.glowOverlay then
        local go = CreateFrame("Frame", nil, frame)
        go:SetAllPoints(frame)
        go:SetAlpha(0)
        go:EnableMouse(false)
        fd.glowOverlay = go
        go:SetFrameLevel(baseLvl + 16)
    end

    -- Re-arm the buff ticker's active-glow "nothing configured" latch: this
    -- function re-runs on rebuilds/settings changes (exactly when the cached
    -- answer can change), so a newly enabled glow is picked up next pass.
    fd._activeGlowNoCfg = nil

    if not fd.textOverlay then
        local txo = CreateFrame("Frame", nil, frame)
        txo:SetAllPoints(frame)
        txo:EnableMouse(false)
        fd.textOverlay = txo
        txo:SetFrameLevel(baseLvl + 23)
    end

    if not fd.keybindText then
        local kt = fd.textOverlay:CreateFontString(nil, "OVERLAY")
        local kbScale = frame:GetScale() or 1
        if kbScale < 0.01 then kbScale = 1 end
        EllesmereUI.ApplyIconTextFont(kt, GetCDMFont(), (barData.keybindSize or 10) / kbScale, "cdm")
        kt:Hide()
        ns.StyleCDMKeybind(kt, barData, fd.textOverlay, 1 / kbScale, GetCDMFont())
        fd.keybindText = kt
    end

    fd.tooltipShown = false

    -- Pandemic hooks deliberately NOT installed here: they install lazily from
    -- the buff tick, per icon, only when the bar uses a custom pandemic style
    -- (zero cost unless enabled; closures are CDM-billed via file-scope bodies).

    local fc = FC(frame)
    if not fc.tooltipHooked then
        fc.tooltipHooked = true
        frame:HookScript("OnEnter", function()
            local ffc = _ecmeFC[frame]
            local bd = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if bd and not bd.showTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    fd.procGlowActive = false

    if fd.cooldown then
        fd.cooldown:SetDrawEdge(false)
        -- Swipe starts disabled; CollectAndReanchor enables it once claimed and
        -- positioned, so no black-swipe flash at the viewer's default position.
        fd.cooldown:SetDrawSwipe(false)
        fd.cooldown:SetDrawBling(false)
        fd._isProcessingOverride = true
        fd.cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
        fd._isProcessingOverride = false
        -- High-res flat white, never WHITE8x8: the wedge cut's anti-aliasing comes
        -- from texel filtering, so an 8px texture rasterizes the boundary jagged at
        -- any angle. Own asset over the game's viewer swipe for sharp corners (the
        -- stock file bakes in corner rounding that mismatches our squared icons).
        -- Blizzard Style keeps the viewer's rounded swipe to match its mask.
        fd.cooldown:SetSwipeTexture(ns.CdmSwipeFile())
        -- Hook SetSwipeColor on EVERY CD/utility frame: forces our swipe color
        -- (black, or per-spell custom) so Blizzard's active-state color flash
        -- never shows. SetDrawSwipe hooked too, to keep charge swipes visible.
        if not fd._swipeColorHooked then
            fd._swipeColorHooked = true
            local cd = fd.cooldown
            hooksecurefunc(cd, "SetSwipeColor", function()
                if fd._isProcessingOverride then return end
                -- Buff-viewer frame (buff bar or hosted) or our own preset/custom
                -- buff frame (cast-timer driven): the swipe is the aura DURATION,
                -- so skip all cd-style logic (Suppress-GCD, active-state) and
                -- apply only per-spell "Cooldown Swipe Color" (Default = bar's
                -- swipe colour/black, Class/Custom per settings).
                if fd._isBuffViewerFrame or frame._isCustomBuffFrame then
                    fd._isProcessingOverride = true
                    local fcB = _ecmeFC[frame]
                    local sidB = fcB and fcB.spellID
                    local bkB = fcB and fcB.barKey
                    local ssB = (sidB and bkB and ns.ResolveSpellSettings)
                        and ns.ResolveSpellSettings(frame, sidB, false, bkB) or nil
                    local sr, sg, sb
                    -- CURRENT bar's swipe alpha, not the decorate-time closure
                    -- barData: pooled frames decorate once, so it holds whichever
                    -- bar first decorated this frame.
                    local bdB = bkB and barDataByKey and barDataByKey[bkB]
                    local alpha = (bdB and bdB.swipeAlpha) or barData.swipeAlpha or 0.7
                    local mode = ssB and ssB.cdSwipeColor
                    if mode == "class" then
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then sr, sg, sb = cc.r, cc.g, cc.b end
                    elseif mode == "custom" then
                        sr, sg, sb = ssB.cdSwipeColorR, ssB.cdSwipeColorG, ssB.cdSwipeColorB
                    elseif mode == "none" then
                        alpha = 0  -- fully hide the swipe (alpha 0, geometry still valid)
                    end
                    cd:SetSwipeColor(sr or 0, sg or 0, sb or 0, alpha)
                    fd._isProcessingOverride = false
                    return
                end
                fd._isProcessingOverride = true
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                local bd2 = bk2 and barDataByKey and barDataByKey[bk2]
                -- Resolved BEFORE the Suppress GCD block: the per-spell
                -- suppressGCD flag joins the bar toggle there (pure hoist --
                -- this resolve always ran once per hook pass, just later).
                local ss2
                if sid2 and bk2 then
                    ss2 = ResolveSpellSettings(frame, sid2, false)
                end
                local _gcdSuppressed = false
                -- Recharge duration of a charge spell whose recharge is running
                -- out underneath a GCD; see ns.GCDTailAlpha at the swipe writes.
                local _gcdChargeTail
                -- Per-bar "Suppress GCD": alpha-0 the swipe while the displayed
                -- cooldown is just a GCD (isOnGCD is a clean bool). Do NOT return
                -- early -- active-state detection below must still run so overlays
                -- and duration timers work during a GCD. Two cases must NEVER be
                -- suppressed: (1) the Hide-Active override window forcing the real
                -- recharge display (a GCD from another ability is moot); (2) a
                -- charge spell with a recharge in flight (ANY count below max,
                -- incl. 0) -- that swipe IS the recharge, and alpha-0'ing it blanks
                -- the recharge for a whole GCD whenever another ability is pressed.
                -- The Hide-Active exclusion applies to whole-swipe suppression
                -- ONLY, not the charge tail: _hideActiveOverriding follows the
                -- active read, which flaps for charge spells.
                -- Per-spell "Suppress GCD" ORs into the bar toggle: with the
                -- bar toggle ON the per-spell flag is a natural no-op.
                if ((bd2 and bd2.suppressGCD) or (ss2 and ss2.suppressGCD)) and sid2
                   and C_Spell and C_Spell.GetSpellCooldown then
                    -- Charge-recharge guard: mid-recharge (INCLUDING 0 charges)
                    -- shows the recharge, never a GCD, so never alpha-0 it.
                    -- Derived from STABLE charge data (maxCharges > 1 AND
                    -- GetSpellCharges().isActive), NOT
                    -- HasVisualDataSource_Charges, which flips FALSE while a GCD
                    -- swipe is layered on top -- the exact moment this hook runs
                    -- -- letting a 0-charge recharge get suppressed. Both fields
                    -- clean; secret currentCharges never read. Override ID
                    -- resolved for transform spells.
                    local effID2 = sid2
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                        if ovr and ovr > 0 and ovr ~= sid2 then effID2 = ovr end
                    end
                    -- Resolved through Blizzard's own accessor: see CdmChargeInfoFor.
                    -- This value decides whether the swipe may be alpha-0'd, and a
                    -- wrong "not recharging" here blanks a live recharge for a whole
                    -- GCD on every override spell.
                    local chargeRecharging = false
                    do
                        local ci = CdmChargeInfoFor(frame, sid2)
                        chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                    end
                    -- The GCD read must use the override too: a transform's real
                    -- CD ticks on the override ID, and the base-ID query reads
                    -- isOnGCD=true through that whole CD, suppressing the swipe
                    -- for its full duration.
                    local cdInfo = C_Spell.GetSpellCooldown(effID2) or C_Spell.GetSpellCooldown(sid2)
                    if cdInfo and cdInfo.isOnGCD then
                        if not chargeRecharging then
                            if not fd._hideActiveOverriding then
                                cd:SetSwipeColor(0, 0, 0, 0)
                                _gcdSuppressed = true
                            end
                        elseif C_Spell.GetSpellChargeDuration then
                            -- Recharge in flight, but its LAST GCD-length slice
                            -- is drawn by the GCD. Hand the recharge duration to
                            -- the swipe writes below, which alpha-0 that slice
                            -- only; earlier keeps the recharge swipe (case 2).
                            _gcdChargeTail = C_Spell.GetSpellChargeDuration(effID2)
                                or C_Spell.GetSpellChargeDuration(sid2)
                        end
                    end
                end
                -- Publish the tail decision for ReArmChargeRecharge. That runs from
                -- the SetCooldown hooks, which fire for EVERY icon on every push,
                -- so it must decide whether it cares without paying for a spell
                -- lookup. This flag is exactly the state it needs -- a charge
                -- recharge running underneath a GCD -- and it is already computed
                -- here from clean bools. Blizzard's refresh calls SetSwipeColor
                -- before CooldownFrame_Set, so it is fresh when the re-arm reads it.
                fd._gcdChargeTailArmed = _gcdChargeTail ~= nil
                -- Active state detected from the swipe color.
                local swipeColor = frame.cooldownSwipeColor
                local isActive = false
                if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                    local r = swipeColor:GetRGBA()
                    if r and type(r) == "number" and not issecretvalue(r) then
                        isActive = (r ~= 0)
                    end
                end

                -- Flip the per-session gates the moment any spell uses these
                -- settings, so the SetDesaturated/SetDrawSwipe hooks early-out on
                -- one check for everyone else. Runs for every icon on login.
                if ss2 and ss2.desatNotActive then ns._cdmAnyDesatNotActive = true end
                if ss2 and ss2.noDesatOnCD then ns._cdmAnyNoDesatOnCD = true end
                if ss2 and (ss2.chargeHideSwipe or ss2.hideRechargeEdge) then ns._cdmAnyChargeStyle = true end
                if ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then ns._cdmAnyMaxStacksGlow = true end
                if ss2 and ss2.activeGlow and ss2.activeGlow > 0 then ns._cdmAnyActiveGlow = true end
                if ss2 and ss2.chargeHideCdText then ns._cdmAnyChargeHideCdText = true end
                if ss2 and ss2.showCooldownText ~= nil then ns._cdmAnySpellDurationText = true end
                if ss2 and ss2.hideChargeText then ns._cdmAnyHideChargeText = true end
                if ss2 and ss2.suppressGCD then ns._cdmAnySuppressGcd = true end
                if ss2 and ss2.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                if ss2 and ss2.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                if ss2 and (tonumber(ss2.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end

                if ss2 and ss2.activeSwipeMode == "none" then
                    -- Hide Active State: force black swipe, track active flag (CD
                    -- model override belongs to the SetDesaturation hook, which fires
                    -- on every Blizzard cooldown tick). Suppress GCD for a hero-talent
                    -- transform to a usable follow-up: while a castable proc shows
                    -- (override present, not on its own real CD) this icon has no real
                    -- CD, so the black swipe has no geometry -- until another ability
                    -- pushes a GCD via SetCooldown, whose geometry the PERSISTENT
                    -- black colour sweeps as a visible bar (SetCooldown changes
                    -- geometry, not colour, so nothing re-hides it). Paint fully
                    -- transparent for exactly that case, and also for a plain
                    -- hide-active spell whose swipe color never zeroes out
                    -- (e.g. Prismatic Barrier), which pins fd._hideActiveOverriding
                    -- and otherwise leaks a bare GCD once charges max out. Gated
                    -- on Suppress GCD; a spell genuinely on its own real CD keeps
                    -- the black swipe, and a charge proc mid-recharge is carved
                    -- out (its swipe IS the recharge).
                    local hideActiveAlpha = barData.swipeAlpha or 0.7
                    if ((bd2 and bd2.suppressGCD) or (ss2 and ss2.suppressGCD)) and sid2
                       and C_SpellBook and C_SpellBook.FindSpellOverrideByID
                       and C_Spell and C_Spell.GetSpellCooldown then
                        local chargeRecharging = false
                        do
                            local ci = CdmChargeInfoFor(frame, sid2)
                            chargeRecharging = (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) or false
                        end
                        if not chargeRecharging then
                            local ovrID = C_SpellBook.FindSpellOverrideByID(sid2)
                            local checkID = (ovrID and ovrID > 0 and ovrID ~= sid2) and ovrID or sid2
                            local oc = C_Spell.GetSpellCooldown(checkID)
                            if oc and not (oc.isActive and not oc.isOnGCD) then
                                hideActiveAlpha = 0
                            end
                        end
                    end
                    if not _gcdSuppressed then
                        cd:SetSwipeColor(0, 0, 0, ns.GCDTailAlpha(_gcdChargeTail, hideActiveAlpha))
                    end
                    if isActive then
                        fd._hideActiveOverriding = true
                        fd._wasActive = true
                    elseif fd._hideActiveOverriding then
                        fd._hideActiveOverriding = false
                        if cd.SetUseAuraDisplayTime then
                            cd:SetUseAuraDisplayTime(true)
                        end
                    end
                elseif isActive then
                    -- Active: swipe color (custom, class, or default #FFC660).
                    local cr, cg, cb, ca
                    if ss2 and ss2.activeSwipeClassColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                        end
                    end
                    -- Blizzard Style: the viewer's own active swipe colour
                    -- unless a per-spell active colour is set.
                    if fd._blizzArt and not cr and not (ss2 and ss2.activeSwipeR) then
                        cr, cg, cb = 1, 0.95, 0.57
                    end
                    cr = cr or (ss2 and ss2.activeSwipeR) or 1
                    cg = cg or (ss2 and ss2.activeSwipeG) or 0.776
                    cb = cb or (ss2 and ss2.activeSwipeB) or 0.376
                    ca = (ss2 and ss2.activeSwipeA) or 0.7
                    cd:SetSwipeColor(cr, cg, cb, ca)
                    if fd.tex then fd.tex:SetDesaturated(false); fd._desatNA = nil end
                    fd._wasActive = true
                else
                    -- Not active: black swipe.
                    if not _gcdSuppressed then
                        cd:SetSwipeColor(0, 0, 0, ns.GCDTailAlpha(_gcdChargeTail, barData.swipeAlpha or 0.7))
                    end
                    -- Desaturate When Not Active (per-spell). Symmetric, but
                    -- re-saturates only icons WE desaturated (fd._desatNA), so
                    -- turning it off never fights cdState/buff desaturation and
                    -- un-greys without waiting for the next cooldown event.
                    if fd.tex then
                        if ss2 and ss2.desatNotActive then
                            fd.tex:SetDesaturated(true)
                            fd._desatNA = true
                        elseif fd._desatNA then
                            fd.tex:SetDesaturated(false)
                            fd._desatNA = nil
                        end
                    end
                    -- Buff ended, CD starting: re-apply the cooldown duration so
                    -- the swipe shows immediately. Once per transition, only when
                    -- the spell actually has an active cooldown.
                    if fd._wasActive then
                        fd._wasActive = false
                        if sid2 and cd.SetCooldownFromDurationObject and C_Spell.GetSpellCooldown then
                            local cdInfo = C_Spell.GetSpellCooldown(sid2)
                            if cdInfo and cdInfo.isActive then
                                local durObj = C_Spell.GetSpellCooldownDuration(sid2)
                                if durObj then
                                    cd:SetCooldownFromDurationObject(durObj)
                                    cd:SetDrawSwipe(true)
                                end
                            end
                        end
                    end
                end

                -- Charge "Hide Swipe" suppresses only the recharge swipe: the
                -- active-state colored swipe IS the active overlay, so keep it
                -- while active. Inside the override guard, so no re-entry.
                if ns._cdmAnyChargeStyle and ss2 and ss2.chargeHideSwipe and cd.SetDrawSwipe
                   and type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then
                    cd:SetDrawSwipe(ss2.activeSwipeMode ~= "none" and isActive)
                end

                -- Active glow + border (per-spell). Extracted so the Fake-Active
                -- engine can drive the same overlays from its own ticker, sharing
                -- fd._activeGlowOn / fd._activeBorderOn. Touches only our
                -- overlays, never the Blizzard swipe: safe from any context.
                ns.ApplyActiveOverlays(frame, fd, ss2, isActive, bd2)

                -- Max Stacks Glow: "at max" = no recharge running
                -- (GetSpellCharges().isActive; secret currentCharges never read).
                -- Consuming a charge fires this swipe hook, refilling to max
                -- fires Cooldown:Clear. Register for charge events (the only
                -- catch for refill-to-max) and eval now so a SPEND is immediate.
                if ns._cdmAnyMaxStacksGlow and ss2 and ss2.maxStacksGlow and ss2.maxStacksGlow > 0 then
                    WatchMaxStacksFrame(frame, fd)
                    EvalMaxStacksFrame(frame, fd)
                elseif fd._maxStacksGlowOn then
                    ApplyMaxStacksGlow(frame, fd, nil, false)  -- setting cleared -> off
                    ns._maxStacksWatch[frame] = nil
                end

                fd._gcdSwipeSuppressed = _gcdSuppressed
                fd._isProcessingOverride = false
            end)
            hooksecurefunc(cd, "SetDrawSwipe", function(_, show)
                if fd._isProcessingOverride then return end
                -- Hosted buff: never toggle its duration swipe from our cd logic.
                if fd._isBuffViewerFrame then return end
                -- Charges/Stacks Only (No Icon): art is hidden, so a swipe would
                -- draw a dark pie over empty space on every re-push. Suppress
                -- instead of the force-true below, ahead of the charge-style call
                -- (with no icon there is nothing for an edge to decorate).
                if fd._osnOn then
                    if show then
                        fd._isProcessingOverride = true
                        cd:SetDrawSwipe(false)
                        fd._isProcessingOverride = false
                    end
                    return
                end
                -- Charge spells get the baseline edge (+ per-spell Hide Swipe):
                -- ApplyCdmChargeStyle returns true and owns swipe + edge for
                -- them; non-charge frames fall to the force-true below.
                fd._isProcessingOverride = true
                local handled = ApplyCdmChargeStyle(frame, cd)
                -- Bar-wide Show Cooldown Edge (non-charge frames; charge frames
                -- get their edge from ApplyCdmChargeStyle). GCD suppression
                -- drops an edge we applied, tracked so the disabled/default
                -- path never issues a redundant SetDrawEdge.
                if not handled and fd._edgeFeatureOn and cd.SetDrawEdge then
                    if not fd._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[frame]
                        ApplyCdmEdge(cd, fcEdge and fcEdge.barKey)
                        fd._edgeApplied = true
                    elseif fd._edgeApplied then
                        cd:SetDrawEdge(false)
                        fd._edgeApplied = nil
                    end
                end
                fd._isProcessingOverride = false
                if handled then return end
                -- Per-spell Hide CD Swipe (non-charge): keep the swipe suppressed
                -- across Blizzard re-pushes. Gated (costs nothing until enabled),
                -- resolved from our own flags (secret-safe) in BOTH stores:
                -- per-bar spellSettings and preset customActiveStates.
                if ns._cdmAnyHideCDSwipe then
                    local ssH = ns._ResolveCdmSS(frame)
                    local hideSw = ssH and ssH.hideCDSwipe
                    if not hideSw and ns.GetEffectiveCustomActiveState then
                        local fcH = _ecmeFC[frame]
                        local sidH = fcH and fcH.spellID
                        if sidH then
                            local casH = ns.GetEffectiveCustomActiveState(sidH)
                            hideSw = casH and casH.hideCDSwipe
                        end
                    end
                    if hideSw then
                        if show then
                            fd._isProcessingOverride = true
                            cd:SetDrawSwipe(false)
                            fd._isProcessingOverride = false
                        end
                        return
                    end
                end
                if show then return end
                fd._isProcessingOverride = true
                cd:SetDrawSwipe(true)
                fd._isProcessingOverride = false
            end)
            -- Cooldown edge enforcement. Re-assert the bar-wide Blizzard edge, or
            -- per-spell Hide Recharge Edge, across Blizzard cooldown re-pushes.
            if cd.SetDrawEdge then
                hooksecurefunc(cd, "SetDrawEdge", function(_, show)
                    if fd._isProcessingOverride then return end
                    -- Edge-off pushes only matter to the bar-wide edge re-assert
                    -- (every other branch below acts on show=true alone), so the
                    -- disabled/default path keeps its zero-cost early-out.
                    if not show and not fd._edgeFeatureOn then return end
                    if fd._isBuffViewerFrame then return end
                    -- No icon art: no recharge edge, charge or not. Blizzard
                    -- re-enables it on every re-push, so this must be in the hook.
                    if fd._osnOn then
                        if show then
                            fd._isProcessingOverride = true
                            cd:SetDrawEdge(false)
                            fd._isProcessingOverride = false
                        end
                        return
                    end
                    local hasChargeSource = type(frame.HasVisualDataSource_Charges) == "function"
                        and frame:HasVisualDataSource_Charges()
                    if hasChargeSource and ns._cdmAnyChargeStyle then
                        local ss2 = ns._ResolveCdmSS(frame)
                        if ss2 and ss2.hideRechargeEdge then
                            if show then
                                fd._isProcessingOverride = true
                                cd:SetDrawEdge(false)
                                fd._isProcessingOverride = false
                            end
                            return
                        end
                    end
                    -- Bar-wide Show Cooldown Edge: re-assert across Blizzard's
                    -- own edge-off pushes (stock disables it on every non-charge
                    -- cooldown update).
                    if fd._edgeFeatureOn and not fd._gcdSwipeSuppressed then
                        local fcEdge = _ecmeFC[frame]
                        fd._isProcessingOverride = true
                        ApplyCdmEdge(cd, fcEdge and fcEdge.barKey)
                        fd._isProcessingOverride = false
                        fd._edgeApplied = true
                    end
                end)
            end
            -- Non-charge cooldown re-assert. Blizzard's CooldownViewer zeroes the
            -- widget for some spells partway through their REAL cooldown and never
            -- re-pushes -- e.g. DH placement sigils (Flame/Misery/Silence, not Spite)
            -- clear when the sigil activates (~1s in) while GetSpellCooldown still
            -- reports the full 30s, leaving no swipe for the rest of the CD. Charge
            -- spells use the charge re-arm below. Gated tightly to that exact failure
            -- (widget cleared to ~0 while a genuine non-GCD cooldown is live), so it never fights a GCD swipe or aura-display time (both non-zero).
            local function ReAssertRealCooldown()
                if fd._isProcessingOverride then return end
                -- Always-Show placeholders deliberately keep their widget cleared
                -- (never arm a 0-duration swipe); never re-assert onto one.
                if fd._isBuffViewerFrame or frame._isPlaceholderFrame then return end
                -- Charge spells: owned by the charge re-arm path.
                if type(frame.HasVisualDataSource_Charges) == "function"
                   and frame:HasVisualDataSource_Charges() then return end
                if not (C_Spell and C_Spell.GetSpellCooldown
                        and C_Spell.GetSpellCooldownDuration) then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 then return end
                -- Act only when the widget is cleared to ~0 (never fight a real
                -- cooldown, GCD, or aura-display time). The secret check MUST
                -- precede any truthiness/comparison (a secret errors on either);
                -- a secret duration cannot prove "cleared", so fail closed (the
                -- sigil failure moment reads a clean 0, so the fix still runs).
                --
                -- SECOND PROOF, needed because the fail-closed above is permanent in
                -- instanced combat (the duration reads secret there, so this function
                -- could never act -- see CdmStaleLinkedSpell). A stale linked spell
                -- means Blizzard clears this widget on EVERY refresh, so there is
                -- nothing to fight and no duration read is required to know it.
                --
                -- These free reads run BEFORE the spell queries below: every Clear on
                -- every non-charge icon lands here, and the cooldown query allocates a
                -- table per call, so the common exits (secret duration in instanced
                -- combat, a widget still carrying a real swipe) must cost no query.
                local staleLink = CdmStaleLinkedSpell(frame)
                if not staleLink and cd.GetCooldownDuration then
                    local ok, curDur = pcall(cd.GetCooldownDuration, cd)
                    if not ok then return end
                    if issecretvalue and issecretvalue(curDur) then return end
                    if curDur and curDur > 100 then return end
                end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Only re-assert for a genuine, non-GCD cooldown still running.
                -- isActive / isOnGCD are clean bools (read bare elsewhere).
                local cdInfo = C_Spell.GetSpellCooldown(effID) or C_Spell.GetSpellCooldown(sid2)
                if not (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD) then return end
                local durObj = C_Spell.GetSpellCooldownDuration(effID)
                    or C_Spell.GetSpellCooldownDuration(sid2)
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
                cd:SetCooldownFromDurationObject(durObj)
                if staleLink then
                    -- Blizzard's expired branch never calls SetSwipeColor, so the
                    -- widget still carries whatever colour was painted last. For an
                    -- aura-tracking icon that is the ACTIVE colour from the aura
                    -- window, and it then renders over the cooldown we just armed --
                    -- field-seen as "the swipe was still yellow". Repaint the resting
                    -- cooldown colour, the same black the SetSwipeColor hook's
                    -- not-active branch uses (the per-spell Cooldown Swipe Color only
                    -- applies to buff-viewer frames, which never reach here).
                    -- This also releases a Suppress-GCD alpha-0 that can be stuck for
                    -- the same reason -- what we just armed is a real cooldown, never
                    -- a GCD. Mirrors ReArmChargeRecharge, which repaints for exactly
                    -- this reason on the charge path.
                    -- Gated to the stale case on purpose: the placement-sigil case
                    -- reaches here with a colour Blizzard has kept current, so it is
                    -- left alone. Bar data is resolved LIVE rather than from the
                    -- decorate-time closure, since pooled frames decorate once.
                    local bkS = fc2.barKey
                    local bdS = bkS and barDataByKey and barDataByKey[bkS]
                    cd:SetSwipeColor(0, 0, 0, (bdS and bdS.swipeAlpha) or 0.7)
                end
                -- Only geometry was wiped (Blizzard's clear leaves draw-swipe on),
                -- so re-arming the duration restores the swipe. Deliberately NOT
                -- forcing SetDrawSwipe(true): under the override guard that would
                -- bypass per-spell "Hide CD Swipe".
                fd._isProcessingOverride = false
            end

            -- Charge-spell recharge swipe restore. The swipe renders from the
            -- widget's armed duration, NOT the SetDrawSwipe flag (which only
            -- gates an existing swipe). When one charge refills while another
            -- still recharges Blizzard calls Cooldown:Clear(), wiping the armed
            -- duration, so SetDrawSwipe(true) has no geometry and the valid
            -- recharge swipe vanishes: re-arm from the charge recharge duration.
            -- Charge spells only; non-charge frames route to the re-assert above.
            hooksecurefunc(cd, "Clear", function()
                if fd._isProcessingOverride then return end
                -- HasVisualDataSource_Charges is a clean bool present only on
                -- Blizzard CooldownViewer item frames, so this also excludes our
                -- custom (trinket/racial/item) and aura buff frames.
                local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                    and frame:HasVisualDataSource_Charges()
                if not hasCharges then ReAssertRealCooldown(); return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCooldown
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                -- Resolve the override ID for transformed spells BEFORE querying
                -- cooldown state, so replacements report against the live spell.
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- isActive / isOnGCD are clean bools. Only re-arm while genuinely
                -- recharging AND not merely on GCD: a GCD-tail race can report
                -- isActive with a degenerate charge duration, and arming a 0,0
                -- cooldown strobes the swipe. All charges back (isActive false):
                -- leave cleared so the swipe correctly disappears.
                -- Max Stacks Glow: Clear fires on every charge refill (incl. to
                -- max), so re-eval from GetSpellCharges().isActive (clean, false
                -- only at max) and the glow lights as the last charge returns.
                if ns._cdmAnyMaxStacksGlow then
                    local bkm = fc2 and fc2.barKey
                    local ssm = bkm and ResolveSpellSettings(frame, sid2, false) or nil
                    if ssm and ssm.maxStacksGlow and ssm.maxStacksGlow > 0 then
                        WatchMaxStacksFrame(frame, fd)
                        EvalMaxStacksFrame(frame, fd)
                    end
                end
                local cdInfo = C_Spell.GetSpellCooldown(effID)
                local cdActive = cdInfo and cdInfo.isActive and not cdInfo.isOnGCD
                -- Charge-in-hand Hide-Active window: GetSpellCooldown().isActive
                -- is false while a castable charge remains, so the cd gate above
                -- never re-arms and Blizzard's per-aura-refresh wipe leaves the
                -- swipe blank. Re-arm off the clean recharge flag instead, ONLY
                -- inside our Hide-Active override so non-override charge spells
                -- keep Blizzard's native display. currentCharges never read.
                local chargeActive = fd._hideActiveOverriding
                    and (CdmChargeInfoFor(frame, sid2) or {}).isActive == true
                if not (cdActive or chargeActive) then return end
                -- Re-derive the recharge duration. The duration object is opaque,
                -- fed straight to the widget and never inspected: secret-safe.
                local durObj = C_Spell.GetSpellChargeDuration(effID)
                if not durObj and effID ~= sid2 then
                    durObj = C_Spell.GetSpellChargeDuration(sid2)
                end
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then
                    cd:SetUseAuraDisplayTime(false)
                end
                cd:SetCooldownFromDurationObject(durObj)
                -- Baseline charge edge (+ per-spell Hide Swipe) on the re-arm.
                ApplyCdmChargeStyle(frame, cd)
                fd._isProcessingOverride = false
            end)
            -- During the Hide-Active window Blizzard re-pushes the widget for a
            -- charge-in-hand spell via SetCooldownFromDurationObject (aura
            -- display) and SetUseAuraDisplayTime -- NOT plain SetCooldown -- and
            -- those pushes wipe the recharge we armed (Clear/SetDesaturated fire
            -- far too rarely to keep up). Re-assert on those two real drivers,
            -- gated to EXACTLY (charge frame + Hide-Active window + recharge
            -- running) = no-op otherwise; _isProcessingOverride blocks recursion.
            local function ReArmChargeRecharge()
                if fd._isProcessingOverride then return end
                -- Two field reads and nothing else. This runs from the SetCooldown
                -- / SetCooldownFromDurationObject / SetUseAuraDisplayTime hooks, so
                -- it fires for EVERY icon on EVERY cooldown push -- every GCD the
                -- player triggers. Neither entry can be live without one of these
                -- set, so bail before touching the frame or any API.
                if not (fd._hideActiveOverriding or fd._gcdChargeTailArmed) then
                    return
                end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if not sid2 or not C_Spell or not C_Spell.GetSpellCharges
                    or not C_Spell.GetSpellChargeDuration then
                    return
                end
                -- Hosted buff / custom buff frames are excluded here for the same
                -- reason the SetSwipeColor and Clear hooks exclude them: their
                -- cooldown widget is showing an AURA, and arming a spell recharge
                -- over it would overwrite the duration they exist to display.
                if fd._isBuffViewerFrame or frame._isCustomBuffFrame then return end
                -- Split from the value: "false" and "the frame has no such method"
                -- are different states, and entry B needs the first. Preset, racial,
                -- custom-spell and trinket frames are ours rather than CooldownViewer
                -- items and have no data source at all, which the sibling Clear hook
                -- relies on as an exclusion -- treating that as "at zero charges"
                -- would let them into a branch written for viewer items.
                local isViewerItem = type(frame.HasVisualDataSource_Charges) == "function"
                local hasCharges = isViewerItem and frame:HasVisualDataSource_Charges()
                -- ENTRY A (original): the Hide-Active override window, where
                -- Blizzard's aura pushes wipe the recharge we armed.
                local entryA = (fd._hideActiveOverriding and hasCharges) or false
                -- ENTRY B: the GCD has taken the icon over at the TAIL of a
                -- recharge. Measured in game: once the remaining recharge falls
                -- below one GCD length, Blizzard re-points the widget at the GCD
                -- (SetCooldown fires, GetSpellCooldown().isOnGCD flips true), and
                -- HasVisualDataSource_Charges is false throughout because the
                -- player is at ZERO charges -- so entry A cannot fire. Suppress
                -- GCD then does its job and alpha-0s that swipe, and the last
                -- second of the recharge goes blank, snapping back only when the
                -- charge lands. That is the reported "0 -> 1 breaks the cooldown
                -- swipe", and hiding was never the right answer: the recharge is
                -- still running and is what the player is watching. Re-arm the
                -- real recharge so the swipe keeps showing the truth.
                --
                -- fd._gcdChargeTailArmed is the SetSwipeColor hook's own verdict on
                -- that state, published one call earlier in the same refresh, so
                -- this path re-derives nothing.
                --
                -- Suppress GCD is re-checked here rather than trusted from the
                -- latch. Blizzard's expired branch skips SetSwipeColor entirely and
                -- frames are pooled, so the latch can survive into a frame or a bar
                -- it was not set for; requiring the setting again bounds a stale
                -- latch to "re-arm a charge spell that is genuinely recharging",
                -- which is the intended action anyway.
                local entryB = false
                if not entryA and isViewerItem and not hasCharges
                   and fd._gcdChargeTailArmed == true then
                    local bkB = fc2.barKey
                    local bdB = bkB and barDataByKey and barDataByKey[bkB]
                    entryB = (bdB and bdB.suppressGCD and true) or false
                    -- Per-spell Suppress GCD: same re-check contract as the bar
                    -- toggle. Session-gated so unused installs never resolve.
                    if not entryB and ns._cdmAnySuppressGcd then
                        local ssB = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
                        entryB = (ssB and ssB.suppressGCD and true) or false
                    end
                end
                if not (entryA or entryB) then return end
                local effID = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID = ovr end
                end
                -- Charge spell with a recharge genuinely running. maxCharges > 1 is
                -- the charge-spell test every other carve-out in this file uses --
                -- a 1-charge spell reports charge data too, and re-arming one that
                -- Suppress GCD had just alpha-0'd would repaint it at full alpha in
                -- the same refresh. Both fields are clean; the secret
                -- currentCharges is never read.
                local ci = CdmChargeInfoFor(frame, sid2)
                if not (ci and (ci.maxCharges or 0) > 1 and ci.isActive == true) then
                    return
                end
                local durObj = C_Spell.GetSpellChargeDuration(effID)
                if not durObj and effID ~= sid2 then
                    durObj = C_Spell.GetSpellChargeDuration(sid2)
                end
                if not durObj then return end
                fd._isProcessingOverride = true
                if cd.SetUseAuraDisplayTime then
                    cd:SetUseAuraDisplayTime(false)
                end
                cd:SetCooldownFromDurationObject(durObj)
                -- No-op on the entry-B path by construction: ApplyCdmChargeStyle
                -- bails unless HasVisualDataSource_Charges is true, and entry B
                -- requires it false. That is correct rather than an oversight --
                -- Hide Swipe (Charges) and Hide Recharge Edge already do not apply
                -- while the widget is off the charge source, so the tail now
                -- matches the rest of the zero-charge window instead of differing
                -- from it. Entry A still needs the call.
                ApplyCdmChargeStyle(frame, cd)
                -- We have just re-armed the REAL recharge, so whatever is now
                -- displayed is the recharge -- never a GCD. Suppress-GCD's alpha-0
                -- swipe (set while isOnGCD, e.g. right after pressing ANOTHER
                -- ability) must not stick here or the recharge stays invisible.
                --
                -- Black is only unconditionally right on the entry-A path, which by
                -- definition runs inside the Hide-Active window. Entry B can reach
                -- an icon whose active state paints a COLOURED swipe, and this write
                -- sits under _isProcessingOverride so the SetSwipeColor hook cannot
                -- put that colour back -- hence the active check. When the icon is
                -- active, leaving the colour alone is correct: the next refresh
                -- repaints it, and the geometry we just armed is what mattered.
                local bkA = fc2.barKey
                local bdA = bkA and barDataByKey and barDataByKey[bkA]
                if entryA or not CdmFrameIsActive(frame) then
                    cd:SetSwipeColor(0, 0, 0, (bdA and bdA.swipeAlpha) or 0.7)
                end
                fd._isProcessingOverride = false
            end
            if cd.SetCooldownFromDurationObject then
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReArmChargeRecharge)
                -- Also catch the placement-sigil case where Blizzard clears the
                -- widget via a zero-duration SetCooldownFromDurationObject rather
                -- than Clear(). The guard blocks recursion and the ~0 duration
                -- gate makes this a no-op for normal pushes.
                hooksecurefunc(cd, "SetCooldownFromDurationObject", ReAssertRealCooldown)
            end
            if cd.SetUseAuraDisplayTime then
                hooksecurefunc(cd, "SetUseAuraDisplayTime", ReArmChargeRecharge)
            end
            -- Pressing ANOTHER ability pushes the GCD onto this frame via
            -- SetCooldown (not the aura-display setters), replacing the charge
            -- recharge geometry -- in the Hide-Active window that wipes the real
            -- recharge until the active state ends, so re-arm on SetCooldown too.
            -- ReArmChargeRecharge fully self-gates and is re-entry guarded: a
            -- no-op for normal cooldowns and outside the override window.
            if cd.SetCooldown then
                hooksecurefunc(cd, "SetCooldown", ReArmChargeRecharge)
            end
        end
        -- Hook SetDesaturated AND SetDesaturation on the icon texture (Blizzard
        -- calls these every cooldown tick): while overriding the CD model (hide
        -- active state), re-apply the real CD duration so it cannot revert.
        if fd.tex and not fd._desatOverrideHooked then
            fd._desatOverrideHooked = true
            local function onDesatChange()
                if fd._isProcessingOverride then return end
                -- Two owners of this path now. The Hide-Active override is the
                -- original one. The second is the stale-linked-spell state, where
                -- Blizzard re-clears the widget AND re-saturates the icon on every
                -- refresh -- so the repair has to ride the same per-tick driver to
                -- survive, and the body below already does exactly the right thing
                -- for it: it re-arms the cooldown from OUR spell id and then sets
                -- the desaturation from that same id's real cooldown state.
                -- Cheap-first: the flag is one lookup, the helper two more.
                if not (fd._hideActiveOverriding or CdmStaleLinkedSpell(frame)) then return end
                fd._isProcessingOverride = true
                local cdw = fd.cooldown
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if sid2 and cdw then
                    if cdw.SetUseAuraDisplayTime then
                        cdw:SetUseAuraDisplayTime(false)
                    end
                    if cdw.SetCooldownFromDurationObject then
                        -- Effective spell ID: for transforms the charge/cooldown
                        -- APIs report against the override ID, not the base.
                        -- Query override first, fall back to base.
                        local effID = sid2
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                            if ovr and ovr > 0 and ovr ~= sid2 then
                                effID = ovr
                            end
                        end
                        local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                            and frame:HasVisualDataSource_Charges()
                        local durObj
                        if hasCharges and C_Spell.GetSpellChargeDuration then
                            durObj = C_Spell.GetSpellChargeDuration(effID)
                            if not durObj and effID ~= sid2 then
                                durObj = C_Spell.GetSpellChargeDuration(sid2)
                            end
                        end
                        if not durObj and C_Spell.GetSpellCooldownDuration then
                            durObj = C_Spell.GetSpellCooldownDuration(effID)
                            if not durObj and effID ~= sid2 then
                                -- Borrow the base spell's cooldown ONLY when the live
                                -- override is itself on a real CD (a cosmetic transform
                                -- sharing the base cooldown -- the fallback's purpose)
                                -- OR its cooldown is unknown (oc nil). A hero-talent
                                -- transform to a CASTABLE follow-up reports no real CD
                                -- and must NOT inherit the base's remaining cooldown
                                -- (that painted the base CD swipe over a usable proc);
                                -- leaving durObj nil takes the same no-swipe path as a
                                -- proc without a real CD. Only a CONFIRMED- castable
                                -- proc suppresses the borrow. Mirrors the desat guard
                                -- below so swipe and saturation agree. isActive/isOnGCD
                                -- are clean bools.
                                local oc = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(effID)
                                if (not oc) or (oc.isActive and not oc.isOnGCD) then
                                    durObj = C_Spell.GetSpellCooldownDuration(sid2)
                                end
                            end
                        end
                        if durObj then
                            cdw:SetCooldownFromDurationObject(durObj)
                        end
                    end
                end
                -- Desaturate only if actually on cooldown; procs without a real
                -- CD stay saturated. Filter GCDs like the suppressGCD check. Ask
                -- the EFFECTIVE spell, override first: a transform's real cooldown
                -- ticks on the OVERRIDE id while the base reports none (measured:
                -- base isActive=false, override isActive=true isOnGCD=false), so a
                -- base-only read verdicts "not on cooldown" and never greys. Fall
                -- back to the base ONLY when the override query returns nothing
                -- (unknown), never on a clean "not active" -- that is the
                -- castable-proc case and must win.
                local effID2 = sid2
                if sid2 and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                    if ovr and ovr > 0 and ovr ~= sid2 then effID2 = ovr end
                end
                local cdInfo2 = effID2 and C_Spell.GetSpellCooldown
                    and (C_Spell.GetSpellCooldown(effID2)
                        or (effID2 ~= sid2 and C_Spell.GetSpellCooldown(sid2)) or nil)
                local onRealCD = cdInfo2 and cdInfo2.isActive and not cdInfo2.isOnGCD
                -- Charge spells report cooldown isActive mid-recharge even with a
                -- castable charge left, which would wrongly desaturate a usable
                -- icon. currentCharges is SECRET in this tainted hook, so the
                -- usable-charge verdict has to come from somewhere else -- see
                -- the guard below.
                -- The charge-SPELL test is static charge data, NOT the
                -- HasVisualDataSource_Charges flag: that one is documented three
                -- times in this file as answering "is this icon drawing its recharge
                -- right now", which is false at full charges and during a GCD, so
                -- gating the whole branch on it made it dead code. maxCharges is
                -- stable and clean; the secret currentCharges is never read.
                -- Resolve it through Blizzard's own accessor rather than a base-ID
                -- read: CdmChargeInfoFor documents the two disagreeing on override
                -- spells (captured on Blink 1953 -> Shimmer 212653), where a base
                -- read reports the charge-less base, so this test came back false
                -- and the guard never ran on a 2-charge ability. The swipe guard
                -- already resolves charges this way and the two verdicts must agree.
                local chargeCI = CdmChargeInfoFor(frame, sid2)
                local maxCh = chargeCI and chargeCI.maxCharges
                local isChargeSpell = type(maxCh) == "number"
                    and not (issecretvalue and issecretvalue(maxCh))
                    and maxCh > 1
                local outOfCharges
                if onRealCD and isChargeSpell then
                    -- Preferred signal: Blizzard's own charge visual-data-source
                    -- flag. isOnActualCooldown below is derived from the cooldown
                    -- startTime + duration, both SECRET inside instanced content,
                    -- so it comes back unreadable from this tainted hook the
                    -- moment a key starts -- the guard then set nothing and a
                    -- banked charge desaturated. Fresh login looked fine because
                    -- nothing was secret yet. wasSetFromCharges is a plain literal
                    -- assigned inside an untainted branch, so it survives that,
                    -- and RefreshData clears it and CacheCooldownValues re-sets it
                    -- immediately before the SetDesaturated call this hooks, so it
                    -- is never stale here.
                    -- Only TRUE is informative: Blizzard sets it for
                    -- "cooldownStartTime > 0 and currentCharges > 0", so false is
                    -- equally what a full-charge icon and an aura-driven one
                    -- report -- those keep falling through to the read below, which
                    -- is why this cannot re-break greying at zero charges.
                    -- Read the field, falling back to the getter: a past field
                    -- dump on a 12.0 client reported the getter as nil on these
                    -- frames while isOnActualCooldown beside it read fine, so
                    -- take whichever of the two this client actually carries.
                    local fromCharges = frame.wasSetFromCharges
                    if type(fromCharges) ~= "boolean"
                        and type(frame.HasVisualDataSource_Charges) == "function" then
                        fromCharges = frame:HasVisualDataSource_Charges()
                    end
                    if type(fromCharges) == "boolean"
                        and not (issecretvalue and issecretvalue(fromCharges))
                        and fromCharges then
                        outOfCharges = false
                    end
                    if type(outOfCharges) ~= "boolean" then
                        local actualCD = frame.isOnActualCooldown
                        if not issecretvalue or not issecretvalue(actualCD) then
                            if actualCD == false then
                                outOfCharges = false
                            elseif actualCD == true then
                                outOfCharges = true
                            end
                        end
                    end
                end
                if outOfCharges == false then
                    onRealCD = false
                end
                -- No clear-only transform guard here: asking the override first
                -- already answers the castable-proc case. Such a guard can turn
                -- greying off but never on, so an icon whose cooldown lives on
                -- the override could never grey -- do not reintroduce one.
                fd.tex:SetDesaturated(onRealCD or false)
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", onDesatChange)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", onDesatChange)
            end
        end
        -- Swipe direction baseline by FRAME kind, not just bar kind: a buff frame
        -- (or hosted-buff placeholder) fills like a buff even on a CD/utility bar.
        -- Decoration is once-per-frame while Blizzard POOLS frames, so record the
        -- kind in fd._revKind and let the claim loops re-assert on kind change,
        -- else a frame decorated for the wrong family keeps that direction all
        -- session (buffs randomly reversed by pool history).
        local isBuff = (barData.barType == "buffs" or barData.key == "buffs"
            or barData.barType == "custom_buff"
            or fd._isBuffViewerFrame or frame._isPlaceholderFrame) and true or false
        -- Per-spell Reverse Swipe flips the baseline (see EffectiveReverseSwipe):
        -- writing the bare kind here undid the setting on every reanchor.
        local revEff = ns.EffectiveReverseSwipe(frame, barData.key, isBuff)
        fd.cooldown:SetReverse(revEff)
        fd._revKind = revEff

        -- Clear IS hooked above (_swipeColorHooked block) to restore the recharge swipe
        -- on charge spells, and SetCooldown too (ReArmChargeRecharge) so an off-GCD
        -- push cannot wipe the recharge in the Hide-Active window. A hooksecurefunc
        -- post-hook does not taint the secure caller; taint would stick only if the
        -- hook BODY wrote a Blizzard frame field (isActive, allowAvailableAlert) or
        -- called Show/Hide/SetAlpha on a Blizzard frame. Neither does: they read clean
        -- getters and call pure cooldown-widget setters (SetUseAuraDisplayTime /
        -- SetCooldownFromDurationObject / SetDrawSwipe / SetSwipeColor), and all hook
        -- state lives on the external fd table, never on the Blizzard frame.

        -- Cooldown State Effect: separate additive SetDesaturated hook.
        -- Blizzard calls it on every CD tick AND on CD end -- the right event
        -- for both transitions. Independent from onDesatChange (hideActive).
        if fd.tex and not fd._cdStateHooked then
            fd._cdStateHooked = true
            hooksecurefunc(fd.tex, "SetDesaturated", function()
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                if bk2:sub(1, 7) == "__ghost" then return end
                -- FocusKick icon alpha is owned by SetFocusKickAlpha only.
                if bk2 == ns.FOCUSKICK_BAR_KEY then return end
                -- Preset frames (trinket/racial/potion/custom spell) own their cd-state
                -- through the Fake-Active engine, which reads the ITEM/racial cooldown.
                -- GetSpellCooldown cannot read a negative item key, so this spell path
                -- always sees the item as ready and would re-light the shared
                -- glowOverlay every desat tick while on cooldown. Hand off cleanly
                -- (clear any glow we owned).
                if ns.PresetHasCdState and ns.PresetHasCdState(frame) then
                    if fd._cdStateGlowOn then
                        ns.StopCdGlow(fd)
                        fd._cdStateGlowOn = false
                        -- The Fake-Active path tracks this overlay via its own
                        -- flag; clear it too so its next tick re-asserts the
                        -- glow we just stopped (else it thinks the glow is
                        -- still on and a ready preset stays dark).
                        fd._presetCdGlowOn = false
                    end
                    return
                end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
                local cse = ns.GetSpellCdStateEffect(frame, ss2)
                -- Shift-Icons variants = base hidden mode + a bar-relayout
                -- flag; normalize here so every comparison below is unchanged.
                -- Hidden Until Usable = Hidden (On CD) + the usable flag.
                local cseShift = (cse == "hiddenOnCDShift" or cse == "hiddenReadyShift"
                    or cse == "hiddenUnusableShift")
                local cseUsable = (cse == "hiddenUnusable" or cse == "hiddenUnusableShift")
                if cse == "hiddenOnCDShift" or cseUsable then cse = "hiddenOnCD"
                elseif cse == "hiddenReadyShift" then cse = "hiddenReady" end
                if not cse then
                    if fd._cdStateGlowOn then
                        ns.StopCdGlow(fd)
                        fd._cdStateGlowOn = false
                    end
                    -- A preset's cdState lives in customActiveStates (Fake-Active
                    -- engine), not per-bar spellSettings -- clearing its hidden flag
                    -- here would flash it visible every desat tick. Those frames
                    -- already returned through the PresetHasCdState hand-off above,
                    -- so no re-check is needed on this path.
                    if fc2 and fc2._cdStateHidden then
                        fc2._cdStateHidden = false
                    end
                    if fc2 and fc2._cdStateShiftHidden and ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc2, false)
                    end
                    return
                end
                -- Clear stale hidden state when switching to a non-hidden effect
                -- (lowerAlphaOnCD is alpha-owning like the hidden modes, so exclude it).
                if cse ~= "hiddenOnCD" and cse ~= "hiddenReady" and cse ~= "lowerAlphaOnCD" then
                    if fc2 and fc2._cdStateHidden then
                        fc2._cdStateHidden = false
                        local bd2 = barDataByKey and barDataByKey[bk2]
                        frame:SetAlpha(ns.IconShownAlpha(fc2, bd2))
                    end
                    -- (cse is already normalized, so Shift variants never land here.)
                    if fc2 and ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc2, false)
                    end
                end
                -- Hidden / lower-alpha modes: hand off to the shared deferred
                -- evaluator (ArmCdStateEval -- see its comment for the
                -- one-frame wait). cse is normalized, so Shift variants arrive
                -- as their base mode plus cseShift.
                if cse == "hiddenOnCD" or cse == "hiddenReady" or cse == "lowerAlphaOnCD" then
                    ArmCdStateEval(frame, fd, cse, cseShift,
                        (ss2 and ss2.cdStateLowerAlpha) or 0.5,
                        ss2 and ss2.chargeHideUntilSpent, cseUsable)
                    -- Proc edges change only usability: SPELL_UPDATE_USABLE watch.
                    if cseUsable then ns.WatchCdUsable(frame) end
                    -- Hidden (CD Ready) on a charge spell also needs the refill-to-max
                    -- edge, which this hook never fires. Registered once per spell
                    -- binding (a pooled frame can be handed a different spell), so
                    -- steady-state cost is one field compare per repaint.
                    if cse == "hiddenReady" and fd._cdStateChargeBoundSid ~= sid2 then
                        fd._cdStateChargeBoundSid = sid2
                        ns.WatchCdStateChargeIfEnabled(frame)
                    end
                    return
                end
                -- Query cooldown on the live override (e.g. Shimmer, not
                -- Blink) so charge-based replacements report correctly.
                local liveSid = sid2
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
                end
                local cseInfo = C_Spell.GetSpellCooldown(liveSid)
                local onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
                if cse == "pixelGlowReady" or cse == "buttonGlowReady" then
                    -- Plain CD Ready Glow: cooldown state only, decided right here
                    -- -- no usability reads, no deferral, no events for genuine
                    -- Blizzard frames (Blizzard calls SetDesaturated on them at
                    -- every cd transition, re-firing this hook). EUI's own custom
                    -- frames (racials / trinkets / potions / custom spells) instead
                    -- drive desaturation via SetDesaturation(float), which does NOT
                    -- trigger this SetDesaturated hook -- so on those the glow would
                    -- never re-evaluate and would stay lit through the whole
                    -- cooldown. Register just those for the event-driven cooldown
                    -- watch (its loop handles plain variants too); Blizzard frames
                    -- keep the zero-event path.
                    if (frame._isRacialFrame or frame._isTrinketFrame or frame._isPresetFrame
                        or frame._isItemPresetFrame or frame._isCustomSpellFrame)
                        and ns.CDGlowWatch then
                        ns.CDGlowWatch(frame)
                    end
                    -- Pool reassignment: glow state inherited from a previous
                    -- spell on this frame belongs to that spell -- reset now.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopCdGlow(fd)
                            fd._cdStateGlowOn = false
                        end
                    end
                    if not onCD then
                        -- The proc and active-state glows share this overlay
                        -- and have priority: ns.StartCdGlow never starts over
                        -- them (only a Blackout, on its own overlay, shows
                        -- beside them) and records the glow as owed instead.
                        if fd.glowOverlay and not fd._cdStateGlowOn then
                            local style = ns.CdReadyGlowStyle(cse, ss2)
                            local cr, cg, cb = ns.CdReadyGlowColor(style, ss2)
                            fd._cdStateGlowOn = ns.StartCdGlow(fd, style, cr, cg, cb, ns.CdReadyGlowAlpha(ss2)) ~= nil
                        end
                    elseif fd._cdStateGlowOn then
                        ns.StopCdGlow(fd)
                        fd._cdStateGlowOn = false
                    end
                elseif cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable"
                    or cse == "glowOnCD" then
                    -- Resource Aware CD Ready Glow: also requires the spell to
                    -- be castable (resources/form/lockout). Glow (On CD): the plain
                    -- Ready rule inverted -- glows for the whole cooldown.
                    -- Pool reassignment reset, same as the plain variants.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopCdGlow(fd)
                            fd._cdStateGlowOn = false
                        end
                    end
                    -- Track this frame for the event-driven re-evaluation loop:
                    -- every Resource Aware glow, and On CD glows on EUI's custom
                    -- frames (see the plain branch). The loop's events stay
                    -- unregistered until the first watch, so the whole system is
                    -- inert unless such a glow is actually configured somewhere.
                    if ns.CDGlowWatch and (cse ~= "glowOnCD" or frame._isRacialFrame
                        or frame._isTrinketFrame or frame._isPresetFrame
                        or frame._isItemPresetFrame or frame._isCustomSpellFrame) then
                        ns.CDGlowWatch(frame)
                    end
                    -- Defer the actual decision by one frame, same as
                    -- hiddenOnCD/hiddenReady above: SetDesaturated fires inside
                    -- Blizzard's secure CDM chain where C_Spell.IsSpellUsable can
                    -- return stale values and a GCD can read as a real cooldown
                    -- (lighting Glow (On CD) on a ready spell). The OnUpdate script
                    -- is installed ONCE per frame object -- this hook fires on every
                    -- repaint (range/resource tints), so the per-fire work must stay
                    -- at plain field writes, never closure creation.
                    local pending = fd._cdStateGlowPending
                    if not pending then
                        pending = CreateFrame("Frame")
                        pending:Hide()
                        fd._cdStateGlowPending = pending
                        pending:SetScript("OnUpdate", function(self)
                            self:Hide()
                            -- Re-read the cooldown now instead of trusting a value
                            -- sampled inside the secure chain a frame ago (GCD
                            -- transients misreport isActive there).
                            local ci = C_Spell.GetSpellCooldown(self.sid)
                            local pOnCD = ci and ci.isActive and not ci.isOnGCD
                            local shouldGlow
                            if self.cse == "glowOnCD" then
                                shouldGlow = pOnCD
                            else
                                local isUsable
                                if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                    -- Loading-screen settle window: IsSpellUsable is not
                                    -- trustworthy yet. Glow from cooldown state alone
                                    -- (pre-usability behavior); the queued post-settle
                                    -- pass re-evaluates with real data.
                                    isUsable = true
                                else
                                    -- nil = API has no data for this spell -> treat as
                                    -- not usable; a later event re-evaluates.
                                    isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(self.sid)
                                end
                                shouldGlow = (not pOnCD) and (isUsable == true)
                            end
                            if shouldGlow then
                                -- A live proc or active-state glow owns the
                                -- shared overlay: ns.StartCdGlow lights only a
                                -- Blackout beside it.
                                if fd.glowOverlay and not fd._cdStateGlowOn then
                                    local style = ns.CdReadyGlowStyle(self.cse, self.ss2)
                                    local cr, cg, cb = ns.CdReadyGlowColor(style, self.ss2)
                                    fd._cdStateGlowOn = ns.StartCdGlow(fd, style, cr, cg, cb, ns.CdReadyGlowAlpha(self.ss2)) ~= nil
                                end
                            elseif fd._cdStateGlowOn then
                                ns.StopCdGlow(fd)
                                fd._cdStateGlowOn = false
                            end
                        end)
                    end
                    pending.cse = cse
                    pending.sid = liveSid
                    pending.ss2 = ss2
                    pending:Show()
                end
            end)
        end

        -- Desaturate When Not Active: additive hook on SetDesaturated AND
        -- SetDesaturation (Blizzard re-saturates ready icons via either, on CD-end
        -- and ticks). Re-applies desaturation whenever the spell is NOT in its
        -- active state, read LIVE from the swipe color (fd._wasActive is stale on
        -- some falloffs, e.g. DoT expiry); secret arg never read, guarded against
        -- fighting the swipe block's own SetDesaturated. ZERO-COST WHEN UNUSED: the
        -- first line is a flag check (ns._cdmAnyDesatNotActive, set only when a
        -- spell actually uses the setting), so disabled users pay nothing.
        if fd.tex and not fd._desatNotActiveHooked then
            fd._desatNotActiveHooked = true
            local function _maintainDesat()
                if not ns._cdmAnyDesatNotActive then return end
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
                if not (ss2 and ss2.desatNotActive) then
                    -- Setting turned off: re-saturate if WE greyed this icon, so it
                    -- doesn't stay desaturated until the next cooldown event.
                    if fd._desatNA then
                        fd._isProcessingOverride = true
                        fd.tex:SetDesaturated(false)
                        fd._isProcessingOverride = false
                        fd._desatNA = nil
                    end
                    return
                end
                local isAct = false
                local sc = frame.cooldownSwipeColor
                if sc and type(sc) ~= "number" and sc.GetRGBA then
                    local r = sc:GetRGBA()
                    if type(r) == "number" and not issecretvalue(r) then isAct = (r ~= 0) end
                end
                if isAct then return end
                fd._isProcessingOverride = true
                fd.tex:SetDesaturated(true)
                fd._desatNA = true
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", _maintainDesat)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", _maintainDesat)
            end
        end

        -- Keep Colored (On CD): additive hook on SetDesaturated/SetDesaturation,
        -- mirror of the block above. Desaturating on cooldown is BLIZZARD's own
        -- behaviour (greys the icon every CD tick), so suppressing it means
        -- re-saturating right after each call rather than skipping our own.
        -- Deliberately does NOT clear fd._desatNA: Desaturate When Not Active is the
        -- more specific setting and wins when both are on (bail below); this one
        -- only removes the implicit cooldown grey. Zero-cost when unused (same shape as above).
        if fd.tex and not fd._noDesatOnCDHooked then
            fd._noDesatOnCDHooked = true
            local function _keepColored()
                if not ns._cdmAnyNoDesatOnCD then return end
                if fd._isProcessingOverride then return end
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                if not sid2 or not bk2 then return end
                local ss2 = ResolveSpellSettings(frame, sid2, false)
                if not (ss2 and ss2.noDesatOnCD) then return end
                if ss2.desatNotActive then return end
                fd._isProcessingOverride = true
                fd.tex:SetDesaturated(false)
                if fd.tex.SetDesaturation then fd.tex:SetDesaturation(0) end
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", _keepColored)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", _keepColored)
            end
        end

        -- Audio Effect on CD Ready (cd/utility per-icon) is driven purely by the
        -- authoritative SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES events via
        -- WatchCdReadySoundIfEnabled (called from DecorateFrame), deliberately NOT
        -- off a SetDesaturated visual hook: that hook fires at repaint moments
        -- unrelated to the real cooldown and sampled a transient GCD race
        -- (isActive=true/isOnGCD=false) that false-fired the sound.
    end

    hookFrameData[frame] = fd
    return fd
end

-------------------------------------------------------------------------------
--  CategorizeFrame
-------------------------------------------------------------------------------
local function CategorizeFrame(frame, viewerBarKey)
    local displaySID, baseSID = ResolveFrameSpellID(frame)
    if not displaySID or displaySID <= 0 then return nil, nil, nil end

    -- Lazy route resolution: ResolveCDIDToBar handles cache lookup,
    -- diversion-set match, and viewer-default fallback (defaultBar =
    -- viewerBarKey, the viewer this frame came from). Always returns a
    -- valid bar key for any non-nil cdID.
    local cdID = frame.cooldownID
    local claimBarKey = ResolveCDIDToBar(cdID, viewerBarKey)
    if claimBarKey then
        local claimBD = barDataByKey[claimBarKey]
        local claimType = claimBD and claimBD.barType or claimBarKey
        local viewerIsBuff = (viewerBarKey == "buffs")
        local claimIsBuff  = (claimType == "buffs" or claimType == "custom_buff")
        -- Same family always routes. A BUFF viewer resolving to a CD/util bar is
        -- also honored: that only happens for an explicit HOSTED buff (the sole
        -- writer of a CD/util bar key into _divertedSpellsBuff is the hosted-buff
        -- pass in RebuildSpellRouteMap), so the buff's real frame reparents onto
        -- the CD/util bar just like on a buff bar. A CD viewer -> buff bar is still
        -- rejected (falls through) -- that direction is never wanted.
        if viewerIsBuff == claimIsBuff or viewerIsBuff then
            return claimBarKey, displaySID, baseSID
        end
        -- Type mismatch (CD viewer routing to a buff bar). Under the 1-spell-per-bar
        -- rule this can't happen via picker claims, but legacy data could trigger
        -- it. Fall through to the viewer's default bar so the frame still renders.
    end
    return viewerBarKey, displaySID, baseSID
end

I.CategorizeFrame, I.DecorateFrame = CategorizeFrame, DecorateFrame
I.broken = false
