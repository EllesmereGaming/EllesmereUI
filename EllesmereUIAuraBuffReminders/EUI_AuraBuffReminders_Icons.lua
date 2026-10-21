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
local ResolveGlowTint, SetABRFont, Tex = I.ResolveGlowTint, I.SetABRFont, I.Tex
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

-- Talent icon state moved to EllesmereUIABR_TalentReminders.lua

-------------------------------------------------------------------------------
--  Combat Icon Pool -- non-secure frames for visual-only display during combat.
-------------------------------------------------------------------------------
local combatAnchor      -- created in OnEnable, follows iconAnchor position
I.combatAnchorSetters[#I.combatAnchorSetters + 1] = function(v) combatAnchor = v end
local combatIconPool = {}
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

        local p = db and db.profile and db.profile.display
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

local function GetOrCreateCombatIcon(index)
    if combatIconPool[index] then return combatIconPool[index] end
    local f = CreateFrame("Frame", "EABR_CombatIcon"..index, combatAnchor)
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
    combatIconPool[index] = f
    return f
end

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
    if EABR.SetProviderCastCombatVisible then
        EABR.SetProviderCastCombatVisible(false)
    end
    if combatAnchor then EllesmereUI.SetElementVisibility(combatAnchor, false) end
end

local function ShowCombatIcon(iconIdx, m)
    local f = GetOrCreateCombatIcon(iconIdx)
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
    local xOff = reserveSlot and (sz + spacing) or 0
    local pt = "TOPLEFT"
    if p.growDirection == "LEFT" and not reserveSlot then
        pt, xOff = "TOPRIGHT", -(count - 1) * (sz + spacing)
    end
    for i, f in ipairs(combatActiveIcons) do
        f:SetSize(sz, sz)
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
    local totalW = (count * sz) + ((count-1) * spacing)
    local startX = -(totalW/2) + (sz/2)
    for i, f in ipairs(cursorActiveIcons) do
        f:SetSize(sz, sz)
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
    btn:SetSize(sz, sz)
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
        EllesmereUI.Glows.StartSpecGlow(wrapper, spec, sz, sz, "icon")
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
    else
        f:EnableMouse(true)
        local hl = f:CreateTexture(nil, "OVERLAY")
        hl:SetAllPoints(icon)
        hl:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        hl:SetColorTexture(1, 1, 1, 0.2)
        hl:Hide()
        f:HookScript("OnEnter", function() hl:Show() end)
        f:HookScript("OnLeave", function() hl:Hide() end)
    end
    f._eabrHoverAttached = true
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

function EABR.ApplyIconBagCount(f, count, outOfStock, substitute)
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
    elseif showCount and count and count > 0 then
        f._bagCountShown = true
        fs:SetText(count)
        if substitute then
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
    -- casting (ShowIcon's pass-through toggle decides whether this reminder
    -- claims the click at all, vs letting it fall through like every other
    -- reminder does).
    btn:HookScript("PostClick", function(self, button)
        if button == "MiddleButton" and self._dismissKey then
            _dismissedUntilLoad[self._dismissKey] = true
            if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
        elseif button == "RightButton" and self._petCycleTotal then
            EABR._petCycleIndex = ((EABR._petCycleIndex or 1) % self._petCycleTotal) + 1
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
        e.qualityAtlas = nil
        e.bagCount = nil
        e.substitute = nil
        e.groupHave = nil
        e.groupTotal = nil
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
        end
        btn._text:SetText(m.label or "")
        btn._icon:SetDesaturated(m.desaturated or false)
        btn._tooltipLabel = m.label or nil
    end
end

I.AcquireEntry, I.activeIcons, I.ApplyGlow = AcquireEntry, activeIcons, ApplyGlow
I.ApplySetup, I.combatActiveIcons = ApplySetup, combatActiveIcons
I.combatIconPool, I.cursorActiveIcons = combatIconPool, cursorActiveIcons
I.FadeOutSecureIcons, I.GetOrCreateIcon = FadeOutSecureIcons, GetOrCreateIcon
I.GetStrata, I.HideCombatIcons, I.HideCursorIcons = GetStrata, HideCombatIcons, HideCursorIcons
I.ICON_SIZE, I.iconPool, I.IsImportantBuff = ICON_SIZE, iconPool, IsImportantBuff
I.LayoutCombatIcons, I.LayoutCursorIcons = LayoutCombatIcons, LayoutCursorIcons
I.RemoveGlow, I.ResetEntryPool, I.ShowCombatIcon = RemoveGlow, ResetEntryPool, ShowCombatIcon
I.ShowCursorIcon, I.ReleaseCursorAnchor = ShowCursorIcon, ReleaseCursorAnchor
I.broken = false
