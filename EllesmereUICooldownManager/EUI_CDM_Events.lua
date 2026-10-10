if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Events.lua
--
--  The event frame for run-time maintenance and the slash commands.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME, _bonusScanSeen, _cdmViewerNames = I.ECME, I._bonusScanSeen, I._cdmViewerNames
local _ecmeFC, _maxChargeCount = I._ecmeFC, I._maxChargeCount
local _multiChargeSpells, CheckSpecChange = I._multiChargeSpells, I.CheckSpecChange
local OnProcGlowEvent = I.OnProcGlowEvent
local BLIZZ_CDM_FRAMES_SECONDARY = I.BLIZZ_CDM_FRAMES_SECONDARY
local HideBlizzardCDM, RestoreBlizzardBuffFrame = I.HideBlizzardCDM, I.RestoreBlizzardBuffFrame
local BuildAllCDMBars, UpdateCDMKeybinds = I.BuildAllCDMBars, I.UpdateCDMKeybinds
local _CDMApplyVisibility, RequestUpdate = I._CDMApplyVisibility, I.RequestUpdate
local SetInCombat = I.SetInCombat
local OpenBlizzardCDMTab = I.OpenBlizzardCDMTab

local _keybindDebounceTimer = nil   -- cancellable timer for debounced keybind updates

-------------------------------------------------------------------------------
--  Event-Driven Runtime Maintenance
--
--  This frame owns the non-tick triggers: login/world transitions, spec swaps,
--  talent changes, roster updates, binding changes, proc-glow signals, and
--  combat/visibility state. Most heavy work is deferred into rebuild helpers
--  rather than performed inline in the event callback.
-------------------------------------------------------------------------------
-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
-- Live override flips (proc-based hero-talent transforms): resolution memos
-- derived from override state go stale the moment this fires.
eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
-- Only ever acted on for an override id we armed ourselves; Blizzard's own base-spell
-- registrations dispatch here too and fall straight through.
eventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
-- Hero talent / loadout change events
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
-- Viewer data landing after our init: the injection phase keys on live
-- Blizzard frames (frames as truth), so a build that ran before the viewer
-- populated may have injected a custom racial frame the native viewer now
-- covers. One debounced rebuild re-evaluates; fires rarely (login, and
-- Blizzard-side data refreshes).
eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
-- Cinematic/cutscene end: Blizzard restores hidden frames, so re-hide ours
eventFrame:RegisterEvent("CINEMATIC_STOP")
eventFrame:RegisterEvent("STOP_MOVIE")
-- Equipment changes: trinket/weapon swaps update trinket frames and reanchor
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Visibility option events: mounted, target, instance zone changes
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Resting: IsResting() has no dedicated poll, so without this the Resting
-- axis only re-evaluated when some unrelated event above happened to fire.
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
-- Party Mode axis: no game event; the core fires its own edge.
if EllesmereUI.RegisterVisEdge then
    EllesmereUI.RegisterVisEdge(function() _CDMApplyVisibility() end)
end
-- Vehicle edges for the In Vehicle axis (player-filtered; same reasoning).
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
-- Dragonriding visibility modes: capability edge (mount/dismount/zone) plus
-- the airborne edge (takeoff/landing while staying mounted; probed at load
-- in EllesmereUI_Visibility.lua -- absent = the checklist items lock).
eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
if EllesmereUI._hasGlidingEvent then
    eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
end
-- Druid travel/flight/aquatic form needs an explicit re-check for the
-- visHideMounted option. PLAYER_MOUNT_DISPLAY_CHANGED only fires for real
-- mounts, and the viewer hooks rebuild icon content on shapeshift but
-- don't re-run bar-level visibility. Only register for druids -- non-druid
-- classes have no mount-like shapeshift forms, and druid combat shifts
-- (Bear/Cat) would otherwise trigger unnecessary visibility recomputes.
local _, _playerClassCDM = UnitClass("player")
if _playerClassCDM == "DRUID" then
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
end

-- Debounce token for talent-change rebuilds: rapid talent clicks collapse
-- into a single deferred rebuild rather than firing once per click.
local _talentRebuildToken = 0

local function ScheduleTalentRebuild()
    _talentRebuildToken = _talentRebuildToken + 1
    local token = _talentRebuildToken
    C_Timer.After(0.5, function()
        if token ~= _talentRebuildToken then return end  -- superseded
        -- Wipe per-spell caches that may reference stale override IDs or stale charge
        -- data from spells that changed with the talent swap. Also wipe the persisted
        -- DB entries so CacheMultiChargeSpell re-detects from live API rather than
        -- reading a stale false entry. Skip during combat: actual talent changes are
        -- combat-locked, so these events only fire mid-combat from hero talent procs
        -- (e.g. Celestial Infusion). Wiping here would clear charge data for all spells
        -- with no way to re-detect it until the next out-of-combat cache rebuild.
        if not InCombatLockdown() then
            wipe(_multiChargeSpells)
            wipe(_maxChargeCount)
            local db = ECME.db
            if db and db.sv and db.sv.multiChargeSpells then
                wipe(db.sv.multiChargeSpells)
            end
            -- Hidden Outside Form/Stance answers (a talent can change which
            -- forms a spell needs)
            if ns.CdmWipeFormCache then ns.CdmWipeFormCache() end
        end
        -- Rebuild the cdID route map against the new talent set. The stored
        -- assignedSpells is left untouched (it's pure user intent); the route map is
        -- the live source of truth for which frame renders on which bar. A full CDM
        -- rebuild + reanchor below picks up the new routing.
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        -- The placeholder icon bridge reads the spellbook, and a talent swap is
        -- exactly what changes which form a name resolves to.
        if ns.WipeCdmBookNameCache then ns.WipeCdmBookNameCache() end
        -- Clear cached viewer child info so the next tick re-reads from API
        -- (overrideSpellID may have changed with the new talent set)
        for _, vname in ipairs(_cdmViewerNames) do
            local vf = _G[vname]
            if vf and vf:GetNumChildren() > 0 then
                local children = { vf:GetChildren() }
                for ci = 1, #children do
                    local ch = children[ci]
                    if ch then
                        local chfc = _ecmeFC[ch]
                        if chfc then
                            chfc.resolvedSid = nil
                            chfc.baseSpellID = nil
                            chfc.overrideSid = nil
                            chfc.cachedCdID = nil
                            chfc.isChargeSpell = nil
                            chfc.maxCharges = nil
                        end
                    end
                end
            end
        end
        ns._cdmUnresolvedRetries = 0  -- fresh window; see FullCDMRebuild
        -- Rebuild keybind cache (talent swap may change action slot contents)
        UpdateCDMKeybinds()
        -- Invalidate TBB frame cache + spell caches, then reanchor so
        -- overlays re-evaluate against the new viewer pool state.
        if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
        if ns.MarkCDMSpellCacheDirty then ns.MarkCDMSpellCacheDirty() end
        if ns.QueueReanchor then ns.QueueReanchor() end
    end)
end

local _rosterRebuildPending = false
local function ScheduleRosterRebuild()
    -- Roster changes (promote, join, leave) don't change spells or bar
    -- routing. Only party frame anchoring needs a refresh. A full
    -- BuildAllCDMBars was causing massive single-frame CPU spikes.
    EllesmereUI.InvalidateFrameCache()
    if InCombatLockdown() then
        _rosterRebuildPending = true
        return
    end
    -- Lightweight: just reanchor bars that depend on party frames
    if ns.QueueReanchor then ns.QueueReanchor() end
end

-- Events that can move an ability to another action button (Bar Glows keyed per ability).
local BAR_REBIND_EVENTS = {
    ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true, SPELLS_CHANGED = true,
}

eventFrame:SetScript("OnEvent", function(_, event, unit, updateInfo, arg3)
    if not ECME.db then return end
    if ns._barGlowRebindOn and BAR_REBIND_EVENTS[event] then ns.QueueBarGlowRebind() end
    if event == "PLAYER_LOGOUT" then
        ns.SaveCachedBarSizes()
        return
    end
    if event == "SPELL_RANGE_CHECK_UPDATE" then
        ns.RepaintOverrideRange(unit)   -- payload is (spellID, isInRange, checksRange)
        return
    end
    if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        -- Bump-only: painting is driven by the cooldown/desat hooks, which re-resolve on their next fire. No repaint request from here.
        ns._cdmResGen = ns._cdmResGen + 1
        -- Except the range tint, which no hook re-resolves -- Blizzard's own check
        -- is armed on the base id and never re-polls for the override.
        -- Payload here is (baseSpellID, overrideSpellID).
        ns.ResyncCdmRange(unit, updateInfo)
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        return
    end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnProcGlowEvent(event, unit)  -- unit = spellID (first arg after event)
        return
    end
    if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED"
       or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR"
       or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
        -- A page/bonus/override/vehicle swap only changes which page is
        -- active, not the contents of the slots the stable scan reads -- so it
        -- cannot change the cache. Drop it, and with it the rebuild storm a
        -- stealthing rogue or shapeshifting druid used to cause. Only
        -- UPDATE_BINDINGS and ACTIONBAR_SLOT_CHANGED are real edits.
        --
        -- Exception, as insurance: let the first sighting of each bonus bar
        -- through, in case that form's slots (73-132) are only populated when
        -- the player first shifts into it rather than at login.
        if event ~= "UPDATE_BINDINGS" and event ~= "ACTIONBAR_SLOT_CHANGED"
           and ns.CDMStableKeybindsEnabled and ns.CDMStableKeybindsEnabled() then
            local firstSighting = false
            if event == "UPDATE_BONUS_ACTIONBAR" then
                local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
                if offset > 0 and not _bonusScanSeen[offset] then
                    _bonusScanSeen[offset] = true
                    firstSighting = true
                end
            end
            if not firstSighting then return end
        end
        -- Debounce: one-button rotation addons fire ACTIONBAR_SLOT_CHANGED on every GCD. Cancel the previous timer so rapid-fire events coalesce into a single update 0.5s after the last event.
        if _keybindDebounceTimer then _keybindDebounceTimer:Cancel() end
        _keybindDebounceTimer = C_Timer.NewTimer(0.5, function()
            _keybindDebounceTimer = nil
            UpdateCDMKeybinds()
        end)
        return
    end
    if event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        -- Native viewer data arrived (usually after login init), or a server
        -- hotfix rewrote the cooldown tables mid-session (the viewer then
        -- releases and re-acquires its whole item pool, which the CD/utility
        -- hooks deliberately do not follow): re-evaluate the
        -- frames-as-truth injection decisions against the now-live frame set.
        -- Rides the same debounced rebuild as talent changes; the reanchor sweep
        -- hides any injected racial frame the native viewer now covers. The spell
        -- picker's learned-set cache refreshes too (category sets just changed),
        -- and the reseed session stamps clear so base-bar materialization re-runs
        -- against the COMPLETE icon set (an init-time reseed may have seen a
        -- partial viewer; the racial-family guard keeps the re-run from minting
        -- a second racial slot).
        if ns.MarkCDMSpellCacheDirty then ns.MarkCDMSpellCacheDirty() end
        if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
        ScheduleTalentRebuild()
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_PVP_TALENT_UPDATE" then
        -- Hero talent, loadout, or PvP talent context change -- debounced rebuild. PvP talents
        -- (de)activating on arena enter/exit makes Blizzard re-evaluate the viewer's tracked
        -- cooldown set; without a rebuild the new pool frames are never re-claimed and the
        -- unclaimed-frame cleanup blanks them (arena-exit empty-CDM bug). The spell set may have changed: let the post-rebuild reanchor re-run the automatic base-bar materialization for this spec.
        if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
        -- Drop the spellbook name map NOW, not only in the debounced rebuild. It answers "which
        -- form does the player have", which is exactly what just changed, and anything repainting
        -- inside the debounce window would otherwise resolve against the pre-swap book. The rebuild
        -- wipes it again, which still matters: this early rebuild can read a book the client has not finished updating, and that second wipe corrects it.
        if ns.WipeCdmBookNameCache then ns.WipeCdmBookNameCache() end
        -- Talent Conditions read node ranks from a cache; the rebuild's reanchor re-evaluates them.
        -- Unconditional: the options popup fills the cache before the gate is ever set.
        ns.TalentCondInvalidate()
        -- Bar Glows limited to a hero tree: re-check them now (only while one exists).
        if ns._barGlowAnyHero and ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
        ScheduleTalentRebuild()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        ScheduleRosterRebuild()
        _CDMApplyVisibility()
        return
    end
    if event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        -- Blizzard restores frame positions/alpha after cinematics end. Re-hide immediately so the Blizzard CDM doesn't reappear.
        local p = ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.hideBlizzard then
            C_Timer.After(0, function()
                HideBlizzardCDM()
                if p.cdmBars.useBlizzardBuffBars then
                    RestoreBlizzardBuffFrame()
                end
            end)
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if InCombatLockdown() then return end
        BuildAllCDMBars()
        if ns.QueueReanchor then ns.QueueReanchor() end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_UPDATE_RESTING"
       or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        _CDMApplyVisibility()
        return
    end
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED"
        or event == "PLAYER_CAN_GLIDE_CHANGED"
        or event == "PLAYER_IS_GLIDING_CHANGED" then
        -- Defer to a clean execution context: the event handler chain can carry taint from other
        -- addons, which propagates into LayoutCDMBar when a bar transitions from hidden to visible (visHideMounted). The dragonriding edges take the same deferred path for the same reason (mid-flight unhide runs LayoutCDMBar).
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORM" then
        -- Bail fast if no bar actually uses visHideMounted: druids shift constantly in combat (Bear/Cat) and we don't want to re-run the visibility pipeline for nothing.
        local p = ECME.db and ECME.db.profile
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return end
        local anyMountedOpt = false
        for _, bd in ipairs(bars) do
            if bd.visHideMounted then anyMountedOpt = true; break end
        end
        if not anyMountedOpt then return end
        -- Defer one frame: the Travel Form aura is applied slightly after UPDATE_SHAPESHIFT_FORM fires, so IsPlayerMountedLike's aura check would miss it on the immediate pass.
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        if ns._syncRotationCombatState then ns._syncRotationCombatState() end
        if event == "PLAYER_REGEN_DISABLED" then
            SetInCombat(true)
            _CDMApplyVisibility()
            ns.RefreshItemCountOOCBars()
            -- Straight through, same as the exit edge below: the sweep only
            -- touches our own overlays, so it needs nothing from the visibility
            -- pass above, and a deferral would leave the pull one frame dark.
            ns.CDMGlowCombatSync()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Buffer combat exit: brief out-of-combat blips (mob dies, re-aggro) shouldn't flash visibility changes.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    SetInCombat(false)
                    _CDMApplyVisibility()
                    ns.RefreshItemCountOOCBars()
                    ns.CDMGlowCombatSync()
                end
            end)
        else
            -- Zone transition: re-apply visibility (mounted state etc. may have changed). No rebuild or reanchor -- SPELLS_CHANGED handles the rebuild if the spec changed.
            _CDMApplyVisibility()
        end
        -- Flush deferred TBB rebuild that was queued during combat
        if event == "PLAYER_REGEN_ENABLED" and ns.IsTBBRebuildPending and ns.IsTBBRebuildPending() then
            if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end
        end
        -- Flush a secondary buff-viewer park that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and ns._secondaryParkPending then
            ns._secondaryParkPending = nil
            local sv = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
            local svc = sv and _ecmeFC[sv]
            if svc and svc.hidden then ns.ParkSecondaryBuffViewer(sv) end
        end
        -- Flush deferred roster reanchor that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and _rosterRebuildPending then
            _rosterRebuildPending = false
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- UnitAffectingCombat, not InCombatLockdown: the latter reads false in
        -- the login window of a combat /reload, which seeded "out of combat"
        -- for the rest of the pull (in-combat visibility modes and the OOC
        -- fade then hid every bar). Secret in restricted content: fall back.
        local c = UnitAffectingCombat and UnitAffectingCombat("player")
        if c == nil or (issecretvalue and issecretvalue(c)) then
            c = InCombatLockdown and InCombatLockdown() or false
        end
        SetInCombat(c == true)
        -- Re-read the gate (a profile may have loaded), then reconcile against
        -- the combat state sampled just above: the regen events never fire for
        -- a zone-in that lands mid-combat. At the very first world entry nothing
        -- is recorded yet, so only the gate read matters there.
        ns.RefreshGlowCombatGate()
        ns.CDMGlowCombatSync()
        -- PvP instance transition backstop: entering or leaving a PvP instance rebuilds viewer pools (PvP talents activate/deactivate). Rebuild + reanchor so the new pool frames are claimed.
        local _, instType = IsInInstance()
        local wasPvP = ns._cdmWasInPvP
        local isPvP = (instType == "arena" or instType == "pvp")
        if wasPvP and not isPvP then
            ScheduleTalentRebuild()
        end
        ns._cdmWasInPvP = isPvP or nil
        if isPvP and not wasPvP then
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
        -- Install rotation helper hook after CDM frames have been built
        C_Timer.After(1, function()
            ns.InstallRotationHook()
        end)
        -- Safety: re-apply visibility after loading screen settles. Two passes to catch both fast and late viewer pool rebuilds.
        C_Timer.After(1.5, _CDMApplyVisibility)
        C_Timer.After(3, _CDMApplyVisibility)
    end
    if event == "SPELLS_CHANGED" then
        CheckSpecChange()
        ns._spellsReadyForApply = true
        -- Spell data churn invalidates cooldownID resolution memos.
        ns._cdmResGen = ns._cdmResGen + 1
        -- Engine spell data changed (spec-swap churn tail, druid form swap, talent/spell overrides).
        -- The variant-expanded diversion maps and the memoized cdID->bar routes were derived from
        -- the PREVIOUS spell state; a route resolved mid-churn against transitional cooldown info
        -- is cached until the next map rebuild and pins a ghosted/custom spell onto the wrong
        -- visible bar. Re-derive from current truth and re-claim -- the LAST fire of any churn
        -- burst always leaves the final state correct, with no settle timers. (CheckSpecChange's reconcile also rebuilds the map, but a same-key fire means the data changed again after that rebuild.)
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        -- The tracked-buff catalog can change in the same churn, and the login-pass reconcile may
        -- have consumed its dirty flag against a still-empty viewer pool (the flag is cleared
        -- before the call and an empty catalog no-ops). Re-arm so the queued reanchor reconciles the buff display order against the populated catalog.
        ns._cdmBuffOrderDirty = true
        if ns.QueueReanchor then ns.QueueReanchor() end
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        ns.DisarmOverrideRanges()   -- the new spec's overrides re-arm on their own events
        -- Non-rebuild work only. The actual spec change rebuild is driven by SPELLS_CHANGED above
        -- (which fires for both manual and auto swaps). This handler just invalidates caches that need immediate clearing.
        EllesmereUI.InvalidateFrameCache()
    end
    RequestUpdate()
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ECME1 = "/ecme"
SLASH_ECME2 = "/cdmeffects"
SLASH_ECME3 = "/ecdm"
SlashCmdList.ECME = function(msg)
    if InCombatLockdown and InCombatLockdown() then return end
    EllesmereUI:ShowModule("EllesmereUICooldownManager")
end

-- /cd toggles Blizzard's Cooldown Manager settings: out of combat, a frame
-- later (off the chat line, as the parent's commands run). WoW Forever's
-- Gamepad interface style blocks opening a Blizzard panel from addon code.
-- The /cd alias itself is set in ECME:OnInitialize, and only while Quality of
-- Life's "Type /cd to open Blizzard CDM" is on.
SlashCmdList.EUIBLIZZCDM = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot open the Cooldown Manager during combat."))
            return
        end
        if EllesmereUI.PadGamepadUI() then
            EllesmereUI.PrintError(EllesmereUI.L("Cannot open the Cooldown Manager with the Gamepad interface style."))
            return
        end
        OpenBlizzardCDMTab()
    end)
end


I.broken = false
