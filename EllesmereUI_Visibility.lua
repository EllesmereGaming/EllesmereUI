if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Visibility.lua
--  Shared visibility dispatcher. Each module (Minimap, Friends, QuestTracker,
--  Cursor) registers its own update function here; this file owns the event
--  frame, combat state, mouseover polling, and the global bridge names.
--
--  store.visibilityMatch: nil / "all" = every constrained axis must pass (the
--  original and still default behavior), "any" = at least one must. A plain store
--  scalar rather than a key inside visibilityModes, because an Any selection can
--  consist of option lanes alone, and those are stored without a mode set to hang
--  it on.
-------------------------------------------------------------------------------
local EUI = _G.EllesmereUI or {}
_G.EllesmereUI = EUI

-------------------------------------------------------------------------------
--  Combat state (single source of truth)
-------------------------------------------------------------------------------
local _inCombat = false

local function IsInCombat() return _inCombat end

EUI.IsInCombat = IsInCombat

-------------------------------------------------------------------------------
--  Eval helper (shared by all modules' cfg checks)
-------------------------------------------------------------------------------
-- Capability profile for the dispatcher-evaluated modules (Minimap, Friends,
-- Chat, Damage Meters, Quest Tracker): their legacy "In Party" means
-- party-exclusive-of-raid, so multi-selections keep that meaning here.
local DISPATCHER_CAPS = { partyIncludesRaid = false }

-- Returns true = show, false = hide, "mouseover" = mouseover mode
local function EvalVisibility(cfg)
    if not cfg then return true end
    if EUI.CheckVisibilityOptions and EUI.CheckVisibilityOptions(cfg) then
        return false
    end
    local ext = EUI.EvalVisibilityExtended and EUI.EvalVisibilityExtended(cfg, "visibility", nil, DISPATCHER_CAPS)
    if ext ~= nil then return ext end
    local mode = cfg.visibility or "always"
    if mode == "mouseover" then return "mouseover" end
    if mode == "always" then return true end
    if mode == "never" then return false end
    if mode == "in_combat" then return _inCombat end
    if mode == "out_of_combat" then return not _inCombat end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if mode == "in_raid"  then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo"     then return not inGroup end
    return true
end

EUI.EvalVisibility = EvalVisibility

-------------------------------------------------------------------------------
--  Updater registry
-------------------------------------------------------------------------------
local updaters = {}

-- Register a module's update function. Called whenever visibility state may
-- have changed (combat/zone/group/target change). The function should read
-- its own DB state and Show/Hide its frame accordingly.
function EUI.RegisterVisibilityUpdater(fn)
    if type(fn) ~= "function" then return end
    updaters[#updaters + 1] = fn
end

function EUI.UnregisterVisibilityUpdater(fn)
    for i = #updaters, 1, -1 do
        if updaters[i] == fn then
            table.remove(updaters, i)
            return
        end
    end
end

-- Mouseover poll registry: each entry is { frame=, visible=, isActive=fn }.
-- isActive returns true when that frame currently wants mouseover behavior.
local mouseoverTargets = {}
-- Mouseover predicates are pure functions of module settings plus the same state edges
-- the dispatcher already watches, so each target's answer is cached and re-derived only
-- when this generation moves: synchronously on every dispatcher event (the combat edge
-- must land before the next scan tick -- a stale "active" through a combat flip would
-- let the scan touch the protected Minimap during lockdown), on every
-- RequestVisibilityUpdate (every module apply pokes it), and on every shared
-- visibility-selection write. Each target's isActive closure runs at most once per
-- generation instead of once per 0.15s tick.
local _moGen = 1
local MouseoverScan  -- defined with the scan below; bound here for the subscribe

function EUI.RegisterMouseoverTarget(frame, isActive)
    if not frame or type(isActive) ~= "function" then return end
    mouseoverTargets[#mouseoverTargets + 1] = { frame = frame, visible = false, isActive = isActive }
    -- First target arms the shared 0.15s scan on the Mouse service (same-key
    -- subscribe is idempotent). No targets registered = the scan never runs.
    EllesmereUI.Mouse.SubscribeTick("visMouseover", 0.15, MouseoverScan)
end

-- Closable panels (Friends) unregister while hidden so the scan never spends
-- their isActive closure on a panel that cannot be revealed anyway. Callers
-- unregister only while their frame is hidden/dormant; no alpha restore runs.
function EUI.UnregisterMouseoverTarget(frame)
    for i = #mouseoverTargets, 1, -1 do
        if mouseoverTargets[i].frame == frame then
            table.remove(mouseoverTargets, i)
        end
    end
end

-------------------------------------------------------------------------------
--  Dispatcher
-------------------------------------------------------------------------------
local function RequestVisibilityUpdate()
    _moGen = _moGen + 1
    for i = 1, #updaters do
        local ok = pcall(updaters[i])
        if not ok then
            -- swallow; one bad updater should not take down the rest
        end
    end
end

EUI.RequestVisibilityUpdate = RequestVisibilityUpdate

-- Deferred callback so we don't re-allocate a closure on every event
local function DeferredRequest()
    RequestVisibilityUpdate()
end

-------------------------------------------------------------------------------
--  Event frame
-------------------------------------------------------------------------------
local visFrame = CreateFrame("Frame")
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visFrame:RegisterEvent("PLAYER_DEAD")
visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
-- Dragonriding edges: mount-capability changes fire PLAYER_CAN_GLIDE_CHANGED
-- (repo-proven event); takeoff/landing while staying mounted fires
-- PLAYER_IS_GLIDING_CHANGED, which is probed because nothing registered it before this
-- feature. When the probe fails on a client, the dragonriding checklist items lock
-- (EUI._hasGlidingEvent) instead of evaluating with stale edges.
visFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
do
    local ok
    if C_EventUtils and C_EventUtils.IsEventValid then
        ok = C_EventUtils.IsEventValid("PLAYER_IS_GLIDING_CHANGED") and true or false
        if ok then visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED") end
    else
        ok = pcall(visFrame.RegisterEvent, visFrame, "PLAYER_IS_GLIDING_CHANGED") and true or false
    end
    EUI._hasGlidingEvent = ok
end

visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        _inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _inCombat = false
    elseif event == "PLAYER_DEAD" then
        -- A dead player is never in combat, but PLAYER_REGEN_ENABLED is not
        -- guaranteed to fire on death (notably when dying mid-encounter in an
        -- instance). A missed "left combat" event would otherwise leave
        -- _inCombat stuck true, hiding every "Out of Combat" frame until a
        -- reload. Clearing it here is the safety net for that case.
        _inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-sync from the real combat state across world / instance boundaries
        -- in case a regen toggle was missed while loading.
        _inCombat = InCombatLockdown() and true or false
    end
    -- Synchronous: the cache must flip before any same-frame scan tick.
    _moGen = _moGen + 1
    C_Timer.After(0, DeferredRequest)
end)

-------------------------------------------------------------------------------
--  Mouseover poll
-------------------------------------------------------------------------------
-- Cursor-in-bounds check (works on hidden frames using saved position/size).
-- Coordinates come from the shared Mouse service sample.
local function IsCursorOver(frame, rawX, rawY)
    if not frame.GetRect then return false end
    local l, b, w, h = frame:GetRect()
    if not l then return false end
    local es = frame:GetEffectiveScale()
    local cx, cy = rawX / es, rawY / es
    return cx >= l and cx <= l + w and cy >= b and cy <= b + h
end

-- The mouseover-visibility scan, dispatched by the shared Mouse service at the same
-- 0.15s cadence the old poll used -- but with no per-frame OnUpdate underneath (the
-- service's anim ticker sleeps in C between fires), one shared cursor sample instead of
-- one per target, and zero cost until the first target registers.
MouseoverScan = function(rawX, rawY)
    for i = 1, #mouseoverTargets do
        local t = mouseoverTargets[i]
        local frame = t.frame
        if frame then
            local active
            if t._genSeen == _moGen then
                active = t._genActive
            else
                active = t.isActive() and true or false
                t._genSeen = _moGen
                t._genActive = active
            end
            if active then
                t._wasActive = true
                local over = IsCursorOver(frame, rawX, rawY)
                if over and not t.visible then
                    t.visible = true
                    frame:SetAlpha(1); frame:EnableMouse(true); frame:Show()
                elseif not over and t.visible then
                    t.visible = false
                    frame:Hide()
                end
            elseif t._wasActive then
                -- isActive just turned off -- clear tracking state and let
                -- UpdateVisibility handle the alpha for the new mode.
                t._wasActive = false
                t.visible = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Compat globals (kept for the many call sites already using them)
-------------------------------------------------------------------------------
_G._EBS_InCombat         = IsInCombat
_G._EBS_EvalVisibility   = EvalVisibility
_G._EBS_UpdateVisibility = RequestVisibilityUpdate
-- UpdateVisEventRegistration is a no-op now -- the events are always on,
-- but the overhead is trivial (a handful of rarely-firing events).
_G._EBS_UpdateVisEventRegistration = function() end

-------------------------------------------------------------------------------
--  Multi-Select Visibility Engine
--  The Visibility dropdown is a checklist: one checked item behaves exactly
--  like the legacy single mode (stored in the legacy scalar key, evaluated by
--  the module's existing code, byte-identical); two or more checked condition
--  items store a set in `visibilityModes` and evaluate here.
--
--  Combination semantics: OR within an axis, AND across axes.
--    combat axis:  in_combat / out_of_combat
--    group axis:   in_raid / in_party / solo
--    dragon axis:  show_dragonriding / show_not_dragonriding
--  An axis with none (or all) of its items checked imposes no constraint.
--  Never / Always are exclusive single selections and never appear in a set.
--  Mouseover combines as one more AND gate (hover-gated conditions): the
--  element is hover-revealed while every condition axis passes and hidden
--  outright while any fails. A set containing mouseover stores the scalar
--  "mouseover" as its representative, so every legacy mouseover mechanism
--  (Action Bars' mouseoverEnabled fade, UF hover handlers, the dispatcher
--  poll) engages without per-module rewiring.
-------------------------------------------------------------------------------

EUI.VIS_AXES = {
    combat = { "in_combat", "out_of_combat" },
    group  = { "in_raid", "in_party", "solo" },
    dragon = { "show_dragonriding", "show_not_dragonriding" },
}

-- Shared caps table for Action Bars, CDM, Unit Frames, and Resource Bars.
-- In Party and In Raid Group are disjoint here, same as every other module --
-- checking one does not implicitly check the other. Kept on the namespace so
-- files at the Lua 5.1 200-local cap don't need a new local.
EUI.VIS_CAPS_DEFAULT = { partyIncludesRaid = false }

-- Copy-target caps for elements that cannot express group modes (Pet Bar).
EUI.VIS_CAPS_NO_GROUP = { partyIncludesRaid = false, noGroupModes = true }

-- Canonical priority order for the representative scalar: the single legacy
-- mode written alongside a multi-selection so older addon versions and every
-- existing scalar reader see a sane, user-recognizable value.
local VIS_REPRESENTATIVE_ORDER = {
    "in_combat", "out_of_combat", "in_raid", "in_party", "solo",
    "show_dragonriding", "show_not_dragonriding",
}
local VIS_CONDITION_KEYS = {}
for _, k in ipairs(VIS_REPRESENTATIVE_ORDER) do VIS_CONDITION_KEYS[k] = true end
EUI.VIS_CONDITION_KEYS = VIS_CONDITION_KEYS

-- Keys allowed inside a visibilityModes set: the seven conditions plus
-- mouseover (the hover-gate). Never/Always stay exclusive scalars.
local VIS_COMBINABLE_KEYS = { mouseover = true }
for _, k in ipairs(VIS_REPRESENTATIVE_ORDER) do VIS_COMBINABLE_KEYS[k] = true end
EUI.VIS_COMBINABLE_KEYS = VIS_COMBINABLE_KEYS

-- Airborne skyriding predicate shared by CheckVisibilityMode's dragonriding
-- branches and the multi-select engine. Mirrors the secure driver's
-- [advflyable,flying]: glide capability plus airborne, and nothing else.
-- An IsMounted() term used to sit here, which made every non-secure module
-- disagree with the secure Action Bars driver in a flight form (Druid and
-- Haranir flight forms are shapeshifts, not mounts, so IsMounted() is false
-- while [advflyable] still matches).
function EUI.IsAirborneSkyriding()
    if not (IsFlying and IsFlying()) then return false end
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        return canGlide == true
    end
    -- No capability API to consult: keep the old mounted heuristic rather
    -- than count ordinary (non-skyriding) flight as dragonriding.
    return (IsMounted and IsMounted()) and true or false
end

local function VisRepresentative(modes)
    -- A hover-gated set is represented by "mouseover": downgrades keep the
    -- closest UX (hover-only everywhere), and every legacy scalar reader
    -- (mouseoverEnabled derivation, hover handlers, the poll) engages.
    if modes.mouseover then return "mouseover" end
    for i = 1, #VIS_REPRESENTATIVE_ORDER do
        local k = VIS_REPRESENTATIVE_ORDER[i]
        if modes[k] then return k end
    end
    return nil
end

-- Returns the store's visibilityModes table when it is authoritative, else nil
-- (legacy scalar authoritative). A non-empty set is authoritative only while the
-- legacy scalar still equals its canonical representative: the shared setter always
-- writes the pair together, so a mismatch proves an out-of-band scalar write (e.g. a
-- Visibility change made on an older addon version) that must win. Stale sets are
-- ignored, never wiped -- a transient partial state (profile sync applying keys one
-- by one) heals itself once both keys arrive.
local function ActiveModes(store, legacyKey)
    local vm = store.visibilityModes
    if type(vm) ~= "table" then return nil end
    local rep = VisRepresentative(vm)
    if not rep then return nil end
    local scalar = store[legacyKey]
    if scalar ~= nil and scalar ~= rep then return nil end
    return vm
end

-- Public heal-aware read of the raw set: returns the authoritative
-- visibilityModes table or nil (used by the Action Bars macro compiler).
function EUI.GetActiveVisibilityModes(store, legacyKey)
    if not store then return nil end
    return ActiveModes(store, legacyKey)
end

-- True when the selection can flip purely because combat started or ended.
-- Consumers whose Show()/Hide() is protected need this: those transitions are
-- delivered inside combat lockdown (PLAYER_REGEN_DISABLED already reports
-- InCombatLockdown), so a protected updater has to switch to an unprotected
-- mechanism for them rather than skip the update.
function EUI.VisDependsOnCombat(store, legacyKey)
    if not store then return false end
    local vm = ActiveModes(store, legacyKey)
    if vm then
        return (vm.in_combat or vm.out_of_combat) and true or false
    end
    local scalar = store[legacyKey]
    return scalar == "in_combat" or scalar == "out_of_combat"
end

-- Read view: the current selection as a set (always freshly allocated).
-- Second return is true when a multi-selection is active.
function EUI.GetVisibilitySelection(store, legacyKey)
    local sel = {}
    if not store then sel.always = true; return sel, false end
    local vm = ActiveModes(store, legacyKey)
    if vm then
        for k in pairs(vm) do
            if VIS_COMBINABLE_KEYS[k] then sel[k] = true end
        end
        return sel, true
    end
    sel[store[legacyKey] or "always"] = true
    return sel, false
end

-- The single write path. Normalizes the selection, writes the legacy scalar (via
-- applyScalarFn when the module's scalar write has side effects, e.g. Action Bars'
-- VisibilityCompat.ApplyMode), and assigns or clears visibilityModes. A fresh table is
-- assigned on every multi write (never mutated in place): profile sync, Myslot backups,
-- and spec-override snapshots may hold references to the previous table.
function EUI.SetVisibilitySelection(store, legacyKey, selection, applyScalarFn)
    if not store then return end
    local conditions = {}
    local count = 0
    for i = 1, #VIS_REPRESENTATIVE_ORDER do
        local k = VIS_REPRESENTATIVE_ORDER[i]
        if selection[k] then
            conditions[k] = true
            count = count + 1
        end
    end
    local hasMouseover = selection.mouseover and true or false
    local scalar
    if count == 0 then
        -- Pure special (or empty -> Always). Conditions win over never/always when both
        -- appear; the checklist enforces that on click, this is defense in depth.
        if selection.never then scalar = "never"
        elseif hasMouseover then scalar = "mouseover"
        else scalar = "always" end
    elseif hasMouseover then
        -- Hover-gated conditions: the set carries mouseover alongside the conditions
        -- and the scalar reads "mouseover" so every legacy mouseover mechanism engages.
        conditions.mouseover = true
        scalar = "mouseover"
    else
        scalar = VisRepresentative(conditions)
    end
    if applyScalarFn then
        applyScalarFn(store, scalar)
    else
        store[legacyKey] = scalar
    end
    -- A set is stored for >=2 conditions, or for any condition + mouseover
    -- (which cannot collapse to a single scalar).
    store.visibilityModes = (count >= 2 or (count >= 1 and hasMouseover)) and conditions or nil
    -- Direct belt for the shared Visibility widget: a mouseover-mode edit
    -- must re-arm the scan without waiting for a dispatcher event.
    _moGen = _moGen + 1
end

-- Per-axis verdicts for the three mode axes: (constrained, passed). state = { inCombat,
-- inRaid, inParty }, inParty = party-exclusive-of-raid; caps.partyIncludesRaid widens
-- in_party to raids (no caller sets it). An empty or fully-checked axis is never counted.
-- stopAt "fail" returns at the first failing axis, "any" at the first passing one; the
-- undercounted `constrained` is safe because both callers stop reading it there.
function EUI.TallyVisibilityModeAxes(selection, state, caps, stopAt)
    local incRaid = caps and caps.partyIncludesRaid
    local constrained, passed = 0, 0

    -- Combat axis
    local c1, c2 = selection.in_combat, selection.out_of_combat
    if c1 and not c2 then
        constrained = constrained + 1
        if state.inCombat then passed = passed + 1 end
    elseif c2 and not c1 then
        constrained = constrained + 1
        if not state.inCombat then passed = passed + 1 end
    end

    if stopAt == "fail" and passed < constrained then return constrained, passed end
    if stopAt == "any" and passed > 0 then return constrained, passed end

    -- Group axis (the three items are ONE axis, OR'd together)
    local g1, g2, g3 = selection.in_raid, selection.in_party, selection.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        constrained = constrained + 1
        local pass = false
        if g1 and state.inRaid then pass = true end
        if not pass and g2 and (state.inParty or (incRaid and state.inRaid)) then pass = true end
        if not pass and g3 and not state.inRaid and not state.inParty then pass = true end
        if pass then passed = passed + 1 end
    end

    if stopAt == "fail" and passed < constrained then return constrained, passed end
    if stopAt == "any" and passed > 0 then return constrained, passed end

    -- Dragonriding axis
    local d1, d2 = selection.show_dragonriding, selection.show_not_dragonriding
    if (d1 or d2) and not (d1 and d2) then
        constrained = constrained + 1
        local dr = EUI.IsAirborneSkyriding()
        if (d1 and dr) or (d2 and not dr) then passed = passed + 1 end
    end

    return constrained, passed
end

-- Default "all" match: every constrained axis has to pass. Public entry point (other
-- files evaluate mode sets with it).
function EUI.EvalVisibilityModes(selection, state, caps)
    local constrained, passed = EUI.TallyVisibilityModeAxes(selection, state, caps, "fail")
    return constrained == passed
end

-- Module-facing dispatcher. Returns a value when the multi-select engine
-- owns the decision -- an authoritative visibilityModes set, or a
-- dragonriding scalar (so both dragonriding modes work in every module
-- through this one path) -- or nil when the caller's legacy evaluation
-- should run untouched, byte-identical. Owned results:
--   true        show
--   false       hide
--   "mouseover" hover-gated: conditions pass, reveal on hover only (the
--               caller's existing mouseover mechanism does the revealing;
--               a failing set returns plain false, hover included)
local _dispatchState = {}  -- reused; filled per call when no state is passed

local function FillDispatchState()
    local inRaid = IsInRaid()
    _dispatchState.inCombat = _inCombat
    _dispatchState.inRaid = inRaid
    _dispatchState.inParty = IsInGroup() and not inRaid
    return _dispatchState
end

-- Any match: every constrained axis is a disjunct; mode axes and option lanes tally
-- TOGETHER (CheckVisibilityOptions steps aside for such a store). _anySel is a reused
-- scalar view so a single stored mode costs no allocation per dispatcher event.
local _anySel, _anySelKey = {}, nil

local function EvalAnyMatch(store, legacyKey, vm, state, caps)
    local sel = vm
    if not sel then
        if _anySelKey then _anySel[_anySelKey] = nil end
        _anySelKey = store[legacyKey] or "always"
        _anySel[_anySelKey] = true
        sel = _anySel
    end
    -- Never stays terminal: an exclusive scalar is not an axis, so no other lane can
    -- out-vote it.
    if sel.never then return false end
    state = state or FillDispatchState()
    local constrained, passed = EUI.TallyVisibilityModeAxes(sel, state, caps, "any")
    -- One passing disjunct settles it; the option probes (instance, housing, the druid
    -- form walk) only run when no mode axis passed.
    if passed == 0 and EUI.TallyVisibilityOptionAxes then
        local optC, optP = EUI.TallyVisibilityOptionAxes(store)
        constrained, passed = constrained + optC, passed + optP
    end
    -- Nothing constrained at all reads as Always, exactly as it does under All.
    local pass = (constrained == 0) or (passed > 0)
    if sel.mouseover then
        return pass and "mouseover" or false
    end
    return pass
end

function EUI.EvalVisibilityExtended(store, legacyKey, state, caps)
    if not store then return nil end
    local vm = ActiveModes(store, legacyKey)
    -- Any owns the whole verdict (option lanes included, even with no mode set). The one
    -- case handed back is a legacy ORPHAN scalar: the caller's chain resolves the mode
    -- and the option lanes stop applying; the Visibility row locks Match Mode while an
    -- orphan is stored so that state is unreachable from the UI.
    if store.visibilityMatch == "any" then
        local scalar = store[legacyKey]
        if vm or scalar == nil or VIS_CONDITION_KEYS[scalar]
            or scalar == "never" or scalar == "always" or scalar == "mouseover" then
            return EvalAnyMatch(store, legacyKey, vm, state, caps)
        end
    end
    if not vm then
        local scalar = store[legacyKey]
        if scalar == "show_dragonriding" then
            return EUI.IsAirborneSkyriding()
        elseif scalar == "show_not_dragonriding" then
            return not EUI.IsAirborneSkyriding()
        end
        return nil
    end
    state = state or FillDispatchState()
    local pass = EUI.EvalVisibilityModes(vm, state, caps)
    if vm.mouseover then
        return pass and "mouseover" or false
    end
    return pass
end

-- Hover-eligibility for the mouseover poll and hover handlers: true when
-- the element should currently reveal on hover. Legacy single "mouseover"
-- keeps its historical behavior (scalar check only); a hover-gated set
-- additionally requires its condition axes to pass right now.
function EUI.VisWantsMouseover(store, legacyKey, state, caps)
    if not store then return false end
    -- Under Any the hover gate arms only while the disjunction (option lanes included)
    -- passes, so the verdict comes from the one evaluator that sees both halves.
    if store.visibilityMatch == "any" then
        return EUI.EvalVisibilityExtended(store, legacyKey, state, caps) == "mouseover"
    end
    local vm = ActiveModes(store, legacyKey)
    if vm then
        if not vm.mouseover then return false end
        return EUI.EvalVisibilityExtended(store, legacyKey, state, caps) == "mouseover"
    end
    return store[legacyKey] == "mouseover"
end

-- Set-aware equality for the sync icons: compares the effective selection of
-- two stores (multi set vs multi set, else scalar vs scalar).
function EUI.VisSelectionEquals(a, aKey, b, bKey)
    if not a or not b then return false end
    if (a.visibilityMatch == "any") ~= (b.visibilityMatch == "any") then return false end
    local ma = ActiveModes(a, aKey)
    local mb = ActiveModes(b, bKey)
    if ma or mb then
        if not (ma and mb) then return false end
        for k in pairs(ma) do
            if VIS_COMBINABLE_KEYS[k] and not mb[k] then return false end
        end
        for k in pairs(mb) do
            if VIS_COMBINABLE_KEYS[k] and not ma[k] then return false end
        end
        return true
    end
    return (a[aKey] or "always") == (b[bKey] or "always")
end

-------------------------------------------------------------------------------
--  Secure driver compiler
--  Compiles a set into macro-conditional grammar (comma = AND inside a
--  bracket, bracket groups = OR) for RegisterAttributeDriver
--  "state-visibility" drivers. Shared by the Action Bars drivers and the
--  Unit Frames condition drivers.
-------------------------------------------------------------------------------

-- Returns the AND-term string shared by every bracket group (with trailing comma, or
-- "") plus the leading unconditional hide gate used for a lone negated dragon axis (""
-- when unused; the same technique the callers' hide-prefix gates already use -- no
-- negated-flying tokens needed). Non-axis keys (mouseover) are ignored. OR within an
-- axis, AND across axes; a saturated or empty axis contributes nothing.
function EUI.BuildVisModeConjuncts(vm)
    local conj, negGate = "", ""
    local d1, d2 = vm.show_dragonriding, vm.show_not_dragonriding
    if d1 and not d2 then
        conj = conj .. "advflyable,flying,"
    elseif d2 and not d1 then
        negGate = "[advflyable,flying] hide; "
    end
    local c1, c2 = vm.in_combat, vm.out_of_combat
    if c1 and not c2 then
        conj = conj .. "combat,"
    elseif c2 and not c1 then
        conj = conj .. "nocombat,"
    end
    return conj, negGate
end

-- Compiles the driver tail appended after `prefix` (caller-supplied leading hide gates:
-- unit existence, pet battle, vehicle, option clauses...). Group-axis disjuncts
-- distribute into separate bracket groups, each carrying the shared AND terms. in_raid
-- and in_party are disjoint -- checking In Party alone does not also show in a raid
-- group; In Raid Group must be checked separately for that.
function EUI.BuildVisibilityDriverString(prefix, vm)
    local conj, negGate = EUI.BuildVisModeConjuncts(vm)
    prefix = prefix .. negGate

    local g1, g2, g3 = vm.in_raid, vm.in_party, vm.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        local out = prefix
        local emitted = {}
        local function emit(tok)
            if emitted[tok] then return end
            emitted[tok] = true
            out = out .. "[" .. conj .. tok .. "] show; "
        end
        if g1 then emit("group:raid") end
        -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows the
        -- party disjunct to a real party (a separate group:raid clause, when
        -- In Raid Group is also checked, still shows there).
        if g2 then emit("group:party,nogroup:raid") end
        if g3 then emit("nogroup") end
        return out .. "hide"
    end

    if conj == "" then
        -- All axes saturated/empty: Always-equivalent (negGate, when
        -- present, still hides while dragonriding).
        return prefix .. "show"
    end
    return prefix .. "[" .. conj:sub(1, -2) .. "] show; hide"
end

-- Any-match tail: one bracket group per constrained axis (adjacent groups OR in macro
-- grammar). `opts` = the option lanes the driver can express (Lua-only ones are the
-- caller's); `wrap` = tokens every bracket must carry (Pet Bar); `extraConstrained` =
-- axes decided outside this string, so a Lua-only-constrained selection compiles to hide.
function EUI.BuildVisibilityDriverStringAny(prefix, vm, opts, extraConstrained, wrap)
    vm, opts, wrap = vm or {}, opts or {}, wrap or ""
    local lead = (wrap ~= "") and (wrap .. ",") or ""
    local out, axes = "", 0
    local emitted = {}
    local function emit(tok)
        if emitted[tok] then return end
        emitted[tok] = true
        out = out .. "[" .. lead .. tok .. "] show; "
    end

    -- Combat axis
    local c1, c2 = vm.in_combat, vm.out_of_combat
    if c1 and not c2 then
        axes = axes + 1; emit("combat")
    elseif c2 and not c1 then
        axes = axes + 1; emit("nocombat")
    end

    -- Group axis: three items, ONE axis, already OR'd among themselves.
    local g1, g2, g3 = vm.in_raid, vm.in_party, vm.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        axes = axes + 1
        if g1 then emit("group:raid") end
        -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows the party
        -- disjunct to a real party, same as the all-match tail does.
        if g2 then emit("group:party,nogroup:raid") end
        if g3 then emit("nogroup") end
    end

    -- Option axes with a macro conditional of their own.
    if opts.visOnlyMounted and not opts.visHideMounted then
        axes = axes + 1; emit("mounted")
    elseif opts.visHideMounted and not opts.visOnlyMounted then
        axes = axes + 1; emit("nomounted")
    end
    if opts.visHideNoTarget and not opts.visHideWithTarget then
        axes = axes + 1; emit("exists")
    elseif opts.visHideWithTarget and not opts.visHideNoTarget then
        axes = axes + 1; emit("noexists")
    end
    if opts.visHideNoEnemy and not opts.visHideWithEnemy then
        axes = axes + 1; emit("harm")
    elseif opts.visHideWithEnemy and not opts.visHideNoEnemy then
        axes = axes + 1; emit("noharm")
    end

    -- Dragonriding axis. NOT(advflyable AND flying) has no single bracket form, so the
    -- negative lane becomes the TAIL: once no other disjunct matched, hide while
    -- airborne, show otherwise (first matching clause wins).
    local d1, d2 = vm.show_dragonriding, vm.show_not_dragonriding
    local dragonTail = false
    if d1 and not d2 then
        axes = axes + 1; emit("advflyable,flying")
    elseif d2 and not d1 then
        axes = axes + 1; dragonTail = true
    end

    local wrappedShow = (wrap ~= "") and ("[" .. wrap .. "] show; hide") or "show"
    if axes == 0 then
        -- Nothing this string can decide: either nothing is constrained anywhere
        -- (Always), or the only constrained axes are Lua-only ones that all failed.
        if (extraConstrained or 0) > 0 then return prefix .. "hide", 0 end
        return prefix .. wrappedShow, 0
    end
    if dragonTail then
        return prefix .. out .. "[" .. lead .. "advflyable,flying] hide; " .. wrappedShow, axes
    end
    return prefix .. out .. "hide", axes
end

-- Two macro tokens disagree with their Lua probe: [exists] counts a soft target and
-- [mounted] cannot see druid travel/flight forms. Under Any a veto would silence the
-- other axes, so the fix is per axis: a token that would wrongly PASS has its disjunct
-- dropped, one that would wrongly FAIL shows outright. Each probe runs only when its
-- own lanes are set (the mount one walks the druid form auras).
local function AnyDriverLaneFixups(store, edges)
    local drop, forceShow = nil, false

    local wantsTarget = (edges and edges.softTarget)
        and (store.visHideNoTarget or store.visHideWithTarget)
    if wantsTarget then
        local softOnly = not UnitExists("target")
            and (UnitExists("softinteract") or UnitExists("softenemy") or UnitExists("softfriend"))
        if softOnly then
            -- Show lane: [exists] would show on the soft target the probe does not count.
            if store.visHideNoTarget and not store.visHideWithTarget then
                drop = { visHideNoTarget = true }
            -- Hide lane: [noexists] stays false, but "no target" is true to the probe.
            elseif store.visHideWithTarget and not store.visHideNoTarget then
                forceShow = true
            end
        end
    end

    if store.visOnlyMounted or store.visHideMounted then
        local formOnly = not (IsMounted and IsMounted())
            and EUI.IsPlayerMountedLike and EUI.IsPlayerMountedLike()
        if formOnly then
            -- Show lane: [mounted] misses the form the probe counts as mounted.
            if store.visOnlyMounted and not store.visHideMounted then
                forceShow = true
            -- Hide lane: [nomounted] would show while the probe says mounted.
            elseif store.visHideMounted and not store.visOnlyMounted then
                drop = drop or {}
                drop.visHideMounted = true
            end
        end
    end

    return drop, forceShow
end

-- Store -> Any-match driver tail, shared by Action Bars, Unit Frames and the Minimap.
-- Returns tail, constrained (a LOWER BOUND: the early-outs stop counting once settled)
-- and liveAxes (axes that are LIVE macro terms in `tail`; 0 for a constant). A
-- driver-registering caller gates on liveAxes: constrained can be positive purely from
-- Lua-resolved axes, which a driver could never keep honest.
function EUI.BuildAnyMatchTail(store, legacyKey, vm, wrap, edges)
    wrap = wrap or ""
    local wrappedShow = (wrap ~= "") and ("[" .. wrap .. "] show; hide") or "show"
    -- Never is an exclusive scalar, not an axis, so nothing can out-vote it.
    if (store[legacyKey] or "always") == "never" then return "hide", 1, 0 end

    local luaC, luaP = 0, 0
    if EUI.TallyVisibilityOptionAxes then
        luaC, luaP = EUI.TallyVisibilityOptionAxes(store, "luaOnly", edges)
    end
    -- Settled before the fixups run: their probes are the expensive ones.
    if luaP > 0 then return wrappedShow, luaC, 0 end

    local drop, forceShow = AnyDriverLaneFixups(store, edges)
    -- A driver axis whose token cannot see what the probe sees; it is not in luaC.
    if forceShow then return wrappedShow, luaC + 1, 0 end

    local modes = vm
    if not modes then
        -- A single stored mode is one constrained axis, the shape a set would have.
        modes = {}
        local scalar = store[legacyKey]
        if VIS_CONDITION_KEYS[scalar] then modes[scalar] = true end
    end
    -- The compiler sees only the lanes THIS consumer compiles: Lua-resolved axes are
    -- already in luaC, dropped ones still count as constrained but cannot be disjuncts.
    local axisList = EUI.VIS_OPT_AXES
    local needsFilter = drop ~= nil
    if not needsFilter and axisList then
        for i = 1, #axisList do
            if EUI.VisAxisIsLuaOnly(axisList[i], edges) then needsFilter = true; break end
        end
    end
    local opts, dropped = store, 0
    if needsFilter then
        opts = {}
        for i = 1, #axisList do
            local ax = axisList[i]
            if not EUI.VisAxisIsLuaOnly(ax, edges) then
                if drop and (drop[ax.show] or drop[ax.hide]) then
                    dropped = dropped + 1
                else
                    opts[ax.show] = store[ax.show]
                    opts[ax.hide] = store[ax.hide]
                end
            end
        end
    end
    local tail, axes = EUI.BuildVisibilityDriverStringAny("", modes, opts, luaC + dropped, wrap)
    return tail, axes + luaC + dropped, axes
end

-- Set-aware copy for the sync icons. dstCaps.noGroupModes strips group-axis
-- items the target cannot express (Pet Bar); the stripped selection
-- re-normalizes through the setter (a now-single selection collapses to the
-- scalar, a now-empty one becomes Always). applyScalarFn runs the target
-- module's scalar side effects, same contract as SetVisibilitySelection.
function EUI.VisCopySelection(dst, src, legacyKey, dstCaps, applyScalarFn)
    if not dst or not src then return end
    -- The match travels with every copy, mode-only ones included.
    dst.visibilityMatch = (src.visibilityMatch == "any") and "any" or nil
    local ms = ActiveModes(src, legacyKey)
    if ms then
        local sel = {}
        for k in pairs(ms) do
            if VIS_COMBINABLE_KEYS[k] then sel[k] = true end
        end
        if dstCaps and dstCaps.noGroupModes then
            sel.in_raid, sel.in_party, sel.solo = nil, nil, nil
        end
        if dstCaps and dstCaps.noMouseover then
            sel.mouseover = nil
        end
        EUI.SetVisibilitySelection(dst, legacyKey, sel, applyScalarFn)
        return
    end
    -- Legacy single value: copy the raw scalar (orphan values included,
    -- matching the pre-rework copy behavior) and clear any stale set.
    local scalar = src[legacyKey] or "always"
    if applyScalarFn then
        applyScalarFn(dst, scalar)
    else
        dst[legacyKey] = scalar
    end
    dst.visibilityModes = nil
end

-- The unified Visibility row puts the mode selection and the option booleans behind
-- ONE control, so its sync icon copies and compares both halves at once. These two
-- wrap the existing mode-only pair; callers that still build the legacy two-dropdown
-- layout keep using VisCopySelection / VisSelectionEquals with their own option loop.
function EUI.VisFullCopy(dst, src, legacyKey, dstCaps, applyScalarFn)
    if not dst or not src then return end
    EUI.VisCopySelection(dst, src, legacyKey, dstCaps, applyScalarFn)
    local keys = EUI.VIS_OPT_KEYS
    if not keys then return end
    for i = 1, #keys do
        local k = keys[i]
        dst[k] = src[k] or nil
    end
end

-- True when the store has ANY visibility option lane set. Callers gate work on this:
-- event passes that would otherwise be skipped, hover keep-shown, drag surfacing. A
-- hand-written subset here is exactly how a newly added lane silently stops working, so
-- this always walks VIS_OPT_KEYS rather than naming fields.
function EUI.VisHasAnyOption(store)
    if not store then return false end
    local keys = EUI.VIS_OPT_KEYS
    if not keys then return false end
    for i = 1, #keys do
        if store[keys[i]] then return true end
    end
    return false
end

function EUI.VisFullEquals(a, aKey, b, bKey)
    if not a or not b then return false end
    if not EUI.VisSelectionEquals(a, aKey, b, bKey) then return false end
    local keys = EUI.VIS_OPT_KEYS
    if not keys then return true end
    for i = 1, #keys do
        local k = keys[i]
        if (a[k] or false) ~= (b[k] or false) then return false end
    end
    return true
end
