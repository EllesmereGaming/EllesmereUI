if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewFrame.lua
--
--  The standalone preview frames: CreatePreviewFrame and its container
--  state.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs       = ipairs
local CreateFrame           = CreateFrame

local RF = ns._internals -- the table of the Raid Frames chain
local ApplyFont, defaults, IsPowerBarEnabled = RF.ApplyFont, RF.defaults, RF.IsPowerBarEnabled
local PixelSnap, ResolveHealthTexture = RF.PixelSnap, RF.ResolveHealthTexture

local previewFrames, PvActive, PvFrames = I.previewFrames, I.PvActive, I.PvFrames

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local PP
RF.PPSetters[#RF.PPSetters + 1] = function(v) PP = v end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(v) containerFrame = v end

-- Preview frames: standalone frames NOT managed by SecureGroupHeaderTemplate.
-- Header-managed buttons can't be shown without real units, so we create
-- our own lightweight frames that look identical for the options preview.
local previewGroupLabels = {}  -- [1..4] FontStrings showing group numbers
local previewContainer = nil   -- standalone anchor frame for preview (doesn't move with containerFrame)
I.previewContainerSetters[#I.previewContainerSetters + 1] = function(v) previewContainer = v end

local function CreatePreviewFrame(index, party)
    local s = db.profile
    local w = PixelSnap(s.frameWidth or 72)
    local h = PixelSnap(s.frameHeight or 46)
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    -- Party Frames kit (party preview only): the stock frame's own layout.
    local kit = party and ns.RF_PartyKit()
    local healthH = PixelSnap(h - ns.RF_HealthPowerInset(s, powerH))

    local f = CreateFrame("Frame", nil, previewContainer or containerFrame)
    f:SetSize(w, h)
    f:SetFrameStrata("HIGH")
    f:Hide()

    -- Background
    local bgc = s.customBgColor or defaults.customBgColor
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, (s.bgDarkness or 50) / 100)
    if PP then PP.DisablePixelSnap(bg) end

    -- Health bar
    local health = CreateFrame("StatusBar", nil, f)
    health:SetFrameLevel(f:GetFrameLevel() + 2)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    health:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    health:SetHeight(healthH)
    health:SetStatusBarTexture(ResolveHealthTexture())
    health:GetStatusBarTexture():SetHorizTile(false)
    if PP then PP.DisablePixelSnap(health) end
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)

    -- Full-height anchor reference (mirrors the live buttons' d.uniformRef so
    -- Uniform Icon Anchoring previews identically; see ns.RF_AnchorHost).
    f._uniformRef = CreateFrame("Frame", nil, f)
    f._uniformRef:SetFrameLevel(health:GetFrameLevel())
    f._uniformRef:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    f._uniformRef:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    health._euiUniformRef = f._uniformRef
    f._uniformRef._euiHealth = health

    -- Absorb shield preview (dual clip-frame, matching real frames)
    -- Mask: constrains absorb rendering to health bar bounds
    local absorbMask = health:CreateMaskTexture()
    absorbMask:SetAllPoints(health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Current HP clip: bounds the backfill bar to the filled health area
    local curClip = CreateFrame("Frame", nil, health)
    curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    curClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area
    local missClip = CreateFrame("Frame", nil, health)
    missClip:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    missClip:SetClipsChildren(true)

    -- Backfill bar: grows into filled health from the right (overshield)
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    -- Modern compound absorb base (preview): mirrors the live frame's solid c6c8ff
    -- base drawn under the striped fill. Anchored to the fill at render time.
    local bfBase = backfillBar:CreateTexture(nil, "ARTWORK", nil, 0)
    bfBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then bfBase:AddMaskTexture(absorbMask) end
    bfBase:Hide()
    backfillBar._modernBase = bfBase
    backfillBar:SetStatusBarColor(1, 1, 1, 0.3)
    backfillBar:SetReverseFill(true)
    backfillBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    backfillBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    backfillBar:SetWidth(health:GetWidth())
    backfillBar:SetHeight(health:GetHeight())
    -- Absorb on top of the HP cluster (above heal absorb/heal pred and max health).
    backfillBar:SetFrameLevel(health:GetFrameLevel() + 3)
    backfillBar:SetMinMaxValues(0, 100)
    backfillBar:Hide()

    -- Forward bar: grows into missing health from the HP edge
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    -- Modern compound absorb base (preview) for the forward bar.
    local fwBase = forwardBar:CreateTexture(nil, "ARTWORK", nil, 0)
    fwBase:SetColorTexture(0.776, 0.784, 1.0, 1)
    if absorbMask then fwBase:AddMaskTexture(absorbMask) end
    fwBase:Hide()
    forwardBar._modernBase = fwBase
    forwardBar:SetStatusBarColor(1, 1, 1, 0.3)
    forwardBar:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    forwardBar:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    forwardBar:SetWidth(health:GetWidth())
    forwardBar:SetHeight(health:GetHeight())
    -- Match backfill: absorb above heal absorb/heal pred and max health.
    forwardBar:SetFrameLevel(health:GetFrameLevel() + 3)
    forwardBar:SetMinMaxValues(0, 100)
    forwardBar:Hide()

    -- "Default Blizz Frames" spark (preview): mirrors live -- a fixed 16px cast_spark
    -- glow on a non-clipping host above the shield, CENTER pinned to the forward bar's
    -- LEFT edge (the seam). Gated by the preview's plain absorb compare in the renderer.
    local sparkHost = CreateFrame("Frame", nil, health)
    sparkHost:SetAllPoints(health)
    sparkHost:SetClipsChildren(true)
    sparkHost:SetFrameLevel(health:GetFrameLevel() + 4)
    local gateBar = CreateFrame("StatusBar", nil, sparkHost)
    gateBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gateBar:SetStatusBarColor(1, 1, 1, 0)
    gateBar:SetSize(16, health:GetHeight())
    gateBar:SetMinMaxValues(0, 1)
    gateBar:SetValue(0)
    gateBar:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    local edgeSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    edgeSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    edgeSpark:SetBlendMode("ADD")
    edgeSpark:SetAllPoints(gateBar:GetStatusBarTexture())
    edgeSpark:Hide()
    forwardBar._edgeSpark = edgeSpark
    forwardBar._edgeGate = gateBar
    -- Overshield spark (preview): rides the backfill's left edge while overshielding.
    local bfSpark = sparkHost:CreateTexture(nil, "OVERLAY")
    bfSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    bfSpark:SetBlendMode("ADD")
    bfSpark:SetSize(16, health:GetHeight())
    bfSpark:SetPoint("CENTER", forwardBar, "LEFT", -1, 0)
    bfSpark:Hide()
    forwardBar._bfSpark = bfSpark

    -- Heal absorb bar (preview): red overlay eating into filled health from HP edge
    do
        -- Own clip frame (mirrors live): right/left span the full bar, overlay
        -- clips to filled health. Bounds set per healAbsorbEdgeMode in render.
        local healClip = CreateFrame("Frame", nil, health)
        healClip:SetClipsChildren(true)
        healClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        f._healClip = healClip
        local ha = CreateFrame("StatusBar", nil, healClip)
        ha:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = ha:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        ha:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
        ha:SetReverseFill(true)
        ha:SetPoint("TOPRIGHT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        ha:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        ha:SetWidth(health:GetWidth())
        ha:SetHeight(health:GetHeight())
        ha:SetFrameLevel(health:GetFrameLevel() + 1)
        ha:SetMinMaxValues(0, 100)
        ha._mask = absorbMask
        -- Black backing behind the heal-absorb texture (preview; mirrors live).
        local haBg = ha:CreateTexture(nil, "ARTWORK", nil, 1)
        haBg:SetColorTexture(0, 0, 0, 0.25)
        if absorbMask then haBg:AddMaskTexture(absorbMask) end
        haBg:Hide()
        ha._bg = haBg
        ha:Hide()
        f._healAbsorbBar = ha
    end

    -- Heal prediction bar (preview): extends from HP edge into missing health
    do
        local hp = CreateFrame("StatusBar", nil, missClip)
        hp:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local hf = hp:GetStatusBarTexture()
        if hf then hf:SetDrawLayer("ARTWORK", 2); hf:AddMaskTexture(absorbMask) end
        hp:SetStatusBarColor(0.3, 0.8, 0.3, 0.4)
        hp:SetReverseFill(false)
        hp:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        hp:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        hp:SetWidth(health:GetWidth())
        hp:SetHeight(health:GetHeight())
        hp:SetFrameLevel(health:GetFrameLevel() + 1)
        hp:SetMinMaxValues(0, 100)
        hp:Hide()
        f._healPredBar = hp
    end

    -- Reduced max health bar (preview): black bg + red striped overlay on right side
    do
        local rmh = CreateFrame("StatusBar", nil, health)
        rmh:SetStatusBarTexture("Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png")
        local rmhFill = rmh:GetStatusBarTexture()
        if rmhFill then
            rmhFill:SetDrawLayer("ARTWORK", 3)
            rmhFill:SetHorizTile(true); rmhFill:SetVertTile(true)
        end
        rmh:SetStatusBarColor(0.7, 0.1, 0.1, 1)
        rmh:SetReverseFill(true)
        rmh:SetAllPoints(health)
        rmh:SetFrameLevel(health:GetFrameLevel() + 2)
        rmh:SetMinMaxValues(0, 1)
        rmh:Hide()
        -- Black background behind the stripes
        local rmhBg = rmh:CreateTexture(nil, "ARTWORK", nil, 2)
        rmhBg:SetAllPoints(rmhFill)
        rmhBg:SetColorTexture(0, 0, 0, 1)
        f._reducedMaxHealthBar = rmh
        f._reducedMaxHealthBg = rmhBg
    end

    -- Store absorb references on preview frame
    local absorbBar = backfillBar
    absorbBar._forward = forwardBar
    absorbBar._mask = absorbMask
    absorbBar._curClip = curClip
    absorbBar._missClip = missClip

    -- Absorb Bar (preview): solid bar above the frame, fills from the right
    do
        local tb = CreateFrame("StatusBar", nil, f)
        tb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        tb:SetStatusBarColor(1, 1, 1, 1)
        tb:SetReverseFill(true)
        tb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        tb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        tb:SetHeight(4)
        tb:SetFrameLevel(health:GetFrameLevel() + 3)
        tb:SetMinMaxValues(0, 100)
        tb:Hide()
        absorbBar._topBar = tb
    end

    -- Heal Absorb Bar (preview): mirrors the Absorb Bar strip above.
    do
        local thb = CreateFrame("StatusBar", nil, f)
        thb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        thb:SetStatusBarColor(200/255, 29/255, 29/255, 1)
        thb:SetReverseFill(true)
        thb:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0)
        thb:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 0)
        thb:SetHeight(4)
        thb:SetFrameLevel(health:GetFrameLevel() + 3)
        thb:SetMinMaxValues(0, 100)
        thb:Hide()
        absorbBar._healTopBar = thb
    end

    -- Power bar (anchored to frame bottom for pixel alignment). Always built:
    -- frames are reused for the session and the party preview reads its own
    -- role flags, so ApplyPreviewData shows or hides it per unit.
    local power
    do
        power = CreateFrame("StatusBar", nil, f)
        power:SetFrameLevel(f:GetFrameLevel() + 3)
        power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        power:SetHeight(powerH)
        power:SetStatusBarTexture(ResolveHealthTexture())
        power:GetStatusBarTexture():SetHorizTile(false)
        if PP then PP.DisablePixelSnap(power) end
        power:SetMinMaxValues(0, 100)
        power:SetValue(100)
        local pwBg = power:CreateTexture(nil, "BACKGROUND")
        pwBg:SetAllPoints()
        pwBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
        if PP then PP.DisablePixelSnap(pwBg) end
        f._powerBg = pwBg

        -- Power border
        local pwBdr = CreateFrame("Frame", nil, f)
        pwBdr:SetAllPoints(power)
        pwBdr:SetFrameLevel(power:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(pwBdr, 0, 0, 0, 1, 1) end
        f._powerBorder = pwBdr
    end

    -- Border (single border styled via ApplyBorderStyle in ApplyPreviewData,
    -- recolored by state -- mirrors the real frames)
    local bdrFrame = CreateFrame("Frame", nil, f)
    bdrFrame:SetAllPoints(f)
    bdrFrame:SetFrameLevel(f:GetFrameLevel() + 8)

    local function PvApplyBorderColor()
        if not PP then return end
        -- Overlay ahead of _scaledProfile: border/hover/target keys are not
        -- tier-scaled, so the effective overlay may shadow them safely.
        local s = ns._previewSettingsOverride or (ns._partyPvActive and ns._scaledPartyProxy)
            or ns._pvOverlayProxy or ns._scaledProfile
        if ns.RF_ButtonCompact(f, s) then
            ns.RF_CompactHighlight(bdrFrame, f, s, f)
            return
        end
        if f.kit then
            ns.RF_KitHighlight(f, bdrFrame, s, f._hovered and s.hoverBorderEnabled ~= false,
                f._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        if f.stockEdge then
            local hover = f._hovered and s.hoverBorderEnabled ~= false
            local lvl = f:GetFrameLevel() + (hover and ns.LVL_RAISE or 8)
            if bdrFrame:GetFrameLevel() ~= lvl then
                bdrFrame:SetFrameLevel(lvl)
                local container = PP.GetBorders(bdrFrame)
                if container then container:SetFrameLevel(lvl + 1) end
            end
            ns.RF_StockHighlight(f, bdrFrame, s, hover, f._isTarget and s.targetBorderEnabled ~= false)
            return
        end
        local r, g, b, a
        local raised, hlSize, hlPx = false, nil, nil
        if f._pvDispelBdrC and s.borderBehind then
            -- Show Behind: the live copy sits over the never-raised base border, so the
            -- type color covers hover/target there too.
            local c = f._pvDispelBdrC
            r, g, b, a = c.r, c.g, c.b, c.a or 1
        elseif f._hovered and s.hoverBorderEnabled ~= false then
            local c = s.hoverBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.hoverBorderAlpha or 1
            raised, hlSize = true, s.hoverBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.hoverBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif f._isTarget and s.targetBorderEnabled ~= false then
            local c = s.targetBorderColor or { r = 1, g = 1, b = 1 }
            r, g, b, a = c.r, c.g, c.b, s.targetBorderAlpha or 1
            raised, hlSize = true, s.targetBorderSize or 1
            hlPx = EllesmereUI.BorderPx(s.targetBorderSizePx, hlSize, s.borderTexture or "solid")
        elseif f._pvAggroBdr then
            -- Threat Borders' Color Custom Borders (set by ApplyPreviewData): the threat
            -- color, raised like the real frames, below hover/target and above dispel.
            r, g, b, a = 1, 0, 0, 1
            raised = true
        elseif f._pvDispelBdrC then
            -- Color Custom Borders (set by ApplyPreviewData): the type color, below hover/target.
            local c = f._pvDispelBdrC
            r, g, b, a = c.r, c.g, c.b, c.a or 1
        else
            local c = s.borderColor or { r = 0, g = 0, b = 0 }
            r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
        end
        -- Match real frames: raise the inset border above overlapping neighbors
        -- while highlighted (handles negative Frame Spacing in the preview too).
        -- Guard the level writes so a refresh only touches them on a real change.
        local pl = f:GetFrameLevel()
        local lvl = s.borderBehind and math.max(0, pl - 1) or (pl + (raised and ns.LVL_RAISE or 8))
        local container = PP.GetBorders(bdrFrame)
        if bdrFrame:GetFrameLevel() ~= lvl
           or (container and container:GetFrameLevel() ~= lvl + 1) then
            bdrFrame:SetFrameLevel(lvl)
            if container then container:SetFrameLevel(lvl + 1) end
            -- Textured styles: the backdrop child too, as on live frames.
            local bd = EllesmereUI._bdBorderData and EllesmereUI._bdBorderData[bdrFrame]
            if bd then bd:SetFrameLevel(lvl) end
        end
        if (s.borderSize or 1) <= 0 then
            ns.ApplyHighlightBorder(bdrFrame, s, hlSize, r, g, b, a, hlPx)
            return
        end
        if hlSize then r, g, b = ns.RF_VisibleHighlight(s, r, g, b) end
        bdrFrame._hlBorderSize = nil
        EllesmereUI.SetBorderStyleColor(bdrFrame, r, g, b, a)
        if s.powerBorderMatchColor == true and f._powerBorder and f._powerBorder._powerArtMode == "divider" then
            ns.RF_ColorPowerDivider(f._powerBorder, r, g, b, a)
        end
        if s.topNameBarDividerMatchColor == true and f._topNameBar and f._topNameBar._divider then
            ns.RF_ColorPowerDivider(f._topNameBar._divider, r, g, b, a)
        end
    end
    f._ApplyBorderColor = PvApplyBorderColor

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() f._hovered = true; PvApplyBorderColor() end)
    f:SetScript("OnLeave", function() f._hovered = false; PvApplyBorderColor() end)

    -- Threat border (aggro indicator)
    local threatFrame = CreateFrame("Frame", nil, f)
    threatFrame:SetAllPoints(f)
    threatFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    threatFrame:Hide()
    if PP then PP.CreateBorder(threatFrame, 1, 0, 0, 1, 2) end

    -- Click to toggle target in test mode (recolors the single border)
    f:SetScript("OnMouseDown", function(self)
        if not PvActive() then return end
        for _, pf in ipairs(PvFrames()) do
            if pf ~= self and pf._isTarget then
                pf._isTarget = false
                if pf._ApplyBorderColor then pf._ApplyBorderColor() end
            end
        end
        f._isTarget = true
        PvApplyBorderColor()
    end)

    -- Dispel border
    local dispelBdrFrame = CreateFrame("Frame", nil, f)
    dispelBdrFrame:SetAllPoints(health)
    dispelBdrFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    dispelBdrFrame:Hide()
    if PP then PP.CreateBorder(dispelBdrFrame, 0.2, 0.6, 1, 1, 2) end

    -- Dispel overlay (texture on health bar at ARTWORK sublevel 3: above fill
    -- and above the BM health-color overlay (sublevel 2), below absorbs/text)
    local dispelOLTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
    dispelOLTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dispelOLTex:Hide()

    -- Dispel type icon. Preview parity with the real frames' dispel icon
    -- band: above the aura band so it covers debuff icons sharing its
    -- corner, below the marker band.
    local dispelIconFrame = CreateFrame("Frame", nil, f)
    dispelIconFrame:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER - 1)
    dispelIconFrame:SetSize(16, 16)
    dispelIconFrame:SetPoint("CENTER", health, "CENTER", 0, 0)
    dispelIconFrame:Hide()
    local dispelIconTex = dispelIconFrame:CreateTexture(nil, "ARTWORK")
    dispelIconTex:SetAllPoints()
    dispelIconTex:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Marker carrier: above the frame border (incl. hover/target raise) so the
    -- leader icon and raid marker render on top of it (mirrors real frames).
    local markerCarrier = CreateFrame("Frame", nil, f)
    markerCarrier:SetAllPoints(health)
    markerCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_MARKER)

    -- Raid marker (on marker carrier, above the border)
    local raidMarker = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 2)
    local rmSz = PixelSnap(s.raidMarkerSize or 16)
    raidMarker:SetSize(rmSz, rmSz)
    raidMarker:Hide()

    -- Ready check icon (position/size re-applied in the preview indicator pass)
    local readyCheck = markerCarrier:CreateTexture(nil, "OVERLAY")
    readyCheck:SetSize(PixelSnap(s.readyCheckSize or 20), PixelSnap(s.readyCheckSize or 20))
    readyCheck:SetPoint("CENTER", health, "CENTER", 0, 0)
    readyCheck:Hide()

    -- Combat icon (position/size/style re-applied in the preview indicator pass)
    local combatIcon = markerCarrier:CreateTexture(nil, "OVERLAY", nil, 1)
    combatIcon:SetSize(PixelSnap(s.combatIndicatorSize or 16), PixelSnap(s.combatIndicatorSize or 16))
    combatIcon:Hide()

    -- Text carrier: text band (above every border incl. the raise, below auras).
    local textCarrier = CreateFrame("Frame", nil, f)
    textCarrier:SetAllPoints(health)
    textCarrier:SetFrameLevel(f:GetFrameLevel() + ns.LVL_TEXT)

    -- Name text (anchoring done by ApplyPreviewData on every refresh)
    local nameFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(nameFS, s.nameSize or 10)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    nameFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Health text
    local healthFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healthFS, s.healthTextSize or 9)
    healthFS:SetJustifyH("CENTER")
    healthFS:SetPoint("CENTER", health, "CENTER", 0, 0)
    healthFS:SetTextColor(1, 1, 1, 0.9)

    -- Power text (anchored, sized, coloured and shown by ApplyPreviewData)
    local powerFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(powerFS, s.powerTextSize or 8)
    powerFS:SetWordWrap(false)
    powerFS:SetTextColor(1, 1, 1, 0.9)
    powerFS:Hide()

    -- Level text on its own spot (anchored, sized, coloured and shown by ApplyPreviewData)
    local levelFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(levelFS, s.levelTextSize or 10)
    levelFS:SetWordWrap(false)
    levelFS:Hide()

    -- Heal absorb text (preview)
    local healAbsorbFS = textCarrier:CreateFontString(nil, "OVERLAY")
    ApplyFont(healAbsorbFS, s.healAbsorbTextSize or 9)
    healAbsorbFS:SetWordWrap(false)
    healAbsorbFS:SetJustifyH("CENTER")
    healAbsorbFS:SetPoint("CENTER", health, "CENTER", 0, 0)

    -- Status text (DEAD / OFFLINE / AFK)
    local statusFS = textCarrier:CreateFontString(nil, "OVERLAY")
    local pvStc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    ApplyFont(statusFS, s.statusTextSize or 14)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetTextColor(pvStc.r, pvStc.g, pvStc.b)
    statusFS:Hide()

    -- Role icon. Carrier sits just BELOW the aura band and above the base border
    -- (mirrors the real frames): clears the general border while auras draw over
    -- it; the hover/target border raise intentionally covers it.
    local roleCarrier = CreateFrame("Frame", nil, f)
    roleCarrier:SetAllPoints(health)
    roleCarrier:SetFrameLevel(f:GetFrameLevel() + (ns.LVL_AURA - 1))
    local roleIcon = roleCarrier:CreateTexture(nil, "OVERLAY")
    local riSz = PixelSnap(s.roleIconSize or 14)
    roleIcon:SetSize(riSz, riSz)

    -- Leader icon: on the text carrier band (above the general border, below the
    -- aura layer) to mirror the real frames -- the hover/target raise covers it,
    -- the general border does not.
    local leaderIcon = textCarrier:CreateTexture(nil, "OVERLAY")
    local liSz = PixelSnap(s.leaderIconSize or 14)
    leaderIcon:SetSize(liSz, liSz)
    local liPos = (s.leaderIconPosition or "top"):upper()
    leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
    leaderIcon:Hide()

    -- Top Name Bar (preview; sized/styled by ApplyPreviewData)
    local tnb = CreateFrame("Frame", nil, f)
    tnb:SetFrameLevel(f:GetFrameLevel() + 4)
    tnb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tnb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tnb:SetHeight(PixelSnap(s.topNameBarHeight or 20))
    local tnbBg = tnb:CreateTexture(nil, "BACKGROUND")
    tnbBg:SetAllPoints()
    if PP then PP.DisablePixelSnap(tnbBg) end
    local tnbText = tnb:CreateFontString(nil, "OVERLAY")
    ApplyFont(tnbText, s.topNameBarTextSize or 11)
    tnbText:SetWordWrap(false)
    tnb:Hide()

    -- Store references
    f._bg = bg
    f._health = health
    f._absorbBar = absorbBar
    f._power = power
    f._border = bdrFrame
    f._threatFrame = threatFrame
    -- Stock styles: the stock edge, highlights and divider (our frame), or
    -- the Party Frames kit (host, art, portrait; stamps health._euiKitRef
    -- here, before any refresh anchors to the host).
    if kit then
        ns.RF_KitBuild(f, f, health, power, bdrFrame)
    elseif ns.RF_Stock() then
        ns.RF_StockBuild(f, f, power)
    end
    f._dispelBdrFrame = dispelBdrFrame
    f._dispelOLTex = dispelOLTex
    f._dispelIcon = dispelIconFrame
    f._dispelIconTex = dispelIconTex
    f._raidMarker = raidMarker
    f._readyCheck = readyCheck
    f._nameText = nameFS
    f._topNameBar = tnb
    f._topNameBarBg = tnbBg
    f._topNameBarText = tnbText
    f._healthText = healthFS
    f._powerText = powerFS
    f._levelText = levelFS
    f._healAbsorbText = healAbsorbFS
    f._statusText = statusFS
    f._roleIcon = roleIcon
    f._leaderIcon = leaderIcon
    f._combatIcon = combatIcon

    -- Helper: create a preview aura icon with texture, cooldown, border
    local function MakePreviewAuraIcon(parent, level, sz)
        local di = CreateFrame("Frame", nil, parent)
        di:SetFrameLevel(level)
        di:SetSize(sz, sz)
        di:Hide()
        local dt = di:CreateTexture(nil, "ARTWORK")
        dt:SetAllPoints(); dt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        di._tex = dt
        local cd = CreateFrame("Cooldown", nil, di, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.6); cd:SetReverse(true)
        cd:SetHideCountdownNumbers(true)
        di._cooldown = cd
        local dbdr = CreateFrame("Frame", nil, di)
        dbdr:SetAllPoints(); dbdr:SetFrameLevel(di:GetFrameLevel() + 1)
        if PP then PP.CreateBorder(dbdr, 0, 0, 0, 1, 1) end
        di._borderFrame = dbdr
        local countCarrier = CreateFrame("Frame", nil, di)
        countCarrier:SetAllPoints()
        countCarrier:SetFrameLevel(math.max(cd:GetFrameLevel() + 2, dbdr:GetFrameLevel() + 1))
        local fpInit = (EllesmereUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
        local countFS = countCarrier:CreateFontString(nil, "OVERLAY")
        countFS:SetPoint("BOTTOMRIGHT", di, "BOTTOMRIGHT", 1, -1)
        EllesmereUI.ApplyIconTextFont(countFS, fpInit, 8, "raidFrames")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetText("")
        di._count = countFS
        -- Duration text (on same carrier above cooldown swipe)
        local durFS = countCarrier:CreateFontString(nil, "OVERLAY")
        durFS:SetPoint("CENTER", di, "CENTER", 0, 0)
        EllesmereUI.ApplyIconTextFont(durFS, fpInit, 8, "raidFrames")
        durFS:SetTextColor(1, 1, 1)
        durFS:Hide()
        di._durText = durFS
        return di
    end

    -- Debuff preview icons. Pool sized to the max debuffCap (8) so the player
    -- frame can showcase a full wrapping layout; only a few are shown otherwise.
    f._pvDebuffs = {}
    for i = 1, 8 do
        f._pvDebuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, ns.RFC_DebuffSize(s))
    end

    -- Static dispel debuff icon (shown when dispel eyeball is on)
    f._pvDispelDebuff = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, ns.RFC_DebuffSize(s))

    -- Defensive preview icons
    f._pvDefs = {}
    for i = 1, 4 do
        f._pvDefs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, s.defSize or 22)
    end

    -- Buff preview icons (test mode: configured buffs cycled across frames)
    f._pvBuffs = {}
    for i = 1, 8 do
        f._pvBuffs[i] = MakePreviewAuraIcon(f, f:GetFrameLevel() + ns.LVL_AURA, 18)
    end

    return f
end

local function GetOrCreatePreviewFrame(index)
    if not previewFrames[index] then
        previewFrames[index] = CreatePreviewFrame(index)
    end
    return previewFrames[index]
end

I.CreatePreviewFrame, I.GetOrCreatePreviewFrame = CreatePreviewFrame, GetOrCreatePreviewFrame
I.previewGroupLabels = previewGroupLabels
I.broken = false
