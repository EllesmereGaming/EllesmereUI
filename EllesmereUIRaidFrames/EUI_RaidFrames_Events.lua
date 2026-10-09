if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Events.lua
--
--  OnEvent: the handler of the event frame and of every unit tracker.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs       = ipairs
local wipe         = wipe
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local InCombatLockdown      = InCombatLockdown
local C_Timer               = C_Timer

local allButtons, GetFFD, unitToButton = I.allButtons, I.GetFFD, I.unitToButton
local RebuildUnitMap, UpdateButton = I.RebuildUnitMap, I.UpdateButton
local UpdateReadyCheck, LayoutGroups = I.UpdateReadyCheck, I.LayoutGroups
local ReloadFrames, RangeUpdate = I.ReloadFrames, I.RangeUpdate
local UpdateVisibility, SetInCombat = I.UpdateVisibility, I.SetInCombat
local SetReadyCheckActive = I.SetReadyCheckActive

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local inCombat = false
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) inCombat = v end
local readyCheckActive = false
I.readyCheckActiveSetters[#I.readyCheckActiveSetters + 1] = function(v) readyCheckActive = v end
local framesVisible = false
I.framesVisibleSetters[#I.framesVisibleSetters + 1] = function(v) framesVisible = v end

-- Healer Mana Display: its rebuild normally rides the raid/party frame paths
-- (UpdatePowerEventRegistration tails). A roster change that lands with BOTH
-- frame sets hidden -- leaving a raid to solo, or to a party while EUI party
-- frames are disabled -- skips every rebuild, so the display would keep its
-- last group's content (raid-mode names included) indefinitely.
local function RebuildHealerManaIfFramesHidden()
    if not framesVisible and not ns._partyFramesVisible and ns.HM_Rebuild then
        ns.HM_Rebuild()
    end
end

-------------------------------------------------------------------------------
--  Event handlers
-------------------------------------------------------------------------------
local function OnEvent(self, event, arg1, ...)
    -- Hot per-unit branches FIRST (thousands per pull); everything below them
    -- is rare. Order is semantics-free -- event names are distinct -- and a
    -- hidden frame set has empty routing maps, so these no-op there exactly as
    -- they did behind the visibility guard further down.
    if event == "UNIT_HEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- Latched rez offer: the accept lands as a health edge (no further
            -- INCOMING_RESURRECT_CHANGED). This edge OWNS the alive-clear (the
            -- predicate is deliberately pure), then repaints the shared icon.
            -- Clearing here also stops a lingering offer window from painting a
            -- fresh, unrezzed corpse if the unit dies again. Nil lookup for
            -- everyone else.
            local hadRez = ns._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                ns._rezPend[arg1] = nil
            end
            ns._UpdateButtonHealth(btn, arg1)
            if hadRez then UpdateReadyCheck(btn, arg1) end
        end
    elseif event == "UNIT_MAXHEALTH" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- Same latch ownership as UNIT_HEALTH: on accept both fire in
            -- unguaranteed order, and whichever runs first must fix the icon.
            local hadRez = ns._rezPend[arg1]
            if hadRez ~= nil and hadRez ~= true and not UnitIsDeadOrGhost(arg1) then
                ns._rezPend[arg1] = nil
            end
            ns._UpdateButtonHealth(btn, arg1)
            ns._ResettleButtonHealth(btn)
            -- Max moves the absorb bars' range (see the header dispatcher's
            -- UNIT_MAXHEALTH branch for the full rationale).
            local dmx = GetFFD(btn)
            if dmx._absActive then ns._MarkAbsorbDirty(btn, arg1) end
            if hadRez then UpdateReadyCheck(btn, arg1) end
        end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
        or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            -- The event IS the arm: plainly observable even while the values
            -- are secret. Paint coalesces to once per render frame.
            -- Prediction is view-gated: with the feature off for this button's
            -- view the event changes no pixel and must not arm.
            local dd = GetFFD(btn)
            if event == "UNIT_HEAL_PREDICTION" then
                local sv = dd._isParty and ns._scaledPartyProxy
                    or (dd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
                if sv.healPrediction then
                    ns._AbArm(btn, arg1, dd)
                    ns._MarkAbsorbDirty(btn, arg1)
                end
            else
            if event ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then ns._AbArm(btn, arg1, dd) end
            ns._MarkAbsorbDirty(btn, arg1)
            if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(btn, arg1) end
            if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                dd._rmhPct = nil -- reduced-max cache: this is its only value edge
                ns._UpdateButtonHealth(btn, arg1)
                ns._ResettleButtonHealth(btn)
            end
            end -- prediction view-gate else
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetInCombat(true)
        -- HARD INVARIANT: the real party/raid frames must never be left hidden
        -- when a pull starts. Every restore op reached from here is combat-legal
        -- (SetAlpha on our own containers; Hide/SetParent on our own non-secure
        -- preview frames), so it can never be blocked or deferred. This forces
        -- the frames fully visible the instant combat begins, even if a preview
        -- or size preview was still active, independent of the panel auto-close.
        if ns._sizePreviewTier then
            ns._sizePreviewTier = nil
            if ns._HideSizePreview then ns._HideSizePreview() end
        end
        if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
        -- Combat starting: hide role/leader icons on frames using the in-combat cogs.
        if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        if ns._UpdateLeaderIcons then ns._UpdateLeaderIcons() end
        if ns._CombatIconEnabled() and ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        SetInCombat(false)
        local frameStrataDirty = ns._frameStrataDirty
        if frameStrataDirty and ns.ApplyFrameStrata then ns.ApplyFrameStrata() end
        -- Combat ended: restore any role/leader icons suppressed during combat.
        if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        if ns._UpdateLeaderIcons then ns._UpdateLeaderIcons() end
        if ns._CombatIconEnabled() and ns._UpdateCombatIcons then ns._UpdateCombatIcons() end
        -- Complete any container reparent that was blocked during combat (e.g.
        -- the options panel was closed mid-combat while a preview was active).
        -- Without this, a combat auto-close can leave the real frames orphaned
        -- under the hidden preview parent until the next options open+close.
        if ns._restorePending then
            ns._restorePending = nil
            if ns.EnsureRealFramesRestored then ns.EnsureRealFramesRestored() end
        end
        local rosterDirty = ns._rosterDirtyInCombat
        local sizeTierDirty = ns._sizeTierDirtyInCombat
        -- Force the heavy refresh ONLY if the roster/size changed during combat.
        -- Otherwise the live per-unit events kept buttons current and the
        -- transition gate in UpdateVisibility skips the rebuild.
        if rosterDirty or sizeTierDirty then
            ns._visForceRebuild = true
        end
        ns._rosterDirtyInCombat = nil
        ns._sizeTierDirtyInCombat = nil
        UpdateVisibility()
        ns._UpdatePartyVisibility()
        if rosterDirty or sizeTierDirty then
            if framesVisible then
                if sizeTierDirty then
                    -- Size tier crossed during combat: full reload now safe
                    ReloadFrames()
                else
                    LayoutGroups()
                end
            end
            -- Same-dimension tier changes take the LayoutGroups branch; reapply offset
            -- so the container lands at the correct tier. Outside the framesVisible
            -- gate for the same reason as the roster path: a raid left mid-combat must
            -- still re-base the now-hidden container once combat ends.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
            if rosterDirty then RebuildHealerManaIfFramesHidden() end
        end
        -- Party container geometry deferred by a combat-time _ERF_RefreshAll.
        if ns._partyGeomDirtyInCombat then
            ns._partyGeomDirtyInCombat = nil
            if ns._ApplyPartyContainerGeometry then ns._ApplyPartyContainerGeometry() end
        end
        -- Flush any power show/hide transitions deferred during combat (see UpdateButton);
        -- only the buttons actually marked dirty get a repaint.
        if ns._powerDirtyInCombat then
            ns._powerDirtyInCombat = nil
            for _, btn in ipairs(allButtons) do
                local d = GetFFD(btn)
                if d._powerDirtyInCombat then
                    d._powerDirtyInCombat = nil
                    UpdateButton(btn)
                end
            end
            if ns._partyAllButtons then
                for _, btn in ipairs(ns._partyAllButtons) do
                    local d = GetFFD(btn)
                    if d._powerDirtyInCombat then
                        d._powerDirtyInCombat = nil
                        UpdateButton(btn)
                    end
                end
            end
        end
        -- Restore child frame levels after a deferred strata change. A Party
        -- Frames kit or party portrait geometry write blocked in combat (a
        -- Frame Scale or portrait change through a combat-time refresh) needs
        -- the same full party pass: it re-sizes the buttons, re-runs the kit
        -- and portrait passes and relays the slots.
        local kitDirty = ns._partyKitDirtyInCombat
        ns._partyKitDirtyInCombat = nil
        if frameStrataDirty then
            if not (sizeTierDirty and framesVisible) then ReloadFrames() end
            if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
            -- The re-stack reset the child levels the Color Custom Borders copies took at
            -- their last restyle, which ran in combat before the strata applied; the
            -- fingerprint-gated reload above will not restyle them again.
            local AK = EllesmereUI.AuraKit
            if AK and AK.RestyleSoon then
                AK.RestyleSoon("rf:dispel:raid")
                AK.RestyleSoon("rf:dispel:party")
                AK.RestyleSoon("rf:dispel:extra")
            end
        elseif kitDirty and ns.ReloadPartyFrames then
            ns.ReloadPartyFrames()
        end
        -- Pet frames: the roster changes and applies deferred through combat, after the layout above.
        ns.PF_Flush()
    elseif event == "ENCOUNTER_START" then
        -- Drives the raid/party frame "Out of Boss Combat" tooltip mode (read in
        -- the frame OnEnter via ns._inBossCombat).
        ns._inBossCombat = true
    elseif event == "ENCOUNTER_END" then
        ns._inBossCombat = false
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        -- Roles changed: refresh raid sort so the player's-group nameList
        -- (Show Self First) re-orders the rest by the new roles. The other
        -- groups re-sort natively. Out of combat only; no-op if order unchanged.
        if not inCombat and framesVisible and ns._ApplySortToHeaders then
            ns._ApplySortToHeaders()
        end
        -- Party Prioritize Class and the arena self-order nameList are both
        -- role-aware, so a role change must rebuild them (native role sort
        -- updates itself; these do not). FrameSort's list is role-aware too.
        if not inCombat and ns._partyFramesVisible
            and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
            and ns._LayoutPartyFrames then
            ns._LayoutPartyFrames()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Unit tokens reindex on roster changes; a latched rez offer keyed by the
        -- old token would paint on the wrong player, so drop them all.
        if event == "GROUP_ROSTER_UPDATE" then
            wipe(ns._rezPend)
            -- Pet frames: flushed once by the roster pass below, or at combat end.
            ns.PF_MarkDirty()
        end
        -- InCombatLockdown too: a /reload in combat never sees PLAYER_REGEN_DISABLED.
        if inCombat or InCombatLockdown() then
            ns._rosterDirtyInCombat = true
            -- The visibility drivers show and hide the containers on their own;
            -- bring the Lua side (event gates, maps, tickers) in step first.
            ns._RFCombatVisEdge()
            -- Check if size tier changed during combat (deferred to REGEN)
            local numMembers = ns._GetEffectiveRaidSize()
            if numMembers > 0 then
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers)
                if newW ~= ns._activeSizeW or newH ~= ns._activeSizeH then
                    ns._sizeTierDirtyInCombat = true
                end
                local _, newOv = ns._RFResolveTierOverride(numMembers)
                if newOv ~= ns._activeTierOverride then
                    ns._sizeTierDirtyInCombat = true
                end
            end
            -- Rebuild unit maps during combat so new/moved members get events.
            if framesVisible then
                wipe(unitToButton)
                for _, btn in ipairs(allButtons) do
                    if btn:IsVisible() then
                        local u = btn:GetAttribute("unit")
                        if u then
                            local d = GetFFD(btn)
                            -- Extra Frames duplicates never own a map slot
                            if not d._isExtra then unitToButton[u] = btn end
                            local _, classToken = UnitClass(u)
                            d.classToken = classToken
                        end
                    end
                end
            end
            -- Party frames: rebuild unit map during combat
            if ns._partyFramesVisible then
                wipe(ns._partyUnitToButton)
                for _, btn in ipairs(ns._partyAllButtons) do
                    if btn:IsVisible() then
                        local u = btn:GetAttribute("unit")
                        if u then
                            ns._partyUnitToButton[u] = btn
                            local d = GetFFD(btn)
                            local _, classToken = UnitClass(u)
                            d.classToken = classToken
                        end
                    end
                end
                -- The self button's unit never changes, so no assignment remaps it
                -- when the driver shows the container a tick after this pass; its
                -- own shown flag (set out of combat) says whether it owns the player.
                local sb = ns._partySelfButton
                if sb and sb:IsShown() then ns._partyUnitToButton.player = sb end
            end
            -- Combat zone-ins deliver GROUP_ROSTER_UPDATE in storms; unit maps stay
            -- per-fire (routing must be correct immediately) but the paint coalesces to
            -- one next-frame pass reading the storm's FINAL state (same NewTimer(0)
            -- shape as the OOC branch). Paint work is unprotected, so this is combat-safe.
            if not ns._crPaintTimer and (framesVisible or ns._partyFramesVisible) then
                ns._rosterArmAt = GetTime()
                ns._crPaintTimer = C_Timer.NewTimer(0, function()
                    ns._crPaintTimer = nil
                    if framesVisible then
                        for _, btn in ipairs(allButtons) do
                            local u = btn:GetAttribute("unit")
                            if u and btn:IsVisible() then
                                ns._RosterPassPaint(btn, u)
                                ns._UpdateButtonRange(u, btn)
                            end
                        end
                    end
                    if ns._partyFramesVisible then
                        for _, btn in ipairs(ns._partyAllButtons) do
                            local u = btn:GetAttribute("unit")
                            if u and btn:IsVisible() then
                                ns._RosterPassPaint(btn, u)
                                ns._UpdateButtonRange(u, btn)
                            end
                        end
                    end
                    if ns._partySharedBorderOn then ns.RF_RefreshPartyBorder() end
                    if ns._raidSharedBorderOn then ns.RF_RefreshRaidBorders() end
                end)
            end
            return
        end
        if ns._rosterUpdateTimer then
            ns._rosterUpdateTimer:Cancel()
        else
            -- First event of this cycle: paints stamped at or after this instant
            -- came from the assignment hook (or a full pass) inside the cycle.
            ns._rosterArmAt = GetTime()
        end
        ns._rosterUpdateTimer = C_Timer.NewTimer(0, function()
            ns._rosterUpdateTimer = nil
            -- Roster changed (OOC): never force UpdateVisibility's full 40-button
            -- rebuild. The per-button OnAttributeChanged hook already fully repainted
            -- (incl. auras) every reassigned button, so a blanket x40 aura re-scan is
            -- redundant; react per-unit instead. UpdateButton still runs on every visible
            -- button (no aura rescan) so leader/role/marker/health stay correct for
            -- UNCHANGED-token units (e.g. a new leader whose token didn't change).
            local numMembers = ns._GetEffectiveRaidSize()
            local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
            local tierChanged = (newW ~= ns._activeSizeW or newH ~= ns._activeSizeH)
            local wasVis = framesVisible
            ns._visForceRebuild = nil
            UpdateVisibility()
            ns._UpdatePartyVisibility()
            -- A hidden->visible transition needs nothing more here: UpdateVisibility
            -- already laid the headers out and ran the full rebuild (RebuildUnitMap +
            -- UpdateAllButtons).
            if framesVisible then
                if tierChanged then
                    -- Tier changed: full reload (recalculates _activeSizeW/H, restyles).
                    ReloadFrames()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                elseif wasVis then
                    -- Already visible, same tier: light refresh only. Aura
                    -- full-rescans are intentionally skipped (hook + UNIT_AURA
                    -- keep them current); the per-button pass repaints only what
                    -- the roster can change (see ns._RosterPassPaint).
                    RebuildUnitMap()
                    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
                    for _, btn in ipairs(allButtons) do
                        local u = btn:GetAttribute("unit")
                        if u and btn:IsVisible() then ns._RosterPassPaint(btn, u) end
                    end
                    LayoutGroups()
                end
            end
            -- Re-derive the growth-corner anchor after any roster-driven layout.
            -- tierChanged only compares frame DIMENSIONS, so two same-sized tiers (fresh
            -- tiers copy the base 20-man size) take the bare-LayoutGroups branches even
            -- with different offsets/growth -- without this, a roster that refined from
            -- an early undercount (streaming subgroup data at join) stuck the container on
            -- the small-tier position until the next full reload. Cheap, idempotent,
            -- self-gates on combat. Deliberately OUTSIDE framesVisible: a raid left mid-
            -- combat still needs the dormant container re-based (it re-derives its own
            -- size while hidden) or unlock mode saves against stale raid-tier geometry.
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            if ns._partyFramesVisible then
                ns._LayoutPartyFrames()
            end
            RebuildHealerManaIfFramesHidden()
            -- Pet frames: once per roster pass, after the groups they attach to are laid out.
            ns.PF_Flush()
        end)
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "PORTRAITS_UPDATED" or event == "UNIT_MODEL_CHANGED" then
        -- Party Frames kit / party portrait only (registered while the party
        -- frames are shown with a portrait that needs them; the model event
        -- for a 3D portrait alone). Matched on each party button's unit
        -- attribute, never the routing map: a portrait is a sticky paint,
        -- and the map keeps stale tokens.
        local list = ns._partyAllButtons
        for i = 1, #list do
            local b = list[i]
            local u = b:GetAttribute("unit")
            if u and (arg1 == nil or u == arg1) then
                local bd = GetFFD(b)
                if (bd.kitPortrait or bd.pt) and UnitExists(u) then ns.RF_PtPaint(bd, u, event) end
            end
        end
    elseif not framesVisible and not ns._partyFramesVisible then
        -- Skip all per-unit event processing when no frames are visible
        return
    elseif event == "UNIT_IN_RANGE_UPDATE" then
        -- Standard ~40yd range change for this unit (event-driven, debounced).
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            ns._UpdateButtonRange(arg1, btn)
            -- A 3D party portrait showing the out-of-sight question mark:
            -- a member coming into range is in sight again.
            if ns._ptModelEv then
                local bd = GetFFD(btn)
                local pt = bd.pt
                if pt and pt._state == false then ns.RF_PtPaint(bd, arg1, "Probe") end
            end
        end
    elseif event == "UNIT_PHASE" then
        -- Phasing doesn't fire UNIT_IN_RANGE_UPDATE; re-evaluate all (rare).
        if ns._RangeSeedAll then ns._RangeSeedAll() end
    elseif event == "UNIT_POWER_UPDATE" then
        -- Healer Mana Display rides the same per-unit registration: one hash
        -- lookup when off/empty, one text repaint when this unit has a row.
        local hmRows = ns._hmUnitRows
        if hmRows and hmRows[arg1] then ns._HMUpdateValue(arg1) end
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local d = GetFFD(btn)
            -- Value only (Blizzard's CompactUnitFrame_UpdatePower shape): type,
            -- color and bounds belong to the UNIT_DISPLAYPOWER edge below; nil
            -- = not derived yet for this occupant, derive once.
            local pType = d._pwType
            if pType == nil then
                ns._RFPowerTypeEdge(d, arg1)
                pType = d._pwType
            end
            -- Percent-based, secret-safe (see UpdateButton power block).
            local ppct = UnitPowerPercent(arg1, pType, true, CurveConstants.ScaleTo100)
            d.power:SetValue(ppct)
            -- Power Text rides the same value (nil = off: this one field test).
            local pwtMode = d._pwtMode
            if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, arg1, pType) end
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        -- The displayed power type changed (forms, spec swaps, vehicles):
        -- re-derive type + color + bounds once (Power Text's colour too), then push the value.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and GetFFD(btn).power then
            local d = GetFFD(btn)
            ns._RFPowerTypeEdge(d, arg1)
            local ppct = UnitPowerPercent(arg1, d._pwType, true, CurveConstants.ScaleTo100)
            d.power:SetValue(ppct)
            local pwtMode = d._pwtMode
            if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, arg1, d._pwType) end
        end
    elseif event == "UNIT_NAME_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        -- The name arriving is also when the class becomes known (Blizzard's
        -- own comment on this edge): drop the cached class token first.
        if btn then GetFFD(btn)._clsTok = nil; UpdateButton(btn) end
        -- NAMELIST-driven headers (party Prioritize Class, raid Show Self
        -- First) are built from member names. A member whose name populated
        -- late, or changed since the build, sits under the trailing
        -- placeholder token (sorted last) or, when the builder bailed, in
        -- native order. Rebuild the lists now that the real name exists
        -- (debounced: names resolve in bursts after a loading screen) so the
        -- proper order returns once the last name lands.
        if inCombat then
            ns._rosterDirtyInCombat = true
        else
            if ns._nameUpdateTimer then ns._nameUpdateTimer:Cancel() end
            ns._nameUpdateTimer = C_Timer.NewTimer(0.1, function()
                ns._nameUpdateTimer = nil
                if InCombatLockdown() then
                    ns._rosterDirtyInCombat = true
                    return
                end
                if ns._partyFramesVisible
                    and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
                    and ns._LayoutPartyFrames then
                    ns._LayoutPartyFrames()
                end
                if framesVisible and ns._ApplySortToHeaders then
                    ns._ApplySortToHeaders()
                end
            end)
        end
    elseif event == "UNIT_LEVEL" then
        -- Level Text only (registered while a view shows it): the level alone repaints,
        -- on its spot or in front of the name.
        local btn = unitToButton[arg1]
        if btn then ns._RFRepaintLevel(btn) end
        btn = ns._partyUnitToButton[arg1]
        if btn then ns._RFRepaintLevel(btn) end
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            local d = GetFFD(btn)
            ns.RF_PaintThreat(d, d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile, arg1)
        end
    elseif event == "UNIT_FLAGS" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then ns._UpdateCombatIconFor(arg1, btn) end
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_CONNECTION" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then
            if event == "UNIT_CONNECTION" then GetFFD(btn)._clsTok = nil end
            UpdateButton(btn)
            -- Connection changes don't fire UNIT_IN_RANGE_UPDATE; re-evaluate
            -- range so offline units take their fixed alpha and reconnecting
            -- units return to the normal out-of-range fade.
            if event == "UNIT_CONNECTION" then ns._UpdateButtonRange(arg1, btn) end
        end
        -- The member's pet frame, when one shows.
        if event == "UNIT_CONNECTION" then ns._PF_OwnerRange(arg1) end
    elseif event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
        -- Only status text / health color changes (online/offline). The payload
        -- names the unit: repaint its button(s) alone. The full sweeps remain the
        -- fallback for a unit no button maps yet (token shape we do not route).
        local btn = arg1 and (unitToButton[arg1] or ns._partyUnitToButton[arg1])
        if btn then
            local pv = GetFFD(btn)._isParty and ns._partyPvActive or previewActive
            if not pv and btn:IsVisible() then UpdateButton(btn) end
            local xf = ns._xfUnitToButton[arg1]
            if xf and not previewActive and xf:IsVisible() then UpdateButton(xf) end
        else
            if not previewActive then
                for _, b in ipairs(allButtons) do
                    local u = b:GetAttribute("unit")
                    if u and b:IsVisible() then UpdateButton(b) end
                end
            end
            if not ns._partyPvActive then
                for _, b in ipairs(ns._partyAllButtons) do
                    local u = b:GetAttribute("unit")
                    if u and b:IsVisible() then UpdateButton(b) end
                end
            end
        end
    elseif event == "RAID_TARGET_UPDATE" then
        ns._UpdateRaidMarkers()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns._UpdateTargetBorders()
    elseif event == "READY_CHECK" then
        SetReadyCheckActive(true)
        for _, btn in ipairs(allButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        for _, btn in ipairs(ns._partyAllButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
    elseif event == "READY_CHECK_CONFIRM" then
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn then UpdateReadyCheck(btn, arg1) end
    elseif event == "READY_CHECK_FINISHED" then
        SetReadyCheckActive(false)
        C_Timer.After(5, function()
            if not readyCheckActive then
                -- Re-evaluate rather than force-hide: a unit may have an incoming
                -- summon active that shares the same texture.
                for _, btn in ipairs(allButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
                end
                for _, btn in ipairs(ns._partyAllButtons) do
                    local u = btn:GetAttribute("unit")
                    if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
                end
            end
        end)
    elseif event == "INCOMING_SUMMON_CHANGED" then
        -- Broadcast event (no unit payload); re-evaluate every visible button.
        for _, btn in ipairs(allButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
        for _, btn in ipairs(ns._partyAllButtons) do
            local u = btn:GetAttribute("unit")
            if u and btn:IsVisible() then UpdateReadyCheck(btn, u) end
        end
    elseif event == "INCOMING_RESURRECT_CHANGED" then
        -- Fires with a unit payload when a rez starts/stops on that unit. The stop
        -- edge on a still-dead unit that was being cast on latches the offer window
        -- (ns._RFRezShown keeps the icon up until accept/expiry); the single-shot
        -- timer is the only thing that repaints an untouched corpse at expiry.
        if arg1 then
            if UnitHasIncomingResurrection(arg1) then
                ns._rezPend[arg1] = true
            elseif ns._rezPend[arg1] == true then
                if UnitIsDeadOrGhost(arg1) then
                    local exp = GetTime() + 60
                    ns._rezPend[arg1] = exp
                    local unit = arg1
                    C_Timer.After(60.1, function()
                        if ns._rezPend[unit] ~= exp then return end
                        ns._rezPend[unit] = nil
                        local b = unitToButton[unit] or ns._partyUnitToButton[unit]
                        if b and b:IsVisible() then
                            if ns._UpdateButtonHealth then ns._UpdateButtonHealth(b) end
                            UpdateReadyCheck(b, unit)
                        end
                    end)
                else
                    ns._rezPend[arg1] = nil
                end
            end
        end
        -- Refresh the status text (so DEAD hides while rezzing / reappears after)
        -- as well as the shared rez icon.
        local btn = unitToButton[arg1] or ns._partyUnitToButton[arg1]
        if btn and btn:IsVisible() then
            if ns._UpdateButtonHealth then ns._UpdateButtonHealth(btn) end
            UpdateReadyCheck(btn, arg1)
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if ns.BM_RebuildLookup then ns.BM_RebuildLookup(db) end
        -- The player's effective role is spec-derived (EllesmereUI.UnitEffectiveRole),
        -- so the player's own spec swap is a role change for every role consumer:
        -- mirror the PLAYER_ROLES_ASSIGNED refresh and repaint role icons. The
        -- event also fires for other units' spec updates; only the player's
        -- changes our answers.
        if arg1 == "player" and not inCombat then
            if framesVisible and ns._ApplySortToHeaders then
                ns._ApplySortToHeaders()
            end
            if ns._partyFramesVisible
                and (db.profile.partyPrioritizeClass or ns._PartyInRaid() or ns._FsPartyMode())
                and ns._LayoutPartyFrames then
                ns._LayoutPartyFrames()
            end
            if ns._UpdateRoleIcons then ns._UpdateRoleIcons() end
        end
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        -- Hide Groups 5-8 in Mythic Raid (heard only while on): a switch inside
        -- the raid (e.g. Heroic -> Mythic) against the set the layout applied.
        if (ns._VisibleGroups() == ns._mythicGroups) ~= (ns._rfLaidMythic == true) then
            if InCombatLockdown() then
                ns._sizeTierDirtyInCombat = true  -- REGEN runs the full reload
            elseif framesVisible then
                ReloadFrames()
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-sync the boss-combat flag on load. IsEncounterInProgress() still
        -- reports an active encounter after a mid-fight /reload or zone (where
        -- ENCOUNTER_START already fired and will not fire again), so "Out of Boss
        -- Combat" keeps suppressing; otherwise this clears a stale flag from a
        -- missed ENCOUNTER_END so tooltips are not stuck hidden.
        ns._inBossCombat = (IsEncounterInProgress and IsEncounterInProgress()) or false
        -- 3D party portraits: a world transition can reset a model at the
        -- same guid.
        if ns._ptModelEv and ns.RF_PtRepaintAll then ns.RF_PtRepaintAll("PLAYER_ENTERING_WORLD") end
        C_Timer.After(0.5, function()
            -- Pet frames: flushed at the end of this settle, or at combat end.
            ns.PF_MarkDirty()
            -- Zoning in mid-combat (e.g. into a raid where trash is already
            -- pulled) must NOT run the reload here: ReloadFrames calls SetSize on
            -- the protected SecureGroupHeader buttons, which Blizzard blocks in
            -- combat (ADDON_ACTION_BLOCKED). Defer the full reload to combat end
            -- via the existing size-tier dirty flag; PLAYER_REGEN_ENABLED re-runs
            -- UpdateVisibility + ReloadFrames + the party layout once it is safe.
            -- The other calls below already self-bail in combat, so skipping them
            -- until REGEN is behavior-neutral.
            if InCombatLockdown() then
                ns._sizeTierDirtyInCombat = true
                return
            end
            -- Entering or leaving a Mythic raid with Hide Groups 5-8 on changes which groups
            -- show even when the tier holds; read before UpdateVisibility can re-lay them.
            local mythicChanged = (ns._VisibleGroups() == ns._mythicGroups) ~= (ns._rfLaidMythic == true)
            UpdateVisibility()
            ns._UpdatePartyVisibility()
            if framesVisible then
                -- Full reload ONLY when the size tier actually changed across the zone
                -- -- recalculating tier dimensions is this call's whole purpose, and
                -- with the tier unchanged the restyle would re-derive identical values
                -- on every button. The unchanged path heals just what zoning can
                -- invalidate: private-aura anchor geometry (baked in at registration;
                -- the unit-guarded rebuild paths skip re-registration when tokens are
                -- unchanged), range alpha, and the boss/extra inheritors. Content
                -- staleness is covered by the per-unit event storm that follows every
                -- zone-in (the same model the roster path documents above).
                local numMembers = ns._GetEffectiveRaidSize()
                local newW, newH = ns._GetRaidSizeFrameDimensions(numMembers > 0 and numMembers or 1)
                local tierChanged = (newW ~= ns._activeSizeW or newH ~= ns._activeSizeH)
                if not tierChanged and numMembers > 0 then
                    local _, newOv = ns._RFResolveTierOverride(numMembers)
                    if newOv ~= ns._activeTierOverride then tierChanged = true end
                end
                if tierChanged or mythicChanged then
                    ReloadFrames()
                else
                    RangeUpdate()
                    if ns.FB_Apply then ns.FB_Apply() end
                    if ns.XF_Apply then ns.XF_Apply() end
                end
            end
            if ns._partyFramesVisible then
                -- Full party reload (not just layout), mirroring the raid branch above:
                -- private aura anchors registered during the loading screen can carry
                -- stale geometry (icon size / border scale are baked in at
                -- registration), and the unit-guarded rebuild paths skip
                -- re-registration when units are unchanged. ReloadPartyFrames
                -- recomputes the Auto Resize scale and re-registers every anchor.
                ns.ReloadPartyFrames()
            end
            -- A tier reload above has already applied the pets; otherwise they apply once here.
            ns.PF_Flush()
        end)
    end
end

I.OnEvent = OnEvent
I.broken = false
