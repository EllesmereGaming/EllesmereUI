if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Lifecycle.lua
--
--  The public toggles, vehicle and cinematic hiding, the events and the
--  recovery path.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local PAB, ComputeGrid, DefaultBuffsCfg = I.PAB, I.ComputeGrid, I.DefaultBuffsCfg
local DefaultDebuffsCfg, ApplyDefaultBarShown = I.DefaultDebuffsCfg, I.ApplyDefaultBarShown
local ApplyLiveConfig, BuffsContentSig = I.ApplyLiveConfig, I.BuffsContentSig
local CreateBars, RegisterPABUnlock = I.CreateBars, I.RegisterPABUnlock
local SetParentShownSafe = I.SetParentShownSafe
local ShowBlizzardPlayerAuras = I.ShowBlizzardPlayerAuras
local SyncEnchantEvents, SyncNativeAuras = I.SyncEnchantEvents, I.SyncNativeAuras
local customBuffContainers, customBuffParents = I.customBuffContainers, I.customBuffParents
local customDebuffContainers = I.customDebuffContainers
local customDebuffParents = I.customDebuffParents
local RegisterPABCustomUnlock = I.RegisterPABCustomUnlock
local ReloadAllCustomBars, SetPabSuppressed = I.ReloadAllCustomBars, I.SetPabSuppressed

local buffsContainer
I.buffsContainerSetters[#I.buffsContainerSetters + 1] = function(v) buffsContainer = v end
local debuffsContainer
I.debuffsContainerSetters[#I.debuffsContainerSetters + 1] = function(v) debuffsContainer = v end
local buffsParent
I.buffsParentSetters[#I.buffsParentSetters + 1] = function(v) buffsParent = v end
local debuffsParent
I.debuffsParentSetters[#I.debuffsParentSetters + 1] = function(v) debuffsParent = v end
local buffsSlotSig
I.buffsSlotSigSetters[#I.buffsSlotSigSetters + 1] = function(v) buffsSlotSig = v end

local ClearDegraded -- forward-declared; defined in the recovery section, called from PAB_SetEnabled
local vehicleHidden = false -- vehicle ride state; feeds pabSuppressed

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

-- Login build: EUI_UnitFrames_OptionsSetup.lua's SetupOptionsPanel() calls this once it
-- has set ns.db. A PLAYER_LOGIN listener here needed EnableBody's handler to run
-- first and stood down silently otherwise (field: Blizzard buffs up, no custom
-- bars until an options change). A disabled Unit Frames module never runs
-- SetupOptionsPanel, so PAB stays down with no extra check.
ns.PAB_CreateBars = CreateBars

function ns.PAB_Enabled()
    local s = PAB()
    return (s and s.enabled == true) or false
end

-- Called by the options page's activation overlay and the sidebar's Disable
-- All toggle. Enabling builds the bars live (CreateBars guards its own
-- re-entry; container creation is combat-legal). Disabling is reload-bound
-- for the BLIZZARD side (the corner-frame
-- hide latches for the session) but stands every PAB frame down NOW -- the
-- field bug was custom bars lingering through the "Later" window while the
-- default bars hid: Disable All must be a complete visual no-op.
function ns.PAB_SetEnabled(v)
    local s = PAB()
    if not s then return end
    s.enabled = v and true or nil
    if v then
        -- A stand-down latched before the module went off has no lane to lift
        -- it while disabled, and the rebuild below would come up dimmed.
        ClearDegraded()
        CreateBars()
        return
    end
    if buffsParent then buffsParent:Hide() end
    if debuffsParent then debuffsParent:Hide() end
    for _, parent in pairs(customBuffParents) do parent:Hide() end
    for _, parent in pairs(customDebuffParents) do parent:Hide() end
    SyncEnchantEvents(false)
    -- The re-hide hooks release once the master is off: hand Blizzard's
    -- native display back live.
    ShowBlizzardPlayerAuras()
    -- Re-registering re-reads isHidden (master gate now false everywhere), so
    -- an open unlock session drops every PAB mover immediately.
    RegisterPABUnlock()
    RegisterPABCustomUnlock()
end

-- Stock styles (Global Settings > Style) for the aura bars: "eui",
-- "blizzard" or "classic", read from the profile once (first call with a
-- profile present) and latched for the session like the other module
-- getters, so a live profile switch never flips the look under the
-- engine-registered border art; the profile system prompts for a reload
-- instead. The Classic flag wins when both are set. Both stock styles wear
-- the same stock aura borders, so PAB_Blizz answers for either.
function ns.PAB_Style()
    local v = ns._pabStyle
    if v == nil then
        local s = PAB()
        if not s then return "eui" end
        v = (s.useClassicStyle and "classic") or (s.useBlizzardStyle and "blizzard") or "eui"
        ns._pabStyle = v
    end
    return v
end
function ns.PAB_Blizz() return ns.PAB_Style() ~= "eui" end

-- Profile-grade resync, called from the _EUF_ReloadFrames tail (profile
-- switches, imports, spec-override swaps all land there): re-asserts the
-- CURRENT profile's enable/useBlizzard modes across the default-bar
-- visibility, the native frames and the default unlock movers. Builds the
-- module late when a swap crosses from a disabled-at-login state into an
-- enabled profile (nothing else would). Deliberately does NOT run
-- ApplyLiveConfig: its size-rebase writes assume lastSize belongs to the
-- SAME profile and would corrupt the new profile's saved positions.
function ns.PAB_ProfileResync()
    local s = PAB()
    if s and s.enabled == true and s.useBlizzardBuffs ~= true
        and not (buffsParent or debuffsParent) then
        -- Enabled profile, module never built this session: full build
        -- (covers customs + unlock + natives itself).
        CreateBars()
        return
    end
    -- Content that can only change by rebuilding the container (the resolved
    -- spell set, and the weapon-enchant row the engine cannot undeclare) does
    -- not reach ApplyLiveConfig on a swap, so the new profile's signature is
    -- reconciled here. CreateBars is the safe lane for it: it applies the new
    -- profile's sizes and positions outright instead of running
    -- ApplyLiveConfig's size-rebase against the OLD profile's lastSize.
    if s and s.enabled == true and s.useBlizzardBuffs ~= true and buffsParent then
        local buffCfg = DefaultBuffsCfg(s)
        local buffGrid = ComputeGrid(true, buffCfg)
        if BuffsContentSig(buffCfg, ns.PAB_ResolveSpells(buffCfg), buffGrid.enchSlots) ~= buffsSlotSig then
            CreateBars()
            return
        end
    end
    ApplyDefaultBarShown(true)
    ApplyDefaultBarShown(false)
    SyncNativeAuras()
    RegisterPABUnlock()
end

-- Live apply for the Use Blizzard Buffs toggle. ON: the default bars stand
-- down and the natives come back NOW (the re-hide hooks read ownership
-- live). OFF: a full CreateBars pass rebuilds the default bars and hides
-- the natives again, entirely live. Custom bars run in both modes.
function ns.PAB_ApplyUseBlizzard()
    local s = PAB()
    if not (s and s.enabled == true) then return end
    if s.useBlizzardBuffs == true then
        ApplyDefaultBarShown(true)
        ApplyDefaultBarShown(false)
        SyncEnchantEvents(false)
        ShowBlizzardPlayerAuras()
        RegisterPABUnlock()
    else
        CreateBars()
        RegisterPABUnlock()
    end
end

-- Cinematic / faction-flip recovery. Two triggers, one degradation class:
-- an addon-cancelled cinematic (CINEMATIC_STOP) puts the engine aura
-- containers through a hide/re-show whose re-parse can land while the
-- teardown's filter state is still degraded, and EVERY cinematic
-- (in-world cutscenes included) fires UNIT_FACTION for the player at start
-- and end -- the unit briefly stops being assistable, which silently
-- disables spell-ID candidate filters engine-side (authors-channel
-- consensus 2026-08-13: same mechanism community-wide; UNIT_FLAGS does NOT
-- fire, UNIT_FACTION is the only edge). Filtered bars then render the FULL
-- buff set, and with no aura event following, the wrong content sticks.
-- The one lever Lua holds over engine-owned content is config: re-run the
-- group config for every live container (candidate filters are the
-- live-changeable channel, so re-setting them forces a fresh parse), one
-- tick after the event so the transition has finished. Coalesced; the
-- start+end UNIT_FACTION burst collapses to one re-drive.
-- Vehicle suppression: assistability stays down for the WHOLE ride, so the
-- exit re-drive alone still left the ride itself showing the full buff set.
-- Match the raid frames' gate by standing the bar parents down -- the
-- vehicle has its own UI -- and restoring on exit, where the recovery
-- re-drive repaints from clean filter state. The stand-down is alpha, not a
-- Hide (SetParentShownSafe): the exit routinely lands inside lockdown, where
-- a Show is blocked. A suppressed ride therefore costs what ordinary play
-- costs -- the containers stay registered behind alpha 0.
-- vehicleHidden is declared at the top of this file; pabSuppressed lives in
-- EUI_PlayerAuraBars_Bars.lua (every parent-visibility pass reads it).
-- Bare apply, no state guard: the recovery lane re-asserts the CURRENT
-- state after its reload paths (which Show() the parents as a side effect).
-- Restoring (hidden = false) honors each bar's OWN enable toggle -- a
-- vehicle exit must never re-show a disabled bar's fully-populated grid.
-- Probe-verified self-assist state (the RF AssistProbe self-branch, ported):
-- the engine's spell-ID filter degradation tracks ASSISTABILITY, not any event's
-- timing. A clean false = degraded (hide, never render the full-set parse);
-- unreadable answers fail OPEN (the historical self-exemption -- never
-- retry-loop against secrecy).
local pabDegraded = false
local pabSettleTicker
local function PabAssistProbe()
    local probe = UnitUsingVehicle or UnitInVehicle
    if probe("player") then return false end
    local ok, canSelf = pcall(UnitCanAssist, "player", "player")
    if ok and not (issecretvalue and issecretvalue(canSelf)) and canSelf == false then
        return false
    end
    return true
end

local function ApplyVehicleHidden(hidden)
    -- One suppression state, two causes: a vehicle ride and a probe-degraded
    -- window (cinematic / faction flip) hide the same parents -- degraded
    -- filter output must never render, exactly like the RF assist gate.
    hidden = hidden or pabDegraded
    -- The suppression itself lands on alpha inside SetParentShownSafe; `want`
    -- below stays the durable render verdict, so a bar disabled mid-ride still
    -- hides for real and a reload that runs during the ride cannot un-suppress
    -- the parents behind our back.
    SetPabSuppressed(hidden)
    local s = PAB()
    -- Regen replay re-derives from the LIVE vehicle state, not the argument.
    local function recompute() ApplyVehicleHidden(vehicleHidden) end
    -- Master enable + Use Blizzard Buffs both stand the defaults down: a
    -- vehicle exit during the disabled "Later" window must not re-show them.
    if buffsParent then
        SetParentShownSafe("vehicle-buffs", buffsParent, (not s
            or (s.enabled == true and DefaultBuffsCfg(s).enabled ~= false
                and s.useBlizzardBuffs ~= true)), recompute)
    end
    if debuffsParent then
        SetParentShownSafe("vehicle-debuffs", debuffsParent, (not s
            or (s.enabled == true and DefaultDebuffsCfg(s).enabled ~= false
                and s.useBlizzardBuffs ~= true)), recompute)
    end
    -- Restore honors the FULL render verdict (master enable + bar toggle +
    -- editing-spec bucket applicability + per-spec disable): a vehicle exit
    -- must never re-show a parked bar's fully-populated grid. Orphan parents
    -- (bar gone after a delete/profile switch) stay hidden -- the old
    -- `not bar` show-fallback punched through every gate.
    for barId, parent in pairs(customBuffParents) do
        local bar, bk = ns.PAB_GetCustomBuffBar(barId)
        SetParentShownSafe("vehicle-cb-" .. barId, parent,
            bar ~= nil and ns.PAB_BarActive(bar, bk), recompute)
    end
    for barId, parent in pairs(customDebuffParents) do
        local bar, bk = ns.PAB_GetCustomDebuffBar(barId)
        SetParentShownSafe("vehicle-cd-" .. barId, parent,
            bar ~= nil and ns.PAB_BarActive(bar, bk), recompute)
    end
end
local function SetVehicleHidden(hidden)
    if vehicleHidden == hidden then return end
    vehicleHidden = hidden
    -- Lifting: the containers kept parsing behind alpha 0 (dimmed, not hidden,
    -- so their engine events stayed live) and the spell-ID filters are still
    -- degraded through the exit transition -- un-dimming on the raw event edge
    -- would paint the full-set parse. Hand the stand-down to the degraded lane
    -- instead: the same event arms it, and it un-dims and forces the clean
    -- re-parse in one execution. Both callers reach the lane immediately, and
    -- every lane exit clears the latch (ClearDegraded below).
    if not hidden then pabDegraded = true end
    ApplyVehicleHidden(hidden)
end

-- The latch is only ever meaningful while the recovery lane is live: every
-- early exit down there hands it back, or a stand-down set on a transition
-- outlives the thing that caused it and every later bar comes up dimmed.
-- Forward-declared at the top of this file (the enable path clears a
-- latch that was set while the module was off, where no lane runs at all).
function ClearDegraded()
    if not pabDegraded then return end
    pabDegraded = false
    ApplyVehicleHidden(vehicleHidden)
end

local cineFixPending = false
local function ReapplyAllAfterCinematic()
    if cineFixPending then return end
    -- Custom containers count as live consumers too: under Use Blizzard
    -- Buffs the default containers never exist, but custom bars still need
    -- the filter-degradation repair.
    if not (buffsContainer or debuffsContainer
        or next(customBuffContainers) or next(customDebuffContainers)) then
        ClearDegraded()
        return
    end
    cineFixPending = true
    C_Timer.After(0, function()
        cineFixPending = false
        -- Master-disabled (awaiting reload): nothing to repair, and the
        -- re-drives below must not touch parked frames.
        local sM = PAB()
        if not sM or sM.enabled ~= true then
            ClearDegraded()
            return
        end
        -- Suppressed ride: a re-drive is pointless -- the bars are dimmed and
        -- the exit edge re-drives for real. UNIT_FACTION fires on the boarding
        -- transition and funnels straight here, so this is the common path.
        -- Re-assert and stop.
        if vehicleHidden then
            ApplyVehicleHidden(true)
            return
        end
        -- Probe before acting (the RF regain model): a re-drive that lands
        -- while the player is STILL non-assistable re-bakes the degraded
        -- full-set parse, and if that was the last UNIT_FACTION edge nothing
        -- ever repairs it (field: full buff set stuck after cinematics).
        -- Degraded at this tick: stand the parents down and wait. No event
        -- marks "assistability restored" when the restore lags the event, so a
        -- settle watcher exists ONLY while degraded and self-cancels on the
        -- first clean probe. It deliberately never gives up: the stand-down is
        -- alpha-only now, so nothing else re-shows the bars, and a watcher that
        -- stopped early would leave them invisible for the rest of the session.
        -- Two C calls per quarter-second, and only while degraded.
        if not PabAssistProbe() then
            if not pabDegraded then
                pabDegraded = true
                ApplyVehicleHidden(vehicleHidden)
            end
            if not pabSettleTicker then
                pabSettleTicker = C_Timer.NewTicker(0.25, function()
                    if PabAssistProbe() then
                        pabSettleTicker:Cancel()
                        pabSettleTicker = nil
                        ReapplyAllAfterCinematic()
                    end
                end)
            end
            return
        end
        if pabSettleTicker then pabSettleTicker:Cancel(); pabSettleTicker = nil end
        if pabDegraded then
            -- Verified regain: un-dim here and force the re-parse below in the
            -- same execution, so no frame paints the stand-down's stale content.
            pabDegraded = false
            ApplyVehicleHidden(vehicleHidden)
        end
        ApplyLiveConfig(true)
        ApplyLiveConfig(false)
        -- Every custom bar, editing-spec buckets included: the recovery
        -- exists to repair engine-degraded candidate filters, and an active
        -- bucket bar degrades exactly like a legacy one.
        ReloadAllCustomBars()
        -- Force the re-parse outright. The config re-drive above cannot: a
        -- live group's candidate payload does not retake (see CandFP), and the
        -- engine caches membership per aura instance -- UNIT_AURA re-parses only
        -- what changed, so a spell-ID group parsed while the player was
        -- non-assistable keeps serving the full buff set until something marks a
        -- full rebuild. UpdateAllAuras is that lever (the same one the RF assist
        -- regain, UF player lane and CDM FakeActive use); the vehicle path only
        -- got it for free through the parents' Hide/Show. Bounded to this
        -- coalesced edge: one full parse per live container per cinematic edge.
        if buffsContainer then buffsContainer:UpdateAllAuras() end
        if debuffsContainer then debuffsContainer:UpdateAllAuras() end
        for _, c in pairs(customBuffContainers) do c:UpdateAllAuras() end
        for _, c in pairs(customDebuffContainers) do c:UpdateAllAuras() end
    end)
end

-- Registers nothing itself: CreateBars calls ns.PAB_ArmRecovery() once it has
-- confirmed the module is enabled -- login build and live enable both.
local initFrame = CreateFrame("Frame")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if vehicleHidden then
            local probe = UnitUsingVehicle or UnitInVehicle
            if not probe("player") then
                SetVehicleHidden(false)
                ReapplyAllAfterCinematic()
            end
        end
        -- Editing-spec buckets: the login reload can run before
        -- GetSpecialization() answers, parking every bucket bar until the
        -- next spec change. Re-drive once per world entry (gated = one
        -- table read for profiles without buckets; idempotent otherwise).
        local s = PAB()
        if s and s.pabSpecBars then ReloadAllCustomBars() end
        return
    end
    if event == "UNIT_ENTERING_VEHICLE" or event == "UNIT_ENTERED_VEHICLE" then
        SetVehicleHidden(true)
        return
    end
    if event == "UNIT_EXITED_VEHICLE" then
        SetVehicleHidden(false)
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Editing-spec bucket bars activate/park with the spec. Gated to
        -- profiles that actually built buckets -- everyone else pays one
        -- table read per spec change. Unlock elements re-sync through the
        -- per-bar reload wrappers.
        local s = PAB()
        if s and s.pabSpecBars then
            ReloadAllCustomBars()
        end
        return
    end
    ReapplyAllAfterCinematic()
end)

-- Called by CreateBars once it has passed its own enabled check -- the only
-- point where "PAB is actually running" is known to be true. Idempotent:
-- CreateBars can run more than once per session (login build, live enable).
local recoveryArmed = false
function ns.PAB_ArmRecovery()
    if recoveryArmed then return end
    recoveryArmed = true
    initFrame:RegisterEvent("CINEMATIC_STOP")
    -- Player-only registration: cinematics fire UNIT_FACTION for every unit;
    -- the player edge is the one that degrades these containers' filters.
    -- Also covers non-cinematic faction flips (Pandaren faction choice) --
    -- rare, and the re-drive is cheap.
    initFrame:RegisterUnitEvent("UNIT_FACTION", "player")
    -- Vehicles are the third trigger of the same class: boarding drops the
    -- player's assistability for the whole ride. The bars SUPPRESS for the
    -- duration (SetVehicleHidden) and the exit edge re-drives -- same
    -- trigger set as the RF assist gate and the UF player lane.
    initFrame:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
    initFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    initFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    -- Safety net only: an exit that never fires EXITED (teleport out of a
    -- vehicle). Zero work on ordinary loading screens.
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Editing-spec buckets: bucket bars follow the player's spec (handler
    -- early-returns for profiles without buckets).
    initFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
end

I.broken = false
