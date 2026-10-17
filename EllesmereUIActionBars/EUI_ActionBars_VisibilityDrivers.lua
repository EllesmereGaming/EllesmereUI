if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_VisibilityDrivers.lua
--
--  The visibility condition builder for the state drivers, runtime
--  visibility with the lazy bar build, and extra bar visibility.
--  Loads after EUI_ActionBars_Fade.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local RegisterAttributeDriver = RegisterAttributeDriver

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local ALL_BARS, BAR_CONFIG, EXTRA_BARS = I.ALL_BARS, I.BAR_CONFIG, I.EXTRA_BARS
local barFrames, blizzMovableHolders, dataBarFrames = I.barFrames, I.blizzMovableHolders, I.dataBarFrames
local extraBarHolders, SecureSetupHandler_PrepareRefs = I.extraBarHolders, I.SecureSetupHandler_PrepareRefs
local LayoutBar = I.LayoutBar
local SetSecureRefsReady = I.SetSecureRefsReady
-- Written in EUI_ActionBars_Layout.lua;
-- SetIsApplyingAll hands the value to this copy.
local _isApplyingAll = false
I.isApplyingAllSetters[#I.isApplyingAllSetters + 1] = function(v) _isApplyingAll = v end

-------------------------------------------------------------------------------
--  Visibility Condition Builder: macro condition string for RegisterStateDriver,
--  per bar type and user settings (combat show/hide).
--    MainBar (bar 1): visible during vehicle/override (paging shows the right
--                      actions); hides during pet battle.
--    Bars 2-8:         hide during vehicle UI, pet battle and override bar
--                      (only bar 1 pages to override/vehicle actions).
--    StanceBar:        hide during vehicle UI and pet battle.
--    PetBar:           hide during pet battle; shows only with a pet and no
--                      vehicle/override/possess state.
-------------------------------------------------------------------------------
-- Multi-select visibility compiler: thin delegate to the shared secure driver
-- compiler in EllesmereUI_Visibility.lua (one grammar for Action Bars and
-- Unit Frames). EAB table fields, not locals.
function EAB.BuildVisModeConjuncts(vm)
    return EllesmereUI.BuildVisModeConjuncts(vm)
end

function EAB.BuildVisibilityStringMulti(hidePrefix, vm)
    return EllesmereUI.BuildVisibilityDriverString(hidePrefix, vm)
end

-- Edges this addon watches, for the shared Any tail builder: the target/enemy axes may
-- compile to live macro tokens because the soft-target machinery (PLAYER_SOFT_* events
-- + the 0.1s poll) rebuilds the driver when they drift. EAB field, not a local.
EAB.VIS_EDGES = { softTarget = true }

local function BuildVisibilityString(info, s, visOverride)
    -- Hide Bar When Using Gamepad compiles to the constant a Never bar gets, so
    -- every writer that builds a bar's driver here agrees (combat-gated sites,
    -- regen healers, housing/soft-target/pet rebuilds). An explicit override
    -- (toggle keybind, drag, spellbook) still wins, as it does over Never.
    if EAB._padHide and not visOverride and s.gamepadHideBar == true then return "hide" end
    local key = info.key
    local vis = visOverride or s.barVisibility or "always"
    -- An applied Visibility override replaces the whole setting, the shared option
    -- lanes included. The runtime toggle keybind still wins over it, the same way it
    -- wins over the saved mode.
    local visOv = (not visOverride) and EllesmereUI.VisOverrideValue(s) or nil

    if info.isStance and (GetNumShapeshiftForms() or 0) == 0 then
        return "hide" -- classes/specs with no forms have no stance bar to show
    end

    -- Visibility-option hide clauses expressed as macro conditionals; run
    -- inside the secure state driver so they work in combat without taint. Under Any the
    -- Any tail below compiles both halves itself: Show lanes as disjuncts, Hide lanes as
    -- its own leading gates, so this block would only duplicate them.
    local visOptHide = ""
    if s.visibilityMatch ~= "any" and not visOv then
        if s.visHideMounted then visOptHide = visOptHide .. "[mounted] hide; " end
        -- Inverse of the above. [nomounted] cannot see druid travel/flight forms
        -- (they are shapeshifts), so a druid in a mount-like form reads unmounted
        -- here and the bar hides -- accepted asymmetry: the secure clause is what
        -- keeps this working in combat, and Lua cannot un-hide past the driver.
        if s.visOnlyMounted then visOptHide = visOptHide .. "[nomounted] hide; " end
        if s.visHideNoTarget then visOptHide = visOptHide .. "[noexists] hide; " end
        if s.visHideWithTarget then visOptHide = visOptHide .. "[exists] hide; " end
        if s.visHideNoEnemy then visOptHide = visOptHide .. "[noharm] hide; " end
        if s.visHideWithEnemy then visOptHide = visOptHide .. "[harm] hide; " end
    end

    -- Authoritative multi-select set. Explicit overrides (toggle keybind,
    -- QuickKeybind, grid drag) substitute the whole mode term as for single
    -- modes, so they keep the legacy path.
    local vm
    if not visOverride and EllesmereUI.GetActiveVisibilityModes then
        vm = EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
    end

    -- Any match: the shared builder compiles the whole tail; Lua-only lanes (instances,
    -- housing, skyriding mount) are resolved at build time, so their verdict is only as
    -- fresh as the last driver rebuild. Explicit overrides keep the legacy path.
    if not visOverride and s.visibilityMatch == "any" and EllesmereUI.BuildAnyMatchTail then
        local anyPrefix, anyWrap
        if info.isPetBar then
            anyPrefix = "[petbattle] hide; "
            anyWrap = "novehicleui,pet,nooverridebar,nopossessbar"
        elseif key == "MainBar" then
            anyPrefix = "[petbattle] hide; "
        elseif info.isStance then
            anyPrefix = "[vehicleui][petbattle] hide; "
        else
            anyPrefix = "[vehicleui][petbattle][overridebar] hide; "
        end
        return anyPrefix .. EllesmereUI.BuildAnyMatchTail(s, "barVisibility", vm, anyWrap, EAB.VIS_EDGES)
    end

    -- Pet bar has unique logic: it only shows when a pet is active and
    -- the player is not in a vehicle/override/possess state.
    if info.isPetBar then
        -- Both paths fold the mode's AND terms INTO the pet wrapper bracket. Adjacent
        -- bracket groups are OR in macro grammar, so a mode clause beside the wrapper
        -- ("[...pet...] [combat] show") matches on the pet term alone and ignores the
        -- mode (inverting the two dragonriding modes). A negated axis has no AND token,
        -- becoming a leading hide gate instead (same technique as visOptHide).
        local conj, negGate
        if visOv then
            -- An override replaces the setting, so no mode terms at all: Never hides
            -- outright, the other two leave the pet wrapper as the only condition.
            if visOv == "never" then return "hide" end
            conj, negGate = "", ""
        elseif vm then
            -- Group modes are structurally unsupported here (locked in UI, stripped by sync copies).
            conj, negGate = EAB.BuildVisModeConjuncts(vm)
        else
            conj, negGate = "", ""
            if vis == "in_combat" then
                conj = "combat,"
            elseif vis == "out_of_combat" then
                conj = "nocombat,"
            elseif vis == "show_dragonriding" then
                conj = "advflyable,flying,"
            elseif vis == "show_not_dragonriding" then
                negGate = "[advflyable,flying] hide; "
            elseif s.combatShowEnabled then
                conj = "combat,"
            elseif s.combatHideEnabled then
                negGate = "[combat] hide; "
            end
        end
        local bracket = "[novehicleui,pet,nooverridebar,nopossessbar"
        if conj ~= "" then bracket = bracket .. "," .. conj:sub(1, -2) end
        bracket = bracket .. "]"
        return "[petbattle] hide; " .. visOptHide .. negGate .. bracket .. " show; hide"
    end

    -- Build the hide-prefix based on bar type
    local hidePrefix
    if key == "MainBar" then
        hidePrefix = "[petbattle] hide; "
    elseif info.isStance then
        hidePrefix = "[vehicleui][petbattle] hide; "
    else
        hidePrefix = "[vehicleui][petbattle][overridebar] hide; "
    end

    -- Inject visibility-option hide clauses after the standard hide-prefix
    hidePrefix = hidePrefix .. visOptHide

    -- One constant, with the standard pet battle / vehicle prefix still in front.
    if visOv then
        return hidePrefix .. ((visOv == "never") and "hide" or "show")
    end

    -- Multi-select set: compiled tail; the legacy single-mode chain below
    -- stays byte-identical for every scalar value.
    if vm then
        return EAB.BuildVisibilityStringMulti(hidePrefix, vm)
    end

    -- Append visibility mode conditions
    if vis == "never" then
        return hidePrefix .. "hide"
    elseif vis == "in_combat" then
        return hidePrefix .. "[combat] show; hide"
    elseif vis == "out_of_combat" then
        return hidePrefix .. "[nocombat] show; hide"
    elseif vis == "in_raid" then
        return hidePrefix .. "[group:raid] show; hide"
    elseif vis == "in_party" then
        -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows it
        -- to a real party so unchecking In Raid Group actually hides in raids.
        return hidePrefix .. "[group:party,nogroup:raid] show; hide"
    elseif vis == "solo" then
        return hidePrefix .. "[nogroup] show; hide"
    elseif vis == "show_dragonriding" then
        -- No "mounted": Flight Form is a shapeshift, not a mount. advflyable
        -- covers skyriding mounts + Flight Form, excludes ordinary flying.
        return hidePrefix .. "[advflyable,flying] show; hide"
    elseif vis == "show_not_dragonriding" then
        -- Exact inverse: hide while dragonriding, show otherwise; hidePrefix
        -- still force-hides in pet battle/vehicle.
        return hidePrefix .. "[advflyable,flying] hide; show"
    end
    return hidePrefix .. "show"
end

-------------------------------------------------------------------------------
--  Extra Bar Visibility (Pet Battle / Vehicle Hiding): MicroBar, BagBar, data
--  bars and Blizzard movable frames are not SecureHandlerStateTemplate
--  frames, so one secure proxy frame monitors [petbattle]/[vehicleui] and
--  calls methods to show/hide them.
-------------------------------------------------------------------------------
local _extraBarVisProxy  -- created once, reused

function EAB:ApplyExtraBarVisibility()
    if not _extraBarVisProxy then
        _extraBarVisProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        _extraBarVisProxy:SetAttribute("_onstate-extravis", [[
            self:CallMethod("OnExtraVisChanged", newstate)
        ]])
        _extraBarVisProxy.OnExtraVisChanged = function(_, state)
            -- state is "hide" during pet battle, "show" otherwise
            local shouldHide = (state == "hide")
            for _, info in ipairs(EXTRA_BARS) do
                if info.noManagedVisibility then
                    -- skip
                else
                local key = info.key
                local s = EAB.db and EAB.db.profile.bars[key]
                if s and not s.alwaysHidden then
                    local frame
                    if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                        frame = EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
                    elseif info.isBlizzardMovable then
                        frame = blizzMovableHolders[key]
                    else
                        frame = _G[info.frameName]
                    end
                    if frame then
                        if shouldHide then
                            if info.blizzOwnedVisibility then
                                EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "petbattle", true)
                            else
                                frame:Hide()
                            end
                        else
                            if info.blizzOwnedVisibility then
                                EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "petbattle", false)
                            end
                            if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                                EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
                            else
                                frame:Show()
                            end
                        end
                    end
                end
            end -- if s
            end -- if not noManagedVisibility
        end
    end
    -- Register the state driver: hide during pet battle, show otherwise
    RegisterStateDriver(_extraBarVisProxy, "extravis", "[petbattle] hide; show")
end

--  Combat Show/Hide, Runtime Visibility, Click-Through, Housing
-------------------------------------------------------------------------------
function EAB:ApplyCombatVisibility()
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s then
            local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
            if frame and not info.visibilityOnly then
                local newStr
                if s.alwaysHidden then
                    newStr = "hide"
                -- Under Any the compiled driver already carries both halves (Show lanes as
                -- disjuncts, Hide lanes as leading gates, the Lua-only ones resolved at
                -- build time with their own combat escape hatch), so a literal "hide" here
                -- would replace a self-updating string with a dead constant. Same guard
                -- ShouldHideNonMacro carries; with all of them skipping it, the "any"
                -- branch inside CheckVisibilityOptionsNonMacro has no live caller left and
                -- is kept only so the helper stays correct for a future non-driver one.
                elseif s.visibilityMatch ~= "any" and EllesmereUI.CheckVisibilityOptionsNonMacro(s) then
                    newStr = "hide"
                else
                    newStr = BuildVisibilityString(info, s)
                end
                -- Skip re-registration if driver string is unchanged (avoids blink from re-evaluation)
                if frame._eabLastVisStr ~= newStr then

                    frame._eabLastVisStr = newStr
                    RegisterAttributeDriver(frame, "state-visibility", newStr)
                end
            end
        end
    end
    -- Pet battle / vehicle hiding for extra bars (MicroBar, BagBar, data bars)
    -- via a dedicated secure proxy: they are not SecureHandlerStateTemplate.
    self:ApplyExtraBarVisibility()
end

-- Gates for the soft-target poll, so it costs nothing for users who do not use
-- the feature. Recomputed on every visibility refresh below and once at setup,
-- so it can never desync from the bar settings.
function EAB:_RefreshSoftTargetGate()
    -- Two gates from one walk (re-run on every config apply):
    --   _anyHideNoTarget -- any bar with "Hide when No Target" (soft-target
    --   override machinery: the 0.1s poll + ImmediateSoftTargetCheck).
    --   _anyNonMacroVis  -- any bar using ANY non-macro visibility option, or
    --   a managed non-secure bar; when false, UpdateHousingVisibility has
    --   nothing it could ever change and skips entirely.
    --   _anyHoverGated   -- any bar whose hover gate can OPEN and CLOSE on a state edge
    --   (Match Any plus mouseover). Only those need the resting alpha re-derived when
    --   combat/group/mount state moves; under All a mouseover bar is hover-gated for as
    --   long as the setting stands, so its alpha never changes off an edge.
    local anySoft, anyNonMacro, anyHoverGated = false, false, false
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        if s then
            if s.mouseoverEnabled and s.visibilityMatch == "any" then
                anyHoverGated = true
            end
            -- Under Any the counter lane carries the soft-target correction too, so it
            -- arms the same machinery; under All it never did and still does not.
            if s.visHideNoTarget or (s.visHideWithTarget and s.visibilityMatch == "any") then
                anySoft = true
            end
            -- Driven off the shared key list rather than a hand-written subset: an
            -- option missing here silently skips the whole UpdateHousingVisibility pass
            -- for that bar. Deliberately over-inclusive (it also matches the
            -- macro-expressible lanes) -- a needless walk on a rare zone/mount edge is
            -- cheap, a missed one leaves the bar stale until the next settings change.
            if not anyNonMacro and EllesmereUI.VisHasAnyOption(s) then
                anyNonMacro = true
            end
        end
        if not anyNonMacro and EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
            anyNonMacro = true
        end
    end
    self._anyHideNoTarget = anySoft
    self._anyNonMacroVis = anyNonMacro
    self._anyHoverGated = anyHoverGated
end

-- Re-derive the resting alpha of every hover-gated bar. Registered once with the shared
-- visibility dispatcher (below), which already watches the exact edge set this depends on
-- (combat, group, target, mount, zone, shapeshift, gliding) and fans out one frame later.
-- Alpha only: no Show/Hide, no driver registration, so this is safe inside combat lockdown
-- and carries no taint exposure. Fully gated -- users with no Any-plus-mouseover bar pay
-- one flag read per dispatcher event.
function EAB:RefreshHoverGatedAlpha()
    if not self._anyHoverGated then return end
    self:RefreshMouseover(true)
end

-- Build the buttons of bars skipped at load (see SetupBar) that need them now:
-- the bar left the Never set (reveal), or a key landed on one of its commands
-- (hidden bars keep live bindings, and a click-routed key needs a button to
-- route to). Deliberately state-based rather than edge-based: an options write
-- taken in combat flips the Never map but cannot create secure frames, and the
-- PLAYER_REGEN_ENABLED healer re-enters the callers with the map ALREADY
-- flipped, so a transition test would never fire again and the bar would stay
-- buttonless until the next reload. Returns true when anything was built. The
-- CALLER owns the binding rebuild: one caller is UpdateKeybinds itself. On ns:
-- not a file local.
ns._eabBuildSkippedBars = function()
    if not next(ns._eabBarNoButtons) or InCombatLockdown() then return false end
    local built = false
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local frame = barFrames[key]
        if frame and ns._eabBarNoButtons[key]
           and (not ns._eabBarNever[key] or ns.BarHasBoundKeys(info)) then
            ns.BuildBarButtons(info, frame, false)
            LayoutBar(key)
            -- Still hidden (keybind case, or a reveal whose driver has not
            -- shown the frame yet): the hide edge already passed with no
            -- buttons, so park the new mixin event lists the way it would
            -- have. The show edge lifts this as usual.
            if not frame:IsShown() then
                ns._eabBarDormant[key] = nil
                ns.ApplyBarDormancy(key, true)
            end
            built = true
        end
    end
    if built then
        -- The refs pass already ran without these buttons in it.
        SetSecureRefsReady(false)
        SecureSetupHandler_PrepareRefs()
        -- Everything cosmetic (borders, shapes, fonts, backgrounds, button
        -- art, cooldown visuals, range colouring) converges through the
        -- full apply. Next frame, not inline: ApplyAll calls back into
        -- RefreshRuntimeVisibility, and the marker is already cleared by then
        -- so it finds nothing to build. On ns, not on EAB, so the
        -- EUI_UnlockMode hook on EAB.ApplyAll stays as it was.
        C_Timer.After(0, function()
            if ns._eabApplyAll then ns._eabApplyAll() end
        end)
    end
    return built
end

-- Tail of ApplyBordersForBar / ApplyShapesForBar. Armed copies restyle with the
-- bar border (out of combat; a combat pass defers to the regen ApplyAll);
-- eligOnly (the shape tail) skips that restyle. A bar that moved in or out of
-- eligibility re-runs the three role passes, which own the edges-or-copy
-- choice; ApplyAll runs them itself right after its bar loop. Lives here, not
-- in EUI_ActionBars_Pushed.lua with the rest of Match Bar Border: it reads
-- _isApplyingAll, a chunk local that ApplyAll rewrites.
ns._ixBarSync = function(barKey, eligOnly)
    local p = EAB.db and EAB.db.profile
    if not p then return end
    local push, hover, cast = ns._ixRolesOn(p)
    if not (push or hover or cast) then return end
    local elig, changed = ns._ixBarEligible(barKey)
    if elig and not eligOnly then
        local buttons = barButtons[barKey]
        local s = p.bars[barKey]
        if buttons and s then
            if InCombatLockdown() then
                ns._eabApplyDeferred = true
            else
                for i = 1, #buttons do
                    local btn = buttons[i]
                    local fd = btn and ns._eabFD[btn]
                    if fd and fd.ixStyled then ns._ixStyle(btn, fd, s) end
                end
            end
        end
    end
    if changed and not _isApplyingAll then
        EAB:ApplyPushedTextures()
        EAB:ApplyHighlightTextures()
        EAB:ApplyCheckedTextures()
    end
end

-- Entry points the files after this one re-import by name.
I.BuildVisibilityString = BuildVisibilityString
