if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Lifecycle.lua
--
--  OnInitialize, OnEnable and the Party Mode spin.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local UnitExists            = UnitExists
local InCombatLockdown      = InCombatLockdown
local C_Timer               = C_Timer

local allButtons, defaults, ERF, eventFrame = I.allButtons, I.defaults, I.ERF, I.eventFrame
local InitHealthBarTextures, IsPowerBarEnabled = I.InitHealthBarTextures, I.IsPowerBarEnabled
local PixelSnap, separatedHdrs, unitTrackers = I.PixelSnap, I.separatedHdrs, I.unitTrackers
local StyleButton, RebuildUnitMap = I.StyleButton, I.RebuildUnitMap
local UpdateAllButtons, CreateHeaders = I.UpdateAllButtons, I.CreateHeaders
local LayoutGroups, ReloadFrames = I.LayoutGroups, I.ReloadFrames
local UpdateVisibility, OnEvent = I.UpdateVisibility, I.OnEvent
local RegisterWithUnlockMode, SetDB, SetPP = I.RegisterWithUnlockMode, I.SetDB, I.SetPP
local SetInCombat = I.SetInCombat

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local PP
I.PPSetters[#I.PPSetters + 1] = function(v) PP = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end
local framesVisible = false
I.framesVisibleSetters[#I.framesVisibleSetters + 1] = function(v) framesVisible = v end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (ADDON_LOADED - SavedVariables available)
-------------------------------------------------------------------------------
function ERF:OnInitialize()
    -- Detect first install before DB creation overwrites the raw SV
    local rawDB = EllesmereUIRaidFramesDB
    local isFirstInstall = not rawDB or not rawDB.profiles
        or (rawDB.profiles and not next(rawDB.profiles))

    self.db = EllesmereUI.Lite.NewDB("EllesmereUIRaidFramesDB", defaults, true)
    SetDB(self.db)
    ns.db = db
    ns._PreviewBind(db, PP, containerFrame)

    -- Migration: the legacy "Threat Borders" toggle (showThreat) became the
    -- "threatBorderSize" slider. Preserve intent for users who turned it off
    -- (false -> 0); everyone else falls through to the default size. Run for
    -- every saved profile so switching profiles mid-session keeps the choice.
    if EllesmereUIDB and EllesmereUIDB.profiles then
        for _, pdata in pairs(EllesmereUIDB.profiles) do
            local pf = pdata.addons and pdata.addons.EllesmereUIRaidFrames
            if pf then
                if pf.showThreat ~= nil then
                    if pf.showThreat == false then pf.threatBorderSize = 0 end
                    pf.showThreat = nil
                end
                if pf.party_showThreat ~= nil then
                    if pf.party_showThreat == false then pf.party_threatBorderSize = 0 end
                    pf.party_showThreat = nil
                end
            end
        end
    end

    -- Mark if we need to snapshot Blizzard's raid frame position
    local sv = self.db.sv
    self._needsCapture = not sv._capturedOnce_RF

    InitHealthBarTextures()
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (PLAYER_LOGIN - game data available)
-------------------------------------------------------------------------------
function ERF:OnEnable()
    SetPP(EllesmereUI.PanelPP or EllesmereUI.PP)
    ns._PreviewBind(db, PP, containerFrame)

    -- First-install default position: left edge of frame at 200px from screen
    -- left, vertically centered.
    if self._needsCapture then
        db.profile.unlockPos = {
            point = "LEFT", relPoint = "LEFT",
            x = 200, y = 0,
        }
        if not db.profile.partyUnlockPos then
            db.profile.partyUnlockPos = {
                point = "LEFT", relPoint = "LEFT",
                x = 400, y = 0,
            }
        end
        self.db.sv._capturedOnce_RF = true
        self._needsCapture = false
    end

    -- Stock styles: a profile that arrives already switched (an import, an
    -- older build) gets the style's first-visit defaults once, before the
    -- proxies below materialize them.
    if ns.RF_Stock() then ns.RF_SeedStock(db.profile, ns.RF_Style()) end
    ns.RF_MigrateSmRaidBar(db.profile)
    ns._FrameSortRegister()

    -- Inherit the Absorbs section's party-sync state from Health Bar for
    -- profiles saved before the section split (must precede any proxy reads).
    ns._NormalizePartySyncSections()

    -- Rebase pre-top-left-anchor tier offsets (marker travels in the data)
    ns._NormalizeTierOffsetAnchors()

    -- Initialize click-cast engine (before CreateHeaders so ClickCastFrames hook is active)
    if ns.CC_Init then ns.CC_Init() end

    -- Set party strata before creating its secure header.
    if ns.ApplyFrameStrata then ns.ApplyFrameStrata() end

    -- Create headers; buttons get window-phase secure styling only
    CreateHeaders()

    -- Initial reload minus the restyle loop (sets _activeSizeW/H from group
    -- size + tier overrides, lays out headers) -- the insecure styling bodies
    -- run in the deferred pass below
    ReloadFrames(true)

    -- Create party header (after CC_Init so click-cast registers)
    ns._CreatePartyHeader()

    -- Both containers show and hide through their visibility drivers from here
    -- on, registered in the login window so a /reload in combat has them too.
    -- Blizzard's PartyFrame goes down here too, so it can never stand in for
    -- ours (a group joined in combat).
    ns._RFSyncVisDrivers()
    ns._SuppressBlizzParty(true)

    -- Size + position party container from profile
    do
        local s = db.profile
        local pw, ph, pcs = ns.RF_PartyDims(s)
        ns._SizePartyContainer(PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
        local pos = s.partyUnlockPos
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
            and ns._partyContainerFrame:GetLeft()
        if pos and not anchored then
            ns._partyContainerFrame:ClearAllPoints()
            ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    -- Party layout minus the restyle loop (bodies deferred)
    ns.ReloadPartyFrames(true)

    -- Friendly Boss Frames: initial activation (raid-only boss1-5 frames)
    if ns.FB_Apply then ns.FB_Apply() end
    -- Extra Frames: initial activation (raid-only member duplicates)
    if ns.XF_Apply then ns.XF_Apply() end
    -- Pet frames: built and styled here, once (in the login window, so a combat /reload has them);
    -- the deferred reloads below find their style unchanged.
    ns.PF_Apply(true)

    -- DEFERRED LOGIN PASS, BUDGET-FRAGMENTED. Starts on the first frame
    -- after the loading screen (timers never fire during it). Everything
    -- here is combat-legal: the insecure styling bodies for every
    -- pre-spawned button (~80% of this module's login CPU), then the full
    -- reload passes, whose protected ops self-gate in combat and heal on the
    -- regen dirty-flag path. Order is load-bearing and preserved by C_Timer
    -- FIFO: BM lookup before the bodies (aura shell pools size from the
    -- indicator lists), bodies before the restyle loops.
    --
    -- WHY FRAGMENTED: each C_Timer callback is its own execution and so its
    -- own 12.1 script-watchdog budget -- but a budget is a fixed slice, and
    -- this pass's cost scales with button count x profile size. As ONE tick
    -- it exceeded its own budget on slower machines (field: watchdog kill
    -- inside _RefreshProxyModes at the TAIL of the tick -- the named line is
    -- just where the budget died, not the culprit). Now the styling loop
    -- self-limits with debugprofilestop and re-queues, and each reload pass
    -- runs as its own execution, so no single execution here scales with
    -- data size. Fast machines still finish styling in one tick; slow ones
    -- style progressively over a few frames instead of erroring. Buttons
    -- created between slices (roster spawns) are healed by the restyle-loop
    -- fallbacks and the 0.5s safety pass, same as the existing one-tick gap;
    -- UpdateButton's `not d.styled` guard covers event dispatch in the gap.
    C_Timer.After(0, function()
        -- Invalidate the frame's paint stamps so the deferred repaint can
        -- never be deduped away (mirrors _ERF_RefreshAll). Re-bumped in each
        -- later stage: every stage is a new frame with its own stamps.
        ns._paintGen = (ns._paintGen or 0) + 1
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end
        local queue = {}
        for _, btn in ipairs(allButtons) do queue[#queue + 1] = btn end
        for _, btn in ipairs(ns._partyAllButtons) do queue[#queue + 1] = btn end
        local idx = 1
        local function drain()
            local deadline = debugprofilestop() + 8
            while idx <= #queue do
                StyleButton(queue[idx])
                idx = idx + 1
                if idx <= #queue and debugprofilestop() > deadline then
                    C_Timer.After(0, drain)
                    return
                end
            end
            -- Styling complete: each remaining pass gets a whole budget.
            C_Timer.After(0, function()
                ns._paintGen = (ns._paintGen or 0) + 1
                ReloadFrames()
            end)
            C_Timer.After(0, function()
                ns._paintGen = (ns._paintGen or 0) + 1
                ns.ReloadPartyFrames()
            end)
            C_Timer.After(0, RegisterWithUnlockMode)
        end
        drain()
    end)

    -- Party container size + saved position. The container is implicitly
    -- protected (the secure party header is parented to it), so under combat
    -- lockdown the write is deferred to the PLAYER_REGEN_ENABLED flush instead
    -- of tripping ADDON_ACTION_BLOCKED: _ERF_RefreshAll is a public entry point
    -- (profiles, spec overrides, third-party installers) and not every caller
    -- is out of combat.
    function ns._ApplyPartyContainerGeometry()
        local c = ns._partyContainerFrame
        if not c or not ns.db then return end
        if InCombatLockdown() then ns._partyGeomDirtyInCombat = true; return end
        local s = ns.db.profile
        local pw, ph, pcs = ns.RF_PartyDims(s)
        ns._SizePartyContainer(PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
        local pos = s.partyUnlockPos
        -- Skip the saved-pos SetPoint when element-anchored with resolved
        -- geometry: the unlock anchor system owns the position.
        local anchored = EllesmereUI.IsUnlockAnchored
            and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
            and c:GetLeft()
        if pos and not anchored then
            c:ClearAllPoints()
            c:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end

    -- Profile-swap refresh: EllesmereUI.RefreshAllAddons calls this on a profile
    -- change so raid + party frames re-read the (now-swapped) profile live,
    -- instead of staying stale until /reload. Mirrors the reload sequence above.
    _G._ERF_RefreshAll = function()
        if not ns.db then return end
        -- Profile/view swaps break the same-frame paint-stamp window: the
        -- repaint of the new profile must never dedupe against a paint made
        -- under the old one earlier this frame.
        ns._paintGen = (ns._paintGen or 0) + 1
        -- Absorbs sync-state inheritance for swapped/imported profiles saved
        -- before the Absorbs section split (must precede party proxy reads).
        ns._NormalizePartySyncSections()
        -- Rebase old-scheme tier offsets on swapped/imported profiles too
        -- (the marker lives inside raidSizeOverrides, so this self-detects).
        ns._NormalizeTierOffsetAnchors()
        -- Rebuild the buff-manager spell lookup for the new profile's per-spec
        -- indicators (and the Simple Setup whitelist) before frames re-render.
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        -- Apply strata first; reload restores child frame levels.
        if ns.ApplyFrameStrata then ns.ApplyFrameStrata() end
        -- Raid frames: restyle + relayout + reposition from the new profile.
        if ns.ReloadFrames then ns.ReloadFrames() end
        -- Party container size + position (combat-deferred inside), then the party buttons.
        ns._ApplyPartyContainerGeometry()
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
        -- Re-sync per-unit UNIT_POWER_UPDATE registration to the new profile's
        -- power role filters, so units that GAIN power across the swap get live
        -- updates instead of a frozen one-shot snapshot (rage/runic power would
        -- otherwise sit empty out of combat). Event registration is combat-safe.
        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
        -- Re-apply click-cast / hovercast bindings for the new profile.
        if ns.CC_ApplyBindings then ns.CC_ApplyBindings() end
        -- Friendly Boss Frames and Extra Frames re-read the swapped profile (the pet frames did at
        -- the tails of the raid and party reloads above).
        if ns.FB_Apply then ns.FB_Apply() end
        if ns.XF_Apply then ns.XF_Apply() end
        -- Real-preview effective overlay: RunRefreshers reaches here synchronously from
        -- every view/spec/conditional transition, so the preview's value source is
        -- corrected in the SAME frame -- the shared tickers never render a stale
        -- overlay across a flip. Near-zero cost when the overlay gate is inactive.
        if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
        -- Solo-visibility recompute: override/profile transitions can flip showWhenSolo
        -- (e.g. a healer solo-frames spec override), and the DB restore alone never
        -- re-derives container visibility or the secure showSolo header attributes, so
        -- frames kept the state of whichever override page was viewed last. Both
        -- recomputes no-op via change guards when nothing moved. OOC-gated: override
        -- refreshers are REGEN-stashed, but direct callers may not be, and secure
        -- attribute writes are combat-blocked; a combat-time skip self-heals on the
        -- existing combat-exit visibility pass.
        if not InCombatLockdown() then
            if ns.UpdateVisibility then ns.UpdateVisibility() end
            if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
        end
    end

    -- Buff Manager LAYER swap refresh (spec-override BM forks): re-derives
    -- the spell lookup, then re-drives the aura containers that render BM.
    -- Deliberately BM-only: never calls ReloadFrames, so profile swaps
    -- (_ERF_RefreshAll above) are not doubled. Combat-safe: BM code only
    -- touches our own pooled child frames, never the secure buttons.
    -- noPage: skip the options-page repaint when the caller IS a page build.
    _G._ERF_BMRefresh = function(noPage)
        if not ns.db then return end
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(ns.db) end
        local pv = ns._bmPreviewFrame
        if pv and pv._health and ns.BM_ApplyPreviewIndicators then
            ns.BM_ApplyPreviewIndicators(pv, 1, ns.db.profile)
        end
        -- Aura containers own BM rendering on 12.1: re-drive them so a
        -- swapped-in override fork repaints (fingerprint guards make this
        -- near-free when nothing actually changed).
        if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
        -- Open BM options page: force a rebuild so its widgets re-bind to
        -- the (identity-preserved, content-swapped) profile tables.
        if not noPage and ns._bmRoot and EllesmereUI and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage(true)
        end
    end


    -- Expose EUI party frames to external trackers that support a provider
    -- API (e.g. MiniAuras). No-op when none is installed.
    ns._RegisterTrackerProviders()

    -- Event frame: register global (non-unit) events
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("READY_CHECK")
    eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    eventFrame:RegisterEvent("INCOMING_SUMMON_CHANGED")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE")
    eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("UNIT_PHASE")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")

    -- Heal prediction feeds ONLY the incoming-heal display, never absorbs.
    -- Any view rendering it keeps the event; the default (all off) never
    -- registers it at all. Materialized proxies = plain table reads.
    function ns._RFPredWanted()
        return (ns._scaledProfile.healPrediction
            or ns._scaledPartyProxy.healPrediction
            or ns._scaledExtraProxy.healPrediction) and true or false
    end
    -- Idempotent toggle sync, called from the _BumpAbsorbGen options funnel.
    function ns._RFSyncPredRegistration()
        local want = ns._RFPredWanted()
        for unit, tracker in pairs(unitTrackers) do
            if want then
                tracker:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
            else
                tracker:UnregisterEvent("UNIT_HEAL_PREDICTION")
            end
        end
    end

    -- Per-unit event trackers: one frame per unit.
    -- RegisterUnitEvent only accepts 1-2 units per call, so each unit gets
    -- its own frame. Units that don't exist simply don't fire (zero cost).
    local UNIT_EVENTS_BASE = {
        -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
        -- repaints prediction from health/absorb events only). The one gap --
        -- an aura-granted shield expiring on its TIMER on an unhit, topped
        -- unit (field report: VDH Infernal Strike) fires NO event at all --
        -- is covered by the armed-members belt next to the absorb coalescer.
        -- UNIT_HEAL_PREDICTION absent: it feeds ONLY the incoming-heal
        -- display (never absorbs) and fires on every healer cast at every
        -- target -- registered conditionally in MakeUnitTracker, synced by
        -- ns._RFSyncPredRegistration on options writes.
        "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_NAME_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
    }
    local function MakeUnitTracker(unit)
        -- Shell-pool adoption: the initial roster build runs from OnEnable
        -- (parent lifecycle context), which would bill every tracker's
        -- event tree to the parent addon for the whole session.
        local f = ns.TakeShell()
        for _, ev in ipairs(UNIT_EVENTS_BASE) do
            f:RegisterUnitEvent(ev, unit)
        end
        if ns._RFPredWanted() then
            f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
        end
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
        f:SetScript("OnEvent", OnEvent)
        unitTrackers[unit] = f
    end
    MakeUnitTracker("player")
    for i = 1, 4 do MakeUnitTracker("party" .. i) end
    for i = 1, 40 do MakeUnitTracker("raid" .. i) end
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Level Text's UNIT_LEVEL: registered on every tracker only while a view shows the
    -- level. Called from _RefreshProxyModes (every settings write, reload and profile
    -- swap); the stamp keeps the 45-tracker walk to real flips.
    local lvlRegistered = false
    function ns._RFSyncLevelRegistration()
        local want = ns._RFLevelWanted()
        if want == lvlRegistered then return end
        lvlRegistered = want
        for unit, tracker in pairs(unitTrackers) do
            if want then
                tracker:RegisterUnitEvent("UNIT_LEVEL", unit)
            else
                tracker:UnregisterEvent("UNIT_LEVEL")
            end
        end
    end
    ns._RFSyncLevelRegistration()

    -- UNIT_FLAGS is opt-in: only registered while the combat icon is enabled.
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end

    -- Dynamically register/unregister UNIT_POWER_UPDATE per unit based on
    -- role and power display settings. Called after roster changes and
    -- when the user changes power bar role filters. The trackers are shared
    -- by raid AND party frames: player/party1-4 tokens also drive the party
    -- buttons, whose Power Bar section can be unsynced from raid -- those
    -- must consult the party proxy too, or raid-off/party-on would strip
    -- their events and freeze the party power bars mid-combat.
    local function UpdatePowerEventRegistration()
        local rs = db.profile
        local ps = ns._partyProxy
        local function wantsPower(s, role)
            return (role == "HEALER" and s.powerShowForHealer)
                or (role == "TANK" and s.powerShowForTank)
                or (role == "DAMAGER" and s.powerShowForDPS)
                or (role == "NONE" and s.powerShowForDPS)
        end
        -- Healer Mana Display rides these registrations: healers keep their
        -- power events while its mode matches the current group type,
        -- whatever the power bar settings.
        local hmOn = ns._HMActive and ns._HMActive()
        for unit, tracker in pairs(unitTrackers) do
            local wantPower = false
            if UnitExists(unit) then
                local role = ns._ResolvePowerRole(unit)
                wantPower = (IsPowerBarEnabled(rs) and wantsPower(rs, role))
                    or (hmOn and role == "HEALER")
                -- player/party tokens always count as party-displayable; the
                -- routing-map check additionally covers arena, where the party
                -- header binds raid1-5.
                if not wantPower and (unit == "player" or unit:match("^party%d$")
                        or (ns._partyUnitToButton and ns._partyUnitToButton[unit])) then
                    if ns.RF_PartyKit() then
                        -- Party Frames kit: the stock mana bar always shows
                        -- (while the party frames are shown; the hide edge
                        -- re-runs this through RF_KitPortraitEvents).
                        wantPower = ns._partyFramesVisible and true or false
                    elseif IsPowerBarEnabled(ps) then
                        wantPower = wantsPower(ps, role)
                    end
                end
            end
            if wantPower then
                tracker:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
                tracker:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
            else
                tracker:UnregisterEvent("UNIT_POWER_UPDATE")
                tracker:UnregisterEvent("UNIT_DISPLAYPOWER")
            end
        end
        -- Same cadence as the registrations (roster/roles/settings changes).
        if ns.HM_Rebuild then ns.HM_Rebuild() end
    end
    ns.UpdatePowerEventRegistration = UpdatePowerEventRegistration

    -- Initial update after a short delay
    C_Timer.After(0.5, function()
        -- A /reload in combat never sees PLAYER_REGEN_DISABLED: take the combat
        -- state from the lockdown, and let the combat edge set the visibility
        -- flags the two passes below skip in combat.
        if InCombatLockdown() then
            SetInCombat(true)
            ns._RFCombatVisEdge()
            -- Members assigned while the flag was still down (the first half
            -- second) were kept out of the map; the raid branch below rebuilds too.
            if ns._partyFramesVisible then ns._RebuildPartyUnitMap() end
        end
        UpdateVisibility()
        ns._UpdatePartyVisibility()
        if framesVisible then
            RebuildUnitMap()
            LayoutGroups()
            -- Re-derive the growth-corner anchor: this can be the first
            -- sized pass when roster data arrives late, and its SetSize
            -- must not leave the container on a stale anchor.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            UpdateAllButtons()
        end
        if ns._partyFramesVisible then
            ns._LayoutPartyFrames()
        end
    end)

    -- Nickname integrations. When Northern Sky Raid Tools (NSAPI) or Timeline
    -- Reminders (TimelineReminders) is present, raid + party names use their
    -- nicknames (see ResolveDisplayName). Callbacks refresh names instantly
    -- without a /reload when nickname data changes or the user flips the addon's
    -- dedicated EllesmereUI nicknames checkbox. Both addons may load after us, so
    -- registration retries on PLAYER_LOGIN / PLAYER_ENTERING_WORLD until it sticks.
    -- All registrations are dot calls, NOT colon: the first argument is the unique
    -- registrant key (CallbackHandler keys registrations by it). A colon call would
    -- pass the API table itself as the key and collide with other addons doing the same.
    local function RegisterNSRTNicknames()
        if ns._nsrtNickHooked then return true end
        if NSAPI and NSAPI.RegisterCallback then
            local function onChange() if ns.RefreshAllNames then ns.RefreshAllNames() end end
            NSAPI.RegisterCallback("EllesmereUI", "NSRT_NICKNAME_UPDATED", onChange)
            NSAPI.RegisterCallback("EllesmereUI", "EUI_NICKNAME_TOGGLE", onChange)
            ns._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterMethodInternalNicknames()
        if ns._methodInternalSurfaceNickHooked then return end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback("SurfaceNicknamesChanged", function()
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end, "EllesmereUIRaidFrames")
            ns._methodInternalSurfaceNickHooked = true
        end
    end
    local function RegisterTRNicknames()
        if ns._trNickHooked then return true end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            -- CallbackHandler passes the event name as the first callback argument.
            -- Toggle fires for every addon checkbox in TR, so filter on ours.
            TR.RegisterCallback("EllesmereUI", "TimelineReminders_NicknameToggle", function(_, _, addOnName)
                if addOnName == ns.NICK_ADDON and ns.RefreshAllNames then ns.RefreshAllNames() end
            end)
            TR.RegisterCallback("EllesmereUI", "TimelineReminders_NicknameUpdate", function()
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end)
            ns._trNickHooked = true
            return true
        end
        return false
    end
    local function RegisterRGALIASNicknames()
        if ns._rgaliasNickHooked then return true end
        local RGA = _G.RG_ALIAS
        if RGA and RGA.RegisterCallback and _G.RG_UnitName then
            -- ns._rgaNick gates the ResolveDisplayName consult. The settings
            -- shape is nil-guarded and only read here and in callbacks, never
            -- per name resolve; a fresh RGA install with no settings table
            -- yet simply reads as module-off.
            local function SyncRGAFlag()
                local s = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
                ns._rgaNick = (s and s["ellesmereui"]) and true or nil
                if ns.RefreshAllNames then ns.RefreshAllNames() end
            end
            -- pcall: RGA owns its RegisterCallback signature; a mismatch or
            -- future change must not error our OnEnable. If registration
            -- fails, the flag is still seeded once below -- module toggles
            -- then need a /reload to be noticed (degraded, never broken).
            pcall(RGA.RegisterCallback, "DbUpdated", SyncRGAFlag)
            pcall(RGA.RegisterCallback, "ModuleEnabled", function(event, moduleName)
                if moduleName == "ellesmereui" then SyncRGAFlag() end
            end)
            pcall(RGA.RegisterCallback, "ModuleDisabled", function(event, moduleName)
                if moduleName == "ellesmereui" then SyncRGAFlag() end
            end)
            local s = RG_ALTS_SETTINGS and RG_ALTS_SETTINGS.settings
            ns._rgaNick = (s and s["ellesmereui"]) and true or nil
            ns._rgaliasNickHooked = true
            return true
        end
        return false
    end

    local nsrtHooked = RegisterNSRTNicknames()
    local trHooked = RegisterTRNicknames()
    local rgaliasHooked = RegisterRGALIASNicknames()
    if not (nsrtHooked and trHooked and rgaliasHooked) then
        local nickFrame = ns.TakeShell()
        nickFrame:RegisterEvent("PLAYER_LOGIN")
        nickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        nickFrame:SetScript("OnEvent", function(self, event)
            local a = RegisterNSRTNicknames()
            local b = RegisterTRNicknames()
            local c = RegisterRGALIASNicknames()
            -- Anything not loaded by first PLAYER_ENTERING_WORLD is not coming.
            if (a and b and c) or event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternalNicknames)

    -- Init options module if it loaded before us
    if ns._InitEUIModule then
        C_Timer.After(0, ns._InitEUIModule)
    end
end

-- Slash command registered in EUI_RaidFrames_Options.lua

-------------------------------------------------------------------------------
--  Party Mode: spinning party and raid frames (EllesmereUI.PartySpin_Create).
--  Each set's shown buttons orbit the centre of its container, so the 5-slot
--  party box turns around its third frame. homeInCombat puts the secure
--  buttons back on the header layout for each fight.
-------------------------------------------------------------------------------
do
    -- A header's shown buttons, in child order.
    local function AddShown(hdr, list)
        if not (hdr and hdr:IsVisible()) then return end
        local i, b = 1, hdr:GetAttribute("child1")
        while b do
            if b:IsVisible() then list[#list + 1] = b end
            i = i + 1
            b = hdr:GetAttribute("child" .. i)
        end
    end

    local partyList = {}
    local partyGroup = { frames = partyList }
    local partyGroups = {}
    EllesmereUI.PartySpin_Create({
        target = "partyFrames",
        homeInCombat = true,
        collect = function()
            wipe(partyList); wipe(partyGroups)
            local box = ns._partyContainerFrame
            if box and box:IsVisible() then
                AddShown(ns._partyHeader, partyList)
                local sb = ns._partySelfButton
                if sb and sb:IsVisible() then partyList[#partyList + 1] = sb end
                partyGroup.pivot = box
                partyGroups[1] = partyGroup
            end
            return partyGroups
        end,
    })

    local raidList = {}
    local raidGroup = { frames = raidList }
    local raidGroups = {}
    EllesmereUI.PartySpin_Create({
        target = "raidFrames",
        homeInCombat = true,
        collect = function()
            wipe(raidList); wipe(raidGroups)
            if containerFrame and containerFrame:IsVisible() then
                for g = 1, 8 do AddShown(separatedHdrs[g], raidList) end
                AddShown(ns._flatHeader, raidList)
                raidGroup.pivot = containerFrame
                raidGroups[1] = raidGroup
            end
            return raidGroups
        end,
    })
end

I.broken = false
