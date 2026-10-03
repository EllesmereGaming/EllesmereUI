if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Events.lua
--
--  The central event dispatcher for the action bar buttons, the assist and
--  charge cooldown helpers it drives, ForceButtonRefresh and bar dormancy.
--  Loads right after the main file and reads it through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local floor = math.floor
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local GetBindingKey = GetBindingKey
local EFD = ns.EFD

local EAB, EAB_VTABLE, BAR_LOOKUP = ns.EAB, ns.EAB_VTABLE, ns.BAR_LOOKUP
local ForceCooldownPaint, barButtons = ns.ForceCooldownPaint, ns.barButtons
local I = ns._internals
local BAR_CONFIG, BINDING_MAP, BUTTON_EVENT_LISTS = I.BAR_CONFIG, I.BINDING_MAP, I.BUTTON_EVENT_LISTS
local ReRegisterButtonEvents, barFrames = I.ReRegisterButtonEvents, I.barFrames

-------------------------------------------------------------------------------
--  Central Event Dispatcher: registers action bar events on a SINGLE frame
--  and dispatches to all buttons, avoiding the per-button registration that
--  caused 96 separate OnEvent calls per tick (screen-wide black blink).
-------------------------------------------------------------------------------

-- Usable-tint mirror for ForceButtonRefresh, a named function so pcall passes
-- args instead of allocating a closure per call (runs in the
-- ACTIONBAR_SLOT_CHANGED storm path). On ns: file at the 200-local cap.
ns._TintUsableIcon = function(icon, action)
    local isUsable, noMana
    if C_ActionBar and C_ActionBar.IsUsableAction then
        isUsable, noMana = C_ActionBar.IsUsableAction(action)
    elseif IsUsableAction then
        isUsable, noMana = IsUsableAction(action)
    end
    if isUsable then
        icon:SetVertexColor(1, 1, 1)
    elseif noMana then
        icon:SetVertexColor(0.5, 0.5, 1.0)
    elseif isUsable ~= nil then
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

-- Script-free replacement for Blizzard's assisted-combat rotation swirl.
-- Blizzard's frame runs a Lua OnUpdate every render frame forever (measured:
-- over half this addon's idle CPU, billed to whichever context the frame
-- chain was born under). Ours is a plain frame + STATIC texture cloned from
-- Blizzard's art: no scripts, no animation, nothing billed, free to stay
-- visible out of combat. The Blizzard frame stays permanently hidden via the
-- UpdateAssistedCombatRotationFrame hook.
function ns.EnsureAssistSpinner(btn, rtf)
    local fd = EFD(btn)
    local spin = fd.assistSpin
    if not spin then
        spin = CreateFrame("Frame", nil, btn)
        spin:SetPoint("CENTER", btn, "CENTER")
        local tex = spin:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        -- The rotation-helper marker art, stretched to this frame's rect.
        -- Fallback: clone whatever Blizzard's own texture carries.
        local ok = pcall(tex.SetAtlas, tex, "UI-HUD-RotationHelper-Inactive-2x", false)
        if not ok then
            local src = rtf.InactiveTexture
            local atlas = src and src.GetAtlas and src:GetAtlas()
            if atlas then
                tex:SetAtlas(atlas, false)
            elseif src and src.GetTexture then
                tex:SetTexture(src:GetTexture())
                if src.GetTexCoord then
                    tex:SetTexCoord(src:GetTexCoord())
                end
            end
        end
        fd.assistSpin = spin
    end
    -- Two-point anchor derives the rect from the button's, tracking every size/layout
    -- change with zero math and no re-apply pass. Scale-based sizing broke here because
    -- btn:GetWidth() isn't the visual size on every style path; anchors sidestep that.
    -- User-adjustable outset (default 9px/side) makes the ring art's inset circle meet
    -- the button edge. Change-guarded so frequent hook calls cost two reads.
    local outset = (EAB.db and EAB.db.profile and EAB.db.profile.obaIconOutset) or 9
    if fd.assistSpinOutset ~= outset then
        fd.assistSpinOutset = outset
        spin:ClearAllPoints()
        spin:SetPoint("TOPLEFT", btn, "TOPLEFT", -outset, outset)
        spin:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", outset, -outset)
    end
    spin:SetFrameLevel(rtf:GetFrameLevel())
    return spin
end

-- Repaint the assist button's icon with the SUGGESTED spell's texture;
-- returns how many assist buttons were found. The slot's own action texture
-- is only the static assist marker, and with the swirl frame hidden (its
-- OnUpdate poll drove Blizzard's re-stamp loop) NO event fires on suggestion
-- changes -- the assist ticker below is the driver. Buttons are found via the
-- spinner registry; the slot-spam event's id never matched our action attr anyway.
-- suggestedSpell: the ticker's single sample for this pass, so the icon and the
-- swipe below describe the same ability. Callers without one read it themselves.
function ns.RepaintAssistIcons(suggestedSpell)
    local found = 0
    local nextSpell = suggestedSpell
    if nextSpell == nil then
        nextSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
            and C_AssistedCombat.GetNextCastSpell()
    end
    local tex = nextSpell and C_Spell and C_Spell.GetSpellTexture
        and C_Spell.GetSpellTexture(nextSpell)
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for i = 1, #buttons do
                    local btn = buttons[i]
                    -- Raw read: only buttons that have ever hosted the
                    -- assist action carry a spinner entry.
                    local fd = btn and ns._eabFD[btn]
                    if fd and fd.assistSpin then
                        local action = btn.GetAttribute and btn:GetAttribute("action") or btn.action
                        if action and HasAction(action) and C_ActionBar
                           and C_ActionBar.IsAssistedCombatAction
                           and C_ActionBar.IsAssistedCombatAction(action) then
                            found = found + 1
                            local icon = btn.icon or btn.Icon
                            if icon then
                                icon:SetTexture(tex or GetActionTexture(action))
                                icon:SetShown(true)
                            end
                            -- This button's cooldown/charges mirror the suggested
                            -- spell: a suggestion change is content change for THIS
                            -- button only, so paint its swipe now (two C calls); the
                            -- next natural walk reconciles charges/desat -- never a
                            -- bar-wide invalidation (see ns._ArmAssistTicker).
                            -- Painted from the SAME spell whose texture just
                            -- went on the icon, never from the slot.
                            ns.PaintAssistCooldown(btn, nextSpell)
                        end
                    end
                end
            end
        end
    end
    return found
end

-- Suggested-spell driver for One Button Assist. The engine fires no event on
-- suggestion changes for OUR buttons (see RepaintAssistIcons), so a 5 Hz anim
-- ticker polls GetNextCastSpell and repaints only on CHANGE. The ticker
-- object is created lazily on first arm (users without assist never create
-- it), self-disarms when no assist button remains, and its host frame is
-- born in assist-armed context, so only OBA users are billed for it.
function ns._ArmAssistTicker()
    local t = ns._assistTicker
    if not t then
        local Tick = EllesmereUI and EllesmereUI.Tick
        if not (Tick and Tick.NewAnimTicker) then return end
        t = Tick.NewAnimTicker(CreateFrame("Frame"), function()
            -- ONE sample per tick, shared by the swipe and the icon: reading
            -- the suggestion here and the slot's cooldown separately let the
            -- two land on different abilities (see ns.PaintAssistCooldown).
            local nextSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
                and C_AssistedCombat.GetNextCastSpell()
            -- Every tick, not just on suggestion change: the suggested
            -- spell's own cooldown can end/shorten while the suggestion
            -- holds steady, and nothing else repaints for that.
            ns.RefreshAssistCooldowns(nextSpell)
            if nextSpell ~= ns._assistLastSuggest then
                ns._assistLastSuggest = nextSpell
                local n = ns.RepaintAssistIcons(nextSpell)
                -- Suggestion moved: the shine may need to follow it too.
                if ns.QueueAssistRescan then ns.QueueAssistRescan() end
                -- The assist slot's cooldown mirrors the SUGGESTED spell, so a
                -- suggestion change is cooldown content for that ONE button --
                -- RepaintAssistIcons already painted its swipe and dropped its
                -- memos. The dirty bump keeps the walker out of idle sleep so
                -- the next NATURAL walk (<=0.5s mid-storm via trailing flush,
                -- <=1s via idle heartbeat) reconciles charges/desat. Never
                -- invalidate/force work BAR-WIDE here: a full walk + count-pass
                -- reset ran a second ~140-button storm every GCD on top of the
                -- cast's own (profiled 8% vs 5% CPU chain-casting vs manual;
                -- item stacks don't move on suggestion flips, so assist Count
                -- riding the normal ~2s sub-pass stays correct).
                ns._cdDirtyUntil = GetTime() + 2
                if n == 0 then return false end  -- assist left the bars: self-disarm
            end
            return true
        end, 0.2)
        ns._assistTicker = t
    end
    t.Start()
end

-- Re-assert ONLY the assist button's cooldown swipe: it mirrors the SUGGESTED
-- spell, whose own cooldown can end/shorten with no suggestion change, no
-- cast, and no action-bar event to walk on (measured up to 1.38s stale
-- swipe). Cost: a raw _eabFD read per button (no allocation, no API call),
-- then three C calls for the one or two hosting buttons -- ~700 table
-- reads/sec at the 0.2s ticker. Deliberately NOT a walk/memo-drop/dirty-bump:
-- a one-button change never invalidates bar-wide (see ns._ArmAssistTicker).
-- suggestedSpell: paint from this spell rather than the slot, so the per-tick
-- refresh cannot land on a different ability than the icon is showing.
function ns.RefreshAssistCooldowns(suggestedSpell)
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for i = 1, #buttons do
                    local btn = buttons[i]
                    local fd = btn and ns._eabFD[btn]
                    if fd and fd.assistSpin then
                        local action = btn.GetAttribute and btn:GetAttribute("action") or btn.action
                        if action and HasAction(action) and C_ActionBar
                           and C_ActionBar.IsAssistedCombatAction
                           and C_ActionBar.IsAssistedCombatAction(action) then
                            ns.PaintAssistCooldown(btn, suggestedSpell)
                        end
                    end
                end
            end
        end
    end
end

-- Re-apply One Button Assist icon settings (toggle + outset) to every
-- existing spinner. Called by the options widgets; spinners on buttons that
-- have never held the assist action don't exist and cost nothing.
function ns.RefreshAssistSpinners()
    local p = EAB.db and EAB.db.profile
    local enabled = not p or p.obaIconEnabled ~= false
    local outset = (p and p.obaIconOutset) or 9
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for i = 1, #buttons do
                    local btn = buttons[i]
                    -- Raw read (not EFD()): no per-button state allocation
                    -- for buttons that never built a spinner.
                    local fd = btn and ns._eabFD[btn]
                    local spin = fd and fd.assistSpin
                    if spin then
                        if fd.assistSpinOutset ~= outset then
                            fd.assistSpinOutset = outset
                            spin:ClearAllPoints()
                            spin:SetPoint("TOPLEFT", btn, "TOPLEFT", -outset, outset)
                            spin:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", outset, -outset)
                        end
                        local action = btn.GetAttribute and btn:GetAttribute("action") or btn.action
                        local isAssist = action and C_ActionBar and C_ActionBar.IsAssistedCombatAction
                            and C_ActionBar.IsAssistedCombatAction(action) or false
                        spin:SetShown(enabled and isAssist)
                    end
                end
            end
        end
    end
end

-- Lazily build a button's charge (recharge) cooldown frame -- Blizzard's
-- mixin created it from the per-button ACTIONBAR_UPDATE_COOLDOWN handler we
-- no longer register (BUTTON_EVENT_LISTS). Native shape: edge-only overlay.
-- Our button, so writing the Blizzard-expected field is safe; native paths
-- still running (PEW full Update) reuse the same frame.
function ns.EnsureChargeCooldown(btn)
    local chargeCd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    chargeCd:SetHideCountdownNumbers(true)
    chargeCd:SetDrawSwipe(false)
    chargeCd:SetDrawEdge(true)
    chargeCd:SetAllPoints(btn)
    chargeCd:SetFrameLevel((btn.cooldown and btn.cooldown:GetFrameLevel())
        or (btn:GetFrameLevel() + 1))
    btn.chargeCooldown = chargeCd
    return chargeCd
end

-- Recharge-number visibility for one charge cooldown: extends "Show numbers
-- for cooldowns" to recharging charge spells, but ONLY while the MAIN
-- cooldown is idle or GCD-only. At 0 charges the main cooldown mirrors the
-- same recharge and shows its own countdown -- Blizzard hides charge numbers
-- unconditionally for that overlap, and un-hiding blindly would stack two
-- countdowns in two fonts. cdInfo.isActive/isOnGCD are plain booleans (no
-- secret comparisons). Cached per chargeCd so repeat calls are near-free.
function ns.UpdateChargeNumbersVisibility(btn, chargeCd, cdInfo, chargeInfo)
    if not (chargeCd and chargeCd.SetHideCountdownNumbers) then return end
    -- Occlusion: hide our recharge numbers only when the MAIN cooldown draws
    -- its own countdown for this spell -- at 0 charges (the main cooldown
    -- mirrors the recharge; the exact double-countdown this rule exists for),
    -- or on an EXPLICITLY real main cooldown (isOnGCD == false). isOnGCD is
    -- documented untrustworthy outside a direct SPELL_UPDATE_COOLDOWN response
    -- and arrives NIL from the pass/press/charge-walk contexts (field-confirmed)
    -- -- the old `not isOnGCD` read nil as "real", classified every GCD as a
    -- countdown, and STRANDED the numbers hidden: the GCD's end fires no event
    -- to re-evaluate. currentCharges is secret in instances: guarded read,
    -- secret falls to the isOnGCD term (NeverSecret per the docs).
    local zeroCharges = false
    if chargeInfo then
        local cur = chargeInfo.currentCharges
        if not (issecretvalue and issecretvalue(cur)) and cur == 0 then
            zeroCharges = true
        end
    end
    local hideNums = (EAB.db.profile.showChargeRechargeNumbers == false)
        or (not GetCVarBool("countdownForCooldowns"))
        or (cdInfo and cdInfo.isActive and (cdInfo.isOnGCD == false or zeroCharges) and true)
        or false
    local cfd = EFD(chargeCd)
    if cfd.rechargeNumbersHidden ~= hideNums then
        cfd.rechargeNumbersHidden = hideNums
        chargeCd:SetHideCountdownNumbers(hideNums)
        -- Lazily created charge cooldowns never pass through the login-time
        -- font application, so their countdown would render in Blizzard's
        -- default font. Queue the patch on un-hide; the FontString exists by
        -- the time the deferred flush runs.
        if not hideNums and not cfd.cdFontStamp then
            EAB_VTABLE.CooldownFonts.pending[btn] = true
            if not EAB_VTABLE.CooldownFonts.timerScheduled then
                EAB_VTABLE.CooldownFonts.timerScheduled = true
                C_Timer_After(0, EAB_VTABLE.CooldownFonts.FlushPatch)
            end
        end
    end
end

-- Full per-button visual refresh for slot CONTENT changes (spec swap,
-- drag-drop: slot numbers stay, contents change -- force-less UpdateAction
-- short-circuits on that exact case). NEVER route through the mixin's
-- UpdateAction/Update from our context: Update() runs UpdatePressAndHoldAction
-- -> SetAttribute (protected write, ADDON_ACTION_BLOCKED in combat) and
-- ActionButton_ApplyCooldown with SECRET start/duration (rejected under taint), and its
-- mixin-state writes poison later secure OnShow/driver executions of the same button.
-- Refresh directly with secret-tolerant setters instead: icon (SetTexture accepts
-- secrets), count, and the cooldown swipe via the same duration-object API the
-- dispatcher's ACTIONBAR_UPDATE_COOLDOWN branch uses.
function EAB_VTABLE.ForceButtonRefresh(btn, action)
    if not action then return end
    local icon = btn.icon or btn.Icon
    if icon then
        -- Stamp the icon texture-delta memo with what we actually paint:
        -- ns._cdIconHeal skips its repaint when the memo equals the live
        -- texture, so the memo must always match what is ON the icon. A
        -- spell override can resolve late (zone in/out on a hero talent),
        -- making this paint the BASE texture; left unstamped, the memo
        -- diverges and the SPELL_UPDATE_ICON heal wrong-skips the repaint.
        local tex = GetActionTexture(action)
        icon:SetTexture(tex)
        EFD(btn).lastIconTex = tex
        -- Blizzard's Update() HIDES the icon region for empty slots and only
        -- re-Shows on fill, so painting onto a previously-empty slot renders
        -- nothing until hover runs Blizzard's Update. Gate on HasAction --
        -- the slot-filled boolean is the question being asked (the texture
        -- fileID is never secret, per the API docs on every client).
        icon:SetShown(HasAction(action))
        -- Saturated baseline on every content change: desaturation is
        -- event/hover-managed and survives the slot emptying, so new content
        -- would inherit stale desat until mouseover; recompute below
        -- re-applies genuine on-CD desat when the feature is on.
        if icon.SetDesaturation then
            icon:SetDesaturation(0)
        elseif icon.SetDesaturated then
            icon:SetDesaturated(false)
        end
        -- Usable tint is a separate stale channel: grey from a zero-quantity
        -- item survives the content change, and usability events only fire
        -- on CHANGES, so nothing repaints until hover. Mirrors Blizzard's
        -- UpdateUsable; pcall-guarded in case the usability booleans are
        -- restricted (tint then left for the usable-event path).
        -- Skipped while the range system owns the color, same rule as
        -- DispWalkUsable: a spell override changes the texture and lands here,
        -- and painting the usable tint over a live range tint strands a white
        -- icon that only a hover undoes -- this path bypasses UpdateUsable, so
        -- the re-apply hook never sees it, and the range cache still reads
        -- out-of-range so no later event repaints either.
        local rfd = EFD(btn)
        if rfd.rangeTinted then
            rfd.usableState = nil
        else
            pcall(ns._TintUsableIcon, icon, action)
        end
    end
    if btn.Count and C_ActionBar and C_ActionBar.GetActionDisplayCount then
        -- No `or ""` on the raw return: it is secret while cooldowns are
        -- restricted, and coercing one before the guard is what strands the
        -- count. SetText accepts a secret, so only the plain nil needs healing.
        local display = C_ActionBar.GetActionDisplayCount(action)
        if not (issecretvalue and issecretvalue(display)) and display == nil then
            display = ""
        end
        btn.Count:SetText(display)
        ns._EABZeroCountAlpha(EFD(btn), btn.Count, display, action)
    end
    -- Macro/action text: with per-button events suppressed, a moved macro leaves its
    -- name stuck on the old slot (new slot blank) until hover runs Blizzard's Update.
    -- Mirror its logic: set name only for slots that use action text, clear otherwise.
    if btn.Name and C_ActionBar and C_ActionBar.UsesActionText then
        if C_ActionBar.UsesActionText(action) then
            local nm = C_ActionBar.GetActionText and C_ActionBar.GetActionText(action)
            btn.Name:SetText(nm or "")
        else
            btn.Name:SetText("")
        end
    end
    local cd = btn.cooldown
    if cd and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cdInfo = C_ActionBar.GetActionCooldown(action)
        if cdInfo and cdInfo.isActive then
            local dur = C_ActionBar.GetActionCooldownDuration(action)
            if dur and cd.SetCooldownFromDurationObject then
                cd:SetCooldownFromDurationObject(dur)
            end
        else
            cd:Clear()
        end
    end
    -- Desat / on-CD alpha are otherwise only recomputed by cooldown events
    -- (Blizzard's secure Update only runs on hover), and a persistent
    -- EABButton keeps its last desat state through being emptied. Recompute
    -- from live cooldown data now that the slot's contents changed.
    if EAB._RefreshCooldownVisuals then
        EAB._RefreshCooldownVisuals(btn)
    end
end

-------------------------------------------------------------------------------
--  Bar dormancy: a driver-hidden bar does no event work. Source of truth is
--  the bar frame's effective visibility, observed as OnShow/OnHide edges
--  (CreateBarFrame). Hide: strip the per-button mixin event list. Show:
--  re-register and reconcile everything stale, then re-seed the central
--  walk's memos through the existing cast-wave path (paid every GCD anyway).
--
--  What stays live for dormant bars, on purpose: the dispatcher's
--  content-class branches (targeted SLOT_CHANGED repaint, infrequent full
--  walk) still cover ALL bars, so page flips, drag-and-drop onto a hidden
--  bar, and spec swaps are correct-on-reveal by construction. Accepted
--  staleness while hidden: loss-of-control swipes (corrected by the next LOC
--  event after reveal).
--
--  Alpha-0 mouseover bars are SHOWN frames and deliberately count as
--  visible: gating on alpha would move reconcile work onto the hover-in edge
--  -- the exact spike the mouseover fix removed. (On ns: 200-local cap.)
-------------------------------------------------------------------------------
ns._eabBarDormant = {}
-- HARD dormancy: bars whose visibility mode is "Never" (or disabled, or hidden by
-- Hide Bar When Using Gamepad) cannot become visible through ANY runtime condition --
-- no driver state, no combat edge. The only reveal paths are a settings write, the
-- Toggle Action Bar runtime override, a controller disconnect or Quick Keybind mode
-- opening (out of combat only); all four funnel through RefreshRuntimeVisibility,
-- which recomputes this map. While a bar is in this map EVERY per-event walk skips it,
-- content classes included: the reveal reconcile below repaints each button from live
-- state on the show edge, so correct-on-reveal holds at zero background cost.
-- Conditional-visibility bars keep content-walk coverage (their reveal edges can fire
-- mid-combat, where a heavier reconcile would spike).
ns._eabBarNever = {}
ns._eabBarNeverWas = {}
-- Bars whose buttons were skipped at load because they were Never AND unbound
-- then. Cleared by BuildBarButtons. Drives ns._eabBuildSkippedBars (reveal
-- via RefreshRuntimeVisibility, or a key landing via UpdateKeybinds).
ns._eabBarNoButtons = {}
-- Single source of truth for "this bar can never become visible through any
-- runtime condition". RecomputeNeverBars and the load-time button skip both
-- read it, so the two cannot drift apart -- a separately maintained restore
-- predicate already drifted once in this file (see RestoreGridSurfacedBars).
ns.IsNeverBar = function(info)
    if info.isStance or info.isPetBar or info.visibilityOnly then return false end
    local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
    local s = bars and bars[info.key]
    -- Hide Bar When Using Gamepad joins the set while a controller is connected
    -- (EAB._padHide only turns on out of combat, see EAB._PadSync).
    local never = s and (s.alwaysHidden or s.enabled == false
        or (EAB._padHide and s.gamepadHideBar == true)) or false
    -- Toggle override wins both ways: hiding an Always bar hard-disables its UI
    -- work; showing a Never bar wakes it. Action bindings stay live.
    local override = EAB._visOverride and EAB._visOverride[info.key]
    if override == "never" then never = true
    elseif override == "always" then never = false end
    return never and true or false
end
-- True when any of the bar's binding commands has a key. A hidden bar keeps
-- live bindings by contract, and a click-routed key (Bar9/Bar10, custom
-- paging, flyouts) has nothing to route to without a button, so the load-time
-- button skip only applies to bars that are BOTH Never and unbound.
ns.BarHasBoundKeys = function(info)
    local prefix = BINDING_MAP[info.key]
    if not prefix then return false end
    for i = 1, info.count do
        if GetBindingKey(prefix .. i) then return true end
    end
    return false
end
ns.RecomputeNeverBars = function()
    local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
    if not bars then return end
    local map = ns._eabBarNever
    local changed = false
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar and not info.visibilityOnly then
            -- nil rather than false so the map stays sparse for its readers.
            local never = ns.IsNeverBar(info) or nil
            if map[info.key] ~= never then
                if map[info.key] and not never then
                    -- Leaving Never: remember to run the one heal the gates skipped (AlwaysShow grid).
                    ns._eabBarNeverWas[info.key] = true
                end
                map[info.key] = never
                changed = true
            end
        end
    end
    if changed then
        -- Retire content signature + list memos so every gated pass rebuilds
        -- against the new active set.
        ns._eabSpellsSig = nil
        ns._cdFilledDirty = true
        ns._slotBtnMapDirty = true
    end
end
ns.ApplyBarDormancy = function(key, dormant)
    local info = BAR_LOOKUP[key]
    -- Stance/pet bars reuse Blizzard buttons with their own event wiring,
    -- gated on frame visibility; on show edge just rerun their painters.
    if not info or info.isStance or info.isPetBar then
        if info and not dormant then
            if info.isStance and ns._eabStanceReconcile then ns._eabStanceReconcile() end
            if info.isPetBar and ns._eabPetReconcile then ns._eabPetReconcile() end
        end
        return
    end
    local btns = barButtons[key]
    if not btns then return end
    dormant = dormant and true or false
    if ns._eabBarDormant[key] == dormant then return end
    ns._eabBarDormant[key] = dormant
    ns._cdFilledDirty = true -- either edge changes which buttons the tier/filled lists may include
    -- Range acquisition follows the same edges (defined later, hence the ns
    -- indirection): hidden bars stop generating range traffic.
    if ns._eabRangeBarDormancy then ns._eabRangeBarDormancy(key, dormant) end
    -- Reveal: restore any proc glow that fired while dormant (GLOW_SHOW skipped this
    -- bar). Runs after the map flip so the queued rescan sees the bar as live.
    if not dormant and ns._eabQueueGlowRescan then ns._eabQueueGlowRescan() end
    if dormant then
        -- Strip the mixin event list: a hidden bar's buttons otherwise keep running
        -- Blizzard's full mixin OnEvent per event (state/usable/ target/charges x 12
        -- buttons x every hidden bar), billed to the CORE addon row. UnregisterEvent on
        -- template-self-registered events is the proven idiom (see GetOrCreateButton
        -- strips); NEVER wrap btn.OnEvent -- the engine resolves the method at fire
        -- time and a replacement would taint every per-button dispatch.
        local list = BUTTON_EVENT_LISTS.action
        for _, btn in ipairs(btns) do
            local fd = EFD(btn)
            if not fd.evGated then
                fd.evGated = true
                for _, ev in ipairs(list) do
                    btn:UnregisterEvent(ev)
                end
            end
        end
        return
    end
    for _, btn in ipairs(btns) do
        local fd = EFD(btn)
        if fd.evGated then
            fd.evGated = nil
            ReRegisterButtonEvents(btn, "action")
        end
        local a = btn:GetAttribute("action")
        if a and HasAction(a) then
            -- Icon/count/name/cooldown/desat/usable in one existing helper.
            EAB_VTABLE.ForceButtonRefresh(btn, a)
            -- Two channels ForceButtonRefresh doesn't own, whose events were
            -- gated: checked state and the equipped-item border.
            btn:SetChecked((IsCurrentAction(a) or IsAutoRepeatAction(a)) and true or false)
            if btn.Border then
                btn.Border:SetShown(IsEquippedAction(a) and true or false)
            end
        end
    end
    -- A bar revealed OUT of Never was skipped by the AlwaysShow pass while
    -- gated (grid state can be stale for hide-empty configs); heal once
    -- here. Never reveals are settings-driven, so this runs unlocked.
    if ns._eabBarNeverWas[key] then
        ns._eabBarNeverWas[key] = nil
        if EAB.ApplyAlwaysShowButtons then EAB:ApplyAlwaysShowButtons(key) end
    end
    -- Re-seed the cooldown walk for this bar exactly as a cast does: the
    -- dirty flag rebuilds the tier lists first, the kick delivers a full
    -- push-through pass next frame.
    ns._cdDirtyUntil = GetTime() + 2
    ns._cdWalkNext = 0
    ns._cdSlowNext = 0
    if ns._cdCastKick and not ns._cdCastKickPending then
        ns._cdCastKickPending = true
        C_Timer.After(0, ns._cdCastKick)
    end
end

do
    local _dispatcherSetup = false
    local _empowerReroutePending = false

    -- Empower keybind reroute, shared by the immediate and deferred paths. The secure
    -- re-trigger that re-evaluates pressAndHoldAction lives in UpdateKeybinds itself
    -- (pass 3) so no caller can omit it; still skipped when the routing signature is
    -- unchanged, keeping mouseover-conditional macro storms (SLOT_CHANGED on every
    -- flip) from rebuilding bindings and running the ChildUpdate snippet every frame.
    local function _EmpowerReroute()
        if _G._EAB_UpdateKeybinds then _G._EAB_UpdateKeybinds() end
    end

    function EAB:SetupEventDispatcher()
        if _dispatcherSetup then return end
        _dispatcherSetup = true
        local dispatcher = ns.TakeShell()
        ns._cdDispatcher = dispatcher
        -- Cooldown-vs-GCD classification for the desaturate and on-CD-alpha
        -- channels. Both ask the same question -- is this button on a REAL
        -- cooldown, or only on the global cooldown? -- and both must answer it
        -- without reading a secret number.
        --
        -- Why not cdInfo.isOnGCD alone: the API docs say that field is only
        -- trustworthy while responding to SPELL_UPDATE_COOLDOWN, and these
        -- visuals repaint from a dozen other places (the cast kick, the press
        -- hot lane, the charge branch, the hover and OnCooldownDone hooks, the
        -- options apply). One stale isOnGCD=false there dimmed every plain
        -- spell on the bar for the length of a GCD -- reported 8.7.7 as random
        -- alpha on cast, and the desaturate channel had the same defect. So the
        -- verdict comes from the cooldown's TOTAL duration instead, compared
        -- engine-side against the live GCD length by a Step curve: at or below
        -- the GCD the icon keeps its ready look, above it the on-cooldown look
        -- applies. The total never decays, so the verdict holds for the whole
        -- life of the cooldown (see RefreshCooldownVisuals for why the
        -- REMAINING duration cannot carry it).
        --
        -- GCD length comes from UnitSpellHaste, which is itself secret in
        -- instanced combat, so a secret read falls back to the unhasted 1.5s
        -- (same treatment as ns.GCDTailAlpha in the Cooldown Manager). That
        -- fallback and the 0.15s margin both push the threshold HIGH on
        -- purpose: too high only means a sub-GCD cooldown keeps its ready look,
        -- which is how Blizzard's own cooldown viewer treats those; too low
        -- brings the bug back.
        local _gcdStep, _gcdStepAt, _gcdStepHold
        local function GcdStep()
            local nowG = GetTime()
            if _gcdStepAt ~= nowG then
                -- GetTime is frame-constant, so the haste read below costs one
                -- call per frame no matter how many buttons repaint in it.
                _gcdStepAt = nowG
                local haste = UnitSpellHaste and UnitSpellHaste("player") or 0
                if (issecretvalue and issecretvalue(haste)) or type(haste) ~= "number" then
                    haste = 0
                end
                local len = 1.5 / (1 + haste / 100)
                if len < 0.75 then len = 0.75 end            -- engine floor
                -- Rounded to a 0.05 grid so continuous haste drift does not
                -- rebuild the curves every frame.
                local step = floor((len + 0.15) * 20 + 0.5) / 20
                -- The threshold tracks haste NOW, but a running cooldown's
                -- TOTAL was fixed by the haste in force when it started. A
                -- haste GAIN mid-GCD (Bloodlust, a large proc) shortens the
                -- GCD, and an unlatched threshold would drop below the total
                -- already recorded for the GCD in flight -- dimming the whole
                -- bar until it expired, which is the defect this whole
                -- classification exists to remove. So the step rises at once
                -- (always the safe direction) and only falls after a hold
                -- longer than any GCD it could still be measuring. The cost of
                -- the hold is that a real cooldown inside the old and new
                -- thresholds keeps its ready look for up to 2s.
                if not _gcdStep or step >= _gcdStep or nowG >= (_gcdStepHold or 0) then
                    _gcdStep = step
                    _gcdStepHold = nowG + 2
                end
            end
            return _gcdStep
        end
        -- Fallback curve for clients with no EvaluateTotalDuration: 1 for any
        -- active cooldown. The GCD threshold cannot ride the REMAINING duration
        -- -- remaining decays into the threshold and restores the icon a GCD
        -- early -- so that path keeps this any-cooldown step and leans on
        -- isOnGCD the way it did before the total-duration classification.
        local desatCurveAny
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            desatCurveAny = C_CurveUtil.CreateCurve()
            desatCurveAny:SetType(Enum.LuaCurveType.Step)
            desatCurveAny:AddPoint(0, 0)
            desatCurveAny:AddPoint(0.001, 1)
        end
        -- Desaturation curve: 0 up to the GCD length, 1 above it. Rebuilt only
        -- when the player's GCD length changes.
        local desatCurve, desatCurveStep
        local function GetDesatCurve()
            local step = GcdStep()
            if desatCurveStep ~= step and C_CurveUtil and C_CurveUtil.CreateCurve then
                desatCurve = C_CurveUtil.CreateCurve()
                desatCurve:SetType(Enum.LuaCurveType.Step)
                desatCurve:AddPoint(0, 0)
                desatCurve:AddPoint(step, 1)
                desatCurveStep = step
            end
            return desatCurve
        end
        -- On-CD alpha curve: full alpha up to the GCD length, the user's dim
        -- value above it. Rebuilt when the alpha setting or the GCD changes.
        local cdAlphaCurve, cdAlphaCurveFor, cdAlphaCurveStep
        local function GetCdAlphaCurve(cdAlpha)
            local step = GcdStep()
            if (cdAlphaCurveFor ~= cdAlpha or cdAlphaCurveStep ~= step)
               and C_CurveUtil and C_CurveUtil.CreateCurve then
                cdAlphaCurve = C_CurveUtil.CreateCurve()
                cdAlphaCurve:SetType(Enum.LuaCurveType.Step)
                cdAlphaCurve:AddPoint(0, 1)
                cdAlphaCurve:AddPoint(step, cdAlpha / 100)
                cdAlphaCurveFor = cdAlpha
                cdAlphaCurveStep = step
            end
            return cdAlphaCurve
        end
        -- Mount-state memo, one IsMounted per frame no matter how many
        -- buttons repaint in it (the GcdStep pattern): the banked-count
        -- probe below exists only for vigor-style abilities, which only
        -- exist while mounted -- so dismounted combat (the cooldown-storm
        -- case) pays zero extra C calls for it.
        local _mountedAt, _mountedNow
        local function MountedNow()
            local t = GetTime()
            if _mountedAt ~= t then
                _mountedAt = t
                _mountedNow = IsMounted() and true or false
            end
            return _mountedNow
        end
        -- Desaturation + on-CD alpha for ONE button, from live cooldown data.
        -- Called from the cooldown event loop (data prefetched; false = known
        -- absent) and from each button's OnCooldownDone edge + the infrequent
        -- full-update path (nil = fetched fresh here). Early-outs before any
        -- API call when both features are off.
        -- Why TOTAL duration and never REMAINING: the desat/alpha writes are
        -- static between repaints, and an earlier version evaluated the step
        -- against the REMAINING duration -- correct at cooldown start, but any
        -- cooldown event landing inside the step window (in combat every cast
        -- fires one) read below the threshold and restored the icon early. The
        -- TOTAL duration never decays, so the classification holds for the
        -- cooldown's entire life; the OnCooldownDone edge then restores the
        -- icon the moment the cooldown actually completes.
        local function RefreshCooldownVisuals(btn, action, cdInfo, durObj, chargeInfo)
            local desatOn = EAB.db.profile.desaturateOnCooldown
            local cdAlpha = EAB.db.profile.alphaWhenOnCD or 100
            local alphaOn = cdAlpha ~= 100
            if not desatOn and not alphaOn then return end
            local icon = btn.icon
            if not icon then return end
            if not action then
                action = btn:GetAttribute("action")
                if not action or not HasAction(action) then return end
            end
            if cdInfo == nil then
                cdInfo = C_ActionBar.GetActionCooldown(action)
                if cdInfo and cdInfo.isActive then
                    durObj = C_ActionBar.GetActionCooldownDuration(action)
                end
            end
            if chargeInfo == nil then
                chargeInfo = C_ActionBar.GetActionCharges(action)
            end
            local useRealCurve = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1
            if not useRealCurve and GetActionInfo(action) == "item" then
                useRealCurve = true
            end
            local active = cdInfo and cdInfo.isActive and durObj
            -- Banked-use gate, BOTH branches: uses remaining = ready look,
            -- with no reliance on the stale-prone isOnGCD flag. Charge
            -- spells read currentCharges (their recharge duration total is
            -- above the GCD step even with charges banked -- and a vigor
            -- ability's regen "recharge" is ALWAYS running below max, so any
            -- stale-isOnGCD repaint greyed it). Vigor sometimes reports as
            -- charges and sometimes only as a plain action count, hence the
            -- count fallback for the non-charge shape. Secret or zero values
            -- change nothing (fall to the existing classification).
            local banked = false
            if active then
                if useRealCurve and chargeInfo then
                    local cur = chargeInfo.currentCharges
                    if not (issecretvalue and issecretvalue(cur))
                        and type(cur) == "number" and cur > 0 then
                        banked = true
                    end
                elseif not useRealCurve and GetActionCount and MountedNow() then
                    -- Mounted-only: the count shape exists only for vigor
                    -- abilities, so dismounted repaints skip the probe.
                    local cnt = GetActionCount(action)
                    if not (issecretvalue and issecretvalue(cnt))
                        and type(cnt) == "number" and cnt > 0 then
                        banked = true
                    end
                end
            end
            -- A GCD must never classify a button as being on cooldown, for
            -- either channel. The GCD-length Step curve above answers that from
            -- the TOTAL duration, which is the same value for the cooldown's
            -- whole life -- so a plain spell that only carries a GCD stays
            -- ready-looking no matter which repaint path arrives, and a real
            -- cooldown keeps its on-cooldown look down to its last tick.
            --
            -- The charge/item branch keeps the extra isOnGCD guard. For those,
            -- the engine hands back a duration object whose total is the
            -- RECHARGE PERIOD (20s on Arcane Orb) even while charges are
            -- banked, so the threshold on its own would grey a spell sitting at
            -- FULL charges on every cast. A stale isOnGCD there can only fail
            -- toward the threshold, which then rejects the GCD anyway.
            if desatOn then
                local val = 0
                if active and not banked then
                    local curve = GetDesatCurve()
                    if curve and durObj.EvaluateTotalDuration then
                        if not useRealCurve or not cdInfo.isOnGCD then
                            val = durObj:EvaluateTotalDuration(curve, 0)
                        end
                    elseif durObj.EvaluateRemainingDuration and not cdInfo.isOnGCD then
                        -- Client without the total evaluator. Charge spells and
                        -- items keep the GCD-length step (remaining is
                        -- start-accurate and the Done edge fixes the tail);
                        -- plain spells take the any-cooldown step, which has no
                        -- tail to lose. Both leaned on isOnGCD before this
                        -- change and still do -- there is no threshold that
                        -- works against a decaying duration.
                        local rc = useRealCurve and curve or desatCurveAny
                        if rc then val = durObj:EvaluateRemainingDuration(rc, 0) end
                    end
                end
                -- val may be SECRET: never compare it; SetDesaturation accepts secret numbers.
                icon:SetDesaturation(val or 0)
            end
            if alphaOn then
                local alphaSet = false
                if active and not banked then
                    local curve = GetCdAlphaCurve(cdAlpha)
                    if curve and durObj.EvaluateTotalDuration then
                        if not useRealCurve or not cdInfo.isOnGCD then
                            icon:SetAlpha(durObj:EvaluateTotalDuration(curve, 1) or 1)
                            alphaSet = true
                        end
                    elseif icon.SetAlphaFromBoolean and durObj.IsZero
                       and not cdInfo.isOnGCD then
                        -- Client without the total evaluator. IsZero() is a
                        -- secret boolean; SetAlphaFromBoolean consumes it
                        -- without any Lua comparison. This path has no GCD
                        -- threshold, so it leans on isOnGCD as before.
                        icon:SetAlphaFromBoolean(durObj:IsZero(), 1, cdAlpha / 100)
                        alphaSet = true
                    end
                end
                if not alphaSet then icon:SetAlpha(1) end
            end
        end
        -- Exposed for per-button OnCooldownDone edge hooks (button creation).
        EAB._RefreshCooldownVisuals = function(btn)
            if btn and btn.GetAttribute then RefreshCooldownVisuals(btn) end
        end

        -- One-shot corrective sweep for the Desaturate on Cooldown toggle; called ONLY
        -- from that option's setValue, never an event or pass. Push machinery is
        -- edge-only and the visuals writer early-outs when both features are off, so a
        -- grey icon at uncheck time has no path back to color until its next cooldown
        -- edge (mirror on checking mid-cooldown). OFF clears the desat channel outright
        -- (alpha owns SetAlpha, untouched); ON recomputes each button so running
        -- cooldowns grey immediately.
        EAB._DesatSettingChanged = function(enabled)
            for _, info in ipairs(BAR_CONFIG) do
                local btns = barButtons[info.key]
                if btns then
                    for i = 1, #btns do
                        local btn = btns[i]
                        if btn then
                            if enabled then
                                RefreshCooldownVisuals(btn)
                            elseif btn.icon and btn.icon.SetDesaturation then
                                btn.icon:SetDesaturation(0)
                            end
                        end
                    end
                end
            end
        end

        -- Per-button cooldown push: the swipe-only body (cd fetch, push on active edge
        -- via duration objects, Clear on the fall, opt-in desat/alpha), shared by the
        -- spell-keyed passes below and the residual slot walk. Spell-keyed callers
        -- prefetch the group's cooldown struct (ci) and duration object (gDur) ONCE per
        -- group: for a spell-typed action the action cooldown IS the spell cooldown
        -- (tier memos gate every push on that equivalence), so per-button struct/object
        -- fetches (the module's top combat allocation source) only remain for the
        -- residual non-spell walk and the running-real re-push, where no spell key
        -- exists. Pushes stay unconditional for actively-pressed (hot) buttons: a spell
        -- QUEUED mid-GCD updates the engine's cooldown record at press, but every
        -- readable field crosses that transition unchanged (isActive stays true,
        -- schedule secret in instances) -- the default UI paints at press only because
        -- its update is unconditional. Its numeric SetCooldown path is closed to addon
        -- code (SecretArguments AllowedWhenUntainted), so the unconditional push goes
        -- through the duration-object sink.
        local function PushButtonCooldown(btn, visOn, ci, gDur)
            local action = btn:GetAttribute("action")
            if not action or not HasAction(action) then return end
            local fd = EFD(btn)
            -- Assist host: its slot cooldown mirrors whatever the engine is
            -- suggesting at the instant it is read, so a slot-fed push here can
            -- land on a different ability than the icon the assist ticker
            -- painted -- the same split ns.PaintAssistCooldown closes. Every
            -- cooldown event (any cast, any bar) reaches this function, so the
            -- ticker's fix must own this path too. The spinner read keeps the
            -- check a raw table lookup for every other button.
            if fd.assistSpin and C_ActionBar.IsAssistedCombatAction
               and C_ActionBar.IsAssistedCombatAction(action) then
                return ns.PaintAssistCooldown(btn, ns._assistLastSuggest)
            end
            local cd = btn.cooldown
            local durObj = gDur
            local cdInfo = ci or C_ActionBar.GetActionCooldown(action)
            local active = (cdInfo and cdInfo.isActive) and true or false
            local cdReal = active and not cdInfo.isOnGCD
            local cdClassFlip = cdReal ~= (fd.cdWasReal or false)
            if cd then
                if active then
                    -- PUSH-THROUGH: no change gate. A same-frame-as-cast push may hand
                    -- over a not-yet-populated (in combat SECRET, so uninspectable)
                    -- duration object -- fine because nothing gates: the cast kick's
                    -- next-frame pass and every capped pass while active re-deliver
                    -- fresh objects, so a provisional paint self-corrects within a
                    -- frame instead of being memo-stranded.
                    if not durObj then
                        durObj = C_ActionBar.GetActionCooldownDuration(action)
                    end
                    if durObj then cd:SetCooldownFromDurationObject(durObj) end
                elseif fd.cdWasActive then
                    cd:Clear()
                end
            end
            -- Visuals (desat/alpha) ride the same doctrine: repaint on every
            -- push while active plus the falling edge -- cheap setters, and
            -- Blizzard's UpdateUsable stomps vertex state mid-cooldown, so
            -- change-gating here would recreate the stale-desat class.
            if visOn and (active or (fd.cdWasActive or false) or fd.chargeWasLive
               or cdClassFlip) then
                if active and not durObj then
                    durObj = C_ActionBar.GetActionCooldownDuration(action)
                end
                RefreshCooldownVisuals(btn, action, cdInfo or false, durObj, nil)
            end
            -- Charge recharge numbers ride the real-cooldown CLASS EDGE. The
            -- occlusion rule (hide charge numbers while a real main cooldown
            -- shows its own countdown) caches its verdict, and its cdReal input
            -- was previously re-read ONLY by the charge event walk -- whose
            -- evaluation at the spend edge lands inside the server-ack window
            -- where the cooldown snapshot LIES (recharge-start reads as a real
            -- main cooldown). The wrong "hidden" verdict then stranded for the
            -- whole recharge: no later charge event re-evaluates, and this pass
            -- observed the lie settle without owning the numbers channel. The
            -- flip below fires exactly when cdReal changes (ack settle, real
            -- main cooldown ending), completing the rule's input coverage --
            -- one nil-check per push otherwise, no new gates on the swipe path.
            if cdClassFlip and btn.chargeCooldown then
                ns.UpdateChargeNumbersVisibility(btn, btn.chargeCooldown, cdInfo,
                    C_ActionBar.GetActionCharges(action))
            end
            fd.cdWasActive = active
            fd.cdWasReal = cdReal
            if active then return true end
        end
        dispatcher:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        dispatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN") -- aliased to ACTIONBAR_UPDATE_COOLDOWN in the handler
        -- Dirty-trigger only (early return in handler): a player cast is the
        -- reliable herald of new cooldowns, re-arming the heartbeat walk
        -- below without running button work itself.
        dispatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        -- Cancel heralds, same dirty-trigger shape: a cancelled cast REFUNDS the GCD,
        -- and a shortened cooldown fires no action-bar event (see SPELL_UPDATE_COOLDOWN
        -- alias note) -- the spell event accompanying the refund lands in the cancel's
        -- own frame, inside the cooldown API's transient-disagreement window. Without
        -- an owning edge the pushed swipe plays out full-length on the cancelled spell.
        -- Player-filtered: silent at idle.
        dispatcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        dispatcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        dispatcher:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
        -- Press-time hot-lane triggers (handler's press branch): earliest
        -- edges observing a QUEUED press's cooldown-record update. Quiet
        -- outside active casting; the branch is a nil-check otherwise.
        dispatcher:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        dispatcher:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
        -- ACTIONBAR_UPDATE_STATE deliberately NOT registered: every button's own
        -- Blizzard mixin receives it per button (BUTTON_EVENT_LISTS.action) and drives
        -- SetChecked natively -- a central checked walk is redundant (field-verified).
        -- C_ActionBar.RegisterActionUIButton was probed as a possible engine-side swipe
        -- driver; it paints NOTHING for our buttons (do not re-chase it).
        dispatcher:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
        dispatcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        dispatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        dispatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        dispatcher:RegisterEvent("SPELL_UPDATE_CHARGES")
        dispatcher:RegisterEvent("SPELL_UPDATE_ICON")
        dispatcher:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
        dispatcher:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
        -- Owning edges for Blizzard paging (page arrows, stealth/form bonus
        -- bars): these re-map action attributes, so must land in the
        -- infrequent branch as content edges -- nothing else heals the filled lists.
        dispatcher:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        dispatcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
        dispatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        dispatcher:RegisterEvent("CVAR_UPDATE")  -- "Show numbers for cooldowns" toggled -> re-apply charge recharge numbers
        -- Owning edge for item-count changes on buttons (loot, mail,
        -- vendoring -- none of which cast). Dirty-trigger via the infrequent
        -- branch; also forces the next walk's count pass.
        dispatcher:RegisterEvent("BAG_UPDATE_DELAYED")
        -- Viewer DATA events (talent/hotfix/override re-curation): pure data signals,
        -- no dependency on CDM or the Blizzard viewer UI. Land in the infrequent
        -- branch, retiring button lists via ns._cdFilledDirty; the curated-set memo
        -- retires separately (ns._cdCuratedDirty) -- these three plus SPELLS_CHANGED
        -- and PEW are the ONLY edges that can change what the viewer curates.
        dispatcher:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        dispatcher:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
        dispatcher:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
        -- Per-button content refresh for a changed slot. Shared by the
        -- dispatcher's SLOT_CHANGED full walk (arg1 == 0) and the
        -- slot->buttons fast path; on ns because this chunk is at the 200-local cap.
        ns._eabSlotRefreshBtn = function(btn, action)
            -- Assisted-combat slot: its "content changes" are the manager
            -- re-stamping the suggestion (idle spam plus per rotation step in
            -- combat) and only the ICON can differ -- a full refresh would
            -- repaint count/cooldown/tint identically forever. Icon-only,
            -- secret-tolerant setters; cooldown swipes ride the COOLDOWN branch.
            local _, _, subType = GetActionInfo(action)
            if subType == "assistedcombat" then
                local icon = btn.icon or btn.Icon -- same member resolution as ForceButtonRefresh
                if icon then
                    icon:SetTexture(GetActionTexture(action))
                    icon:SetShown(HasAction(action))
                end
            else
                -- Slot CONTENTS changed while slot number stayed (spec swap,
                -- drag-drop): needs the forced refresh path (ForceButtonRefresh).
                EAB_VTABLE.ForceButtonRefresh(btn, action)
                -- Content changed: drop this slot's memos so every cached visual re-derives fresh.
                local mfd = EFD(btn)
                mfd.lastCountText = nil
                mfd.usableState = nil
                -- Slot emptied: refresh leaves stale count text behind
                -- (buttons no longer receive ACTIONBAR_SLOT_CHANGED themselves).
                local filled = HasAction(action)
                if btn.Count and not filled then
                    btn.Count:SetText("")
                end
                -- Blizzard icon background follows slot contents, same reason
                -- as count text (no per-button OnEvent sees this event), so a
                -- vacated slot kept its background hidden. Raw read (not
                -- EFD()): don't allocate per-button state for options never built.
                local bfd = ns._eabFD[btn]
                local clip = bfd and bfd.iconBgClip
                if clip then
                    local p2 = EAB.db and EAB.db.profile
                    clip:SetShown((p2 and p2.showBlizzIconBg or false) and not filled)
                end
                -- Classic WoW UI: the slot ring vs empty-slot art follows the
                -- same content edge (one field read on every other look).
                if bfd and bfd.classicArt then
                    ns.AB_ClassicSlotRing(btn, filled)
                end
            end
        end
        -- The cast kick: ONE authoritative next-frame pass, shared by the
        -- cast and cancel branches below. Built at setup, under this AB-born
        -- entry, so the timer callback bills ActionBars (closures carry their creation context).
        ns._cdCastKick = function()
            ns._cdCastKickPending = nil
            -- A wave that already ran THIS frame outside the cast's own frame
            -- is a settled delivery (a real event beat the timer to it):
            -- re-waving would be a same-frame duplicate, so skip. A wave
            -- consumed in the cast's OWN frame is provisional (may have read
            -- the transient window) and never satisfies this.
            if ns._cdWaveAt == GetTime() and ns._gcdCastAt ~= GetTime() then
                return
            end
            -- Re-open the two rate gates: the cast branch zeroes both, but a cooldown
            -- event in the cast's OWN frame consumes that opening and re-arms them
            -- (storm cap +0.15s, slow tier +0.5s) off a state read inside the API's
            -- transient-disagreement window -- the kick would then be capped out
            -- entirely, and the slow tier (most of the bar: utility spells, items,
            -- macros) would keep the transient paint until its gate expired or the
            -- ~1/sec heartbeat. Measured: swipe starts a mean 231-304ms late (tails
            -- past 500ms) before; 85ms mean, nothing past 208ms, after. Self- limiting:
            -- kick is once per cast (pending guard), already 0 when settled.
            ns._cdWalkNext = 0
            ns._cdSlowNext = 0
            -- The kick fires from the timer phase, AFTER the frame's event dispatch: a
            -- real cooldown event earlier THIS frame already stamped the same-frame
            -- dedupe, so the kick's dispatch would dedupe-return and the settled wave
            -- STRAND (castWave armed, gates open) until the next cooldown event. Under
            -- combat secrecy the diff passes can't see a chained cast's new schedule
            -- (isActive never flips), so the stranded wave was the swipe's ONLY
            -- carrier -- swipe starts drifted progressively later through a fight
            -- (0.5s-class tails). Clearing the stamp makes the kick's wave
            -- deterministic at zero net cost (the diff pass plus this wave cost what
            -- the stranded wave cost anyway, timed right).
            local st2 = ns._evStamps
            if st2 then st2["ACTIONBAR_UPDATE_COOLDOWN"] = nil end
            local d2 = ns._cdDispatcher
            local h2 = d2 and d2:GetScript("OnEvent")
            if h2 then h2(d2, "ACTIONBAR_UPDATE_COOLDOWN") end
            -- If this kick's wave landed inside a NEWER cast's own frame
            -- (cancel -> instant weave: that cast's SUCCEEDED saw our pending
            -- flag and armed nothing), the delivery above was provisional for
            -- it -- re-arm once so its settled wave still gets a carrier.
            -- Self-terminating: the re-armed kick runs later, where this condition is false.
            if ns._gcdCastAt == GetTime() and not ns._cdCastKickPending then
                ns._cdCastKickPending = true
                C_Timer.After(0, ns._cdCastKick)
            end
        end
        -- Named walk branches: one named function per event class, in the
        -- same do-block scope so every local the bodies reference resolves.
        local function DispWalkCharges(walkBtns)
            -- Dedicated branch: fires per charge-regen tick (scales with charge spells
            -- mid-recharge); falling through to the infrequent branch would run full
            -- mixin UpdateAction on all ~140 buttons per tick. A charge tick can only
            -- move charge visuals: recharge swipe, count text, charge-aware desat.
            for _, btn in ipairs(walkBtns) do
                local action = btn:GetAttribute("action")
                if action and HasAction(action) then
                    local fd = EFD(btn)
                    -- Unconditional fetch: fires only on charge ticks, and
                    -- this branch is the SOLE owner of charge visuals.
                    local chargeInfo = C_ActionBar.GetActionCharges(action)
                    local chargeShown = (chargeInfo and chargeInfo.maxCharges
                        and chargeInfo.maxCharges > 1) and true or false
                    if chargeShown then
                        -- Hoisted out of the occlusion call below: the MAIN
                        -- cooldown mirrors the recharge at 0 charges, so
                        -- regaining a charge silently stops it being a real
                        -- cooldown with no `active` edge mid-GCD. A reduction
                        -- proc that collapses the recharge lands here first:
                        -- repaint this one button now (push-or-clear, three C
                        -- calls) so the old countdown never ticks on a spell
                        -- back up; push-through walks re-derive the rest.
                        local ci = C_ActionBar.GetActionCooldown(action)
                        local cdReal = (ci and ci.isActive and not ci.isOnGCD) and true or false
                        if cdReal ~= (fd.cdWasReal or false) then
                            -- Assist host: swipe follows the ticker's sample,
                            -- never the slot (see PushButtonCooldown).
                            if fd.assistSpin and C_ActionBar.IsAssistedCombatAction
                               and C_ActionBar.IsAssistedCombatAction(action) then
                                ns.PaintAssistCooldown(btn, ns._assistLastSuggest)
                            else
                                ForceCooldownPaint(btn)
                            end
                            fd.cdWasReal = cdReal
                        end
                        local chargeCd = btn.chargeCooldown
                        if not chargeCd and chargeInfo.isActive then
                            chargeCd = ns.EnsureChargeCooldown(btn)
                        end
                        if chargeCd then
                            -- Off-GCD charge spends can hit 0 charges without
                            -- a COOLDOWN walk in between; keep the occlusion
                            -- rule current from the charge tick too.
                            ns.UpdateChargeNumbersVisibility(btn, chargeCd, ci, chargeInfo)
                            if chargeInfo.isActive then
                                local chargeDur = C_ActionBar.GetActionChargeDuration(action)
                                if chargeDur then chargeCd:SetCooldownFromDurationObject(chargeDur) end
                            else
                                chargeCd:Clear()
                            end
                        end
                        -- nil (not false) cd args: the shared function re-fetches
                        -- main-cd state itself for these few charge buttons.
                        RefreshCooldownVisuals(btn, action, nil, nil, chargeInfo)
                    elseif btn.chargeCooldown then
                        btn.chargeCooldown:Clear() -- falling edge (temp charge expired, talent swap)
                    end
                    -- Count write sits OUTSIDE the chargeShown gate: a proc can grant a
                    -- TEMPORARY charge to a spell with none by default (e.g. Shadowy
                    -- Insights), so maxCharges runs 1->2->1 and gating on maxCharges>1
                    -- switches the write off exactly when the count needs clearing
                    -- (stranded until the ~2s count sub-pass). This event fires
                    -- ~0.1/sec, so writing unconditionally costs nothing.
                    if btn.Count and C_ActionBar.GetActionDisplayCount then
                        -- Raw read, guard, THEN coerce. The `or ""` used to sit
                        -- on this line, ahead of the issecretvalue check below,
                        -- so a restricted-cooldown return (raids, keys) was
                        -- coerced before anything established it was safe to
                        -- touch. A throw here aborts the walk, and this handler
                        -- is the SOLE owner of the count text, so the number
                        -- freezes at its last value.
                        local display = C_ActionBar.GetActionDisplayCount(action)
                        if issecretvalue and issecretvalue(display) then
                            btn.Count:SetText(display)
                            fd.lastCountText = nil
                        else
                            if display == nil then display = "" end
                            if fd.lastCountText ~= display then
                                fd.lastCountText = display
                                btn.Count:SetText(display)
                            end
                        end
                        ns._EABZeroCountAlpha(fd, btn.Count, display, action)
                    end
                    fd.chargeWasLive = (chargeInfo and chargeInfo.isActive) and true or false
                end
            end
        end
        -- Shared per-button icon heal (texture-delta memo). Texture fileID is
        -- the override's visible fingerprint (never secret per the API
        -- docs), so only buttons whose texture actually changed pay the
        -- mixin path. INVARIANT: the memo must equal what is ON the icon,
        -- so every path that paints the ACTION's texture stamps it too
        -- (ForceButtonRefresh) -- a late-resolving override means an
        -- unstamped paint CAN differ from the memo, and a diverged memo
        -- turns this heal's skip into a wrong skip. The assist painters are
        -- the deliberate exception -- they paint the SUGGESTED spell's
        -- texture, not the action's, and stamping that would clobber them.
        -- Used by the full walk below and the payload-targeted
        -- SPELL_UPDATE_ICON fast path; ns-hosted (200-local cap).
        ns._cdIconHeal = function(btn)
            local action = btn:GetAttribute("action")
            if action and HasAction(action) then
                local tex = GetActionTexture(action)
                local fd = EFD(btn)
                if fd.lastIconTex ~= tex then
                    fd.lastIconTex = tex
                    -- Taint-safe refresh; avoids passing secret cooldown values through a tainted call.
                    EAB_VTABLE.ForceButtonRefresh(btn, action)
                end
            end
        end
        local function DispWalkIcon(btns)
            -- Spell overrides change the icon without changing the slot;
            -- heal is memoized per button (ns._cdIconHeal): a morph storm
            -- changes a handful of buttons, never the whole set -- before this memo, the walk ran full mixin UpdateAction on every populated button per pass, the heaviest single line in the module's worst frames.
            local heal = ns._cdIconHeal
            for _, btn in ipairs(btns) do
                heal(btn)
            end
        end
        local function DispWalkUsable(btns)
                            for _, btn in ipairs(btns) do
                                local ufd = EFD(btn)
                                if ufd.rangeTinted then
                                    -- Skip: range system owns vertex color for tinted buttons; force repaint once it releases.
                                    ufd.usableState = nil
                                else
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    local isUsable, notEnoughMana = IsUsableAction(action)
                                    -- Tri-state memo: USABLE storms with every
                                    -- resource change while chain-casting;
                                    -- unchanged buttons skip the vertex push.
                                    local ustate = (isUsable and 1) or (notEnoughMana and 2) or 3
                                    if ufd.usableState ~= ustate then
                                        ufd.usableState = ustate
                                        local icon = btn.icon
                                        if icon then
                                            if ustate == 1 then
                                                icon:SetVertexColor(1.0, 1.0, 1.0)
                                            elseif ustate == 2 then
                                                icon:SetVertexColor(0.5, 0.5, 1.0)
                                            else
                                                icon:SetVertexColor(0.4, 0.4, 0.4)
                                            end
                                        end
                                    end
                                end
                                end
                            end
        end
        -- Filled-list + tier-map rebuild (see the dirty-check site in the dispatcher),
        -- named for profiler attribution; publishes via ns._cdFilled / tier maps. Table
        -- pool for the short-generation tables (rule 8: the rebuild allocated ~5.6KB
        -- per run at ~1-2 runs/sec in combat, pure GC food). Pool bounded by one
        -- generation's table count (~50); reuse is semantically identical since fresh
        -- and wiped groups both start with empty memo fields.
        local function CdTakeTable()
            local pool = ns._cdTablePool
            local n = pool and #pool or 0
            if n > 0 then
                local t = pool[n]
                pool[n] = nil
                return t
            end
            return {}
        end
        local function DispRebuildLists()
                    ns._cdFilledDirty = nil
                    -- Same-frame stamp for the rebuild cap at the dirty-check
                    -- site (GetTime is frame-constant).
                    ns._cdRebuiltAt = GetTime()
                    -- Retire the previous generation into the pool before taking
                    -- replacements. Nothing holds these tables across events: every
                    -- consumer re-reads ns._cdFilled and the tier maps per pass.
                    local pool = ns._cdTablePool
                    if not pool then pool = {}; ns._cdTablePool = pool end
                    local pn = #pool
                    local oldFilled = ns._cdFilled
                    if oldFilled then
                        for _, list in pairs(oldFilled) do
                            table.wipe(list); pn = pn + 1; pool[pn] = list
                        end
                        table.wipe(oldFilled); pn = pn + 1; pool[pn] = oldFilled
                    end
                    local oldFast = ns._cdFastSpells
                    if oldFast then
                        for _, g in pairs(oldFast) do
                            table.wipe(g); pn = pn + 1; pool[pn] = g
                        end
                        table.wipe(oldFast); pn = pn + 1; pool[pn] = oldFast
                    end
                    local oldSlow = ns._cdSlowSpells
                    if oldSlow then
                        for _, g in pairs(oldSlow) do
                            table.wipe(g); pn = pn + 1; pool[pn] = g
                        end
                        table.wipe(oldSlow); pn = pn + 1; pool[pn] = oldSlow
                    end
                    local oldRes = ns._cdResidual
                    if oldRes then
                        table.wipe(oldRes); pn = pn + 1; pool[pn] = oldRes
                    end
                    local _filled = CdTakeTable()
                    ns._cdFilled = _filled
                    -- SPELL-KEYED CLASSIFICATION for the targeted cooldown
                    -- passes. Slots dedup to unique spells (pages duplicate
                    -- heavily), split into two cadence tiers:
                    --   fast = viewer-CURATED rotation kit (pure DATA api,
                    --          zero dependency on CDM or the viewer being
                    --          shown; talent-aware). No curated data at all
                    --          (client variance) = every spell is fast.
                    --   slow = every other spell slot (utilities).
                    --   residual = non-spell slots (items, macros -- whose
                    --          resolved spell shifts with modifier keys --
                    --          mounts): slot-polled at the slow cadence.
                    local fast, slow, residual = CdTakeTable(), CdTakeTable(), CdTakeTable()
                    ns._cdFastSpells, ns._cdSlowSpells, ns._cdResidual = fast, slow, residual
                    -- curated[sid] = true (Essential rotation kit -> fast
                    -- tier) or false (other curated category -> slow). The fast tier
                    -- must stay LEAN: its per-pass fetch floor runs at the capped storm
                    -- rate, and under combat secrecy every cast cycles every fast
                    -- spell's readable state twice (GCD on/off); utilities' rare
                    -- castless changes tolerate 0.5s. Memoized separately from the list
                    -- rebuild: curated data only changes on COOLDOWN_VIEWER_* /
                    -- SPELLS_CHANGED / spec edges, but LISTS retire on every content
                    -- edge (~1 rebuild/sec across a fight) -- the pcall-per-category
                    -- viewer walk ran ~90x/fight for data that changed maybe twice.
                    local curated = ns._cdCuratedMemo
                    if not curated or ns._cdCuratedDirty then
                        ns._cdCuratedDirty = nil
                        curated = {}
                        ns._cdCuratedMemo = curated
                        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
                            and C_CooldownViewer.GetCooldownViewerCooldownInfo and Enum.CooldownViewerCategory then
                            local essential = Enum.CooldownViewerCategory.Essential
                            for _, cat in pairs(Enum.CooldownViewerCategory) do
                                local isEss = (cat == essential)
                                local okS, set = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat)
                                if okS and type(set) == "table" then
                                    for _, cdID in ipairs(set) do
                                        local okI, ci = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                                        if okI and ci and ci.spellID then
                                            local function mark(id)
                                                if not id or id <= 0 then return end
                                                if isEss or curated[id] == nil then curated[id] = isEss end
                                            end
                                            mark(ci.spellID)
                                            mark(ci.overrideSpellID)
                                            if type(ci.linkedSpellIDs) == "table" then
                                                for _, lid in ipairs(ci.linkedSpellIDs) do mark(lid) end
                                            end
                                            if C_Spell and C_Spell.GetBaseSpell then
                                                mark(C_Spell.GetBaseSpell(ci.spellID))
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    local haveCurated = next(curated) ~= nil
                    for _, info in ipairs(BAR_CONFIG) do
                        if not info.isStance and not info.isPetBar then
                            -- Dormant (driver-hidden) bars are excluded from lists
                            -- and tier groups entirely. Reads the dormancy map, not
                            -- live IsVisible(): the map is edge-driven and every
                            -- edge also sets _cdFilledDirty, so lists and gating
                            -- can never disagree mid-transition. A bar flipping
                            -- visible rejoins on the next rebuild; its show-edge
                            -- reconcile repaints it meanwhile.
                            local btns = (not ns._eabBarDormant[info.key])
                                and (not ns._eabBarNever[info.key])
                                and barButtons[info.key] or nil
                            if btns then
                                local list = CdTakeTable()
                                for _, btn in ipairs(btns) do
                                    local a = btn:GetAttribute("action")
                                    if a and HasAction(a) then
                                        list[#list + 1] = btn
                                        local aType = GetActionInfo(a)
                                        local sid = C_ActionBar.GetSpell and C_ActionBar.GetSpell(a)
                                        if aType == "spell" and sid and sid > 0 then
                                            local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(sid)
                                            -- Essential (true) -> fast; any other
                                            -- curated (false) or uncurated (nil)
                                            -- -> slow. No curated data at all ->
                                            -- everything fast (degraded client).
                                            local tier
                                            if not haveCurated then
                                                tier = fast
                                            elseif curated[sid] or (base and base > 0 and curated[base]) then
                                                tier = fast
                                            else
                                                tier = slow
                                            end
                                            local g = tier[sid]
                                            if not g then g = CdTakeTable(); tier[sid] = g end
                                            g[#g + 1] = btn
                                        else
                                            residual[#residual + 1] = btn
                                        end
                                    end
                                end
                                _filled[info.key] = list
                            end
                        end
                    end
        end
        -- Targeted-probe body (see the dispatch site below), named for profiler
        -- attribution. g is the tier group for key; push-through, same semantics as the
        -- tier body -- one fetch + one duration object per probe, pushed to the group's
        -- buttons unconditionally. Payload events fire at chatter rate, so a probe
        -- costs a handful of sink calls on the one named group.
        local function DispProbe(g, key)
                    local p = EAB.db.profile
                    local visOn = p.desaturateOnCooldown
                        or (p.alphaWhenOnCD or 100) ~= 100
                    local GetSpellCd = C_Spell and C_Spell.GetSpellCooldown
                    local GetSpellCdDur = C_Spell and C_Spell.GetSpellCooldownDuration
                    local live = false
                    local ci = GetSpellCd and GetSpellCd(key) or nil
                    local gDur
                    if ci and ci.isActive then
                        live = true
                        if GetSpellCdDur then gDur = GetSpellCdDur(key) end
                    elseif not GetSpellCd then
                        live = true
                    end
                    for i = 1, #g do
                        if PushButtonCooldown(g[i], visOn, ci, gDur) then live = true end
                    end
                    -- A live schedule needs the heartbeat awake for its END
                    -- transition: the settled gate would otherwise sleep
                    -- through it (OnCooldownDone covers the swipe edge, but
                    -- desat/alpha recovery rides the passes).
                    if live then ns._cdDirtyUntil = GetTime() + 2 end
        end
            -- TARGETED COOLDOWN PASSES (spell-keyed): PUSH-THROUGH, no value memos.
            -- Every capped pass fetches per UNIQUE SPELL and pushes fresh state to
            -- every hosting button unconditionally, sink-style (duration objects handed
            -- to the widget, never read). This is a SANCTIONED paint-the-world
            -- exception on the swipe channel: the per-spell startTime/duration memos
            -- compared against snapshot values that LIE during the server-ack window
            -- (secret in instanced combat), and every eaten transition in this saga --
            -- late GCD swipes, stale charge overlays, stranded waves -- traced to a
            -- memo or gate sitting between the event and SetCooldown. The economy still
            -- comes from SPELL-keyed batching (one fetch per unique spell, not per
            -- button), the same-frame event collapse, the 0.15s storm cap, the 0.5s
            -- slow-tier cadence, and idle sleep: pushes are cheap C sink calls; the
            -- comparisons were the bug. Falling edges are additionally caught per
            -- button by the OnCooldownDone hooks.
        -- Named so the profiler attributes the pass separately from event
        -- dispatch. Returns true when any live schedule was seen (the
        -- caller ORs it into its settled-detection flag).
        local function DispCooldownPass()
                local liveSeen = false
                local p = EAB.db.profile
                local visOn = p.desaturateOnCooldown
                    or (p.alphaWhenOnCD or 100) ~= 100
                local GetSpellCd = C_Spell and C_Spell.GetSpellCooldown
                local GetSpellCdDur = C_Spell and C_Spell.GetSpellCooldownDuration
                -- One duration-object fetch per GROUP (unique spell), never
                -- per button -- and NEVER one shared GCD object across
                -- groups whose struct read isOnGCD=true: the API docs say
                -- that field is only trustworthy in a direct
                -- SPELL_UPDATE_COOLDOWN response, and these passes also run
                -- from synthesized dispatches (cast kick, cap flushes, hot
                -- lane). A REAL cooldown reading a stale isOnGCD=true gets
                -- painted with the ~1s GCD object: swipe sweeps too fast,
                -- finishes early, button sits swipe-less until a later
                -- repaint lands mid-cooldown.
                local function RunGroup(g, sid, ci)
                    local gDur
                    if ci and ci.isActive and GetSpellCdDur then
                        gDur = GetSpellCdDur(sid)
                    end
                    for i = 1, #g do
                        if PushButtonCooldown(g[i], visOn, ci, gDur) then liveSeen = true end
                    end
                end
                -- Pass-delivery stamp: lets the cast kick skip its re-pass
                -- when a real event already ran a settled pass in the
                -- kick's own frame (GetTime is frame-constant).
                ns._cdWaveAt = GetTime()
                local function RunTier(tier)
                    if not tier then return end
                    for sid, g in pairs(tier) do
                        local ci = GetSpellCd and GetSpellCd(sid) or nil
                        RunGroup(g, sid, ci)
                        -- Any active schedule (incl. the GCD, and secret
                        -- schedules -- isActive stays readable) keeps the
                        -- heartbeat awake for the END transition.
                        if not GetSpellCd or (ci and ci.isActive) then
                            liveSeen = true
                        end
                    end
                end
                RunTier(ns._cdFastSpells)
                local nowS = GetTime()
                if nowS >= (ns._cdSlowNext or 0) then
                    ns._cdSlowNext = nowS + 0.5
                    RunTier(ns._cdSlowSpells)
                    local res = ns._cdResidual
                    if res then RunGroup(res) end
                end
                return liveSeen
        end
        -- Force-push the recently-PRESSED buttons from fresh state. Called from every
        -- cooldown-event fire AND the press-time triggers while the 3s window is open;
        -- collapses to nil-checks outside it. The ring is keyed by BUTTON, never spell
        -- id: ids are SECRET in instanced combat, so an id-keyed ring would silently
        -- no-op exactly where the server-ack window exists. Button references carry no
        -- secrets; the push resolves the CURRENT action at fetch time, so
        -- paging/content changes self-correct. Only the pressed button ever has an ack
        -- window; duplicates of its spell on other bars ride the waves.
        local function HotPushRecent()
            local b1 = ns._cdRecentBtn1
            if not b1 then return end
            local nowH = GetTime()
            if (nowH - (ns._cdRecentBtn1At or 0)) >= 3 then
                ns._cdRecentBtn1, ns._cdRecentBtn1At = nil, nil
                ns._cdRecentBtn2, ns._cdRecentBtn2At = nil, nil
                return
            end
            local pH = EAB.db.profile
            local visH = pH.desaturateOnCooldown
                or (pH.alphaWhenOnCD or 100) ~= 100
            PushButtonCooldown(b1, visH)
            local b2 = ns._cdRecentBtn2
            if b2 and b2 ~= b1 and (nowH - (ns._cdRecentBtn2At or 0)) < 3 then
                PushButtonCooldown(b2, visH)
            end
        end
        -- Physical-press paint (each button's PostClick hook): the client PREDICTS the
        -- GCD at the hardware press and updates the action cooldown record immediately,
        -- while every UNIT_SPELLCAST_* edge waits a full server round-trip -- the
        -- residual press-to-swipe gap under latency. Push the clicked button from the
        -- predicted record NOW, prime it as the hot spell (window covers presses after
        -- a lull; following chatter re-asserts it), and arm the bar-wide wave+kick so
        -- every ready button's GCD starts at the press. Runs at user press rate.
        ns._EABPressPush = function(btn)
            local p = EAB.db.profile
            local visOn = p.desaturateOnCooldown
                or (p.alphaWhenOnCD or 100) ~= 100
            PushButtonCooldown(btn, visOn)
            -- Prime the button-keyed hot ring (no ids read -- see
            -- HotPushRecent): the pressed button gets event-rate re-pushes
            -- through its ack window in every ruleset, secrecy included.
            if ns._cdRecentBtn1 ~= btn then
                ns._cdRecentBtn2, ns._cdRecentBtn2At = ns._cdRecentBtn1, ns._cdRecentBtn1At
                ns._cdRecentBtn1 = btn
            end
            ns._cdRecentBtn1At = GetTime()
            ns._cdDirtyUntil = GetTime() + 2
            ns._cdWalkNext = 0
            ns._cdSlowNext = 0
            if not ns._cdCastKickPending then
                ns._cdCastKickPending = true
                C_Timer.After(0, ns._cdCastKick)
            end
        end
        -- Direct API calls bypass the mixin's OnEvent dispatch, which
        -- triggers UpdateButtonArt (noop + hook), icon bg hook, and other
        -- per-button overhead. With 60 populated buttons, the mixin path
        -- caused visible frame drops on high-frequency events.
        dispatcher:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
            -- Press-time triggers for the hot set: a press QUEUED inside the
            -- running GCD updates the engine's cooldown record at the press
            -- itself (client-side), and these are the earliest edges that can
            -- see it -- so the spammed button's next GCD paints at the press,
            -- not at the queued cast's SUCCEEDED.
            if event == "UNIT_SPELLCAST_SENT" or event == "CURRENT_SPELL_CAST_CHANGED" then
                HotPushRecent()
                -- Full-bar parity: the queued press starts the NEXT GCD for
                -- every ready button, so SENT (once per actual press) arms
                -- the same wave+kick a cast does -- the whole bar's swipe
                -- starts at the press, one frame later at most. No gen bump
                -- (nothing cast yet); the kick's settled-wave dedupe keeps
                -- collisions with the real cast's own wave to zero extra.
                if event == "UNIT_SPELLCAST_SENT" then
                    ns._cdDirtyUntil = GetTime() + 2
                    ns._cdWalkNext = 0
                    ns._cdSlowNext = 0
                    if not ns._cdCastKickPending then
                        ns._cdCastKickPending = true
                        C_Timer.After(0, ns._cdCastKick)
                    end
                end
                return
            end
            -- HOT LANE: the spells the player just cast get default-UI
            -- latency. The 0.15s storm cap is correct economics for ~50
            -- settled buttons, but on the actively-pressed button it
            -- stretches the engine's own server-ack window (cooldown reads
            -- isActive=true before its schedule handle populates; a capped
            -- pass lands up to 150ms after the data turns real). The recently-cast 1-2
            -- buttons are re-pushed with a FRESH per-button fetch on EVERY cooldown
            -- event fire, ahead of the cap, for 3s after their cast -- the first event
            -- after the data turns real paints the swipe. Cost: a couple of fetches per
            -- cooldown event inside the window; one nil-check outside it.
            if ns._cdRecentBtn1 and (event == "ACTIONBAR_UPDATE_COOLDOWN"
                or event == "SPELL_UPDATE_COOLDOWN") then
                HotPushRecent()
            end
            -- TARGETED SPELL PROBE: SPELL_UPDATE_COOLDOWN names the changed
            -- spell (spellID, baseSpellID; nil spellID means "update
            -- everything" per the API docs). Discarding the payload means
            -- every CDR proc, reset, and charge refill sweeps every unique
            -- spell on the bars (measured 0.48ms per event, 82 events in
            -- 18.7s of combat). Probe exactly the named spell: same tier
            -- maps, same memo semantics as the full pass, one group. The full pass
            -- still owns nil-payload events, a pending cast wave (fall through so the
            -- wave's carrier is never consumed by a probe), dirty maps (sweep rebuilds
            -- first), and ACTIONBAR_UPDATE_COOLDOWN itself. Probes bypass the 0.15s
            -- storm cap on purpose (cheap; cap protects the sweep), so proc-driven
            -- changes paint the same frame. Secret payloads fail open to the sweep: a
            -- secret value cannot be a table key.
            if event == "SPELL_UPDATE_COOLDOWN" and arg1 ~= nil
               and not ns._cdFilledDirty
               and not (issecretvalue and (issecretvalue(arg1) or issecretvalue(arg2))) then
                local fastT, slowT = ns._cdFastSpells, ns._cdSlowSpells
                local key = arg1
                local g = (fastT and fastT[key]) or (slowT and slowT[key])
                if not g and arg2 ~= nil then
                    key = arg2
                    g = (fastT and fastT[key]) or (slowT and slowT[key])
                end
                if g then
                    DispProbe(g, key)
                end
                return
            end
            -- SPELL_UPDATE_COOLDOWN drives the same walk as its action-bar twin:
            -- Blizzard fires NO action-bar event when a cooldown ends or is SHORTENED
            -- (a reduction proc painted the old schedule until the ~1/sec heartbeat --
            -- measured 1.37s of stale swipe), and the spell-level event does fire on
            -- modification. Deliberately an alias rather than a second branch: it
            -- inherits the same-frame dedupe, the 0.15s cap, and the idle-sleep gate,
            -- so a broadcast storm cannot add walks beyond the budget.
            if event == "SPELL_UPDATE_COOLDOWN" then
                event = "ACTIONBAR_UPDATE_COOLDOWN"
            end
            -- Idle sleep for the ~1/sec ACTIONBAR_UPDATE_COOLDOWN heartbeat
            -- (bisect-verified: walking 140 settled buttons per heartbeat was ALL of
            -- ActionBars' idle CPU). The cooldown walk runs ONLY while something is
            -- live or within 2s of real activity -- no periodic resync. Every way
            -- button state changes while settled has an owning event edge (casts,
            -- dirty-trigger events, BAG_UPDATE_DELAYED for item counts); a stale
            -- display here is a missing edge to FIX, never something to sweep for.
            -- Casts are pure dirty-triggers and return before any button work.
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- (Hot-ring priming lives in ns._EABPressPush -- button
                -- keys carry no secrets; see HotPushRecent.)
                ns._cdDirtyUntil = GetTime() + 2
                -- A cast re-opens BOTH rate gates so events that follow THIS
                -- cast always paint immediately (incl. the slow tier's GCD
                -- sweep) -- caps only ever throttle between-cast chatter.
                ns._cdWalkNext = 0
                ns._cdSlowNext = 0
                -- Deterministic delivery: don't wait for Blizzard's next
                -- cooldown event to run the post-cast pass (a cast's own
                -- events can arrive BEFORE this one, inside the API's
                -- transient window) -- kick one authoritative pass next frame ourselves.
                if not ns._cdCastKickPending then
                    ns._cdCastKickPending = true
                    C_Timer.After(0, ns._cdCastKick)
                end
                -- The cast's frame timestamp: pushes running in THIS frame
                -- are provisional (may hand over a pre-settled duration
                -- object); the kick reads this to know its pass must run
                -- even when a pass already ran this frame (GetTime is
                -- frame-constant, so equality identifies the cast's own event cascade exactly).
                ns._gcdCastAt = GetTime()
                return
            end
            -- A CANCELLED cast is the other cooldown herald: the GCD is refunded, a
            -- shortened cooldown fires no action-bar event, and the spell-level event
            -- lands in the cancel's own frame inside the cooldown API's
            -- transient-disagreement window -- so the pushed swipe would play out
            -- full-length on the cancelled spell. Same treatment as a cast minus the
            -- cast bookkeeping (no castAt: nothing was cast): reopen the gates and let
            -- the shared next-frame kick read the settled state. On a COMPLETED hard
            -- cast STOP fires alongside SUCCEEDED; the pending guard collapses the two
            -- arms into the one kick owed.
            if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
               or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
                ns._cdDirtyUntil = GetTime() + 2
                ns._cdWalkNext = 0
                ns._cdSlowNext = 0
                if not ns._cdCastKickPending then
                    ns._cdCastKickPending = true
                    C_Timer.After(0, ns._cdCastKick)
                end
                return
            end
            -- ICON rate cap. SPELL_UPDATE_ICON is a broadcast whose walk is the
            -- dispatcher's heaviest (full mixin UpdateAction on ~140 buttons, plus
            -- the glow rescan rides the same event); the cap is insurance for setups
            -- where the event storms (form/override morphs, spell-morph procs). 0.5s
            -- cap + trailing flush so the final icon state always paints.
            -- Deliberately NO cast-gate reset (unlike COOLDOWN/STATE): morph storms
            -- are cast-adjacent, so a cast-reset would defeat the cap, and the assist
            -- slot's icon (must track the rotation beat-for-beat) is painted by
            -- RepaintAssistIcons, never here.
            if event == "SPELL_UPDATE_ICON" then
                local now = GetTime()
                local nextAt = ns._icoWalkNext or 0
                if now < nextAt then
                    if not ns._icoFlushArmed then
                        ns._icoFlushArmed = true
                        if not ns._icoFlushFn then
                            -- Built under this AB-born entry (timer callbacks
                            -- bill their closure's creation context).
                            ns._icoFlushFn = function()
                                ns._icoFlushArmed = nil
                                ns._icoWalkNext = 0
                                local d = ns._cdDispatcher
                                local h = d and d:GetScript("OnEvent")
                                if h then h(d, "SPELL_UPDATE_ICON") end
                            end
                        end
                        C_Timer.After((nextAt - now) + 0.02, ns._icoFlushFn)
                    end
                    return
                end
                ns._icoWalkNext = now + 0.5
                -- Targeted LEADING EDGE (payload: arg1 = BASE spell id of the
                -- changed icon, nil = "all icons"). The first fire after
                -- quiet heals just the named spell's hosting buttons (tier
                -- maps key by RESOLVED id: base key covers untransformed
                -- slots, override key currently-morphed ones) plus the
                -- residual list (a macro can resolve to the morphing spell)
                -- -- a proc morph paints the SAME frame it fires. Further
                -- fires coalesce into the trailing-flush full walk above. LESSON:
                -- capless targeted healing per fire and per-id-per-frame dedupe both
                -- spiked WORSE than the capped walk -- some icons GENUINELY re-morph
                -- continuously (macro resolves track target/modifier, assist slots
                -- track the rotation), and only the 0.5s cap holds them to a sane
                -- cadence. Fail-open everywhere: nil/secret payload, dirty maps, or a
                -- lookup miss fall through to this pass's own full walk below. Dormant
                -- bars are absent from the maps BY CONTRACT (their show-edge reconcile
                -- repaints from live state), and the icon memo is write-behind, so a
                -- stale memo can never wrongly skip.
                if not ns._cdFilledDirty
                   and type(arg1) == "number"
                   and not (issecretvalue and issecretvalue(arg1)) then
                    local fastT, slowT = ns._cdFastSpells, ns._cdSlowSpells
                    local g1 = fastT and fastT[arg1]
                    local g2 = slowT and slowT[arg1]
                    local ovr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
                        and C_SpellBook.FindSpellOverrideByID(arg1) or nil
                    if not (type(ovr) == "number"
                            and not (issecretvalue and issecretvalue(ovr))
                            and ovr > 0 and ovr ~= arg1) then
                        ovr = nil
                    end
                    local g3 = ovr and fastT and fastT[ovr] or nil
                    local g4 = ovr and slowT and slowT[ovr] or nil
                    if g1 or g2 or g3 or g4 then
                        local heal = ns._cdIconHeal
                        if g1 then for i = 1, #g1 do heal(g1[i]) end end
                        if g2 then for i = 1, #g2 do heal(g2[i]) end end
                        if g3 then for i = 1, #g3 do heal(g3[i]) end end
                        if g4 then for i = 1, #g4 do heal(g4[i]) end end
                        local res = ns._cdResidual
                        if res then for i = 1, #res do heal(res[i]) end end
                        return
                    end
                end
            end
            -- Same-frame dedupe for pure-repaint events: one cast fires
            -- COOLDOWN/USABLE/STATE several times in the same frame (cast + GCD +
            -- charge edges), and repeats within a frame repaint identical state. First
            -- fire of each type per frame walks; dupes return (GetTime() is
            -- frame-constant, so two compares). SLOT_CHANGED is exempt (slot-targeted,
            -- content-critical), as is the infrequent-events else-branch. CHARGES is
            -- included: its walk allocates a charge-info table + duration object per
            -- charge button per fire, and regen ticks storm several to a frame with
            -- identical state (the module's #3 allocator). Same one-frame staleness
            -- contract (an intra-frame double mutation paints on the next regen tick);
            -- per-BUTTON count-text registrations are separate frames and unaffected,
            -- and any deferred filled-list rebuild rides to the next consuming event.
            if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_USABLE"
               or event == "SPELL_UPDATE_CHARGES" then
                local stamps = ns._evStamps
                if not stamps then stamps = {}; ns._evStamps = stamps end
                local now = GetTime()
                if stamps[event] == now then return end
                stamps[event] = now
            end
            local _cdSkip = false
            if event == "ACTIONBAR_UPDATE_COOLDOWN" then
                local now = GetTime()
                if not ns._cdAnyLive and now >= (ns._cdDirtyUntil or 0) then
                    -- Fully settled: skip every heartbeat outright.
                    _cdSkip = true
                else
                    -- Storm cap while live/dirty (timed: ~1.0ms per walk at
                    -- 3.5/sec while chain-casting). Leading edge passes
                    -- immediately; repeats inside the cap defer to ONE
                    -- trailing flush so the final state always paints; casts
                    -- reset the gate above. 0.15s, deliberately no longer:
                    -- only a cast of OURS reopens the gate, so every other cooldown
                    -- change (proc shortening, reset, charge refund, cancelled-cast GCD
                    -- refund) eats the full window before drawing -- reads to users as
                    -- bars lagging the game. At the measured 3.5 fires/sec this never
                    -- caps a normal rotation (~1.5ms/sec of walks, ~0.15% of one core);
                    -- it only catches pathological storms.
                    local nextAt = ns._cdWalkNext or 0
                    if now < nextAt then
                        if not ns._cdFlushArmed then
                            ns._cdFlushArmed = true
                            if not ns._cdFlushFn then
                                -- Built HERE, under this AB-born entry, so the
                                -- timer callback bills ActionBars (closures
                                -- carry their creation context).
                                ns._cdFlushFn = function()
                                    ns._cdFlushArmed = nil
                                    ns._cdWalkNext = 0
                                    local d = ns._cdDispatcher
                                    local h = d and d:GetScript("OnEvent")
                                    if h then h(d, "ACTIONBAR_UPDATE_COOLDOWN") end
                                end
                            end
                            C_Timer.After((nextAt - now) + 0.02, ns._cdFlushFn)
                        end
                        -- (Recently-cast repaints are owned by the HOT LANE
                        -- at the top of the handler -- it runs ahead of
                        -- this cap on every cooldown event fire.)
                        _cdSkip = true
                    else
                        ns._cdWalkNext = now + 0.15
                    end
                end
            elseif event ~= "PLAYER_TARGET_CHANGED" then
                -- Any other dispatcher event implies real activity (slot, charge,
                -- usable, form, vehicle...); target flips cannot start cooldowns and
                -- tab-targeting spams them. EXCEPT the assisted-combat slot's
                -- SLOT_CHANGED spam: the manager re-stamps that slot ~10x/sec at total
                -- idle, which would keep the dirty window permanently open. A real cast
                -- around the OBA button still dirties via UNIT_SPELLCAST_SUCCEEDED and
                -- its usable/state events (same fires that drive the assist icon
                -- repaint; see ns.RepaintAssistIcons).
                if not (event == "ACTIONBAR_SLOT_CHANGED" and arg1 and arg1 ~= 0
                        and select(3, GetActionInfo(arg1)) == "assistedcombat") then
                    ns._cdDirtyUntil = GetTime() + 2
                    -- Content-bearing edges ONLY retire the filled-slot lists
                    -- and the slot->button map: pure-repaint events
                    -- (charges/usable/bag/cvar/icon) cannot change slot
                    -- filledness, tier membership, or mapping -- yet dirtying
                    -- on them rebuilt the lists ~2x/sec in combat (measured 55
                    -- rebuilds in 27s). Paging edges that DO change content
                    -- but fire no event here are owned explicitly:
                    -- ACTIONBAR_PAGE_CHANGED / UPDATE_BONUS_ACTIONBAR are registered,
                    -- and custom modifier paging dirties via the bar frame's state-page
                    -- attribute hook (CreateBarFrame). The assist slot's re-stamp spam
                    -- is excluded above: its filledness never changes, and dirtying
                    -- ~10/sec would make the rebuild cost what the lists save.
                    local _contentEdge = not (event == "SPELL_UPDATE_CHARGES"
                        or event == "ACTIONBAR_UPDATE_USABLE"
                        or event == "BAG_UPDATE_DELAYED"
                        or event == "CVAR_UPDATE"
                        or event == "SPELL_UPDATE_ICON")
                    if _contentEdge then
                        ns._cdFilledDirty = true
                    end
                    -- The curated-set memo only retires on edges that can
                    -- actually re-curate (viewer data events, PEW; plus
                    -- SPELLS_CHANGED in the controller sweep and ApplyAll).
                    -- Every OTHER content edge reuses the memo -- measured:
                    -- the viewer walk ran ~90x/fight for data that changed at
                    -- most twice.
                    if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
                        -- Payload names the delta (baseSpellID,
                        -- overrideSpellID|nil), so a transform patches the
                        -- curated memo in place instead of retiring it (the full
                        -- pcall category walk rebuilds an IDENTICAL set, since the
                        -- build already marks every base/override/linked id). The
                        -- override inherits the base's curated class; an override
                        -- REMOVAL needs nothing (extra marked ids are harmless).
                        -- Secret payload fails open to the retire. The filled-list
                        -- dirty above still runs: tier groups key on the RESOLVED
                        -- spell, which this event flips.
                        local cur = ns._cdCuratedMemo
                        if issecretvalue and (issecretvalue(arg1) or issecretvalue(arg2)) then
                            ns._cdCuratedDirty = true
                        elseif cur and arg1 and arg2 and cur[arg1] ~= nil and cur[arg2] == nil then
                            cur[arg2] = cur[arg1]
                        end
                    elseif event == "COOLDOWN_VIEWER_DATA_LOADED"
                        or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED"
                        or event == "PLAYER_ENTERING_WORLD" then
                        ns._cdCuratedDirty = true
                    end
                    -- The slot->buttons map tracks which button HOSTS a slot,
                    -- only changing when paging re-maps action attributes
                    -- (page/bonus/vehicle/override/form/PEW), never on
                    -- SLOT_CHANGED itself (contents, not mapping) -- dirtying
                    -- per slot event would cost what the map saves. Same
                    -- pure-repaint exclusion as the filled lists.
                    if _contentEdge and event ~= "ACTIONBAR_SLOT_CHANGED" then
                        ns._slotBtnMapDirty = true
                    end
                    -- Item stacks repaint on their owning edge (charge
                    -- counts ride SPELL_UPDATE_CHARGES; slot edits clear
                    -- their own text in the SLOT_CHANGED branch).
                    if event == "BAG_UPDATE_DELAYED" and C_ActionBar.GetActionDisplayCount then
                        for _, info2 in ipairs(BAR_CONFIG) do
                            if not info2.isStance and not info2.isPetBar
                                and not ns._eabBarNever[info2.key] then
                                local list2 = barButtons[info2.key]
                                if list2 then
                                    for _, b2 in ipairs(list2) do
                                        local a2 = b2:GetAttribute("action")
                                        if a2 and HasAction(a2) and b2.Count then
                                            -- Guard before coercing: same
                                            -- ordering fix as the charge-tick
                                            -- handler; the `or ""` was ahead of
                                            -- the issecretvalue check.
                                            local d2 = C_ActionBar.GetActionDisplayCount(a2)
                                            local f2 = EFD(b2)
                                            if issecretvalue and issecretvalue(d2) then
                                                -- Secret string (combat): write through
                                                -- and dirty the memo (never store one).
                                                b2.Count:SetText(d2)
                                                f2.lastCountText = nil
                                            else
                                                if d2 == nil then d2 = "" end
                                                if f2.lastCountText ~= d2 then
                                                    f2.lastCountText = d2
                                                    b2.Count:SetText(d2)
                                                end
                                            end
                                            ns._EABZeroCountAlpha(f2, b2.Count, d2, a2)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local _cdLiveSeen = false
            -- Per-slot SLOT_CHANGED throttle. The assisted-combat action spam-fires
            -- SLOT_CHANGED for its own slot (~10/sec at TOTAL IDLE, a known Blizzard
            -- bug whenever One Button Assist sits on a bar). Leading edge passes
            -- immediately (drag-drop/spec-swap bursts hit distinct slots, each passing
            -- instantly); repeats for the SAME slot inside the window defer to ONE
            -- trailing re-dispatch, so the slot's final content always paints. arg1 == 0
            -- ("all slots") shares this throttle under its own key (0 is not a real
            -- slot number): a loadout swap changing talents/gear/bars at once can fire
            -- it repeatedly, and unthrottled that was a full ~140-button walk per
            -- firing with no coalescing (freeze reported via BTWLoadouts, Embrace 9.0.7).
            if event == "ACTIONBAR_SLOT_CHANGED" and arg1 then
                local now = GetTime()
                local nextAt = ns._slotNext
                if not nextAt then nextAt = {}; ns._slotNext = nextAt end
                local at = nextAt[arg1] or 0
                if now < at then
                    local pend = ns._slotPend
                    if not pend then pend = {}; ns._slotPend = pend end
                    if not pend[arg1] then
                        pend[arg1] = true
                        local slot = arg1
                        -- Built here, under this AB-born entry, so the timer
                        -- callback bills ActionBars. One closure per slot per
                        -- window (max ~4/sec), not per event.
                        C_Timer.After((at - now) + 0.02, function()
                            pend[slot] = nil
                            nextAt[slot] = 0
                            local d = ns._cdDispatcher
                            local h = d and d:GetScript("OnEvent")
                            if h then h(d, "ACTIONBAR_SLOT_CHANGED", slot) end
                        end)
                    end
                    return
                end
                nextAt[arg1] = now + 0.25
            end
            -- Assisted shine follows slot contents; coalesced (storm-safe)
            -- and belt-and-braces vs the OnActionChanged callback -- an
            -- in-combat Update() abort dies before Blizzard's TriggerEvent.
            if event == "ACTIONBAR_SLOT_CHANGED" and ns.QueueAssistRescan then
                ns.QueueAssistRescan()
            end
            -- Filled-slot fast lists for the four repaint walks: iterating every button
            -- paid GetAttribute+HasAction on EMPTY slots each walk (about half the
            -- probe floor). Lists rebuild lazily on content edges (SLOT_CHANGED /
            -- vehicle / override / form / PEW via the infrequent branch,
            -- ACTIONBAR_PAGE_CHANGED in the range dispatcher, SPELLS_CHANGED in the
            -- controller sweep). Failure modes are benign by construction: a stale
            -- INCLUDED empty slot no-ops through the per-button HasAction belts, and a
            -- newly FILLED slot always fires ACTIONBAR_SLOT_CHANGED, repainting it
            -- directly AND marking the lists dirty.
            local _filled
            if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_USABLE"
               or event == "SPELL_UPDATE_CHARGES" then
                _filled = ns._cdFilled
                -- Same-frame rebuild cap: a flip storm can dirty the lists
                -- again AFTER this frame's rebuild (page attrs settle across
                -- the burst). One rebuild per frame is enough: a trailing
                -- dirty rides to the next consuming event, and the walks
                -- tolerate one-frame staleness by construction.
                if (ns._cdFilledDirty and ns._cdRebuiltAt ~= GetTime()) or not _filled then
                    DispRebuildLists()
                    _filled = ns._cdFilled
                end
            end
            -- Spell-keyed cooldown pass (see DispCooldownPass above).
            if event == "ACTIONBAR_UPDATE_COOLDOWN" and not _cdSkip then
                if DispCooldownPass() then _cdLiveSeen = true end
            end
            -- Slot-targeted fast path: the lazily rebuilt action->buttons map makes
            -- each SLOT_CHANGED O(hosting buttons) instead of a ~140-button attribute
            -- scan (a form flip fires the event for a dozen distinct slots). Rebuilds
            -- at most once per paging edge. Belt: each hit re-checks the live
            -- attribute, so a stale map entry (slot event racing ahead of its paging
            -- event) can only skip, never wrongly refresh -- the paging event's own
            -- full pass repaints anything a stale map missed.
            local _slotFast, _infreqStampNew
            if event == "ACTIONBAR_SLOT_CHANGED" and arg1 and arg1 ~= 0 then
                local smap = ns._slotBtnMap
                if not smap or ns._slotBtnMapDirty then
                    ns._slotBtnMapDirty = nil
                    smap = {}
                    ns._slotBtnMap = smap
                    for _, info2 in ipairs(BAR_CONFIG) do
                        if not info2.isStance and not info2.isPetBar
                            and not ns._eabBarNever[info2.key] then
                            local list2 = barButtons[info2.key]
                            if list2 then
                                for _, b2 in ipairs(list2) do
                                    local a2 = b2:GetAttribute("action")
                                    if a2 then
                                        local bucket = smap[a2]
                                        if not bucket then bucket = {}; smap[a2] = bucket end
                                        bucket[#bucket + 1] = b2
                                    end
                                end
                            end
                        end
                    end
                end
                _slotFast = smap[arg1] or false
                if not ns._eabNoBtns then ns._eabNoBtns = {} end
                if _slotFast then
                    for _, b2 in ipairs(_slotFast) do
                        local a2 = b2:GetAttribute("action")
                        if a2 == arg1 then
                            ns._eabSlotRefreshBtn(b2, a2)
                        end
                    end
                end
            end
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    -- Never/disabled bars pay NOTHING here, content classes included:
                    -- no runtime reveal edge exists, and the dormancy reveal reconcile
                    -- repaints from live state on the settings-driven reveal.
                    local btns = (not ns._eabBarNever[info.key]) and barButtons[info.key] or nil
                    -- Repaint branches iterate the filled list; content
                    -- branches (SLOT_CHANGED, ICON, infrequent else) keep the full set.
                    local walkBtns = (_filled and _filled[info.key]) or btns
                    -- Repaint walks skip bars not currently visible:
                    -- swipes/desat/checked state on hidden buttons render
                    -- nothing, engine-live swipes complete themselves, and a
                    -- missed edge self-heals on the first walk after the bar
                    -- reappears. Content updates (SLOT_CHANGED) and the
                    -- infrequent-events branch still run for hidden bars so
                    -- icons/bindings are correct the moment they show.
                    local _barHidden = (event == "ACTIONBAR_UPDATE_COOLDOWN"
                        or event == "ACTIONBAR_UPDATE_USABLE"
                        or event == "SPELL_UPDATE_CHARGES")
                        and not (barFrames[info.key] and barFrames[info.key]:IsVisible())
                    if btns and not _barHidden then
                        if event == "ACTIONBAR_SLOT_CHANGED" then
                            -- Targeted events were resolved through the map
                            -- fast path above; only arg1 == 0 ("all slots")
                            -- still walks every button here.
                            for _, btn in ipairs((_slotFast == nil) and btns or ns._eabNoBtns) do
                                local action = btn:GetAttribute("action")
                                if action and (arg1 == 0 or arg1 == action) then
                                    ns._eabSlotRefreshBtn(btn, action)
                                end
                            end
                        elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
                            -- Handled entirely by the spell-keyed passes BEFORE this
                            -- loop. This branch exists so the event can never fall
                            -- through to the infrequent full-refresh else below.
                        elseif event == "CVAR_UPDATE" then
                            -- "Show numbers for cooldowns" toggled: re-apply
                            -- recharge-number visibility to every charge cooldown
                            -- immediately (main cooldown numbers update natively). Only
                            -- buttons that already own a charge cooldown pay the fetch,
                            -- so unrelated CVAR_UPDATEs stay near-free.
                            for _, btn in ipairs(btns) do
                                local chargeCd = btn.chargeCooldown
                                if chargeCd then
                                    local action = btn:GetAttribute("action")
                                    local ok = action and HasAction(action)
                                    ns.UpdateChargeNumbersVisibility(btn, chargeCd,
                                        ok and C_ActionBar.GetActionCooldown(action) or nil,
                                        ok and C_ActionBar.GetActionCharges(action) or nil)
                                end
                            end
                        elseif event == "ACTIONBAR_UPDATE_USABLE" then
                            DispWalkUsable(walkBtns)
                        elseif event == "SPELL_UPDATE_CHARGES" then
                            DispWalkCharges(walkBtns)
                        elseif event == "SPELL_UPDATE_ICON" then
                            DispWalkIcon(btns)
                        else
                            -- Infrequent events: full update + usable refresh
                            -- (UpdateButtonArt is nooped, so desat may not
                            -- update; explicit usable refresh covers
                            -- form/stance/talent changes). Same-frame dedupe:
                            -- ONE stance/form flip fires several infrequent events
                            -- (form, forms, bonus, page), each running this identical
                            -- ~140-button UpdateAction + cooldown-visual pass -- the
                            -- dominant cost of form dancing. Dupes skip, but arm ONE
                            -- next-frame flush so state mutating BETWEEN a frame's
                            -- events always gets a final pass: correctness never rides
                            -- on skipped dupes. Target changes keep their own cheap
                            -- path and neither stamp nor skip.
                            local nowI = GetTime()
                            if not ns._eabNoBtns then ns._eabNoBtns = {} end
                            local _infreqDup = event ~= "PLAYER_TARGET_CHANGED"
                                and ns._infreqPassAt == nowI and not _infreqStampNew
                            if _infreqDup then
                                ns._infreqFlushEvent = event
                                if not ns._infreqFlushArmed then
                                    ns._infreqFlushArmed = true
                                    if not ns._infreqFlushFn then
                                        -- Built here, under this AB-born entry
                                        -- (timer callbacks bill their closure's
                                        -- creation context).
                                        ns._infreqFlushFn = function()
                                            ns._infreqFlushArmed = nil
                                            ns._infreqPassAt = nil
                                            local d = ns._cdDispatcher
                                            local h = d and d:GetScript("OnEvent")
                                            if h then h(d, ns._infreqFlushEvent) end
                                        end
                                    end
                                    C_Timer.After(0, ns._infreqFlushFn)
                                end
                            elseif event ~= "PLAYER_TARGET_CHANGED" then
                                ns._infreqPassAt = nowI
                                _infreqStampNew = true
                            end
                            local canSetAttr = not InCombatLockdown()
                            for _, btn in ipairs(_infreqDup and ns._eabNoBtns or btns) do
                                -- Covers SPELL_UPDATE_CHARGES (a regained charge must
                                -- re-evaluate desat) plus form/stance/world entries;
                                -- early-outs when both features are off. Target changes
                                -- share this branch but change NO button content (the
                                -- mixin handles its own native target reactions), so
                                -- tab-target spam skips the full UpdateAction AND
                                -- cooldown refresh (measured 0.7ms per tab). Only the
                                -- usable tri-state below can legitimately flip on a
                                -- target swap, and it is memo-gated.
                                local ufd = EFD(btn)
                                if event ~= "PLAYER_TARGET_CHANGED" then
                                    -- Taint-safe refresh; avoids passing secret cooldown values through a tainted call.
                                    local infreqAction = btn:GetAttribute("action")
                                    EAB_VTABLE.ForceButtonRefresh(btn, infreqAction)
                                    RefreshCooldownVisuals(btn)
                                    -- Two channels ForceButtonRefresh doesn't own (same
                                    -- pairing as the bar-reveal path): checked state +
                                    -- equipped border, both stale after page/form flips.
                                    if infreqAction then
                                        btn:SetChecked((IsCurrentAction(infreqAction) or IsAutoRepeatAction(infreqAction)) and true or false)
                                        if btn.Border then
                                            btn.Border:SetShown(IsEquippedAction(infreqAction) and true or false)
                                        end
                                    end
                                    -- Classic WoW UI: a third such channel, the slot ring
                                    -- vs empty-slot art (one field read on every other look).
                                    if ufd.classicArt then
                                        ns.AB_ClassicSlotRing(btn, infreqAction and HasAction(infreqAction))
                                    end
                                end
                                if ufd.rangeTinted then
                                    ufd.usableState = nil
                                else
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    local isUsable, notEnoughMana = IsUsableAction(action)
                                    -- Same tri-state memo as the USABLE branch.
                                    local ustate = (isUsable and 1) or (notEnoughMana and 2) or 3
                                    if ufd.usableState ~= ustate then
                                        ufd.usableState = ustate
                                        local icon = btn.icon
                                        if icon then
                                            if ustate == 1 then
                                                icon:SetVertexColor(1.0, 1.0, 1.0)
                                            elseif ustate == 2 then
                                                icon:SetVertexColor(0.5, 0.5, 1.0)
                                            else
                                                icon:SetVertexColor(0.4, 0.4, 0.4)
                                            end
                                        end
                                    end
                                end
                                end
                            end
                        end
                    end
                end
            end
            -- Settled-detection: after a full (unskipped) heartbeat walk with
            -- nothing live, the walks stop until re-armed by activity.
            if event == "ACTIONBAR_UPDATE_COOLDOWN" and not _cdSkip then
                ns._cdAnyLive = _cdLiveSeen
            end
            -- Re-evaluate keybind routing when any slot changes (spec swap,
            -- spell drag, etc.) so empower slots use click bindings and
            -- non-empower slots use native commands. Debounced because
            -- page swaps fire 12+ ACTIONBAR_SLOT_CHANGED events.
            if event == "ACTIONBAR_SLOT_CHANGED" and not _empowerReroutePending then
                _empowerReroutePending = true
                C_Timer_After(0, function()
                    _empowerReroutePending = false
                    if InCombatLockdown() then
                        -- SLOT_CHANGED fires freely in combat, but the rebuild needs
                        -- SetOverrideBinding and a secure SetAttribute. Never drop it:
                        -- SLOT_CHANGED won't refire, so defer under the shared
                        -- "UpdateKeybinds" key (the reroute is UpdateKeybinds itself).
                        ns.CombatQueue.Defer("UpdateKeybinds", _EmpowerReroute)
                        return
                    end
                    _EmpowerReroute()
                end)
            end

            -- ExtraActionButton1 is a Blizzard button outside our barButtons.
            -- Its cooldown ticks come from the broadcaster's tick set, which is
            -- off under secrecy, so the cooldown is painted from here directly.
            -- Blizzard's own SLOT_CHANGED registration reaches it untainted as
            -- well (the broadcaster quieting keeps that one); the slot refresh
            -- here is our painter's pass on top of it.
            if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_SLOT_CHANGED" then
                local eab1 = ExtraActionButton1
                if eab1 and eab1:IsShown() then
                    if event == "ACTIONBAR_SLOT_CHANGED" then
                        local action = eab1:GetAttribute("action")
                        if action and (arg1 == 0 or arg1 == action) then
                            -- Content changes keep the slot number (see the
                            -- main SLOT_CHANGED branch).
                            EAB_VTABLE.ForceButtonRefresh(eab1, action)
                        end
                    else
                        ForceCooldownPaint(eab1)
                    end
                end
            end

            -- Blizzard refresh paths (mixin UpdateAction from the infrequent
            -- else-branch / SPELL_UPDATE_ICON, plus C-side slot repaints) reset
            -- HotKey text color; re-assert it with one deferred color-only pass
            -- per burst. The cooldown branch never touches text color.
            if event ~= "ACTIONBAR_UPDATE_COOLDOWN" then
                EAB:QueueHotkeyColorReassert()
            end
        end)
    end
end

