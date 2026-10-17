if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_GCD.lua
--
--  The GCD bar.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP

local CLASS_COLORS, ERB, SnapXY, ApplyBarFlat = I.CLASS_COLORS, I.ERB, I.SnapXY, I.ApplyBarFlat
local ApplyBarGradient, ApplyBarOrientation = I.ApplyBarGradient, I.ApplyBarOrientation
local OrientedSize, SPARK_TEX, SetGCDBarFrame = I.OrientedSize, I.SPARK_TEX, I.SetGCDBarFrame
local SetUpdateGCDBar = I.SetUpdateGCDBar

local gcdBarFrame
I.gcdBarFrameSetters[#I.gcdBarFrameSetters + 1] = function(v) gcdBarFrame = v end
local cachedClass
I.cachedClassSetters[#I.cachedClassSetters + 1] = function(v) cachedClass = v end
local UpdateGCDBar
I.UpdateGCDBarSetters[#I.UpdateGCDBarSetters + 1] = function(v) UpdateGCDBar = v end

local BuildGCDBar

-------------------------------------------------------------------------------
--  GCD Bar
--  Uses the same detection logic as the cursor GCD Circle
-------------------------------------------------------------------------------
-- Idle fill render for the GCD bar. Debug-measured on the live client
-- (2026-08-08): a COMPLETED bar timer keeps painting its finished state --
-- SetValue(0) read back 0 while the fill still drew full -- so the idle
-- look is set by RE-ARMING the finished duration object in whichever
-- direction PAINTS the desired state (RemainingTime of a finished cooldown
-- paints empty, ElapsedTime paints full). SetValue keeps the value channel
-- and the no-timer Lua fill path coherent.
ns.GCDIdleFill = function(g)
    local bar = gcdBarFrame and gcdBarFrame._bar
    if not bar then return end
    local wantFull = g.idleShowFill == true
    if bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
        -- Fetch a FRESH object here: after a CANCELLED cast the GCD is
        -- refunded and the stored handle goes stale -- a RemainingTime
        -- re-arm on it plays out the original countdown (a slow un-fill
        -- over the leftover window). A fresh handle reflects the reset and
        -- paints the terminal state instantly. wantFull prefers the stored
        -- FINISHED object (ElapsedTime of finished paints full, proven);
        -- each side falls back to the other.
        local fresh = C_Spell and C_Spell.GetSpellCooldownDuration
            and C_Spell.GetSpellCooldownDuration(EllesmereUI.GCD_SPELL)
        local obj
        if wantFull then
            obj = gcdBarFrame._gcdDurObj or fresh
        else
            obj = fresh or gcdBarFrame._gcdDurObj
        end
        if obj then
            bar:SetTimerDuration(obj, nil,
                wantFull and Enum.StatusBarTimerDirection.ElapsedTime
                    or Enum.StatusBarTimerDirection.RemainingTime)
        end
    end
    bar:SetValue(wantFull and 1 or 0)
end

BuildGCDBar = function()
    local g = ERB.db.profile.gcdBar

    if not g.enabled then
        if gcdBarFrame then
            EllesmereUI.SetElementVisibility(gcdBarFrame, false)
            gcdBarFrame:UnregisterAllEvents()
            gcdBarFrame._gcdStart = nil
            gcdBarFrame._gcdDur = nil
            gcdBarFrame._gcdActualStart = nil
            gcdBarFrame._barActive = nil
            gcdBarFrame._nativeGCD = nil
            gcdBarFrame._gcdDurObj = nil
        end
        return
    end

    if not gcdBarFrame then
        -- Adopt the file-scope shell (attribution; see the note in EUI_ResourceBars_Frames.lua).
        SetGCDBarFrame(ns.GCDShell)
        gcdBarFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
        gcdBarFrame:SetFrameLevel(15)

        local bg = gcdBarFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        gcdBarFrame._bg = bg

        local bdrFrame = CreateFrame("Frame", nil, gcdBarFrame)
        bdrFrame:SetAllPoints(gcdBarFrame)
        bdrFrame:SetFrameLevel(gcdBarFrame:GetFrameLevel() + 5)
        gcdBarFrame._border = bdrFrame
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.CreateBorder(bdrFrame, 0, 0, 0, 1, 1) end

        local clipFrame = CreateFrame("Frame", nil, gcdBarFrame)
        clipFrame:SetClipsChildren(true)
        gcdBarFrame._barClip = clipFrame

        local bar = CreateFrame("StatusBar", "ERB_GCDBar", clipFrame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        gcdBarFrame._bar = bar
        -- Native smoothing, applied via SetValue(progress, _castInterp).
        bar._castInterp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

        -- Spark (same texture/approach as the cast bar)
        local sparkFrame = CreateFrame("Frame", nil, clipFrame)
        sparkFrame:SetAllPoints(bar)
        -- One over the fill (18): Draw Above GCD Bar lifts the power border to 19.
        sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
        local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        gcdBarFrame._spark = spark

        -- Event-driven GCD capture (like the cursor GCD ring)
        local getCD = C_Spell and C_Spell.GetSpellCooldown

        -- Push a fresh GCD duration object into the bar timer. Hoisted so a
        -- capture allocates no closure beyond the pcall body. The object is
        -- kept on the frame: the idle render re-arms it to repaint (see
        -- ns.GCDIdleFill).
        local function armNativeGCD(bar, deplete)
            local durObj = C_Spell.GetSpellCooldownDuration(EllesmereUI.GCD_SPELL)
            if not durObj then return end
            gcdBarFrame._gcdDurObj = durObj
            bar:SetTimerDuration(durObj, nil,
                deplete and Enum.StatusBarTimerDirection.RemainingTime
                    or Enum.StatusBarTimerDirection.ElapsedTime)
            return true
        end

        -- (Re)capture the GCD and arm the fill. windowOnly marks the
        -- cooldown-chatter edge: when the values are secret it may only
        -- refresh an already-open lifecycle window, never open one --
        -- otherwise random cooldown chatter would flash an empty bar.
        local function captureGCD(self, gc, windowOnly)
            local cd = getCD and getCD(EllesmereUI.GCD_SPELL)
            if not cd or not cd.startTime then return end
            -- Engine-true fill, same duration-object push-through as the
            -- action bar swipes: hand the GCD's duration object to the bar
            -- timer and the engine renders TRUE progress every frame --
            -- zero Lua per frame, queue-proof (re-arms land on the same
            -- timeline, so they are idempotent), and secret-proof (the
            -- object is never read).
            local bar = self._bar
            local canNative = bar and bar.SetTimerDuration and Enum
                and Enum.StatusBarTimerDirection
                and C_Spell and C_Spell.GetSpellCooldownDuration
            local ok, elapsed, dur = pcall(function()
                local d, s = cd.duration, cd.startTime
                if d and d > 0 and d <= 1.6 and s and s > 0 then return GetTime() - s, d end
                return nil
            end)
            if ok and elapsed and not (issecretvalue and (issecretvalue(elapsed) or issecretvalue(dur))) then
                local actualStart = GetTime() - elapsed
                -- (Re)start whenever this is a genuinely NEWER GCD than the one we
                -- last captured. Do NOT gate on how far the GCD has elapsed:
                -- while spamming, the next ability is queued and its SUCCEEDED
                -- lands partway into the fresh GCD, so an "elapsed near 0" gate
                -- rejected every queued cast and the bar stayed dropped for the
                -- rest of combat. The newer-start check still stops an off-GCD
                -- spell from restarting the running GCD: it reads the SAME
                -- start, so actualStart is not newer. The remaining check just
                -- skips an already-finished GCD.
                if (dur - elapsed) > 0.05 and ((not self._gcdActualStart) or actualStart > (self._gcdActualStart + 0.05)) then
                    self._gcdActualStart = actualStart
                    -- Readable length: the window is exact, so the isActive
                    -- end check (secret windows only) stands down.
                    self._gcdUnread = nil
                    -- Lifecycle window for the tick (end detection + fade):
                    -- the engine timer owns the drawn fill when available;
                    -- the Lua fill only draws when it is not.
                    self._gcdStart = GetTime()
                    self._gcdDur = math.max(dur - elapsed, 0.05)
                    self._nativeGCD = canNative and armNativeGCD(bar, gc.depleteFill) or nil
                    -- Show the bar THIS frame: waiting for the next tick (or
                    -- the central dispatcher) stacked visible latency on top
                    -- of the event edge.
                    ns.GCDTick.Start()
                    UpdateGCDBar()
                end
            elseif not ok and canNative then
                -- Secret cooldown values (instanced combat): the readable
                -- gate cannot run, and gating this channel on guesses is
                -- the exact trap the action bar swipe work documented --
                -- push the object through. The engine renders the true
                -- fill; the lifecycle window is a conservative GCD
                -- ceiling, cut short by the next arm or once the cooldown
                -- reports isActive false (UpdateGCDBar).
                if windowOnly then
                    -- Cooldown chatter may only refresh the fill of an open
                    -- window (armNative keeps the engine honest); it never
                    -- opens visibility on its own.
                    if self._gcdStart then armNativeGCD(bar, gc.depleteFill) end
                    return
                end
                -- A GCD that is already over (a hard cast's SUCCEEDED, an
                -- off-GCD spell) opens nothing; isActive is never secret.
                if not cd.isActive then return end
                if armNativeGCD(bar, gc.depleteFill) then
                    self._nativeGCD = true
                    self._gcdStart = GetTime()
                    self._gcdDur = 1.6
                    self._gcdUnread = true
                    self._gcdActualStart = nil
                    ns.GCDTick.Start()
                    UpdateGCDBar()
                end
            end
        end

        -- How each spell last behaved, keyed by spellID: "hard" once it has
        -- ever opened a cast, channel or empower bar, "instant" once it has
        -- finished with no cast bar at all. "hard" is sticky -- a proc (e.g.
        -- Infusion of Light) makes one CAST instant, not the spell -- so a
        -- procced cast simply falls back to the slower, always-correct
        -- SUCCEEDED edge. Instant-only reads this to decide whether a press
        -- may arm the bar; see the SPELL_UPDATE_COOLDOWN edge below.
        local castKind = {}

        gcdBarFrame:SetScript("OnEvent", function(self, event, unit, arg2, arg3, arg4)
            local gc = ERB.db.profile.gcdBar
            if not gc or not gc.enabled then return end
            -- UNIT_SPELLCAST_SENT carries an extra target argument, so its
            -- spellID sits one slot further along than the other cast events'.
            local spellID = (event == "UNIT_SPELLCAST_SENT") and arg4 or arg3

            -- Press-parity edge (the action bar swipe lesson): the client
            -- PREDICTS the GCD and fires SPELL_UPDATE_COOLDOWN the moment
            -- the button is pressed -- and, for a queued spell, the moment
            -- the queued cast actually fires. SUCCEEDED only lands after
            -- the server ack, so arming from it alone opened every fill a
            -- tenth of the way in. Same-frame collapse absorbs the storm.
            if event == "SPELL_UPDATE_COOLDOWN" then
                local now = GetTime()
                if self._gcdCapStamp == now then return end
                self._gcdCapStamp = now
                if gc.instantOnly then
                    -- Hard casts and channels predict a GCD at the press too,
                    -- and this edge IS the press: UNIT_SPELLCAST_START only
                    -- lands a round trip later, so a one-frame-later cast read
                    -- found nothing on any real latency and the bar filled for
                    -- every hard cast. Arm only when the spell just
                    -- sent has already been seen finishing instantly; every
                    -- other press waits for its own SUCCEEDED, which arrives
                    -- classified. Unknown always means "wait", so the first
                    -- cast of a spell is late rather than wrong.
                    local sent = self._sentSpellID
                    self._sentSpellID = nil   -- one press edge per send
                    if not (sent and castKind[sent] == "instant"
                        and (now - (self._sentAt or 0)) < 1) then return end
                    -- An off-GCD press landing mid-cast must not open the bar
                    -- on the hard cast's own GCD.
                    if UnitCastingInfo("player") or UnitChannelInfo("player") then return end
                end
                captureGCD(self, gc, true)
                return
            end
            if unit ~= "player" then return end

            if event == "UNIT_SPELLCAST_SENT" then
                -- Press-time bookkeeping for the edge above. Recording only --
                -- this event never shows the bar.
                self._sentSpellID = spellID
                self._sentAt = GetTime()
                return
            end

            -- Stop events: clear the bar the moment the GCD is no longer active.
            if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
               or event == "UNIT_SPELLCAST_STOP" then
                local cd = getCD and getCD(EllesmereUI.GCD_SPELL)
                local stillActive = false
                if cd and cd.startTime then
                    local ok, act = pcall(function()
                        local d, s = cd.duration, cd.startTime
                        return (d and d > 0 and d <= 1.6 and s and s > 0) and true or false
                    end)
                    -- If the read succeeded, trust it. If it FAILED (the GCD
                    -- cooldown came back as a secret value -- common in combat),
                    -- assume the GCD is still active and keep the bar. Otherwise a
                    -- single secret read on one of the many FAILED events that
                    -- spamming generates would wrongly wipe a running GCD.
                    stillActive = (not ok) or act
                end
                if not stillActive then
                    self._gcdStart = nil
                    self._gcdDur = nil
                    self._gcdActualStart = nil
                    -- Paint the idle state NOW: a cancelled cast refunds the
                    -- GCD, and waiting for the next tick leaves the dead fill
                    -- on screen for up to one tick.
                    ns.GCDIdleFill(gc)
                end
                self._realCastSpellID = nil  -- the cast ended; clear the hard-cast flag
                return
            end

            if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
               or event == "UNIT_SPELLCAST_EMPOWER_START" then
                -- Remember this spell had a cast time/channel/empower so the
                -- succeeded it fires can be skipped under instant-only.
                -- Channels/empowers fire succeeded on start.
                -- verify there's an actual cast time, a spell made instant
                -- (e.g. Swiftness Regrowth) will count as instant cast
                if event ~= "UNIT_SPELLCAST_START" then
                    self._realCastSpellID = spellID
                    if spellID then castKind[spellID] = "hard" end
                else
                    local _, _, _, st, et = UnitCastingInfo("player")
                    if st and et and et > st then
                        self._realCastSpellID = spellID
                        if spellID then castKind[spellID] = "hard" end
                    end
                end
                if gc.instantOnly then return end  -- instant-only: don't fill for hard casts
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- instant-only: skip the succeeded that matches spellID
                if gc.instantOnly and spellID and spellID == self._realCastSpellID then
                    self._realCastSpellID = nil
                    return
                end
            else
                return
            end

            if gc.instantOnly and event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- A channel's succeeded can fire before its channel_start.
                -- Defer the capture one frame and skip it if channeling.
                -- Avoids a 1-frame flash on channel start
                local succeededID = spellID
                C_Timer.After(0, function()
                    if UnitChannelInfo and UnitChannelInfo("player") then return end
                    -- The option promises the bar stays down for the whole of
                    -- a hard cast, so an off-GCD instant fired mid-cast must
                    -- not open it on the cast's own GCD either.
                    if UnitCastingInfo("player") then return end
                    -- Got here with no cast bar of its own: this spell is an
                    -- instant, so its next press may arm the bar directly.
                    if succeededID and not castKind[succeededID] then castKind[succeededID] = "instant" end
                    local gc2 = ERB.db.profile.gcdBar
                    if gc2 and gc2.enabled then captureGCD(self, gc2) end
                end)
            else
                captureGCD(self, gc)
            end
        end)
    end

    -- register the cast events that start a GCD. SPELL_UPDATE_COOLDOWN is
    -- the press-parity edge (client GCD prediction); the UNIT_SPELLCAST
    -- events carry the instant-only bookkeeping and the stop/clear edges.
    -- SENT names the spell behind the press, which is the only thing the
    -- press edge has to go on before the server answers.
    gcdBarFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    gcdBarFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")

    -- Size (orientation swaps width/height for vertical) + position
    local ori = g.orientation or "HORIZONTAL"
    local w, h = OrientedSize(g.width, g.height, ori)
    gcdBarFrame:SetFrameStrata(g.frameStrata or "MEDIUM")

    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_GCDBar", gcdBarFrame) then
        -- Override anchor owns position; only update size
        gcdBarFrame:SetSize(w, h)
    elseif g.unlockPos and g.unlockPos.point then
        gcdBarFrame:SetSize(w, h)
        if not EllesmereUI._unlockActive then
            local anchored = EllesmereUI.IsUnlockAnchored("ERB_GCDBar")
            if not (anchored and gcdBarFrame:GetLeft()) then
                local rp = g.unlockPos.relPoint or g.unlockPos.point
                gcdBarFrame:ClearAllPoints()
                -- Same dimension-aware snap as the cast bar above: the unlock-mode
                -- drag path (gcdApply, near ERB_GCDBar's MK() registration) already
                -- snaps; this normal-build path didn't, leaving the stored center
                -- off-grid on odd-pixel heights.
                local sx, sy = SnapXY(g.unlockPos.x or 0, g.unlockPos.y or 0, gcdBarFrame, g.unlockPos)
                gcdBarFrame:SetPoint(g.unlockPos.point, UIParent, rp, sx, sy)
            end
        end
    else
        gcdBarFrame:SetSize(w, h)
        if not EllesmereUI._unlockActive then
            gcdBarFrame:ClearAllPoints()
            gcdBarFrame:SetPoint("CENTER", UIParent, "CENTER", g.anchorX or 0, g.anchorY or 0)
        end
    end

    if gcdBarFrame._border then
        local bs = g.borderSize or 0
        local pl = gcdBarFrame:GetFrameLevel()
        gcdBarFrame._border:SetFrameLevel(g.borderBehind and math.max(0, pl - 1) or (pl + 5))
        -- Lost-rect recovery and Extend Top / Extend Bottom, see the cast bar border above
        -- (no stock style on this bar).
        ns.ERB_AnchorBorderHost(gcdBarFrame._border, gcdBarFrame, ns.ERB_BorderExtents(g))
        EllesmereUI.ApplyBorderStyle(gcdBarFrame._border, bs,
            g.borderR or 0, g.borderG or 0, g.borderB or 0, g.borderA or 1,
            g.borderTexture or "solid", g.borderTextureOffset, g.borderTextureOffsetY,
            g.borderTextureShiftX, g.borderTextureShiftY, "resourcebars", bs,
            nil, EllesmereUI.BorderPx(g.borderSizePx, bs, g.borderTexture or "solid"))
    end
    -- Bottom Separator above the border; none on a Solid border (no stock style
    -- on this bar; inert unless it was ever on).
    if g.edgeSep or gcdBarFrame._erbSep then
        ns.ERB_Separators(gcdBarFrame, g, (g.edgeSep and ns.ERB_Textured(g)) and true or false,
            gcdBarFrame:GetFrameLevel() + 7)
    end

    -- Clip + bar layout. The 1px inset keeps the fill from bleeding past the
    -- border; with no border there's nothing to clip to, so skip it -- otherwise
    -- it eats the whole height of very thin bars (height 1-2 -> nothing visible).
    local clipFrame = gcdBarFrame._barClip
    local bar = gcdBarFrame._bar
    local bdrInset = ((g.borderSize or 0) > 0 and PP and PP.mult) or 0
    clipFrame:ClearAllPoints()
    clipFrame:SetPoint("TOPLEFT", gcdBarFrame, "TOPLEFT", bdrInset, -bdrInset)
    clipFrame:SetPoint("BOTTOMRIGHT", gcdBarFrame, "BOTTOMRIGHT", -bdrInset, bdrInset)
    clipFrame:SetFrameLevel(gcdBarFrame:GetFrameLevel() + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clipFrame)

    -- Texture + background
    local texPath = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.texture, "Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarTexture(texPath)
    gcdBarFrame._bg:SetTexture(nil)
    gcdBarFrame._bg:SetColorTexture(g.bgR, g.bgG, g.bgB, g.bgA)
    -- Textured Background.
    if g.textureBg or gcdBarFrame._bg._erbBgTex then
        ns.ERB_BgTexture(gcdBarFrame._bg, g.textureBg and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.texture, nil),
            g.bgR, g.bgG, g.bgB, g.bgA)
    end

    ApplyBarOrientation(bar, ori)
    -- HORIZONTAL_LEFT = horizontal, but the fill grows right->left (reverse).
    -- ApplyBarOrientation treats any non-vertical key as normal horizontal, so
    -- flip reverse-fill here for the left variant.
    if ori == "HORIZONTAL_LEFT" then bar:SetReverseFill(true) end

    -- Fill color / gradient
    local fillTex = bar:GetStatusBarTexture()
    local fR, fG, fB, fA = g.fillR, g.fillG, g.fillB, g.fillA
    if g.classColored then
        local cc = CLASS_COLORS[cachedClass]
        if cc then fR, fG, fB = cc[1], cc[2], cc[3] end
    end
    if g.gradientEnabled then
        ApplyBarGradient(fillTex, g.gradientDir or "HORIZONTAL", fR, fG, fB, fA,
            g.gradientR, g.gradientG, g.gradientB, g.gradientA)
    else
        ApplyBarFlat(fillTex, fR, fG, fB, fA)
    end

    -- Leading-edge spark: anchored to the fill texture's moving edge so it tracks
    -- the fill. Edge depends on orientation (right / top / bottom for down-fill).
    local spark = gcdBarFrame._spark
    if spark then
        if g.showSpark then
            spark:ClearAllPoints()
            if ori == "VERTICAL_UP" then
                spark:SetSize(w, 8)
                spark:SetPoint("CENTER", fillTex, "TOP", 0, 0)
            elseif ori == "VERTICAL_DOWN" then
                spark:SetSize(w, 8)
                spark:SetPoint("CENTER", fillTex, "BOTTOM", 0, 0)
            elseif ori == "HORIZONTAL_LEFT" then
                spark:SetSize(8, h)
                spark:SetPoint("CENTER", fillTex, "LEFT", 0, 0)
            else
                spark:SetSize(8, h)
                spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
            end
            spark:Show()
        else
            spark:Hide()
        end
    end

    -- Visibility
    gcdBarFrame:Show()
    if gcdBarFrame._gcdStart then
        -- A GCD is mid-flight: leave the fill alone -- a plain SetValue here
        -- would cancel the engine bar timer with nothing to restore it until
        -- the next arm.
        EllesmereUI.SetElementVisibility(gcdBarFrame, true)
    elseif g.alwaysShow and not (g.instanceOnly and not IsInInstance()) then
        ns.GCDIdleFill(g)
        EllesmereUI.SetElementVisibility(gcdBarFrame, true)
    else
        ns.GCDIdleFill(g)
        EllesmereUI.SetElementVisibility(gcdBarFrame, false)
    end
end

SetUpdateGCDBar(function(_dt)
    if not gcdBarFrame or not gcdBarFrame:IsShown() then return end
    local g = ERB.db.profile.gcdBar
    if not g or not g.enabled then return end

    -- Frame stays shown; visibility is via alpha to avoid the Hide->Show fill
    -- flash. (Re-showing a hidden StatusBar renders its fill full for a frame.)
    local bar = gcdBarFrame._bar

    if g.instanceOnly and not IsInInstance() then
        ns.GCDIdleFill(g)
        gcdBarFrame._barActive = nil
        gcdBarFrame._nativeGCD = nil
        EllesmereUI.SetElementVisibility(gcdBarFrame, false)
        return
    end

    -- Animate from the start/duration captured at the cast event (set in the
    -- OnEvent handler). The cooldown is polled only while a secret-value window
    -- is open (the isActive check below, at the GCD ticker's 20 Hz): that
    -- window's length is only a ceiling, and the poll ends it with the GCD.
    local startT, dur = gcdBarFrame._gcdStart, gcdBarFrame._gcdDur
    local active = startT and dur
    local elapsed
    if active then
        elapsed = GetTime() - startT
        if elapsed < 0 or elapsed >= dur then
            gcdBarFrame._gcdStart = nil
            gcdBarFrame._gcdDur = nil
            gcdBarFrame._gcdActualStart = nil
            active = false
        end
    end

    -- Secret values: the real length is unreadable, so the window above is only a ceiling.
    -- The cooldown's isActive stays a plain boolean; end the window when the GCD is over.
    if active and gcdBarFrame._gcdUnread then
        local cd = C_Spell.GetSpellCooldown(EllesmereUI.GCD_SPELL)
        local act = cd and cd.isActive
        if not (issecretvalue and issecretvalue(act)) and act == false then
            gcdBarFrame._gcdStart = nil
            gcdBarFrame._gcdDur = nil
            gcdBarFrame._gcdActualStart = nil
            gcdBarFrame._gcdUnread = nil
            active = false
        end
    end

    if not active then
        -- No GCD running: invisible unless Always Show is on. Idle fill is
        -- empty (background) by default, full when Show Fill Color When
        -- Idle is on.
        ns.GCDIdleFill(g)
        gcdBarFrame._barActive = nil
        gcdBarFrame._nativeGCD = nil
        local visible = false
        if g.alwaysShow then visible = true end
        EllesmereUI.SetElementVisibility(gcdBarFrame, visible)
        return
    end

    EllesmereUI.SetElementVisibility(gcdBarFrame, true)
    if gcdBarFrame._nativeGCD then
        -- The engine bar timer owns the fill (true progress, per frame,
        -- zero Lua); the tick keeps only lifecycle and visibility.
        gcdBarFrame._barActive = true
        return
    end
    -- Deplete mode starts full (1) and drains to empty (0); normal mode fills 0->1.
    local progress = elapsed / dur
    local value = g.depleteFill and (1 - progress) or progress
    if gcdBarFrame._barActive then
        bar:SetValue(value, bar._castInterp)
    else
        -- First frame of a fresh GCD: snap to the start value (no interpolation).
        -- Otherwise deplete mode would briefly ease UP from the empty idle state
        -- before reversing, flashing a fill at the start of every GCD.
        bar:SetValue(value)
        gcdBarFrame._barActive = true
    end
end)

I.BuildGCDBar = BuildGCDBar
I.broken = false
