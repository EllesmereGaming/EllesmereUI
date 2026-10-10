if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Health.lua
--
--  NameplateFrame: health values and health color.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitIsUnit = UnitIsUnit
local UnitIsDeadOrGhost = UnitIsDeadOrGhost

local defaults, NoTintFlag, GetTextSlotColor = I.defaults, I.NoTintFlag, I.GetTextSlotColor
local IsComboHealthText, SetCombinedHealthText = I.IsComboHealthText, I.SetCombinedHealthText
local ApplyOverlayGeometry, EnsureFocusOverlay = I.ApplyOverlayGeometry, I.EnsureFocusOverlay
local OverlayBgAlpha, NotifyCastEnded, _C = I.OverlayBgAlpha, I.NotifyCastEnded, I._C
local GetReactionColor, _fallbackPlates = I.GetReactionColor, I._fallbackPlates
local castFallbackFrame, NameplateFrame = I.castFallbackFrame, I.NameplateFrame

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-- WoW Forever: no health number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua).
-- On ns, not a local: this chunk is near its 200-local cap.
ns.AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
function NameplateFrame:UpdateHealthValues()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            -- Token swap: this plate now represents a DIFFERENT mob. Any in-flight cast display
            -- belongs to the old unit: tear it down and re-evaluate. The cooldown watcher does
            -- not re-read cast info per event, so this is the swap's only cast-state self-heal.
            if self.isCasting then
                if self._castFallback then
                    self._castFallback = nil
                    _fallbackPlates[self] = nil
                    I.fallbackCastCount = I.fallbackCastCount - 1
                    if I.fallbackCastCount <= 0 then I.fallbackCastCount = 0; castFallbackFrame:Hide() end
                end
                NotifyCastEnded(self)
                self.isCasting = false
                self:HideKickTick()
                self:ClearImportantCastGlow()
                if not self._interrupted then self.cast:Hide() end
                self.castTimer:SetText("")
                self._castTex = nil
            end
            self.unit = actualUnit
            unit = actualUnit
            if ns._npToTSlot or self._totEv then self:SyncToT(actualUnit) end
            -- New occupant: its absorb state is unknown. Nil the lean-gate flag
            -- so this pass takes the full absorb path and re-seeds it; the
            -- cached max belongs to the old unit, drop it too.
            self._absorbHidden = nil
            self._maxHPValid = nil
            -- Only refresh auras for the lockout when one was actually active
            -- (zero cost when the Cast Lockout feature is off / no lockout).
            if self._castLockout then
                self._castLockout = nil
                if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
            end
            self:UpdateName()
            self._castDirtyFull = true
            self:UpdateCast()
            -- Unit changed without an add/remove cycle: the old occupant's
            -- target/hover border styling would otherwise stick to the plate.
            -- The one-shot flags MUST stay set going in -- ClearHoverExtras
            -- early-outs on _hoverFxOn and ApplyTarget's size restore is
            -- gated on _targetBorderSized; clearing them first skips both
            -- restores. ClearHoverExtras restores hover size then re-runs
            -- ApplyTarget; the direct call covers its no-hover-fx early-out
            -- and re-evaluates target state for the new unit.
            ns.ClearHoverExtras(self)
            self:ApplyTarget()
        end
    end

    local curHealth, maxHealth, absorbAmt

    -- LEAN PATH: the last full pass proved this unit carries no absorb, and no
    -- UNIT_ABSORB_AMOUNT_CHANGED edge has fired since (that handler arms
    -- _absorbEdge; ClearUnit and both token-swap sites nil _absorbHidden so a
    -- new occupant always takes the full pass). The gate reads only OUR OWN
    -- booleans -- never unit state -- so combat secrecy cannot poison it.
    -- Shieldless units, the vast majority of health events, pay two unit reads
    -- and two bar pushes here instead of the calculator fetch + absorb branch.
    if self._absorbHidden and not self._absorbEdge then
        curHealth = UnitHealth(unit)
        -- Bar bounds ride UNIT_MAXHEALTH: the cached max (possibly secret --
        -- stored but never compared; _maxHPValid is OUR plain flag) pushes
        -- once on change/seed/absorb-teardown instead of every paint. The
        -- steady-state health paint is one read + one SetValue, matching
        -- Blizzard's own per-event bar cost.
        if not self._maxHPValid then
            maxHealth = UnitHealthMax(unit)
            self._maxHP = maxHealth
            self._maxHPValid = true
            self.health:SetMinMaxValues(0, maxHealth)
        else
            maxHealth = self._maxHP
        end
        self.health:SetValue(curHealth)
    else
    self._absorbEdge = nil

    if self.hpCalculator and self.hpCalculator.GetMaximumHealth and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)
        curHealth = self.hpCalculator:GetCurrentHealth()
        maxHealth = self.hpCalculator:GetMaximumHealth()
        absorbAmt = self.hpCalculator:GetDamageAbsorbs()
    else
        curHealth = UnitHealth(unit)
        maxHealth = UnitHealthMax(unit)
        absorbAmt = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
    end

    -- The health bar keeps plain max health whatever the shield: the shield
    -- draws over it rather than squeezing it.
    self.health:SetMinMaxValues(0, maxHealth)
    self.health:SetValue(curHealth)

    -- A secret absorb can't be tested for zero, so it always draws (a zero
    -- value renders nothing).
    local absorbIsSecret = issecretvalue and issecretvalue(absorbAmt)
    if not absorbIsSecret and (not absorbAmt or absorbAmt <= 0) then
        -- No shield: hide once, then the lean path carries the plate until
        -- the next absorb edge.
        if not self._absorbHidden then
            self._absorbHidden = true
            self._absCurClip:Hide()
            self._absMissClip:Hide()
        end
    else
        self._absorbHidden = false
        -- Both bars take the raw absorb over max health; the clip frames do
        -- the split (ns.NP_BuildAbsorbBars), so no Lua math touches it.
        self.absorb:SetMinMaxValues(0, maxHealth)
        self.absorb:SetValue(absorbAmt)
        self._absCurClip:Show()
        -- The forward bar draws only in the overlay placements (stamped by
        -- the layout); the edge placements draw the whole shield through the
        -- main bar.
        local fw = self.absorbForward
        if self._absFwOn then
            fw:SetMinMaxValues(0, maxHealth)
            fw:SetValue(absorbAmt)
            self._absMissClip:Show()
        else
            self._absMissClip:Hide()
        end
    end
    end -- lean-gate else (full absorb path)

    -- Hash line positioning (target only). PERF: uses cached _isTarget, not UnitIsUnit per tick.
    local hlEnabled = (p and p.hashLineEnabled)
    local hlPct = (p and p.hashLinePercent) or defaults.hashLinePercent
    if hlEnabled and hlPct and hlPct > 0 and self._isTarget then
        -- Input-gated: anchor/color pushes only depend on bar width and settings (bar width is
        -- our frame -- never secret), re-pushed only when an input moves.
        local barW = self.health:GetWidth()
        local hlc = (p and p.hashLineColor) or defaults.hashLineColor
        if self._hlW ~= barW or self._hlPct ~= hlPct
           or self._hlR ~= hlc.r or self._hlG ~= hlc.g or self._hlB ~= hlc.b then
            self._hlW = barW; self._hlPct = hlPct
            self._hlR, self._hlG, self._hlB = hlc.r, hlc.g, hlc.b
            local xPos = barW * (hlPct / 100)
            self.hashLine:ClearAllPoints()
            self.hashLine:SetPoint("TOP", self.health, "TOPLEFT", xPos, 0)
            self.hashLine:SetPoint("BOTTOM", self.health, "BOTTOMLEFT", xPos, 0)
            self.hashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
        end
        self.hashLine:Show()
        self._hashHidden = nil
    else
        -- Own-flag gate: non-target plates were paying a Hide() every paint.
        -- nil flag (fresh/recycled plate, unknown widget state) hides once.
        if not self._hashHidden then
            self.hashLine:Hide()
            self._hashHidden = true
        end
    end

    -- PERF: text content only -- font/position/color live in ApplyHealthTextAppearance. Runs
    -- on every UNIT_HEALTH tick: stay lean.
    local ca = self._cachedHealthSlots
    if ca and ca._count > 0 then
        -- Value memo: health ticks land on the same DISPLAYED values constantly, and
        -- string.format + SetText churn is the hottest allocation source on plates. Keys MUST
        -- be quantized to display granularity -- the raw percent is a FLOAT that moves every
        -- tick, so a raw key never repeats and the memo never hits. Raw health gates the skip
        -- ONLY when a slot renders it (number/combo): a percent-only layout then keeps its hits
        -- through raw churn. Secret values cannot be compared or floored: any secret input
        -- fails open to writing and clears its key.
        local isSec = issecretvalue
        local dead = UnitIsDeadOrGhost(unit)
        local anyDec = ca._anyDecimal
        local pctVal
        if not dead and UnitHealthPercent then
            pctVal = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
        end
        local pctKey
        if dead then
            pctKey = -1
        elseif pctVal ~= nil and not (isSec and isSec(pctVal)) then
            pctKey = anyDec and math.floor(pctVal * 10 + 0.5) or math.floor(pctVal)
        end
        local anyNum = ca._anyNum
        if anyNum == nil then
            anyNum = false
            local anyNoSign, anyMax = false, false
            for si = 1, ca._count do
                local entry = ca[si]
                local el = entry.element
                -- Stamp the combo classification once per appearance build:
                -- the write loop below runs per paint and must not pay a
                -- classification call per slot per paint.
                entry.combo = IsComboHealthText(el) or false
                if el == "healthNumber" or entry.combo then anyNum = true end
                if el == "healthPercentNoSign" then anyNoSign = true end
                if el == "healthNumMax" then anyMax = true end
            end
            ca._anyNum = anyNum
            ca._anyNoSign = anyNoSign
            ca._anyMax = anyMax
        end
        local hpKey
        if not anyNum then
            hpKey = 0
        elseif dead then
            hpKey = -1
        elseif curHealth ~= nil and not (isSec and isSec(curHealth)) then
            hpKey = curHealth
        end
        -- The max only gates the skip when a Number / Max slot renders it.
        local maxKey
        if not ca._anyMax then
            maxKey = 0
        elseif maxHealth ~= nil and not (isSec and isSec(maxHealth)) then
            maxKey = maxHealth
        end
        local skipText = pctKey ~= nil and hpKey ~= nil and maxKey ~= nil
            and self._hpTxtPct == pctKey and self._hpTxtCur == hpKey and self._hpTxtMax == maxKey
        if not skipText then
        self._hpTxtPct = pctKey
        self._hpTxtCur = hpKey
        self._hpTxtMax = maxKey
        local pctText, pctNoSignText, numText, maxText
        local pctTextDec, pctNoSignTextDec
        local anyDec = ca._anyDecimal
        if dead then
            pctText = "0%"
            pctNoSignText = "0"
            numText = "0"
            maxText = "0"
            if anyDec then pctTextDec = "0.0%"; pctNoSignTextDec = "0.0" end
        elseif pctVal ~= nil then
            pctText = string.format("%d%%", pctVal)
            -- No-sign variant only when a slot actually renders it.
            if ca._anyNoSign then pctNoSignText = string.format("%d", pctVal) end
            -- Number text only when a number/combo slot renders it (percent-only
            -- layouts were paying the abbreviation call + string every tick).
            if anyNum then
                numText = ns.AbbreviateNumbers(curHealth)
                if ca._anyMax then maxText = ns.AbbreviateNumbers(maxHealth) end
            end
            -- Decimal variants computed only when at least one slot opts in.
            if anyDec then
                pctTextDec = string.format("%.1f%%", pctVal)
                if ca._anyNoSign then pctNoSignTextDec = string.format("%.1f", pctVal) end
            end
        else
            pctText = ""
            pctNoSignText = ""
            numText = ""
            maxText = ""
            if anyDec then pctTextDec = ""; pctNoSignTextDec = "" end
        end
        for si = 1, ca._count do
            local entry = ca[si]
            local el = entry.element
            local fs = entry.fs
            if el == "healthPercent" then
                fs:SetText(entry.pctDecimal and pctTextDec or pctText)
            elseif el == "healthPercentNoSign" then
                fs:SetText(entry.pctDecimal and pctNoSignTextDec or pctNoSignText)
            elseif el == "healthNumber" then
                fs:SetText(numText)
            elseif entry.combo then
                SetCombinedHealthText(fs, el, entry.pctDecimal and pctTextDec or pctText, numText, maxText)
            end
        end
        end -- skipText
    end

    -- Execute Pulse Glow gate: evaluate the execute-window curve C-side and feed the color
    -- straight into the glow textures (alpha 1 below threshold, 0 above -- never branched on in
    -- Lua). Parent frame's pulse multiplies on top. No-execute specs never build textures.
    local lg = self.lowHpGlowTextures
    if lg and self._lowHpGlowOn then
        local curve = ns.GetLowHpGlowCurve()
        if curve then
            if UnitIsDeadOrGhost(unit) then
                for i = 1, #lg do lg[i]:SetVertexColor(0, 0, 0, 1) end
            else
                local ok, col = pcall(UnitHealthPercent, unit, true, curve)
                if ok and col and col.GetRGBA then
                    local r, g, b, a = col:GetRGBA()
                    for i = 1, #lg do lg[i]:SetVertexColor(r, g, b, a) end
                end
            end
        end
    end
end
-- Repaint the base border after the Threat Colors "Border" tint changed. Skipped while
-- this plate wears the target or hover border color: both are applied ON TOP of the base
-- border and outrank threat, and when they end their own restore (ApplyTarget's
-- else-branch, ClearHoverExtras) calls ApplyBorderColor, which picks the tint up then.
-- The wrap re-sync mirrors what ApplyTarget does after its own border paint: with the
-- border wrapped around the cast bar, the color just set landed on the hidden health
-- border (Basic) or not yet on the lower piece and seam (Custom).
function NameplateFrame:RepaintThreatBorder(unit)
    if UnitIsUnit(unit, "target") and ns.GetTargetGlowBorderColor() then return end
    if self._hoverFxOn and ns.GetHoverGlowBorderColor() then return end
    self:ApplyBorderColor()
    if self._wrapActive or self._cbWrapActive then self:UpdateBorderWrap() end
end
function NameplateFrame:UpdateHealthColor()
    local unit = self.unit
    if not unit then return end
    -- Skip-if-unchanged: GetReactionColor returns plain profile-sourced numbers (every return
    -- path verified non-secret). Threat events fire constantly with an unchanged result, so
    -- compare against the last applied values and skip the setter. Cache nil'd in ClearUnit.
    local hr, hg, hb = GetReactionColor(unit)
    -- Enemy player whose class token was redacted (instanced PvP): paint the bar from
    -- Blizzard's plate instead. A secret cannot go through the skip-if-unchanged compare, so
    -- this re-reads and re-applies every pass rather than latching -- a latch would freeze the
    -- bar on a stale colour when Blizzard's changes (a disconnect greys it, the CVar is
    -- toggled mid-match). Two C calls against the dozen GetReactionColor already spent, on
    -- the few plates that take this path. hr/hg/hb stay the plain fallback for the tints below.
    local mirrored, mr, mg, mb = false
    if ns._reactionMirrorClass then
        -- The redacted token still keys C_ClassColor (the slot painter does the same); the
        -- colour may be secret and goes straight to the setter.
        local _, tok = UnitClass(unit)
        if tok then
            local ok, found, r, g, b = pcall(EllesmereUI.GetClassColorForRestrictedUnit, unit, tok)
            if ok and found then
                mirrored, mr, mg, mb = true, r, g, b
            else
                local okC, c = pcall(C_ClassColor.GetClassColor, tok)
                if okC and c then
                    local okRGB, r2, g2, b2 = pcall(c.GetRGB, c)
                    if okRGB then mirrored, mr, mg, mb = true, r2, g2, b2 end
                end
            end
        end
        if not mirrored then
            -- Any failure above lands here: Blizzard's plate, the previous behaviour. Wanted
            -- to mirror but it was not on this unit yet: the deferred setup pass retries.
            mirrored, mr, mg, mb = ns.GetBlizzardBarColor(self)
            self._mirrorPending = not mirrored or nil
        else
            self._mirrorPending = nil
        end
    else
        self._mirrorPending = nil
    end
    -- Off-tank fold: same shape as mirror -- the folded components can be
    -- SECRET, so they bypass the value compare, never enter the caches, and
    -- reach setters only. hr/hg/hb stay the plain tankNoAggro fallback.
    local folded, fr, fg, fb = false
    if not mirrored and ns._reactionOffTankFold and ns.ComputeOffTankFold then
        local otc = _C("offTankAggro")
        folded, fr, fg, fb = ns.ComputeOffTankFold(unit, hr, hg, hb, otc.r, otc.g, otc.b)
    end
    if mirrored then
        -- Cache invalidated, never written with a secret: the next plain colour must reapply.
        self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
        self.health:SetStatusBarColor(mr, mg, mb)
    elseif folded then
        self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
        self.health:SetStatusBarColor(fr, fg, fb)
    elseif hr ~= self._lastHCr or hg ~= self._lastHCg or hb ~= self._lastHCb then
        self._lastHCr, self._lastHCg, self._lastHCb = hr, hg, hb
        self.health:SetStatusBarColor(hr, hg, hb)
    end
    -- Threat Colors "Border" / "Text" channels -- the SECOND signal. Both off by default,
    -- so the shipped path costs two field reads. ns.ResolveThreatColor answers "what does
    -- threat say about this unit" without any of the health bar's priority competition,
    -- which is the whole point: the bar can carry the mob type (Caster/Mini-Boss/Boss)
    -- while border and name carry aggro at the same time. It reuses the threat situation
    -- GetReactionColor read above. Its fourth return marks SECRET components (an off-tank
    -- C-fold over a secret read): those bypass every compare, stay out of the caches and
    -- reach setters only, exactly like the bar's own fold path.
    local tcBorder = ns.GetThreatColorBorder()
    local tcName   = ns.GetThreatColorName()
    local tcr, tcg, tcb, tcSecret
    if tcBorder or tcName then
        tcr, tcg, tcb, tcSecret = ns.ResolveThreatColor(unit, ns._reactionThreatStatus)
    end
    -- Plain "there is a signal" boolean: tcr itself may be secret, so the short-circuit
    -- keeps it out of the comparison.
    local tcOn = (tcSecret or tcr ~= nil) and true or false
    -- Border. The color is parked on the plate and ApplyBorderColor -- the single funnel
    -- that paints the base border -- reads it, so every restore path (RefreshBorderColor,
    -- ApplyTarget's else-branch, ClearHoverExtras) picks it up for free. Repainted here
    -- only when it actually changed, and never over a plate currently wearing the target
    -- or hover border color: those are explicit selection states that win, and their own
    -- restore runs ApplyBorderColor when they end.
    if tcBorder and tcOn then
        local repaint = false
        self._threatBdOn = true
        self._threatBdR, self._threatBdG, self._threatBdB = tcr, tcg, tcb
        if tcSecret then
            self._threatBdKr, self._threatBdKg, self._threatBdKb = nil, nil, nil
            repaint = true
        elseif tcr ~= self._threatBdKr or tcg ~= self._threatBdKg or tcb ~= self._threatBdKb then
            self._threatBdKr, self._threatBdKg, self._threatBdKb = tcr, tcg, tcb
            repaint = true
        end
        if repaint then self:RepaintThreatBorder(unit) end
    elseif self._threatBdOn then
        self._threatBdOn = nil
        self._threatBdR, self._threatBdG, self._threatBdB = nil, nil, nil
        self._threatBdKr, self._threatBdKg, self._threatBdKb = nil, nil, nil
        self:RepaintThreatBorder(unit)
    end
    -- Enemy name text: two lanes can want it. Threat Colors "Text" wins while it has a
    -- signal; next the Core Text Positions Text Coloring slot mode, Hostility / Class or
    -- Level Difficulty (one boolean read while every slot is custom). The slot mode keeps
    -- painting its other font strings while threat holds the name (skipName drops the
    -- name's memo, so it repaints the moment threat hands the name back). Each lane keeps
    -- its own skip-if-unchanged cache, and handing the name from one to another clears the
    -- previous owner's cache so the new owner always repaints once. A custom-mode name
    -- threat hands back takes its static slot colour here; changing a slot's mode runs
    -- ApplyAppearance, whose static write and cache resets hand the name back to the lanes.
    local nameThreat = tcName and tcOn
    local wasNameThreat = self._threatNameOn
    self._threatNameOn = nameThreat or nil
    local slotClassName = false
    if ns._npSlotClassOn then
        slotClassName = ns.NP_PaintSlotClassColors(self, unit, nameThreat)
    end
    if nameThreat then
        if tcSecret then
            self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
            self.name:SetTextColor(tcr, tcg, tcb, 1)
        elseif tcr ~= self._nameThR or tcg ~= self._nameThG or tcb ~= self._nameThB then
            self._nameThR, self._nameThG, self._nameThB = tcr, tcg, tcb
            self.name:SetTextColor(tcr, tcg, tcb, 1)
        end
    elseif slotClassName then
        -- (name painted by the slot's class or level mode)
        if wasNameThreat then self._nameThR, self._nameThG, self._nameThB = nil, nil, nil end
    elseif wasNameThreat then
        self._nameThR, self._nameThG, self._nameThB = nil, nil, nil
        local nameSlotKey = ns.FindNameSlot()
        if nameSlotKey then
            local nr, ng, nb = GetTextSlotColor(nameSlotKey)
            self.name:SetTextColor(nr, ng, nb, 1)
        end
    end
    -- Near-aggro glow (Non-Tank Threat cog): ns._reactionNearAggro was written
    -- by the GetReactionColor call ABOVE (same decision that picked the color).
    -- Own state cache, so constant same-result threat events are one compare;
    -- feature off = one boolean read on top of that.
    local naGlow = false
    if ns._reactionNearAggro then
        local dbg = p or defaults
        naGlow = dbg.threatNearAggroGlow == true
    end
    if naGlow ~= (self._naGlowOn or false) then
        self._naGlowOn = naGlow
        if naGlow then
            ns.EnsureNearAggroGlow(self)
            self.naGlowFrame:Show()
        elseif self.naGlowFrame then
            self.naGlowFrame:Hide()
        end
    end
    -- Threat % text (WoW Forever): one field read while off; a shown text is
    -- still hidden on the pass after the option turns off.
    if ns._npTptOn or self._tptShown then ns.NP_UpdateThreatPct(self, unit) end
    -- Focus overlay: stripe textures on the focus target's health bar (fill clip at full alpha,
    -- bg clip at half). Value-keyed: reapplied only when a component differs from the last
    -- applied state. No Tint keeps the whole pipeline and only swaps the tint source to the
    -- bar's current health color (hr/hg/hb above). NEVER use these overlay textures as the
    -- bar's own fill texture: they are pattern-on-transparent art, so transparent ground
    -- renders as holes and darkens the whole bar.
    local db2 = p or defaults
    local focusTex = db2.focusOverlayTexture or defaults.focusOverlayTexture
    if focusTex ~= "none" and UnitIsUnit(unit, "focus") then
        -- Texture path memoized by texture NAME (no per-call concat); live dropdown changes rebuild it.
        if ns._focusOverlayTexName ~= focusTex then
            ns._focusOverlayTexName = focusTex
            ns._focusOverlayTexPath = ns.ResolveOverlayTexPath(focusTex)
        end
        local texPath = ns._focusOverlayTexPath
        local overlayAlpha = db2.focusOverlayAlpha or defaults.focusOverlayAlpha
        local ocr, ocg, ocb
        -- No Tint means "wear the bar's colour", so on a mirrored plate it has to take the
        -- mirrored values, not the plain fallback -- tinting from hr/hg/hb there would show
        -- the exact mismatch No Tint exists to avoid. Secrets cannot be value-keyed, so
        -- forced re-applies every pass and the cache is left unset (the `or` below
        -- short-circuits before any compare touches them).
        local forced = false
        if NoTintFlag(db2, "focusOverlayNoTint") then
            if mirrored then
                ocr, ocg, ocb, forced = mr, mg, mb, true
            elseif folded then
                ocr, ocg, ocb, forced = fr, fg, fb, true
            else
                ocr, ocg, ocb = hr, hg, hb
            end
        else
            local oc = db2.focusOverlayColor or defaults.focusOverlayColor
            ocr, ocg, ocb = oc.r, oc.g, oc.b
        end
        local bgAlpha = OverlayBgAlpha(db2.focusOverlayFullBgAlpha, overlayAlpha)
        if forced or not self._ovFocShown or self._ovFocTex ~= texPath
            or self._ovFocAlpha ~= overlayAlpha or self._ovFocBgAlpha ~= bgAlpha
            or self._ovFocR ~= ocr or self._ovFocG ~= ocg or self._ovFocB ~= ocb then
            EnsureFocusOverlay(self)
            self._ovFocShown = true
            self._ovFocTex, self._ovFocAlpha = texPath, overlayAlpha
            self._ovFocBgAlpha = bgAlpha
            if forced then
                self._ovFocR, self._ovFocG, self._ovFocB = nil, nil, nil
            else
                self._ovFocR, self._ovFocG, self._ovFocB = ocr, ocg, ocb
            end
            ApplyOverlayGeometry(self.focusOverlayFill, self.focusOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[focusTex] == true)
            self.focusOverlayFill:SetTexture(texPath)
            self.focusOverlayFill:SetAlpha(overlayAlpha)
            self.focusOverlayFill:SetVertexColor(ocr, ocg, ocb)
            self.focusClipFill:Show()
            self.focusOverlayBg:SetTexture(texPath)
            self.focusOverlayBg:SetAlpha(bgAlpha)
            self.focusOverlayBg:SetVertexColor(ocr, ocg, ocb)
            self.focusClipBg:Show()
        end
    elseif self.focusClipFill then
        self._ovFocShown = nil
        self.focusClipFill:Hide()
        self.focusClipBg:Hide()
    end
    -- Focus letter: zero cost when off -- a disabled plate pays two field reads (no call, no
    -- UnitIsUnit, no allocation). _focusLetterShown lets a live letter hide itself when turned off.
    if db2.focusLetterEnabled or self._focusLetterShown then
        ns.ApplyFocusLetter(self, unit, db2)
    end
    -- Target overlay: identical to focus overlay but for current target,
    -- including the No Tint bar-color tint source.
    local targetTex = db2.targetOverlayTexture or defaults.targetOverlayTexture
    if targetTex ~= "none" and UnitIsUnit(unit, "target") then
        if ns._targetOverlayTexName ~= targetTex then
            ns._targetOverlayTexName = targetTex
            ns._targetOverlayTexPath = ns.ResolveOverlayTexPath(targetTex)
        end
        local texPath = ns._targetOverlayTexPath
        local overlayAlpha = db2.targetOverlayAlpha or defaults.targetOverlayAlpha
        local ocr, ocg, ocb
        -- Mirrored plate: same reasoning as the focus overlay above.
        local forced = false
        if NoTintFlag(db2, "targetOverlayNoTint") then
            if mirrored then
                ocr, ocg, ocb, forced = mr, mg, mb, true
            elseif folded then
                ocr, ocg, ocb, forced = fr, fg, fb, true
            else
                ocr, ocg, ocb = hr, hg, hb
            end
        else
            local oc = db2.targetOverlayColor or defaults.targetOverlayColor
            ocr, ocg, ocb = oc.r, oc.g, oc.b
        end
        local bgAlpha = OverlayBgAlpha(db2.targetOverlayFullBgAlpha, overlayAlpha)
        if forced or not self._ovTgtShown or self._ovTgtTex ~= texPath
            or self._ovTgtAlpha ~= overlayAlpha or self._ovTgtBgAlpha ~= bgAlpha
            or self._ovTgtR ~= ocr or self._ovTgtG ~= ocg or self._ovTgtB ~= ocb then
            ns.EnsureTargetOverlay(self)
            self._ovTgtShown = true
            self._ovTgtTex, self._ovTgtAlpha = texPath, overlayAlpha
            self._ovTgtBgAlpha = bgAlpha
            if forced then
                self._ovTgtR, self._ovTgtG, self._ovTgtB = nil, nil, nil
            else
                self._ovTgtR, self._ovTgtG, self._ovTgtB = ocr, ocg, ocb
            end
            ApplyOverlayGeometry(self.targetOverlayFill, self.targetOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[targetTex] == true)
            self.targetOverlayFill:SetTexture(texPath)
            self.targetOverlayFill:SetAlpha(overlayAlpha)
            self.targetOverlayFill:SetVertexColor(ocr, ocg, ocb)
            self.targetClipFill:Show()
            self.targetOverlayBg:SetTexture(texPath)
            self.targetOverlayBg:SetAlpha(bgAlpha)
            self.targetOverlayBg:SetVertexColor(ocr, ocg, ocb)
            self.targetClipBg:Show()
        end
    elseif self.targetClipFill then
        self._ovTgtShown = nil
        self.targetClipFill:Hide()
        self.targetClipBg:Hide()
    end
end
function NameplateFrame:UpdateHealth()
    self:UpdateHealthValues()
    self:UpdateHealthColor()
end

I.broken = false
