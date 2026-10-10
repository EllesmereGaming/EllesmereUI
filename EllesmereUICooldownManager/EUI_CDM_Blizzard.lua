if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Blizzard.lua
--
--  Blizzard viewer lists and fonts, position capture, Edit Mode enforcement,
--  hiding and restoring the Blizzard Cooldown Manager.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME, FC, _ecmeFC, cdmBarFrames = I.ECME, I.FC, I._ecmeFC, I.cdmBarFrames

-------------------------------------------------------------------------------
--  CDM Bars: Our replacement for Blizzard's Cooldown Manager
--  Captures Blizzard positions on first login, then creates our own bars.
-------------------------------------------------------------------------------
local function GetCDMFont() return EllesmereUI.GetFontPath("cdm") end
local function SetBlizzCDMFont(fs, font, size, r, g, b)
    if not (fs and fs.SetFont) then return end
    EllesmereUI.ApplyIconTextFont(fs, font, size, "cdm")
    if r then fs:SetTextColor(r, g, b) end
end

-- Blizzard CDM frame names
local BLIZZ_CDM_FRAMES = {
    cooldowns = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffs     = "BuffIconCooldownViewer",
}

-- BuffBarCooldownViewer is Blizzard's buff bar strip, hidden alongside the icon viewer so
-- the default buff display is fully suppressed when CDM hiding is on. Our Tracked Buff Bars replace it.
local BLIZZ_CDM_FRAMES_SECONDARY = {
    buffs = "BuffBarCooldownViewer",
}

-- CDM category numbers per bar key (for C_CooldownViewer API)
local CDM_BAR_CATEGORIES = {
    cooldowns = { 0, 1 },    -- Essential + Utility
    utility   = { 0, 1 },    -- Essential + Utility
    buffs     = { 2, 3 },    -- Tracked Buff + Tracked Debuff
}

-- Maximum number of custom bars a user can create
local MAX_CUSTOM_BARS = 20

-- Forward declarations
local HideBlizzardCDM, RestoreBlizzardCDM
local CaptureCDMPositions

-------------------------------------------------------------------------------
--  Capture Blizzard CDM positions (first login only)
-------------------------------------------------------------------------------
CaptureCDMPositions = function()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    for barKey, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            local data = {}

            -- Read the frame's scale (used to adjust icon size capture)
            local frameScale = frame:GetScale()
            if not frameScale or frameScale < 0.1 then frameScale = 1 end

            -- Icon size + spacing from child icons. Blizzard CDM icons have a base size plus a
            -- per-icon scale driven by the IconSize percentage slider; spacing is the gap between two adjacent visible icons in parent coordinates.
            local numDistinctY = {}
            local shownIcons = {}
            local children = { frame:GetChildren() }
            for ci = 1, #children do
                local child = children[ci]
                if child and child.Icon then
                    local cw = child:GetWidth()
                    local cs = child:GetScale()
                    if cw and cw > 1 and not data.iconSize then
                        local visual = cw * (cs or 1)
                        data.iconSize = math.floor(visual + 0.5)
                    end
                    -- Collect shown icons for spacing measurement
                    if child:IsShown() then
                        shownIcons[#shownIcons + 1] = child
                        -- Track distinct Y positions for row counting
                        if child:GetPoint(1) then
                            local _, _, _, _, cy = child:GetPoint(1)
                            if cy then
                                numDistinctY[math.floor(cy + 0.5)] = true
                            end
                        end
                    end
                end
            end

            if #shownIcons >= 2 and data.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(a, b)
                    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                end)
                -- Smallest step between consecutive sorted icons. GetLeft() returns UIParent-coordinate-space values.
                local bestStep = nil
                for si = 1, #shownIcons - 1 do
                    local aLeft = shownIcons[si]:GetLeft()
                    local bLeft = shownIcons[si + 1]:GetLeft()
                    if aLeft and bLeft then
                        local dist = bLeft - aLeft
                        if dist > 0 and (not bestStep or dist < bestStep) then
                            bestStep = dist
                        end
                    end
                end
                if bestStep then
                    -- bestStep is UIParent coords; the icon-parent -> UIParent multiplier is
                    -- frame.effectiveScale / UIParent.effectiveScale, so divide for frame coords.
                    -- Frame positions use cw units while iconSize = cw * cs (visual), so multiply by cs for the step in iconSize units.
                    local frameEff = frame:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    local cs = shownIcons[1]:GetScale() or 1
                    local stepInIconUnits = parentStep * cs
                    local gap = stepInIconUnits - data.iconSize
                    if gap < 0 then gap = 0 end
                    data.spacing = math.floor(gap + 0.5)
                end
            end

            -- Rows: count distinct Y positions among visible icon children
            local rowCount = 0
            for _ in pairs(numDistinctY) do rowCount = rowCount + 1 end
            if rowCount >= 1 then
                data.numRows = rowCount
            end

            if frame.isHorizontal ~= nil then
                data.isHorizontal = frame.isHorizontal
            end

            -- Position (center-based, in UIParent coordinates)
            if frame:GetPoint(1) then
                local cx, cy = frame:GetCenter()
                if cx and cy then
                    local bScale = frame:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    data.point = "CENTER"
                    data.relPoint = "CENTER"
                    data.x = cx - (uiW / 2)
                    data.y = cy - (uiH / 2)
                end
            end

            captured[barKey] = data
        end
    end

    return captured
end

-------------------------------------------------------------------------------
--  EnforceCooldownViewerEditModeSettings (one-shot)
--  Runs ONCE on init to force Edit Mode settings so Blizzard's hideWhenInactive/visibility
--  modes can't interfere with CDM's frame management:
--    - VisibleSetting = Always on ALL viewers
--    - HideWhenInactive = 1 on buff viewers (BuffIcon + BuffBar)
--  SaveLayouts is called at most once, during init, NEVER at runtime: a SaveLayouts-triggered layout reapply from addon code taints Blizzard frame properties (isActive, etc.).
-------------------------------------------------------------------------------
local _editModePolicyApplied = false

-- Shown when our automatic save did NOT take (see the loop breaker below). Dismissable, and
-- deliberately repeats every login until the layout is correct: going quiet would leave CDM
-- misbehaving unexplained. CDM must be OFF while the user follows the steps -- this addon hides
-- Blizzard's cooldown viewers, and a hidden system cannot be selected in Edit Mode; the confirm
-- button does that step. Step 6 lives in the text because once CDM is disabled nothing of ours runs to remind them to re-enable it.
local function ShowManualEditModeFixPopup()
    C_Timer.After(0, function()
        if not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then return end
        EllesmereUI:ShowConfirmPopup({
            title = "Edit Mode Needs a Manual Fix",
            message = "EllesmereUI could not save this change to your Edit Mode layout, so it has to be set by hand. The Cooldown Manager has to be off while you do it, because it hides Blizzard's cooldown viewers and a hidden viewer cannot be selected in Edit Mode.\n\n"
                .. "1. Disable EllesmereUI Cooldown Manager (button below).\n"
                .. "2. Open Edit Mode from the Game Menu.\n"
                .. "3. Select each Cooldown Manager viewer and set Visibility to Always.\n"
                .. "4. On Tracked Buffs and Tracked Bars, tick Hide When Inactive.\n"
                .. "5. Save the layout and leave Edit Mode.\n"
                .. "6. Re-enable EllesmereUI Cooldown Manager.",
            disclaimer = "This will keep appearing each login until the layout is correct.",
            confirmText = "Disable CDM & Reload",
            cancelText = "Not Now",
            reload = true,
            onConfirm = function()
                C_AddOns.DisableAddOn("EllesmereUICooldownManager")
            end,
        })
    end)
end

local function EnforceCooldownViewerEditModeSettings()
    if _editModePolicyApplied then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSystemIndices) then
        return
    end

    -- Presets merged first so the activeLayout index resolves correctly. Presets unresolved:
    -- activeLayout counts them, so without the merge it picks the WRONG layout below and the
    -- save hands the client a list its own index no longer fits.
    local layoutInfo, numPresets = EllesmereUI.EditModeLayoutsForSave()
    if not layoutInfo then return end

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    -- Preset layouts are read-only: SaveLayouts won't persist changes to them, which would
    -- loop enforce -> save -> reload forever (the preset resets next login). Skip enforcement for presets.
    if numPresets > 0 and type(layoutInfo.activeLayout) == "number" and layoutInfo.activeLayout <= numPresets then
        -- Nothing to enforce on a preset: Always Show Buffs needs no layout change (it draws placeholder icons).
        _editModePolicyApplied = true
        return
    end

    local changed = false
    local cooldownSystem = Enum.EditModeSystem.CooldownViewer
    local visSetting  = Enum.EditModeCooldownViewerSetting.VisibleSetting
    local visAlways   = Enum.CooldownViewerVisibleSetting.Always
    local hideEnum    = Enum.EditModeCooldownViewerSetting.HideWhenInactive
    local buffIconIdx = Enum.EditModeCooldownViewerSystemIndices.BuffIcon
    local buffBarIdx  = Enum.EditModeCooldownViewerSystemIndices.BuffBar

    -- Returns changed(bool). A layout stores a CooldownViewer setting ONLY when changed away
    -- from Blizzard's default, so an absent entry means "at the default" (defaultValue). When
    -- that already equals what we want, leave the entry absent (no change, no forced reload); only add an explicit entry when default differs from desired.
    -- Each change is noted for Uninstall EUI (only the player's own earlier value is put
    -- back: these are Blizzard's defaults, so there is no fallback).
    local function UpsertSetting(sysInfo, settingEnum, desiredValue, defaultValue)
        local settings = sysInfo.settings
        for _, s in ipairs(settings) do
            if s.setting == settingEnum then
                if s.value ~= desiredValue then
                    EllesmereUI.NoteEditModeSetting(activeLayout, sysInfo, settingEnum, s.value, desiredValue)
                    s.value = desiredValue
                    return true
                end
                return false
            end
        end
        -- Absent: at the Blizzard default. Nothing to do if that already matches.
        if desiredValue == defaultValue then
            return false
        end
        EllesmereUI.NoteEditModeSetting(activeLayout, sysInfo, settingEnum, defaultValue, desiredValue)
        settings[#settings + 1] = { setting = settingEnum, value = desiredValue }
        return true
    end

    for _, sysInfo in ipairs(activeLayout.systems) do
        if sysInfo.system == cooldownSystem and type(sysInfo.settings) == "table" then
            -- VisibleSetting=Always on ALL viewers. That IS the default, so an absent entry is already correct and is left alone.
            if UpsertSetting(sysInfo, visSetting, visAlways, visAlways) then
                changed = true
            end
            -- Both buff viewers keep Blizzard's default HideWhenInactive=1 (inactive entries
            -- stay hidden): Always Show Buffs is drawn by our own per-bar placeholder icons, NOT
            -- Blizzard's layout, so any stale HideWhenInactive=0 is reset. New installs are already at the default (no change, no reload).
            if sysInfo.systemIndex == buffIconIdx or sysInfo.systemIndex == buffBarIdx then
                if UpsertSetting(sysInfo, hideEnum, 1, 1) then
                    changed = true
                end
            end
        end
    end

    _editModePolicyApplied = true
    if not changed then
        -- Settled: the layout already carries what we want, so a previous save DID stick.
        -- Re-arm the loop breaker so a genuine future change (new layout, manual edit) still prompts.
        if EllesmereUIDB then EllesmereUIDB.cdmEditModeSavePending = nil end
        return
    end

    -- Save the corrected layout. Blizzard won't visually apply it until the next login/reload, so force a reload via popup.
    C_EditMode.SaveLayouts(layoutInfo)

    -- LOOP BREAKER: a forced reload only makes sense if the save persisted. If this exact
    -- correction was saved in a PREVIOUS session and the delta is STILL here, the save did not
    -- stick, so re-offering the same non-dismissable reload would trap the user every login.
    -- The forced reload is offered at most once per unresolved correction; after that the user
    -- gets manual instructions every login until the layout comes back clean. Flag clears itself
    -- in the not-changed branch above, so a working user pays nothing. Backstop, NOT the cure -- it stops the loop without knowing why the save failed.
    local savedLastSession = EllesmereUIDB and EllesmereUIDB.cdmEditModeSavePending
    if EllesmereUIDB then EllesmereUIDB.cdmEditModeSavePending = true end
    if savedLastSession then
        ShowManualEditModeFixPopup()
        return
    end

    -- Forced (non-dismissable) reload popup. On first install the Welcome picker is
    -- pending/open and ALWAYS ends in its own reload, which applies the layout we
    -- just saved -- a second forced popup would stomp the picker, so stay silent and ride that reload.
    if EllesmereUI and EllesmereUI._firstInstallPending then return end
    C_Timer.After(0, function()
        EllesmereUI:ShowConfirmPopup({
            title = "Edit Mode Update",
            message = "EllesmereUI has updated your CDM Edit Mode settings to ensure cooldown tracking works correctly.\n\nA UI reload is required for the changes to take effect.",
            confirmText = "Reload UI",
            reload    = true,
        })
        -- Force: no cancel, no escape, no click-outside dismiss.
        local popup = _G["EUIConfirmPopup"]
        if popup then
            if popup._cancelBtn then popup._cancelBtn:Hide() end
            if popup._confirmBtn then
                popup._confirmBtn:ClearAllPoints()
                popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13)
            end
            popup:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            end)
            if popup._dimmer then
                popup._dimmer:SetScript("OnMouseDown", nil)
            end
        end
    end)
end

-- One-time per-profile migration: the GLOBAL Always Show Buffs settings (cdmBars.showInactiveBuffIcons/
-- .desaturateInactiveBuffs) become PER-BAR fields; a profile with the global ON turns every buff bar ON.
-- Runs once per profile (flag on cdmBars); re-runs on swap to a pre-migration profile, which carries no flag.
function ns.MigrateAlwaysShowBuffsToPerBar()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or p.cdmBars._asbPerBarMigrated then return end
    p.cdmBars._asbPerBarMigrated = true
    local oldOn = p.cdmBars.showInactiveBuffIcons
    local oldDesat = p.cdmBars.desaturateInactiveBuffs
    if oldOn == nil and oldDesat == nil then return end
    if type(p.cdmBars.bars) ~= "table" then return end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.barType == "buffs" then
            if oldOn ~= nil then bd.showInactiveBuffIcons = oldOn and true or false end
            if oldDesat ~= nil then bd.desaturateInactiveBuffs = oldDesat end
        end
    end
end

-- One-time per-profile migration: the custom_buff ("Auras") bar type merged into the buff
-- family. Converts every custom_buff bar to "buffs" in place -- key, assignedSpells,
-- spellDurations, customSpellIDs, position and all visual settings carry over unchanged. The
-- buff phase injects the same cast-timer custom buffs, so a converted bar behaves as an extra
-- buff-family bar (its key stays custom_*, never "buffs"). Same once-per-profile contract as
-- above. MUST run AFTER MigrateAlwaysShowBuffsToPerBar so the old global Always-Show value only lands on original buff bars, not converted Auras bars.
function ns.MigrateCustomBuffBarsToBuffBars()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or p.cdmBars._customBuffMergedV1 then return end
    p.cdmBars._customBuffMergedV1 = true
    if type(p.cdmBars.bars) ~= "table" then return end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.barType == "custom_buff" then
            bd.barType = "buffs"
        end
    end
end

-------------------------------------------------------------------------------
--  Hide / Restore Blizzard CDM
-------------------------------------------------------------------------------

-- Suppress the secondary buff-bar viewer (BuffBarCooldownViewer).
--
-- Parked offscreen, NEVER Hidden: TBB mirrors min/max/value straight off Blizzard's Bar frames
-- and a hidden viewer stops updating them. The park, not the alpha, is what holds -- Blizzard's
-- hide-when-inactive fade animates the viewer's alpha back to 1 whenever a tracked buff goes
-- active, through a path no hook can see (same lesson as the unclaimed-frame park in
-- CollectAndReanchor). So once anything re-anchors the viewer to its Edit Mode position (layout
-- apply, SaveLayouts, zone-in), the next buff proc in combat draws Blizzard's bars over ours. The SetPoint hook makes the park self-healing, mirroring the unclaimed CD/utility pool frames' hook.
function ns.ParkSecondaryBuffViewer(frame)
    if not frame then return end
    local fc = FC(frame)
    frame:SetAlpha(0)
    if InCombatLockdown() then
        -- Flushed on PLAYER_REGEN_ENABLED.
        ns._secondaryParkPending = true
    else
        ns._secondaryParkPending = nil
        fc.parkGuard = true
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
        fc.parkGuard = nil
    end
    if not fc.parkHooked then
        fc.parkHooked = true
        -- Deferred by a frame: Blizzard re-anchors this viewer inside its Edit Mode layout pass,
        -- which goes on to move protected systems (action bars); re-parking inline would carry
        -- our taint into the rest of that pass. The delay also coalesces ClearAllPoints + SetPoint bursts into one park, and a single frame of a stray bar is invisible.
        local function QueueRepark(self, method)
            local c = _ecmeFC[self]
            if not c or not c.hidden or c.parkGuard or c.restoring or c.parkQueued then return end
            c.parkQueued = true
            C_Timer.After(0, function()
                c.parkQueued = nil
                if c.hidden and not c.restoring then ns.ParkSecondaryBuffViewer(self) end
            end)
        end
        hooksecurefunc(frame, "SetPoint", function(self) QueueRepark(self, "SetPoint") end)
        -- SetPoint is not the only way off the park: SetAllPoints and SetParent strand the
        -- viewer on screen without ever calling it, and nothing heals that until an unrelated SetPoint happens to fire.
        hooksecurefunc(frame, "SetAllPoints", function(self) QueueRepark(self, "SetAllPoints") end)
        hooksecurefunc(frame, "SetParent", function(self) QueueRepark(self, "SetParent") end)
    end
end

-- Park integrity check, edge-driven via ns._parkEdges below.
--
-- The hooks above cover the movers we can see; a scale change, a mover that swaps anchors
-- through an unhooked path, or the one-frame gap the deferred re-park leaves open all put
-- Blizzard's bars back on screen. This closes the loop from the other end: read where the
-- viewer actually IS and re-park. Position ONLY -- alpha is deliberately not checked, since
-- Blizzard's hide-when-inactive fade animates it back to 1 through a path no hook sees and re-asserting would fight that animation while the frame is offscreen anyway.
function ns.CheckSecondaryBuffViewerPark()
    local frame = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
    if not frame then return end
    local fc = _ecmeFC[frame]
    if not fc or not fc.hidden or fc.restoring or fc.parkQueued then return end
    local pt, rel, relPt, x, y
    -- Indexing past the last point errors; an unanchored viewer counts as drifted and falls through to the re-park.
    if frame:GetNumPoints() > 0 then pt, rel, relPt, x, y = frame:GetPoint(1) end
    -- Tolerant compare: GetPoint round-trips through UI scale, so the stored -10000/10000 can
    -- read back with float drift, and a parent-anchored point can report its relative frame as
    -- nil. Exact equality fails every pass on scaled UIs, re-parking forever. Anywhere far offscreen top-left IS parked.
    if pt == "TOPLEFT" and (rel == UIParent or rel == nil) and relPt == "TOPLEFT"
       and x and x < -9990 and y and y > 9990 then
        return
    end
    -- In combat this re-asserts alpha 0 and defers the park itself; the frame is protected, so alpha is the only lever until PLAYER_REGEN_ENABLED.
    ns.ParkSecondaryBuffViewer(frame)
end

-- Park integrity for visibility-hidden cursor bars (edge-driven via ns._parkEdges below).
-- Their glue shells sleep while hidden, so a mover that strands one on-screen is healed here instead of by a per-frame OnUpdate. A parked bar costs two reads.
function ns._CheckCursorParks()
    for _, frame in pairs(cdmBarFrames) do
        if frame and frame._mouseTrack and frame._visHidden
           and (frame:GetLeft() or 0) > -9000 then
            frame._mouseParked = true
            frame:ClearAllPoints()
            frame:SetPoint(frame._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        end
    end
end

-- Edge-driven park integrity (NO polling patrols): hookable movers self-heal via the
-- QueueRepark hooksecurefuncs, LayoutCDMBar guards hidden cursor bars directly, and these are
-- the remaining un-hookable edges (scale changes and Edit Mode layout passes re-anchor Blizzard frames through paths no hook sees). A stale park beyond these is a missing edge to add here -- never a patrol.
ns._parkEdges = CreateFrame("Frame")
ns._parkEdges:RegisterEvent("UI_SCALE_CHANGED")
ns._parkEdges:RegisterEvent("DISPLAY_SIZE_CHANGED")
ns._parkEdges:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
ns._parkEdges:RegisterEvent("PLAYER_ENTERING_WORLD")
ns._parkEdges:SetScript("OnEvent", function()
    if ns.CheckSecondaryBuffViewerPark then ns.CheckSecondaryBuffViewerPark() end
    if ns._CheckCursorParks then ns._CheckCursorParks() end
end)

HideBlizzardCDM = function()
    -- Anchor each viewer to our corresponding bar container. Frames stay parented to viewers
    -- (no reparenting = no taint); the viewer becomes an invisible shell overlapping our
    -- container and CollectAndReanchor re-anchors individual icons within it. Viewer alpha stays at 1 so child frames inherit visibility.
    local viewerToBar = {
        [BLIZZ_CDM_FRAMES.cooldowns] = "cooldowns",
        [BLIZZ_CDM_FRAMES.utility]   = "utility",
        [BLIZZ_CDM_FRAMES.buffs]     = "buffs",
    }
    local allFrameNames = {}
    for _, fn in pairs(BLIZZ_CDM_FRAMES) do allFrameNames[#allFrameNames + 1] = fn end
    for _, fn in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do allFrameNames[#allFrameNames + 1] = fn end
    for _, frameName in ipairs(allFrameNames) do
        local frame = _G[frameName]
        if frame then
            local fc = FC(frame)
            if not fc.hidden then
                fc.origPoints = {}
                for i = 1, frame:GetNumPoints() do
                    fc.origPoints[i] = { frame:GetPoint(i) }
                end
                fc.hidden = true
            end
            -- NEVER reposition primary viewers (Essential/Utility/BuffIcon): individual icon
            -- anchoring handles that. The secondary BuffBarCooldownViewer gets alpha + offscreen park, since TBB renders its own bars and we don't hook its Cooldown widgets.
            local isSecondary = (frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs)
            if isSecondary then
                ns.ParkSecondaryBuffViewer(frame)
            end
            if not InCombatLockdown() then
                frame:EnableMouse(false)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
            end
        end
    end
end

RestoreBlizzardCDM = function()
    local allFrameNames = {}
    for _, fn in pairs(BLIZZ_CDM_FRAMES) do allFrameNames[#allFrameNames + 1] = fn end
    for _, fn in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do allFrameNames[#allFrameNames + 1] = fn end
    for _, frameName in ipairs(allFrameNames) do
        local frame = _G[frameName]
        local fc = frame and _ecmeFC[frame]
        if fc and fc.hidden then
            fc.restoring = true
            ns._secondaryParkPending = nil
            if fc.origPoints then
                frame:ClearAllPoints()
                for _, pt in ipairs(fc.origPoints) do
                    frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            -- The secondary viewer is the only alpha-suppressed one, and its Blizzard default is EnableMouse(false) -- restoring it true leaves an invisible click-catcher.
            if frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs then
                frame:SetAlpha(1)
            else
                frame:EnableMouse(true)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
            end
            fc.hidden = false
            fc.restoring = nil
        end
    end
end

-- Restore Blizzard's BuffBarCooldownViewer (bar-style buff tracking strip) when TBB is
-- disabled via "Use Blizzard CDM Bars". Touches ONLY the secondary bar viewer; CDM icon bars are never affected.
local function RestoreBlizzardBuffFrame()
    local frameName = BLIZZ_CDM_FRAMES_SECONDARY.buffs
    if not frameName then return end
    local frame = _G[frameName]
    local fc = frame and _ecmeFC[frame]
    if fc and fc.hidden then
        fc.restoring = true
        ns._secondaryParkPending = nil
        if fc.origPoints then
            frame:ClearAllPoints()
            for _, pt in ipairs(fc.origPoints) do
                frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        frame:SetAlpha(1)
        -- BuffBarCooldownViewer's default is EnableMouse(false); EnableMouse(true) would create an invisible click-catcher. Other viewers need mouse for tooltip hover.
        if frameName ~= "BuffBarCooldownViewer" then
            frame:EnableMouse(true)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
        end
        fc.hidden = false
        fc.restoring = nil
    end
end

I.BLIZZ_CDM_FRAMES, I.BLIZZ_CDM_FRAMES_SECONDARY = BLIZZ_CDM_FRAMES, BLIZZ_CDM_FRAMES_SECONDARY
I.CaptureCDMPositions, I.CDM_BAR_CATEGORIES = CaptureCDMPositions, CDM_BAR_CATEGORIES
I.EnforceCooldownViewerEditModeSettings = EnforceCooldownViewerEditModeSettings
I.GetCDMFont, I.HideBlizzardCDM = GetCDMFont, HideBlizzardCDM
I.MAX_CUSTOM_BARS, I.RestoreBlizzardBuffFrame = MAX_CUSTOM_BARS, RestoreBlizzardBuffFrame
I.RestoreBlizzardCDM, I.SetBlizzCDMFont = RestoreBlizzardCDM, SetBlizzCDMFont
I.broken = false
