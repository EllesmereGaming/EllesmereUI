if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Events.lua
--
--  ApplySmoothing and ApplyAll, the roster and spec resolve timers, the
--  event handler, OnInitialize and OnEnable, the slash command and the
--  Party Mode spin.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local format = string.format
local UnitHealthMax, UnitClass, InCombatLockdown = UnitHealthMax, UnitClass, InCombatLockdown

local ERB, GetPrimaryPowerType = I.ERB, I.GetPrimaryPowerType
local GetSecondaryResource, GetSpecialization = I.GetSecondaryResource, I.GetSpecialization
local IP, IronfurBaseDuration, ironfurTicks = I.IP, I.IronfurBaseDuration, I.ironfurTicks
local POWER_COLORS, POWER_ENUM_TO_KEY = I.POWER_COLORS, I.POWER_ENUM_TO_KEY
local BuildBarTypeSpecMap, DEFAULTS = I.BuildBarTypeSpecMap, I.DEFAULTS
local _erbEventFrame, BuildMainFrame = I._erbEventFrame, I.BuildMainFrame
local CalcPipGeometry, IsPowerBarHidden = I.CalcPipGeometry, I.IsPowerBarHidden
local IsSpecDisabled, pips, runeFrames = I.IsSpecDisabled, I.pips, I.runeFrames
local secondaryPipTicks, RegisterUnlockElements = I.secondaryPipTicks, I.RegisterUnlockElements
local BuildBars, HandleIronfurCast = I.BuildBars, I.HandleIronfurCast
local UpdateHealthBar, UpdatePrimaryBar = I.UpdateHealthBar, I.UpdatePrimaryBar
local UpdateSecondaryResource, UpdateVisibility = I.UpdateSecondaryResource, I.UpdateVisibility
local AppendSharedMediaTextures, BuildCastBar = I.AppendSharedMediaTextures, I.BuildCastBar
local OnCastComplete, OnCastFailed = I.OnCastComplete, I.OnCastFailed
local OnCastStart, OnChannelStart = I.OnCastStart, I.OnChannelStart
local OnChannelStop, OnChannelUpdate = I.OnChannelStop, I.OnChannelUpdate
local OnEmpowerStart, OnEmpowerStop = I.OnEmpowerStart, I.OnEmpowerStop
local OnEmpowerUpdate, BuildGCDBar = I.OnEmpowerUpdate, I.BuildGCDBar
local BuildTotemBar, SetIronfurBaseDur = I.BuildTotemBar, I.SetIronfurBaseDur
local SetIronfurGoEUntil, SetInCombat = I.SetIronfurGoEUntil, I.SetInCombat
local SetCachedClass, SetCachedPrimary = I.SetCachedClass, I.SetCachedPrimary
local SetCachedSecondary, SetEbonMightExpiry = I.SetCachedSecondary, I.SetEbonMightExpiry
local SetEssenceNextTick, SetEssenceLastCount = I.SetEssenceNextTick, I.SetEssenceLastCount
local SetEssenceTickDur = I.SetEssenceTickDur

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
local totemBarFrame
I.totemBarFrameSetters[#I.totemBarFrameSetters + 1] = function(v) totemBarFrame = v end
local cachedPrimary
I.cachedPrimarySetters[#I.cachedPrimarySetters + 1] = function(v) cachedPrimary = v end
local cachedSecondary
I.cachedSecondarySetters[#I.cachedSecondarySetters + 1] = function(v) cachedSecondary = v end

-- Master Apply Native StatusBar fill smoothing (opt-in per bar; default off): store the
-- interpolation mode on the bar and let the CreateStatusBar SetValue wrapper
-- pass it to Blizzard's C-side interpolation. nil = no interpolation = zero
-- added cost (plain SetValue). Only the three main bars are toggled here (pips
-- never smooth; the WoW Forever druid mana bar follows the Power Bar's). The
-- cast bar has its own Smooth Bar Animation (castBar.smoothFill) and the GCD
-- bar its own bar._castInterp.
function ERB:ApplySmoothing()
    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
    local p = ERB.db and ERB.db.profile
    if not (interp and p) then return end
    local _hCfg = _G._ERB_ResolveHealthCfg(p)
    local _pCfg = _G._ERB_ResolvePowerCfg(p)
    local _sCfg = _G._ERB_ResolveSecondaryCfg(p)
    if healthBar    then healthBar._smoothing    = (_hCfg      and _hCfg.smoothBars)        and interp or nil end
    if primaryBar   then primaryBar._smoothing   = (_pCfg      and _pCfg.smoothBars)        and interp or nil end
    if secondaryBar then secondaryBar._smoothing = (_sCfg and _sCfg.smoothBars) and interp or nil end
end

-- Legacy "Anchor To" retirement. The Bar Position "Anchor To" dropdown for the
-- health/power/class resource bars is gone from the options UI, but the
-- runtime still honors profile values written before removal (or imported via
-- old profile strings). A leftover anchorTo still anchors the bar AND
-- suppresses its unlock-mode mover, with no UI left to see or clear it. Retire
-- it: once the anchored layout has real geometry, capture the bar's on-screen
-- position as a normal free position (unlockPos), clear anchorTo, and rebuild
-- -- the bar stays visually in place and gets its mover back. Geometry-dependent,
-- so it runs from ApplyAll on the active profile rather than the data-migration
-- registry. do-block + ns exposure.
do
    local pending
    local function LegacyAnchored()
        local p = ERB.db and ERB.db.profile
        if not p then return nil end
        local list
        local function add(s, f)
            -- "mouse" is the LIVE Anchor to Cursor setting (BuildCursorAnchorRow),
            -- not a retired legacy frame anchor -- migrating it froze the bar at
            -- its momentary position and nil'd the setting on every login, so
            -- cursor anchoring never survived a reload.
            if s and s.anchorTo and s.anchorTo ~= "none" and s.anchorTo ~= "mouse" then
                list = list or {}
                list[#list + 1] = { cfg = s, frame = f }
            end
        end
        add(p.health, healthBar)
        add(p.primary, primaryBar)
        add(p.secondary, secondaryFrame)
        return list
    end
    function ns.MigrateLegacyAnchorTo()
        if pending or (EllesmereUI and EllesmereUI._unlockActive) then return end
        if not LegacyAnchored() then return end
        pending = true
        -- One frame later so ApplyBarAnchor's SetPoint has flushed and
        -- GetCenter returns the anchored on-screen position.
        C_Timer.After(0, function()
            pending = nil
            if EllesmereUI and EllesmereUI._unlockActive then return end
            local list = LegacyAnchored()
            if not list then return end
            local uiS = UIParent:GetEffectiveScale()
            local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
            local cleared = false
            for _, e in ipairs(list) do
                local s, f = e.cfg, e.frame
                -- Plain multi-value assignment: wrapping GetCenter in "f and"
                -- would truncate it to one value and leave cy always nil.
                local cx, cy
                if f then cx, cy = f:GetCenter() end
                if cx and cy then
                    local r = f:GetEffectiveScale() / uiS
                    s.unlockPos = {
                        point = "CENTER", relPoint = "CENTER",
                        x = cx * r - uiW * 0.5, y = cy * r - uiH * 0.5,
                    }
                end
                -- Clear even without geometry (bar never laid out): defaults
                -- position the bar; leaving anchorTo would re-suppress the mover.
                s.anchorTo = nil
                cleared = true
            end
            if cleared then ERB:ApplyAll() end
        end)
    end
end

-- Health/power bar ping receivers. Blizzard's player-resource alert ("low mana",
-- "low health") is a CONTEXTUAL ping sent when the cursor sits over PlayerFrame and
-- not over its portrait: PingableType_PlayerUnitFrameMixin returns
-- isPlayerResource = true and C_PingSecure.SendUnitPing picks health or mana itself.
-- A player running these bars in place of the Blizzard player frame has nothing left
-- to aim at, so the alert is simply unavailable. Mark our own bars instead.
--
-- WHICH resource gets called out is not ours and cannot be made ours: SendUnitPing
-- takes (guid, type, isPlayerResource) and nothing else -- no position, no health/mana
-- member on PingSubjectType -- and Blizzard's own player frame carries that same single
-- boolean for its health bar and its mana bar alike. Field-checked 2026-08-13: at low
-- mana the Blizzard player frame also calls out health, so this matches it exactly.
--
-- No option and no mouse change: the attribute and the three getters are inert until
-- the ping system itself asks, so an unpinged bar costs nothing and behaves exactly as
-- before. Mouse stays OFF -- verified sufficient in the field, and a mouse-enabled bar
-- would steal mouseover focus from whatever sits behind it, which is why the
-- hover-reveal poll drives plain proxy tables instead of the real bars.
--
-- Taint: PingManager reads these three through securecallfunction and securecopies the
-- returned table, so our tainted execution stays contained. Safe HERE and not on the
-- unit frames (see the "NO ping mixin here" note in EUI_UnitFrames_Init.lua): this
-- receiver only ever names the player, whose GUID is never secret-content, so the
-- securecopy that hard-errors on a restricted unit has nothing to choke on.
local function ApplyPingReceivers()
    for _, bar in ipairs({ healthBar, primaryBar }) do
        if bar and not bar._erbPingOn then
            bar._erbPingOn = true
            bar:SetAttribute("ping-receiver", true)
            -- Always pingable: a receiver that answers false is treated as BLOCKING UI
            -- and kills the ping outright with PING_FAILED_GENERIC, which is strictly
            -- worse than the fall-through this replaces.
            bar.GetIsPingable = function() return true end
            -- Contextual ping only, matching Blizzard over its own player resources.
            bar.GetAllowRadialWheel = function() return false end
            bar.GetTargetInfo = function()
                return { guid = UnitGUID("player"), isPlayerResource = true }
            end
        end
    end
end

function ERB:ApplyAll()
    -- Invalidate the per-event config caches. Everything that can change a
    -- resolved config -- profile switch, option edit, spec swap, form change --
    -- routes through here, so bumping the generation in one place is enough.
    ns.CfgGen = (ns.CfgGen or 0) + 1
    local _, classFile = UnitClass("player")
    SetCachedClass(classFile)
    SetCachedPrimary(GetPrimaryPowerType())
    SetCachedSecondary(GetSecondaryResource())
    -- Seed combat state so a /reload mid-combat doesn't apply the OOC fade
    -- during the fight (isInCombat otherwise only flips on PLAYER_REGEN).
    SetInCombat(InCombatLockdown())

    BuildMainFrame()
    BuildBars()
    BuildCastBar()
    -- Hide While Using Gamepad: after the build, which a profile switch, spec
    -- override or option edit reaches without the options setter.
    ns.RB_ApplyGamepadCastbar()
    BuildGCDBar()
    BuildTotemBar()

    -- Options changes and profile swaps come through here without firing any
    -- game event, and a rebuild can leave a bar mid-animation with nothing
    -- scheduled to finish it. Arm unconditionally; the tick disarms itself.
    if ns.ArmTick then ns.ArmTick() end

    -- Apply frame strata to all existing bar frames (covers live changes). Health and
    -- power may take their own from the Frame Strata cog (false matches the main row).
    local g = ERB.db.profile.general or DEFAULTS.profile.general
    local barStrata = g.frameStrata or "MEDIUM"
    if mainFrame then mainFrame:SetFrameStrata(barStrata) end
    if healthBar then healthBar:SetFrameStrata(ERB.db.profile.health.frameStrata or barStrata) end
    if primaryBar then primaryBar:SetFrameStrata(ERB.db.profile.primary.frameStrata or barStrata) end
    if secondaryFrame then secondaryFrame:SetFrameStrata(barStrata) end
    local tb = ERB.db.profile.totemBar
    if totemBarFrame then totemBarFrame:SetFrameStrata(tb and tb.frameStrata or "MEDIUM") end
    local cb = ERB.db.profile.castBar
    if castBarFrame then castBarFrame:SetFrameStrata(cb and cb.frameStrata or "MEDIUM") end
    local gb = ERB.db.profile.gcdBar
    if gcdBarFrame then gcdBarFrame:SetFrameStrata(gb and gb.frameStrata or "MEDIUM") end
    -- Draw Above GCD Bar / Draw Above Other Bars / the power Bottom Separator:
    -- the strata pass above re-strata's every bar's children.
    ns.ERB_ReassertLayers()
    ApplyPingReceivers()
    UpdateHealthBar()
    UpdatePrimaryBar()
    UpdateSecondaryResource()
    UpdateVisibility()
    self:ApplySmoothing()
    if ns.MigrateLegacyAnchorTo then ns.MigrateLegacyAnchorTo() end
    if ns.AS_Apply then ns.AS_Apply() end
    if ns.ST_Apply then ns.ST_Apply() end
    if ns.CT_Apply then ns.CT_Apply() end

    -- Vehicle proxy: hide resource bars during full vehicle UI ([vehicleui]
    -- condition). Secure frame creation + RegisterStateDriver both need combat OOC.
    if not ERB._vehicleProxy then
        local function InitVehicleProxy()
            if ERB._vehicleProxy then return end
            ERB._vehicleProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
            ERB._vehicleProxy:SetAttribute("_onstate-erbvehicle", [[
                self:CallMethod("OnVehicleStateChanged", newstate)
            ]])
            ERB._vehicleProxy.OnVehicleStateChanged = function(_, state)
                ERB._inVehicle = (state == "hide")
                UpdateVisibility()
            end
            RegisterStateDriver(ERB._vehicleProxy, "erbvehicle", "[vehicleui][petbattle] hide; show")
        end
        if InCombatLockdown() then
            ns.CombatQueue.Defer("VehicleProxyInit", InitVehicleProxy)
        else
            InitVehicleProxy()
        end
    end

    -- Size matching: every settings path lands here, so each bar's match pad
    -- is re-checked once; the notifier compares it with the last one seen and
    -- re-pushes only a bar whose pad actually moved (one deferred pass).
    if EllesmereUI.MatchPadChanged then
        local keys = ns._erbPadKeys
        for i = 1, #keys do EllesmereUI.MatchPadChanged(keys[i]) end
    end
end

local function ScheduleRosterApply()
    EllesmereUI.InvalidateFrameCache()
    C_Timer.After(0.2, function()
        ERB:ApplyAll()
    end)
end

-- Talent/loadout changes fire TRAIT_CONFIG_UPDATED/PLAYER_TALENT_UPDATE in a burst (a
-- loadout swap applies many nodes at once); coalesce into a single out-of-combat
-- rebuild instead of running the heavy BuildBars() per event. do-block + ns exposure so
-- the pending flag/function use no main-chunk local slots.
do
    local pending
    function ns.ScheduleTalentApply()
        if pending then return end
        pending = true
        C_Timer.After(0.1, function()
            pending = false
            if InCombatLockdown() then return end
            SetIronfurBaseDur(IronfurBaseDuration())
            SetCachedPrimary(GetPrimaryPowerType())
            SetCachedSecondary(GetSecondaryResource())
            BuildBars()
            UpdatePrimaryBar()
            UpdateSecondaryResource()
            UpdateVisibility()
        end)
    end
end


-- Login race on the primary power type. GetPrimaryPowerType branches on
-- GetSpecialization(), which can still read nil half a second after
-- PLAYER_ENTERING_WORLD on a slow login (heavy addon load). Every class whose spec
-- power differs from its class base falls through to MANA on a nil spec -- Shadow
-- loses Insanity, Guardian loses Rage, Augmentation loses Ebon Might -- and
-- PLAYER_SPECIALIZATION_CHANGED fires only on a CHANGE, never at login, so the
-- wrong value stayed cached for the whole session. Reported as "power type resets
-- to mana every time I log in".
--
-- Retry until the spec reads, then re-resolve exactly what the spec-change branch
-- does. Costs one call and no timer when the spec is already available, which is
-- the common case. The attempt cap matters: a character with no specialization
-- chosen reads nil forever, so an uncapped retry would arm timers for the session.
local _specResolveTries = 0
local ScheduleSpecResolve
ScheduleSpecResolve = function()
    -- WoW Forever: the GetSpecialization alias above always reads nil there, so
    -- no retry could ever succeed; nothing is armed.
    if EllesmereUI.IS_FOREVER then return end
    if GetSpecialization() then _specResolveTries = 0; return end
    if _specResolveTries >= 40 then return end   -- ~20s, then stop rather than spin
    _specResolveTries = _specResolveTries + 1
    C_Timer.After(0.5, function()
        if not GetSpecialization() then
            ScheduleSpecResolve()
            return
        end
        _specResolveTries = 0
        ns.InvalidateThresholdCaches()
        SetCachedPrimary(GetPrimaryPowerType())
        SetCachedSecondary(GetSecondaryResource())
        BuildBars()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    end)
end

-- Event handling
local function OnEvent(self, event, ...)
    if event == "UNIT_HEALTH" then
        UpdateHealthBar()
        if healthBar and healthBar._missLive then ns.ERB_MissingPaint(healthBar) end
        -- Stagger is based on health, so update secondary resource too
        if cachedSecondary and cachedSecondary.power == "BREWMASTER_STAGGER" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_POWER_FREQUENT" then
        -- Fires on every power change, so both bars paint on this event alone,
        -- as Blizzard's own resource display and class resource bars do: the
        -- throttled UNIT_POWER_UPDATE only re-reports changes this event has
        -- already delivered, and is not registered. The Power Bar paints only
        -- for a change of the type it shows (payload token; an unmapped type
        -- or a secret token paints).
        local unit, powerToken = ...
        if unit == "player" then
            local tok = POWER_ENUM_TO_KEY[cachedPrimary]
            if not tok or issecretvalue(powerToken) or powerToken == tok then
                UpdatePrimaryBar()
            end
            if primaryBar then
                if primaryBar._missLive then
                    local mtok = POWER_ENUM_TO_KEY[primaryBar._missPower]
                    if not mtok or issecretvalue(powerToken) or powerToken == mtok then
                        ns.ERB_MissingPaint(primaryBar)
                    end
                end
                local mh = primaryBar._missHost
                if mh and mh._missLive and (issecretvalue(powerToken) or powerToken == "MANA") then
                    ns.ERB_MissingPaint(mh)
                end
            end
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXHEALTH" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        UpdateHealthBar()
        if healthBar and healthBar._missLive then ns.ERB_MissingPaint(healthBar) end
        -- Two-step max-health landing (max first, value after): one next-frame
        -- re-read settles torn numbers (canonical story: UF engine RESETTLE_EVENTS).
        if not self._erbHpResettle then
            self._erbHpResettle = true
            C_Timer.After(0, function()
                self._erbHpResettle = nil
                UpdateHealthBar()
            end)
        end
        -- Stagger / Ignore Pain max derives from player max health
        if cachedSecondary and (cachedSecondary.power == "BREWMASTER_STAGGER"
           or cachedSecondary.power == "IGNOREPAIN_BAR") then
            local newMax = UnitHealthMax("player") or 1
            if not issecretvalue or not issecretvalue(newMax) then
                if cachedSecondary.power == "IGNOREPAIN_BAR" then
                    newMax = newMax * IP.CAP
                end
                if newMax > 0 and newMax ~= cachedSecondary.max then
                    cachedSecondary.max = newMax
                    BuildBars()
                    -- BuildBars re-shows the frames; re-apply conditional hides
                    -- (same as the UNIT_MAXPOWER rebuild below). Without this a
                    -- max-health change -- gearing up, an item upgrade, a stamina
                    -- buff -- leaves bars that a visibility condition had hidden
                    -- parked visible until the next visibility event.
                    UpdateVisibility()
                    -- BuildBars repainted the Power Bar's base fill; repaint its
                    -- live colors now rather than at the next power change.
                    UpdatePrimaryBar()
                end
            end
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        -- Drives the Prot Ignore Pain bar; no-op for everyone else.
        if cachedSecondary and cachedSecondary.power == "IGNOREPAIN_BAR" then
            UpdateSecondaryResource()
        end
    elseif event == "UNIT_MAXPOWER" then
        -- Re-check secondary resource in case max changed (e.g. talent-based pip count)
        local newSec = GetSecondaryResource()
        local oldMax = cachedSecondary and cachedSecondary.max
        local newMax = newSec and newSec.max
        if oldMax ~= newMax then
            SetCachedSecondary(newSec)
            BuildBars()
            -- BuildBars re-shows the frames; re-apply conditional hides.
            UpdateVisibility()
        end
        UpdatePrimaryBar()
        if primaryBar then
            if primaryBar._missLive then ns.ERB_MissingPaint(primaryBar) end
            local mh = primaryBar._missHost
            if mh and mh._missLive then ns.ERB_MissingPaint(mh) end
        end
        UpdateSecondaryResource()
    elseif event == "RUNE_POWER_UPDATE" then
        UpdateSecondaryResource()
    elseif event == "UNIT_POWER_POINT_CHARGE" then
        -- The charged set is not in the value early-out's key: drop the memo so
        -- a charge change with the count unchanged still repaints.
        if ns.SecSt then ns.SecSt.gen = nil end
        UpdateSecondaryResource()
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetInCombat(true)
        UpdateVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetInCombat(false)
        UpdateVisibility()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
        if event == "PLAYER_TARGET_CHANGED" then UpdateVisibility() end
        -- WoW Forever: combo points belong to the target, so a target swap, or
        -- the points moving to a new target, changes the count with no power
        -- event behind it. Skipped while the Class Resource is off.
        if cachedSecondary and cachedSecondary.onTarget then
            local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
            if sp and sp.enabled ~= false and not IsSpecDisabled(sp) then UpdateSecondaryResource() end
        end
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_CAN_GLIDE_CHANGED"
        or event == "PLAYER_IS_GLIDING_CHANGED" or event == "PLAYER_UPDATE_RESTING"
        or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        UpdateVisibility()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Re-check secondary max power: UnitPowerMax can change across zone
        -- transitions (e.g. Prot Paladin holy power reporting 3 vs 5).
        -- UNIT_MAXPOWER doesn't always fire reliably on zone change.
        local newSec = GetSecondaryResource()
        local oldMax = cachedSecondary and cachedSecondary.max
        local newMax = newSec and newSec.max
        if oldMax ~= newMax then
            SetCachedSecondary(newSec)
            BuildBars()
            -- Repaint both bars on the rebuilt frames, as UNIT_MAXPOWER does.
            UpdatePrimaryBar()
            UpdateSecondaryResource()
        end
        UpdateVisibility()
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateVisibility()
        ScheduleRosterApply()
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        SetEssenceNextTick(nil)
        SetEssenceLastCount(nil)
        SetEssenceTickDur(0)
        SetEbonMightExpiry(0)
        wipe(ironfurTicks)
        SetIronfurGoEUntil(0)
        SetIronfurBaseDur(IronfurBaseDuration())
        IP.hashEndTime = 0
        ns.InvalidateThresholdCaches()
        SetCachedPrimary(GetPrimaryPowerType())
        SetCachedSecondary(GetSecondaryResource())
        BuildBars()
        BuildCastBar()
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        -- A talent toggled or a loadout applied. Invalidate the talent-gate
        -- caches immediately (cheap; hot paths re-resolve next tick) and
        -- coalesce the heavy rebuild via a debounce so a burst of node events
        -- rebuilds once, not once per event.
        ns.InvalidateThresholdCaches()
        ns.ScheduleTalentApply()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        SetCachedPrimary(GetPrimaryPowerType())
        SetCachedSecondary(GetSecondaryResource())
        -- Leaving Bear form drops all Ironfur in-game, so clear tracker
        -- Otherwise shifting out and rapidly back in shows the stale stacks.
        if not (cachedSecondary and cachedSecondary.power == "IRONFUR_BAR") then
            wipe(ironfurTicks)
            SetIronfurGoEUntil(0)
        end
        BuildBars()
        UpdateHealthBar()  -- re-evaluate per-form text visibility
        UpdatePrimaryBar()
        UpdateSecondaryResource()
        UpdateVisibility()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            if cachedPrimary == "EBON_MIGHT" then UpdatePrimaryBar() end
            if cachedSecondary then
                -- Refresh on aura change for custom resources and for buff coloring
                -- (any resource type -- a tracked buff gain/loss recolors the bar).
                if cachedSecondary.type == "custom" or ns.SecTracks() then
                    UpdateSecondaryResource()
                end
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Route to manual resource trackers (12.0+ secret-value safe)
        local unit, _, spellID = ...
        if unit == "player" then
            HandleIronfurCast(spellID)
            IP.HandleCast(spellID)
            if cachedSecondary and (cachedSecondary.type == "custom"
               or cachedSecondary.power == "IRONFUR_BAR") then
                UpdateSecondaryResource()
            end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        -- Reset manual trackers on death/resurrect
        wipe(ironfurTicks)
        SetIronfurGoEUntil(0)
        IP.hashEndTime = 0
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            ERB:ApplyAll()
            RegisterUnlockElements()
            -- ApplyAll just cached the power type off a spec that may not have
            -- loaded yet; correct it once it does.
            ScheduleSpecResolve()
        end)
    elseif event == "UNIT_SPELLCAST_START" then
        local unit = ...
        if unit == "player" then OnCastStart() end
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        -- Cast pushback (damage taken mid-cast) or any other mid-cast cast time change:
        -- Blizzard shifts the cast's start/end times. Re-read them or the fill
        -- completes at the stale early end and the bar sits full for the rest of the
        -- real cast. (Channels get the same via UNIT_SPELLCAST_CHANNEL_UPDATE.)
        local unit = ...
        if unit == "player" and castBarFrame and castBarFrame._casting then
            local name, _, _, startTimeMS, endTimeMS = UnitCastingInfo("player")
            if name then
                castBarFrame._startTime = startTimeMS / 1000
                castBarFrame._endTime = endTimeMS / 1000
                castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
                ns.ApplyCastTimer("cast")
            end
        end
    elseif event == "UNIT_SPELLCAST_STOP" then
        local unit, _, _, castID = ...
        if unit == "player" then OnCastComplete(castID) end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- args: unit, castGUID, spellID, castID
        local unit, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- args: unit, castGUID, spellID, interruptedBy, castID
        local unit, _, _, _, castID = ...
        if unit == "player" then OnCastFailed(castID) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit = ...
        if unit == "player" then OnChannelStart() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local unit = ...
        if unit == "player" then OnChannelUpdate() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- args: unit, castGUID, spellID, interruptedBy, castBarID
        local unit = ...
        if unit == "player" then OnChannelStop() end
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        local unit = ...
        if unit == "player" then OnEmpowerStart() end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        -- args: unit, castGUID, spellID, empowerComplete, interruptedBy, castID
        local unit, _, _, _, _, castID = ...
        if unit == "player" then OnEmpowerStop(castID) end
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        local unit = ...
        if unit == "player" then OnEmpowerUpdate() end
    end
end


-- Initialization
function ERB:OnInitialize()
    -- Spec Overrides migration basis: stored profile tables are sparse (Lite
    -- merges defaults at NewDB, not persisted), so the RB Advanced migration
    -- compares against these defaults. Export, then migrate every stored
    -- profile (idempotent; flagged per RB profile table).
    EllesmereUI._RBSectionDefaults = {
        health    = DEFAULTS.profile.health,
        primary   = DEFAULTS.profile.primary,
        secondary = DEFAULTS.profile.secondary,
    }
    self.db = EllesmereUI.Lite.NewDB("EllesmereUIResourceBarsDB", DEFAULTS, true)
    if EllesmereUI.MigrateRBAdvancedProfile and EllesmereUIDB and EllesmereUIDB.profiles then
        for _, prof in pairs(EllesmereUIDB.profiles) do
            EllesmereUI.MigrateRBAdvancedProfile(prof)
        end
    end

    _G._ERB_AceDB = self.db
    _G._ERB_Apply = function() ERB:ApplyAll() end
    _G._ERB_ApplySmoothing = function() ERB:ApplySmoothing() end
    -- Unlock mode / EUI options panel: temporarily render the power bar at its true
    -- stored height (no expand) so movers and getSize see the real size. RUNTIME-ONLY
    -- suppression via EllesmereUI._erbExpandSuppressed -- NEVER writes the saved
    -- primary.expandIfNoResource setting. Mutating the saved bool directly is unsafe:
    -- the toggle's getValue reads it and the Lite DB persists it verbatim, so opening
    -- the panel would read the toggle OFF, a missed restore (reload/logout) would
    -- strand it false on disk with no recovery, and profile swaps would write the flag
    -- onto the wrong profile. Mirrors the shift provider below, which computes its
    -- effect from live state and never writes the saved value. The ApplyAll gate also
    -- checks EllesmereUI._unlockActive directly, so the panel->unlock transition stays
    -- suppressed even if this flag races (e.g. the unlock-open animation fires the
    -- panel OnHide and clears the flag while _unlockActive is still true).
    _G._ERB_SuppressExpand = function()
        EllesmereUI._erbExpandSuppressed = true
        ERB:ApplyAll()
    end
    _G._ERB_RestoreExpand = function()
        EllesmereUI._erbExpandSuppressed = false
        ERB:ApplyAll()
    end
    _G._ERB_GetSecondaryResource = GetSecondaryResource
    _G._ERB_CalcPipGeometry = CalcPipGeometry
    _G._ERB_GetPrimaryPowerType = GetPrimaryPowerType
    _G._ERB_PowerColors = POWER_COLORS

    -- "Shift Elements if No Resource" / "Shift Elements if No Power": direction
    -- signals the shared anchor engine consults to temporarily move elements
    -- anchored to the class resource bar (spec has no class resource) or the
    -- power bar (spec has no primary power, e.g. BM/MM Hunter whose Focus shows
    -- as the class resource bar, or the power bar is disabled outright).
    -- Visual-only; never written to saved positions. Direction the shift WOULD
    -- apply (ignores unlock state): +1 = Up, -1 = Down, 0 = none.
    local function ResolveShiftDir()
        local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        if not sp then return 0 end
        local mode = sp.shiftElementsIfNoResource
        if mode ~= "Up" and mode ~= "Down" then return 0 end
        -- Fires whenever the class resource bar leaves an empty slot: hidden via
        -- "Show Class Resource", disabled for the CURRENT spec/DRUID FORM, or the
        -- spec has no class resource. The frame is created unconditionally (zero
        -- alpha when off), so there is always a target to anchor to -- mirrors
        -- ResolveShiftDirPower. The form test must match the visibility pass
        -- exactly, or a form-hidden bar's empty slot stays uncovered (the shift
        -- never fires).
        if sp.enabled ~= false and not IsSpecDisabled(sp)
           and not _G._ERB_BarHiddenByForm(sp)
           and GetSecondaryResource() then return 0 end
        return (mode == "Up") and 1 or -1
    end
    local function ResolveShiftDirPower()
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        if not pp then return 0 end
        local mode = pp.shiftElementsIfNoPower
        if mode ~= "Up" and mode ~= "Down" then return 0 end
        -- Fires whenever the power bar leaves an empty slot. IsPowerBarHidden() is the
        -- single source of truth for that -- the same predicate the visibility pass and
        -- "Resource Text" gate consult -- so the shift can never disagree with what's
        -- on screen; every future power-hiding condition reaches the shift for free by
        -- landing in that helper. The power frame is created unconditionally and kept
        -- at full height/zero alpha when not shown, so anchored children and the shift
        -- magnitude (target height) stay correct in every hidden case.
        if not IsPowerBarHidden() then return 0 end
        return (mode == "Up") and 1 or -1
    end
    -- Seeded into the shared shift-provider list (EUI_UnlockMode.lua dispatches
    -- EllesmereUI._GetAnchorTargetShiftDir over it; CooldownManager seeds its
    -- own provider for TBBG_ keys). Direct or-preserve push, NEVER an API call:
    -- registration must carry zero load-order coupling (the old single-slot
    -- assignment's property; a cross-file call here hit nil in the field).
    -- dir: consulted inside ApplyAnchorPosition; returns 0 while unlock mode is
    -- active so the layout shows normal (and movers capture true positions),
    -- else dir (+1/-1/0) and an optional extra-pixel offset added to the shift
    -- magnitude ("Extra Y Offset" -- only meaningful when dir ~= 0). wants:
    -- whether a shift WOULD apply outside unlock mode (unlock entry un-shifts
    -- before snapshotting; deliberately ignores unlock state). restore:
    -- re-apply after unlock closes (PropagateAnchorChain is a no-op while
    -- unlocked). Gated so None = zero work.
    EllesmereUI._anchorShiftProviders = EllesmereUI._anchorShiftProviders or {}
    table.insert(EllesmereUI._anchorShiftProviders, {
        dir = function(targetKey, childKey)
            if EllesmereUI._unlockActive then return 0 end
            if targetKey == "ERB_ClassResource" then
                local dir = ResolveShiftDir()
                if dir == 0 then return 0 end
                local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
                return dir, (sp and sp.shiftElementsIfNoResourceExtraY) or 0
            end
            if targetKey == "ERB_Power" then
                local dir = ResolveShiftDirPower()
                if dir == 0 then return 0 end
                local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
                return dir, (pp and pp.shiftElementsIfNoPowerExtraY) or 0
            end
            return 0
        end,
        wants = function()
            return ResolveShiftDir() ~= 0 or ResolveShiftDirPower() ~= 0
        end,
        restore = function()
            if not EllesmereUI.PropagateAnchorChain then return end
            if ResolveShiftDir() ~= 0 then
                EllesmereUI.PropagateAnchorChain("ERB_ClassResource")
            end
            if ResolveShiftDirPower() ~= 0 then
                EllesmereUI.PropagateAnchorChain("ERB_Power")
            end
        end,
    })

    BuildBarTypeSpecMap()

    AppendSharedMediaTextures()
end

function ERB:OnEnable()
    -- The event frame was created at file scope so its handler work bills
    -- this addon (see the note in EUI_ResourceBars_Frames.lua); here we only register
    -- events and attach the handler.
    local eventFrame = _erbEventFrame
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "player")
    eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- WoW Forever: combo points moving to a new target fire no power event
    -- (only a rogue or druid ever raises it; the handler acts for onTarget).
    if EllesmereUI.IS_FOREVER == true then
        eventFrame:RegisterEvent("COMBO_TARGET_CHANGED")
    end
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    -- Visibility option events
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    -- Resting: IsResting() has no dedicated poll, so without this the Resting
    -- axis only re-evaluated when some unrelated event above happened to fire.
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    -- Vehicle edges for the In Vehicle axis (player-filtered; same reasoning).
    eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    -- Airborne edge for the dragonriding visibility modes (probed at load
    -- in EllesmereUI_Visibility.lua; absent = the checklist items lock)
    if EllesmereUI._hasGlidingEvent then
        eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    end

    -- Mouseover hover-reveal: one proxy per bar registered with the shared poll. Plain
    -- tables (Quest Tracker precedent) so the poll never calls EnableMouse/Show on the
    -- real bars -- a mouse-enabled bar would steal mouseover focus from frames beneath
    -- it. Eligibility comes from the flags UpdateVisibility maintains, so hover only
    -- reveals a bar whose evaluation currently lands on "mouseover".
    if EllesmereUI.RegisterMouseoverTarget then
        local function RegisterBarHover(barKey, frameGetter)
            local proxy = {}
            proxy.GetRect = function()
                local f = frameGetter()
                if f then return f:GetRect() end
                return nil
            end
            proxy.GetEffectiveScale = function()
                local f = frameGetter()
                return f and f:GetEffectiveScale() or 1
            end
            proxy.SetAlpha = function() end
            proxy.EnableMouse = function() end
            proxy.Show = function()
                local f = frameGetter()
                if f then EllesmereUI.SetElementVisibility(f, true) end
            end
            proxy.Hide = function()
                local f = frameGetter()
                if f then EllesmereUI.SetElementVisibility(f, false) end
            end
            EllesmereUI.RegisterMouseoverTarget(proxy, function()
                return ERB._moEligible and ERB._moEligible[barKey] or false
            end)
        end
        RegisterBarHover("health", function() return healthBar end)
        RegisterBarHover("primary", function() return primaryBar end)
        -- Blizzard Class Resource Art: hover reveals the host holding Blizzard's
        -- frame (nil while it waits to be claimed at login).
        RegisterBarHover("secondary", function()
            if ns._erbArtOn then return ns._erbArtHost end
            return secondaryFrame
        end)
    end
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    -- Arm the shared tick after every event: any of them can start something
    -- animating (value change, cast start, GCD, spec swap, form change), and
    -- working out which ones can't is exactly the cleverness that eventually
    -- freezes a bar. The tick disarms itself once nothing is in flight, so a
    -- redundant arm costs a single tick. See "Tick arming".
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        OnEvent(self, event, ...)
        -- Three independent subscribers. Each is armed only by the state that
        -- needs it, and each disarms itself, so a cast no longer drags the
        -- health/power/secondary blocks along at frame rate.
        if castBarFrame and (castBarFrame._casting
           or castBarFrame._channeling or castBarFrame._empowering) then
            ns.StartCastTick()
        end
        if gcdBarFrame and gcdBarFrame._gcdStart then
            ns.GCDTick.Start()
        end
        ns.ArmTick()
    end)


    ns.ArmTick()

    -- A cast bar profile already on a stock style gets its one-time seed
    -- before the first build (the Style page seeds on the switch); an
    -- unseeded one keeps its own texture in the EllesmereUI slot first, so a
    -- switch back restores it.
    if ns.ERB_CastBlizz() then
        local cb = self.db.profile.castBar
        if cb and not cb.stockTextureSeeded and EllesmereUI.BankEuiStyleSlot then
            EllesmereUI.BankEuiStyleSlot(cb, ns._erbCastSlotKeys)
        end
        ns.ERB_SeedStockCast(cb)
    end
    -- The same for the bars: an unseeded profile keeps its own values in the
    -- EllesmereUI slot before the Classic seed writes over them.
    if ns.ERB_BarsClassic() then
        local p = self.db.profile
        local g = p and p.general
        if g and not g.classicTextureSeeded and not g.borderAllSeeded and EllesmereUI.BankEuiStyleSlot then
            EllesmereUI.BankEuiStyleSlot(p, ns._erbBarsSlotKeys)
        end
        ns.ERB_SeedStockBars(p, "classic")
    end

    -- Apply immediately at PLAYER_LOGIN so positions are set before combat
    -- lockdown blocks ApplySavedPositions. The PLAYER_ENTERING_WORLD handler
    -- will re-apply after the full game state is available.
    ERB:ApplyAll()
    RegisterUnlockElements()

    -- Re-render when the global Dark Mode palette changes so the class resource
    -- bar's dark colours update live (colours are fetched live each render, so a
    -- plain rebuild is enough). ApplyAll touches secure positioning, so guard combat.
    EllesmereUI.RegisterDarkModeRefresh(function()
        if InCombatLockdown() then return end
        ERB:ApplyAll()
    end)

    -- Global Dark Mode master: expose the class resource bar's darkTheme flag so
    -- the parent addon's master toggle can flip it alongside other modules.
    -- Combat-guarded like the palette refresher above.
    EllesmereUI.RegisterDarkModeToggle({
        id = "resourceBars",
        isOn = function()
            return (ERB.db and ERB.db.profile and ERB.db.profile.secondary
                and ERB.db.profile.secondary.darkTheme) or false
        end,
        setOn = function(on)
            if not (ERB.db and ERB.db.profile and ERB.db.profile.secondary) then return end
            ERB.db.profile.secondary.darkTheme = on
            if not InCombatLockdown() then ERB:ApplyAll() end
        end,
    })

    -- Collapse/restore expandIfNoResource when EUI options panel opens/closes
    EllesmereUI:RegisterOnShow(function()
        if _G._ERB_SuppressExpand then _G._ERB_SuppressExpand() end
    end)
    EllesmereUI:RegisterOnHide(function()
        if _G._ERB_RestoreExpand then _G._ERB_RestoreExpand() end
    end)
end

-- Slash commands
SLASH_ERB1 = "/erb"
SLASH_ERB2 = "/ellesresource"
SlashCmdList.ERB = function(msg)
    if msg == "lock" or msg == "unlock" then
        -- Unlock mode is now handled by the shared EllesmereUI system
        if EllesmereUI and EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end
    EllesmereUI:ShowModule("EllesmereUIResourceBars")
end

-------------------------------------------------------------------------------
--  Party Mode: spinning resource and power bars (EllesmereUI.PartySpin_Create).
--  Resource Bars: pips / runes orbit the class resource bar's centre.
--  Power Bars: the health and primary power bars orbit the screen centre.
-------------------------------------------------------------------------------
-- Wrapped in a function to keep its locals out of the main chunk.
;(function()
-- Party Mode visibility axis: no game event; the core fires its own edge.
if EllesmereUI.RegisterVisEdge then
    EllesmereUI.RegisterVisEdge(function() UpdateVisibility() end)
end
do
    -- The backdrop, gap fills and ticks are drawn on the bar and cannot turn,
    -- and empty pips are transparent, so while spinning those layers fade out
    -- and each pip gets its own backing. Restore puts the saved alphas back.
    local resGroups, resList = {}, {}
    local resGroup = { frames = resList }
    local savedA = {}          -- texture -> alpha before we faded it
    local backings = {}        -- pip/rune -> our backing texture

    local function Fade(tex)
        if tex and savedA[tex] == nil then
            savedA[tex] = tex:GetAlpha()
            tex:SetAlpha(0)
        elseif tex then
            tex:SetAlpha(0)    -- re-assert: a rebuild may have reset it
        end
    end
    local function Back(piece)
        local t = backings[piece]
        if not t then
            t = piece:CreateTexture(nil, "BACKGROUND", nil, -8)
            t:SetAllPoints(piece)
            t:SetColorTexture(0, 0, 0, 0.5)
            backings[piece] = t
        end
        t:Show()
    end

    EllesmereUI.PartySpin_Create({
        target = "resource",
        collect = function()
            wipe(resGroups); wipe(resList)
            if secondaryFrame and not ns._erbArtOn then
                for i = 1, #pips do
                    local p = pips[i]
                    if p and p:IsShown() then resList[#resList + 1] = p end
                end
                for i = 1, #runeFrames do
                    local r = runeFrames[i]
                    if r and r:IsShown() then resList[#resList + 1] = r end
                end
                resGroup.pivot = secondaryFrame
                resGroups[1] = resGroup
            end
            return resGroups
        end,
        onClaim = function()
            if not secondaryFrame or #resList == 0 then return end
            Fade(secondaryFrame._barBg)
            local gf = secondaryFrame._gapFills
            if gf then for i = 1, #gf do Fade(gf[i]) end end
            for i = 1, #secondaryPipTicks do Fade(secondaryPipTicks[i]) end
            for i = 1, #resList do Back(resList[i]) end
        end,
        onRestore = function()
            for tex, a in pairs(savedA) do tex:SetAlpha(a) end
            wipe(savedA)
            for _, t in pairs(backings) do t:Hide() end
        end,
    })

    local powList = {}
    local powGroups = { { pivot = UIParent, frames = powList } }
    EllesmereUI.PartySpin_Create({
        target = "power",
        collect = function()
            wipe(powList)
            if healthBar then powList[#powList + 1] = healthBar end
            if primaryBar then powList[#powList + 1] = primaryBar end
            return powGroups
        end,
    })
end
end)()

I.broken = false
