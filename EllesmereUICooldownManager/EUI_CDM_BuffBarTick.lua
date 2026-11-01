if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarTick.lua
--
--  The combat and visibility gates and UpdateTrackedBuffBarTimers, the
--  per-frame tick.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime
local pcall = pcall
local abs = math.abs
local min = math.min

local _pandemicState, FormatTime = I._pandemicState, I.FormatTime
local LifebloomPandemic, _tbbWake = I.LifebloomPandemic, I._tbbWake
local ReflowVisibleGroupedTBBars, tbbFrames = I.ReflowVisibleGroupedTBBars, I.tbbFrames
local AnchorTBBSparkState, ApplyTBBTickMarks = I.AnchorTBBSparkState, I.ApplyTBBTickMarks
local FeedTBBThresholdOverlay, _tbbStickyCdID = I.FeedTBBThresholdOverlay, I._tbbStickyCdID
local AssignFramesToConfigs, CfgWantsSID = I.AssignFramesToConfigs, I.CfgWantsSID
local MatchesSID, TbbCfgFamilyMatch = I.MatchesSID, I.TbbCfgFamilyMatch
local TbbNameFamily, TbbSlotVariantLabeled = I.TbbNameFamily, I.TbbSlotVariantLabeled
local _potionDur, _potionExpiry, _ts = I._potionDur, I._potionExpiry, I._ts
local _UpdateSelfTimedBar, ClearPandemic = I._UpdateSelfTimedBar, I.ClearPandemic
local EffectiveIconSpellID = I.EffectiveIconSpellID
local GetBlizzBarFontStrings, MirrorEngineTimer = I.GetBlizzBarFontStrings, I.MirrorEngineTimer
local TIME_SPIRAL_DURATION, UpdateLustBar = I.TIME_SPIRAL_DURATION, I.UpdateLustBar
local UpdatePandemic, UpdateStacks = I.UpdatePandemic, I.UpdateStacks
local _UpdateCooldownBar, SetAssignDirty = I._UpdateCooldownBar, I.SetAssignDirty

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end
-- Feature-gating flags (rebuilt in BuildTrackedBuffBars, read in tick)
local _anyPandemic = false
I.anyPandemicSetters[#I.anyPandemicSetters + 1] = function(v) _anyPandemic = v end
local _anyThreshold = false
I.anyThresholdSetters[#I.anyThresholdSetters + 1] = function(v) _anyThreshold = v end
local _anyStacks = false
I.anyStacksSetters[#I.anyStacksSetters + 1] = function(v) _anyStacks = v end
local _anyVisCond = false
I.anyVisCondSetters[#I.anyVisCondSetters + 1] = function(v) _anyVisCond = v end
local tbbTickFrame
I.tickFrameSetters[#I.tickFrameSetters + 1] = function(v) tbbTickFrame = v end
-- Group reflow gate: see _MarkTBBReflowDirty in EUI_CDM_BuffBarGroups.lua.
local _tbbReflowDirty = true
I.reflowDirtySetters[#I.reflowDirtySetters + 1] = function(v) _tbbReflowDirty = v end
-- Smooth-fill switch memo for the tick: GetTBBSmoothSettings walks the profile store,
-- and its result can only change with the active profile name or the live spec-profile bucket, both re-read per tick without a call.
local _tickSm, _tickSmProf, _tickSmSp

-------------------------------------------------------------------------------
--  "Only In Combat" gate
--  Combat state comes from the main module's event-tracked flag (debounced combat
--  exit, so a mob dying between pulls does not flash every bar away).
--  InCombatLockdown() is only the fallback for a load order that has not published
--  the shared read yet.
-------------------------------------------------------------------------------
local function TBBInCombat()
    if ns.CDMInCombat then return ns.CDMInCombat() end
    return InCombatLockdown() and true or false
end

-- Park a bar the combat gate hides. Drops the same transient render state the inactive
-- branches drop, so the next in-combat show re-resolves icon/name/fill from scratch instead of mirroring a stale frame.
local function HideTBBBarForCombat(bar)
    -- Already parked: nothing to tear down, and clearing _nameSet here would make the
    -- deferred name-fill pass re-resolve the spell every frame for the whole time out of combat.
    if not bar:IsShown() then return end
    if bar._pandemicGlowActive then ClearPandemic(bar) end
    if bar._stacksText then bar._stacksText:Hide() end
    bar._stackCount = 0
    bar._cachedBlizzFillTex   = nil
    bar._cachedOurFillTex     = nil
    bar._cachedBlizzIconTex   = nil
    bar._cachedBlizzIconOwner = nil
    bar._lastIconSID = nil
    bar._nameSet     = nil
    bar:Hide()
end

-------------------------------------------------------------------------------
--  "Visibility" gate (CDM-Bars-style mode + options, TBB-scoped)
--  Mirrors _CDMApplyVisibility's priority-2/3 checks (EUI_CDM_Rebuild.lua),
--  but folded into TBB's own tick since TBB bars are not native CDM bars.
--  Zero cost for bars without a condition: the tick consults the gate only
--  for bars flagged at build (bar._tbbVisCond) and fills the shared state
--  table ONCE per pass (TBBFillVisState) when any bar carries a condition.
-------------------------------------------------------------------------------
local _tbbVisState = {}

local function TBBFillVisState()
    local inRaid = IsInRaid and IsInRaid() or false
    _tbbVisState.inCombat = TBBInCombat()
    _tbbVisState.inRaid = inRaid
    _tbbVisState.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
end

local function TBBVisibilityHides(cfg)
    if EllesmereUI.CheckVisibilityOptions(cfg) then
        return true
    end

    local vis = cfg.barVisibility or "always"
    local visExt = EllesmereUI.EvalVisibilityExtended(cfg, "barVisibility", _tbbVisState, EllesmereUI.VIS_CAPS_DEFAULT)
    if visExt ~= nil then return not visExt end
    if vis == "never" then return true end
    if vis == "in_combat" then return not _tbbVisState.inCombat end
    if vis == "out_of_combat" then return _tbbVisState.inCombat end
    if vis == "in_raid" then return not _tbbVisState.inRaid end
    if vis == "in_party" then return not _tbbVisState.inParty end
    if vis == "solo" then return _tbbVisState.inRaid or _tbbVisState.inParty end
    return false
end

-- Does this bar rely on a Visibility mode or option? Mirrors what TBBVisibilityHides reads,
-- minus hideWhenInactive/onlyInCombat, which flip on the aura and combat edges the sleeper
-- already wakes on. Option keys come from the shared list so a new one is covered here too.
local function TBBUsesVisCondition(cfg)
    if not cfg then return false end
    local vis = cfg.barVisibility
    if vis and vis ~= "always" then return true end
    local vm = cfg.visibilityModes
    if type(vm) == "table" and next(vm) then return true end
    local keys = EllesmereUI.VIS_OPT_KEYS
    if keys then
        for i = 1, #keys do
            if cfg[keys[i]] then return true end
        end
    end
    return false
end

-- Name, icon, auto fill colour and stacks on a mirrored bar change only when
-- Blizzard refreshes the bound frame's data: on player and target aura events
-- and target changes (the wake frame counts both), a new binding or slot, and
-- the active edge. So the tick re-reads them on those edges, once more on the
-- tick after (Blizzard cleans a dirty frame in its own OnUpdate, which may run
-- after ours), and at least every TBB_CONTENT_REFRESH seconds for the edges it
-- does not count (totems, spell overrides, icon updates). Every path that
-- leaves the active mirror, and every settings apply, clears bar._cChild, so a
-- return is always an edge. An unreadable cooldownID fails open to every tick.
local TBB_CONTENT_REFRESH = 0.25
local function TBBContentDue(bar, blzChild, cfg, wasShown, now)
    local cd = blzChild.cooldownID
    local pGen, tGen = _tbbWake._fbPGen, _tbbWake._fbTGen
    local sticky = _tbbStickyCdID[cfg]
    if not wasShown or bar._cChild ~= blzChild or bar._cPGen ~= pGen
       or bar._cTGen ~= tGen or bar._cSticky ~= sticky
       or issecretvalue(cd) or bar._cCdID ~= cd then
        bar._cChild, bar._cPGen, bar._cTGen, bar._cSticky = blzChild, pGen, tGen, sticky
        bar._cCdID = not issecretvalue(cd) and cd or nil
        bar._cAgain = true
        bar._cAt = now
        return true
    end
    if bar._cAgain or now - bar._cAt >= TBB_CONTENT_REFRESH then
        bar._cAgain = nil
        bar._cAt = now
        return true
    end
    return false
end

-------------------------------------------------------------------------------
--  Main Tick: UpdateTrackedBuffBarTimers
--  Direct reskin of Blizzard's BuffBarCooldownViewer StatusBars: reads
--  min/max/value from Blizzard's Bar, zero duration computation.
-------------------------------------------------------------------------------
function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end

    -- Liveness for the idle sleeper: set by any branch below that is actually animating or tracking something this tick.
    local tickLive = false
    local now = GetTime()

    -- Resolved once per tick, not per bar: the bind-miss fallback below asks the target
    -- for a debuff the player applied, and there is no point asking with nothing targeted.
    local hasTarget = UnitExists and UnitExists("target") and true or false

    -- Profile-wide smooth-fill switches, resolved once per tick for every fill site (absent buffs key = enabled; absent cooldowns key = OFF).
    local sm
    do
        local pn = EllesmereUIDB and EllesmereUIDB.activeProfile
        local sp = ns._cachedSpecProfiles
        if _tickSm and pn == _tickSmProf and sp == _tickSmSp then
            sm = _tickSm
        else
            sm = ns.GetTBBSmoothSettings and ns.GetTBBSmoothSettings()
            _tickSm, _tickSmProf, _tickSmSp = sm, pn, sp
        end
    end
    if sm then
        _tbbWake._smoothBuffs = sm.buffs ~= false
        _tbbWake._smoothCooldowns = sm.cooldowns == true
    else
        _tbbWake._smoothBuffs, _tbbWake._smoothCooldowns = true, false
    end

    -- Self-heal placeholder mode when the user navigates away from Tracking Bars
    if ns._tbbPlaceholderMode then
        local am = EllesmereUI:GetActiveModule()
        local ap = EllesmereUI:GetActivePage()
        if am ~= "EllesmereUICooldownManager" or ap ~= "Tracking Bars" then
            ns._tbbPlaceholderMode = false
            if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            -- Auras may have moved while the preview was up: re-pair on the first real mirror tick.
            SetAssignDirty(true)
            -- The preview may have written the self-timed bars' timer text and
            -- the mirrored bars' name, icon and stacks: drop their stamps so the
            -- next live tick rewrites them.
            for bi = 1, #tbbFrames do
                local b = tbbFrames[bi]
                if b then b._stTxtKey = nil; b._cChild = nil end
            end
        end
    end


    -- Pair configs to Blizzard frames ONE-TO-ONE up front, consuming each frame once, so two
    -- configs sharing a cooldownInfo (Eclipse Solar+Lunar) cannot both mirror the same frame and show twice.
    local assignment = AssignFramesToConfigs(bars)

    -- Visibility gate inputs, once per pass, only when some bar has a condition.
    if _anyVisCond then TBBFillVisState() end

    -- Audio on Buff Loss for the self-timed presets: a latch the gain armed
    -- fires at the window's end ahead of every visibility gate below, so a bar
    -- parked at that moment (Only In Combat after combat drops) still cues.
    -- The window has no end event, so a pending latch keeps the tick awake;
    -- one found long past its end (the tick was parked) clears silently.
    local lossLatch = ns._tbbPresetLoss
    if next(lossLatch) then
        for pk, at in pairs(lossLatch) do
            if now >= at then
                lossLatch[pk] = nil
                if now - at < 1 then ns.TBBPresetSoundEdge(pk, false) end
            else
                tickLive = true
            end
        end
    end

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if not bar or not bar._tbbReady then
            -- skip
        elseif ns._tbbPlaceholderMode then
            tickLive = true
            if not bar:IsShown() then bar:Show() end
        elseif cfg.enabled == false then
            bar:Hide()
        elseif bar._tbbVisCond and TBBVisibilityHides(cfg) then
            HideTBBBarForCombat(bar)
        elseif cfg.onlyInCombat and not TBBInCombat() then
            -- "Only In Combat": out of combat the bar is gone regardless of aura/cooldown state, and regardless of Hide When Inactive.
            HideTBBBarForCombat(bar)
        elseif cfg.popularKey == "bloodlust" then
            -- Self-driven 40s lust bar; no Blizzard frame to mirror.
            if UpdateLustBar(bar, cfg) then tickLive = true end
        elseif cfg.popularKey == "timespiral" then
            -- Self-driven 10s Time Spiral "Free Move" bar; glow-armed, no frame.
            if _UpdateSelfTimedBar(bar, cfg, _ts.expiry, TIME_SPIRAL_DURATION) then tickLive = true end
        elseif cfg.popularKey and _potionDur[cfg.popularKey] then
            -- Self-cast potion preset: hardcoded window off the spell-cast edge; no aura tracking, no Blizzard frame to mirror.
            if _UpdateSelfTimedBar(bar, cfg, _potionExpiry[cfg.popularKey] or 0,
                _potionDur[cfg.popularKey]) then tickLive = true end
        elseif cfg.trackType == "cooldown" then
            -- Spell-cooldown tracking: self-driven, no Blizzard frame/aura.
            _UpdateCooldownBar(bar, cfg)
            -- Live while an engine handle drives the fill OR the bar is on screen: covers the
            -- secret-timing mirror drain and always-shown bars, both needing per-tick updates.
            if bar._cdDurObj or bar:IsShown() then tickLive = true end
        else
            local blzChild = assignment[cfg]
            if blzChild then ns.HookPandemicState(blzChild) end

            -- Active state MUST come from the CooldownViewer item's IsActive() (real
            -- aura state: expirationTime > now, or infinite auras), NEVER IsShown(): a
            -- buff-bar item stays SHOWN while inactive unless the user enabled
            -- Blizzard's "Hide When Inactive" edit-mode option (off by default), which
            -- would leave our bar visible 100% of the time. Fall back to IsShown() only
            -- if IsActive is absent.
            local isActive = false
            if blzChild then
                if blzChild.IsActive then
                    isActive = blzChild:IsActive() and true or false
                elseif blzChild.IsShown then
                    isActive = blzChild:IsShown() or false
                end
            end

            -- Blizzard viewer bind-miss / not-tracked-at-all fallback: covers (1) the
            -- buff-bar viewer failing to bind a freshly applied aura (auraInstanceID
            -- never set, IsActive stuck false until another bar's activation forces a
            -- refresh) and (2) a spell absent from every CooldownViewer category
            -- (blzChild permanently nil, e.g. a hero-talent proc CDM never registers).
            -- Either way, when the player demonstrably carries the aura (known-spellID
            -- player-aura query, no scanning), drive the bar from the aura data --
            -- reads only, our own frames only, NEVER pokes the Blizzard frame.
            local fbAura
            if not isActive and not cfg.spellIDs
               and cfg.spellID and cfg.spellID > 0
               and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                -- Each half re-queries only after its own aura edge (the wake frame
                -- counts player aura events in _fbPGen; target aura events and target
                -- changes in _fbTGen), not on every tick: a refresh or an expiry is
                -- such an event, so the kept aura data stays current.
                if bar._fbCfg ~= cfg or bar._fbSpell ~= cfg.spellID or bar._fbBase ~= cfg.baseSpellID then
                    bar._fbCfg, bar._fbSpell, bar._fbBase = cfg, cfg.spellID, cfg.baseSpellID
                    bar._fbPGen, bar._fbTGen = nil, nil
                end
                if bar._fbPGen ~= _tbbWake._fbPGen then
                    bar._fbPGen = _tbbWake._fbPGen
                    local a = C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                    if not a and cfg.baseSpellID and cfg.baseSpellID > 0 then
                        a = C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)
                    end
                    bar._fbPAura = a or false
                end
                fbAura = bar._fbPAura or nil
                -- Same net for a debuff the player put on the TARGET, which the queries
                -- above can never see. Blizzard's viewer stalls exactly there after a
                -- macro that clears and restores the target inside one frame: its
                -- OnPlayerTargetChanged compares GUIDs, sees the same one it stored, and
                -- never refreshes, so the item stays inactive until a real target switch.
                if not fbAura and hasTarget then
                    if bar._fbTGen ~= _tbbWake._fbTGen then
                        bar._fbTGen = _tbbWake._fbTGen
                        bar._fbTAura = _tbbWake.GetTargetAura(cfg) or false
                    end
                    fbAura = bar._fbTAura or nil
                end
                -- Fallback driving means the viewer has not bound this aura yet, and
                -- Blizzard's late-bind can land WITHOUT a fresh player aura event. Keep
                -- the memo dirty while any fallback is live so the next tick re-pairs
                -- the moment the frame appears (restoring stacks/pandemic from mirror).
                if fbAura then SetAssignDirty(true) end
            end
            if isActive or fbAura then tickLive = true end

            -- Read Blizzard's StatusBar (the data source for fill/timer)
            local blizzBar = blzChild and blzChild.Bar

            if isActive then
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar
                -- Name, icon, auto fill colour and stacks: on edges only (TBBContentDue).
                local content = TBBContentDue(bar, blzChild, cfg, wasShown, now)

                -- Stacks (gated)
                if _anyStacks and content then UpdateStacks(bar, blzChild, cfg) end

                if blizzBar then
                    -- Mirror Blizzard's bar onto ours. Secret values pass natively to widget
                    -- setters (NEVER compared in Lua). Smooth fill is baseline (see UpdateLustBar note).
                    local smooth = _tbbWake._smoothBuffs and wasShown and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if cfg.stackBasedBar and cfg.trackType ~= "cooldown"
                       and cfg.stackThresholdMaxEnabled then
                        -- Stack-based fill: current stacks over the user's Max Stacks instead
                        -- of the time mirror. An unreadable count (no cached aura data, no
                        -- readable instance id) fails open to a full bar, like every unreadable fill here.
                        if bar._stackUnreadable then
                            sb:SetMinMaxValues(0, 1)
                            sb:SetValue(1)
                        else
                            sb:SetMinMaxValues(0, cfg.stackThresholdMax or 10)
                            if smooth then
                                sb:SetValue(bar._stackCount or 0, smooth)
                            else
                                sb:SetValue(bar._stackCount or 0)
                            end
                        end
                    elseif smooth then
                        sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        sb:SetValue(blizzBar:GetValue(), smooth)
                    else
                        sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        sb:SetValue(blizzBar:GetValue())
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end

                    -- Auto fill color from Blizzard's bar texture
                    if content and (cfg.fillColorMode or "auto") == "auto" then
                        -- Cache texture refs: GetStatusBarTexture() allocates userdata per call.
                        local blizzFillTex = bar._cachedBlizzFillTex
                        if not blizzFillTex then
                            blizzFillTex = blizzBar:GetStatusBarTexture()
                            bar._cachedBlizzFillTex = blizzFillTex
                        end
                        if blizzFillTex then
                            local br, bg, bb, ba = blizzFillTex:GetVertexColor()
                            if br then
                                if bar._gradientActive and bar._gradTex then
                                    local c1 = bar._gradColor1 or CreateColor(0,0,0,1)
                                    local c2 = bar._gradColor2 or CreateColor(0,0,0,1)
                                    bar._gradColor1 = c1
                                    bar._gradColor2 = c2
                                    c1.r, c1.g, c1.b, c1.a = br, bg, bb, ba or 1
                                    c2.r, c2.g, c2.b, c2.a = cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1
                                    bar._gradTex:SetGradient(cfg.gradientDir or "HORIZONTAL", c1, c2)
                                else
                                    local ourFillTex = bar._cachedOurFillTex
                                    if not ourFillTex then
                                        ourFillTex = sb:GetStatusBarTexture()
                                        bar._cachedOurFillTex = ourFillTex
                                    end
                                    if ourFillTex then ourFillTex:SetVertexColor(br, bg, bb, ba or 1) end
                                end
                            end
                        end
                    end

                    -- Name resolution ladder:
                    --  1. Blizzard's rendered label FontString on the BOUND
                    --     frame -- the only channel carrying live variant
                    --     names (Diabolist probe 2026-08-16: on the active
                    --     ritual frame every id AND the aura-instance read are
                    --     secret even out of combat; only the label knows
                    --     which ritual is up). FIELD-PROVEN 2026-08: a hidden
                    --     pool frame's label can ALSO hold another slot's
                    --     readable text persistently after re-acquire (binding
                    --     right, label lying -- SotR as "Consecration", Bone
                    --     Shield as "Blood Draw"), so the label is trusted
                    --     only inside the config's name family: readable text
                    --     must be family-compatible, and secret text paints
                    --     only on slots whose linked forms provably render
                    --     distinct names. Secrets pass straight to SetText
                    --     (never compared or stored).
                    --  2. Live aura data, when readable and provably this bar's
                    --     family (exact config ids or the bound slot's
                    --     cooldownInfo override/spellID/linkedSpellIDs).
                    --  3. The configured spell's name (deterministic).
                    -- None of it runs for a bar with a custom name: the build painted
                    -- that, and nothing else writes the label.
                    if content and bar._nameText and bar._nameText:IsShown()
                       and not ns.TBBCustomName(cfg) then
                        local nameStr
                        -- auraInstanceID may itself be SECRET on the active frame
                        -- (probe-confirmed): type() reads the tag without touching
                        -- the value -- the taint-safe presence test for secrets.
                        -- SLOT CHECK (the Wardead class, 2+ bars in one group in
                        -- combat): cooldownID stays a plain readable number in
                        -- secret windows, so a pooled frame moved to another slot
                        -- since binding is caught before its label is read (the
                        -- sticky pass applies the identical test on its own
                        -- schedule); a mismatch skips the label and falls through.
                        if blzChild and blzChild:IsShown() and blizzBar
                           and type(blzChild.auraInstanceID) ~= "nil"
                           and (_tbbStickyCdID[cfg] == nil
                                or blzChild.cooldownID == _tbbStickyCdID[cfg]) then
                            local blizzNameFS = GetBlizzBarFontStrings(blizzBar)
                            if blizzNameFS then
                                local ok, txt = pcall(blizzNameFS.GetText, blizzNameFS)
                                if ok and txt ~= nil then
                                    if issecretvalue and issecretvalue(txt) then
                                        if TbbSlotVariantLabeled(bar, blzChild.cooldownID) then
                                            nameStr = txt
                                        end
                                    elseif txt ~= "" then
                                        -- Family gate memoized on (cfg, cfg.name,
                                        -- text): the verdict only moves when the
                                        -- rendered string or the config does.
                                        if bar._labelGateCfg ~= cfg
                                           or bar._labelGateNm ~= cfg.name
                                           or bar._labelGateTxt ~= txt then
                                            bar._labelGateCfg = cfg
                                            bar._labelGateNm  = cfg.name
                                            bar._labelGateTxt = txt
                                            bar._labelGateOk  = TbbCfgFamilyMatch(
                                                cfg, TbbNameFamily(txt), true)
                                        end
                                        if bar._labelGateOk then nameStr = txt end
                                    end
                                end
                            end
                        end
                        if not nameStr and blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit
                           and not (issecretvalue and issecretvalue(blzChild.auraInstanceID)) then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            if ok and ad and ad.name and not (issecretvalue and issecretvalue(ad.name)) then
                                local sid = ad.spellId
                                if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                                    local mine = CfgWantsSID(cfg, sid)
                                    if not mine and blzChild.cooldownID
                                       and not (issecretvalue and issecretvalue(blzChild.cooldownID))
                                       and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                                        local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, blzChild.cooldownID)
                                        if ok2 and info then
                                            local ok3, m = pcall(MatchesSID, info, sid)
                                            mine = ok3 and m
                                        end
                                    end
                                    if mine then nameStr = ad.name end
                                end
                            end
                        end
                        if not nameStr and cfg.spellID and cfg.spellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(cfg.spellID)
                            if spInfo then
                                nameStr = spInfo.name
                            elseif C_Spell.RequestLoadSpellData then
                                C_Spell.RequestLoadSpellData(cfg.spellID)
                            end
                        end
                        if not nameStr and cfg.baseSpellID and cfg.baseSpellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(cfg.baseSpellID)
                            if spInfo then nameStr = spInfo.name end
                        end
                        if nameStr then
                            bar._nameText:SetText(nameStr)
                            bar._nameSet = true
                        end
                    end
                    -- Timer: engine-bound decimal mirror first (the engine formats the secret
                    -- remaining time into a hidden FS we copy). Fallback: passthrough from
                    -- Blizzard's FontString every frame (it changes constantly).
                    if MirrorEngineTimer(bar, cfg) then
                        bar._timerText:Show()
                    else
                        local _, blizzTimerFS = GetBlizzBarFontStrings(blizzBar)
                        if cfg.showTimer and bar._timerText and blizzTimerFS then
                            bar._timerText:SetText(blizzTimerFS:GetText())
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    end

                    -- Icon source priority: 1) Blizzard's icon texture on the bound
                    -- frame (SetBarContent already resolved the override/variant form,
                    -- so mirroring the file can never disagree with Blizzard's own CDM;
                    -- mirrored on the content edges like the fill color, passes through
                    -- even when secret since SetTexture accepts secrets); 2) live aura data
                    -- (frames without an icon region), so dynamic buffs (Roll the
                    -- Bones) show the rolled buff; 3) effective config spell
                    -- (override-resolved saved id). Every non-config write clears
                    -- _lastIconSID so the config fallback can't skip its SetTexture
                    -- against a stale cache and strand another source's icon.
                    if content and bar._icon and bar._icon:IsShown() then
                        local gotIcon = false
                        if bar._cachedBlizzIconOwner ~= blzChild then
                            local iconRegion = blzChild.Icon
                            bar._cachedBlizzIconTex = (iconRegion and iconRegion.Icon) or false
                            bar._cachedBlizzIconOwner = blzChild
                        end
                        local blzIconTex = bar._cachedBlizzIconTex
                        if blzIconTex then
                            local file = blzIconTex:GetTexture()
                            if file then
                                bar._icon._tex:SetTexture(file)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon and blzChild.auraInstanceID and blzChild.auraDataUnit then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            -- Instance ids recycle onto other buffs; only trust a match.
                            if ok and ad and ad.icon and CfgWantsSID(cfg, ad.spellId) then
                                bar._icon._tex:SetTexture(ad.icon)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon then
                            local iconSID = EffectiveIconSpellID(cfg)
                            if iconSID and iconSID ~= bar._lastIconSID then
                                local spInfo = C_Spell.GetSpellInfo(iconSID)
                                if spInfo and spInfo.iconID then
                                    bar._icon._tex:SetTexture(spInfo.iconID)
                                    bar._lastIconSID = iconSID
                                end
                            end
                        end
                    end

                    -- Pandemic glow: the ShowPandemicStateFrame hook sets _pandemicState.
                    -- Requires the user to enable pandemic alerts in Blizzard CDM settings.
                    if _anyPandemic and cfg.pandemicGlow then
                        local inPandemic = blzChild and _pandemicState[blzChild]
                        -- Fallback for auras Blizzard never pandemic-flags (currently only
                        -- Lifebloom). bar._isLifebloom is cached after the first resolve, so a
                        -- bar known not to be Lifebloom costs one table read and skips.
                        if not inPandemic and blzChild and bar._isLifebloom ~= false then
                            inPandemic = LifebloomPandemic(bar, blzChild)
                        end
                        -- TBBs always show OUR glow (Blizzard Default included): the native
                        -- PandemicIcon lives on the hidden blzChild frame, not our visible TBB bar.
                        if inPandemic then
                            if not bar._pandemicGlowActive then UpdatePandemic(bar, cfg) end
                            if bar._pandemicGlowTarget then bar._pandemicGlowTarget:SetAlpha(1) end
                        elseif bar._pandemicGlowActive then
                            ClearPandemic(bar)
                        end
                    elseif bar._pandemicGlowActive then
                        ClearPandemic(bar)
                    end
                else
                    -- Active aura but no Blizzard bar data: show full bar
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(1)
                    if bar._timerText then bar._timerText:Hide() end
                    if bar._spark then bar._spark:Hide() end
                    if bar._pandemicGlowActive then ClearPandemic(bar) end
                end

                -- Threshold feed (gated)
                if _anyThreshold and cfg.stackThresholdEnabled then
                    FeedTBBThresholdOverlay(bar)
                end

                -- Deferred tick marks
                if bar._ticksDirty and sb then
                    local bw = sb:GetWidth()
                    if bw and bw > 0 then
                        ApplyTBBTickMarks(sb, cfg, bar._threshTicks,
                            cfg.verticalOrientation, bar._tickOverlay)
                        bar._ticksDirty = nil
                    end
                end
            elseif fbAura then
                -- Bind-miss fallback: self-drive fill/timer from the live aura until
                -- Blizzard's frame catches up; isActive then resumes the normal mirror path seamlessly.
                bar._cChild = nil
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar
                local dur = fbAura.duration
                local exp = fbAura.expirationTime
                local isSec = issecretvalue
                local clean = dur and exp and not (isSec and (isSec(dur) or isSec(exp)))
                -- Stack-based fill works in fallback mode too: fill and stacks text come from
                -- the live aura's applications (plain or secret; SetValue/SetText accept both) while the timer keeps tracking remaining time.
                local fbStackFill = cfg.stackBasedBar
                    and cfg.trackType ~= "cooldown"
                    and cfg.stackThresholdMaxEnabled
                if sb and fbStackFill then
                    local apps = fbAura.applications
                    -- The aura is up, so a readable count floors at 1 even when applications reads 0/nil (non-stacking aura).
                    if not apps or (not (isSec and isSec(apps)) and apps < 1) then
                        apps = 1
                    end
                    sb:SetMinMaxValues(0, cfg.stackThresholdMax or 10)
                    local smooth = _tbbWake._smoothBuffs and wasShown and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if smooth then
                        sb:SetValue(apps, smooth)
                    else
                        sb:SetValue(apps)
                    end
                    bar._stackCount = apps
                    if bar._stacksText and not bar._stacksHidden then
                        bar._stacksText:SetText(apps)
                        bar._stacksText:Show()
                    elseif bar._stacksText then
                        bar._stacksText:Hide()
                    end
                    -- Timer text: same handling as the duration fill below.
                    if clean and dur > 0 then
                        if cfg.showTimer and bar._timerText then
                            local remaining = exp - GetTime()
                            if remaining < 0 then remaining = 0 end
                            if not MirrorEngineTimer(bar, cfg) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    elseif bar._timerText then
                        bar._timerText:SetShown(MirrorEngineTimer(bar, cfg))
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end
                elseif sb then
                    if clean and dur > 0 then
                        local remaining = exp - GetTime()
                        if remaining < 0 then remaining = 0 end
                        sb:SetMinMaxValues(0, dur)
                        local smooth = _tbbWake._smoothBuffs and wasShown and Enum
                            and Enum.StatusBarInterpolation
                            and Enum.StatusBarInterpolation.ExponentialEaseOut
                        if smooth then
                            sb:SetValue(remaining, smooth)
                        else
                            sb:SetValue(remaining)
                        end
                        if cfg.showTimer and bar._timerText then
                            -- Engine-bound decimal mirror first; the clean local format is the fallback.
                            if not MirrorEngineTimer(bar, cfg) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    else
                        -- Duration unreadable (secret) or infinite aura: show a full bar with no countdown.
                        sb:SetMinMaxValues(0, 1)
                        sb:SetValue(1)
                        if bar._timerText then
                            -- The engine-bound decimal mirror can render the secret remaining
                            -- time we cannot; otherwise no readable time -> no text.
                            bar._timerText:SetShown(MirrorEngineTimer(bar, cfg))
                        end
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end
                end
                -- Icon/name from the aura data itself: fires when the frame mirror is
                -- unavailable, and for override/variant spells the build-time saved-form
                -- icon can be the wrong form, so the live aura is the truth. Icon passes
                -- through even when secret (SetTexture accepts secrets); name applies
                -- only on a clean read (font strings need a plain string) and never
                -- over a bar's custom name.
                if bar._icon and bar._icon:IsShown() and fbAura.icon then
                    bar._icon._tex:SetTexture(fbAura.icon)
                    bar._lastIconSID = nil
                end
                local fbName = fbAura.name
                if bar._nameText and bar._nameText:IsShown() and fbName
                   and not (isSec and isSec(fbName)) and not ns.TBBCustomName(cfg) then
                    bar._nameText:SetText(fbName)
                    bar._nameSet = true
                end
                -- Extras stay quiet in fallback mode: no Blizzard child to read stacks/pandemic from. Skipped when the stack fill drove them.
                if not (sb and fbStackFill) then
                    if bar._stacksText then bar._stacksText:Hide() end
                    bar._stackCount = 0
                end
                if bar._pandemicGlowActive then ClearPandemic(bar) end
            else
                -- Inactive: clear transient state
                bar._cChild = nil
                bar._cachedBlizzFillTex = nil
                bar._cachedOurFillTex = nil
                bar._cachedBlizzIconTex = nil
                bar._cachedBlizzIconOwner = nil
                bar._lastIconSID = nil
                if _anyPandemic and bar._pandemicGlowActive then ClearPandemic(bar) end
                if bar._stacksText then bar._stacksText:Hide() end
                bar._stackCount = 0
                if cfg.hideWhenInactive == false then
                    -- "Hide When Inactive" off: keep the bar on screen as an empty idle bar (name visible, no fill/timer/spark).
                    if not bar:IsShown() then bar:Show() end
                    local sb = bar._bar
                    if sb then sb:SetMinMaxValues(0, 1); sb:SetValue(0) end
                    if bar._timerText then bar._timerText:Hide() end
                    if bar._spark then bar._spark:Hide() end
                elseif bar:IsShown() then
                    -- Clear the name latch on the hide EDGE only: clearing it every hidden
                    -- tick would make the deferred name fill call C_Spell.GetSpellInfo every tick for every hidden bar.
                    bar._nameSet = nil
                    bar:Hide()
                end
            end
        end
    end

    -- Re-pack visible grouped Tracking Bars after the active/inactive pass so hidden buffs do not reserve a slot in the group.
    if _tbbReflowDirty then ReflowVisibleGroupedTBBars(tbb, bars) end

    -- Deferred name fill: retry each tick when BuildTrackedBuffBars could not resolve the spell name (spell data not loaded yet).
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and bar._nameText and not bar._nameSet then
            local customName = ns.TBBCustomName(cfg)
            if customName then
                bar._nameText:SetText(customName)
                bar._nameSet = true
            elseif cfg.spellID and cfg.spellID > 0 then
                local si = C_Spell.GetSpellInfo(cfg.spellID)
                if si and si.name then
                    bar._nameText:SetText(si.name)
                    bar._nameSet = true
                end
            end
        end
    end

    -- Normal-fill spark maintenance (hash-fill sparks are anchored by their own renderer).
    -- Both paths use AnchorTBBSparkState's scalar signature, so unchanged anchors do no native layout work and allocate nothing.
    for _, bar in ipairs(tbbFrames) do
        -- bar:IsShown() gate: a child spark's own shown flag stays latched true after its
        -- parent bar Hides, so without this the loop would keep anchoring sparks of hidden bars every tick forever.
        if bar and bar:IsShown() and bar._spark and bar._spark:IsShown() and bar._bar then
            if not bar._chargeHashFillActive then
                local anchor = (bar._gradientActive and bar._gradClip)
                    or bar._cachedOurFillTex
                if not anchor then
                    anchor = bar._bar:GetStatusBarTexture()
                    bar._cachedOurFillTex = anchor
                end
                if anchor then
                    AnchorTBBSparkState(bar, anchor, bar._lastVertical,
                        bar._lastReverse, false)
                end
            end
        end
    end

    -- Smooth opacity lerp
    local dt = tbbTickFrame and tbbTickFrame._lastDt or 0.016
    local lerpSpeed = dt * 8
    for _, f in ipairs(tbbFrames) do
        if f and f._opacityTarget then
            local cur = f:GetAlpha()
            local tgt = f._opacityTarget
            if abs(cur - tgt) > 0.005 then
                f:SetAlpha(cur + (tgt - cur) * min(1, lerpSpeed))
            elseif cur ~= tgt then
                f:SetAlpha(tgt)
            end
        end
    end

    -- Idle sleeper: after ~0.5s of ticks with nothing live, park the OnUpdate entirely and
    -- let the wake listeners re-arm it. The settle window lets smooth fills and the opacity
    -- lerp converge (both ease within ~0.35s) before updates stop, and stays short so wake bursts remain cheap.
    if tickLive then
        _tbbWake._idleTicks = 0
    elseif tbbTickFrame and tbbTickFrame:IsShown() then
        local n = _tbbWake._idleTicks + 1
        _tbbWake._idleTicks = n
        if n >= 30 then _tbbWake.Sleep() end
    end
end

I.TBBUsesVisCondition = TBBUsesVisCondition
I.broken = false
