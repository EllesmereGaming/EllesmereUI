if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewSize.lua
--
--  The size preview: health and power bars at a raid-size tier's
--  dimensions.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local max          = math.max
local ipairs       = ipairs
local tostring     = tostring
local InCombatLockdown      = InCombatLockdown
local CreateFrame           = CreateFrame

local RF = ns._internals -- the table of the Raid Frames chain
local MOVER_GROUPS, PixelSnap = RF.MOVER_GROUPS, RF.PixelSnap

local HidePreview = I.HidePreview

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local PP
RF.PPSetters[#RF.PPSetters + 1] = function(v) PP = v end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(v) containerFrame = v end
local previewActive = false
I.previewActiveSetters[#I.previewActiveSetters + 1] = function(v) previewActive = v end

-------------------------------------------------------------------------------
--  Size preview (simple: just health + power bars at the tier's dimensions)
--  Shows the correct number of frames for the tier (10/15/25/30/40).
--  Always screen-anchored exactly where the live frames land (shared
--  growth-corner origin ns._RFTierTopLeft), regardless of preview mode.
--  No indicators, no randomization.
-------------------------------------------------------------------------------
ns._sizePreviewTier = nil
ns._sizePreviewFrames = {}
ns._sizePreviewContainer = nil

ns._ShowSizePreview = function(tier)
    -- Preview only ever runs out of combat. A mid-combat alpha-0 here could not
    -- be undone by the PLAYER_REGEN_DISABLED safety net (it already fired at
    -- combat start), and would strand the real frames invisible for the rest of
    -- the pull -- the same game-breaking outcome the alpha rework prevents.
    if InCombatLockdown() then return end
    local s = db.profile
    local overrides = s.raidSizeOverrides
    if not overrides or not overrides[tier] then return end

    -- Hide any active previews (both real and overlay mode)
    if previewActive then
        HidePreview()  -- cleans up real-mode preview frames
    end
    if ns._partyPvActive then
        ns.HidePartyPreview()
    end
    -- Hide real raid + party frames during size preview via alpha so a combat
    -- start can re-show them (Hide/Show are protected and cannot be undone in
    -- combat; SetAlpha is not). The size-preview frames live in their own
    -- UIParent child (ns._sizePreviewContainer), so container alpha does not
    -- affect them. The mouse blocker keeps the now-invisible real unit buttons
    -- from catching clicks while configuring out of combat.
    if containerFrame then containerFrame:SetAlpha(0) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(0) end
    if ns._ptModelOn then ns.RF_PtContainerAlpha(0) end
    if ns._PF.container then ns._PF.container:SetAlpha(0) end
    ns._PF_AlphaSync()
    ns._SetPreviewMouseBlock(true)

    local ov = overrides[tier]
    local bw = PixelSnap(ov.width or s.frameWidth or 125)
    local bh = PixelSnap(ov.height or s.frameHeight or 60)
    local cs = ns.RF_CellSpacing(s)
    local gs = ns.RF_GroupSpacing(s)
    local unitGrowth, groupGrowth = ns._RFEffectiveGrowth(
        ov.unitGrowth or s.unitGrowth or "DOWN", ov.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
    local frameCount  = tier
    local perGroup    = 5
    local numGroups   = math.ceil(frameCount / perGroup)

    -- Group bounding box (same logic as LayoutGroups)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = perGroup * bw + (perGroup - 1) * cs
        groupH = bh
    else
        groupW = bw
        groupH = perGroup * bh + (perGroup - 1) * cs
    end

    -- Unit step within a group along unitGrowth axis
    local uStepX, uStepY = 0, 0
    if unitGrowth == "DOWN" then        uStepY = -(bh + cs)
    elseif unitGrowth == "UP" then      uStepY = (bh + cs)
    elseif unitGrowth == "RIGHT" then   uStepX = (bw + cs)
    else                                uStepX = -(bw + cs)
    end

    -- Normalize unit positions within a group (matches RefreshPreview pattern)
    local minUX, maxUY = 0, 0
    for u = 0, perGroup - 1 do
        local px = u * uStepX
        local py = u * uStepY
        if px < minUX then minUX = px end
        if py > maxUY then maxUY = py end
    end

    -- Total bounding box: the tier's group mover footprint via the SAME
    -- ns._RFFootprint the live container sizing and the corner origin use (one
    -- formula, so preview and live can never drift).
    local totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)

    -- Tier offset
    local tierOX = ov.offsetX or 0
    local tierOY = ov.offsetY or 0

    -- Create or reuse container
    local container = ns._sizePreviewContainer
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container:SetFrameStrata("FULLSCREEN_DIALOG")
        container:SetFrameLevel(10)
        -- Never clamp: the preview must land exactly where the live
        -- container lands, including partially off-screen positions.
        container:SetClampedToScreen(false)
        ns._sizePreviewContainer = container
    end

    -- Always use real positioning (where frames actually sit)
    local pad = 0
    container:SetSize(totalW, totalH)
    if container._bg then container._bg:Hide() end
    container:SetFrameStrata("HIGH")
    container:ClearAllPoints()
    -- Same growth-corner origin as the live container (_ApplyTierOffset):
    -- the tier footprint's growth-derived corner pins at the base
    -- footprint's same corner plus the tier offset, via the shared
    -- ns._RFTierTopLeft -- the preview lands exactly where live lands.
    local px, py = ns._RFTierTopLeft(totalW, totalH, unitGrowth, groupGrowth, tierOX, tierOY)
    if px then
        container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(px), PixelSnap(py))
    else
        container:SetPoint("CENTER", UIParent, "CENTER", tierOX, tierOY)
    end

    -- Font for the unit-number label
    local fontPath = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local nameSize = s.nameSize or 10

    -- Group slot origins along the growth flow, normalized over MOVER_GROUPS
    -- (matching the real LayoutGroups container). At least MOVER_GROUPS slots
    -- are generated even when the tier shows fewer groups: the normalization
    -- origin is what puts slot 0 at the growth corner, so normalizing over a
    -- 2- or 3-group prefix would place the preview on the wrong side of the
    -- box for LEFT/UP growth. The extra slots are simply not drawn.
    local gSlots, minX, maxY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, max(numGroups, MOVER_GROUPS))

    local groupOrder = s.customGroupOrder and not s.mergeGroups
        and ns._RFValidatedGroupOrder(s.groupOrder)
    local sizePreviewSlotByGroup
    if groupOrder then
        sizePreviewSlotByGroup = {}
        local sizePreviewSlot = 0
        for _, group in ipairs(groupOrder) do
            if group <= numGroups then
                sizePreviewSlotByGroup[group] = sizePreviewSlot
                sizePreviewSlot = sizePreviewSlot + 1
            end
        end
    end

    for i = 1, frameCount do
        local f = ns._sizePreviewFrames[i]
        if not f then
            f = CreateFrame("Frame", nil, container)
            local health = CreateFrame("StatusBar", nil, f)
            health:SetPoint("TOPLEFT")
            health:SetPoint("TOPRIGHT")
            health:SetMinMaxValues(0, 100)
            health:SetValue(100)
            -- Pre-paint tint (see StyleButton's health bar note).
            health:SetStatusBarColor(0.12, 0.12, 0.12)
            if PP then PP.DisablePixelSnap(health) end
            f._health = health

            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if PP then PP.DisablePixelSnap(bg) end
            f._bg = bg

            local power = CreateFrame("StatusBar", nil, f)
            power:SetPoint("BOTTOMLEFT")
            power:SetPoint("BOTTOMRIGHT")
            power:SetMinMaxValues(0, 1)
            power:SetValue(1)
            if PP then PP.DisablePixelSnap(power) end
            f._power = power

            local bdr = CreateFrame("Frame", nil, f)
            bdr:SetAllPoints()
            bdr:SetFrameLevel(f:GetFrameLevel() + 2)
            if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end
            f._border = bdr

            -- Name text
            local nameFS = health:CreateFontString(nil, "OVERLAY")
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            f._nameText = nameFS

            -- Top Name Bar
            local tnb = CreateFrame("Frame", nil, f)
            tnb:SetFrameLevel(f:GetFrameLevel() + 4)
            tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
            tnbBg:SetAllPoints()
            if PP then PP.DisablePixelSnap(tnbBg) end
            local tnbText = tnb:CreateFontString(nil, "OVERLAY")
            tnbText:SetWordWrap(false)
            tnb:Hide()
            f._topNameBar = tnb
            f._topNameBarBg = tnbBg
            f._topNameBarText = tnbText

            -- Role icon
            local roleIcon = health:CreateTexture(nil, "OVERLAY")
            roleIcon:Hide()
            f._roleIcon = roleIcon

            ns._sizePreviewFrames[i] = f
        end

        f:SetParent(container)
        f:SetSize(bw, bh)
        -- GENERIC SIZING PLACEHOLDER (NOT a style preview):
        -- The custom raid-size previews (10/15/25/30) deliberately do NOT mimic the
        -- user's real raid-frame style. They render as plain blocks that only show
        -- each frame's footprint at the chosen width/height/spacing, so the size
        -- preview can never be mistaken for a live style preview when it does not
        -- match the user's customized frames. No class colors, textures, power bars,
        -- names, role icons or custom border -- just a flat fill, a thin neutral
        -- outline and the unit number.
        f._health:ClearAllPoints()
        f._health:SetAllPoints(f)
        f._health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        if f._health:GetStatusBarTexture() then f._health:GetStatusBarTexture():SetHorizTile(false) end
        f._health:SetStatusBarColor(0.24, 0.26, 0.30, 1)
        f._health:SetValue(100)
        f._bg:SetColorTexture(0.09, 0.09, 0.11, 1)
        if f._power then f._power:Hide() end
        if f._topNameBar then f._topNameBar:Hide() end
        if f._roleIcon then
            f._roleIcon:Hide()
            if f._roleIcon._roleText then f._roleIcon._roleText:Hide() end
        end

        -- Thin neutral outline so each block and the spacing between them reads clearly.
        if f._border and PP then
            f._border:SetFrameLevel(f:GetFrameLevel() + 2)
            EllesmereUI.ApplyBorderStyle(f._border, 1, 0.7, 0.7, 0.75, 0.8,
                "solid", nil, nil, nil, nil, "unitframes", 1)
        end

        -- Centered unit number.
        if f._nameText then
            EllesmereUI.ApplyModuleFont(f._nameText, fontPath, math.max(11, nameSize), "raidFrames")
            f._nameText:SetText(tostring(i))
            f._nameText:SetTextColor(0.9, 0.9, 0.9)
            f._nameText:SetWidth(bw)
            f._nameText:ClearAllPoints()
            f._nameText:SetPoint("CENTER", f._health, "CENTER", 0, 0)
            f._nameText:Show()
        end

        -- Position: group index + unit index within group
        local groupIdx = math.ceil(i / perGroup) - 1
        local unitIdx  = (i - 1) % perGroup

        -- Group origin (TOPLEFT-relative, adjusted for growth direction)
        local displaySlot = sizePreviewSlotByGroup and sizePreviewSlotByGroup[groupIdx + 1] or groupIdx
        local gx = gSlots[displaySlot][1] - minX
        local gy = gSlots[displaySlot][2] - maxY

        -- Unit offset within group (TOPLEFT-normalized, matching RefreshPreview)
        local ux = unitIdx * uStepX - minUX
        local uy = unitIdx * uStepY - maxUY

        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", container, "TOPLEFT", pad + gx + ux, -pad + gy + uy)
        f:Show()
    end

    -- Hide excess frames
    for i = frameCount + 1, #ns._sizePreviewFrames do
        ns._sizePreviewFrames[i]:Hide()
    end

    container:Show()
end

ns._HideSizePreview = function()
    if ns._sizePreviewContainer then
        ns._sizePreviewContainer:Hide()
    end
    for _, f in ipairs(ns._sizePreviewFrames) do
        f:Hide()
    end
    -- Restore real frame opacity (size preview only changed alpha, never the
    -- Shown state) and drop the mouse blocker. SetAlpha(1) is always legal, in
    -- or out of combat, so the frames can never be stranded invisible.
    if containerFrame then containerFrame:SetAlpha(1) end
    if ns._partyContainerFrame then ns._partyContainerFrame:SetAlpha(1) end
    if ns._ptModelOn then ns.RF_PtContainerAlpha(1) end
    if ns._PF.container then ns._PF.container:SetAlpha(1) end
    ns._PF_AlphaSync()
    ns._SetPreviewMouseBlock(false)
    -- Recompute party visibility (only shows party frames if actually grouped /
    -- Show When Solo). Bails in combat; the alpha restore above suffices there.
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

I.broken = false
