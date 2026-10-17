if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Keybinds.lua
--
--  The keybind system: override bindings for every bar and the key-down
--  CVar.
--  Loads after EUI_ActionBars_VisibilityDrivers.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local BAR_CONFIG = I.BAR_CONFIG
local BAR_SLOT_OFFSETS, barFrames, BINDING_MAP = I.BAR_SLOT_OFFSETS, I.barFrames, I.BINDING_MAP

-------------------------------------------------------------------------------
--  Keybind System: ALL standard-bar slots (empowered spells included) bind to
--  native commands (ACTIONBUTTON1 etc.) -- the engine pairs press/release
--  against the physical key, which is the only queue-safe empower path. A
--  click-routed key delivers stateless up/down clicks, and an up landing
--  while an empower is still QUEUED files a release the engine honors the
--  instant the cast starts (the rank-1 latch; typerelease-disarm gating was
--  field-tested against it and failed -- the up is consumed as a second
--  UseAction, not as a release attribute read). Click routing remains ONLY
--  where native commands cannot express the slot: custom-paged bars and
--  Bar9/Bar10.
-------------------------------------------------------------------------------
local _bindState = { housingCleared = false }

-- Binding owner: one frame owns all override bindings so they clear/reapply as
-- a unit. Native-command routing (ACTIONBUTTON1, etc.) lets the engine's
-- hold-to-cast and empowered-spell systems work without our own attrs.
local _eabBindOwner = CreateFrame("Frame", "EAB_BindOwner", UIParent)

-- Returns true when the override bindings were (re)applied, false when the
-- routing signature was unchanged and the rebuild was skipped.
--
-- The signature cache exists because rebuilding is expensive: up to two override
-- bindings cleared and re-registered per button (engine binding-table rebuilds) plus
-- GetActionInfo/IsPressHoldReleaseSpell per slot, and the empower reroute calls this on
-- ACTIONBAR_SLOT_CHANGED, which storms dozens of times/sec with mouseover-conditional
-- macros (each flip re-resolves them). Slot contents do NOT change the bindings
-- themselves (keys map to native commands or button names, not actions), so a rebuild
-- is only needed when a routing decision, bound key, or empower state changes.
local function UpdateKeybinds()
    -- Combat bail, self-re-arming. Everything below is protected
    -- (ClearOverrideBindings/SetOverrideBindingClick) so it cannot run here,
    -- and returning false with nothing to retry drops the whole build: the
    -- load-time apply has no deferral of its own, so logging in or reloading
    -- during combat leaves EVERY override binding unapplied for the session
    -- -- custom-bound keys dead and custom-paged routing wrong. (A previous
    -- version of this comment blamed native bindings for press-and-tap
    -- empower behaviour; superseded 2026-08-09 -- empowers route native BY
    -- DESIGN now, with hold-and-release engine-owned.)
    -- Re-arming here covers every caller at once; sibling paths that already defer share
    -- the "UpdateKeybinds" queue key, so the rebuild runs once after combat.
    if InCombatLockdown() then
        ns.CombatQueue.Defer("UpdateKeybinds", UpdateKeybinds)
        return false
    end
    -- With the house editor active our overrides are cleared so Blizzard's
    -- housing hotkeys work (see Housing Editor Keybind Clearing). The editor
    -- then registers its OWN overrides, firing UPDATE_BINDINGS straight back
    -- here; without this guard the rebuild re-applies ~200 of ours on top and
    -- stomps the housing hotkeys until the editor's next mode change. Rebuild
    -- resumes on editor close (housingCleared reset -> UpdateKeybinds;
    -- sigValid stays false while cleared, so that rebuild is never skipped).
    if _bindState.housingCleared then return false end
    -- A hidden bar skipped at load must exist the moment a key lands on one of
    -- its commands (UPDATE_BINDINGS lands here): hidden bars keep live
    -- bindings, and a click-routed key has no button to route to otherwise.
    -- Combat already bailed above, so the build is legal here; the passes
    -- below then bind the new buttons like any other.
    ns._eabBuildSkippedBars()
    -- Empower detection for one action slot, shared by the current-page
    -- and base-slot checks in pass 1.
    local function SlotIsPH(slot)
        if not (slot and HasAction(slot)) then return false end
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "flyout" then return true end
        if C_Spell and C_Spell.IsPressHoldReleaseSpell then
            local spellID
            if actionType == "spell" then
                spellID = id
            elseif actionType == "macro" and subType == "spell" then
                spellID = id
            end
            if spellID and not (issecretvalue and issecretvalue(spellID))
               and C_Spell.IsPressHoldReleaseSpell(spellID) then
                return true
            end
        end
        return false
    end
    -- Flyout detection, split out from SlotIsPH. A flyout MUST click-route to
    -- our visible EABButton: SpellFlyout:Toggle anchors to self, and native
    -- command routing (ACTIONBUTTONn) fires on Blizzard's original button,
    -- which we hide/reparent off-screen (see stock-bar hiding above) --
    -- opening the popup there produces no visible menu even though the key
    -- was received. Empowers have no popup to anchor, so they're unaffected
    -- and must stay on the native command (see routing comment below).
    local function SlotIsFlyout(slot)
        if not (slot and HasAction(slot)) then return false end
        return GetActionInfo(slot) == "flyout"
    end
    -- Pass 1: compute per-button routing signature (k1, k2, useClick, isPH)
    -- and compare against the last applied build.
    local sig = _bindState.sig
    if not sig then sig = {}; _bindState.sig = sig end
    local n = 0
    local changed = not _bindState.sigValid
    local anyPH = false
    for _, info in ipairs(BAR_CONFIG) do
        local prefix = BINDING_MAP[info.key]
        local btns = barButtons[info.key]
        if prefix and btns then
            -- Custom modifier/form paging lives only in our private secure
            -- state driver, which never moves Blizzard's GetActionBarPage().
            -- Native engine commands (ACTIONBUTTONn / MULTIACTIONBARxBUTTONn)
            -- resolve against Blizzard's page, so on a custom-paged bar the
            -- keybind would fire the un-paged slot while the icon (our
            -- explicit "action" attr) repages. Route those bars' keybinds
            -- through the button (SetOverrideBindingClick) so the keypress
            -- reads our paged "action" attr, exactly as empower/flyout already do.
            --
            -- Class-default form paging (Druid/Rogue; every class's stance or
            -- form on WoW Forever) is NOT custom paging:
            -- it rides on bonusbar, a native engine concept ACTIONBUTTONn
            -- resolves on its own, so icon and native keybind already agree
            -- in every form. Click-routing those bars would only cost
            -- press-and-hold repeat casting (a synthetic click never reaches
            -- UseAction with isKeyPress=true), so they must stay on the
            -- native command -- only genuine user-configured paging (bs.paging) needs the click route.
            local bs = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[info.key]
            local barHasCustomPaging = EAB_VTABLE.HasCustomPaging(bs)
            -- Auto-paging opt-outs need the click route for the mirror-image
            -- reason: bonusbar stays a native engine concept whether or not
            -- we page off it, so ACTIONBUTTONn still resolves to the
            -- form/skyriding slot after we deliberately STOP the icon from
            -- following it. Left native, a stealthed keypress casts the
            -- page-7 ability the button no longer shows (the show-one/
            -- fire-another split GetClassPagingConditions warns about). Cost:
            -- press-and-hold repeat on MainBar while the opt-out is on.
            if info.key == "MainBar" and bs
               and (bs.disableFormPaging or bs.disableSkyridingPaging) then
                barHasCustomPaging = true
            end
            for i, btn in ipairs(btns) do
                if btn then
                    local cmd = prefix .. i
                    local k1, k2 = GetBindingKey(cmd)
                    -- Routing is native for everything on standard bars,
                    -- empowers included (flyouts are the exception -- see
                    -- isFlyout below): the engine's keystate-paired
                    -- hold-and-release is the only queue-safe empower path
                    -- (stateless click routes latch queued releases at
                    -- rank 1). Click routing exists ONLY where a native
                    -- command cannot express the slot: custom-paged bars
                    -- (above) and the custom bars.
                    local slot = btn:GetAttribute("action")
                    -- Custom bars (Bar9/Bar10) have no native binding command, so
                    -- their keys MUST click-route; SetOverrideBinding to a
                    -- non-existent command does nothing. isPH tracks empower
                    -- state separately from useClick: on a custom-paged bar
                    -- useClick is always true, but the secure empower snippet
                    -- still needs a re-trigger when press-and-hold state flips.
                    local isPH = SlotIsPH(slot)
                    -- Base-slot check: isPH no longer decides ROUTING on its
                    -- own (empowers stay native either way); it stays in the
                    -- signature so
                    -- pass 3 re-fires the attr re-check when a slot's
                    -- press-and-hold state genuinely changes (mouse-click
                    -- correctness), and it feeds the combat-drop re-assert
                    -- gate. Consulting the BASE slot keeps the signature
                    -- stable across page swaps -- deriving it from the
                    -- CURRENT page only would rebuild ~200 bindings on every
                    -- mount and dismount (skyriding page flips). Guarded on
                    -- the offsets table so Pet/Stance buttons (action attr
                    -- nil) never alias into MainBar slots.
                    local isFlyout = SlotIsFlyout(slot)
                    if not isPH then
                        local off = BAR_SLOT_OFFSETS[info.key]
                        if off then
                            local base = off + i
                            if base ~= slot then
                                isPH = SlotIsPH(base)
                            end
                        end
                    end
                    if isPH then anyPH = true end
                    -- isPH (empower) deliberately NOT part of the routing
                    -- decision: empower keys must ride the native command.
                    -- isFlyout IS part of it: flyouts need self to be the
                    -- visible button so SpellFlyout anchors somewhere the
                    -- player can actually see.
                    local useClick = barHasCustomPaging or (info.customPage ~= nil) or isFlyout
                    k1 = k1 or false
                    k2 = k2 or false
                    if sig[n + 1] ~= k1 or sig[n + 2] ~= k2
                       or sig[n + 3] ~= useClick or sig[n + 4] ~= isPH then
                        changed = true
                    end
                    sig[n + 1], sig[n + 2], sig[n + 3], sig[n + 4] = k1, k2, useClick, isPH
                    n = n + 4
                end
            end
        end
    end
    if _bindState.sigN ~= n then changed = true; _bindState.sigN = n end
    -- Tracked on every full pass (even signature-unchanged ones) so the
    -- combat-drop attr re-assert knows whether any press-and-hold slot
    -- exists at all -- non-empower classes never pay for it.
    _bindState.hasPH = anyPH
    -- Blizzard's twin buttons are what a natively-routed empower key actually
    -- drives; their pressAndHoldAction is kept current by Blizzard's own
    -- SLOT_CHANGED and PLAYER_ENTERING_WORLD registrations, which the
    -- broadcaster quieting at the top of the file leaves untouched.
    if not changed then return false end
    _bindState.sigValid = true
    -- Pass 2: apply. Reads the routing decisions computed above.
    ClearOverrideBindings(_eabBindOwner)
    local j = 0
    for _, info in ipairs(BAR_CONFIG) do
        local prefix = BINDING_MAP[info.key]
        local btns = barButtons[info.key]
        if prefix and btns then
            for i, btn in ipairs(btns) do
                if btn then
                    local k1, k2, useClick = sig[j + 1], sig[j + 2], sig[j + 3]
                    j = j + 4
                    if useClick then
                        local btnName = btn:GetName()
                        if k1 and btnName then
                            SetOverrideBindingClick(_eabBindOwner, false, k1, btnName)
                        end
                        if k2 and btnName then
                            SetOverrideBindingClick(_eabBindOwner, false, k2, btnName)
                        end
                    else
                        local cmd = prefix .. i
                        if k1 then
                            SetOverrideBinding(_eabBindOwner, false, k1, cmd)
                        end
                        if k2 then
                            SetOverrideBinding(_eabBindOwner, false, k2, cmd)
                        end
                    end
                end
            end
        end
    end
    -- Pass 3: re-evaluate pressAndHoldAction on every button. Routing the key is only
    -- HALF of hold-and-release -- a CLICK-routed key still behaves as Press-and-Tap
    -- unless the button also carries that attr. The only writers are this re-check and
    -- _childupdate-eab-page (installed on MainBar and custom-paged bars alone).
    --
    -- Blizzard writes the attribute too and gets the last word on every
    -- loading screen: BUTTON_EVENT_LISTS.action registers
    -- PLAYER_ENTERING_WORLD per button and the mixin's PEW branch calls
    -- Update() -> UpdatePressAndHoldAction(). Zoning leaves the page state
    -- unchanged (page 1 -> page 1), so nothing re-runs our snippet and an
    -- empowered spell sits on pressAndHoldAction=false for the rest of the session.
    --
    -- Firing it HERE covers every caller at once (load time, UPDATE_BINDINGS,
    -- the combat re-arm above, the housing restore, the post-loading-screen
    -- restore). SetAttribute on a secure header is protected, but the combat
    -- bail at the top guarantees we only reach here out of combat.
    for _, info in ipairs(BAR_CONFIG) do
        local frame = barFrames[info.key]
        if frame then
            frame:SetAttribute("state-eabempower", GetTime())
        end
    end
    return true
end
_G._EAB_UpdateKeybinds = UpdateKeybinds

-- Re-assert pressAndHoldAction across all bars once combat drops. Combat is
-- the ONE window where the attribute can be rewritten without pass 3 above
-- running: the page-swap snippet fires SECURELY mid-fight (bonusbar/override
-- flips during encounters), and even with its unreadable-read guard the
-- out-of-combat truth must win afterwards -- while the signature cache
-- correctly reports "nothing changed", because the ROUTING didn't change,
-- only the attribute did. One ChildUpdate per bar per combat drop, and only
-- when a press-and-hold slot exists at all, so non-empower classes and idle
-- play pay nothing. Touches pressAndHoldAction only -- never typerelease,
-- never bindings -- so the native hold-to-cast path is untouched by
-- construction.
ns._EABReassertEmpowerAttrs = function()
    if InCombatLockdown() then return end
    if not _bindState.hasPH then return end
    for _, info in ipairs(BAR_CONFIG) do
        local frame = barFrames[info.key]
        if frame then
            frame:SetAttribute("state-eabempower", GetTime())
        end
    end
end





-- Update useOnKeyDown on all action buttons to match the CVar.
-- RegisterForClicks is always ("AnyDown", "AnyUp") so empower spells
-- receive key-down even in key-up mode. Only the attribute changes.
-- Must be called out of combat (SetAttribute on secure buttons).
local function ApplyClickRegistration()
    local keyDown = GetCVarBool("ActionButtonUseKeyDown")
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local btns = barButtons[info.key]
            if btns then
                for _, btn in ipairs(btns) do
                    if btn then
                        btn:SetAttribute("useOnKeyDown", keyDown)
                    end
                end
            end
        end
    end
end

-- Called when ActionButtonUseKeyDown CVar changes. Defers to out-of-combat.
local function ApplyKeyDownCVar()
    if InCombatLockdown() then
        ns.CombatQueue.Defer("ApplyKeyDownCVar", ApplyKeyDownCVar)
        return
    end
    ApplyClickRegistration()
    UpdateKeybinds()
end

-- Entry points the files after this one re-import by name.
I.UpdateKeybinds, I._bindState, I._eabBindOwner = UpdateKeybinds, _bindState, _eabBindOwner
I.ApplyKeyDownCVar = ApplyKeyDownCVar
