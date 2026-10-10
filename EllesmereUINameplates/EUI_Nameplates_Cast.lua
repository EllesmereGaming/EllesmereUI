if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Cast.lua
--
--  NameplateFrame: the cast bar, kick tick, interrupts and the spellcast events.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, type = pairs, type
local UnitName = UnitName
local UnitIsUnit = UnitIsUnit
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetTime = GetTime
local Enum = Enum
local ComputeCastBarTint = ns.ComputeCastBarTint

local defaults, GetCastBarHeight, GetCastScale = I.defaults, I.GetCastBarHeight, I.GetCastScale
local GetKickTickColor, GetKickTickEnabled = I.GetKickTickColor, I.GetKickTickEnabled
local GetShowClassPower, GetTargetScale = I.GetShowClassPower, I.GetTargetScale
local PANDEMIC_GLOW_STYLES, GetActiveKickSpell = I.PANDEMIC_GLOW_STYLES, I.GetActiveKickSpell
local NotifyCastEnded, NotifyCastStarted = I.NotifyCastEnded, I.NotifyCastStarted
local UpdateClassPowerOnPlate, _fallbackPlates = I.UpdateClassPowerOnPlate, I._fallbackPlates
local castFallbackFrame, NameplateFrame = I.castFallbackFrame, I.NameplateFrame

local classPowerType
I.classPowerTypeSetters[#I.classPowerTypeSetters + 1] = function(v) classPowerType = v end
local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

function NameplateFrame:UpdateImportantCastGlow(spellID)
    local cfg = p or defaults
    local enabled = cfg.importantCastGlow
    if enabled == nil then enabled = defaults.importantCastGlow end
    if not enabled then self:ClearImportantCastGlow(); return end

    if not C_Spell or not C_Spell.IsSpellImportant then
        self:ClearImportantCastGlow(); return
    end

    if not self._importantCastOverlay then
        local ov = CreateFrame("Frame", nil, self.cast)
        ov:SetAllPoints(self.cast)
        ov:SetFrameLevel(self.cast:GetFrameLevel() + 5)
        ov:EnableMouse(false)
        self._importantCastOverlay = ov
    end

    local Glows = EllesmereUI.Glows

    local style = cfg.importantCastGlowStyle or defaults.importantCastGlowStyle or 1
    if type(style) ~= "number" or style < 1 or style > #PANDEMIC_GLOW_STYLES then style = 1 end
    local c = cfg.importantCastGlowColor or defaults.importantCastGlowColor or { r = 1, g = 0.2, b = 0.2 }
    local bgColor = cfg.importantCastGlowBackgroundColor or defaults.importantCastGlowBackgroundColor or { r = 0, g = 0, b = 0 }
    -- One scratch spec for every plate: StartSpecGlow reads it synchronously.
    local spec = ns._impCastGlowSpec
    if not spec then spec = {}; ns._impCastGlowSpec = spec end
    spec.style = ns.NP_TO_SHARED_GLOW[style] or 1
    spec.r, spec.g, spec.b = Glows.ResolveColor(cfg.importantCastGlowColorMode or "custom", c.r, c.g, c.b)
    spec.lines = cfg.importantCastGlowLines or defaults.importantCastGlowLines
    spec.thickness = cfg.importantCastGlowThickness or defaults.importantCastGlowThickness
    spec.speed = cfg.importantCastGlowSpeed or defaults.importantCastGlowSpeed
    spec.bg = (cfg.importantCastGlowBackground == true) or nil
    spec.bgR, spec.bgG, spec.bgB = bgColor.r, bgColor.g, bgColor.b
    local pW, pH = self.cast:GetWidth(), self.cast:GetHeight()
    if pW < 5 then pW = 100 end
    if pH < 5 then pH = 14 end
    -- Restarts only when the setting or the bar size changed.
    Glows.StartSpecGlow(self._importantCastOverlay, spec, pW, pH, "bar")
    self._importantGlowActive = true

    -- SetAlphaFromBoolean handles the secret boolean taint-free.
    -- Important = alpha 1 (glow visible), not important = alpha 0 (glow hidden).
    self._importantCastOverlay:Show()
    local ok, isImportant = pcall(C_Spell.IsSpellImportant, spellID or 0)
    if ok then
        self._importantCastOverlay:SetAlphaFromBoolean(isImportant)
    else
        self._importantCastOverlay:SetAlpha(0)
    end
end

function NameplateFrame:ClearImportantCastGlow()
    if self._importantGlowActive and self._importantCastOverlay then
        EllesmereUI.Glows.StopAllGlows(self._importantCastOverlay)
        self._importantCastOverlay:SetAlpha(0)
        self._importantCastOverlay:Hide()
        self._importantGlowActive = false
    end
end

function NameplateFrame:UpdateCast()
    if not self.unit then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(self.unit)
    local isChannel = false
    local isEmpowered = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(self.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        if not self._interrupted then
            self.cast:Hide()
        end
        self:ApplyNameVisibility()
        self.castTimer:SetText("")
        if self.isCasting then
            if self._castFallback then
                self._castFallback = nil
                _fallbackPlates[self] = nil
                I.fallbackCastCount = I.fallbackCastCount - 1
                if I.fallbackCastCount <= 0 then I.fallbackCastCount = 0; castFallbackFrame:Hide() end
            end
            NotifyCastEnded(self)
        end
        self.isCasting = false
        self._castTex = nil
        self._castDirtyFull = nil
        self:HideKickTick()
        self:ClearImportantCastGlow()
        self:ApplyScale()
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
        return
    end

    if self._interrupted then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
    end

    -- FAST PATH: on DELAYED/UPDATE events (not START), the icon, name, target, and glow
    -- haven't changed; only duration needs updating. _castDirtyFull is set by
    -- UNIT_SPELLCAST_START/CHANNEL_START/EMPOWER_START.
    local isFullSetup = self._castDirtyFull or not self.isCasting
    self._castDirtyFull = nil

    if isFullSetup then
        self.cast:Show()
        self:ApplyNameVisibility()
        -- Icon and name MUST describe the SAME cast: both come from this UnitCastingInfo/
        -- UnitChannelInfo snapshot. The icon uses the live texture (possibly SECRET --
        -- SetTexture accepts secrets natively), never a cached/leftover icon.
        if type(texture) ~= "nil" then
            self.castIcon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            -- Texture genuinely absent (rare): fall back to THIS cast's spell icon. pcall
            -- guards an invalid/0/unknown spellID; iconID feeds SetTexture, never branched on.
            local okInfo, info = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(info) == "table" then
                self.castIcon:SetTexture(info.iconID)
            else
                self.castIcon:SetTexture(nil)
            end
        else
            self.castIcon:SetTexture(nil)
        end
        self:UpdateCastText(name)
        self.castTimer:SetShown(self._showCastTimer)

        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        self._kickProtected = kickProtected
        -- Cache the game's "important" flag for the cast bar colour. May be SECRET, so it is
        -- stored raw and only fed to a boolean-curve evaluator, never branched on. pcall
        -- guards a 0/invalid spellID. Persists across interruptible flips/kick ticker reuse.
        self._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
            if impOK then self._castImportant = imp end
        end
        local cfg = p or defaults
        local unintColor = cfg.castBarUninterruptible or defaults.castBarUninterruptible
        if self._blizzCastArt then
            -- Blizzard Style: the overlay IS the stock grey fill art (painted
            -- white; the user's colour stays if that atlas never seated), and
            -- the fill atlas follows the cast kind.
            if self._blizzShieldFill then
                self.castBarOverlay:SetVertexColor(1, 1, 1)
            else
                self.castBarOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
            end
            self._blizzCastLastKind = isChannel and "channel" or "cast"
            ns.NP_SetBlizzCastFill(self, self._blizzCastLastKind)
        else
            self.castBarOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
        end
        self.castShieldFrame:Show()
        self:ApplyCastColor(kickProtected)
    end
    
    if UnitCastingDuration and self.cast.SetTimerDuration then
        if isChannel then
            local castDuration
            -- Empowered channel duration first (Evoker empower spells): normal UnitChannelDuration
            -- can return nil during the empower phase, leaving the bar unticked despite a name.
            if UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
                if castDuration then isEmpowered = true end
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
            if castDuration then
                self.cast:SetReverseFill(false)
                -- Empowered channels fill forward (elapsed time / stages);
                -- normal channels fill backward (remaining time).
                local direction = isEmpowered
                    and Enum.StatusBarTimerDirection.ElapsedTime
                    or Enum.StatusBarTimerDirection.RemainingTime
                self.cast:SetTimerDuration(castDuration, nil, direction)
                if not self.isCasting then NotifyCastStarted(self) end
                self.isCasting = true
            end
        else
            local castDuration = UnitCastingDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            end
            if not self.isCasting then NotifyCastStarted(self) end
            self.isCasting = true
        end
    else
        if not self.isCasting then
            self.isCasting = true
            self._castFallback = true
            _fallbackPlates[self] = true
            I.fallbackCastCount = I.fallbackCastCount + 1
            castFallbackFrame:Show()
            NotifyCastStarted(self)
        end
    end
    -- Cast kind for the STOP handler (UNIT_SPELLCAST_STOP): cached here rather than
    -- read back, since the read is what can go stale/secret at the stop edge.
    self._castIsChannel = isChannel
    if isFullSetup then
        self._kickGeoDirty = nil
        self:ApplyScale()
        self:UpdateKickTick(kickProtected, isChannel, isEmpowered)
        self:UpdateImportantCastGlow(castSpellID)
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
    elseif self._kickGeoDirty then
        -- Cast timing changed mid-cast (delay/channel/empower update): re-derive kick
        -- geometry from the cached cast identity
        self._kickGeoDirty = nil
        self:UpdateKickTick(self._kickProtected, self._kickIsChannel, self._kickIsEmpowered)
    end
end
-- Smooth scale transitions: one shared OnUpdate eases every plate whose displayed scale
-- (_curScale) differs from its destination (_destScale). Driver hides itself the instant no
-- plate is animating, so idle costs nothing; at target/cast scale 100 dest stays 1 and
-- ApplyScale snaps without enrolling.
ns._scaleAnim = {}  -- [plate] = true while its scale is easing
do
    local SPEED = 11     -- exponential approach rate (higher = snappier)
    local SNAP  = 0.004  -- within this of dest -> finish and drop from set
    local anim  = ns._scaleAnim
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function(_, elapsed)
        -- Frame-rate independent ease: same settle time at any FPS.
        local t = 1 - math.exp(-SPEED * elapsed)
        for plate in pairs(anim) do
            local cur  = plate._curScale or 1
            local dest = plate._destScale or 1
            local nv = cur + (dest - cur) * t
            if nv - dest < SNAP and dest - nv < SNAP then
                nv = dest
                anim[plate] = nil
            end
            plate._curScale = nv
            plate:SetScale(nv)
            -- The held "Interrupted" flash keeps the bar visible after isCasting clears; it must ride the shrink-back too.
            if (plate.isCasting or plate._interrupted) and ns.RefreshCastOverlay then ns.RefreshCastOverlay(plate) end
        end
        if not next(anim) then driver:Hide() end
    end)
    ns._ScaleDriverShow = function() driver:Show() end
end
function NameplateFrame:ApplyScale()
    local base = 1
    if self.unit and UnitIsUnit(self.unit, "target") then
        local ts = GetTargetScale() / 100
        if ts ~= 1 then base = ts end
    end
    local cs = GetCastScale() / 100
    local dest = base
    if self.isCasting and cs ~= 1 then dest = base * cs end
    self._destScale = dest
    local cur = self._curScale
    if cur == nil or (dest - cur < 0.004 and cur - dest < 0.004) then
        -- Fresh/recycled plate, or already at the destination: snap instantly.
        self._curScale = dest
        ns._scaleAnim[self] = nil
        self:SetScale(dest)
    else
        -- Ease toward the new destination via the shared OnUpdate driver.
        ns._scaleAnim[self] = true
        ns._ScaleDriverShow()
    end
    -- Lifted cast bar renders outside this plate's scale chain; keep its container pinned to the plate's effective scale.
    if ns.RefreshCastOverlay then ns.RefreshCastOverlay(self) end
end
function NameplateFrame:ApplyCastColor(uninterruptible)
    local cfg = p or defaults
    local kickReadyTint = cfg.interruptReady or defaults.interruptReady
    local normalCastTint = cfg.castBar or defaults.castBar
    -- Blizzard Style: the fill atlas is its own colour, so the normal and
    -- uninterruptible tints are white; the kick-ready and Important tints
    -- still layer on top exactly as before. No per-call allocation.
    local blizzCast = self._blizzCastArt
    if blizzCast then
        if not ns._npWhite then ns._npWhite = { r = 1, g = 1, b = 1 } end
        normalCastTint = ns._npWhite
    end
    -- Important Cast Color (opt-in): a cast the game flags important shows the Important
    -- colour instead of Interruptible. The flag may be SECRET, so blend per channel via
    -- EvaluateColorValueFromBoolean (ifTrue=Important, ifFalse=Interruptible), never branch on
    -- it. Interrupt-on-CD still wins: ComputeCastBarTint layers the kick-ready tint over any
    -- base tint. Uninterruptible casts keep their look (overlay on top).
    local importantOn = cfg.importantCastColorEnabled
    if importantOn == nil then importantOn = defaults.importantCastColorEnabled end
    if importantOn and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local imp = cfg.castBarImportant or defaults.castBarImportant
        local isImp = self._castImportant
        if type(isImp) == "nil" then isImp = false end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        -- Scratch table (same pattern as _dispelScratch): runs per cast event per plate, a fresh color table per call was pure GC churn.
        local sc = ns._castImpScratch
        if not sc then sc = {}; ns._castImpScratch = sc end
        sc.r = ev(isImp, imp.r, normalCastTint.r)
        sc.g = ev(isImp, imp.g, normalCastTint.g)
        sc.b = ev(isImp, imp.b, normalCastTint.b)
        normalCastTint = sc
    end
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, normalCastTint)

    -- Match the base cast fill to uninterruptible casts so plate opacity
    -- doesn't reveal the interruptible color underneath the overlay.
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local unintColor = blizzCast and ns._npWhite or (cfg.castBarUninterruptible or defaults.castBarUninterruptible)
        -- The settings-refresh callers pass the stored _kickProtected stamp,
        -- which is nil until the first cast event -- and a nil reaching the
        -- fold throws. type() is the secret-legal nil test (a plain == nil
        -- compare throws on a secret boolean), same idiom as the Important
        -- Cast block above.
        local isUnint = uninterruptible
        if type(isUnint) == "nil" then isUnint = false end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        cr = ev(isUnint, unintColor.r, cr)
        cg = ev(isUnint, unintColor.g, cg)
        cb = ev(isUnint, unintColor.b, cb)
    end
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    -- Shield icon is opt-out: when disabled it never shows, even on uninterruptible casts. The
    -- setting is a clean boolean, so it gates the (possibly SECRET) flag without evaluating it.
    local showShield = true
    if cfg.castBarShieldEnabled ~= nil then showShield = cfg.castBarShieldEnabled end
    if self.castBarOverlay.SetAlphaFromBoolean then
        self.castBarOverlay:SetAlphaFromBoolean(uninterruptible)
        if showShield then
            self.castShieldFrame:SetAlphaFromBoolean(uninterruptible)
        else
            self.castShieldFrame:SetAlpha(0)
        end
    else
        local a = uninterruptible and 1 or 0
        self.castBarOverlay:SetAlpha(a)
        self.castShieldFrame:SetAlpha(showShield and a or 0)
    end
end
function NameplateFrame:HideKickTick()
    self.kickPositioner:Hide()
    self.kickMarker:Hide()
    self.kickReadyFill:Hide()
    if self._kickTicker then
        self._kickTicker:Cancel()
        self._kickTicker = nil
    end
end
function NameplateFrame:UpdateKickTick(kickProtected, isChannel, isEmpowered)
    -- Two independent CLEAN toggles drive this geometry: the visible tick (kickTickEnabled)
    -- and the interrupt-ready mid-cast fill (interruptMidCastEnabled). Either needs the
    -- positioner/marker StatusBars below; each visible element is gated on its own toggle.
    local tickOn = GetKickTickEnabled()
    local midOn = defaults.interruptMidCastEnabled
    if p and p.interruptMidCastEnabled ~= nil then midOn = p.interruptMidCastEnabled end
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        self:HideKickTick()
        return
    end
    -- kickProtected is a SECRET boolean: never branch on it. Store it and apply visibility via
    -- SetAlphaFromBoolean after setup. isChannel/isEmpowered cached too (cooldown watcher
    -- re-setups from these).
    self._kickProtected = kickProtected
    self._kickIsChannel = isChannel
    self._kickIsEmpowered = isEmpowered
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    -- Midnight path: use secret duration objects
    if UnitCastingDuration and self.cast.SetTimerDuration then
        local castDuration
        if isChannel then
            if isEmpowered and UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
        else
            castDuration = UnitCastingDuration(self.unit)
        end
        if not castDuration then
            self:HideKickTick()
            return
        end
        local totalDur = castDuration:GetTotalDuration()
        local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if not interruptCD then
            self:HideKickTick()
            return
        end
        -- Size the StatusBars to match the cast bar (positioner uses SetPoint("CENTER"), not SetAllPoints)
        local castH = GetCastBarHeight()
        local barW = self.cast:GetWidth()
        self.kickPositioner:SetSize(barW, castH)
        self.kickPositioner:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetSize(barW, castH)
        -- Initial PAIRED snapshot: the tick's position is positioner(elapsed) +
        -- marker(kick CD remaining), which equals the fixed "kick ready here" point only when
        -- both are sampled at the same instant. RefreshKickTick re-pins the pair on every
        -- cooldown event. NEVER update one without the other -- a marker-only refresh drifts
        -- the tick left.
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
        self.kickMarker:SetValue(interruptCD:GetRemainingDuration())
        -- Apply color
        local kr, kg, kb = GetKickTickColor()
        self.kickTick:SetColorTexture(kr, kg, kb, 1)
        -- Handle channel vs cast fill direction. Empowered channels fill
        -- forward (like a normal cast), so treat them as non-channel here.
        if isChannel and not isEmpowered then
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
            -- SetStatusBarTexture unsnap hook will NOT re-fire (caches per StatusBar frame).
            -- Re-disable snap so positioner(elapsed) + marker(CD remaining) stays an exact
            -- float and the tick holds still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("RIGHT", self.kickPositioner:GetStatusBarTexture(), "LEFT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
            -- Reverse fill (draining channel): the kick-ready point is the
            -- marker texture LEFT edge; the "kick available" window runs from
            -- the channel end (bar left) to that point. Not-in-time pushes the
            -- marker edge past the left edge, crossing the anchors to zero width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.cast, "LEFT", 0, 0)
            self.kickReadyFill:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
        else
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the reverse
            -- branch) so the summed elapsed+remaining edge is exact and the tick stays still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("LEFT", self.kickPositioner:GetStatusBarTexture(), "RIGHT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            -- Standard fill (cast/empowered channel): the kick-ready point is the marker
            -- texture RIGHT edge; the "kick available" window runs from it to cast end (bar
            -- right). Not-in-time pushes the marker edge past the right edge, zeroing width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            self.kickReadyFill:SetPoint("RIGHT", self.cast, "RIGHT", 0, 0)
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility. Its alpha (the
        -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
        -- above runs when the tick OR the fill is enabled; SetShown gates each independently.
        local mc = (p and p.interruptMidCastColor) or defaults.interruptMidCastColor
        self.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
        self.kickTick:SetShown(tickOn)
        self.kickReadyFill:SetShown(midOn)
        -- Compute initial tick alpha immediately (avoids split-second delay
        -- from waiting for the first ticker fire at 0.1s).
        if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
            local kickReady = interruptCD:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            self.kickTick:SetAlpha(alpha)
            self.kickReadyFill:SetAlpha(alpha)
        else
            self.kickTick:SetAlpha(0)
            self.kickReadyFill:SetAlpha(0)
        end
        -- Ticker: tick ALPHA only at 10fps (kick-ready x interruptibility secret combine). Bar
        -- values are re-pinned as a PAIR by RefreshKickTick on cooldown events, not here.
        if self._kickTicker then self._kickTicker:Cancel() end
        -- Self-identifying ticker: a superseded ticker cancels ITSELF rather than
        -- calling HideKickTick, which would cancel its successor.
        local myTicker
        myTicker = C_Timer.NewTicker(0.1, function()
            if self._kickTicker ~= myTicker then
                myTicker:Cancel()
                return
            end
            if not self.isCasting or not self.unit then
                self:HideKickTick()
                return
            end
            -- activeKickSpell can go nil mid-cast if a spec/talent change fires SPELLS_CHANGED
            -- and the new spec has no kick learned. Bail rather than pass nil to C_Spell.
            if not GetActiveKickSpell() then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans, chain EvaluateColorValueFromBoolean calls to combine.
            local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
            if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
                local kickReady = icd:IsZero()
                local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
                self.kickTick:SetAlpha(alpha)
                self.kickReadyFill:SetAlpha(alpha)
            end
        end)
        self._kickTicker = myTicker
    else
        -- API not available; hide tick
        self:HideKickTick()
    end
end
-- Light per-cooldown-event refresh: bar values + tick alpha only; geometry (sizes, anchors,
-- fill styles, colors) is cast-identity work done once by UpdateKickTick. CRITICAL: the tick
-- position is positioner(elapsed) + marker(remaining), the true "kick ready here" point only
-- when BOTH snapshots are taken at the same instant -- re-pinning the marker alone drifts the
-- tick left. Always re-pin both together.
function NameplateFrame:RefreshKickTick()
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not icd then
        -- Transient read miss during an ongoing cast: skip this refresh and keep the current
        -- tick/fill. Hiding here would make the tick and kick-ready bar blink through the
        -- rotation. Genuine cast-end is handled by cast-stop/interrupt paths.
        return
    end
    if UnitCastingDuration and self.unit then
        local castDuration
        if self._kickIsChannel then
            if self._kickIsEmpowered and UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
        else
            castDuration = UnitCastingDuration(self.unit)
        end
        if not castDuration then
            -- Transient read miss (see above): skip, do not hide.
            return
        end
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    end
    self.kickMarker:SetValue(icd:GetRemainingDuration())
    if icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(icd:IsZero(), 0, interruptible)
        self.kickTick:SetAlpha(alpha)
        self.kickReadyFill:SetAlpha(alpha)
    end
end
function NameplateFrame:ShowInterrupted(interrupterGUID)
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            I.fallbackCastCount = I.fallbackCastCount - 1
            if I.fallbackCastCount <= 0 then I.fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ApplyScale()

    -- If the interrupted flash effect is disabled, end the cast like a normal
    -- stop (hide the bar) without the flash + held "Interrupted" text.
    local flashOn = defaults.interruptedFlashEnabled
    if p and p.interruptedFlashEnabled ~= nil then flashOn = p.interruptedFlashEnabled end
    if not flashOn then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end

    self._interrupted = true
    self.cast:SetReverseFill(false)
    self.cast:SetMinMaxValues(0, 1)
    self.cast:SetValue(1)
    if self._blizzCastArt then
        -- Blizzard Style: the stock interrupted fill art, untinted.
        ns.NP_SetBlizzCastFill(self, "interrupted")
        self.cast:GetStatusBarTexture():SetVertexColor(1, 1, 1)
    else
        local fc = (p and p.interruptedFlashColor) or defaults.interruptedFlashColor
        self.cast:GetStatusBarTexture():SetVertexColor(fc.r, fc.g, fc.b)
    end

    -- GetPlayerInfoByGUID accepts the event's SECRET interrupter GUID and may
    -- return a SECRET name/class. Keep those values opaque until native sinks.
    local interrupterName
    local interrupterClass
    if type(interrupterGUID) ~= "nil" then
        local _, class, _, _, _, name = GetPlayerInfoByGUID(interrupterGUID)
        interrupterClass = class
        interrupterName = name
        if type(interrupterName) == "nil" then
            -- Fallback for a NON-player interrupter GUID (pet or NPC): GetPlayerInfoByGUID
            -- only resolves players, so pull the name from the GUID's live unit token instead.
            -- Non-players have no class, so interrupterClass stays nil and the class-color path
            -- is skipped. A SECRET GUID resolves to a SECRET token/name; both pass straight to
            -- SetFormattedText as display args, so the name still shows. type() is the only legal check.
            local token = UnitTokenFromGUID(interrupterGUID)
            if type(token) ~= "nil" then
                interrupterName = UnitName(token)
            end
        end
    end
    local cfg = p or defaults
    local useClassColor = defaults.castTargetClassColor
    if cfg.castTargetClassColor ~= nil then useClassColor = cfg.castTargetClassColor end
    local castNameColor = cfg.castNameColor or defaults.castNameColor
    local interrupterColor
    if useClassColor and type(interrupterClass) ~= "nil" and C_ClassColor then
        interrupterColor = C_ClassColor.GetClassColor(interrupterClass)
    end
    if interrupterColor then
        self.castName:SetTextColor(interrupterColor:GetRGB())
    else
        self.castName:SetTextColor(castNameColor.r, castNameColor.g, castNameColor.b, 1)
    end

    -- Show the interrupter inline as "Interrupted (Name)" in the single cast-name
    -- FontString; the cast-target / timer slots are cleared during the flash.
    local hasInterrupter = type(interrupterName) ~= "nil"
    local castW = self.cast:GetWidth()
    if castW and castW > 0 then
        local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
        self.castName:SetWidth(hasInterrupter and math.max(castW - 8, 20) or castW * cnWPct / 100)
    end

    local interruptedText = (EllesmereUI.L("Interrupted")) or "Interrupted"
    if hasInterrupter then
        -- The base FontString color carries SECRET class RGB; only the clean
        -- localized label/punctuation uses an inline profile-color escape.
        local nameHex = string.format("ff%02x%02x%02x",
            math.floor(castNameColor.r * 255 + 0.5), math.floor(castNameColor.g * 255 + 0.5),
            math.floor(castNameColor.b * 255 + 0.5))
        self.castName:SetFormattedText("|c" .. nameHex .. "%s (|r%s|c" .. nameHex .. ")|r",
            interruptedText, interrupterName)
    else
        self.castName:SetText(interruptedText)
    end

    self.castTarget:SetText("")
    self.castTarget:Hide()
    self.castTimer:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.cast:Show()
    self:ApplyNameVisibility()

    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end

    self._interruptTimer = C_Timer.NewTimer(1.0, function()
        if self._interrupted then
            self._interrupted = nil
            self._interruptTimer = nil
            self.cast:Hide()
            self:ApplyNameVisibility()
        end
    end)
end
function NameplateFrame:ShowCastLockout()
    if not ns.ShowCastLockoutAsCrowdControl() or not self.unit then return end
    local now = GetTime()
    local lockout = {
        icon = ns.CAST_LOCKOUT_ICON,
        start = now,
        duration = ns.DEFAULT_CAST_LOCKOUT_DURATION,
        expires = now + ns.DEFAULT_CAST_LOCKOUT_DURATION,
    }
    self._castLockout = lockout
    if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    C_Timer.After(ns.DEFAULT_CAST_LOCKOUT_DURATION, function()
        if self._castLockout ~= lockout or GetTime() < lockout.expires then return end
        self._castLockout = nil
        if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    -- If the mob dies while the "Interrupted" flash is held up, Blizzard's death animation
    -- scales the still-shown cast bar and it looks warped, so tear the flash down on death.
    -- Gated on _interrupted first, so UnitIsDeadOrGhost only runs during the flash window.
    if self._interrupted and self.unit and UnitIsDeadOrGhost(self.unit) then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
        self.cast:Hide()
        self:ApplyNameVisibility()
    end
    self:MarkHealthDirty()
end
-- Max health changed: drop the cached max so the next paint re-derives it and
-- re-pushes the bar bounds (per-paint SetMinMaxValues is gone from the lean
-- path; bounds ride this event, exactly like Blizzard's CompactUnitFrame).
function NameplateFrame:UNIT_MAXHEALTH()
    self._maxHPValid = nil
    self:MarkHealthDirty()
end
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    -- The dedicated absorb edge: force the next paint onto the full absorb
    -- path so the lean-gate flag re-derives from a fresh read.
    self._absorbEdge = true
    self:MarkHealthDirty()
end
-- Health paint coalescer (Blizzard's CompactUnitFrame shape: healthDirty is
-- drained once per frame at most). Health, max and absorb edges for one mob
-- land together in a server batch, and only the last paint of a frame ever
-- renders. Marks are a set write; the drain frame is hidden whenever the set
-- is empty (zero cost idle) and paints inside the same frame the events
-- arrived in, so nothing is displayed later than before. On ns (200-cap).
ns._npHvDirty = ns._npHvDirty or {}
ns._npHvFlush = ns._npHvFlush or CreateFrame("Frame")
ns._npHvFlush:Hide()
ns._npHvFlush:SetScript("OnUpdate", function(self)
    local dirty = ns._npHvDirty
    for plate in pairs(dirty) do
        dirty[plate] = nil
        -- A plate recycled between mark and drain has no unit; the paint's
        -- own guard returns. A re-acquired one paints its new occupant.
        if plate.unit then plate:UpdateHealthValues() end
    end
    if next(dirty) == nil then self:Hide() end
end)
function NameplateFrame:MarkHealthDirty()
    ns._npHvDirty[self] = true
    ns._npHvFlush:Show()
end
function NameplateFrame:UNIT_NAME_UPDATE()
    self:UpdateName()
end
function NameplateFrame:UNIT_THREAT_LIST_UPDATE()
    self:UpdateHealthColor()
end
-- Faction badge: faction and PvP flag changes. The tap-state repaint rides the
-- shared UNIT_FACTION handler (factionFrame), not this one.
function NameplateFrame:UNIT_FACTION()
    self:UpdateFaction(true)
end
function NameplateFrame:UNIT_SPELLCAST_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_DELAYED()
    -- Cast timing changed: the kick-tick geometry (min/max, positioner
    -- snapshot) must re-derive even on the non-full UpdateCast path
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_STOP()
    self:UpdateCast()
    -- Same hole CHANNEL_STOP and EMPOWER_STOP close directly: under restricted
    -- execution UnitCastingInfo can still hand UpdateCast a SECRET (non-nil) tuple
    -- for the cast that just stopped, so the ended branch never runs, isCasting stays
    -- true and ApplyScale keeps the cast multiplier on the plate after the cast (and
    -- after untargeting). A unit has one cast-time cast at a time, so a STOP landing
    -- while a non-channel cast is still flagged means that cast is over; a live
    -- channel (a STOP from an instant mid-channel) is left to CHANNEL_STOP.
    if self.isCasting and not self._castIsChannel then
        self.isCasting = false
        self:HideKickTick()
        self:ClearImportantCastGlow()
        self:ApplyScale()
        if not self._interrupted then
            self.cast:Hide()
        end
        self:ApplyNameVisibility()
        self.castTimer:SetText("")
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            I.fallbackCastCount = math.max(0, I.fallbackCastCount - 1)
            if I.fallbackCastCount == 0 then castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
    end
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_STOP(_, _, _, interrupterGUID)
    -- Directly hide instead of UpdateCast: in restricted execution, UnitCastingInfo can
    -- return secret values (not nil) for a stale channel, making UpdateCast think it's active.
    -- An interrupted channel carries the interrupter GUID on this event; a natural end leaves it nil.
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            I.fallbackCastCount = I.fallbackCastCount - 1
            if I.fallbackCastCount <= 0 then I.fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ApplyScale()
    if not self._interrupted then
        self.cast:Hide()
    end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
    if type(interrupterGUID) ~= "nil" and not self._interrupted then
        self:HandleInterrupted(interrupterGUID)
    end
end
function NameplateFrame:UNIT_SPELLCAST_FAILED()
    self:UpdateCast()
end
function NameplateFrame:HandleInterrupted(interrupterGUID)
    local protected = self._kickProtected
    if type(interrupterGUID) ~= "nil"
        and ((issecretvalue and issecretvalue(protected)) or not protected) then
        self:ShowCastLockout()
    end
    self:ShowInterrupted(interrupterGUID)
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTED(_, _, _, interrupterGUID)
    self:HandleInterrupted(interrupterGUID)
end
-- Mid-cast interruptibility flips: re-read protection once, store it, refresh
-- color + kick tick + overlay. The cooldown watcher never re-reads cast info per
-- event, so these events are the only mid-cast source of protection changes.
function NameplateFrame:KickProtectionChanged()
    if not self.unit then return end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(self.unit)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local chName
        chName, _, _, _, _, _, kp = UnitChannelInfo(self.unit)
        if type(chName) == "nil" then return end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then kickProtected = false end
    self._kickProtected = kickProtected
    self:ApplyCastColor(kickProtected)
    self:RefreshKickTick()
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_NOT_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_STOP(_, _, _, _, interrupterGUID)
    -- Stop directly. Re-checking cast info here can return a stale secret
    -- value in PvP and look like the cast is still going. An interrupted empower
    -- carries the interrupter GUID as the 5th arg (after unit, castGUID, spellID, complete).
    local wasCasting = self.isCasting
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ApplyScale()
    if not self._interrupted then
        self.cast:Hide()
    end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if wasCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            I.fallbackCastCount = math.max(0, I.fallbackCastCount - 1)
            if I.fallbackCastCount == 0 then castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
    if type(interrupterGUID) ~= "nil" and not self._interrupted then
        self:HandleInterrupted(interrupterGUID)
    end
end

I.broken = false
