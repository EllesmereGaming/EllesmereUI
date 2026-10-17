if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewRaid.lua
--
--  The raid preview: the overlay container, RefreshPreview, the mouse
--  blockers, ShowPreview, HidePreview and the preview mode.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local max          = math.max
local abs          = math.abs
local ipairs       = ipairs
local tostring     = tostring
local InCombatLockdown      = InCombatLockdown
local CreateFrame           = CreateFrame

local RF = ns._internals -- the table of the Raid Frames chain
local ApplyFont, LayoutGroups, MOVER_GROUPS = RF.ApplyFont, RF.LayoutGroups, RF.MOVER_GROUPS
local PixelSnap = RF.PixelSnap
local UpdateVisibility = ns.UpdateVisibility

local PvFrames, PvSettings, StartPvAuraTicker = I.PvFrames, I.PvSettings, I.StartPvAuraTicker
local StopPvAuraTicker, GetOrCreatePreviewFrame = I.StopPvAuraTicker, I.GetOrCreatePreviewFrame
local previewFrames, previewGroupLabels = I.previewFrames, I.previewGroupLabels
local BuildPreviewRoles, ApplyPreviewData = I.BuildPreviewRoles, I.ApplyPreviewData
local InitPreviewHealthValues = I.InitPreviewHealthValues
local previewHealthValues, previewPowerValues = I.previewHealthValues, I.previewPowerValues
local previewRoles, SetPreviewActive = I.previewRoles, I.SetPreviewActive
local SetPreviewContainer = I.SetPreviewContainer

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(v) containerFrame = v end
local previewActive = false
I.previewActiveSetters[#I.previewActiveSetters + 1] = function(v) previewActive = v end
local previewContainer
I.previewContainerSetters[#I.previewContainerSetters + 1] = function(v) previewContainer = v end

-------------------------------------------------------------------------------
--  Overlay preview container
--  A black-background frame that holds the preview when in overlay mode.
--  Position is hardcoded (see RefreshPreview) -- it is NOT draggable and
--  nothing is saved to the profile.
-------------------------------------------------------------------------------
local overlayContainer = nil

local function GetOrCreateOverlayContainer()
    if overlayContainer then return overlayContainer end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPreview so it tracks the active font.
    -- SetText is deferred until after ApplyFont there (a fontstring with no font
    -- set errors on SetText), matching how the group-number labels are built.
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    overlayContainer = oc
    ns._overlayContainer = oc
    return oc
end

local function RefreshPreview()
    if not previewActive then return end
    if not containerFrame then return end
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    BuildPreviewRoles()

    local s = ns._pvOverlayProxy or db.profile
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    -- The same self-heal the live layout runs, so the preview cannot render a
    -- grid where merged mode lays out a row (Blizzard's flat header has one
    -- column axis and cannot wrap into one).
    unitGrowth, groupGrowth = ns._RFEffectiveGrowth(unitGrowth, groupGrowth, s.mergeGroups)
    local bw = PixelSnap(s.frameWidth or 72)
    local bh = PixelSnap(s.frameHeight or 46)
    local cs = ns.RF_CellSpacing(s)
    local gs = ns.RF_GroupSpacing(s)

    -- Group bounding box
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Group slot origins along the growth flow (plain direction = one run,
    -- grid flow = ns._RF_GRID_ROWS per column), same helper the live layout
    -- places real groups through.
    local gSlots, minGX, maxGY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, 4)

    -- Unit step within a group
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then
        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then
        uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then
        uStepX = (bw + cs)
    else -- LEFT
        uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (0-indexed)
    local rawUX, rawUY = {}, {}
    local minUX, maxUY = 0, 0
    for i = 0, 4 do
        rawUX[i] = i * uStepX
        rawUY[i] = i * uStepY
        if rawUX[i] < minUX then minUX = rawUX[i] end
        if rawUY[i] > maxUY then maxUY = rawUY[i] end
    end

    -- Overlay mode: anchor to overlay container with padding
    local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
    local anchor = previewContainer or containerFrame
    local anchorPad = 0
    local topExtra = 0   -- extra top space (overlay only): 25px gap above the
                         -- group numbers, leaving room for the centered title
    if isOverlay then
        local oc = GetOrCreateOverlayContainer()
        anchor = oc
        anchorPad = 20
        topExtra = 25
    end

    -- Container size, through the SAME ns._RFFootprint the live container is
    -- sized with. The old one-row formula drew a 4x1 box around the grid flow's
    -- 2x2 block.
    local totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Pets (Show Pets on the Raid tab) go before the first or after the last group. The overlay
    -- grows to hold them; at the real position the groups stay put and the pets hang off them.
    local petSpec = ns.PF_PreviewSpec(false, s, bw, bh, cs, groupW, groupH)
    local petX, petY, padL, padT, padR, padB = 0, 0, 0, 0, 0, 0
    if petSpec then
        local slot = petSpec.before and 0 or (MOVER_GROUPS - 1)
        petX = gSlots[slot][1] - minGX + petSpec.ox
        petY = gSlots[slot][2] - maxGY + petSpec.oy
        if isOverlay then
            padL = max(0, -petX)
            padT = max(0, petY)
            padR = max(0, petX + petSpec.bw - totalW)
            padB = max(0, petSpec.bh - petY - totalH)
        end
    end

    -- Hide all preview frames first
    for _, f in ipairs(previewFrames) do f:Hide() end

    -- The 20-player preview keeps subgroup identities while moving each
    -- group's five frames to its visual slot.
    local groupOrder = s.customGroupOrder and not s.mergeGroups
        and ns._RFValidatedGroupOrder(s.groupOrder)
    local previewSlotByGroup
    if groupOrder then
        previewSlotByGroup = {}
        local previewSlot = 0
        for _, group in ipairs(groupOrder) do
            if group <= 4 then
                previewSlotByGroup[group] = previewSlot
                previewSlot = previewSlot + 1
            end
        end
    end

    -- Place 20 preview frames: 4 groups x 5 units
    local frameIdx = 0
    for g = 0, 3 do
        local displaySlot = previewSlotByGroup and previewSlotByGroup[g + 1] or g
        local gx = gSlots[displaySlot][1] - minGX
        local gy = gSlots[displaySlot][2] - maxGY
        local firstFrame   -- the group's u == 0 frame, the group-number anchor
        for u = 0, 4 do
            frameIdx = frameIdx + 1
            local f = GetOrCreatePreviewFrame(frameIdx)
            f:ClearAllPoints()
            local fx = gx + (rawUX[u] - minUX)
            local fy = gy + (rawUY[u] - maxUY)
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", fx + anchorPad + padL, fy - anchorPad - topExtra - padT)
            ApplyPreviewData(f, frameIdx)

            if f._health and previewHealthValues[frameIdx] then
                local barPct = ns.RF_IsInvertedFill(s) and (100 - previewHealthValues[frameIdx]) or previewHealthValues[frameIdx]
                f._health:SetValue(barPct)
                f._healthPct = previewHealthValues[frameIdx]
            end
            if f._power and previewPowerValues[frameIdx] then
                f._power:SetValue(previewPowerValues[frameIdx])
                f._powerPct = previewPowerValues[frameIdx]
            end
            if u == 0 then firstFrame = f end
        end

        -- Group number label anchored to the first unit of each group
        local lbl = previewGroupLabels[g + 1]
        if not lbl then
            lbl = anchor:CreateFontString(nil, "OVERLAY")
            previewGroupLabels[g + 1] = lbl
        end
        ApplyFont(lbl, s.groupNumberSize or 10)
        do
            -- Shared size/color with the real frames (group-number settings).
            -- Not gated by showGroupNumbers: the preview always shows numbers.
            local gc = s.groupNumberColor or {}
            lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
        end
        lbl:SetText(tostring(g + 1))
        lbl:ClearAllPoints()
        -- Anchor based on unit growth: label goes "before" the first unit.
        -- The X/Y offset (shared group-number setting) shifts it from there.
        local gnox = s.groupNumberOffsetX or 0
        local gnoy = s.groupNumberOffsetY or 0
        if unitGrowth == "DOWN" then
            lbl:SetPoint("BOTTOM", firstFrame, "TOP", gnox, 4 + gnoy)
        elseif unitGrowth == "UP" then
            lbl:SetPoint("TOP", firstFrame, "BOTTOM", gnox, -4 + gnoy)
        elseif unitGrowth == "RIGHT" then
            lbl:SetPoint("RIGHT", firstFrame, "LEFT", -3 + gnox, gnoy)
        else -- LEFT
            lbl:SetPoint("LEFT", firstFrame, "RIGHT", 3 + gnox, gnoy)
        end
        lbl:Show()
    end

    -- Reparent after all frames are created (first load creates them in the loop above)
    local reparentTo = isOverlay and overlayContainer or (previewContainer or containerFrame)
    for _, f in ipairs(previewFrames) do f:SetParent(reparentTo) end
    -- Group-number labels go on a high-level overlay child of the same container
    -- so they draw ABOVE the preview bars (which are descendants of reparentTo);
    -- parenting them straight to reparentTo leaves them beneath the bars.
    if not ns._previewGroupNumberOverlay then
        ns._previewGroupNumberOverlay = CreateFrame("Frame", nil, reparentTo)
    end
    ns._previewGroupNumberOverlay:SetParent(reparentTo)
    ns._previewGroupNumberOverlay:SetAllPoints(reparentTo)
    ns._previewGroupNumberOverlay:SetFrameLevel(9000)
    ns._previewGroupNumberOverlay:Show()
    for _, lbl in ipairs(previewGroupLabels) do lbl:SetParent(ns._previewGroupNumberOverlay) end
    if petSpec then
        ns.PF_ShowPreview(petSpec, s, reparentTo, anchor,
            petX + anchorPad + padL, petY - anchorPad - topExtra - padT)
    else
        ns.PF_HidePreview()
    end

    local snapW = PixelSnap(max(totalW, 1))
    local snapH = PixelSnap(max(totalH, 1))
    if previewContainer then
        previewContainer:SetSize(snapW, snapH)
        -- Re-anchor from the saved position on EVERY refresh (mirrors the real
        -- container and the size preview; preserving a stale TOPLEFT here left the
        -- real-mode preview stranded after a growth change until the panel reopened).
        -- Anchored at the base footprint's top-left so size changes grow down/right
        -- exactly like the real container's _ApplyTierOffset scheme.
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_RaidFrames")
        local bl, bt = ns._RFBaseTopLeft()
        previewContainer:ClearAllPoints()
        if se and se.point then
            -- Editing an override with a custom unlock mode: place the
            -- preview at the LAYER's recorded container position.
            previewContainer:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
        elseif bl then
            previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(bl), PixelSnap(bt))
        else
            previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        -- Snap TOPLEFT to pixel grid (same fix as containerFrame in LayoutGroups)
        local l = previewContainer:GetLeft()
        local t = previewContainer:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                previewContainer:ClearAllPoints()
                previewContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Size and position overlay container
    if isOverlay and overlayContainer then
        overlayContainer:SetSize(totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra)
        if overlayContainer._title then
            ApplyFont(overlayContainer._title, 13)
            overlayContainer._title:SetText("Overlay Preview")
            overlayContainer._title:SetTextColor(1, 1, 1, 0.9)
            overlayContainer._title:Show()
        end
        if ns._testMode then
            -- Test mode: center on screen, above dimmer
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(55)
            overlayContainer:ClearAllPoints()
            overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 80, 0)
        else
            overlayContainer:SetFrameStrata("FULLSCREEN_DIALOG")
            overlayContainer:SetFrameLevel(10)
            overlayContainer:ClearAllPoints()
            -- Hardcoded default position (not draggable, not saved): docked to
            -- the left edge of the options panel, screen center as a fallback.
            local sf = EllesmereUI._scrollFrame
            if sf then
                overlayContainer:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
            else
                overlayContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        overlayContainer:Show()
    end
    ns.RF_PreviewCompact(previewFrames, s, false, unitGrowth)
end

-- Mouse-blocking overlays + alpha-based real-frame hide for the options preview.
-- Wrapped in a do-block, exposed via ns, so these add NO persistent main-chunk
-- locals; rfMouseBlock/partyMouseBlock survive as closure upvalues.
--
-- The overlays are OUR OWN non-secure frames, so EnableMouse is taint-free and
-- Hide() is combat-legal (no secure children) -- torn down instantly at combat
-- start, so they can never trap a healer's clicks during a pull. They track the
-- real containers directly (alpha-0 but correctly sized/positioned), covering
-- the now-invisible real unit buttons in both preview and size preview.
--
-- Real containers hide via ALPHA, not reparenting: they stay parented to
-- UIParent at their saved position, so SetAlpha(1) restore is always legal and
-- can never be deferred by combat (reparenting secure-header containers back
-- is combat-blocked -- the old cause of "no party frames for the whole first
-- pull"). Preview frames reparent to previewContainer/overlayContainer/partyOC/
-- UIParent before display, so container alpha 0 never hides the preview itself.
do
    local rfMouseBlock, partyMouseBlock
    local function setBlock(on)
        if on then
            if containerFrame then
                if not rfMouseBlock then
                    rfMouseBlock = CreateFrame("Frame", nil, UIParent)
                    rfMouseBlock:EnableMouse(true)
                end
                rfMouseBlock:SetAllPoints(containerFrame)
                rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
                rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
                rfMouseBlock:Show()
            end
            if ns._partyContainerFrame then
                if not partyMouseBlock then
                    partyMouseBlock = CreateFrame("Frame", nil, UIParent)
                    partyMouseBlock:EnableMouse(true)
                end
                partyMouseBlock:SetAllPoints(ns._partyContainerFrame)
                partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
                partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
                partyMouseBlock:Show()
            end
        else
            if rfMouseBlock then rfMouseBlock:Hide() end
            if partyMouseBlock then partyMouseBlock:Hide() end
        end
        -- The pet frames' own (their header, and the pets beside the party frames), and the
        -- party target frames' (outside the party container too).
        ns._PF_SetPreviewBlock(on)
        ns._PT_SetPreviewBlock(on)
    end
    ns._SetPreviewMouseBlock = setBlock
    ns._RefreshPreviewMouseBlockStrata = function()
        if rfMouseBlock and rfMouseBlock:IsShown() and containerFrame then
            rfMouseBlock:SetFrameStrata(containerFrame:GetFrameStrata())
            rfMouseBlock:SetFrameLevel(containerFrame:GetFrameLevel() + 50)
        end
        if partyMouseBlock and partyMouseBlock:IsShown() and ns._partyContainerFrame then
            partyMouseBlock:SetFrameStrata(ns._partyContainerFrame:GetFrameStrata())
            partyMouseBlock:SetFrameLevel(ns._partyContainerFrame:GetFrameLevel() + 50)
        end
        ns._PF_RefreshPreviewBlock()
        ns._PT_RefreshPreviewBlock()
    end
    function ns._SetRealFramesPreviewHidden(on)
        -- Overlay preview is a separate docked panel, so the real frames are NOT
        -- under it: leave them faintly visible (alpha 0.2) and DON'T mouse-block
        -- them. Real preview replaces the frames in place, so keep the original
        -- behavior there: hide fully (alpha 0) + block clicks.
        local isOverlay = (db.profile.previewMode == "overlay") or ns._testMode
        if isOverlay then
            local a = on and 0.2 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            if ns._ptModelOn then ns.RF_PtContainerAlpha(a) end
            if ns._PF.container then ns._PF.container:SetAlpha(a) end
            setBlock(false)
        else
            local a = on and 0 or 1
            if containerFrame then containerFrame:SetAlpha(a) end
            if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(a) end
            if ns._ptModelOn then ns.RF_PtContainerAlpha(a) end
            if ns._PF.container then ns._PF.container:SetAlpha(a) end
            setBlock(on)
        end
        -- The pets beside the party frames take the container's alpha through their own.
        ns._PF_AlphaSync()
    end
end

local function ShowPreview()
    -- Never engage the preview unless the options window is actually open (or test mode
    -- is active). A deferred C_Timer ShowPreview firing after the panel closed (combat
    -- auto-close, rapid close) would reparent the real containers under the hidden
    -- preview parent with nothing left to restore them -- the root cause of "frames
    -- vanish after closing options". Reparenting secure-header containers is also
    -- blocked/taint-prone in combat, so bail there too.
    if not ns._testMode and not (EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if previewActive then
        RefreshPreview()
        return
    end
    if not containerFrame then return end
    SetPreviewActive(true)

    -- Preview container
    if not previewContainer then
        SetPreviewContainer(CreateFrame("Frame", nil, UIParent))
        previewContainer:SetFrameStrata("HIGH")
    end
    local pos = db.profile.unlockPos
    previewContainer:ClearAllPoints()
    if pos then
        previewContainer:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        previewContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    previewContainer:SetSize(containerFrame:GetSize())
    previewContainer:Show()

    -- Hide the real containers for preview via alpha (combat-reversible) instead
    -- of reparenting. SetAlpha is not protected, so the restore can never be
    -- blocked or deferred by combat. The containers stay parented to UIParent at
    -- their saved position; preview frames are reparented out of the containers
    -- by RefreshPreview below, so container alpha 0 does not hide the preview.
    ns._SetRealFramesPreviewHidden(true)

    -- Initialize health values and role assignments
    InitPreviewHealthValues()
    BuildPreviewRoles()

    RefreshPreview()
    StartPvAuraTicker()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on tab swaps into the party tab, where ShowPartyPreview
-- re-hides them on the next frame -- restoring here would flash the real frames
-- for one frame first. Panel close restores explicitly.
local function HidePreview(skipRestore)
    if not previewActive then return end
    ns.RF_PreviewCompact(nil, nil, false)
    SetPreviewActive(false)
    ns._previewInitialized = false
    previewRoles._randomized = nil  -- re-randomize on next preview open
    previewRoles._hpalPick = nil    -- re-roll the hpal Legends next open
    StopPvAuraTicker()
    ns.StopPvBuffTicker()
    -- Hide overlay container
    if overlayContainer then overlayContainer:Hide() end
    -- Hide preview container
    if previewContainer then previewContainer:Hide() end
    -- Reparent preview frames back to containerFrame
    for _, f in ipairs(previewFrames) do
        f:SetParent(containerFrame)
        f:Hide()
    end
    for _, lbl in ipairs(previewGroupLabels) do
        lbl:SetParent(containerFrame)
        lbl:Hide()
    end
    ns.PF_HidePreview()
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved), so the
    -- restore is a combat-legal SetAlpha(1) plus dropping the mouse blockers. No
    -- combat gate, no SetParent/SetPoint, no ns._restorePending deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- Re-run layout out of combat in case frame sizes changed while previewing
    -- (LayoutGroups SetPoints secure headers, so out of combat only).
    if not InCombatLockdown() then LayoutGroups() end
    -- Re-derive the growth-corner anchor after the relayout (self-gates on
    -- combat) so a size change made while previewing can never strand the
    -- container at a stale position.
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

local function ApplyPreviewMode()
    local mode = db.profile.previewMode or "overlay"

    if mode == "none" then
        if previewActive then HidePreview() end
        return
    end
    if not previewActive then
        ShowPreview()
        return
    end
    local isOverlay = (mode == "overlay")
    if not isOverlay and overlayContainer then
        overlayContainer:Hide()
    end
    -- Re-apply the real-frame hide state for the (possibly just-changed) mode so a
    -- live Real<->Overlay switch updates alpha + mouse-block: overlay shows the
    -- real frames faintly with NO block; real hides them fully + blocks.
    ns._SetRealFramesPreviewHidden(true)
    -- RefreshPreview handles reparenting, anchoring, and overlay sizing
    RefreshPreview()
end

ns.ApplyPreviewMode = ApplyPreviewMode

-- Expose for options panel
ns.ShowPreview = ShowPreview
ns.HidePreview = HidePreview
ns.previewActive = function() return previewActive end
ns.ResetPreviewRandomization = function()
    previewRoles._randomized = nil
    previewRoles._hpalPick = nil
end
ns.previewFrames = previewFrames
ns.previewHealthValues = previewHealthValues
ns.previewPowerValues = previewPowerValues

-- Party-aware sibling of PvEffectiveProfile, for the shared options tickers:
-- party preview reads party-prefixed settings, raid preview reads the live
-- profile through the real-preview effective overlay.
ns.PvSettings = PvSettings

-- Active-preview accessors for the options eyeballs (resolve raid vs party at
-- call time so the health/power animations drive whichever preview is on screen).
ns.PvActiveFrames = PvFrames
ns.PvHealthValues = function() return (ns._partyPvActive and ns._partyPvHV) or previewHealthValues end
ns.PvPowerValues  = function() return (ns._partyPvActive and ns._partyPvPV) or previewPowerValues end
-- Re-render whichever preview is active (mirrors ShowPreview's refresh-if-active).
-- Uses the ns.* exports because ShowPartyPreview lives in EUI_RaidFrames_PreviewParty.lua.
ns.PvRefresh = function()
    if ns._partyPvActive then
        if ns.ShowPartyPreview then ns.ShowPartyPreview() end
    elseif ns.ShowPreview then
        ns.ShowPreview()
    end
end

I.HidePreview = HidePreview
I.broken = false
