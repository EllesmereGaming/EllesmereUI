if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarCooldown.lua
--
--  The charge hash fill, the cooldown cast mirror and the cooldown-tracking
--  bar.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime

local _classB, _classG, _classR, FormatTime = I._classB, I._classG, I._classR, I.FormatTime
local _tbbWake, AnchorTBBSpark = I._tbbWake, I.AnchorTBBSpark
local ApplyTBBChargeHashLines = I.ApplyTBBChargeHashLines
local ApplyTBBTickMarks = I.ApplyTBBTickMarks
local FeedTBBThresholdOverlay, _tbbCleanNum = I.FeedTBBThresholdOverlay, I._tbbCleanNum
local ClearPandemic, CooldownBarSpellID = I.ClearPandemic, I.CooldownBarSpellID
local SetRestoreNormalFill = I.SetRestoreNormalFill

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local _anyThreshold = false
I.anyThresholdSetters[#I.anyThresholdSetters + 1] = function(v) _anyThreshold = v end
-- Assigned further down and handed to EUI_CDM_BuffBarFrames.lua
-- (SetRestoreNormalFill).
local _restoreTBBNormalFill

-------------------------------------------------------------------------------
--  Charge hash fill
--  currentCharges is secret in combat, so addon Lua cannot compute (currentCharges +
--  next-recharge progress) / maxCharges. Two invisible native StatusBars supply the
--  geometry instead: one takes Blizzard's charge count directly, one animates exactly
--  one charge-wide segment from the duration object. A single full-size texture is
--  clipped to their combined edge, so the player still sees one continuous bar
--  honoring the texture, gradient, spark, orientation and reverse-fill settings.
-------------------------------------------------------------------------------
local function _ensureTBBChargeHashFill(bar)
    if bar._chargeHashCountBar then return end
    local sb = bar._bar
    if not sb then return end

    local countBar = CreateFrame("StatusBar", nil, sb)
    countBar:SetAllPoints(sb)
    countBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local countTexture = countBar:GetStatusBarTexture()
    countTexture:SetSnapToPixelGrid(false)
    countTexture:SetTexelSnappingBias(0)
    countBar:SetAlpha(0)
    countBar:EnableMouse(false)
    bar._chargeHashCountBar = countBar
    bar._chargeHashCountTexture = countTexture

    local progressBar = CreateFrame("StatusBar", nil, sb)
    progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local progressTexture = progressBar:GetStatusBarTexture()
    progressTexture:SetSnapToPixelGrid(false)
    progressTexture:SetTexelSnappingBias(0)
    progressBar:SetAlpha(0)
    progressBar:EnableMouse(false)
    bar._chargeHashProgressBar = progressBar
    bar._chargeHashProgressTexture = progressTexture

    local clip = CreateFrame("Frame", nil, sb)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(sb:GetFrameLevel() + 1)
    clip:Hide()
    bar._chargeHashFillClip = clip

    local fill = clip:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    fill:SetSnapToPixelGrid(false)
    fill:SetTexelSnappingBias(0)
    bar._chargeHashFillTexture = fill

    -- Partial-charge shade: darkens the segment still recharging (the region between the
    -- full-charge edge and the live progress edge). Its anchors ride the two invisible
    -- status textures, so the region tracks secret-driven geometry with no Lua computation.
    -- The hash tick lines center on divider bars whose texture edges come from the same
    -- engine math as countTexture's edge, so the shade's leading edge always lands under
    -- its divider line -- no sub-pixel sliver can open beside it at any bar width.
    local shade = clip:CreateTexture(nil, "ARTWORK", nil, 2)
    shade:SetColorTexture(0, 0, 0, 0.5)
    shade:SetSnapToPixelGrid(false)
    shade:SetTexelSnappingBias(0)
    shade:Hide()
    bar._chargeHashShadeTexture = shade
end

local function _styleTBBChargeHashFill(bar, cfg)
    local fill = bar._chargeHashFillTexture
    if not fill then return end
    local texPath = bar._lastTexPath or "Interface\\Buttons\\WHITE8x8"
    local fR, fG = bar._baseFillR or _classR, bar._baseFillG or _classG
    local fB, fA = bar._baseFillB or _classB, bar._baseFillA or 1
    local gradientEnabled = cfg.gradientEnabled and true or false
    local gradientDir = cfg.gradientDir or "HORIZONTAL"
    local gR, gG = cfg.gradientR or 0.20, cfg.gradientG or 0.20
    local gB, gA = cfg.gradientB or 0.80, cfg.gradientA or 1
    -- SCALAR style signature: unchanged active bars take this branch without allocating a temporary table/key string every tick.
    if bar._chargeHashFillStyleValid
       and bar._chargeHashFillStyleTexPath == texPath
       and bar._chargeHashFillStyleGradient == gradientEnabled
       and bar._chargeHashFillStyleDirection == gradientDir
       and bar._chargeHashFillStyleR == fR
       and bar._chargeHashFillStyleG == fG
       and bar._chargeHashFillStyleB == fB
       and bar._chargeHashFillStyleA == fA
       and bar._chargeHashFillStyleGradientR == gR
       and bar._chargeHashFillStyleGradientG == gG
       and bar._chargeHashFillStyleGradientB == gB
       and bar._chargeHashFillStyleGradientA == gA then
        return
    end

    fill:SetTexture(texPath)
    if bar._blizzFillAtlas then fill:SetAtlas("UI-HUD-CoolDownManager-Bar") end
    fill:ClearAllPoints()
    if gradientEnabled then
        -- Gradients stay mapped across the full bar and are revealed by the moving clip, matching the stock gradient path.
        fill:SetPoint("TOPLEFT", bar._bar, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", bar._bar, "BOTTOMRIGHT", 0, 0)
        fill:SetVertexColor(1, 1, 1, 1)
        local c1 = bar._chargeHashGradientColor1
        local c2 = bar._chargeHashGradientColor2
        if not c1 then
            c1 = CreateColor(fR, fG, fB, fA)
            c2 = CreateColor(gR, gG, gB, gA)
            bar._chargeHashGradientColor1 = c1
            bar._chargeHashGradientColor2 = c2
        else
            c1.r, c1.g, c1.b, c1.a = fR, fG, fB, fA
            c2.r, c2.g, c2.b, c2.a = gR, gG, gB, gA
        end
        fill:SetGradient(gradientDir, c1, c2)
    else
        -- Plain/patterned StatusBar textures stretch with the visible fill.
        fill:SetAllPoints(bar._chargeHashFillClip)
        fill:SetVertexColor(fR, fG, fB, fA)
    end
    bar._chargeHashFillStyleValid = true
    bar._chargeHashFillStyleTexPath = texPath
    bar._chargeHashFillStyleGradient = gradientEnabled
    bar._chargeHashFillStyleDirection = gradientDir
    bar._chargeHashFillStyleR = fR
    bar._chargeHashFillStyleG = fG
    bar._chargeHashFillStyleB = fB
    bar._chargeHashFillStyleA = fA
    bar._chargeHashFillStyleGradientR = gR
    bar._chargeHashFillStyleGradientG = gG
    bar._chargeHashFillStyleGradientB = gB
    bar._chargeHashFillStyleGradientA = gA
end

_restoreTBBNormalFill = function(bar, cfg)
    if not bar._chargeHashFillActive then return end
    if bar._chargeHashFillClip then bar._chargeHashFillClip:Hide() end
    if bar._chargeHashCountBar then bar._chargeHashCountBar:Hide() end
    if bar._chargeHashProgressBar then bar._chargeHashProgressBar:Hide() end

    local sb = bar._bar
    local fillTex = bar._cachedOurFillTex
    if not fillTex and sb then
        fillTex = sb:GetStatusBarTexture()
        bar._cachedOurFillTex = fillTex
    end
    if fillTex then fillTex:SetAlpha(1) end
    if bar._gradientActive and bar._gradClip then bar._gradClip:Show() end
    if cfg.showSpark and fillTex then
        AnchorTBBSpark(bar, cfg, (bar._gradientActive and bar._gradClip) or fillTex)
    end

    bar._chargeHashFillActive = nil
    bar._chargeHashDuration = nil
    -- The stock bar timer is not re-armed while its texture is hidden, so a mid-recharge exit from hash mode must force the original path to refresh.
    bar._cdNeedSet = true
end
SetRestoreNormalFill(_restoreTBBNormalFill)

local function _updateTBBChargeHashFill(bar, cfg, maxCharges, currentCharges,
        durObj, remaining, duration, wasShown)
    if cfg.chargeHashLines ~= true or type(maxCharges) ~= "number"
       or maxCharges <= 1 then
        return false
    end
    local secretCount = issecretvalue and issecretvalue(currentCharges)
    if not secretCount and type(currentCharges) ~= "number" then return false end
    if not durObj and not (_tbbCleanNum(remaining) and _tbbCleanNum(duration)
       and duration > 0) then
        return false
    end

    _ensureTBBChargeHashFill(bar)
    local sb = bar._bar
    local countBar = bar._chargeHashCountBar
    local progressBar = bar._chargeHashProgressBar
    local countTexture = bar._chargeHashCountTexture
    local progressTexture = bar._chargeHashProgressTexture
    local clip = bar._chargeHashFillClip
    if not sb or not countBar or not progressBar or not countTexture
       or not progressTexture or not clip then return false end

    local isVert = cfg.verticalOrientation and true or false
    local reverse = cfg.reverseFill and true or false
    local orientation = isVert and "VERTICAL" or "HORIZONTAL"
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    -- The divider boundary bars the hash ticks anchor to are built and cache-gated
    -- by ApplyTBBChargeHashLines, which runs earlier on the same tick; nothing here
    -- reads them, so this per-tick path never touches them.

    -- Direct scalar comparisons name every geometry invalidator while keeping the steady-state update allocation-free.
    if not bar._chargeHashFillGeometryValid
       or bar._chargeHashFillMaxCharges ~= maxCharges
       or bar._chargeHashFillVertical ~= isVert
       or bar._chargeHashFillReverse ~= reverse
       or bar._chargeHashFillBarW ~= barW
       or bar._chargeHashFillBarH ~= barH then
        countBar:SetOrientation(orientation)
        countBar:SetReverseFill(reverse)
        countBar:SetMinMaxValues(0, maxCharges)

        progressBar:ClearAllPoints()
        progressBar:SetOrientation(orientation)
        progressBar:SetReverseFill(reverse)
        progressBar:SetMinMaxValues(0, 1)
        if isVert then
            progressBar:SetHeight(barH / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPLEFT", countTexture, "BOTTOMLEFT", 0, 0)
                progressBar:SetPoint("TOPRIGHT", countTexture, "BOTTOMRIGHT", 0, 0)
            else
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "TOPRIGHT", 0, 0)
            end
        else
            progressBar:SetWidth(barW / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPRIGHT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "BOTTOMLEFT", 0, 0)
            else
                progressBar:SetPoint("TOPLEFT", countTexture, "TOPRIGHT", 0, 0)
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "BOTTOMRIGHT", 0, 0)
            end
        end

        clip:ClearAllPoints()
        if isVert then
            if reverse then
                clip:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
                clip:SetPoint("BOTTOMLEFT", progressTexture, "BOTTOMLEFT", 0, 0)
            else
                clip:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
                clip:SetPoint("TOPRIGHT", progressTexture, "TOPRIGHT", 0, 0)
            end
        else
            if reverse then
                clip:SetPoint("TOPLEFT", progressTexture, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
            else
                clip:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
            end
        end

        -- The shade spans from the full-charge boundary to the moving progress edge,
        -- mirroring the clip's orientation/reverse geometry.
        local shade = bar._chargeHashShadeTexture
        if shade then
            shade:ClearAllPoints()
            if isVert then
                if reverse then
                    shade:SetPoint("TOPLEFT", countTexture, "BOTTOMLEFT", 0, 0)
                    shade:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
                else
                    shade:SetPoint("BOTTOMLEFT", countTexture, "TOPLEFT", 0, 0)
                    shade:SetPoint("TOPRIGHT", progressTexture, "TOPRIGHT", 0, 0)
                end
            else
                if reverse then
                    shade:SetPoint("TOPRIGHT", countTexture, "TOPLEFT", 0, 0)
                    shade:SetPoint("BOTTOMLEFT", progressTexture, "BOTTOMLEFT", 0, 0)
                else
                    shade:SetPoint("TOPLEFT", countTexture, "TOPRIGHT", 0, 0)
                    shade:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
                end
            end
        end

        bar._chargeHashFillGeometryValid = true
        bar._chargeHashFillMaxCharges = maxCharges
        bar._chargeHashFillVertical = isVert
        bar._chargeHashFillReverse = reverse
        bar._chargeHashFillBarW = barW
        bar._chargeHashFillBarH = barH
    end

    -- SetValue is a supported secret sink: NEVER inspect or compute with the live count in Lua.
    countBar:SetValue(currentCharges)

    if durObj and progressBar.SetTimerDuration and Enum
       and Enum.StatusBarTimerDirection then
        if bar._cdNeedSet or bar._chargeHashDuration ~= durObj or not wasShown then
            local interp = Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.Immediate
            progressBar:SetTimerDuration(durObj, interp,
                Enum.StatusBarTimerDirection.ElapsedTime)
            bar._chargeHashDuration = durObj
        end
    else
        -- Compatibility fallback for clients that expose only clean timing.
        progressBar:SetValue(1 - (remaining / duration))
        bar._chargeHashDuration = nil
    end

    _styleTBBChargeHashFill(bar, cfg)

    -- Partial-charge shade state: scalar-cached so the steady-state tick is a no-op.
    local shade = bar._chargeHashShadeTexture
    if shade then
        local shadeA = cfg.chargeHashShade == true
            and (tonumber(cfg.chargeHashShadeAlpha) or 0.5) or 0
        if shadeA > 1 then shadeA = 1 end
        if shadeA > 0 then
            if bar._chargeHashShadeAlpha ~= shadeA then
                shade:SetColorTexture(0, 0, 0, shadeA)
                bar._chargeHashShadeAlpha = shadeA
            end
            if not shade:IsShown() then shade:Show() end
        elseif shade:IsShown() then
            shade:Hide()
        end
    end

    local activating = not bar._chargeHashFillActive
    if activating then
        countBar:Show()
        progressBar:Show()
        local fillTex = bar._cachedOurFillTex
        if not fillTex then
            fillTex = sb:GetStatusBarTexture()
            bar._cachedOurFillTex = fillTex
        end
        if fillTex then fillTex:SetAlpha(0) end
        if bar._gradClip then bar._gradClip:Hide() end
        clip:Show()
    end
    if cfg.showSpark and bar._spark then
        -- Anchor to the native progress TEXTURE, not the intermediate clip frame: its moving
        -- edge is the exact visible fill boundary, and skipping the frame's pixel rounding
        -- keeps the spark joined to that edge in both normal and reverse fill.
        AnchorTBBSpark(bar, cfg, progressTexture, true)
        if not bar._spark:IsShown() then bar._spark:Show() end
    end
    bar._chargeHashFillActive = true
    bar._cdNeedSet = nil
    return true
end

-------------------------------------------------------------------------------
--  Cooldown-bar cast mirror. In combat the cooldown APIs keep isActive readable but
--  turn startTime/duration SECRET, which would drop every on-cooldown bar into the
--  shown-full fail-open for the whole fight. So each tracked spell keeps a local
--  { start, dur } mirror of clean numbers: synced from every clean read (out of
--  combat, incl. mid-cooldown) and armed from the player's own cast edge in combat
--  (UNIT_SPELLCAST_SUCCEEDED's spellID arg is never secret). The tick falls back to
--  the mirror when the API turns secret; isActive stays readable, so the bar still
--  ends/hides exactly when the real cooldown does even if the mirror drifts (CDR, resets).
-------------------------------------------------------------------------------
local _cdCast = {}       -- [sid] = { start, dur } live local cooldown mirror
local _cdDurCache = {}   -- [sid] = last clean cooldown/recharge duration seen
local _cdWatch = {}      -- [watched sid] = canonical sid to key the mirror by
local _cdFrame
local _cdActive = false
-- Cooldown-state generation: bumped by SPELL_UPDATE_COOLDOWN/CHARGES/player casts. Bars
-- re-fetch + re-arm their engine duration handle only when this moves; a cached handle keeps
-- ticking down on its own, and only a CDR/reset-adjusted cooldown needs a fresh fetch.
local _cdGen = 0

-- Static base cooldown (ms) as the arm-time seed before any clean read. The API lives
-- ONLY at the global (client-verified: no C_Spell form exists); static data, never secret,
-- but validated anyway since the seed feeds arithmetic.
local function _cdBaseDuration(sid)
    if not GetSpellBaseCooldown then return nil end
    local ms = GetSpellBaseCooldown(sid)
    if _tbbCleanNum(ms) and ms > 0 then return ms / 1000 end
    return nil
end

local function _ensureCooldownCastListener(enable)
    if enable then
        if not _cdFrame then
            _cdFrame = ns.TakeShell()
            _cdFrame:SetScript("OnEvent", function(_, event, _, _, castSid)
                _cdGen = _cdGen + 1
                if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
                local spellID = castSid
                if not spellID then return end
                local canon = _cdWatch[spellID]
                if not canon and C_Spell and C_Spell.GetBaseSpell then
                    -- Cast can fire with the override form while the bar watches the base.
                    local base = C_Spell.GetBaseSpell(spellID)
                    if type(base) == "number" then canon = _cdWatch[base] end
                end
                if not canon then return end
                local now = GetTime()
                -- Charge spells: maxCharges is static and stays readable, and the cast just consumed one charge.
                local ch = C_Spell.GetSpellCharges
                    and C_Spell.GetSpellCharges(canon)
                local maxCh = ch and ch.maxCharges
                if not (_tbbCleanNum(maxCh) and maxCh > 1) then maxCh = nil end
                -- NEVER overwrite an unexpired mirror: a plain spell cannot be cast while on
                -- cooldown, and a charge spell cast while already recharging does NOT restart the next charge; only the count drops.
                local m = _cdCast[canon]
                if m and m.dur and (m.start + m.dur) > now then
                    if maxCh and m.charges and m.charges > 0 then
                        m.charges = m.charges - 1
                    end
                    return
                end
                local dur = _cdDurCache[canon] or _cdBaseDuration(canon)
                if dur then
                    if not m then m = {}; _cdCast[canon] = m end
                    m.start = now
                    m.dur = dur
                    if maxCh then
                        -- Cast from full: the first recharge starts now.
                        m.charges = maxCh - 1
                        m.maxCh = maxCh
                    else
                        m.charges = nil
                        m.maxCh = nil
                    end
                end
            end)
        end
        if not _cdActive then
            _cdFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _cdFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
            _cdActive = true
        end
    elseif _cdFrame and _cdActive then
        _cdFrame:UnregisterAllEvents()
        _cdActive = false
    end
end

-- Authoritative (scans the DB): rebuild the watched-spell map and arm the cast listener only
-- while an enabled cooldown-tracking bar exists. Refreshed from the same sites as the other preset listeners.
function ns.UpdateCooldownCastListener()
    wipe(_cdWatch)
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.trackType == "cooldown" then
                local canon = CooldownBarSpellID(cfg)
                if canon then
                    any = true
                    -- Every form the cast event could fire with maps to the canonical id the tick keys the mirror by.
                    _cdWatch[canon] = canon
                    if cfg.spellID and cfg.spellID > 0 then
                        _cdWatch[cfg.spellID] = canon
                    end
                    if cfg.baseSpellID and cfg.baseSpellID > 0 then
                        _cdWatch[cfg.baseSpellID] = canon
                    end
                    -- Seed the duration cache NOW: build paths run out of combat where these
                    -- reads are clean. In combat the same reads can be secret and a fresh
                    -- session has no clean tick read yet, so without a seed the combat cast
                    -- could never arm the mirror. Never overwrites a live clean read.
                    if not _cdDurCache[canon] then
                        local seed
                        local ch = C_Spell.GetSpellCharges
                            and C_Spell.GetSpellCharges(canon)
                        local rd = ch and ch.cooldownDuration
                        if _tbbCleanNum(rd) and rd > 0 then seed = rd end
                        if not seed then seed = _cdBaseDuration(canon) end
                        _cdDurCache[canon] = seed
                    end
                end
            end
        end
    end
    _ensureCooldownCastListener(any)
end

-------------------------------------------------------------------------------
--  Cooldown-tracking bar (cfg.trackType == "cooldown"): the stock fill drains with the
--  spell's remaining cooldown. cfg.fillUp inverts that, filling as the cooldown
--  recovers -- it changes only WHICH WAY the value travels, and every fill source
--  below honours it. Reverse Fill is a different thing entirely and composes with
--  it: that mirrors the bar's geometry and never touches the value. Charge Hash
--  Lines instead fill one section per recovered charge while the timer stays the
--  NEXT charge's cooldown, and already fill upward by construction, so fillUp is a
--  no-op there. Stacks text = current charges. Ready (off cooldown/GCD-only/max
--  charges/unknown) counts as INACTIVE for hideWhenInactive; a shown-but-ready bar
--  renders full with no timer, in either direction.
--
--  FILL SOURCE ORDER (each honours cfg.fillUp):
--  1. Engine duration handle (GetSpellCooldownDuration/GetSpellChargeDuration +
--     SetTimerDuration): engine animates the drain and tracks CDR/resets live,
--     secret-proof by construction; timer text reads the handle's remaining (secret
--     in combat, which SetFormattedText accepts).
--  2. Clean API numbers (out of combat): exact pretty timer text, keeps the cast mirror synced.
--  3. Cast mirror (no duration-object API, or secret reads with no handle): clean local
--     dead-reckoning, blind to in-combat CDR, hence last.
--  4. Fail-open: shown-full bar, no text. Secrecy loses precision, never errors.
-------------------------------------------------------------------------------
local function _UpdateCooldownBar(bar, cfg)
    local sid = CooldownBarSpellID(cfg)

    -- remaining/duration: CLEAN numbers only (nil = ready or secret). wantHandle:
    -- which engine duration handle drives the fill ("charge"/"cd"). timingSecret: raw
    -- numbers unreadable, bar NEEDS the handle (or falls back to the mirror). charges:
    -- CLEAN count for logic/overlays; chargesDisplay: maybe-secret count that ONLY
    -- flows into SetFormattedText; hasCharges: clean flag so no secret is ever branched on.
    local remaining, duration, unreadable, wantHandle, timingSecret
    local charges, chargesDisplay, hasCharges
    local maxCharges, chargeCountValue
    if sid then
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        local maxCh = ch and ch.maxCharges
        if _tbbCleanNum(maxCh) and maxCh > 1 then
            maxCharges = math.floor(maxCh + 0.5)
            -- Charge spell: the bar tracks the next charge's recharge. The recharge-active
            -- flag is the same CLEAN combat signal Max Stacks Glow uses: false only at max
            -- charges, and readable while the count/timing fields are secret.
            local chActive = ch.isActive
            if issecretvalue and issecretvalue(chActive) then
                unreadable = true
            elseif not chActive then
                -- At max charges: ready, and the count is KNOWN without ever touching the secret currentCharges field.
                charges = maxCh
                chargesDisplay = maxCh
                chargeCountValue = maxCh
                hasCharges = true
            else
                -- Recharging (below max).
                wantHandle = "charge"
                local cur = ch.currentCharges
                if _tbbCleanNum(cur) then
                    charges = cur
                end
                chargesDisplay = cur
                chargeCountValue = cur
                hasCharges = true
                local st, du = ch.cooldownStartTime, ch.cooldownDuration
                if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                    duration = du
                    remaining = st + du - GetTime()
                    -- Clean read: keep the fallback mirror exact.
                    _cdDurCache[sid] = du
                    local m = _cdCast[sid]
                    if not m then m = {}; _cdCast[sid] = m end
                    m.start = st
                    m.dur = du
                    if charges then m.charges = charges end
                    m.maxCh = maxCh
                else
                    timingSecret = true
                end
            end
        else
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
            if cd then
                local act, gcd = cd.isActive, cd.isOnGCD
                local isSec = issecretvalue
                if isSec and (isSec(act) or isSec(gcd)) then
                    unreadable = true
                elseif act and not gcd then
                    -- Real cooldown running; a GCD-only spin never drives the bar.
                    wantHandle = "cd"
                    local st, du = cd.startTime, cd.duration
                    if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                        duration = du
                        remaining = st + du - GetTime()
                        -- Clean read: keep the fallback mirror exact.
                        _cdDurCache[sid] = du
                        local m = _cdCast[sid]
                        if not m then m = {}; _cdCast[sid] = m end
                        m.start = st
                        m.dur = du
                    else
                        timingSecret = true
                    end
                end
            end
        end
    end
    -- Resolve the engine duration handle (preferred fill source). Fetch+re-arm ONLY when
    -- cooldown state may have changed: the generation bumps on SPELL_UPDATE_COOLDOWN/CHARGES/
    -- player casts, plus a 1s revalidate for eventless adjustments; between those the CACHED
    -- handle serves every tick, ticking down on its own.
    local durObj
    if wantHandle then
        durObj = bar._cdDurObj
        local now = GetTime()
        if durObj == nil
           or bar._cdArmGen ~= _cdGen
           or bar._cdArmSid ~= sid
           or bar._cdArmKind ~= wantHandle
           or now - (bar._cdArmTime or 0) > 1 then
            local fetch
            if wantHandle == "charge" then
                if C_Spell.GetSpellChargeDuration then
                    fetch = C_Spell.GetSpellChargeDuration(sid)
                end
            else
                if C_Spell.GetSpellCooldownDuration then
                    fetch = C_Spell.GetSpellCooldownDuration(sid)
                end
            end
            durObj = fetch
            bar._cdDurObj = fetch
            bar._cdArmGen = _cdGen
            bar._cdArmSid = sid
            bar._cdArmKind = wantHandle
            bar._cdArmTime = now
            -- The bar timer must be re-set from the fresh handle.
            bar._cdNeedSet = fetch ~= nil
        end
    else
        bar._cdDurObj = nil
    end
    if timingSecret and not durObj then unreadable = true end

    -- Combat-secrecy fallback: timing went secret but the cast mirror holds clean local
    -- numbers, so drive the drain from those instead of shown-full fail-open (expired/absent mirror keeps the fail-open).
    if unreadable and sid then
        local m = _cdCast[sid]
        if m and m.dur then
            local now = GetTime()
            local rem = m.start + m.dur - now
            -- Charge model: an expiry means one charge finished and the next recharge began
            -- at that exact moment, so advance in place. The clean at-max flag above already
            -- ends the bar when the spell truly tops off; still recharging here means the
            -- model ran ahead, so hold one below max and keep draining.
            if m.maxCh and m.charges then
                local guard = m.maxCh + 1
                while rem <= 0 and guard > 0 do
                    m.charges = m.charges + 1
                    if m.charges >= m.maxCh then m.charges = m.maxCh - 1 end
                    m.start = m.start + m.dur
                    if m.start > now then m.start = now end
                    rem = m.start + m.dur - now
                    guard = guard - 1
                end
            end
            if rem > 0 then
                remaining = rem
                duration = m.dur
                unreadable = nil
                if m.charges then
                    charges = m.charges
                    chargesDisplay = m.charges
                    hasCharges = true
                end
            end
        end
    end

    if remaining and remaining <= 0 then remaining = nil; duration = nil end

    -- Clean ready: drop the mirror so a stale window can never resurrect. A live duration
    -- handle means ON cooldown with secret timing (not ready), so the mirror stays in that case.
    if sid and not unreadable and remaining == nil and not durObj then
        _cdCast[sid] = nil
    end

    local onCooldown = (remaining ~= nil) or (durObj ~= nil) or unreadable

    local hashChargeMode = cfg.chargeHashLines == true
        and type(maxCharges) == "number" and maxCharges > 1
    if bar._bar then
        ApplyTBBChargeHashLines(bar, cfg, maxCharges)
    end

    -- No pandemic concept for cooldowns: clear stale glow from a re-purposed bar frame.
    if bar._pandemicGlowActive then ClearPandemic(bar) end

    if not onCooldown and cfg.hideWhenInactive ~= false then
        -- Ready = inactive: hide, matching the buff inactive branch.
        _restoreTBBNormalFill(bar, cfg)
        bar._stackCount = 0
        if bar._stacksText then bar._stacksText:Hide() end
        bar._nameSet = nil
        if bar:IsShown() then bar:Hide() end
        return
    end

    local wasShown = bar:IsShown()
    if not wasShown then bar:Show() end
    local sb = bar._bar
    if sb then
        local timerDir = Enum and Enum.StatusBarTimerDirection
        local hashFillActive = hashChargeMode and _updateTBBChargeHashFill(
            bar, cfg, maxCharges, chargeCountValue,
            durObj, remaining, duration, wasShown)
        if hashFillActive then
            -- The composite's invisible native bars own the recovery geometry; the visible clipped texture and spark were updated above.
        elseif durObj and sb.SetTimerDuration and timerDir then
            _restoreTBBNormalFill(bar, cfg)
            -- Engine-driven fill: the handle tracks CDR and resets live with no numbers ever
            -- read. The bar timer is re-set only when a fresh handle was fetched
            -- (event/revalidate), the bar just appeared, or the requested direction changed --
            -- the engine animates in between. Fill Up asks the engine for ElapsedTime instead
            -- of RemainingTime, the same constant the charge-hash recovery bar uses. The
            -- direction term matters because toggling the option restyles a LIVE bar in
            -- place: with only the fetch/show terms the engine would keep animating the old
            -- direction until the next handle fetch.
            local wantDir = cfg.fillUp and timerDir.ElapsedTime
                or timerDir.RemainingTime
            if bar._cdNeedSet or not wasShown or bar._cdFillDir ~= wantDir then
                sb:SetMinMaxValues(0, 1)
                local interpE = Enum.StatusBarInterpolation
                local interp
                if interpE then
                    if wasShown and _tbbWake._smoothCooldowns then
                        interp = interpE.ExponentialEaseOut
                    else
                        interp = interpE.None
                    end
                end
                sb:SetTimerDuration(durObj, interp, wantDir)
                -- Snap whenever the bar was not already animating THIS
                -- direction. First show is the original case (the
                -- empty-to-full sweep-in). The direction term adds two more:
                -- arriving from the ready state, which parks the bar full and
                -- clears _cdFillDir, and a mid-cooldown toggle. Both leave the
                -- bar sitting at the opposite end, and with smooth cooldowns
                -- on, easing from there plays a visible backwards sweep at the
                -- exact moment the spell was cast.
                if (not wasShown or bar._cdFillDir ~= wantDir)
                    and sb.SetToTargetValue then
                    sb:SetToTargetValue()
                end
                bar._cdNeedSet = nil
                bar._cdFillDir = wantDir
            end
            if cfg.showSpark and bar._spark then bar._spark:Show() end
        elseif remaining then
            _restoreTBBNormalFill(bar, cfg)
            sb:SetMinMaxValues(0, duration)
            -- Both operands are clean numbers on this branch, and a
            -- non-positive remaining was normalised away above, so Fill Up
            -- can simply mirror the fraction in Lua.
            local fillVal = cfg.fillUp and (duration - remaining) or remaining
            -- Smooth fill is baseline (see UpdateLustBar note).
            local smooth = _tbbWake._smoothCooldowns and wasShown and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            if smooth then
                sb:SetValue(fillVal, smooth)
            else
                sb:SetValue(fillVal)
            end
            -- Plain SetValue cancels the running bar timer, so the cached
            -- engine direction is stale the moment this branch runs.
            bar._cdFillDir = nil
            if cfg.showSpark and bar._spark then bar._spark:Show() end
        else
            _restoreTBBNormalFill(bar, cfg)
            -- Ready (kept on screen) or unreadable fail-open: full bar in either direction.
            -- Plain SetValue also cancels any running bar timer.
            sb:SetMinMaxValues(0, 1)
            sb:SetValue(1)
            bar._cdFillDir = nil
            if bar._spark then bar._spark:Hide() end
        end
    end

    -- Timer: remaining cooldown, hidden when ready/unreadable. Clean numbers get the pretty
    -- format; a secret remaining from the duration handle goes through SetFormattedText
    -- (accepts secrets). Hash mode shows tenths, stock mode whole seconds.
    if bar._timerText then
        if remaining and cfg.showTimer then
            if hashChargeMode then
                bar._timerText:SetFormattedText("%.1f", remaining)
            elseif remaining < 10 then
                bar._timerText:SetText(string.format("%.1f", remaining))
            else
                bar._timerText:SetText(FormatTime(remaining))
            end
            bar._timerText:Show()
        elseif cfg.showTimer and durObj and durObj.GetRemainingDuration then
            local rem = durObj:GetRemainingDuration()
            if (issecretvalue and issecretvalue(rem)) or type(rem) == "number" then
                bar._timerText:SetFormattedText(hashChargeMode and "%.1f" or "%.0f", rem)
                bar._timerText:Show()
            else
                bar._timerText:Hide()
            end
        else
            bar._timerText:Hide()
        end
    end

    -- Charges reuse the stacks text and the threshold overlay feed. The text setter accepts
    -- a SECRET live count; overlays need clean numbers, so a secret count zeroes them instead of freezing a stale value.
    if hasCharges then
        bar._stackCount = charges or 0
        if bar._stacksText then
            if (cfg.stacksPosition or "center") ~= "none" then
                bar._stacksText:SetFormattedText("%d", chargesDisplay)
                bar._stacksText:Show()
            else
                bar._stacksText:Hide()
            end
        end
    else
        bar._stackCount = 0
        if bar._stacksText then bar._stacksText:Hide() end
    end

    -- Threshold feed (gated): runs in both arms so a charge count that becomes unreadable zeroes the overlay instead of freezing its last value.
    if _anyThreshold and cfg.stackThresholdEnabled then
        FeedTBBThresholdOverlay(bar)
    end

    -- Deferred tick marks (same consume as the buff mirror branch).
    if bar._ticksDirty and sb then
        local bw = sb:GetWidth()
        if bw and bw > 0 then
            ApplyTBBTickMarks(sb, cfg, bar._threshTicks,
                cfg.verticalOrientation, bar._tickOverlay)
            bar._ticksDirty = nil
        end
    end
end

I._UpdateCooldownBar = _UpdateCooldownBar
I.broken = false
