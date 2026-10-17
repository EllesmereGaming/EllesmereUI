if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ApplyAll.lua
--
--  ApplyAll, the full visual application over every bar.
--  Loads after EUI_ActionBars_Vehicle.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs = ipairs, pairs
local wipe = wipe
local InCombatLockdown = InCombatLockdown

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local I = ns._internals
local _dragState, BAR_CONFIG = I._dragState, I.BAR_CONFIG
local barFrames = I.barFrames
local LayoutBar = I.LayoutBar
local SetIsApplyingAll = I.SetIsApplyingAll

-------------------------------------------------------------------------------
--  Apply All orchestrates full visual application
-------------------------------------------------------------------------------
local function ApplyAll()
    SetIsApplyingAll(true)
    -- Full applies can create/enable bars and reassign slots without any
    -- dispatcher content event: retire the filled-slot fast lists, and the
    -- curated memo with them (profile swaps can land mid-session).
    ns._cdFilledDirty = true
    ns._cdCuratedDirty = true

    -- Restore any strata raised during a drag that wasn't cleaned up
    if _dragState.visible then
        _dragState.visible = false
        for frame, orig in pairs(_dragState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        wipe(_dragState.strataCache)
    end

    local inCombat = InCombatLockdown()

    if not inCombat then
        EAB_VTABLE.MainBarPageSync.InstallAll()
    end

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = EAB.db.profile.bars[key]
        local frame = barFrames[key]

        -- Bar enabled/disabled toggle (protected frames can't be shown/hidden in combat)
        if frame and s and not inCombat then
            if s.enabled == false then
                frame:Hide()
            elseif not s.alwaysHidden then
                -- Skip Show if a state-visibility driver is managing this frame
                -- (the driver handles show/hide; calling Show() causes a one-frame blink)
                if not frame._eabLastVisStr then
                    frame:Show()
                end
            end
        end

        if not inCombat then
            LayoutBar(key)
        end
        if not inCombat then EAB:ApplyBordersForBar(key) end
        if not inCombat then EAB:ApplyShapesForBar(key) end
        EAB:ApplyFontsForBar(key)
        EAB:ApplyBackgroundForBar(key)
        EAB:ApplyIconBackgroundForBar(key)
        if not inCombat then EAB:ApplyAlwaysShowButtons(key) end
        if not inCombat then EAB:ApplyClickThroughForBar(key) end
    end
    -- The micro menu's and bag bar's caps (a profile or spec switch changes
    -- their keys without bar 1's layout stamp moving).
    ns.AB_ExtraCapsAll()

    EAB:ApplyPushedTextures()
    EAB:HookPushedFlash()
    EAB:ApplyHighlightTextures()
    EAB:ApplyCooldownFonts()
    EAB:ApplyCooldownSwipeColor()
    EAB:ApplySlotBackgroundColor()
    -- Gated so it's zero-touch at the default (100); the live handler + setValue
    -- own the rest.
    if EAB.db and EAB.db.profile and EAB.db.profile.alphaWhenOnCD ~= 100 then
        EAB:ApplyCDAlphaAll()
    end
    EAB:ApplyCooldownEdge()
    EAB:ApplyMiscTextures()
    EAB:ApplyCheckedTextures()
    EAB:ApplyEquippedBorder(true)
    if not inCombat then EAB:ApplyCombatVisibility() end
    if not inCombat then EAB:RefreshRuntimeVisibility() end
    EAB:RefreshMouseover()
    EAB:RefreshProcGlows()
    EAB:ApplyRangeColoring()

    -- A full apply that ran DURING combat skipped every `not inCombat` step
    -- above; the REGEN_ENABLED re-run (gated on this flag) converges them.
    if inCombat then ns._eabApplyDeferred = true end

    -- Dormancy re-sync: a profile swap or options change can re-register
    -- visibility drivers without firing the per-bar OnShow/OnHide edges the
    -- dormancy map saw. Per-key memoized, so unchanged bars cost one table read.
    for _, info in ipairs(BAR_CONFIG) do
        local f = barFrames[info.key]
        if f then ns.ApplyBarDormancy(info.key, not f:IsVisible()) end
    end

    -- Party Mode orbit: claims the buttons this rebuild built or showed (Party
    -- Mode may have started -- login, keybind, Bloodlust -- before they
    -- existed); a button the rebuild re-anchored re-measures its rest through
    -- the engine's SetPoint hook.
    ns.PartySpin_Refresh()

    -- Register with Masque after sizing and layout, since AddButton skins immediately.
    EAB_VTABLE.RegisterMasqueButtons()
    if ns.MasqueGroup then
        EAB:ApplyPushedTextures()
        EAB:ApplyHighlightTextures()
    end

    if not inCombat then ns.RefreshPagingCycleMacros() end
    SetIsApplyingAll(false)
end

-- Handle for the lazy bar build in RefreshRuntimeVisibility, which sits above
-- this definition and cannot see the local. On ns and not on EAB deliberately:
-- the EUI_UnlockMode hook watches EAB.ApplyAll, and putting it there would
-- start firing that hook for the first time.
ns._eabApplyAll = ApplyAll

-- Entry points the files after this one re-import by name.
I.ApplyAll = ApplyAll
