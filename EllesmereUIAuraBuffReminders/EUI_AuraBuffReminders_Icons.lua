if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Icons.lua
--
--  The icon pools (secure, combat, cursor), the provider cast button, the
--  glows, the shared icon decorations, the icon factory and the entry
--  setup.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local floor, max = math.floor, math.max

local _B, DEFAULT_TEXT_COLOR, EABR = I._B, I.DEFAULT_TEXT_COLOR, I.EABR
local GetPlayerClass, GetTextAnchorPoints = I.GetPlayerClass, I.GetTextAnchorPoints
local InCombat, Known, ResolveFontPath = I.InCombat, I.Known, I.ResolveFontPath
local ResolveGlowTint, SetABRFont, SpellName, Tex = I.ResolveGlowTint, I.SetABRFont, I.SpellName, I.Tex
local RAID_BUFFS, _dismissedUntilLoad = I.RAID_BUFFS, I._dismissedUntilLoad
local GLOW_VIEW, StopAllGlows = I.GLOW_VIEW, I.StopAllGlows

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Icon Pool SecureActionButton based for click-to-cast
-------------------------------------------------------------------------------
local ICON_SIZE = 40
local iconAnchor
I.iconAnchorSetters[#I.iconAnchorSetters + 1] = function(v) iconAnchor = v end
local iconPool = {}     -- all created icon buttons
local activeIcons = {}  -- currently visible icons

-- Shape settings are shared with the split runtime and load-on-demand options.
do
    function ns.IconShapeValues()
        if not ns._iconShapeValues then
            ns._iconShapeValues = {
                none = "None", cropped = "Cropped", square = "Square", circle = "Circle",
                csquare = "Curved Square", diamond = "Diamond", hexagon = "Hexagon",
                portrait = "Portrait", shield = "Shield",
            }
            ns._iconShapeOrder = { "none", "cropped", "---", "square", "circle", "csquare",
                "diamond", "hexagon", "portrait", "shield" }
        end
        return ns._iconShapeValues, ns._iconShapeOrder
    end

    function ns.IconShapeMasked(p)
        local shape = p and p.iconShape
        return shape and shape ~= "none" and shape ~= "cropped"
            and EllesmereUI.SHAPE_MASKS[shape] ~= nil
    end

    function ns.CropPercent(p)
        local pct = tonumber(p and p.iconCropPercent) or 10
        if pct < 5 then pct = 5 elseif pct > 25 then pct = 25 end
        return pct
    end

    function ns.IconDimensions(size, p)
        if p and p.iconShape == "cropped" then
            return size, math.floor(size * (1 - 2 * ns.CropPercent(p) / 100) + 0.5)
        end
        if ns.IconShapeMasked(p) then return size + 8, size + 8 end
        return size, size
    end

    -- Only addon-owned icons reach this helper. Secure owners are gated by the caller.
    function ns.ApplyIconShape(f, p)
        if not (f and f._icon) then return end
        local shape = (p and p.iconShape) or "none"
        local masked = ns.IconShapeMasked(p)
        local zoom = (p and p.iconZoom) or 0.07
        local crop = shape == "cropped" and ns.CropPercent(p) or 0
        local inset = masked and ((p and p.borderSize) or 1) > 0 and 1 or 0
        local state = f._eabrShape
        if not state then
            if shape == "none" and not (p and p.iconZoom) then return end
            state = {}
            f._eabrShape = state
        end
        if state.shape == shape and state.zoom == zoom and state.crop == crop
            and state.inset == inset and state.highlight == f._hl then return end
        local icon = f._icon
        if masked then
            if not state.mask then state.mask = f:CreateMaskTexture() end
            state.mask:SetTexture(EllesmereUI.SHAPE_MASKS[shape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            state.mask:ClearAllPoints()
            if inset > 0 then
                -- CDM keeps the icon inside the ring; the ring itself is unmasked.
                EllesmereUI.PP.Point(state.mask, "TOPLEFT", f, "TOPLEFT", inset, -inset)
                EllesmereUI.PP.Point(state.mask, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
            else
                state.mask:SetAllPoints(f)
            end
            state.mask:Show()
            if not state.attached then
                icon:AddMaskTexture(state.mask)
                state.attached = true
            end
            if f._hl and (state.highlight ~= f._hl or not state.highlightAttached) then
                f._hl:AddMaskTexture(state.mask)
                state.highlightAttached = true
            end
            if not state.glowExtra then state.glowExtra = {} end
            -- Outline glows extend beyond the inset icon mask, like CDM's proc glows.
            state.glowExtra.shapeMask = state.mask
            state.glowExtra.maskPath = EllesmereUI.SHAPE_MASKS[shape]
            state.glowExtra.borderPath = EllesmereUI.SHAPE_BORDERS[shape]
            local visible = (128 - 2 * (EllesmereUI.SHAPE_INSETS[shape] or 17)) / 128
            local half = (0.5 - zoom) / visible
            icon:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
        else
            if state.attached then
                icon:RemoveMaskTexture(state.mask)
                if state.highlight then state.highlight:RemoveMaskTexture(state.mask) end
                state.attached = nil
                state.highlightAttached = nil
            end
            if state.mask then state.mask:Hide() end
            icon:SetTexCoord(zoom, 1 - zoom, zoom + crop / 100, 1 - zoom - crop / 100)
        end
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        state.shape, state.zoom, state.crop, state.highlight = shape, zoom, crop, f._hl
        state.inset = inset
    end

    function ns.IconGlowExtra(f, panel)
        local state = f._eabrShape
        if state and state.attached then
            state.glowExtra.panel = panel or nil
            return state.glowExtra
        end
        return panel and EllesmereUI.Glows.PANEL_EXTRA or nil
    end

    -- Secure icons are skipped in combat (ApplyIconBorder); the combat-end
    -- refresh lays them out again with the shape.
    function ns.RefreshIconShapes()
        I.EABR.ApplyAllIconBorders()
        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    end
end

-- Talent icon state moved to EllesmereUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Combat Icon Pool -- non-secure frames for visual-only display during combat.
-------------------------------------------------------------------------------
local combatAnchor      -- created in OnEnable, follows iconAnchor position
I.combatAnchorSetters[#I.combatAnchorSetters + 1] = function(v) combatAnchor = v end
local combatIconPool = {}
local receiverIconPool = {}  -- a groupmate's raid buff the player cannot cast
local combatActiveIcons = {}

-------------------------------------------------------------------------------
--  Cursor-attached combat icons -- shown at cursor when cursorAttach is enabled.
-------------------------------------------------------------------------------
local CURSOR_IMPORTANT = {
    -- PROVIDER raid buffs are important (cat == "raidbuff" + mode "spell" --
    -- see IsImportantBuff): a buff YOU can cast that the group is missing.
    -- Receiver-view reminders (a groupmate's buff the player lacks) never
    -- ride the cursor -- nothing there is actionable by the player's own
    -- hands. Beacon tracking uses its own independent system (_B); beacons
    -- are the player's own casts, so their cursor treatment already fits.
}
local cursorAnchor
I.cursorAnchorSetters[#I.cursorAnchorSetters + 1] = function(v) cursorAnchor = v end
local cursorIconPool = {}
local cursorActiveIcons = {}

local function GetStrata()
    return db and db.profile.display.frameStrata or "MEDIUM"
end

-- Borders live on a dedicated visual child instead of on the reminder
-- button itself. Besides allowing Border Size 0 without hiding the icon, this
-- keeps all BackdropTemplate work away from secure action attributes. Secure
-- owners are never created/restyled under combat lockdown; visual-only combat
-- and cursor icons can still update immediately.
-- The options page frame pool's table (the parent makes it, the options addon
-- fills it in place when it loads the pool), captured once at load as the
-- core's paths capture it, so a later write to the public slot never reaches
-- this path. A block local.
do
    local POOL = EllesmereUI._Pool
    function EABR.ApplyIconBorder(f, protectedOwner)
        if not f or (protectedOwner and InCombatLockdown()) then return end
        local p = db and db.profile and db.profile.display
        if (p and ((p.iconShape and p.iconShape ~= "none") or p.iconZoom)) or f._eabrShape then
            ns.ApplyIconShape(f, p)
        end
        local border = f._eabrBorderFrame
        if not border then
            -- The options preview icons are frames of the options page pool, so
            -- their border comes from it too; a live reminder icon gets a plain
            -- new frame.
            border = POOL.CreateFrame("Frame", nil, f)
            border:SetAllPoints()
            border:EnableMouse(false)
            f._eabrBorderFrame = border
        end

        local size = (p and p.borderSize) or 1
        local texture = (p and p.borderTexture) or "solid"
        local r, g, b, a = (p and p.borderR) or 0, (p and p.borderG) or 0,
            (p and p.borderB) or 0, (p and p.borderA) or 1
        local ox, oy = p and p.borderTextureOffset, p and p.borderTextureOffsetY
        local sx, sy = p and p.borderTextureShiftX, p and p.borderTextureShiftY
        local behind = p and p.borderBehind == true
        -- +2: the strips sit one level up (PP.CreateBorder), below the glow
        -- wrapper (+4), so a 1px glow is never hidden under a 1px border.
        local level = behind and max(0, f:GetFrameLevel() - 1) or (f:GetFrameLevel() + 2)
        -- Exact size companion, memoized raw: it only counts while paired with size + texture.
        local pxRaw = p and p.borderSizePx

        if p and p.iconShape and p.iconShape ~= "none" and ns.IconShapeMasked(p) then
            -- Shape art has its own thickness units; never send it through the
            -- rectangular border cache, which must repaint after switching back.
            if border._eabrSize ~= nil then
                EllesmereUI.ApplyBorderStyle(border, 0, r, g, b, a, "solid")
                border._eabrSize = nil
            end
            border:SetFrameLevel(level)
            -- Clearing rectangular art at size zero also hides its host.
            if not border:IsShown() then border:Show() end
            EllesmereUI.PP:ApplyMaskedShapeBorder(border, nil,
                EllesmereUI.SHAPE_BORDERS[p.iconShape], size > 0 and 7 or 0, r, g, b, a)
            return
        elseif f._eabrShape then
            EllesmereUI.PP:HideMaskedShapeBorder(border)
        end

        -- Layout refreshes can be frequent in a raid. Restyle only when an actual
        -- setting or owner-level change occurred; size changes are handled by the
        -- border frame's anchors/BackdropTemplate size hook.
        if border._eabrSize == size and border._eabrTexture == texture and border._eabrPx == pxRaw
            and border._eabrR == r and border._eabrG == g and border._eabrB == b and border._eabrA == a
            and border._eabrOX == ox and border._eabrOY == oy and border._eabrSX == sx and border._eabrSY == sy
            and border._eabrBehind == behind and border._eabrLevel == level then
            return
        end

        border:SetFrameLevel(level)
        EllesmereUI.ApplyBorderStyle(border, size, r, g, b, a, texture,
            ox, oy, sx, sy, "aurabuffreminders", size, nil,
            EllesmereUI.BorderPx(pxRaw, size, texture))
        border._eabrSize, border._eabrTexture, border._eabrPx = size, texture, pxRaw
        border._eabrR, border._eabrG, border._eabrB, border._eabrA = r, g, b, a
        border._eabrOX, border._eabrOY, border._eabrSX, border._eabrSY = ox, oy, sx, sy
        border._eabrBehind, border._eabrLevel = behind, level
    end
end

function EABR.ApplyAllIconBorders()
    for _, f in pairs(iconPool) do EABR.ApplyIconBorder(f, true) end
    for _, f in pairs(combatIconPool) do EABR.ApplyIconBorder(f, false) end
    for _, f in pairs(receiverIconPool) do EABR.ApplyIconBorder(f, false) end
    for _, f in pairs(cursorIconPool) do EABR.ApplyIconBorder(f, false) end
    if EABR._providerCastBtn then EABR.ApplyIconBorder(EABR._providerCastBtn, true) end
    if _B.icons then
        for _, f in pairs(_B.icons) do EABR.ApplyIconBorder(f, false) end
    end
end

function EABR.GetIconTextOverlay(f)
    if f._textOverlay then return f._textOverlay end
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f._textOverlay = overlay
    return overlay
end

local function BuildCombatIcon(name)
    local f = CreateFrame("Frame", name, combatAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata(GetStrata())
    f:SetFrameLevel(120)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    EABR.ApplyIconBorder(f, false)
    local text = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    EABR.CreateIconCountOverlay(f)
    EABR.CreateIconQualityOverlay(f)
    EABR.CreateIconBagCountOverlay(f)
    EABR.AttachIconHover(f)
    EABR.AttachIconTooltip(f)
    EABR.AttachCombatClickHint(f)
    return f
end

local function GetOrCreateCombatIcon(index)
    local f = combatIconPool[index]
    if not f then
        f = BuildCombatIcon("EABR_CombatIcon"..index)
        combatIconPool[index] = f
    end
    return f
end

-- A groupmate's raid buff the player cannot cast is shown to be read, never
-- clicked: its icon lets the left and right click through to whatever is
-- behind, keeps the middle-click dismiss and shows no hover highlight. Click
-- routing (SetPassThroughButtons) is blocked in combat on every frame, ours
-- included, so these icons have a pool of their own whose routing is set once,
-- out of combat. One first built in combat lets every click through (no
-- dismiss) until HideCombatIcons routes it once combat is over.
local receiversUnrouted = false
local function RouteReceiverIcon(f)
    if InCombatLockdown() then
        f:SetMouseClickEnabled(false)
        receiversUnrouted = true
        return
    end
    f:SetPassThroughButtons("LeftButton", "RightButton")
    f:SetMouseClickEnabled(true)
    f._routed = true
end

local function GetOrCreateReceiverIcon(index)
    local f = receiverIconPool[index]
    if not f then
        f = BuildCombatIcon("EABR_ReceiverIcon"..index)
        EABR.SetIconHighlight(f, false)
        RouteReceiverIcon(f)
        receiverIconPool[index] = f
    end
    return f
end

-- Icons of each pool shown by the current combat pass.
local combatShown, receiversShown = 0, 0

local function HideCombatIcons()
    for i = 1, #combatActiveIcons do
        local f = combatActiveIcons[i]
        if f then
            EABR.ClearEatingVisual(f)
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(combatActiveIcons)
    combatShown, receiversShown = 0, 0
    if receiversUnrouted and not InCombatLockdown() then
        receiversUnrouted = false
        for _, f in pairs(receiverIconPool) do
            if not f._routed then RouteReceiverIcon(f) end
        end
    end
    if EABR.SetProviderCastCombatVisible then
        EABR.SetProviderCastCombatVisible(false)
    end
    if combatAnchor then EllesmereUI.SetElementVisibility(combatAnchor, false) end
end

local function ShowCombatIcon(m)
    local f
    if EABR.IsReceiverRaidBuff(m) then
        receiversShown = receiversShown + 1
        f = GetOrCreateReceiverIcon(receiversShown)
    else
        combatShown = combatShown + 1
        f = GetOrCreateCombatIcon(combatShown)
    end
    f._dismissKey = m.dismissKey or nil
    local spellID = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellID and Tex(spellID)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    EABR.ApplyEatingVisual(f, m)
    EABR.ApplyIconExpiry(f, m)
    EABR.ApplyIconTooltipData(f, m)
    EABR.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(f, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    f:Show()
    combatActiveIcons[#combatActiveIcons+1] = f
end

-- Left-aligned from the anchor's left edge; Grow Left right-aligns from its
-- right edge instead. Slot 0 is reserved while the provider secure button is
-- shown, and stays reserved after a mid-combat hide until the OOC park -- its
-- SetPoint/EnableMouse are protected under lockdown, so other icons must never
-- slide under it: while it is reserved Grow Left keeps the left-aligned row.
local function LayoutCombatIcons()
    local reserveSlot = EABR._providerCastVisible or EABR._providerCastCombatReserved
    local count = #combatActiveIcons
    if count == 0 and not reserveSlot then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p.iconShape and p.iconShape ~= "none" then sz, iconH = ns.IconDimensions(sz, p) end
    local xOff = reserveSlot and (sz + spacing) or 0
    local pt = "TOPLEFT"
    if p.growDirection == "LEFT" and not reserveSlot then
        pt, xOff = "TOPRIGHT", -(count - 1) * (sz + spacing)
    end
    for i, f in ipairs(combatActiveIcons) do
        f:SetSize(sz, iconH)
        f:SetAlpha(p.opacity or 1.0)
        EABR.ApplyIconBorder(f, false)
        EABR.SizeIconQuality(f, sz)
        EABR.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint(pt, combatAnchor, pt, xOff + (i-1)*(sz+spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Cursor Icon Pool: same visual style as combat icons, parented to cursorAnchor (follows the cursor frame).
-------------------------------------------------------------------------------
local function GetOrCreateCursorIcon(index)
    if cursorIconPool[index] then return cursorIconPool[index] end
    local f = CreateFrame("Frame", "EABR_CursorIcon"..index, cursorAnchor)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9980)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    EABR.ApplyIconBorder(f, false)
    local text = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text
    EABR.CreateIconCountOverlay(f)
    EABR.CreateIconQualityOverlay(f)
    EABR.CreateIconBagCountOverlay(f)
    EABR.AttachIconHover(f)
    EABR.AttachIconTooltip(f)
    EABR.AttachCombatClickHint(f)
    cursorIconPool[index] = f
    return f
end

-- Hides the cursor anchor once nothing rides it: no cursor icon and no beacon
-- placed on it (_B.onCursor). Hidden, it stops following the cursor (OnHide
-- unsubscribes); every placement shows it again.
local function ReleaseCursorAnchor()
    if cursorAnchor and #cursorActiveIcons == 0 and not _B.onCursor then
        cursorAnchor:Hide()
    end
end

local function HideCursorIcons()
    for i = 1, #cursorActiveIcons do
        local f = cursorActiveIcons[i]
        if f then
            EABR.ClearEatingVisual(f)
            if f._eabrGlowWrapper then f._eabrGlowWrapper:Hide() end
            f._text:SetText(""); f:Hide()
        end
    end
    wipe(cursorActiveIcons)
    if cursorAnchor then EllesmereUI.SetElementVisibility(cursorAnchor, false) end
    ReleaseCursorAnchor()
end

local function ShowCursorIcon(iconIdx, m)
    local f = GetOrCreateCursorIcon(iconIdx)
    f._dismissKey = m.dismissKey or nil
    local spellID = m.spellID or (m.data and m.data.castSpell)
    f._icon:SetTexture(m.texture or (spellID and Tex(spellID)) or 134400)
    local p = db and db.profile.display
    if p and p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontPath, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(m.label or "")
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
    EABR.ApplyEatingVisual(f, m)
    EABR.ApplyIconExpiry(f, m)
    EABR.ApplyIconTooltipData(f, m)
    EABR.ApplyIconQuality(f, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(f, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(f, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    f:Show()
    cursorActiveIcons[#cursorActiveIcons+1] = f
end

local function LayoutCursorIcons()
    local count = #cursorActiveIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p.iconShape and p.iconShape ~= "none" then sz, iconH = ns.IconDimensions(sz, p) end
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, f in ipairs(cursorActiveIcons) do
        f:SetSize(sz, iconH)
        f:SetAlpha(p.opacity or 1.0)
        EABR.ApplyIconBorder(f, false)
        EABR.SizeIconQuality(f, sz)
        EABR.SizeIconBagCount(f, sz)
        f:ClearAllPoints()
        f:SetPoint("CENTER", cursorAnchor, "CENTER", startX + (i-1)*(sz+spacing), 0)
    end
end

-------------------------------------------------------------------------------
--  Provider raid-buff cast button: a dedicated SecureActionButton pre-bound
--  OOC to the player's own raid buff, so the rebuff stays clickable through
--  combat (post-combat-res). Spell attributes, size and position are set out
--  of combat ONLY; in combat only alpha and child visuals change. Parented
--  to UIParent so anchor mouse states never swallow its clicks.
-------------------------------------------------------------------------------
function EABR.LayoutProviderCastHome()
    if InCombatLockdown() then return end
    local btn = EABR._providerCastBtn
    if not btn or not iconAnchor then return end
    local p = db and db.profile and db.profile.display
    local baseScale = (p and p.scale) or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local iconH = sz
    if p and p.iconShape and p.iconShape ~= "none" then sz, iconH = ns.IconDimensions(sz, p) end
    btn:SetSize(sz, iconH)
    EABR.ApplyIconBorder(btn, true)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    EABR.SizeIconQuality(btn, sz)
    EABR.SizeIconBagCount(btn, sz)
end

function EABR.ParkProviderCastButton()
    local btn = EABR._providerCastBtn
    if not btn then return end
    local wasVisible = EABR._providerCastVisible
    EABR._providerCastVisible = false
    btn:SetAlpha(0)
    if btn._text then btn._text:SetText(""); btn._text:Hide() end
    if btn._eabrGlowWrapper then btn._eabrGlowWrapper:Hide() end
    if InCombatLockdown() then
        -- Slot stays reserved; move/mouse changes are protected under lockdown.
        if wasVisible or EABR._providerCastCombatReserved then
            EABR._providerCastCombatReserved = true
        end
        return
    end
    EABR._providerCastCombatReserved = false
    btn:EnableMouse(false)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
end

function EABR.EnsureProviderCastButton()
    if EABR._providerCastBtn then return EABR._providerCastBtn end
    if not iconAnchor or InCombatLockdown() then return nil end
    local btn = CreateFrame("Button", "EABR_ProviderCast", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetFrameStrata(GetStrata())
    btn:SetFrameLevel(120)
    btn:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end
    end)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    EABR.ApplyIconBorder(btn, true)
    local text = EABR.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text
    EABR.CreateIconCountOverlay(btn)
    EABR.CreateIconQualityOverlay(btn)
    EABR.CreateIconBagCountOverlay(btn)
    EABR.AttachIconHover(btn)
    EABR.AttachIconTooltip(btn)
    btn:Show()
    EABR._providerCastBtn = btn
    EABR._providerCastVisible = false
    EABR.ParkProviderCastButton()
    return btn
end

-- Binds the player's own castable raid buff to the button (OOC only), so the
-- binding is already warm when combat starts. WoW Forever binds the cast its
-- Raid Buffs pass picked (a rank and the member to cast it on) and builds the
-- button only once there is one.
function EABR.SyncProviderCastSpell()
    if InCombatLockdown() then return end
    local spellID, unit
    if EABR.FOREVER then
        spellID, unit = EABR._fvCastSpell, EABR._fvCastUnit
        if not (spellID or EABR._providerCastBtn) then return end
    end
    local btn = EABR.EnsureProviderCastButton()
    if not btn then return end
    if not EABR.FOREVER then
        local playerClass = GetPlayerClass()
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass and buff.check == "raid" and Known(buff.castSpell) then
                spellID = buff.castSpell
                break
            end
        end
    end
    unit = unit or "player" -- explicit unit so casting doesn't depend on your current target
    -- Attribute writes are skipped when the resolved cast is unchanged
    -- (this runs on every OOC refresh). Invalidation inputs: the resolved
    -- spellID (covers spec/known changes via SPELLS_CHANGED refreshes) and
    -- the unit (WoW Forever's target member).
    if spellID == EABR._providerCastSpell and unit == EABR._providerCastUnit then
        if not EABR._providerCastVisible then EABR.ParkProviderCastButton() end
        return
    end
    EABR._providerCastSpell = spellID
    EABR._providerCastUnit = unit
    if spellID then
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", spellID)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", unit)
        btn._icon:SetTexture(Tex(spellID) or 134400)
        btn._tooltipSpell = spellID
        btn._tooltipItem = nil
    end
    if not EABR._providerCastVisible then
        EABR.ParkProviderCastButton()
    end
end

-- Shows/hides the provider button. OOC: full place/mouse control. Combat:
-- alpha + child visuals only (EnableMouse/SetPoint are protected).
function EABR.SetProviderCastCombatVisible(visible, m)
    local btn = EABR._providerCastBtn
    if not btn then
        EABR._providerCastVisible = false
        return
    end
    if not visible or not m or not EABR._providerCastSpell then
        EABR.ParkProviderCastButton()
        return
    end
    EABR._providerCastVisible = true
    EABR._providerCastCombatReserved = true
    btn._dismissKey = m.dismissKey or nil
    local spellID = m.spellID or EABR._providerCastSpell
    btn._icon:SetTexture(m.texture or Tex(spellID) or 134400)
    EABR.ApplyIconTooltipData(btn, m)
    local p = db and db.profile and db.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        SetABRFont(btn._text, ResolveFontPath(p.nameFont), p.textSize or 11)
        btn._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        btn._text:SetPoint(tp, btn, ip, p.textXOffset or 0, p.textYOffset or -2)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:SetText(m.label or "")
        btn._text:SetAlpha(1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(btn, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(btn, nil, nil, nil)
    end
    if not InCombatLockdown() then
        EABR.LayoutProviderCastHome()
        btn:EnableMouse(true)
    end
    btn:SetAlpha((p and p.opacity) or 1)
end

local function IsImportantBuff(m)
    -- Cursor-worthy = a buff YOU can cast that others are missing (provider
    -- entries, mode "spell"). The receiver view (mode "texture" -- a
    -- groupmate's buff the PLAYER lacks) stays on the normal rows.
    if m.cat == "raidbuff" then return m.mode == "spell" end
    local key = m.data and m.data.key
    return key and CURSOR_IMPORTANT[key] or false
end

-- Hides stale secure buttons via alpha=0 (safe in combat); also stops glow animations (glow wrappers are plain Frames, not secure).
local function FadeOutSecureIcons()
    for i = 1, #activeIcons do
        local btn = activeIcons[i]
        if btn then
            btn:SetAlpha(0)
            -- A faded button still takes clicks: no buff request from it.
            btn._requestKey = nil
            if btn._text then btn._text:SetAlpha(0) end
            if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:SetAlpha(0) end
        end
    end
end

-- Full render spec from the display settings; the options preview renders the
-- same spec. nil when the glow is off.
local ApplyGlow
do
    local SPEC = {}
    local function GlowSpec(p, out)
        local shared = p and GLOW_VIEW.toShared[p.glowType or 0]
        if not shared then return nil end
        out = out or SPEC
        out.style = shared
        out.r, out.g, out.b = ResolveGlowTint(p)
        out.lines, out.thickness, out.speed = p.glowLines, p.glowThickness, p.glowSpeed
        local bgc = p.glowBackgroundColor
        out.bg = (p.glowBackground == true) or nil
        out.bgR, out.bgG, out.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
        return out
    end
    _G._EABR_GlowSpec = GlowSpec

    -- Also clears the glow when it is off, so callers need no RemoveGlow first
    -- (that would reset StartSpecGlow's signature and restart every refresh).
    ApplyGlow = function(btn, p, overrideSz)
        local spec = GlowSpec(p)
        if not spec then
            local w = btn._eabrGlowWrapper
            if w then StopAllGlows(w); w:Hide() end
            return
        end
        if not btn._eabrGlowWrapper then
            local w = CreateFrame("Frame", nil, btn); w:SetAllPoints(btn); w:SetFrameLevel(btn:GetFrameLevel()+4)
            btn._eabrGlowWrapper = w
        end
        local wrapper = btn._eabrGlowWrapper; local sz = overrideSz or btn:GetWidth() or ICON_SIZE
        local h, extra = sz
        if p.iconShape and p.iconShape ~= "none" then
            if overrideSz then sz, h = ns.IconDimensions(sz, p)
            else h = btn:GetHeight() end
        end
        if btn._eabrShape then extra = ns.IconGlowExtra(btn) end
        EllesmereUI.Glows.StartSpecGlow(wrapper, spec, sz, h, "icon", extra)
        wrapper:SetAlpha(1)
        wrapper:Show()
    end
end

local function RemoveGlow(btn)
    if btn._eabrGlowWrapper then StopAllGlows(btn._eabrGlowWrapper); btn._eabrGlowWrapper:Hide() end
end

-------------------------------------------------------------------------------
--  Shared icon decorations (all pools): hover highlight, tooltips, combat
--  click hint, bag-count / coverage / crafted-quality badges, and the eating
--  countdown. All frames here are OURS (field writes are safe). Every helper
--  hangs on EABR.
-------------------------------------------------------------------------------
function EABR.AttachIconHover(f)
    if f._eabrHoverAttached then return end
    local icon = f._icon
    if f:IsObjectType("Button") then
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(icon)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        f._hl = hl
    else
        f:EnableMouse(true)
        local hl = f:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints(icon)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        hl:Hide()
        f:HookScript("OnEnter", function(self) if not self._hlOff then hl:Show() end end)
        f:HookScript("OnLeave", function() hl:Hide() end)
    end
    f._eabrHoverAttached = true
end

-- A groupmate's raid buff the player cannot cast: shown to be read, never
-- clicked (both clients' collectors mark it cat "raidbuff" in texture mode).
function EABR.IsReceiverRaidBuff(m)
    return m.cat == "raidbuff" and m.mode == "texture"
end

-- Per-use hover highlight: off on an icon that takes no left click, so it
-- never reads as a button. A Button draws its highlight on the HIGHLIGHT
-- layer (hidden as a texture); the plain pools gate their OnEnter on the flag.
function EABR.SetIconHighlight(f, on)
    local off = not on
    if f._hlOff == off then return end
    f._hlOff = off
    if f._hl then f._hl:SetShown(on) end
end

function EABR.ApplyIconTooltipData(f, m)
    if not f then return end
    if not m then
        f._tooltipItem = nil
        f._tooltipSpell = nil
        f._tooltipLabel = nil
        return
    end
    f._tooltipItem = m.tooltipItem or m.itemID or nil
    f._tooltipSpell = m.spellID or (m.data and m.data.castSpell) or nil
    f._tooltipLabel = m.label or nil
end

function EABR.ShowIconTooltip(f)
    local d = db and db.profile and db.profile.display
    if not d or d.showTooltips == false then return end
    if not f then return end
    if f._tooltipItem or f._tooltipSpell then
        -- Item/spell data tooltips render through GameTooltip (the only
        -- game-data renderer). pcall-armored: 12.1 restricted-tooltip ACLs
        -- can deny frame-level calls when the content turns secret.
        local ok = pcall(function()
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            if f._tooltipItem then
                GameTooltip:SetItemByID(f._tooltipItem)
            else
                GameTooltip:SetSpellByID(f._tooltipSpell)
            end
            if f._outOfStock then
                GameTooltip:AddLine(EllesmereUI.L("You don't have this item in your bags"), 1, 0.3, 0.3, true)
            elseif f._substitute then
                GameTooltip:AddLine(EllesmereUI.L("Your preferred food is out - using a backup you own"), 1, 0.82, 0, true)
            end
            GameTooltip:Show()
        end)
        if not ok then GameTooltip:Hide() end
    elseif f._tooltipLabel and f._tooltipLabel ~= "" then
        -- Plain-text reminders use the suite tooltip, never GameTooltip.
        EllesmereUI.ShowWidgetTooltip(f, tostring(f._tooltipLabel))
    end
end

function EABR.HideIconTooltip(f)
    if f and (f._tooltipItem or f._tooltipSpell) then
        GameTooltip:Hide()
    else
        EllesmereUI.HideWidgetTooltip()
    end
end

function EABR.AttachIconTooltip(f)
    if f._eabrTooltipAttached then return end
    f:EnableMouse(true)
    f:HookScript("OnEnter", function(self) EABR.ShowIconTooltip(self) end)
    f:HookScript("OnLeave", function(self) EABR.HideIconTooltip(self) end)
    f._eabrTooltipAttached = true
end

-- Visual-only combat/cursor icons: tell the player why left-click does nothing.
function EABR.NotifyCombatClickDisabled()
    local now = GetTime()
    if EABR._clickHintAt and now - EABR._clickHintAt < 2.5 then return end
    EABR._clickHintAt = now
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(EllesmereUI.L("Click-to-use is disabled in combat"), 1.0, 0.3, 0.3, 1.0)
    end
end

-- Click to request: a left-click on a reminder of a buff a groupmate gives
-- (receiver raid buff, Healthstone) asks the group for it in chat, at most
-- once per buff every REQUEST_THROTTLE seconds. The Custom Request Text
-- replaces the default line; REQUEST_TOKEN in it (any case) becomes the
-- buff's name.
do
    local REQUEST_THROTTLE = 10
    local REQUEST_TOKEN = "[spell]"
    local TOKEN_PATTERN = "%[[Ss][Pp][Ee][Ll][Ll]%]"  -- any case
    local sentAt = {}

    -- Cuts s to at most n bytes without splitting a UTF-8 character.
    local function CutBytes(s, n)
        if #s <= n then return s end
        return (s:sub(1, n):gsub("[\192-\255][\128-\191]*$", ""))
    end

    -- Custom text as saved: "|" and control characters dropped (the chat API
    -- rejects stray escape codes), trimmed, capped; nil when empty.
    local function CleanRequestText(text)
        if type(text) ~= "string" then return nil end
        text = CutBytes(strtrim((text:gsub("[%c|]", ""))), 200)
        if text == "" then return nil end
        return text
    end
    -- Custom text until the player saves their own (shows where the token goes).
    local function RequestExample()
        return EllesmereUI.Lf("Could I get %1$s, please?", REQUEST_TOKEN)
    end
    local function HasRequestToken(text)
        return text:find(TOKEN_PATTERN) ~= nil
    end
    _G._EABR_REQUEST_TOKEN = REQUEST_TOKEN
    _G._EABR_HasRequestToken = HasRequestToken
    _G._EABR_CleanRequestText = CleanRequestText
    _G._EABR_RequestExample = RequestExample

    local function RequestChannel()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    end

    function EABR.SendBuffRequest(key, name)
        if InCombatLockdown() then return end
        local channel = RequestChannel()
        if not channel then return end
        if not name then return end
        if C_ChatInfo.InChatMessagingLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(EllesmereUI.L("Buff requests cannot be sent right now"), 1.0, 0.3, 0.3, 1.0)
            end
            return
        end
        local now = GetTime()
        if sentAt[key] and now - sentAt[key] < REQUEST_THROTTLE then return end
        sentAt[key] = now
        local rb = db.profile.raidBuffs
        local custom = rb.requestCustom and CleanRequestText(rb.requestText or RequestExample())
        local msg
        -- Text without the token falls back to the default line.
        if custom and HasRequestToken(custom) then
            msg = custom:gsub(TOKEN_PATTERN, (name:gsub("%%", "%%%%")))
        else
            msg = EllesmereUI.Lf("%1$s, please!", name)
        end
        C_ChatInfo.SendChatMessage(CutBytes(msg, 255), channel)
    end
end

-- Middle-click dismisses here too. These are plain frames rather than the OOC
-- secure buttons, so the click carries no action of its own.
function EABR.AttachCombatClickHint(f)
    if f._eabrCombatClickHint then return end
    f:EnableMouse(true)
    f:HookScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            EABR.NotifyCombatClickDisabled()
        elseif button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        end
    end)
    f._eabrCombatClickHint = true
end

function EABR.CreateIconCountOverlay(f)
    if f._count then return f._count end
    local count = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    count:SetPoint("CENTER", f._icon, "CENTER", 0, 0)
    count:Hide()
    f._count = count
    return count
end

-- Crafted-quality badge (Professions Tier 1/2/3) for a consumable, or nil.
-- Crafted quality is immutable per item, so only positive hits are cached.
EABR._qualityAtlasCache = EABR._qualityAtlasCache or {}
function EABR.GetItemQualityAtlas(itemID)
    if not itemID then return nil end
    local cached = EABR._qualityAtlasCache[itemID]
    if cached then return cached end
    local atlas
    if C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
        local ok, q = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, itemID)
        if ok and q and q > 0 then
            atlas = "Professions-Icon-Quality-Tier" .. q
        end
    end
    if not atlas then
        local link = select(2, C_Item.GetItemInfo(itemID))
        if link then
            local suffix = link:match("Quality%-[%w%-]*Tier%d")
            if suffix then atlas = "Professions-Icon-" .. suffix end
        end
    end
    if atlas then EABR._qualityAtlasCache[itemID] = atlas end
    return atlas
end

function EABR.CreateIconQualityOverlay(f)
    if f._quality then return f._quality end
    -- Keep the crafted-quality badge above the dedicated border child, just
    -- like count/name text. This matters for the wider textured styles.
    local q = EABR.GetIconTextOverlay(f):CreateTexture(nil, "OVERLAY", nil, 7)
    q:Hide()
    f._quality = q
    return q
end

function EABR.SizeIconQuality(f, sz)
    local q = f._quality
    if not q or not f._qualityAtlas then return end
    local qs = max(10, floor(sz * 0.42))
    local off = floor(sz * 0.10)
    q:SetSize(qs, qs)
    q:ClearAllPoints()
    q:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -off, -off)
end

function EABR.ApplyIconQuality(f, atlas)
    if not f then return end
    EABR.CreateIconQualityOverlay(f)
    f._qualityAtlas = atlas or nil
    local q = f._quality
    if atlas then
        q:SetAtlas(atlas)
        EABR.SizeIconQuality(f, f:GetWidth() or ICON_SIZE)
        q:Show()
    else
        q:Hide()
    end
end

-- Bag-count badge (how many of the consumable remain), bottom-right corner.
function EABR.CreateIconBagCountOverlay(f)
    if f._bagCount then return f._bagCount end
    local fs = EABR.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    local p = db and db.profile.display
    SetABRFont(fs, ResolveFontPath(p and p.countFont), 11)
    fs:Hide()
    f._bagCount = fs
    return fs
end

function EABR.SizeIconBagCount(f, sz)
    local fs = f._bagCount
    if not fs or not f._bagCountShown then return end
    local p = db and db.profile.display
    local base = (p and p.countSize) or 16
    local fsz = max(6, floor(base * (sz / ICON_SIZE) + 0.5))
    SetABRFont(fs, ResolveFontPath(p and p.countFont), fsz)
    local dx = (p and p.countXOffset) or 0
    local dy = (p and p.countYOffset) or 0
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", dx, dy)
end

function EABR.ApplyIconBagCount(f, count, outOfStock, substitute, badge)
    if not f then return end
    EABR.CreateIconBagCountOverlay(f)
    f._outOfStock = outOfStock and true or nil
    f._substitute = (substitute and not outOfStock) and true or nil
    local fs = f._bagCount
    local p = db and db.profile.display
    local showCount = not p or p.showCount ~= false
    if showCount and outOfStock then
        f._bagCountShown = true
        fs:SetText("0")
        fs:SetTextColor(1, 0.2, 0.2, 1)
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    elseif badge or (showCount and count and count > 0) then
        f._bagCountShown = true
        fs:SetText(badge or count)
        if substitute and not badge then
            fs:SetTextColor(1, 0.82, 0, 1)
        else
            fs:SetTextColor(1, 1, 1, 1)
        end
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    else
        f._bagCountShown = nil
        fs:SetText("")
        fs:Hide()
    end
end

-- Raid-buff group coverage ("12/15") on the same corner badge as item count.
function EABR.ApplyIconGroupCoverage(f, have, total)
    if not f then return end
    EABR.CreateIconBagCountOverlay(f)
    local fs = f._bagCount
    if have ~= nil and total and total > 0 then
        f._bagCountShown = true
        f._outOfStock = nil
        f._substitute = nil
        fs:SetText(have .. "/" .. total)
        fs:SetTextColor(1, 1, 1, 1)
        EABR.SizeIconBagCount(f, f:GetWidth() or ICON_SIZE)
        fs:Show()
    else
        f._bagCountShown = nil
        fs:SetText("")
        fs:Hide()
    end
end

-------------------------------------------------------------------------------
--  Eating countdown: while the eating channel runs, the food reminder shows
--  the eating icon with a centered countdown instead of nagging mid-meal.
--  The OnUpdate exists ONLY while eating and is throttled to ~5/sec with no
--  per-tick allocation (text only rewritten on change); it self-clears at
--  expiry and requests one refresh.
-------------------------------------------------------------------------------
function EABR.ClearEatingVisual(f)
    if f._eabrEatingOnUpdate then
        f:SetScript("OnUpdate", nil)
        f._eabrEatingOnUpdate = nil
    end
    if f._count then f._count:Hide() end
    if f._expiryBinding then f._expiryBinding:SetEnabled(false) end
    f._eabrEatingIcon = nil
end

function EABR.EatingTick(self, elapsed)
    self._eatingAccum = (self._eatingAccum or 0) + elapsed
    if self._eatingAccum < 0.2 then return end
    self._eatingAccum = 0
    local rem = (self._eatingExp or 0) - GetTime()
    if rem > 0 then
        local txt
        local mins = math.ceil(rem / 60)
        if mins > 1 then
            txt = mins .. "m"
        else
            txt = math.ceil(rem) .. "s"
        end
        if txt ~= self._eatingText then
            self._eatingText = txt
            self._count:SetText(txt)
        end
        self._count:Show()
        if self._text then self._text:Hide() end
    else
        self._count:Hide()
        self:SetScript("OnUpdate", nil)
        self._eabrEatingOnUpdate = nil
        if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    end
end

function EABR.ApplyEatingVisual(f, m)
    EABR.ClearEatingVisual(f)
    if not (m and m.isEating) then return end
    EABR.CreateIconCountOverlay(f)
    f._icon:SetDesaturated(false)
    f._icon:SetTexture(133950)
    f._eabrEatingIcon = true
    RemoveGlow(f)
    local expTime = m.eatingExpirationTime
    if not expTime then return end
    local p = db and db.profile.display
    local fontPath = ResolveFontPath()
    local textSize = max(14, floor(((p and p.textSize) or 11) * 1.15))
    SetABRFont(f._count, fontPath, textSize)
    f._count:SetTextColor(1, 1, 1, 1)
    f._eatingExp = expTime
    f._eatingText = nil
    f._eatingAccum = 1 -- force an immediate paint on the first tick
    EABR.EatingTick(f, 0)
    f._eabrEatingOnUpdate = true
    f:SetScript("OnUpdate", EABR.EatingTick)
end

function EABR.ApplyIconExpiry(f, m)
    local expireAt = m and m.expireAt
    local swipe = f._expirySwipe
    if expireAt and m.expireSwipe then
        if not swipe then
            swipe = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            swipe:SetAllPoints(f._icon)
            swipe:SetHideCountdownNumbers(true)
            swipe:SetDrawEdge(false)
            swipe:SetDrawBling(false)
            f._expirySwipe = swipe
        end
        if swipe._expiryEnd ~= expireAt or swipe._expiryTotal ~= m.expireTotal then
            swipe:SetCooldown(expireAt - m.expireTotal, m.expireTotal)
            swipe._expiryEnd, swipe._expiryTotal = expireAt, m.expireTotal
        end
        swipe:Show()
    elseif swipe then
        swipe:Hide()
        swipe._expiryEnd, swipe._expiryTotal = nil, nil
    end
    local binding = f._expiryBinding
    if not expireAt then
        if binding then binding:SetEnabled(false) end
        return
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then return end
    local count = EABR.CreateIconCountOverlay(f)
    if not binding then
        f._expiryDuration = C_DurationUtil.CreateDuration()
        binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(count)
        binding:SetDuration(f._expiryDuration)
        local fmt = EllesmereUI.AuraKit.GetDurationFormatter(false)
        if fmt then binding:SetFormatter(fmt) end
        f._expiryBinding = binding
    end
    local p = db and db.profile.display
    SetABRFont(count, ResolveFontPath(), max(14, floor(((p and p.textSize) or 11) * 1.15)))
    count:SetTextColor(1, 1, 1, 1)
    f._expiryDuration:SetTimeFromEnd(expireAt, m.expireTotal)
    binding:SetEnabled(true)
    count:Show()
end

local ShowForeverGroupMenu
local iconPickerStyle
local ShowForeverFoodMenu

local function GetOrCreateIcon(index)
    if iconPool[index] then return iconPool[index] end
    -- SecureActionButtonTemplate for click-to-cast in combat
    local btn = CreateFrame("Button", "EABR_Icon"..index, iconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "MiddleButtonUp", "RightButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
    btn:SetFrameStrata(GetStrata())
    btn:Hide()

    -- Middle-click dismiss: hide this reminder until the next loading screen.
    -- Right-click on a multi-pet-cycle reminder previews the next pet without
    -- casting. On a clickable spell group it opens the spell picker.
    btn:HookScript("PostClick", function(self, button, down)
        if button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if self._dismissKey == "forever:wellfed" then
                EABR.SyncForeverFoodWatch(false)
            end
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        elseif button == "LeftButton" and self._requestKey and not down then
            EABR.SendBuffRequest(self._requestKey, self._requestName)
        elseif button == "RightButton" and self._petCycleTotal then
            EABR._petCycleIndex = ((EABR._petCycleIndex or 1) % self._petCycleTotal) + 1
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        elseif button == "RightButton" and self._foreverGroup and not InCombat() then
            ShowForeverGroupMenu(self)
        elseif button == "RightButton" and self._foreverFood and not InCombat() then
            ShowForeverFoodMenu(self)
        end
    end)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    EABR.ApplyIconBorder(btn, true)

    local text = EABR.GetIconTextOverlay(btn):CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetABRFont(text, ResolveFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text

    EABR.CreateIconCountOverlay(btn)
    EABR.CreateIconQualityOverlay(btn)
    EABR.CreateIconBagCountOverlay(btn)
    EABR.AttachIconHover(btn)
    EABR.AttachIconTooltip(btn)

    iconPool[index] = btn
    return btn
end

-- The four setters below suffix every action attribute with the "1" button, so
-- only a left click resolves them. An unsuffixed "type" is equivalent to
-- "*type*" and is inherited by every button, which is what let a middle-click
-- dismiss also fire the reminder; "*type2"/"*type3" set to ATTRIBUTE_NOOP did
-- not reliably outrank it.

-- Sets icon to a plain texture with no click action (clears cast attributes OOC).
local function SetIconTexture(btn, texture, label)
    if not InCombat() then
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = nil
end

local function SetIconSpell(btn, spellID, texture, label)
    if not InCombat() then
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", spellID)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", "player")
    end
    btn._icon:SetTexture(texture or Tex(spellID) or 134400)
    btn._tooltipSpell = spellID
    btn._tooltipItem = nil
end

local function SetIconItem(btn, itemID, texture, label)
    if not InCombat() then
        btn:SetAttribute("type1", "item")
        btn:SetAttribute("item1", "item:"..itemID)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("macrotext1", nil)
        btn:SetAttribute("unit1", nil)
    end
    btn._icon:SetTexture(texture or C_Item.GetItemIconByID(itemID) or 134400)
    btn._tooltipSpell = nil
    btn._tooltipItem = itemID
end

local function SetIconMacro(btn, macrotext, texture, spellID)
    if not InCombat() then
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", macrotext)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("item1", nil)
        btn:SetAttribute("unit1", nil)
    end
    btn._icon:SetTexture(texture or 134400)
    btn._tooltipSpell = spellID
    btn._tooltipItem = nil
end

local pickerSpellData = {}

function EABR.ForeverPickerSpellData(id, ranked)
    local data = pickerSpellData[id]
    if not data or (ranked and not data.rank) then
        local name = SpellName(id)
        if not name then return end
        local subtext = C_Spell.GetSpellSubtext(id)
        local rank = subtext and subtext:match("%d+")
        if subtext and subtext ~= "" then name = name .. "(" .. subtext .. ")" end
        -- A faded pooled button can still receive clicks during lockdown.
        data = { macro = "/cast [@player,nocombat] " .. name, rank = rank }
        -- Retry incomplete metadata for spells with more than one known rank.
        if rank or not ranked then pickerSpellData[id] = data end
    end
    return data.macro, data.rank
end

local function DrawPickerIcon(frame, texture, selected)
    if selected then
        local border = frame:AttachTexture()
        border:SetSize(38, 38)
        border:SetPoint("CENTER")
        border:SetColorTexture(1, 0.82, 0, 1)
    end
    local icon = frame:AttachTexture()
    icon:SetDrawLayer("ARTWORK", 1)
    icon:SetSize(34, 34)
    icon:SetPoint("CENTER")
    icon:SetTexture(texture or 134400)
end

local function ShowPickerGrid(btn, ids, IsCurrent, populate)
    if not (MenuUtil and MenuUtil.CreateContextMenu and MenuVariants
        and MenuConstants and MenuConstants.HorizontalGridDirection) then return end
    EABR.HideIconTooltip(btn)
    if not iconPickerStyle then
        local inset = { left = 4, right = 4, top = 4, bottom = 4 }
        local padding = { width = 0, height = 0 }
        iconPickerStyle = CreateFromMixins(MenuVariants.GetDefaultContextMenuMixin(), {
            GetInset = function() return inset end,
            GetChildExtentPadding = function() return padding end,
            Generate = function(frame)
                local background = frame:AttachTexture()
                background:SetAtlas("common-dropdown-bg")
                background:SetAllPoints()
                background:SetAlpha(0.925)
            end,
        })
    end
    local previousStyle = btn.menuMixin
    btn.menuMixin = iconPickerStyle
    local menu = MenuUtil.CreateContextMenu(btn, function(_, root)
        root:AddMenuReleasedCallback(function() EABR.ValidateOpenPicker = nil end)
        local columns = math.min(#ids, max(1, floor((UIParent:GetWidth() - 32) / 42)))
        root:SetGridMode(MenuConstants.HorizontalGridDirection, columns, 2)
        -- The context menu otherwise applies a minimum width meant for text rows.
        root:SetMaximumWidth(columns * 38 + 8)
        populate(root)
    end)
    btn.menuMixin = previousStyle
    if menu then
        EABR.ValidateOpenPicker = function()
            if not IsCurrent() then menu:Close() end
        end
    end
    if menu and not InputUtil.IsGamepadUIEnabled() then
        local point = menu:GetPoint()
        menu:ClearAllPoints()
        InputUtil.AnchorRegionToCursor(menu, point == "BOTTOMLEFT" and "BOTTOM" or "TOP")
    end
end

ShowForeverGroupMenu = function(btn)
    local group = btn._foreverGroup
    local profile = db.profile
    local forever = profile.forever
    local settings = group.settings
    if not group.actions then settings = group end
    local function SaveSettings()
        if not settings then
            settings = {}
            group.actions[group.key] = settings
            group.settings = settings
        end
        return settings
    end
    local ids, seen = {}, {}
    for _, spellID in ipairs(group.ids) do
        local castID, ranks = EABR.ForeverGroupCastSpell(group, spellID)
        if castID and (not group.actions or C_SpellBook.IsSpellKnown(castID)) then
            local index = seen[ranks]
            if not index then
                index = #ids + 1
                seen[ranks] = index
                ids[index] = spellID
            elseif settings and spellID == settings.castSpellID then
                ids[index] = spellID
            end
        end
    end
    local function IsSelected(spellID)
        return btn._tooltipSpell == EABR.ForeverGroupCastSpell(group, spellID)
    end
    local function IsCurrent()
        if InCombat() or db.profile ~= profile or profile.forever ~= forever or not (forever and forever.pickerEnabled)
            or btn._foreverGroup ~= group or not btn:IsVisible() then return false end
        if group.actions then
            return forever and forever.classBuffActions == group.actions and group.actions[group.key] == settings
        end
        return forever and forever.customGroups and tContains(forever.customGroups, group)
    end
    local function CanChange(spellID)
        return IsCurrent() and tContains(group.ids, spellID)
    end
    local function ApplySpell(id, ranked)
        local macro, rank = EABR.ForeverPickerSpellData(id, ranked)
        if not macro then return end
        SetIconMacro(btn, macro, Tex(id), id)
        EABR.ApplyIconBagCount(btn, nil, nil, nil, rank)
    end
    local function SelectSpell(spellID)
        if not CanChange(spellID) then return end
        local id, ranks = EABR.ForeverGroupCastSpell(group, spellID)
        if not id or (group.actions and not C_SpellBook.IsSpellKnown(id)) then return end
        SaveSettings().castSpellID = spellID
        ApplySpell(id, #ranks > 1)
    end
    local function AddRankControl(button, spellID)
        button:AddInitializer(function(frame)
            local badge = frame:AttachFontString()
            badge:SetFontObject(NumberFontNormalSmall)
            badge:SetDrawLayer("OVERLAY", 7)
            badge:SetWidth(30)
            badge:SetJustifyH("RIGHT")
            badge:SetPoint("CENTER", frame, "CENTER", 0, -10)
            local id, ranks = EABR.ForeverGroupCastSpell(group, spellID)
            if not id then return end
            local _, rank = EABR.ForeverPickerSpellData(id, #ranks > 1)
            badge:SetText(rank or "")
            if #ranks < 2 then return end
            frame:EnableMouseWheel(true)
            frame:SetScript("OnMouseWheel", function(_, delta)
                if delta == 0 or not CanChange(spellID) then return end
                local current, known, at = EABR.ForeverGroupCastSpell(group, spellID)
                if not current then return end
                local nextRank = at + (delta > 0 and 1 or -1)
                local nextID = known[nextRank]
                if not nextID or (group.actions and not C_SpellBook.IsSpellKnown(nextID)) then return end
                local _, rank = EABR.ForeverPickerSpellData(nextID, true)
                if nextRank < #known and not rank then return end
                local selected = btn._tooltipSpell == current
                if nextRank < #known then
                    local saved = SaveSettings()
                    if not saved.castRanks then saved.castRanks = {} end
                    saved.castRanks[spellID] = nextID
                elseif settings and settings.castRanks then
                    settings.castRanks[spellID] = nil
                    if not next(settings.castRanks) then settings.castRanks = nil end
                end
                if selected then ApplySpell(nextID, true) end
                badge:SetText(rank or "")
                if GameTooltip:IsOwned(frame) then GameTooltip:SetSpellByID(nextID) end
            end)
        end)
        button:AddResetter(function(frame)
            frame:SetScript("OnMouseWheel", nil)
            frame:EnableMouseWheel(false)
        end)
    end
    if #ids < 2 then return end
    ShowPickerGrid(btn, ids, IsCurrent, function(root)
        for _, id in ipairs(ids) do
            local button = root:CreateButton("", SelectSpell, id)
            button:AddInitializer(function(frame, description)
                local spellID = description:GetData()
                DrawPickerIcon(frame, Tex(spellID), IsSelected(spellID))
                return 38, 38
            end)
            button:SetTooltip(function(tooltip, description)
                local owner = tooltip:GetOwner()
                tooltip:SetOwner(owner, "ANCHOR_NONE")
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 4)
                local spellID = EABR.ForeverGroupCastSpell(group, description:GetData())
                if spellID then tooltip:SetSpellByID(spellID) end
            end)
            AddRankControl(button, id)
        end
    end)
end

local foodMacros
function EABR.ForeverFoodMacro(itemID)
    if not foodMacros then foodMacros = {} end
    local macro = foodMacros[itemID]
    if not macro then
        -- A faded pooled button can still receive clicks during lockdown.
        macro = "/use [nocombat] item:" .. itemID
        foodMacros[itemID] = macro
    end
    return macro
end

ShowForeverFoodMenu = function(btn)
    local profile = db.profile
    local fo = profile.forever
    local foods = btn._foreverFood
    local function IsCurrent()
        return not InCombat() and db.profile == profile and profile.forever == fo
            and fo and fo.pickerEnabled == true and fo.wellFed
            and foods and EABR.IsForeverFoodCurrent(foods) and btn._foreverFood == foods and btn:IsVisible()
    end
    if not IsCurrent() then return end
    local ids = {}
    for id in pairs(foods) do ids[#ids + 1] = id end
    if #ids == 0 then return end
    table.sort(ids)
    local function SelectFood(id)
        if not IsCurrent() or not foods[id] then return end
        local count = C_Item.GetItemCount(id)
        if not count or count <= 0 then return end
        fo.wellFedItem = id
        SetIconMacro(btn, EABR.ForeverFoodMacro(id), C_Item.GetItemIconByID(id))
        btn._tooltipItem = id
        EABR.ApplyIconBagCount(btn, count)
    end
    ShowPickerGrid(btn, ids, IsCurrent, function(root)
        for _, id in ipairs(ids) do
            local button = root:CreateButton("", SelectFood, id)
            button:AddInitializer(function(frame, description)
                local itemID = description:GetData()
                DrawPickerIcon(frame, C_Item.GetItemIconByID(itemID), btn._tooltipItem == itemID)
                local count = frame:AttachFontString()
                count:SetFontObject(NumberFontNormalSmall)
                count:SetDrawLayer("OVERLAY", 7)
                count:SetWidth(30)
                count:SetJustifyH("RIGHT")
                count:SetPoint("CENTER", frame, "CENTER", 0, -10)
                count:SetText(foods[itemID])
                return 38, 38
            end)
            button:SetTooltip(function(tooltip, description)
                tooltip:SetItemByID(description:GetData())
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Data-driven setup: eliminates per-refresh closure + table allocations
-------------------------------------------------------------------------------
-- Pre-allocated entry pool + data-driven setup (eliminates per-refresh closures)
local AcquireEntry, ResetEntryPool, ApplySetup
do
    local pool = {}
    local inUse = 0

    AcquireEntry = function()
        inUse = inUse + 1
        local e = pool[inUse]
        if not e then
            e = {}
            pool[inUse] = e
        end
        e.mode = nil; e.spellID = nil; e.itemID = nil; e.macro = nil
        e.texture = nil; e.label = nil; e.unit = nil; e.desaturated = false
        e.tooltipItem = nil
        e.cat = nil; e.data = nil; e.dismissKey = nil; e.petCycleTotal = nil
        e.isEating = nil; e.eatingExpirationTime = nil
        e.expireAt = nil; e.expireTotal = nil; e.expireSwipe = nil
        e.qualityAtlas = nil
        e.bagCount = nil
        e.substitute = nil
        e.groupHave = nil
        e.groupTotal = nil
        e.requestKey = nil; e.requestName = nil
        e.foreverGroup = nil
        e.spellRank = nil
        e.foreverFood = nil
        e.stackText = nil
        return e
    end

    ResetEntryPool = function()
        inUse = 0
    end

    ApplySetup = function(btn, m)
        local mode = m.mode
        if mode == "spell" then
            SetIconSpell(btn, m.spellID, m.texture or Tex(m.spellID), m.label)
            if m.unit and not InCombat() then
                btn:SetAttribute("unit1", m.unit)
            end
        elseif mode == "item" then
            SetIconItem(btn, m.itemID, m.texture, m.label)
        elseif mode == "macro" then
            SetIconMacro(btn, m.macro, m.texture or (m.spellID and Tex(m.spellID)), m.spellID)
            btn._tooltipItem = m.tooltipItem
        else -- "texture"
            SetIconTexture(btn, m.texture, m.label)
            if m.spellID then btn._tooltipSpell = m.spellID end
            if m.tooltipItem then btn._tooltipItem = m.tooltipItem end
        end
        btn._text:SetText(m.label or "")
        btn._icon:SetDesaturated(m.desaturated or false)
        btn._tooltipLabel = m.label or nil
    end
end

I.AcquireEntry, I.activeIcons, I.ApplyGlow = AcquireEntry, activeIcons, ApplyGlow
I.ApplySetup, I.combatActiveIcons = ApplySetup, combatActiveIcons
I.combatIconPool, I.cursorActiveIcons = combatIconPool, cursorActiveIcons
I.receiverIconPool = receiverIconPool
I.FadeOutSecureIcons, I.GetOrCreateIcon = FadeOutSecureIcons, GetOrCreateIcon
I.GetStrata, I.HideCombatIcons, I.HideCursorIcons = GetStrata, HideCombatIcons, HideCursorIcons
I.ICON_SIZE, I.iconPool, I.IsImportantBuff = ICON_SIZE, iconPool, IsImportantBuff
I.LayoutCombatIcons, I.LayoutCursorIcons = LayoutCombatIcons, LayoutCursorIcons
I.RemoveGlow, I.ResetEntryPool, I.ShowCombatIcon = RemoveGlow, ResetEntryPool, ShowCombatIcon
I.ShowCursorIcon, I.ReleaseCursorAnchor = ShowCursorIcon, ReleaseCursorAnchor
I.broken = false
