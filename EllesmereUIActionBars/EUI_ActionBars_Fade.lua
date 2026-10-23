if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Fade.lua
--
--  Mouseover fade: hover states, fade in and out, and the hover hooks on
--  bars and data bars.
--  Loads after EUI_ActionBars_Layout.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local C_Timer_After = C_Timer.After

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local _gridState, _quickKeybindState, ALL_BARS, FadeTo = I._gridState, I._quickKeybindState, I.ALL_BARS, I.FadeTo
local StopFade = I.StopFade
local barFrames, blizzMovableHolders, dataBarFrames = I.barFrames, I.blizzMovableHolders, I.dataBarFrames
local extraBarHolders, GetEABFlyout = I.extraBarHolders, I.GetEABFlyout
local SyncPagingAlpha = I.SyncPagingAlpha
local BAR_LOOKUP, _dragState, _fadeAlpha = I.BAR_LOOKUP, I._dragState, I._fadeAlpha
local abs = math.abs

-------------------------------------------------------------------------------
--  Mouseover Fade System
-------------------------------------------------------------------------------
local hoverStates = {}  -- shared by action bars, data bars, and extra bars

-- Every mouseover-enabled bar follows the same state machine: entering marks
-- it hovered and fades in, leaving schedules a guarded fade-out on the next
-- frame. Per-bar attach functions only provide edge-case policies that differ
-- between action bars, data bars, and Blizzard-owned extra bars.
function EAB_VTABLE.Hover.GetSettings(barKey)
    return EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[barKey]
end

function EAB_VTABLE.Hover.GetState(barKey, frame)
    local state = hoverStates[barKey]
    if not state then
        state = { frame = frame, isHovered = false, fadeDir = nil }
        hoverStates[barKey] = state
    else
        state.frame = frame or state.frame
    end
    return state
end

-------------------------------------------------------------------------------
--  Advanced Fade (optional per-bar alpha layer)
--
--  IMPORTANT CONTRACT:
--    advancedFadeEnabled ~= true  -> this layer is inert for that bar.
--  Native Visibility / Bar Opacity / mouseover remain authoritative and untouched.
--  The layer is applied only after stock alpha writers have completed.
-------------------------------------------------------------------------------
function EAB_VTABLE.Hover.AdvancedFadeEnabled(s)
    return s and s.advancedFadeEnabled == true
end

function EAB_VTABLE.Hover.HasCustomFade(s)
    if not EAB_VTABLE.Hover.AdvancedFadeEnabled(s) then return false end
    local c = s.fadeConditions
    return type(c) == "table" and (c.combat or c.party or c.raid or c.instance
        or c.mounted or c.flying or c.target or c.enemy_target or c.mouseover) and true or false
end

-- Treat restricted state as unavailable; never branch on a secret value.
function EAB_VTABLE.Hover.AdvancedFadePublicTrue(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value == true
end

function EAB_VTABLE.Hover.AdvancedFadeHovered(state)
    return state and (state.isHovered == true or state.fadeDir == "in") or false
end

function EAB_VTABLE.Hover.CustomFadeConditionMet(barKey, s)
    if not EAB_VTABLE.Hover.AdvancedFadeEnabled(s) then return false end
    local c = s.fadeConditions
    if type(c) ~= "table" then return false end
    local state = hoverStates[barKey]
    local PublicTrue = EAB_VTABLE.Hover.AdvancedFadePublicTrue

    -- OR semantics. Restricted values do not reveal a condition.
    if c.mouseover and EAB_VTABLE.Hover.AdvancedFadeHovered(state) then return true end
    if c.combat then
        if EllesmereUI.IsInCombat and PublicTrue(EllesmereUI.IsInCombat()) then return true end
        if PublicTrue(InCombatLockdown()) then return true end
        if UnitAffectingCombat and PublicTrue(UnitAffectingCombat("player")) then return true end
    end
    local inRaid = IsInRaid and PublicTrue(IsInRaid())
    if c.raid and inRaid then return true end
    if c.party and IsInGroup and PublicTrue(IsInGroup()) and not inRaid then return true end
    if c.instance and IsInInstance and PublicTrue(IsInInstance()) then return true end
    if c.mounted and IsMounted and PublicTrue(IsMounted()) then return true end
    if c.flying and EllesmereUI.IsAirborneSkyriding
        and PublicTrue(EllesmereUI.IsAirborneSkyriding()) then return true end
    local targetExists = UnitExists and PublicTrue(UnitExists("target"))
    if c.target and targetExists then return true end
    if c.enemy_target and targetExists and UnitCanAttack
        and PublicTrue(UnitCanAttack("player", "target")) then return true end
    return false
end

function EAB_VTABLE.Hover.CustomFadeFrame(barKey)
    local info = BAR_LOOKUP[barKey]
    if not info or info.noManagedVisibility then return nil, info end
    local frame = barFrames[barKey]
        or (info.isDataBar and dataBarFrames[barKey])
        or (info.isBlizzardMovable and blizzMovableHolders[barKey])
        or extraBarHolders[barKey]
        or (info.visibilityOnly and info.frameName and _G[info.frameName])
    if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable
        and info.frameName and _G[info.frameName] then
        frame = _G[info.frameName]
    end
    return frame, info
end

function EAB_VTABLE.Hover.RefreshCustomFadeBar(barKey, animate, force)
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if not EAB_VTABLE.Hover.AdvancedFadeEnabled(s) then return false end

    local enabled = EAB_VTABLE.Hover.HasCustomFade(s)
    if not enabled and not force then return false end

    -- Temporary surfacing modes remain authoritative over alpha rules.
    local spellbookForced = (_gridState._sbNeverForced and _gridState._sbNeverForced[barKey])
        or (_gridState._sbMoForced and _gridState._sbMoForced[barKey])
    local myslotForced = EAB.db and EAB.db.profile and EAB.db.profile._myslotVisBackup
    if _gridState.shown or _dragState.visible or _quickKeybindState.open
        or spellbookForced or myslotForced then
        local st = hoverStates[barKey]
        if st then st.customFadeTarget = nil end
        return false
    end

    local frame = EAB_VTABLE.Hover.CustomFadeFrame(barKey)
    if not frame then return false end
    local state = hoverStates[barKey]

    -- Visibility has absolute priority. When it currently uses Mouseover as the live
    -- gate, stock EUI owns the hidden/off-hover side entirely. We only adjust alpha
    -- while the bar is already legitimately revealed by hover.
    local visibilityWantsHover
    if EllesmereUI.VisWantsMouseover then
        visibilityWantsHover = EllesmereUI.VisWantsMouseover(
            s, "barVisibility", nil, EllesmereUI.VIS_CAPS_DEFAULT)
    else
        visibilityWantsHover = s.mouseoverEnabled
    end
    local hoverHidden = false
    if visibilityWantsHover then
        local over = EAB_VTABLE.Hover.AdvancedFadeHovered(state)
        if not over and EAB.db.profile.mouseoverShowAll and ns.AnyMouseoverBarHovered then
            over = ns.AnyMouseoverBarHovered()
        end
        hoverHidden = not over
    end

    -- Visibility's Mouseover mode parks the user's real Bar Opacity in
    -- _savedBarAlpha. Use that as the native/base visible alpha; otherwise use the
    -- normal opacity value. This reads native state rather than replacing its storage.
    local base
    if s.mouseoverEnabled and s._savedBarAlpha ~= nil then
        base = s._savedBarAlpha
    else
        base = s.mouseoverAlpha or 1
    end

    local target = base
    if enabled and EAB_VTABLE.Hover.CustomFadeConditionMet(barKey, s) then
        target = s.fadeMaxAlpha
        if target == nil then target = 1 end
    end
    if hoverHidden then target = 0 end
    if target < 0 then target = 0 elseif target > 1 then target = 1 end

    if state and not force and state.customFadeTarget == target then return true end
    if state then state.customFadeTarget = target end

    local current = _fadeAlpha[frame] or 1
    if current == target then return true end
    StopFade(frame, current)
    if animate and enabled and abs(current - target) >= 0.01 then
        local duration = hoverHidden and (s.mouseoverSpeed or 0.15)
            or ((target > current) and (s.fadeInSpeed or 0.15) or (s.fadeOutSpeed or 0.15))
        if duration < 0.01 then duration = 0.01 end
        FadeTo(frame, target, duration)
    else
        StopFade(frame, target)
    end
    if barKey == "MainBar" then SyncPagingAlpha(target) end
    return true
end

function EAB:RefreshCustomFadeGate()
    local any = false
    if self.db and self.db.profile and self.db.profile.bars then
        for _, info in ipairs(ALL_BARS) do
            if EAB_VTABLE.Hover.HasCustomFade(self.db.profile.bars[info.key]) then
                any = true
                break
            end
        end
    end
    self._anyCustomFade = any
    if any then
        self:EnsureAdvancedFadeHooks()
        if not self._advancedFadeUpdaterRegistered and EllesmereUI.RegisterVisibilityUpdater then
            EllesmereUI.RegisterVisibilityUpdater(self._advancedFadeUpdater)
            self._advancedFadeUpdaterRegistered = true
        end
    elseif self._advancedFadeUpdaterRegistered and EllesmereUI.UnregisterVisibilityUpdater then
        EllesmereUI.UnregisterVisibilityUpdater(self._advancedFadeUpdater)
        self._advancedFadeUpdaterRegistered = nil
    end
    return any
end

function EAB:RefreshCustomFadeForBar(barKey, animate)
    self:RefreshCustomFadeGate()
    return EAB_VTABLE.Hover.RefreshCustomFadeBar(barKey, animate, true)
end

function EAB:RefreshAllCustomFade(animate, force)
    local any = self:RefreshCustomFadeGate()
    if not any and not force then return end
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        -- force means restore/re-evaluate every ENABLED Advanced Fade bar (including
        -- one with an empty condition set), never a disabled/native bar.
        if s and s.advancedFadeEnabled == true and (force or EAB_VTABLE.Hover.HasCustomFade(s)) then
            EAB_VTABLE.Hover.RefreshCustomFadeBar(info.key, animate, force and true or false)
        end
    end
end

-- One-time handoff when the master toggle is switched OFF.  This does not touch
-- any persisted Visibility/Opacity setting.  It only stops an Advanced Fade that may
-- already be in flight and paints the exact native hover presentation for this instant.
function EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(barKey)
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if not s then return end
    local frame, info = EAB_VTABLE.Hover.CustomFadeFrame(barKey)
    if not frame then return end

    local state = hoverStates[barKey]
    local over = EAB_VTABLE.Hover.AdvancedFadeHovered(state)
    if not over and EAB.db.profile.mouseoverShowAll and ns.AnyMouseoverBarHovered then
        over = EAB_VTABLE.Hover.AdvancedFadePublicTrue(ns.AnyMouseoverBarHovered())
    end
    local target, wantsHover = EAB_VTABLE.Hover.RestingAlpha(barKey, s)
    if wantsHover and over then target = s._savedBarAlpha or 1 end

    StopFade(frame, target)
    if state then
        state.customFadeTarget = nil
        if s.mouseoverEnabled and over then
            state.fadeDir = "in"
        elseif s.mouseoverEnabled and target == 0 then
            state.fadeDir = "out"
        else
            state.fadeDir = nil
        end
    end
    if barKey == "MainBar" then SyncPagingAlpha(target) end
end

-- Enable/disable changes do not rebuild Visibility, drivers, or native settings.
-- ON merely arms our optional hooks; OFF performs the one-time alpha handoff above.
function EAB:RefreshAdvancedFadeEnabled(changed)
    if type(changed) == "string" then
        local s = self.db.profile.bars[changed]
        if s and s.advancedFadeEnabled ~= true then
            EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(changed)
        end
    elseif type(changed) == "table" then
        for _, barKey in ipairs(changed) do
            local s = self.db.profile.bars[barKey]
            if s and s.advancedFadeEnabled ~= true then
                EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(barKey)
            end
        end
    end

    self:RefreshCustomFadeGate()

    -- If anything remains enabled, run the stock mouseover refresh first.  Our lazy
    -- post-hook then layers Advanced Fade only onto enabled bars.  When all toggles are
    -- OFF, no custom refresh is needed after the one-time handoff.
    if self._anyCustomFade then
        self:RefreshMouseover()
    end
end

-- The alpha a bar RESTS at while the cursor is not on it, plus whether that resting state
-- is a hover gate. Single source of truth for every alpha writer here, so a fade-out
-- cannot land on a different verdict than the visibility refresh would. mouseoverEnabled
-- is STATIC (true whenever mouseover is selected at all, any Match Mode), so it can only
-- answer "is the hover mechanism wired"; VisWantsMouseover answers "is it gating now".
-- _savedBarAlpha is load-bearing: ApplyMode parks mouseoverAlpha at 0 and stashes the real
-- value there while a mouseover selection is stored, so the shown branch would paint 0.
-- On the vtable, not a chunk local.
function EAB_VTABLE.Hover.RestingAlpha(barKey, s)
    s = s or EAB_VTABLE.Hover.GetSettings(barKey)
    if not s then return 1, false end
    local wantsHover
    if s.mouseoverEnabled and EllesmereUI.VisWantsMouseover then
        wantsHover = EllesmereUI.VisWantsMouseover(s, "barVisibility", nil, EllesmereUI.VIS_CAPS_DEFAULT)
    else
        wantsHover = s.mouseoverEnabled
    end
    if wantsHover then return 0, true end
    return s._savedBarAlpha or s.mouseoverAlpha or 1, false
end

-- Fade ONE bar in, no broadcast. The fadeDir memo makes repeat calls while
-- already fading/faded O(1) table reads, so a sweep across a bar's 12 buttons
-- costs 12 memo hits and one real fade. On the vtable,
-- not a chunk local.
function EAB_VTABLE.Hover.FadeInOne(barKey, state)
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if s and s.mouseoverEnabled and state and state.fadeDir ~= "in" then
        local targetAlpha = s._savedBarAlpha or 1
        state.fadeDir = "in"
        StopFade(state.frame)
        -- The shared per-frame fader starts a show-all edge on every bar in
        -- the same frame (lockstep, no ripple).
        FadeTo(state.frame, targetAlpha, s.mouseoverSpeed or 0.15)
        if barKey == "MainBar" then SyncPagingAlpha(targetAlpha) end
    end
end

function EAB_VTABLE.Hover.FadeIn(barKey, state)
    EAB_VTABLE.Hover.FadeInOne(barKey, state)
    -- "Show All Bars on Mouseover": bring other bars along, all starting THIS
    -- frame in lockstep. Cheap because every fade rides the shared fader (a
    -- table write per bar). Iterative, not recursive: no reentrancy latch to get stuck.
    -- Gated on THIS bar being Mouseover itself -- AttachHoverHooks wires the
    -- same OnEnter onto every bar regardless of its own visibility mode, so
    -- without this check hovering an Always-visible bar broadcast the same
    -- as hovering a real Mouseover one (tooltip promises the latter only).
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if s and s.mouseoverEnabled and EAB.db.profile.mouseoverShowAll then
        local FadeInOne = EAB_VTABLE.Hover.FadeInOne
        for otherKey, otherState in pairs(hoverStates) do
            if otherKey ~= barKey then
                FadeInOne(otherKey, otherState)
            end
        end
    end
end

function EAB_VTABLE.Hover.FadeOut(barKey, state)
    if _gridState.shown then return end  -- keep bars visible during spell drag
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if s and s.mouseoverEnabled and state and state.fadeDir ~= "out" then
        -- Fade back to the bar's RESTING alpha, not a hardcoded 0: under Any a passing
        -- disjunct keeps the bar visible with no hover involved, and fading it away here
        -- would leave it wrong until the next visibility refresh.
        local resting = EAB_VTABLE.Hover.RestingAlpha(barKey, s)
        state.fadeDir = "out"
        StopFade(state.frame)
        FadeTo(state.frame, resting, s.mouseoverSpeed or 0.15)
        if barKey == "MainBar" then SyncPagingAlpha(resting) end
    end
end

-- Check if any mouseover-enabled bar is currently hovered.
function ns.AnyMouseoverBarHovered()
    for otherKey, otherState in pairs(hoverStates) do
        if otherState.isHovered then
            local os = EAB_VTABLE.Hover.GetSettings(otherKey)
            if os and os.mouseoverEnabled then return true end
        end
    end
    return false
end

function EAB_VTABLE.Hover.ScheduleFadeOut(barKey, state, opts)
    opts = opts or {}

    -- The bar frame and every button hook OnLeave, so one mouse sweep across a
    -- 12-button bar lands here 12+ times. Coalesced: one pending timer per bar covers
    -- the whole sweep (same pattern as _range.slotPending in
    -- EUI_ActionBars_Range.lua) instead of a timer+closure
    -- per OnLeave each running the O(bars) hovered scan. Callback built once per state
    -- and reused; opts is stable per bar (one BuildHandlers call).
    if state.foPending then return end
    state.foPending = true
    local cb = state.foCb
    if not cb then
        cb = function()
            state.foPending = false
            if opts.isStillHovered and opts.isStillHovered(state) then
                if opts.markHoveredWhileActive then
                    state.isHovered = true
                end
                return
            end
            if state.isHovered then return end
            -- Ground truth: Enter/Leave interleaves between a bar frame and
            -- its children can leave isHovered false while the cursor never
            -- left the bar (fade flicker per twitch). One C call settles it.
            if state.frame and state.frame:IsMouseOver() then
                state.isHovered = true
                return
            end
            if _quickKeybindState.open then return end
            if opts.blockFadeOut and opts.blockFadeOut(state) then return end
            -- When showing all bars together, keep visible while any bar is hovered
            if EAB.db.profile.mouseoverShowAll and ns.AnyMouseoverBarHovered() then return end
            EAB_VTABLE.Hover.FadeOut(barKey, state)
            -- Broadcast fade-out to all other mouseover bars, lockstep
            -- (cheap via the shared fader, same as the fade-in broadcast).
            if EAB.db.profile.mouseoverShowAll then
                for otherKey, otherState in pairs(hoverStates) do
                    if otherKey ~= barKey and not otherState.isHovered then
                        EAB_VTABLE.Hover.FadeOut(otherKey, otherState)
                    end
                end
            end
        end
        state.foCb = cb
    end
    C_Timer_After(0.1, cb)
end

function EAB_VTABLE.Hover.BuildHandlers(barKey, state, opts)
    opts = opts or {}

    local function OnEnter(self)
        if opts.canEnter and not opts.canEnter(self, state) then return end
        state.isHovered = true
        EAB_VTABLE.Hover.FadeIn(barKey, state)
    end

    local function OnLeave()
        state.isHovered = false
        EAB_VTABLE.Hover.ScheduleFadeOut(barKey, state, opts)
    end

    return OnEnter, OnLeave
end

local function AttachDataBarHoverHooks(barKey)
    if hoverStates[barKey] then return end

    local frame = dataBarFrames[barKey]
    if not frame then return end

    local state = EAB_VTABLE.Hover.GetState(barKey, frame)
    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barKey, state)

    frame:HookScript("OnEnter", OnEnter)
    frame:HookScript("OnLeave", OnLeave)
end

local function AttachHoverHooks(barKey)
    -- Idempotency (same guard as both sibling attach functions): HookScript
    -- stacks and can never be unhooked, so a second pass would permanently
    -- double every hover handler on the bar and its 12 buttons.
    if hoverStates[barKey] then return end

    local frame = barFrames[barKey]
    local buttons = barButtons[barKey]
    if not frame or not buttons then return end

    local state = EAB_VTABLE.Hover.GetState(barKey, frame)

    local function CanEnter(self)
        -- Skip hidden empty buttons (alwaysShowButtons off)
        local s = EAB.db.profile.bars[barKey]
        if s then
            local showEmpty = s.alwaysShowButtons
            if showEmpty == nil then showEmpty = true end
            if not showEmpty then
                if self ~= frame then
                    -- Individual button: skip a parked empty slot (our own
                    -- record, never GetAlpha: another addon may fade the button).
                    if ns._eabParked(self) then
                        return false
                    end
                else
                    -- Bar frame itself (gaps between buttons): allow only if the
                    -- cursor is within pad of a shown button that is not parked.
                    local cx, cy = GetCursorPosition()
                    local scale = frame:GetEffectiveScale()
                    cx, cy = cx / scale, cy / scale
                    local pad = (s.buttonPadding or 2) + 2
                    local nearVisible = false
                    for i = 1, #buttons do
                        local btn = buttons[i]
                        if btn and btn:IsShown() and not ns._eabParked(btn) then
                            local bl, bb, bw, bh = btn:GetRect()
                            if bl and cx >= bl - pad and cx <= bl + bw + pad and cy >= bb - pad and cy <= bb + bh + pad then
                                nearVisible = true
                                break
                            end
                        end
                    end
                    if not nearVisible then return false end
                end
            end
        end
        return true
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barKey, state, {
        canEnter = CanEnter,
        blockFadeOut = function()
            -- Keep bar visible while a spell flyout spawned from this bar is open.
            return GetEABFlyout():IsVisible() and GetEABFlyout():IsMouseOver()
        end,
    })

    frame:HookScript("OnEnter", OnEnter)
    frame:HookScript("OnLeave", OnLeave)
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
        end
    end
end

-- onlyHoverGated: visit ONLY the bars whose hover gate can move on a state edge (Match
-- Any plus mouseover). The edge-driven caller passes it so a target change does not drag
-- every other bar through a StopFade/SetAlpha it cannot need.
function EAB:RefreshMouseover(onlyHoverGated)
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s and (not onlyHoverGated or (s.mouseoverEnabled and s.visibilityMatch == "any")) then
            local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
            if frame then
                -- For extra bars (MicroBar, BagBar), fade the Blizzard frame directly
                -- since that's what AttachExtraBarHoverHooks targets.
                if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                    local blizzFrame = _G[info.frameName]
                    if blizzFrame then frame = blizzFrame end
                end
                if info.noManagedVisibility then
                    -- Position-only Blizzard-owned eye (QueueStatus): EUI no longer
                    -- controls its visibility, so never fade or alpha-hide it --
                    -- force full opacity regardless of stale mouseover settings.
                    StopFade(frame, 1)
                elseif s.mouseoverEnabled then
                    if info.isDataBar then
                        AttachDataBarHoverHooks(key)
                    end
                    -- Ensure extra bars have hover hooks attached (may not have been
                    -- set up at load time if mouseover was disabled then)
                    if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                        ns.AttachExtraBarHoverHooks(info)
                    end
                    local state = hoverStates[key]
                    -- A bar the cursor is sitting on keeps what the hover gave it. This
                    -- used to be safe by accident (the function only ran on settings
                    -- changes); it now also runs on combat/group/mount edges, where
                    -- repainting would yank a hovered bar invisible mid-hover.
                    if not (state and state.isHovered) then
                        local resting = EAB_VTABLE.Hover.RestingAlpha(key, s)
                        StopFade(frame, resting)
                        if state then state.fadeDir = (resting == 0) and "out" or nil end
                        if key == "MainBar" then SyncPagingAlpha(resting) end
                    end
                else
                    StopFade(frame, s.mouseoverAlpha or 1)
                    local state = hoverStates[key]
                    if state then state.fadeDir = nil end
                    if key == "MainBar" then SyncPagingAlpha(s.mouseoverAlpha or 1) end
                end
            end
        end
    end
end

-- Advanced Fade hooks are installed lazily, only after at least one enabled bar
-- actually has a Fade Condition.  Therefore a fresh login/reload with all master
-- toggles OFF runs the stock upstream alpha functions with no Advanced Fade hooks at all.
function EAB:EnsureAdvancedFadeHooks()
    if self._advancedFadeHooksInstalled then return end
    self._advancedFadeHooksInstalled = true

    hooksecurefunc(EAB, "ApplyBarOpacity", function(_, barKey)
        if EAB._anyCustomFade then
            EAB_VTABLE.Hover.RefreshCustomFadeBar(barKey, false, true)
        end
    end)

    hooksecurefunc(EAB_VTABLE.Hover, "FadeInOne", function(barKey)
        if EAB._anyCustomFade then
            EAB_VTABLE.Hover.RefreshCustomFadeBar(barKey, true, true)
        end
    end)

    hooksecurefunc(EAB_VTABLE.Hover, "FadeOut", function(barKey)
        if EAB._anyCustomFade then
            EAB_VTABLE.Hover.RefreshCustomFadeBar(barKey, true, true)
        end
    end)

    hooksecurefunc(EAB, "RefreshMouseover", function(self)
        if self._anyCustomFade then
            self:RefreshAllCustomFade(false, true)
        end
    end)

    self._advancedFadeUpdater = function()
        if EAB._anyCustomFade then
            EAB:RefreshAllCustomFade(true, false)
        end
    end
end

-- Entry points the files after this one re-import by name.
I.hoverStates, I.AttachDataBarHoverHooks, I.AttachHoverHooks = hoverStates, AttachDataBarHoverHooks, AttachHoverHooks
