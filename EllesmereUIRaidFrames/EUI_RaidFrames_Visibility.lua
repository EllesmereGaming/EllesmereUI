if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Visibility.lua
--
--  Range fading, the ghost aura safety net and UpdateVisibility.
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
local UnitIsConnected       = UnitIsConnected
local UnitIsVisible         = UnitIsVisible
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitIsUnit            = UnitIsUnit
local UnitInRange           = UnitInRange
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local C_Timer               = C_Timer

local allButtons, FFD, GetFFD, separatedHdrs = I.allButtons, I.FFD, I.GetFFD, I.separatedHdrs
local unitToButton, RebuildUnitMap = I.unitToButton, I.RebuildUnitMap
local UpdateAllButtons, LayoutGroups = I.UpdateAllButtons, I.LayoutGroups
local SetFramesVisible, SetRangeUpdate = I.SetFramesVisible, I.SetRangeUpdate
-- false in the table for a class without one; nil here, which the tests below expect
local playerFriendlySpell = I.playerFriendlySpell or nil
local playerRezSpell = I.playerRezSpell or nil

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end

-- Assigned below; EUI_RaidFrames_Reload.lua holds the forward declaration
-- ReloadFrames calls through.
local RangeUpdate

-------------------------------------------------------------------------------
--  Range fading
--  Event-driven via UNIT_IN_RANGE_UPDATE for the standard ~40yd interact range
--  (all classes), which also covers dead units (they use UnitInRange like the
--  living). A conditional 0.5s refiner poll handles only what the event cannot:
--  the tighter friendly-spell range (Evoker/Rogue) and re-syncing a revived unit
--  back to that tight range. Pure classes with no rez run fully event-driven.
-------------------------------------------------------------------------------
-- Wrapped in a do-block; only Start/StopRangeTicker (+ RangeUpdate, declared in
-- this file's header) need to be reachable from later code.
local StartRangeTicker, StopRangeTicker
do
local rangeTicker = nil

local UnitPhaseReason = UnitPhaseReason
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

-- Classes whose effective reach is well under the ~40yd UnitInRange interact
-- range, so living units are refined with a tighter friendly spell check.
local usesSpellRange = playerFriendlySpell ~= nil
-- Whether the player can resurrect (enables dead-unit rez-range refinement).
local playerHasRez   = playerRezSpell ~= nil

-- Apply final alpha to a button: range alpha * BM frame alpha. Range alpha is
-- stored in FFD so BM can read it; BM alpha lives in _bmSavedAlpha so range can
-- read it. Each system stores its own value; final apply multiplies the two.
local function ApplyRangeAlpha(btn, rangeAlpha)
    local d = GetFFD(btn)
    d.rangeAlpha = rangeAlpha
    local bmA = btn._bmSavedAlpha or 1
    btn:SetAlpha(bmA * rangeAlpha)
    -- A 3D party portrait does not take the button's alpha: mirror it.
    if d.pt and d.pt._3dOn then ns.RF_PtModelAlpha(d, bmA * rangeAlpha) end
end

-- Secret-safe range alpha via SetAlphaFromBoolean (UnitInRange can return a
-- secret boolean in Midnight). Marks rangeAlpha nil so UpdateButton/BM leave
-- the secret-set alpha alone.
local function ApplyRangeAlphaSecret(btn, inRange, inAlpha, outAlpha)
    local bmA = btn._bmSavedAlpha or 1
    if btn.SetAlphaFromBoolean then
        btn:SetAlphaFromBoolean(inRange, bmA * inAlpha, bmA * outAlpha)
    else
        ApplyRangeAlpha(btn, inAlpha)
        return
    end
    local d = GetFFD(btn)
    d.rangeAlpha = nil
    -- A 3D party portrait does not take the button's alpha: mirror it.
    if d.pt and d.pt._3dOn then ns.RF_PtModelAlphaSecret(d, inRange, bmA * inAlpha, bmA * outAlpha) end
end

-- Evaluate + apply range alpha for ONE unit. Shared by the
-- UNIT_IN_RANGE_UPDATE event, the refiner poll, the seed pass, and roster
-- assignment. Standard living units take the secret-safe UnitInRange path.
local function UpdateButtonRange(unit, btn)
    -- Read oorAlpha through the party-aware proxy so a custom party_oorAlpha
    -- actually applies to party frames (was reading the raid value directly).
    local rd = GetFFD(btn)
    local rs = rd._isParty and ns._scaledPartyProxy or (rd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local oorAlpha = rs.oorAlpha or 0.4
    if UnitIsUnit(unit, "player") or not UnitExists(unit) then
        ApplyRangeAlpha(btn, 1)
    elseif not UnitIsConnected(unit) then
        -- Offline units take a fixed 80% alpha, never the out-of-range fade --
        -- an offline player isn't "out of range", and a steady alpha reads
        -- better alongside the offline status tint. Overrides oorAlpha entirely.
        ApplyRangeAlpha(btn, 0.8)
    elseif UnitPhaseReason and UnitPhaseReason(unit) then
        ApplyRangeAlpha(btn, oorAlpha)
    elseif UnitIsDeadOrGhost(unit) then
        -- Ghost units need to be checked using a rez-spell because UnitInRange checks the ghost's range, not the corpse's.
        -- We want to provide rez-range feedback based on the corpse's position.
        if playerHasRez then
            local r = C_Spell_IsSpellInRange(playerRezSpell, unit)
            if r == true then
                ApplyRangeAlpha(btn, 1)
            elseif r == false then
                ApplyRangeAlpha(btn, oorAlpha)
            else
                -- Use the standard ~40yd interact range (UnitInRange) as fallback
                ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
            end
        else
            -- Use the standard ~40yd interact range (UnitInRange) when player has no rez spell
            ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
        end
    elseif usesSpellRange then
        local r = C_Spell_IsSpellInRange(playerFriendlySpell, unit)
        if r == true then
            ApplyRangeAlpha(btn, 1)
        elseif r == false then
            ApplyRangeAlpha(btn, oorAlpha)
        else
            -- r == nil: no range relationship to this unit (unit-targeted spell, so a
            -- same-zone out-of-range target already returned false above) -- almost
            -- always a different zone (or a brief untargetable/LOS blip). Resolve via
            -- the secret-safe ~40yd UnitInRange (false -> faded) rather than holding the
            -- last alpha, which stranded a zone-departed unit at its old in-range alpha.
            -- Cannot reintroduce the 25-vs-40yd boundary flicker: that needed the spell
            -- check to return nil AT the boundary, which a stable far same-zone target does not.
            ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
        end
    else
        ApplyRangeAlphaSecret(btn, UnitInRange(unit), 1, oorAlpha)
    end
end
ns._UpdateButtonRange = UpdateButtonRange

-- Refiner handles only what UNIT_IN_RANGE_UPDATE cannot: the tighter friendly-spell
-- range (Evoker/Rogue). Dead units use the event-driven UnitInRange path like living
-- units, but are still polled so a spell-range class hands a revived unit back to its
-- tight spell range (one-shot resync via _rangeWasDead). Living, non-spell-range units
-- are owned by the event and skipped here, so the poll does ~no work for a stable raid.
local function RefineButtonRange(unit, btn)
    if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
    local d = GetFFD(btn)
    if UnitIsDeadOrGhost(unit) then
        d._rangeWasDead = true
        UpdateButtonRange(unit, btn)
    elseif d._rangeWasDead then
        d._rangeWasDead = nil
        UpdateButtonRange(unit, btn)
    elseif usesSpellRange then
        UpdateButtonRange(unit, btn)
    end
end

-- Seed / full re-evaluation of every assigned unit (enable, roster change,
-- phase change). Kept as RangeUpdate (forward-declared) for existing callers.
RangeUpdate = function()
    for unit, btn in pairs(unitToButton) do UpdateButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do UpdateButtonRange(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do UpdateButtonRange(unit, btn) end
    ns._PF_RangeSeed()
end
SetRangeUpdate(RangeUpdate)
ns._RangeSeedAll = RangeUpdate

local function RangeRefineAll()
    for unit, btn in pairs(unitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do RefineButtonRange(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do RefineButtonRange(unit, btn) end
end

function StartRangeTicker()
    -- Seed initial alpha; UNIT_IN_RANGE_UPDATE only fires on later changes.
    RangeUpdate()
    -- Conditional refiner: only spell-range or rez-capable classes poll.
    -- Everyone else is fully event-driven (zero polling).
    if not rangeTicker and (usesSpellRange or playerHasRez) then
        rangeTicker = C_Timer.NewTicker(0.5, RangeRefineAll)
    end
end

function StopRangeTicker()
    if rangeTicker then
        rangeTicker:Cancel()
        rangeTicker = nil
    end
    -- Reset range alpha, respect BM frame alpha
    for _, btn in pairs(unitToButton) do ApplyRangeAlpha(btn, 1) end
    for _, btn in pairs(ns._partyUnitToButton) do ApplyRangeAlpha(btn, 1) end
    for _, btn in pairs(ns._xfUnitToButton) do ApplyRangeAlpha(btn, 1) end
end
end  -- range fading section

-------------------------------------------------------------------------------
--  Ghost aura safety net
--  Throttled 1s ticker: UNIT_AURA stops firing for invisible/DC'd units and the
--  render-visibility edge has no event, so a unit that ghosts (loadscreen, out
--  of render range, disconnect) keeps whatever its containers last parsed. On
--  regain the containers are re-parsed in place (the same UpdateAllAuras lever
--  the assist gate uses on its own false->true edge). The same pass audits each
--  container's own unit binding, which nothing else re-drives once the header
--  stops re-asserting the token.
-------------------------------------------------------------------------------
local ghostTicker = nil

local function GhostAuraCheck()
    local function checkUnit(unit, btn)
        local d = GetFFD(btn)
        -- unitToButton et al. only ever gain entries on reassignment, never drop
        -- the old one, so unit/btn here can be a stale pairing; re-confirm against
        -- the button's own live attribute before writing to it.
        if btn:GetAttribute("unit") == unit and ns.RFC_RepointStale then
            ns.RFC_RepointStale(d, unit)
        end
        if not UnitIsVisible(unit) or not UnitIsConnected(unit) then
            if not d.ghostCleared then
                d.ghostCleared = true
                -- Binding at ghost time: a reassignment inside the window already
                -- re-parsed the containers (RFC_OnUnitAssigned), so the regain pass
                -- skips a button whose binding moved.
                d.ghostUnit = d.rfcUnit
            end
        else
            if d.ghostCleared then
                d.ghostCleared = false
                -- unitToButton only ever gains entries, so unit/btn can be a stale
                -- pairing: re-parse only containers still bound to this unit.
                if d.rfcUnit == unit and d.ghostUnit == unit then
                    if d.rfcDebuffs then d.rfcDebuffs:UpdateAllAuras() end
                    if d.rfcDispLoc then d.rfcDispLoc:UpdateAllAuras() end
                    if d.rfcDispel then d.rfcDispel:UpdateAllAuras() end
                    if d.rfcBm then d.rfcBm:UpdateAllAuras() end
                    if d.rfcBmChain then
                        for _, cc in pairs(d.rfcBmChain) do cc:UpdateAllAuras() end
                    end
                    if d.dmTiles then
                        for _, c in pairs(d.dmTiles) do c:UpdateAllAuras() end
                    end
                end
                d.ghostUnit = nil
            end
        end
    end
    for unit, btn in pairs(unitToButton) do checkUnit(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do checkUnit(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do checkUnit(unit, btn) end
end

local function StartGhostTicker()
    if not ghostTicker then
        ghostTicker = C_Timer.NewTicker(1.0, GhostAuraCheck)
    end
end

local function StopGhostTicker()
    if ghostTicker then
        ghostTicker:Cancel()
        ghostTicker = nil
    end
    -- Clear ghost flags
    for _, btn in pairs(unitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
    for _, btn in pairs(ns._partyUnitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
    for _, btn in pairs(ns._xfUnitToButton) do
        local d = GetFFD(btn)
        d.ghostCleared = nil
    end
end

-------------------------------------------------------------------------------
--  Visibility: show/hide based on solo/group/raid setting
-------------------------------------------------------------------------------
local framesVisible = false
I.framesVisibleSetters[#I.framesVisibleSetters + 1] = function(v) framesVisible = v end

-- True when the player is inside an arena instance. Arena puts you in a RAID
-- group, but we deliberately show our PARTY frames there (the party header is
-- bound to raid1-5 via showRaid=true) so small-group styling applies and
-- external trackers that anchor to our party frames keep working. Detection is
-- by instance type and must be checked BEFORE any IsInRaid() branch, since
-- arena makes IsInRaid() return true.
ns._InArena = function()
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

-- Party frames while IsInRaid() is true: arena (the whole team, above) or the
-- opt-in Small Raid setting, which shows group 1 as party frames and hides
-- every other member while the raid holds fewer than 10 players. Every
-- "party or raid frames" decision reads this, never ns._InArena directly;
-- the group-1 filter itself lives in _LayoutPartyFrames (ns._SmallRaidGroup).
ns._PartyInRaid = function()
    if ns._InArena() then return true end
    return db.profile.partySmallRaid == true and IsInRaid() and GetNumGroupMembers() < 10
end

-- The subgroup the party header is limited to in Small Raid mode; nil in
-- arena (whole team) and outside party-in-raid mode.
ns._SmallRaidGroup = function()
    if ns._InArena() or not ns._PartyInRaid() then return nil end
    return 1
end

-- Which set the group state shows (raid, party): raid frames in a raid, party
-- frames in a party (arena and Small Raid included), each set's Show When Solo
-- outside a group. ns._RF_VIS_MACROS spells the same rule as macro conditions.
ns._RFVisWanted = function()
    local s = db.profile
    if not IsInGroup() then
        return s.showWhenSolo and true or false, s.partyShowWhenSolo and true or false
    end
    if IsInRaid() and not ns._PartyInRaid() then return true, false end
    return false, true
end

-- Secure visibility drivers on both containers: the containers are implicitly
-- protected (secure headers inside), so only secure code can show or hide them
-- in combat, and a driver re-checks its macro every 0.2 s on its own. A group
-- joined, or a party turned raid, mid-fight then shows its frames at once.
-- Macro per [mode][that set's Show When Solo]; the mode is fixed out of combat.
-- Group state reads unit existence: the [group] conditions keep the state from
-- before combat until combat ends, so a group joined mid-fight reads as solo
-- there, while unit tokens follow the roster at once. raid1 exists exactly in
-- a raid; party1 in a party with another member; [group] stays OR'd in so a
-- group with no other member counts as grouped, as IsInGroup() does.
-- Small Raid: raid tokens run contiguously from raid1 and exist only in a raid,
-- so raid10 exists exactly when a raid holds 10 or more members (the
-- GetNumGroupMembers() < 10 rule); a party never reaches it.
-- Arena has no macro condition: it is taken at the zone-in pass.
ns._RF_VIS_MACROS = {
    raid = {
        group = { [true] = "[@raid1,exists] show; [@party1,exists][group] hide; show", [false] = "[@raid1,exists] show; hide" },
        small = { [true] = "[@raid10,exists] show; [@raid1,exists][@party1,exists][group] hide; show", [false] = "[@raid10,exists] show; hide" },
        arena = { [true] = "[@raid1,exists][@party1,exists][group] hide; show", [false] = "hide" },
    },
    party = {
        group = { [true] = "[@raid1,exists] hide; show", [false] = "[@raid1,exists] hide; [@party1,exists][group] show; hide" },
        small = { [true] = "[@raid10,exists] hide; show", [false] = "[@raid10,exists] hide; [@raid1,exists][@party1,exists][group] show; hide" },
        arena = { [true] = "show", [false] = "[@raid1,exists][@party1,exists][group] show; hide" },
    },
}

-- Registers each container's macro, only when its text changes (driver
-- registration is a protected action: out of combat, or the login window).
ns._RFSyncVisDrivers = function()
    local pc = ns._partyContainerFrame
    if not containerFrame or not pc or InCombatLockdown() then return end
    local s = db.profile
    local M = ns._RF_VIS_MACROS
    local mode = (ns._InArena() and "arena") or ((s.partySmallRaid == true) and "small") or "group"
    local r = M.raid[mode][s.showWhenSolo and true or false]
    local p = M.party[mode][s.partyShowWhenSolo and true or false]
    if ns._rfRaidVisMacro ~= r then
        RegisterStateDriver(containerFrame, "visibility", r)
        ns._rfRaidVisMacro = r
    end
    if ns._rfPartyVisMacro ~= p then
        RegisterStateDriver(pc, "visibility", p)
        ns._rfPartyVisMacro = p
    end
end

-- A set that hides keeps its buttons' units (a hidden header ignores the
-- roster) while its events stop routing: forget each painted occupant so the
-- next assignment, in combat too, takes the full repaint.
ns._RFForgetOccupants = function(list)
    for i = 1, #list do
        local d = FFD[list[i]]
        if d then d._lastGuid = nil end
    end
end

local function UpdateVisibility()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    -- Preview overrides all visibility logic -- real buttons stay suppressed
    -- (alpha), no state changes; the preview close re-runs this.
    if previewActive then return end

    -- Defensive: re-assert full opacity unless a preview is intentionally
    -- dimming the real frames. The preview system is the only thing that lowers
    -- container alpha; this runs out of combat only (the function bails in combat
    -- above) and heals any case where alpha was left at 0 with the flags cleared.
    -- Gated on the party-preview flag too so a raid-visibility recompute never
    -- un-hides the raid container behind an active party preview.
    if not ns._sizePreviewTier and not ns._partyPvActive then containerFrame:SetAlpha(1) end

    local s = db.profile
    -- Arena and Small Raid mode hide the raid frames. The player is in a raid
    -- group there, but we show our party frames instead (see
    -- _UpdatePartyVisibility), so the raid container must stay hidden even
    -- though IsInRaid() returns true.
    local visible = ns._RFVisWanted()
    local wasVisible = framesVisible
    SetFramesVisible(visible)
    ns._raidFramesVisible = visible  -- mirror for readers outside this file (the FrameSort provider)
    -- Raid frames coming or going is the one change a tracker cannot learn from
    -- its own roster events (mirrors the party call in _UpdatePartyVisibility).
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end

    -- Update showSolo attribute on all headers, but ONLY when it actually
    -- differs from the header's current value. Re-setting a SecureGroupHeader
    -- attribute re-triggers Blizzard's full child re-process (re-sort/re-assign)
    -- even when unchanged, so doing it every combat exit / visibility recompute
    -- was a large needless secure-header spike. showWhenSolo is a static setting;
    -- mirrors the needsHideShow guard in ApplySortToHeaders.
    local wantSolo = s.showWhenSolo or false
    for _, hdr in ipairs(separatedHdrs) do
        if hdr and hdr:GetAttribute("showSolo") ~= wantSolo then
            hdr:SetAttribute("showSolo", wantSolo)
        end
    end
    if ns._flatHeader and ns._flatHeader:GetAttribute("showSolo") ~= wantSolo then
        ns._flatHeader:SetAttribute("showSolo", wantSolo)
    end

    -- The driver decides the same way; synced first so the two agree this frame
    -- (readers such as the tier offset check IsShown right after).
    ns._RFSyncVisDrivers()
    containerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames when we're showing for groups
        if (IsInGroup() and not IsInRaid()) and ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end
        -- Headers last laid out hidden (native order) take the shown layout
        -- before the rebuild reads their buttons.
        if ns._rfRaidLaidVis ~= true then LayoutGroups() end
        -- Skip heavy refresh at combat end if roster didn't change. Per-unit events
        -- (UNIT_HEALTH, UNIT_AURA, etc.) kept buttons in sync during combat, so a full
        -- rebuild is only needed when the roster changed or we transition from hidden
        -- to visible. Heavy content rebuild ONLY when it could actually be stale: a
        -- real hidden->visible transition (unitToButton was wiped on hide) or a caller
        -- that flagged a roster/size change. Re-checking visibility while already shown
        -- and unchanged skips the 40-button rebuild -- the live per-unit events kept
        -- every button current the whole time. This generalizes the old combat-exit
        -- "lightweight" skip to every caller (preview restore,
        -- EnsureRealFramesRestored, etc.) so a redundant visibility recompute can never
        -- trigger a full refresh spike.
        local forceRebuild = ns._visForceRebuild
        ns._visForceRebuild = nil
        if (not wasVisible) or forceRebuild then
            RebuildUnitMap()
            if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
            UpdateAllButtons()
        end
        if IsInGroup() or IsInRaid() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        StopRangeTicker()
        StopGhostTicker()
        if wasVisible then ns._RFForgetOccupants(allButtons) end
        wipe(unitToButton)
        -- A hidden set runs native order and keeps every group header up, so the
        -- driver can show it mid-fight with every member in place.
        if ns._rfRaidLaidVis ~= false then
            LayoutGroups()
            -- The dormant container's footprint (see _ApplyTierOffset).
            if ns._ApplyTierOffset then ns._ApplyTierOffset() end
        end
    end
end
ns.UpdateVisibility = UpdateVisibility

I.RangeUpdate, I.StartGhostTicker = RangeUpdate, StartGhostTicker
I.StartRangeTicker, I.StopGhostTicker = StartRangeTicker, StopGhostTicker
I.StopRangeTicker, I.UpdateVisibility = StopRangeTicker, UpdateVisibility
I.broken = false
