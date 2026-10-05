if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookIconWatch.lua
--
--  Per-spell icon watchers: ready sound, charge text, cooldown state effects,
--  Swiftmend brightness, custom icons and icon-art suppression.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local _ecmeFC = ns._ecmeFC
local GetTime = GetTime

local _isDruid, GetViewerFrame, hookFrameData = I._isDruid, I.GetViewerFrame, I.hookFrameData
local IsCDMSettingsOpen, ResolveFrameSpellID = I.IsCDMSettingsOpen, I.ResolveFrameSpellID
local ResolveSpellSettings, CdmChargeInfoFor = I.ResolveSpellSettings, I.CdmChargeInfoFor

-------------------------------------------------------------------------------
--  Audio Effect on CD Ready -- per-spell (CD/utility bars only)
--  Plays a sound the moment a spell becomes ready. Edge-detected with an arm
--  flag (armed only while NOT ready, played + disarmed on the ready edge), so it
--  never fires on login (already ready -> never armed), on a GCD end, or per
--  render tick. The expiry edge comes from Blizzard's TriggerAvailableAlert (see
--  HookCdReadyAvailableAlert): the client sends NO event when a cooldown runs
--  out. Cooldown/charge events drive arming/readiness/resets via the
--  WatchCdReadySoundIfEnabled set -- NEVER the SetDesaturated visual hook, which
--  fires at repaint moments unrelated to the real cooldown where GetSpellCooldown
--  can report a transient isActive=true/isOnGCD=false race that false-armed
--  spells never on cooldown during button spam; reading isActive+isOnGCD AT the
--  event (state settled) avoids that. Charge readiness = GetSpellCharges()
--  .isActive == false (at max, same signal Max Stacks Glow uses); non-charge
--  readiness = not (GetSpellCooldown().isActive and not isOnGCD). No
--  duration/magnitude math (secret in protected instances) -- clean bools only.
-------------------------------------------------------------------------------
ns._cdReadySoundWatch = ns._cdReadySoundWatch or setmetatable({}, { __mode = "k" })

-- Loading-screen / login-settle gate shared by every CDM notification sound (CD-ready,
-- buff gain/loss, preset buff gain). Zone changes, flights and login re-render icons
-- and re-fire aura/charge alerts while the cooldown/charge/aura APIs report transient
-- states across the boundary, false-firing edges on spells/buffs that were mid-cooldown
-- or still present. Cheap: one boolean + one timestamp compare, consulted only on a
-- sound edge (never per tick). Edges landing while suppressed are dropped silently.
do
    local loadingActive = true   -- suppressed until the first PLAYER_ENTERING_WORLD
    local settleUntil = 0
    local SETTLE_SECONDS = 2      -- brief window after a load for re-renders to settle

    function ns._cdmSoundSuppressed()
        return loadingActive or GetTime() < settleUntil
    end

    -- Full CDM rebuilds (spec/talent swaps, settings changes) re-render every
    -- icon while the cooldown/charge APIs are transient, so callers open the same
    -- settle window and the re-prime cannot false-arm a batch. Longest wins.
    function ns._cdmBumpSoundSettle(sec)
        local u = GetTime() + (sec or SETTLE_SECONDS)
        if u > settleUntil then settleUntil = u end
    end

    local gate = ns.TakeShell()
    gate:RegisterEvent("LOADING_SCREEN_ENABLED")
    gate:RegisterEvent("LOADING_SCREEN_DISABLED")
    gate:RegisterEvent("PLAYER_ENTERING_WORLD")
    gate:SetScript("OnEvent", function(_, event)
        if event == "LOADING_SCREEN_ENABLED" then
            loadingActive = true
        else
            -- World up: clear the flag, settle so the re-render cannot false-fire.
            loadingActive = false
            settleUntil = GetTime() + SETTLE_SECONDS
        end
    end)
end


-- Reject armed->ready spans shorter than this: a real cooldown arms the moment
-- the spell is used, so a sub-GCD arm can only be a transient misread (GCD tail
-- / charge race). Costs the sound on real cooldowns under ~1.6s (rare in CDM).
local CD_READY_MIN_ARM = 1.6

-- Both drivers (Blizzard's available alert and the event fallback) can land on
-- the same cooldown end a frame apart -- one shared throttle keeps that single.
local CD_READY_SOUND_GAP = 0.5

-- Is the spell READY now? Charge spells: only at MAX charges (recharge not
-- running). Non-charge: not on a real (non-GCD) cooldown. liveSid = resolved
-- override. strict: the GCD does NOT count as ready. ARMING wants the loose read
-- (a GCD must never arm a spell that was never on cooldown); FIRING must be
-- strict, because a CAST-TIME spell raises its cooldown only on cast SUCCESS and
-- until then GetSpellCooldown reports the GCD alone (isActive + isOnGCD) --
-- "ready" under the loose test, firing the armed sound at the moment of cast.
local function CdReadyIsReady(liveSid, strict)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if ci ~= nil and (ci.maxCharges or 0) > 1 then
        return not ci.isActive
    end
    local cd = C_Spell.GetSpellCooldown(liveSid)
    if not cd then return true end
    if strict then
        -- Not ready while a REAL (non-GCD) cooldown runs. A filler GCD alone
        -- must NOT block the edge: the old "any active cooldown" strict test
        -- deferred the ready sound through continuous GCD spam until the
        -- player stopped casting entirely.
        if cd.isActive and not cd.isOnGCD then return false end
        -- The one GCD-only state that is NOT ready: this spell's own hard cast
        -- in flight (a cast-time spell raises its cooldown only on cast
        -- SUCCESS). Exact identity check; a secret cast id fails toward
        -- suppress -- the armed state survives and the next event retries.
        if UnitCastingInfo then
            local castSid = select(9, UnitCastingInfo("player"))
            if castSid and ((issecretvalue and issecretvalue(castSid)) or castSid == liveSid) then
                return false
            end
        end
        return true
    end
    return not (cd.isActive and not cd.isOnGCD)
end

-- Charge spells keep their own ready edge (refill to MAX, off
-- SPELL_UPDATE_CHARGES). Blizzard's available alert fires when the FIRST
-- charge returns -- a different edge -- so the alert driver skips them.
local function CdReadyIsChargeSpell(liveSid)
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    return ci ~= nil and (ci.maxCharges or 0) > 1
end

-- Single play point for both drivers: throttled, always disarms.
local function PlayCdReadySound(fd, key, liveSid, sid, bk, src)
    fd._cdReadyArmed = false
    local now = GetTime()
    local last = fd._cdReadySoundAt
    if last and (now - last) < CD_READY_SOUND_GAP then return end
    fd._cdReadySoundAt = now
    local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[key]
    if path then PlaySoundFile(path, "Master") end
end

-- Shared evaluator (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES via the
-- WatchCdReadySoundIfEnabled set). Arms while not ready, plays + disarms on the
-- ready edge, deferred one frame and re-confirmed so a charge/GCD-tail race
-- cannot false-fire. Zero-cost on the feature flag. primeOnly: arm state only.
local function EvalCdReadySound(frame, fd, primeOnly)
    if not ns._cdmAnyCdReadySound then return end
    if not fd then return end
    if fd._isProcessingOverride then return end
    -- Buff-family frames never play (see WatchCdReadySoundIfEnabled); held here too so
    -- a frame watched before its decoration flagged it stays silent.
    if fd._isBuffViewerFrame or frame._isCustomBuffFrame or frame._isPlaceholderFrame then
        fd._cdReadyArmed = false
        return
    end
    local fc2 = _ecmeFC[frame]
    -- Hidden by its Talent Conditions (TalentCondFilterPass): stays silent.
    if fc2 and fc2.tcHidden then fd._cdReadyArmed = false; return end
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then return end
    if bk2 == ns.FOCUSKICK_BAR_KEY then return end
    if bk2:sub(1, 7) == "__ghost" then return end
    local ss2 = ResolveSpellSettings(frame, sid2, ns.GetBarSpellData(bk2))
    local key = ss2 and ss2.cdReadySoundKey
    if not key or key == "none" then fd._cdReadyArmed = false; return end
    if ns._cdmSoundSuppressed() then
        -- Settle window: cooldown reads are transient, so gate the ARM (not just
        -- the fire) and clear stale arms. A spell genuinely on cooldown re-arms
        -- on the next SPELL_UPDATE_COOLDOWN after the window: no edge lost.
        fd._cdReadyArmed = false
        return
    end
    local liveSid = sid2
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
    end
    if not CdReadyIsReady(liveSid) then
        -- On cooldown (or a charge spell below max): arm.
        if not fd._cdReadyArmed then fd._cdReadyArmedAt = GetTime() end
        fd._cdReadyArmed = true
        fd._cdReadyArmedSid = sid2
    elseif fd._cdReadyArmed and not primeOnly and CdReadyIsReady(liveSid, true) then
        if fd._cdReadyArmedSid ~= sid2 then
            -- Spell on this frame changed since arming (spec/talent swap); stale arm.
            fd._cdReadyArmed = false
            return
        end
        -- Became ready. Confirm one frame later (let the API settle) before playing.
        if not fd._cdReadyPending then
            fd._cdReadyPending = CreateFrame("Frame")
            fd._cdReadyPending:Hide()
            fd._cdReadyPending:SetScript("OnUpdate", function(self)
                self:Hide()
                if not fd._cdReadyArmed then return end
                local fcp = _ecmeFC[frame]
                local sidp = fcp and fcp.spellID
                local bkp = fcp and fcp.barKey
                if not sidp or not bkp then return end
                if fd._cdReadyArmedSid ~= sidp then fd._cdReadyArmed = false; return end
                local ssp = ResolveSpellSettings(frame, sidp, ns.GetBarSpellData(bkp))
                local kp = ssp and ssp.cdReadySoundKey
                if not kp or kp == "none" then fd._cdReadyArmed = false; return end
                local livep = sidp
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    livep = C_SpellBook.FindSpellOverrideByID(sidp) or sidp
                end
                if not CdReadyIsReady(livep, true) then return end  -- not ready (race/GCD) -> stay armed
                if ns._cdmSoundSuppressed() then fd._cdReadyArmed = false; return end  -- a load began mid-defer
                -- Sub-GCD arm span = transient misread, not a real cooldown ending.
                local armedAt = fd._cdReadyArmedAt
                if not armedAt or (GetTime() - armedAt) < CD_READY_MIN_ARM then
                    fd._cdReadyArmed = false
                    return
                end
                PlayCdReadySound(fd, kp, livep, sidp, bkp, "event")
            end)
        end
        fd._cdReadyPending:Show()
    end
end

-- PRIMARY driver for non-charge spells: Blizzard's "cooldown just became
-- available" edge. The client dispatches NO event on cooldown expiry;
-- TriggerAvailableAlert simulates the final SPELL_UPDATE_COOLDOWN from the
-- viewer's OnUpdate against the real endTime (riding SPELL_UPDATE_COOLDOWN alone
-- never sees the expiry). Post-hooking the alert is the same taint-safe idiom as
-- EnsureBuffSoundHook on TriggerAuraAppliedAlert: no secret duration read, lands
-- on the exact frame. Charge spells stay with the SPELL_UPDATE_CHARGES watcher:
-- this alert fires on the FIRST charge, but CDM readiness means back at MAX.
local _cdReadyAlertHooked = setmetatable({}, { __mode = "k" })
local function HookCdReadyAvailableAlert(frame, fd)
    if _cdReadyAlertHooked[frame] then return end
    if type(frame.TriggerAvailableAlert) ~= "function" then
        _cdReadyAlertHooked[frame] = true   -- own placeholder / injected frame: no alert
        return
    end
    _cdReadyAlertHooked[frame] = true
    hooksecurefunc(frame, "TriggerAvailableAlert", function(f)
        if not ns._cdmAnyCdReadySound then return end
        if fd._isProcessingOverride then return end
        -- A buff frame's alert fires on AURA gain, not readiness (see the watch below).
        if fd._isBuffViewerFrame or f._isCustomBuffFrame or f._isPlaceholderFrame then return end
        local fca = _ecmeFC[f]
        local sida = fca and fca.spellID
        local bka = fca and fca.barKey
        if not sida or not bka then return end
        if fca.tcHidden then return end  -- hidden by its Talent Conditions
        if bka == ns.FOCUSKICK_BAR_KEY then return end
        if bka:sub(1, 7) == "__ghost" then return end
        local ssa = ResolveSpellSettings(f, sida, ns.GetBarSpellData(bka))
        local keya = ssa and ssa.cdReadySoundKey
        if not keya or keya == "none" then return end
        if ns._cdmSoundSuppressed() then fd._cdReadyArmed = false; return end
        local livea = sida
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            livea = C_SpellBook.FindSpellOverrideByID(sida) or sida
        end
        if CdReadyIsChargeSpell(livea) then return end
        PlayCdReadySound(fd, keya, livea, sida, bka, "alert")
    end)
end

-- Register a spell with a CD-ready sound into the event-driven watch set,
-- evaluated on SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES (refill to max),
-- reading isActive/isOnGCD once state settles: covers arming, charge readiness
-- and cooldown RESETS. The expiry edge belongs to the available-alert hook above
-- (this pass backs it up between GCDs); there is NO SetDesaturated driver.
function ns.WatchCdReadySoundIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    -- Buff-family frames never watch: a hosted or custom buff frame resolves the
    -- ABILITY's per-spell entry through the linked-id union, and its
    -- TriggerAvailableAlert fires on aura gain (no readiness check in the hook), so
    -- the cd-ready cue played at buff gain. Same exclusion as the charge hooks.
    if fd._isBuffViewerFrame or frame._isCustomBuffFrame or frame._isPlaceholderFrame then
        if ns._cdReadySoundWatch[frame] then ns._cdReadySoundWatch[frame] = nil end
        return
    end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if ssw and ssw.cdReadySoundKey and ssw.cdReadySoundKey ~= "none" then
        ns._cdmAnyCdReadySound = true
        ns._cdReadySoundWatch[frame] = fd
        if not ns._cdReadySoundEventFrame then
            local ef = ns.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for f, d in pairs(ns._cdReadySoundWatch) do
                    EvalCdReadySound(f, d)
                end
            end)
            ns._cdReadySoundEventFrame = ef
        end
        HookCdReadyAvailableAlert(frame, fd)
        EvalCdReadySound(frame, fd, true)  -- prime the arm state only; never plays here
    elseif ns._cdReadySoundWatch[frame] then
        ns._cdReadySoundWatch[frame] = nil
    end
end

-------------------------------------------------------------------------------
--  Hide CD Text (Charges) -- per-spell (CD/utility bars only)
--  While a CHARGE spell has a usable charge in hand, hide the recharge countdown
--  numbers; they return once every charge is spent (0 charges == on a real
--  cooldown), so the full countdown shows when unavailable. "charges > 0"
--  derives from CLEAN GetSpellCooldown() flags: charge in hand <=> not
--  (isActive and not isOnGCD) -- isActive alone is wrong (true during the GCD
--  right after a cast even with a charge left). Charge-spell test:
--  GetSpellCharges().maxCharges > 1 (stable through the GCD), never
--  HasVisualDataSource_Charges (flips false during a GCD swipe); neither reads
--  the secret currentCharges. Driven by SPELL_UPDATE_CHARGES (same as Max Stacks
--  Glow), catching the topping-off edge the cooldown-widget hooks miss. Gated on
--  ns._cdmAnyChargeHideCdText (~0 cost when unused).
-------------------------------------------------------------------------------

-- Per-spell Duration Text layered onto a bar-derived hide flag, for the paths that hold only
-- barData: the reanchor assign loop and the Only Show Numbers restore tail. The appearance
-- pass does not call this -- it resolves ssb itself, and re-resolving there would replace a
-- correct value with a worse one. Keyed on the DISPLAYED id, never fc.spellID: for a buff
-- whose base is a shared spec spell the base misses the entry and lets one icon's setting
-- shadow another's, the same rule the appearance pass documents at its own resolve.
-- ~= nil, not truthiness: a per-spell ON must beat a bar that is OFF.
function ns.CdmDurationHideFor(frame, barKey, baseHide)
    if not ns._cdmAnySpellDurationText then return baseHide end
    local fcd = _ecmeFC[frame]
    local sidD = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(frame))
        or (fcd and fcd.spellID)
    if not (sidD and barKey and ns.ResolveSpellSettings) then return baseHide end
    local ssD = ns.ResolveSpellSettings(frame, sidD, ns.GetBarSpellData(barKey), barKey)
    if ssD and ssD.showCooldownText ~= nil then return not ssD.showCooldownText end
    return baseHide
end

-- Effective SetHideCountdownNumbers value: layers the per-spell "Hide CD Text
-- (Charges)" toggle on the caller's baseHide (numbers already hidden by the bar
-- / per-icon showCooldownText). Returns baseHide unchanged for anything that is
-- not an enabled charge spell, so callers can wrap unconditionally.
function ns.CdmShouldHideCountdown(frame, baseHide)
    -- Charges/Stacks Only (No Icon) hides the duration outright (the counter is the
    -- whole display). Checked AHEAD of the feature gate so it holds for every caller --
    -- the appearance pass, reanchor loop and SPELL_UPDATE_CHARGES watcher all route
    -- countdown writes through here, so no per-site force is needed. (Only Show Numbers
    -- never sets the flag: there the number IS the display.)
    local fdc = hookFrameData[frame]
    if fdc and fdc._osnHideText then return true end
    if not ns._cdmAnyChargeHideCdText then return baseHide end
    if baseHide then return true end  -- already hidden by the bar/per-icon setting
    local ss = ns._ResolveCdmSS(frame)
    if not (ss and ss.chargeHideCdText) then return baseHide end
    local fc = _ecmeFC[frame]
    local sid = fc and fc.spellID
    if not sid then return baseHide end
    local liveSid = sid
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sid) or sid
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then return baseHide end
    -- "charges > 0" <=> NOT on a real (non-GCD) cooldown; the isOnGCD term is
    -- required (isActive alone is true through every post-cast GCD). Both flags
    -- clean; the secret currentCharges is never read.
    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(liveSid)
    if not cdInfo then return baseHide end
    local onRealCd = cdInfo.isActive and not cdInfo.isOnGCD
    if not onRealCd then return true end  -- at least one charge -> hide duration
    return baseHide
end

-- Only icons with the toggle enabled live in this set, so each SPELL_UPDATE_CHARGES
-- iterates a tiny table; the event frame is created lazily on first watch.
ns._chargeCdTextWatch = ns._chargeCdTextWatch or setmetatable({}, { __mode = "k" })

-- Re-apply the countdown-number visibility for one watched charge frame from the
-- current charge state. Self-unwatches when the setting is off or the frame lost
-- its spell, so the set drains itself (mirrors EvalMaxStacksFrame).
local function EvalChargeCdTextFrame(frame, fd)
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    local cd = (fd and fd.cooldown) or frame.Cooldown
    if not sidw or not bkw or not cd or not cd.SetHideCountdownNumbers then
        ns._chargeCdTextWatch[frame] = nil
        return
    end
    local bd = barDataByKey and barDataByKey[bkw]
    local baseHide = not ns.CdmDurationTextOn(bd)
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    if not (ssw and ssw.chargeHideCdText) then
        -- Setting off: restore the bar's showCooldownText result and unwatch
        -- (per-icon showCooldownText exists only on buff bars, which never
        -- enable this charge toggle, so the bar value is right).
        ns._chargeCdTextWatch[frame] = nil
        -- Through the resolver, not raw: returns baseHide unchanged but still
        -- honours Charges/Stacks Only, so no duration flash on a no-icon bar.
        cd:SetHideCountdownNumbers(ns.CdmShouldHideCountdown(frame, baseHide))
        return
    end
    cd:SetHideCountdownNumbers(ns.CdmShouldHideCountdown(frame, baseHide))
end

local function WatchChargeCdTextFrame(frame, fd)
    ns._chargeCdTextWatch[frame] = fd
    if not ns._chargeCdTextEventFrame then
        local ef = ns.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._chargeCdTextWatch) do
                EvalChargeCdTextFrame(f, d)
            end
        end)
        ns._chargeCdTextEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so a charge
-- spell at max (no recharge text, never fires the swipe hook) still gets watched
-- for the moment it dips below max. Early-outs on non-charge icons; once watched
-- SPELL_UPDATE_CHARGES keeps it current. Self-cleans when the setting is off.
function ns.WatchChargeCdTextIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then return end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    local isCharge = ci ~= nil and (ci.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw)) or nil
    if ssw and ssw.chargeHideCdText then
        ns._cdmAnyChargeHideCdText = true
        WatchChargeCdTextFrame(frame, fd)
        EvalChargeCdTextFrame(frame, fd)
    elseif ns._chargeCdTextWatch[frame] then
        ns._chargeCdTextWatch[frame] = nil
        EvalChargeCdTextFrame(frame, fd)
    end
end

-------------------------------------------------------------------------------
--  "Hide Text at 0 Stacks" (bar-level, cd/utility bars): hide the charge counter
--  (frame.ChargeCount.Current) while a charge spell is genuinely OUT of charges
--  instead of showing a 0. The count IS the alpha: SetAlpha clamps to [0,1]
--  engine-side, so alpha := currentCharges hides at exactly 0 and shows at 1+
--  with no comparison, and SetAlpha accepts secret numbers (SecretArguments
--  AllowedWhenTainted), so the same write runs in and out of instanced combat
--  (secret count written through, memo dirtied, never stored/compared). The
--  clean-flag inference "real non-GCD cooldown = zero charges" is NOT universal
--  -- Roll-class wiring and talent-granted charges on cooldown spells like Feint
--  / Survival of the Fittest keep the main cooldown record active while charges
--  are banked -- so it's unused here; CdmShouldHideCountdown still uses it,
--  harmlessly showing the duration where it could hide it. Driven by the same
--  SPELL_UPDATE_CHARGES edge as the other charge features (lazy shell, self-
--  draining watch set, zero cost for non-users). Alpha not Hide: the engine
--  rewrites the counter's TEXT on charge changes but never its alpha.
-------------------------------------------------------------------------------
ns._zeroChargeTextWatch = ns._zeroChargeTextWatch or setmetatable({}, { __mode = "k" })

-- Paint-the-delta memo: SetAlpha only on a real change. The engine rewrites the
-- counter's TEXT but never its alpha, so the stamp stays truthful.
local function ZctSetAlpha(fd, fs, a)
    if fd._zctAlpha ~= a then
        fd._zctAlpha = a
        fs:SetAlpha(a)
    end
end

local function EvalZeroChargeTextFrame(frame, fd)
    local fs = frame.ChargeCount and frame.ChargeCount.Current
    local fcz = _ecmeFC[frame]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    if not fs or not sidz or not bkz then
        ns._zeroChargeTextWatch[frame] = nil
        if fs then ZctSetAlpha(fd, fs, 1) end
        return
    end
    -- Per-spell "Hide Charge Text" (cd-state menu): a STATIC hide riding this
    -- feature's alpha channel and memo, so the two can never fight over the
    -- counter. It outranks the zero-charge logic; charge events land here and
    -- simply keep the 0.
    local sss = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
    if sss and sss.hideChargeText then
        ZctSetAlpha(fd, fs, 0)
        return
    end
    local bd = barDataByKey and barDataByKey[bkz]
    if not (bd and bd.hideZeroChargeText) then
        ns._zeroChargeTextWatch[frame] = nil
        ZctSetAlpha(fd, fs, 1)
        return
    end
    local liveSid = sidz
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
    end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then
        -- Not a charge spell (talent changed since enrollment): restore and
        -- unwatch; the appearance pass re-enrolls if charge-ness returns, which
        -- keeps the per-event set charge-spells-only.
        ns._zeroChargeTextWatch[frame] = nil
        ZctSetAlpha(fd, fs, 1)
        return
    end
    -- Alpha := currentCharges (see header). Secret count: same write, memo dirtied.
    local cc = ci.currentCharges
    -- issecretvalue FIRST, and type() rather than == nil for the missing case.
    -- currentCharges is secret whenever cooldowns are restricted (combat,
    -- encounter, challenge mode, PvP match), and comparing a secret to nil is
    -- the exact operation this addon's own secret rules forbid. Ordering the
    -- nil "belt" ahead of the guard made the belt the hazard: a throw here
    -- aborts the eval with the alpha still 0, so the counter stays HIDDEN until
    -- the next SPELL_UPDATE_CHARGES -- which for a charge spell that just
    -- refilled is a whole recharge away. That is the reported "0 -> 1 hides the
    -- stack count temporarily". The throw also kills the pairs() loop in the
    -- event handler, so every other watched icon stops updating with it.
    if issecretvalue and issecretvalue(cc) then
        fd._zctAlpha = nil
        fs:SetAlpha(cc)
    elseif type(cc) ~= "number" then
        ZctSetAlpha(fd, fs, 1)
    else
        ZctSetAlpha(fd, fs, cc > 1 and 1 or cc)
    end
end

function ns.WatchZeroChargeTextIfEnabled(frame)
    if not frame then return end
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcz = _ecmeFC[frame]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    -- Per-spell "Hide Charge Text": static, so this appearance-pass call is
    -- its whole driver -- no event watch needed. A frame the bar feature has
    -- watched keeps its enrollment; the eval's own short-circuit holds the 0.
    if sidz and bkz then
        local sss = ns._ResolveCdmSS and ns._ResolveCdmSS(frame)
        if sss and sss.hideChargeText then
            local fsh = frame.ChargeCount and frame.ChargeCount.Current
            if fsh then ZctSetAlpha(fd, fsh, 0) end
            return
        end
    end
    local bd = bkz and barDataByKey and barDataByKey[bkz]
    if bd and bd.hideZeroChargeText and sidz then
        -- Enroll CHARGE SPELLS ONLY: non-charge icons would be pure identity
        -- work per event. Talent swaps re-run this via the appearance pass; the
        -- eval self-unwatches the other direction.
        local liveSid = sidz
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            liveSid = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
        end
        local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
        if not (ci and (ci.maxCharges or 0) > 1) then
            if ns._zeroChargeTextWatch[frame] then EvalZeroChargeTextFrame(frame, fd) end
            return
        end
        if not ns._zeroChargeTextEventFrame then
            local ef = ns.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for f, d in pairs(ns._zeroChargeTextWatch) do
                    EvalZeroChargeTextFrame(f, d)
                end
            end)
            ns._zeroChargeTextEventFrame = ef
        end
        ns._zeroChargeTextWatch[frame] = fd
        EvalZeroChargeTextFrame(frame, fd)
    elseif ns._zeroChargeTextWatch[frame] then
        -- Setting off: the eval's off-branch unwatches + restores alpha.
        EvalZeroChargeTextFrame(frame, fd)
    else
        -- Hide Charge Text just turned off with no watch left to restore for
        -- it: put the counter back. Memoized, so a neither-feature icon pays
        -- one SetAlpha(1) ever.
        local fsr = frame.ChargeCount and frame.ChargeCount.Current
        if fsr then ZctSetAlpha(fd, fsr, 1) end
    end
end

-------------------------------------------------------------------------------
--  Charge counter on SPELL_UPDATE_CHARGES. Blizzard_CooldownViewer does not
--  register the event, so a proc that hands charges to a chargeless spell
--  reaches the icon only at its next RefreshData, seconds later. Mirrors
--  RefreshSpellChargeInfo's charge branch (maxCharges > 1, NeverSecret) from
--  the frame's own GetSpellChargeInfo; SetText takes a secret count. Not
--  routed through RefreshSpellChargeInfo: SetCachedChargeValues compares
--  currentCharges, secret while cooldowns are restricted. Show() is
--  unconditional because the counter's shown aspect is secret once Blizzard
--  set it from a secret cast count. Frames this wrote are hidden again when
--  maxCharges drops back; the rest stays with Blizzard. No payload.
-------------------------------------------------------------------------------
do
    local wrote = setmetatable({}, { __mode = "k" })

    local function WriteChargeCount(frame)
        local cc = frame.ChargeCount
        local fs = cc and cc.Current
        if not fs then return end
        local ci = CdmChargeInfoFor(frame, nil)
        if ci and (ci.maxCharges or 0) > 1 then
            fs:SetText(ci.currentCharges)
            cc:Show()
            wrote[frame] = true
        elseif wrote[frame] then
            wrote[frame] = nil
            cc:Hide()
        end
    end

    local ef = ns.TakeShell()
    ef:RegisterEvent("SPELL_UPDATE_CHARGES")
    ef:SetScript("OnEvent", function()
        if IsCDMSettingsOpen() then return end
        for vi = 1, 2 do
            local viewer = GetViewerFrame(vi)
            local pool = viewer and viewer.itemFramePool
            if pool and pool.EnumerateActive then
                for frame in pool:EnumerateActive() do
                    WriteChargeCount(frame)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Cooldown State Effect -- charge-aware readiness for Hidden (CD Ready)
--  For a CHARGE spell "CD Ready" must mean AT MAX CHARGES, not "a charge in
--  hand": GetSpellCooldown().isActive is false with a charge left, so a plain
--  read calls a recharging spell "ready" and the icon vanishes mid-recharge --
--  exactly the countdown this mode exists to watch. Read the recharge flag
--  instead (GetSpellCharges().isActive: true from the first spent charge until
--  the last refills, the clean Max Stacks Glow signal); maxCharges > 1 is the
--  charge-spell test (stable through the GCD, unlike HasVisualDataSource_Charges);
--  non-charge spells keep the caller's cooldown read. Secret currentCharges
--  never read. Per-spell "+ Stay Hidden While Charges Remain"
--  (ss.chargeHideUntilSpent) opts back into "hidden only once fully spent".
--  Deliberately NOT used by other cd-state effects: those answer "can I press
--  this?" (Hidden/Lower Alpha On CD suppress the uncastable, ready-glows
--  highlight the castable) and a charge spell down one stack IS castable --
--  Hidden (CD Ready) is the only mode tracking the countdown.
-------------------------------------------------------------------------------
function ns.CdmCdStateReady(liveSid, onCD, hideUntilSpent)
    if hideUntilSpent then return not onCD end
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if ci and (ci.maxCharges or 0) > 1 then return not ci.isActive end
    return not onCD
end

-- Hidden Until Usable: the spell counts as unavailable while it cannot be used
-- for any reason but missing power, so a reactive spell (Overpower, Victory
-- Rush, Execute) shows once its proc or condition is up, tinted by Blizzard
-- while rage / energy / mana is short, and power ticks never flip the answer.
-- IsSpellUsable returns plain booleans on every client.
function ns.CdmSpellNotUsable(liveSid)
    local usable, noPower = C_Spell.IsSpellUsable(liveSid)
    return not (usable or noPower)
end

-- Deferred cd-state evaluator for the hide / lower-alpha modes, shared by the
-- SetDesaturated hook (every cooldown transition) and the charge watch below.
-- Deferred one frame because SetDesaturated fires inside Blizzard's secure CDM
-- chain where GetSpellCooldown can briefly disagree with Blizzard's own
-- evaluation (charge spells report isActive with charges left, GCD tail races).
-- The OnUpdate script is installed ONCE per frame object: the hook fires per
-- repaint, so per-arm work stays plain field writes, never closure creation.
local function ArmCdStateEval(frame, fd, cse, cseShift, lowAlpha, hideUntilSpent, usable)
    local pending = fd._cdStatePending
    if not pending then
        pending = CreateFrame("Frame")
        pending:Hide()
        fd._cdStatePending = pending
        pending:SetScript("OnUpdate", function(self)
            self:Hide()
            local fc3 = _ecmeFC[frame]
            local sid3 = fc3 and fc3.spellID
            local bk3 = fc3 and fc3.barKey
            if not sid3 or not bk3 then return end
            local liveSid = sid3
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                liveSid = C_SpellBook.FindSpellOverrideByID(sid3) or sid3
            end
            local onCD
            -- Hidden Until Usable arrives as Hidden (On CD) with this flag: an
            -- unusable spell hides whatever its cooldown, so that read is skipped.
            if self.usable and ns.CdmSpellNotUsable(liveSid) then
                onCD = true
            else
                local cseInfo = C_Spell.GetSpellCooldown(liveSid)
                onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
            end
            local myCse = self.cse
            local bd3 = barDataByKey and barDataByKey[bk3]
            local baseA = ns.IconShownAlpha(fc3, bd3)
            if myCse == "lowerAlphaOnCD" then
                -- Lowered (not hidden): reuse _cdStateHidden as the "cd-state
                -- owns this alpha" flag so the opacity appliers leave the lowered
                -- value alone. A visibility-hidden bar (baseA 0) stays 0 either way.
                frame:SetAlpha(baseA == 0 and 0
                    or (onCD and (self.lowAlpha or 0.5) or baseA))
                if fc3 then
                    fc3._cdStateHidden = onCD or false
                    if ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc3, false)
                    end
                end
            else
                local hide
                if myCse == "hiddenOnCD" then
                    hide = onCD
                else
                    -- Hidden (CD Ready): on a charge spell "ready" is max
                    -- charges, so the icon keeps tracking the recharge.
                    hide = ns.CdmCdStateReady(liveSid, onCD, self.hideUntilSpent)
                end
                frame:SetAlpha(hide and 0 or baseA)
                if fc3 then
                    fc3._cdStateHidden = hide or false
                    if ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc3, self.shift and hide or false)
                    end
                end
            end
        end)
    end
    -- All captured at arm time (settings, not volatile state); only
    -- lowerAlphaOnCD reads lowAlpha, only the CD-Ready modes read hideUntilSpent.
    pending.cse = cse
    pending.lowAlpha = lowAlpha
    pending.shift = cseShift
    pending.hideUntilSpent = hideUntilSpent
    pending.usable = usable
    pending:Show()
end

-------------------------------------------------------------------------------
--  Hidden (CD Ready) on charge spells: refill-edge coverage
--  The mode's SetDesaturated driver fires when a charge is SPENT but NOT when
--  the last charge REFILLS to max -- the gap SPELL_UPDATE_CHARGES closes (both
--  charge transitions, nothing else, far cheaper than SPELL_UPDATE_COOLDOWN).
--  Without it a topped-off charge spell stays visible forever: at max charges
--  nothing repaints the icon. Only icons running the mode on a charge spell
--  enter the set, and it self-drains (eval unwatches dead effects/spells).
-------------------------------------------------------------------------------
ns._cdStateChargeWatch = ns._cdStateChargeWatch or setmetatable({}, { __mode = "k" })

local function EvalCdStateChargeFrame(frame, fd)
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    local ssw = ResolveSpellSettings(frame, sidw, ns.GetBarSpellData(bkw))
    local csew = ns.GetSpellCdStateEffect(frame, ssw)
    if csew ~= "hiddenReady" and csew ~= "hiddenReadyShift" then
        -- Effect changed or cleared: the desat hook owns every other mode.
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    ArmCdStateEval(frame, fd, "hiddenReady", csew == "hiddenReadyShift",
        nil, ssw.chargeHideUntilSpent)
end

-- Register an icon whose resolved effect is Hidden (CD Ready) (callers check)
-- when its spell has charges; non-charge spells never enter the set, their real
-- CD-end edge fires the desat hook. Called from that hook (on spell rebinding)
-- and RefreshCDMIconAppearance.
function ns.WatchCdStateChargeIfEnabled(frame)
    local fd = hookFrameData[frame]
    if not fd then return end
    local fcw = _ecmeFC[frame]
    local sidw = fcw and fcw.spellID
    if not sidw then return end
    local liveSid = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSid = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local ci = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSid)
    if not (ci and (ci.maxCharges or 0) > 1) then
        ns._cdStateChargeWatch[frame] = nil
        return
    end
    ns._cdStateChargeWatch[frame] = fd
    if not ns._cdStateChargeEventFrame then
        local ef = ns.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for f, d in pairs(ns._cdStateChargeWatch) do
                EvalCdStateChargeFrame(f, d)
            end
        end)
        ns._cdStateChargeEventFrame = ef
    end
end

-------------------------------------------------------------------------------
--  Hidden Until Usable: proc edges
--  The mode runs as Hidden (On CD) with "not usable" counting as unavailable,
--  so its cooldown edges ride the SetDesaturated hook like every hidden mode.
--  A proc (Overpower after a dodge, Victory Rush after a kill) changes only
--  usability, which Blizzard's own icons follow through SPELL_UPDATE_USABLE.
--  That event is registered only while an icon runs the mode; a burst folds
--  into one pass on the next frame, which re-resolves each watched icon (an
--  icon whose mode, spell or owner changed leaves the set) and re-arms the
--  shared evaluator. The set drains itself, then the event unregisters.
-------------------------------------------------------------------------------
do
    local watch = setmetatable({}, { __mode = "k" })  -- icon frame -> true
    local eventFrame, flushFrame

    local function Flush(self)
        self:Hide()
        for frame in pairs(watch) do
            local fd = hookFrameData[frame]
            local fc = _ecmeFC[frame]
            local sid = fc and fc.spellID
            local bk = fc and fc.barKey
            local cse
            -- Same ownership guards as the SetDesaturated hook.
            if fd and sid and bk and bk:sub(1, 7) ~= "__ghost" and bk ~= ns.FOCUSKICK_BAR_KEY
               and not (ns.PresetHasCdState and ns.PresetHasCdState(frame)) then
                cse = ns.GetSpellCdStateEffect(frame, ResolveSpellSettings(frame, sid, false))
            end
            if cse == "hiddenUnusable" or cse == "hiddenUnusableShift" then
                ArmCdStateEval(frame, fd, "hiddenOnCD", cse == "hiddenUnusableShift", nil, nil, true)
            else
                watch[frame] = nil
            end
        end
        if not next(watch) then eventFrame:UnregisterEvent("SPELL_UPDATE_USABLE") end
    end

    -- Called wherever the mode is resolved for an icon (SetDesaturated hook,
    -- RefreshCDMIconAppearance). One table read once the icon is watched.
    function ns.WatchCdUsable(frame)
        if watch[frame] then return end
        watch[frame] = true
        if not eventFrame then
            flushFrame = ns.TakeShell()
            flushFrame:Hide()
            flushFrame:SetScript("OnUpdate", Flush)
            eventFrame = ns.TakeShell()
            eventFrame:SetScript("OnEvent", function() flushFrame:Show() end)
        end
        eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
    end
end

-------------------------------------------------------------------------------
--  Swiftmend brightness: Blizzard dims the icon via SetVertexColor when
--  Efflorescence / HoTs drop. Hook the icon texture once to force bright.
--  Recursion guard only -- never compare incoming args (secret values).
--  Retried on EVERY DecorateFrame call: spell-ID resolution can miss on a
--  frame's first pass (cooldownID not yet assigned) and a decorated-flag early
--  return would make that permanent. Free: non-Druids skip on the cached class
--  check, hooked frames on one flag read.
-------------------------------------------------------------------------------
local SWIFTMEND_SID = 18562
local _smHookedIcons = {}
local function SwiftmendEnabled()
    return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
end
local function TryHookSwiftmend(frame, fd)
    if not _isDruid or fd._smVCHooked then return end
    local iconWidget = fd.tex
    if not iconWidget then return end
    local dispSID, baseSID = ResolveFrameSpellID(frame)
    if dispSID and issecretvalue(dispSID) then dispSID = nil end
    if baseSID and issecretvalue(baseSID) then baseSID = nil end
    if baseSID ~= SWIFTMEND_SID and dispSID ~= SWIFTMEND_SID then return end
    fd._smVCHooked = true
    _smHookedIcons[#_smHookedIcons + 1] = iconWidget
    local smGuard = false
    hooksecurefunc(iconWidget, "SetVertexColor", function()
        if smGuard then return end
        if not SwiftmendEnabled() then return end
        smGuard = true
        iconWidget:SetVertexColor(1, 1, 1)
        smGuard = false
    end)
    if SwiftmendEnabled() then iconWidget:SetVertexColor(1, 1, 1) end
end


-------------------------------------------------------------------------------
--  Per-spell Custom Icon
--  Stamp the configured replacement icon (texture fileID) over the icon texture,
--  from DecorateFrame on every (re)claim and from a per-frame
--  RefreshSpellTexture post-hook (installed on first gated visit), so it
--  survives every Blizzard repaint AND spell transforms: RefreshSpellTexture is
--  the ONLY writer of a viewer item's icon texture (every item type's
--  RefreshData + SPELL_UPDATE_ICON), and the settings resolver matches the
--  stored key against the frame's full identity set. Purely per-spell, never
--  written to bar tiers. Gated on ns._cdmAnyCustomIcon (one boolean, no hooks
--  installed for non-users). Clear/restore: when the setting is removed the last
--  stamped frame (fd._customIconOn) restores its real icon once via
--  C_Spell.GetSpellTexture (base id; API resolves live overrides, next
--  RefreshData corrects aura/link nuance). NEVER call the frame's own
--  RefreshSpellTexture for this -- running Blizzard mixin code from insecure
--  context can write tainted values into the frame's table.
-------------------------------------------------------------------------------
local function ApplyCustomIcon(frame, fd)
    if not ns._cdmAnyCustomIcon then return end
    fd = fd or hookFrameData[frame]
    local tex = fd and fd.tex
    if not tex then return end
    -- Per-frame re-assert hook. Must hook the frame INSTANCE: leaf-mixin functions are
    -- COPIED onto each item frame at creation, so a hooksecurefunc on the mixin table
    -- never fires for frames that predate the install (the custom icon then reverts on
    -- every cast, RefreshData repainting the real icon). Same per-frame pattern as the
    -- SetDesaturated hooks. Injected/own frames have no RefreshSpellTexture and skip it
    -- (nothing Blizzard-side repaints them; the claim-path stamps suffice).
    if not fd._ciHooked and frame.RefreshSpellTexture then
        fd._ciHooked = true
        hooksecurefunc(frame, "RefreshSpellTexture", ApplyCustomIcon)
    end
    local ss = ns._ResolveCdmSS(frame)
    local ci = ss and ss.customIcon
    if type(ci) == "number" and ci > 0 then
        tex:SetTexture(ci)
        fd._customIconOn = true
    elseif fd._customIconOn then
        -- Restore ONLY with a resolvable identity: a nil sid means the identity
        -- cache is transiently empty (bar-rebuild mid-login), not that the user
        -- cleared the setting, so keep the flag armed for the next pass.
        local fc = _ecmeFC[frame]
        local sid = fc and (fc.resolvedSid or fc.spellID)
        if type(sid) == "number" and not (issecretvalue and issecretvalue(sid))
           and sid > 0 and C_Spell and C_Spell.GetSpellTexture then
            fd._customIconOn = nil
            local real = C_Spell.GetSpellTexture(sid)
            if real then tex:SetTexture(real) end
        end
    end
end
ns.ApplyCustomIcon = ApplyCustomIcon

-------------------------------------------------------------------------------
--  Icon-art suppression (two bar settings, one machine)
--    buff-family bars: "Only Show Numbers"            -> barData.onlyShowNumbers
--    cd/utility bars:  "Charges/Stacks Only (No Icon)" -> barData.chargesOnly
--  Both hide icon texture, background, square border, shape ring, Blizzard
--  debuff border, swipe and recharge edge; they differ only in the countdown:
--  Only Show Numbers leaves it to the normal Duration Text settings (bar toggle
--  + per-icon overrides; off = stacks-only), Charges/Stacks Only forces it OFF.
--  Swipe, edge and countdown have writers that re-assert between our passes, so
--  each is gated at its own choke point: the SetDrawSwipe hook and
--  ApplyCdmChargeStyle (owner of ApplyCdmEdge) read _osnOn; the resolver every
--  countdown writer funnels through, ns.CdmShouldHideCountdown, reads
--  _osnHideText. Every hide is REGION-level, never frame alpha: frame.ChargeCount
--  / frame.Applications are siblings of the icon (on container-Icon frames the
--  stack text is at Icon.Applications), so frame:SetAlpha(0)/Icon:SetAlpha(0)
--  would take the counters with it; fd.tex is already resolved to the leaf
--  texture by DecorateFrame's GetTexture descent. Applied from DecorateFrame on
--  every (re)claim and re-asserted at the end of RefreshCDMIconAppearance's
--  per-icon pass (which re-applies borders/shapes and would otherwise undo the
--  hides). Hides are alpha/shown/flag based with regions staying live, so
--  turning the setting off restores one-shot via fd._osnOn (pooled frames
--  moving to a bar without the setting restore the same way); normal style
--  passes re-assert the rest. Cost when off: one field read per call.
-------------------------------------------------------------------------------
local function ApplyOnlyNumbers(frame, fd, barData)
    if not barData then return end
    fd = fd or hookFrameData[frame]
    local osn = barData.onlyShowNumbers
    if osn or barData.chargesOnly then
        -- Set BEFORE the swipe/edge writes: the per-frame SetDrawSwipe/
        -- SetDrawEdge hooks force defaults for non-charge frames and read _osnOn
        -- to stand down (buff frames early-out on _isBuffViewerFrame and never
        -- reach that hook, which is why cd/utility needed the gate).
        -- _osnHideText tells ns.CdmShouldHideCountdown the duration is
        -- suppressed; every countdown writer resolves through it.
        if fd then
            fd._osnOn = true
            fd._osnHideText = (not osn) or nil
        end
        local tex = (fd and fd.tex) or frame._tex
        if tex then
            tex:SetAlpha(0)
            -- Hide() too, load-bearing on cd/utility: Texture SetAlpha and
            -- SetVertexColor share ONE alpha slot on this client, and the
            -- resource-dim pass writes a 3-arg SetVertexColor on injected
            -- custom-spell icons, resetting alpha to 1 and popping the art back.
            -- Shown-state is an independent channel no colour writer can touch,
            -- and nothing in the addon Shows an icon texture.
            tex:Hide()
        end
        local bg = (fd and fd.bg) or frame._bg
        if bg then bg:SetAlpha(0) end
        if fd and fd.borderFrame then
            EllesmereUI.PP.HideBorder(fd.borderFrame)
            local bdFrame = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[fd.borderFrame]
            if bdFrame then bdFrame:Hide() end
        end
        local ifc = _ecmeFC[frame]
        if ifc and ifc.shapeBorder then ifc.shapeBorder:SetAlpha(0) end
        -- Blizzard Style ring goes with the art (the custom-aura buttons hide theirs too).
        if ifc and ifc.blizzHost then ifc.blizzHost:Hide() end
        if frame.DebuffBorder then frame.DebuffBorder:SetAlpha(0) end
        local cd = (fd and fd.cooldown) or frame.Cooldown or frame._cooldown
        if cd then
            if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
            -- No icon means no recharge edge either.
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
            -- Charges/Stacks Only forces the countdown OFF. The buff variant does
            -- NOT touch it: the duration follows the normal Duration Text
            -- settings, applied by the appearance pass before this re-hide tail.
            if (not osn) and cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        end
    elseif fd and fd._osnOn then
        fd._osnOn = nil
        fd._osnHideText = nil
        local tex = fd.tex or frame._tex
        if tex then tex:SetAlpha(1); tex:Show() end
        local bg = fd.bg or frame._bg
        if bg then bg:SetAlpha(1) end
        local ifc = _ecmeFC[frame]
        if ifc and ifc.shapeBorder then ifc.shapeBorder:SetAlpha(1) end
        if ifc and ifc.blizzHost then ifc.blizzHost:Show() end
        if frame.DebuffBorder then frame.DebuffBorder:SetAlpha(1) end
        local cd = fd.cooldown or frame.Cooldown or frame._cooldown
        if cd then
            if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
            if cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(
                    ns.CdmDurationHideFor(frame, barData.key, not ns.CdmDurationTextOn(barData)))
            end
        end
        -- Square border / shape ring re-apply on the next style pass
        -- (DecorateFrame / RefreshCDMIconAppearance via BuildAllCDMBars).
    end
end
ns.ApplyOnlyNumbers = ApplyOnlyNumbers

I._smHookedIcons, I.ApplyCustomIcon = _smHookedIcons, ApplyCustomIcon
I.ApplyOnlyNumbers, I.ArmCdStateEval = ApplyOnlyNumbers, ArmCdStateEval
I.SwiftmendEnabled, I.TryHookSwiftmend = SwiftmendEnabled, TryHookSwiftmend
I.broken = false
