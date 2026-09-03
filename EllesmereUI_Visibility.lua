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
    -- Under Any, EvalVisibilityExtended owns the whole verdict, the option HIDE veto
    -- included, so asking CheckVisibilityOptions first re-ran every set lane's probe (the
    -- instance lookup, IsResting, the druid aura walk) once per updater per dispatcher
    -- event for no second opinion. Under All the veto still has to LEAD: the mode engine
    -- knows nothing about option lanes there, so a passing set must not settle it.
    -- A nil result under Any is the legacy-ORPHAN hand-back, and that case drops through
    -- to exactly the chain an All store takes, veto included.
    local ext
    if cfg.visibilityMatch == "any" then
        ext = EUI.EvalVisibilityExtended and EUI.EvalVisibilityExtended(cfg, "visibility", nil, DISPATCHER_CAPS)
        if ext ~= nil then return ext end
    end
    if EUI.CheckVisibilityOptions and EUI.CheckVisibilityOptions(cfg) then
        return false
    end
    ext = EUI.EvalVisibilityExtended and EUI.EvalVisibilityExtended(cfg, "visibility", nil, DISPATCHER_CAPS)
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
-- Resting edge: IsResting() itself has no dedicated poll, so without this the Resting
-- checklist row only re-evaluates when some unrelated event (mount/zone/combat) happens
-- to fire the dispatcher afterward -- e.g. it looked "bound to landing" because dismounting
-- fires PLAYER_MOUNT_DISPLAY_CHANGED, not because resting is actually tied to mounting.
visFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
-- Vehicle edges: same reasoning as Resting -- the In Vehicle axis needs its
-- own edge or it only re-evaluates on incidental traffic. Player-filtered:
-- other units' vehicle changes are irrelevant to these axes.
visFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
visFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
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
--  Mouseover under All is one more AND gate (hover-gated conditions): the
--  element is hover-revealed while every condition axis passes and hidden
--  outright while any fails. Under Any it is a disjunct of its own instead: a
--  passing condition shows the element outright, and hover stays available when
--  none passes. A set containing mouseover stores the scalar "mouseover" as its
--  representative, so every legacy mouseover mechanism (Action Bars' fade, UF
--  hover handlers, the dispatcher poll) engages without per-module rewiring.
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

-- Mode-row axes: one entry per condition ROW of the shared Visibility checklist, the
-- mirror of EllesmereUI.VIS_OPT_AXES for the option rows. show = the key that acts as a
-- conjunct under All and a disjunct under Any; hide = the veto key, which hides whenever
-- the row's condition holds, in EVERY match mode; token = the macro conditional that is
-- true while the condition holds, so a hide gate compiles to "[token] hide"; probe = the
-- same answer in Lua. luaOnly = no positive bracket form exists, so a driver-building
-- caller has to resolve the veto in Lua. combatFlip = the probe can change INSIDE combat,
-- where a driver can no longer be rewritten. group = part of the three-way group row set.
EUI.VIS_MODE_AXES = {
    { show = "in_combat", hide = "hide_in_combat", token = "combat",
      probe = function(state) return state.inCombat and true or false end },
    { show = "out_of_combat", hide = "hide_out_of_combat", token = "nocombat",
      probe = function(state) return not state.inCombat end },
    { show = "in_raid", hide = "hide_in_raid", token = "group:raid", group = true,
      probe = function(state) return state.inRaid and true or false end },
    -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows it to a real party,
    -- exactly as the driver compilers below do for the show lane.
    { show = "in_party", hide = "hide_in_party", token = "group:party,nogroup:raid", group = true,
      probe = function(state, caps)
          if state.inParty then return true end
          return (caps and caps.partyIncludesRaid and state.inRaid) and true or false
      end },
    { show = "solo", hide = "hide_solo", token = "nogroup", group = true,
      probe = function(state) return not state.inRaid and not state.inParty end },
    { show = "show_dragonriding", hide = "hide_dragonriding", token = "advflyable,flying",
      combatFlip = true,
      probe = function() return EUI.IsAirborneSkyriding() end },
    -- NOT(advflyable AND flying) has no single positive bracket, so this veto is the one
    -- mode lane a secure driver cannot carry; it is resolved in Lua at build time.
    -- Under Match ANY only, that means the combat escape hatch: entering combat on the
    -- ground reveals the element until the next out-of-combat rebuild. Under All it folds
    -- into an "advflyable,flying," conjunct and stays live, as does the same intent
    -- written as Show on Skyriding (Airborne). A gate would need a two-bracket clause
    -- ("[noadvflyable][noflying] hide; ") rather than the single `token` here, and whether
    -- [noadvflyable] parses is NOT established: macro conditionals are C-side and in no
    -- Lua source. Confirm it in game before widening this on the assumption alone.
    { show = "show_not_dragonriding", hide = "hide_not_dragonriding", luaOnly = true,
      combatFlip = true,
      probe = function() return not EUI.IsAirborneSkyriding() end },
}

-- The seven hide keys as a flat list for the set walks below, and as a lookup for
-- callers that have to tell a veto lane from a show lane (the options checklist).
local VIS_MODE_HIDE = {}
EUI.VIS_MODE_HIDE_KEYS = {}
for i = 1, #EUI.VIS_MODE_AXES do
    VIS_MODE_HIDE[i] = EUI.VIS_MODE_AXES[i].hide
    EUI.VIS_MODE_HIDE_KEYS[VIS_MODE_HIDE[i]] = true
end

-- Keys allowed inside a visibilityModes set: the seven conditions, their seven hide
-- lanes, plus mouseover (the hover-gate). Never/Always stay exclusive scalars. Hide keys
-- deliberately stay out of VIS_CONDITION_KEYS / VIS_REPRESENTATIVE_ORDER: a veto lane has
-- no legacy scalar representation, so it can only ever live inside a stored set.
local VIS_COMBINABLE_KEYS = { mouseover = true }
for _, k in ipairs(VIS_REPRESENTATIVE_ORDER) do VIS_COMBINABLE_KEYS[k] = true end
for i = 1, #VIS_MODE_HIDE do VIS_COMBINABLE_KEYS[VIS_MODE_HIDE[i]] = true end
EUI.VIS_COMBINABLE_KEYS = VIS_COMBINABLE_KEYS

-- An override session can only carry one of the three EXCLUSIVE states, and it
-- REPLACES the element's whole Visibility configuration instead of merging with it:
-- while this key holds a value, the legacy scalar, the mode set, the match mode and
-- every option lane are ignored. Absent -- every normal profile -- it changes nothing.
-- A plain scalar on purpose, so the override value system captures and restores it
-- like any other setting, and clearing it is an ordinary revert.
local VIS_OVERRIDE_VALUES = { never = true, always = true, mouseover = true }

function EUI.VisOverrideValue(store)
    if not store then return nil end
    local v = store.visibilityOverride
    return VIS_OVERRIDE_VALUES[v] and v or nil
end

-- Same validation for a caller holding the raw value rather than the store: the options
-- row reads it through the module's own fan-out hooks (Resource Bars mirrors one control
-- onto three bar stores), which hand back a value, not a table.
function EUI.VisOverrideNormalize(v)
    return VIS_OVERRIDE_VALUES[v] and v or nil
end

-- True when the set carries at least one mode hide lane.
local function VisHasModeHide(vm)
    for i = 1, #VIS_MODE_HIDE do
        if vm[VIS_MODE_HIDE[i]] then return true end
    end
    return false
end

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
-- ignoreOverride: read the SHARED selection even while an override applies. The options
-- checklist, the sync-icon compare and the sync copy all edit or compare the shared value
-- (the override is a separate marker they never touch), so hiding the set from them made
-- the row render a bare scalar and the next click write that rump back over the stored
-- set. Evaluators and driver compilers pass nothing and keep the replacing behaviour.
local function ActiveModes(store, legacyKey, ignoreOverride)
    -- An override replaces the whole configuration, the stored set included.
    if not ignoreOverride and EUI.VisOverrideValue(store) then return nil end
    local vm = store.visibilityModes
    if type(vm) ~= "table" then return nil end
    local rep = VisRepresentative(vm)
    local scalar = store[legacyKey]
    if not rep then
        -- Hide-only set: a veto lane has no scalar of its own, so the pair the setter
        -- writes is "always" plus the set. The heal rule still applies -- any other
        -- scalar proves an out-of-band write that must win.
        if not VisHasModeHide(vm) then return nil end
        if scalar ~= nil and scalar ~= "always" then return nil end
        return vm
    end
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
    -- None of the three override states can flip on a combat edge.
    if EUI.VisOverrideValue(store) then return false end
    local vm = ActiveModes(store, legacyKey)
    if vm then
        return (vm.in_combat or vm.out_of_combat
            or vm.hide_in_combat or vm.hide_out_of_combat) and true or false
    end
    local scalar = store[legacyKey]
    return scalar == "in_combat" or scalar == "out_of_combat"
end

-- Read view: the current selection as a set (always freshly allocated).
-- Second return is true when a multi-selection is active. ignoreOverride: see ActiveModes
-- -- the options row passes it, because it edits the shared value an override replaces.
function EUI.GetVisibilitySelection(store, legacyKey, ignoreOverride)
    local sel = {}
    if not store then sel.always = true; return sel, false end
    local vm = ActiveModes(store, legacyKey, ignoreOverride)
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
    -- Hide lanes ride along in the same set. They never contribute to `count`: that
    -- counts the keys a scalar could represent, and a veto lane cannot be one.
    local hideCount = 0
    for i = 1, #VIS_MODE_HIDE do
        local k = VIS_MODE_HIDE[i]
        if selection[k] then
            conditions[k] = true
            hideCount = hideCount + 1
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
        scalar = "mouseover"
    else
        scalar = VisRepresentative(conditions)
    end
    -- Whenever the scalar reads "mouseover" the set has to carry it too, or the pair
    -- would not match and ActiveModes would drop the set, hide lanes included.
    if scalar == "mouseover" then conditions.mouseover = true end
    if applyScalarFn then
        applyScalarFn(store, scalar)
    else
        store[legacyKey] = scalar
    end
    -- A set is stored for >=2 conditions, for any condition + mouseover (which cannot
    -- collapse to a single scalar), and for any hide lane (which has no scalar at all).
    -- Never is terminal, so nothing is stored alongside it.
    local storeSet = scalar ~= "never"
        and (count >= 2 or (count >= 1 and hasMouseover) or hideCount >= 1)
    store.visibilityModes = storeSet and conditions or nil
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
    -- A checked Hide lane vetoes in every match mode. Under All that is equivalent to the
    -- AND-conjunct of the negated condition the tally already computes for the opposite
    -- SHOW key, so selections without hide lanes -- every pre-existing one -- are
    -- unaffected by this gate.
    if EUI.VisModeHideVeto(selection, state, caps) then return false end
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

-- Hide-lane veto for the mode rows, the mirror of EllesmereUI.VisOptionHideVeto for the
-- option rows: Match Mode governs how the SHOW side combines, a checked Hide lane always
-- hides. filter: nil walks every axis, "luaOnly" only the ones a secure driver cannot
-- express, "driver" only the ones it can. Both lanes of one row checked counts as
-- unconstrained, the same rule the option tally uses. Second return: the firing axis is
-- combatFlip, so a driver-building caller must bake a combat escape hatch.
function EUI.VisModeHideVeto(sel, state, caps, filter)
    if not sel then return false end
    local axes = EUI.VIS_MODE_AXES
    for i = 1, #axes do
        local ax = axes[i]
        local skip = (filter == "luaOnly" and not ax.luaOnly)
                  or (filter == "driver" and ax.luaOnly)
        if not skip and sel[ax.hide] and not sel[ax.show] then
            state = state or FillDispatchState()
            if ax.probe(state, caps) then return true, ax.combatFlip or false end
        end
    end
    return false
end

-- Any match: every constrained axis is a disjunct; mode axes and option SHOW lanes tally
-- TOGETHER (CheckVisibilityOptions steps aside for such a store, except for its hide
-- veto). _anySel is a reused scalar view so a single stored mode costs no allocation per
-- dispatcher event.
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
    -- So is a firing Hide lane: the match mode governs how the SHOW side combines, a
    -- Hide lane always hides. Mouseover included -- a hover must not reveal what a Hide
    -- lane hid (same rule as UF-3 in VisibilityCombineOr_MasterBriefing.md).
    if EUI.VisOptionHideVeto and EUI.VisOptionHideVeto(store) then return false end
    state = state or FillDispatchState()
    -- Same rule for the mode rows' Hide lanes.
    if EUI.VisModeHideVeto(sel, state, caps) then return false end
    local constrained, passed = EUI.TallyVisibilityModeAxes(sel, state, caps, "any")
    -- One passing disjunct settles it; the option probes (instance, housing, the druid
    -- form walk) only run when no mode axis passed.
    if passed == 0 and EUI.TallyVisibilityOptionAxes then
        local optC, optP = EUI.TallyVisibilityOptionAxes(store)
        constrained, passed = constrained + optC, passed + optP
    end
    -- Nothing constrained at all reads as Always, exactly as it does under All.
    local pass = (constrained == 0) or (passed > 0)
    -- Mouseover is a disjunct in its own right under Any, not a gate on top of the
    -- others: a passing condition shows outright (no hover needed), and a set that
    -- constrains nothing but mouseover -- or whose other conditions all fail -- stays
    -- hover-revealable instead of hiding outright.
    if sel.mouseover then
        return (passed > 0) and true or "mouseover"
    end
    return pass
end

function EUI.EvalVisibilityExtended(store, legacyKey, state, caps)
    if not store then return nil end
    -- An applied override settles it alone: this is the one path every Lua consumer
    -- runs through, so the three states reach all of them without a per-module edit.
    local ov = EUI.VisOverrideValue(store)
    if ov then
        if ov == "never" then return false end
        if ov == "mouseover" then return "mouseover" end
        return true
    end
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
    local ov = EUI.VisOverrideValue(store)
    if ov then return ov == "mouseover" end
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
-- two stores (multi set vs multi set, else scalar vs scalar). The SHARED selection on
-- both sides (ignoreOverride): the icon reports whether the copy would make them equal,
-- and a copy carries the shared value, never the per-spec override marker.
function EUI.VisSelectionEquals(a, aKey, b, bKey)
    if not a or not b then return false end
    if (a.visibilityMatch == "any") ~= (b.visibilityMatch == "any") then return false end
    local ma = ActiveModes(a, aKey, true)
    local mb = ActiveModes(b, bKey, true)
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
    -- Hide lanes are vetoes, but under All a veto is exactly the AND-conjunct of the
    -- negated condition, so each one folds into the term its opposite SHOW lane already
    -- emits instead of needing a gate of its own. A lane whose OWN row also has its Show
    -- box set is skipped, the same rule VisModeHideVeto applies, so the two never fold
    -- into a term the Lua verdict does not agree with.
    local hc1 = vm.hide_in_combat and not vm.in_combat
    local hc2 = vm.hide_out_of_combat and not vm.out_of_combat
    local hd1 = vm.hide_dragonriding and not vm.show_dragonriding
    local hd2 = vm.hide_not_dragonriding and not vm.show_not_dragonriding
    -- Both Hide lanes of one axis: every state is vetoed. Folding them would cancel out
    -- and read as a saturated (unconstrained) axis, while the Lua veto hides everywhere.
    -- An unconditional leading clause is the honest compilation; both compilers prepend
    -- negGate, so it wins as the first matching clause.
    if (hc1 and hc2) or (hd1 and hd2) then return "", "hide; " end
    local d1 = vm.show_dragonriding or hd2
    local d2 = vm.show_not_dragonriding or hd1
    if d1 and not d2 then
        conj = conj .. "advflyable,flying,"
    elseif d2 and not d1 then
        negGate = "[advflyable,flying] hide; "
    end
    local c1 = vm.in_combat or hc2
    local c2 = vm.out_of_combat or hc1
    if c1 and not c2 then
        conj = conj .. "combat,"
    elseif c2 and not c1 then
        conj = conj .. "nocombat,"
    end
    return conj, negGate
end

-- Leading hide gates for the macro-expressible mode Hide lanes, the mirror of
-- BuildVisOptHideGates below. `which` = "group" limits the walk to the three group rows,
-- which is all the All-match compiler needs (it folds the combat and dragon lanes into
-- its conjuncts above). The luaOnly lane has no token and is never emitted here.
-- Returns the gate string and how many gates it holds.
function EUI.BuildVisModeHideGates(vm, which)
    local out, n = "", 0
    local axes = EUI.VIS_MODE_AXES
    for i = 1, #axes do
        local ax = axes[i]
        if ax.token and (which ~= "group" or ax.group)
            and vm[ax.hide] and not vm[ax.show] then
            out = out .. "[" .. ax.token .. "] hide; "
            n = n + 1
        end
    end
    return out, n
end

-- Compiles the driver tail appended after `prefix` (caller-supplied leading hide gates:
-- unit existence, pet battle, vehicle, option clauses...). Group-axis disjuncts
-- distribute into separate bracket groups, each carrying the shared AND terms. in_raid
-- and in_party are disjoint -- checking In Party alone does not also show in a raid
-- group; In Raid Group must be checked separately for that.
function EUI.BuildVisibilityDriverString(prefix, vm)
    local conj, negGate = EUI.BuildVisModeConjuncts(vm)
    -- The group rows' Hide lanes cannot fold into `conj` (their show side distributes
    -- into separate bracket groups), so they lead as gates. Under All that is the same
    -- verdict either way -- a hide clause and an AND term both veto.
    prefix = prefix .. negGate .. EUI.BuildVisModeHideGates(vm, "group")

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
-- `hasMouseover` = the selection also carries the hover-gate: this compiler cannot
-- express mouseover as a macro token, so every branch that would otherwise HIDE the
-- frame outright falls back to showing it instead -- a hard-hidden secure frame can
-- never be revealed again by the unprotected Lua hover poll. The alpha layer (outside
-- this compiler) is what actually decides full opacity vs. hover-gated 0 from there.
function EUI.BuildVisibilityDriverStringAny(prefix, vm, opts, extraConstrained, wrap, hasMouseover, forceShow)
    vm, opts, wrap = vm or {}, opts or {}, wrap or ""
    local lead = (wrap ~= "") and (wrap .. ",") or ""
    local out, axes = "", 0
    -- Hide lanes are vetoes, not disjuncts: they lead the whole string. Mode rows and
    -- option rows follow the same rule, so both gate sets are emitted here.
    local modeGates, modeGateCount = EUI.BuildVisModeHideGates(vm)
    local gates, gateCount = EUI.BuildVisOptHideGates(opts)
    prefix = prefix .. modeGates .. gates
    gateCount = gateCount + modeGateCount
    -- A show lane whose macro token cannot see what its probe sees (druid travel form vs.
    -- [mounted]): the disjunction is settled, but the gates above still apply.
    if forceShow then
        return prefix .. ((wrap ~= "") and ("[" .. wrap .. "] show; hide") or "show"), 0, gateCount
    end
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

    -- Option axes with a macro conditional of their own. SHOW lanes only: their Hide
    -- counterparts are the leading gates above, so no negated disjunct is emitted.
    if opts.visOnlyMounted and not opts.visHideMounted then
        axes = axes + 1; emit("mounted")
    end
    if opts.visHideNoTarget and not opts.visHideWithTarget then
        axes = axes + 1; emit("exists")
    end
    if opts.visHideNoEnemy and not opts.visHideWithEnemy then
        axes = axes + 1; emit("harm")
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
    local noMatch = hasMouseover and wrappedShow or "hide"
    if axes == 0 then
        -- Nothing this string can decide: either nothing is constrained anywhere
        -- (Always), or the only constrained axes are Lua-only ones that all failed.
        if (extraConstrained or 0) > 0 then return prefix .. noMatch, 0, gateCount end
        return prefix .. wrappedShow, 0, gateCount
    end
    if dragonTail then
        -- Under mouseover the negative-dragon veto would just be dead weight: dropping
        -- it lets the trailing wrappedShow (itself the hover-gated fallback) cover the
        -- airborne case too, instead of nesting wrappedShow's own bracket/semicolons
        -- inside this clause's action slot.
        if hasMouseover then
            return prefix .. out .. wrappedShow, axes, gateCount
        end
        return prefix .. out .. "[" .. lead .. "advflyable,flying] hide; " .. wrappedShow, axes, gateCount
    end
    return prefix .. out .. noMatch, axes, gateCount
end

-- Leading hide gates for the macro-expressible HIDE lanes. They veto in every match
-- mode, so they precede the Any disjuncts (first matching clause wins) and are never
-- softened by the mouseover fallback: a hover must not reveal what a Hide lane hid.
-- Deliberately unwrapped -- `wrap` is an AND term of the SHOW side (Pet Bar), not
-- something a veto has to wait for. Returns the gate string and how many gates it holds.
function EUI.BuildVisOptHideGates(opts)
    local out, n = "", 0
    if opts.visHideMounted and not opts.visOnlyMounted then
        out = out .. "[mounted] hide; "; n = n + 1
    end
    if opts.visHideWithTarget and not opts.visHideNoTarget then
        out = out .. "[exists] hide; "; n = n + 1
    end
    if opts.visHideWithEnemy and not opts.visHideNoEnemy then
        out = out .. "[harm] hide; "; n = n + 1
    end
    return out, n
end

-- Two macro tokens disagree with their Lua probe: [exists] counts a soft target and
-- [mounted] cannot see druid travel/flight forms. The correction is per lane, never a
-- blanket veto that would silence the other axes:
--   show lane, token would wrongly PASS -> drop the disjunct
--   show lane, token would wrongly FAIL -> show outright
--   hide lane, gate would wrongly FIRE  -> drop the gate
--   hide lane, gate would wrongly STAY  -> hide outright (forceHide)
-- Each probe runs only when its own lanes are set (the mount one walks the druid auras).
local function AnyDriverLaneFixups(store, edges)
    local drop, forceShow, forceHide = nil, false, false

    local wantsTarget = (edges and edges.softTarget)
        and (store.visHideNoTarget or store.visHideWithTarget)
    if wantsTarget then
        local softOnly = not UnitExists("target")
            and (UnitExists("softinteract") or UnitExists("softenemy") or UnitExists("softfriend"))
        if softOnly then
            -- Show lane: [exists] would show on the soft target the probe does not count.
            if store.visHideNoTarget and not store.visHideWithTarget then
                drop = { visHideNoTarget = true }
            -- Hide lane: the [exists] gate would hide on a soft target the probe does not
            -- count as one; drop the gate and leave the axis to the Lua veto.
            elseif store.visHideWithTarget and not store.visHideNoTarget then
                drop = { visHideWithTarget = true }
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
            -- Hide lane: the [mounted] gate cannot see the form, so it never fires while
            -- the probe says mounted. The caller hides and bakes the combat escape hatch.
            elseif store.visHideMounted and not store.visOnlyMounted then
                forceHide = true
            end
        end
    end

    return drop, forceShow, forceHide
end

-- Store -> Any-match driver tail, shared by Action Bars, Unit Frames and the Minimap.
-- SHOW lanes and mode axes compile to disjuncts, HIDE lanes to leading vetoes.
-- Returns tail, constrained (a LOWER BOUND: the early-outs stop counting once settled)
-- and liveAxes (axes that are LIVE macro terms in `tail`; 0 for a constant). A
-- driver-registering caller gates on liveAxes: constrained can be positive purely from
-- Lua-resolved axes, which a driver could never keep honest.
function EUI.BuildAnyMatchTail(store, legacyKey, vm, wrap, edges)
    wrap = wrap or ""
    -- An override replaces the selection, so the tail is a constant. Reported as one
    -- live axis: it IS a driver worth registering, and it cannot go stale (the value
    -- only changes when the override system rewrites it, which rebuilds the driver).
    local ov = EUI.VisOverrideValue(store)
    if ov then return (ov == "never") and "hide" or "show", 1, 1 end
    -- Never is an exclusive scalar, not an axis, so nothing can out-vote it.
    if (store[legacyKey] or "always") == "never" then return "hide", 1, 0 end

    -- Hide lanes veto in every match mode, so they settle the verdict before any
    -- disjunct is looked at. The ones this consumer cannot compile are resolved here, at
    -- build time -- as fresh as the last driver rebuild, exactly like the Lua-only show
    -- lanes below. combatFlip (mount, skyriding mount, vehicle) means the probe can flip
    -- while a driver cannot be rewritten, so those must not freeze as a dead "hide":
    -- they hide out of combat and hand the rest of the string back in combat, the same
    -- escape hatch the Action Bars "combathide" path bakes under All.
    local combatEscape = false
    if EUI.VisOptionHideVeto then
        local vetoed, vetoFlip = EUI.VisOptionHideVeto(store, "luaOnly", edges)
        if vetoed then
            if not vetoFlip then return "hide", 1, 0 end
            combatEscape = true
        end
    end

    -- The mode rows' Hide lanes veto the same way. All but one compile to a leading gate
    -- inside BuildVisibilityDriverStringAny; hide_not_dragonriding has no positive bracket
    -- form and is resolved here, as fresh as the last driver rebuild. It is combatFlip
    -- (takeoff and landing happen mid-combat), so it always takes the escape hatch.
    if vm and EUI.VisModeHideVeto then
        local mVetoed, mFlip = EUI.VisModeHideVeto(vm, nil, nil, "luaOnly")
        if mVetoed then
            if not mFlip then return "hide", 1, 0 end
            combatEscape = true
        end
    end

    -- Runs before the Lua-only show lanes settle anything: its mount branch can produce a
    -- veto of its own, and a veto outranks a passing disjunct. Its probes only run when
    -- the matching lanes are set.
    local drop, forceShow, forceHide = AnyDriverLaneFixups(store, edges)
    if forceHide then combatEscape = true end

    -- Wraps every return below: out of combat the veto stands, in combat the compiled
    -- string decides (mode axes, prefixes and any live gate keep working there).
    local function Finish(tail, constrained, live)
        if combatEscape then
            return "[nocombat] hide; " .. tail, constrained + 1, live + 1
        end
        return tail, constrained, live
    end

    local luaC, luaP = 0, 0
    if EUI.TallyVisibilityOptionAxes then
        luaC, luaP = EUI.TallyVisibilityOptionAxes(store, "luaOnly", edges)
    end
    -- A passing Lua-only SHOW lane settles the disjunction, but it must not settle the
    -- vetoes: returning a bare "show" here would skip the compiler below, and the compiler
    -- is the only place the leading hide gates are emitted. forceShow already means exactly
    -- this -- show outright, gates intact -- so the fall-through reuses it.
    local settled = luaP > 0

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
                    -- A dropped SHOW lane is still a constrained disjunct this string
                    -- cannot decide; a dropped HIDE gate is a veto that is NOT firing,
                    -- which constrains nothing at all.
                    if drop[ax.show] then dropped = dropped + 1 end
                else
                    opts[ax.show] = store[ax.show]
                    opts[ax.hide] = store[ax.hide]
                end
            end
        end
    end
    local hasMouseover = (vm and vm.mouseover) or (store[legacyKey] == "mouseover") or false
    local tail, axes, gates = EUI.BuildVisibilityDriverStringAny("", modes, opts,
        luaC + dropped, wrap, hasMouseover, forceShow or settled)
    -- liveAxes counts the gates too: a string that carries nothing but "[mounted] hide"
    -- is still a live driver worth registering.
    return Finish(tail, axes + luaC + dropped, axes + gates)
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
    -- The shared selection, not what an override on the source currently replaces it with.
    local ms = ActiveModes(src, legacyKey, true)
    if ms then
        local sel = {}
        for k in pairs(ms) do
            if VIS_COMBINABLE_KEYS[k] then sel[k] = true end
        end
        if dstCaps and dstCaps.noGroupModes then
            sel.in_raid, sel.in_party, sel.solo = nil, nil, nil
            sel.hide_in_raid, sel.hide_in_party, sel.hide_solo = nil, nil, nil
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
