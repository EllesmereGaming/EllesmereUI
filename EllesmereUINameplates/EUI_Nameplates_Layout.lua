if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Layout.lua
--
--  Setting getters (offsets, sizes, scales, slots, borders, class power
--  options), the glow aliases, the dispel glow and aura slot positioning.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs, type = ipairs, type
local PP = EllesmereUI.PP
local UnitIsPlayer = UnitIsPlayer
local GetTime = GetTime

local BAR_W, defaults = I.BAR_W, I.defaults

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

local function GetNameplateYOffset()
    return (p and p.nameplateYOffset) or defaults.nameplateYOffset
end
ns.GetNameplateYOffset = GetNameplateYOffset
local function GetStackSpacingScale()
    return (p and p.stackSpacingScale) or defaults.stackSpacingScale
end
ns.GetStackSpacingScale = GetStackSpacingScale
local function GetCastScale()
    return (p and p.castScale) or defaults.castScale
end
ns.GetCastScale = GetCastScale
local function GetTargetScale()
    return (p and p.targetScale) or defaults.targetScale
end
ns.GetTargetScale = GetTargetScale
local function GetHealthBarHeight()
    return (p and p.healthBarHeight) or defaults.healthBarHeight
end
ns.GetHealthBarHeight = GetHealthBarHeight
local function GetFriendlyHealthBarHeight()
    return (p and p.friendlyHealthBarHeight) or defaults.friendlyHealthBarHeight
end
ns.GetFriendlyHealthBarHeight = GetFriendlyHealthBarHeight
local function GetFriendlyHealthBarWidth()
    return (p and p.friendlyHealthBarWidth) or defaults.friendlyHealthBarWidth
end
ns.GetFriendlyHealthBarWidth = GetFriendlyHealthBarWidth
local function GetEnemyNameTextSize()
    -- Returns the font size of the top text slot (used for stacking gap calculations)
    return (p and p.textSlotTopSize) or defaults.textSlotTopSize or 10
end
ns.GetEnemyNameTextSize = GetEnemyNameTextSize
local function GetDebuffTextColor()
    local c = (p and p.debuffTimerColor) or defaults.debuffTimerColor
    return c.r, c.g, c.b, 1
end
ns.GetDebuffTextColor = GetDebuffTextColor

-- Nameplate glow styles (Pandemic, Dispel, Important Cast) in their saved
-- order: a view over the shared styles without Shape Glow (1 Pixel, 2 Action
-- Button, 3 Auto-Cast, 4 GCD, 5 Modern, 6 Classic). scale/previewScale are
-- nameplate preview-only fields layered over the shared entries.
ns.NP_GLOW_VIEW = EllesmereUI.Glows.MakeView({ 1, 2, 3, 5, 6, 7 }, {
    [2] = { scale = 1.36, previewScale = 1.28 },
    [4] = { scale = 1.47, previewScale = 1.47 },
    [5] = { scale = 1.34, previewScale = 1.34 },
    [6] = { scale = 1.47, previewScale = 1.47 },
})
local PANDEMIC_GLOW_STYLES = ns.NP_GLOW_VIEW.list
ns.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
-- Exposed cross-addon (e.g. CDM "Apply Pandemic Glow to all" sync) so styles translate by NAME,
-- never raw index: this list omits "Custom Shape Glow", so the same index differs per side.
if EllesmereUI then EllesmereUI.NameplatePandemicGlowStyles = PANDEMIC_GLOW_STYLES end

-- The engine aura containers have no duration-driven texture alpha, so no
-- pandemic glow renders on nameplate auras (EUI_Nameplates_AuraContainers.lua,
-- V1 deferred). Gates the CDM pandemic sync.
ns.NP_PandemicGlowRendered = false
EllesmereUI.NameplatePandemicGlowRendered = ns.NP_PandemicGlowRendered

-- PANDEMIC_GLOW_STYLES index -> shared EllesmereUI.Glows.STYLES index.
ns.NP_TO_SHARED_GLOW = ns.NP_GLOW_VIEW.toShared

local function GetPandemicGlowStyle()
    local raw = p and p.pandemicGlowStyle
    if raw == nil then return defaults.pandemicGlowStyle end
    if type(raw) == "number" then return raw end
    return 1
end
ns.GetPandemicGlowStyle = GetPandemicGlowStyle
local function GetPandemicGlowLines()
    return (p and p.pandemicGlowLines) or defaults.pandemicGlowLines
end
ns.GetPandemicGlowLines = GetPandemicGlowLines
local function GetPandemicGlowThickness()
    return (p and p.pandemicGlowThickness) or defaults.pandemicGlowThickness
end
ns.GetPandemicGlowThickness = GetPandemicGlowThickness
local function GetPandemicGlowSpeed()
    return (p and p.pandemicGlowSpeed) or defaults.pandemicGlowSpeed
end
ns.GetPandemicGlowSpeed = GetPandemicGlowSpeed

-- Offensive dispel capability: the shared parent detector (AuraKit), which
-- asks what the PLAYER knows, never what an aura is, so it keeps working in
-- restricted content.
do
    local AKd = EllesmereUI.AuraKit
    -- Capability picks the buff row's candidate filter, so a change has to
    -- rebuild the containers, not merely repaint them.
    AKd.OnOffensiveDispelChange(function()
        if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    end)

    -- canDispelMagic, canDispelEnrage. Consumed by the buff row to pick its
    -- candidate filter and by the glow gate.
    ns.GetOffensiveDispelTypes = function()
        return AKd.OffensiveDispelTypes()
    end

    ns.GetDispelGlow = function()
        return (p and p.dispelGlow) or defaults.dispelGlow
    end
    ns.GetDispelGlowStyle = function()
        local raw = p and p.dispelGlowStyle
        if raw == nil then return defaults.dispelGlowStyle end
        -- Out-of-range picks read (and render) as Action Button Glow; Blizzard
        -- Border sits outside the view.
        if type(raw) == "number" and (raw == EllesmereUI.Glows.STEALABLE_BORDER
           or (raw >= 1 and raw <= #ns.NP_GLOW_VIEW.list)) then
            return raw
        end
        return 2
    end
    -- Per-type colors. The buff row is split into a Magic group and a
    -- non-Magic (enrage) group, so the type is a property of the GROUP and
    -- resolves once at style-build time -- no per-aura read, which is what
    -- made the old ColorMixin-per-aura version impossible under 12.1.
    local TYPE_COLOR = {
        magic  = { r = 0.2, g = 0.6, b = 1.0 },
        enrage = { r = 1.0, g = 0.2, b = 0.2 },
    }
    function ns.GetDispelGlowUseTypeColor()
        local v = p and p.dispelGlowUseTypeColor
        if v == nil then v = defaults.dispelGlowUseTypeColor end
        return v == true
    end
    -- dispelType is "magic", "enrage", or nil for the undifferentiated row.
    ns.GetDispelGlowColor = function(dispelType)
        if dispelType and ns.GetDispelGlowUseTypeColor() then
            local c = TYPE_COLOR[dispelType]
            if c then return c.r, c.g, c.b end
        end
        -- Never customized = "default": no tint request (nil), the suite's
        -- default look (gold). An explicit swatch pick is stored and honored.
        local c = p and p.dispelGlowColor
        local mode = (p and p.dispelGlowColorMode) or (c and "custom" or "default")
        return EllesmereUI.Glows.ResolveColor(mode, c and c.r, c and c.g, c and c.b)
    end
    -- Full render spec for the dispel glow (live purge glow and its preview).
    ns.GetDispelGlowSpec = function(dispelType, out)
        out = out or {}
        local idx = ns.GetDispelGlowStyle()
        -- Blizzard Border sits outside the view and keeps Blizzard's own art
        -- until a colour is picked (ns.GetDispelBorderColor).
        if idx == EllesmereUI.Glows.STEALABLE_BORDER then
            out.style = idx
            out.r, out.g, out.b = ns.GetDispelBorderColor(dispelType)
        else
            out.style = ns.NP_TO_SHARED_GLOW[idx] or 2
            out.r, out.g, out.b = ns.GetDispelGlowColor(dispelType)
        end
        out.lines = p and p.dispelGlowLines
        out.thickness = p and p.dispelGlowThickness
        out.speed = p and p.dispelGlowSpeed
        local bgc = p and p.dispelGlowBackgroundColor
        out.bg = (p and p.dispelGlowBackground == true) or nil
        out.bgR, out.bgG, out.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
        return out
    end
    -- Blizzard Border tint: the glow colour, except the untouched default gold
    -- (the profile merge fills the key, so it is compared, not nil-tested)
    -- keeps Blizzard's own stealable art. Per-type colours always tint.
    ns.GetDispelBorderColor = function(dispelType)
        local r, g, b = ns.GetDispelGlowColor(dispelType)
        if dispelType and ns.GetDispelGlowUseTypeColor() then return r, g, b end
        local d = defaults.dispelGlowColor
        if r == nil or (d and r == d.r and g == d.g and b == d.b) then return nil, nil, nil end
        return r, g, b
    end
end
local function GetCastBarHeight()
    return (p and p.castBarHeight) or defaults.castBarHeight
end
ns.GetCastBarHeight = GetCastBarHeight
local function GetFocusCastHeight()
    return (p and p.focusCastHeight) or defaults.focusCastHeight
end
ns.GetFocusCastHeight = GetFocusCastHeight
local function GetShowCastIcon()
    if p and p.showCastIcon ~= nil then return p.showCastIcon end
    return defaults.showCastIcon
end
ns.GetShowCastIcon = GetShowCastIcon
local function GetCastIconScale()
    return (p and p.castIconScale) or defaults.castIconScale
end
ns.GetCastIconScale = GetCastIconScale
-- "Make Icon Part of the Bar": bar shifts right and narrows by the icon width so the icon
-- (anchored to the bar's left edge) sits inside the footprint instead of hanging off it.
function ns.GetCastIconInWidth()
    if p and p.castbarIconInWidth ~= nil then return p.castbarIconInWidth end
    return defaults.castbarIconInWidth
end
-- "Icon on Right": place the cast spell icon on the right of the bars.
function ns.GetCastIconOnRight()
    if p and p.castIconOnRight ~= nil then return p.castIconOnRight end
    return defaults.castIconOnRight
end
-- "Full Sized": icon is a square the combined height of the health + cast bar,
-- flush from the top of the health bar to the bottom of the cast bar.
function ns.GetCastIconFullSize()
    if p and p.castIconFullSize ~= nil then return p.castIconFullSize end
    return defaults.castIconFullSize
end
local function GetHideEnemyNameWhileCasting()
    if p and p.hideEnemyNameWhileCasting ~= nil then return p.hideEnemyNameWhileCasting end
    return defaults.hideEnemyNameWhileCasting
end

-- Position + size the cast bar within `footprintW` per the icon-in-width setting. A full-size
-- icon spans the health band too (which the cast bar cannot reserve), so in-width applies only
-- at normal size. Left icon: shift bar right into the reserved gap; right icon: fix left edge,
-- narrow only the right. iconW = castH * icon scale (rendered size).
function ns.LayoutCastBar(plate, footprintW, castH)
    local iconW = 0
    local shiftX = 0
    local w = footprintW
    local classic = ns.NP_Classic()
    -- Cast Bar Y Offset: + up, - down; `or` fallback only fires when nil (0 is truthy in Lua).
    local offsetY = (p and p.castBarOffsetY) or defaults.castBarOffsetY
    if classic then
        -- Classic WoW UI: the vanilla cast border hangs under the health
        -- border with its icon plate under the health border's plain end,
        -- so the bar shifts right by the two plates' difference, keeps the
        -- footprint (widened by that difference when the bars' heights
        -- differ) and sits the stock gap lower; the icon rides in the plate.
        local drop
        shiftX, w, drop = ns.NP_ClassicCastLayout(footprintW, GetHealthBarHeight(), castH)
        offsetY = offsetY + drop
    elseif GetShowCastIcon() and ns.GetCastIconInWidth() and not ns.GetCastIconFullSize() then
        iconW = castH * (GetCastIconScale() or 1)
        if not ns.GetCastIconOnRight() then
            shiftX = iconW
        end
    end
    plate.cast:ClearAllPoints()
    plate.cast:SetSize(math.max(1, w - iconW), castH)
    -- Snap to whole physical pixels at the plate's own scale (nameplates have their own scale
    -- stack, not UIParent's) so the health-bottom/cast-top gap stays constant instead of
    -- oscillating +/-1px as the plate slides to fractional screen positions.
    if offsetY ~= 0 and PP then
        local plateES = plate:GetEffectiveScale()
        local onePx = (plateES and plateES > 0) and (PP.perfect / plateES) or (PP.mult or 1)
        offsetY = math.floor(offsetY / onePx + 0.5) * onePx
    end
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", shiftX, offsetY)
    -- The cast bar's bottom edge below the health bar's: the bottom text slots
    -- drop by this while a cast shows (PlaceSlotText). Clamped at 0, so a cast
    -- bar raised above the health bar never lifts them.
    plate._castDrop = math.min(0, offsetY - castH)
    if ns._npBottomUsed and plate.AnchorBottomTexts and plate.cast:IsShown() then
        plate:AnchorBottomTexts()
    end
    if classic then ns.NP_ApplyClassicCastArt(plate, castH) end
end

-- Size + anchor the cast spell icon; always square. Normal: cast-bar height, hangs off the
-- bar's left (default) or right edge, top-aligned, scaled by Scale. Full: a (healthH + castH)
-- square anchored to a cast BOTTOM corner (top flush with health top) with scale forced to 1
-- to stay flush to both edges. Frame level fixed at creation (health+1), never touched here.
function ns.LayoutCastIcon(plate, castH)
    local icon = plate.castIconFrame
    local onRight = ns.GetCastIconOnRight()
    local xOff = (p and p.castIconOffsetX) or defaults.castIconOffsetX
    local yOff = (p and p.castIconOffsetY) or defaults.castIconOffsetY
    icon:ClearAllPoints()
    if ns.NP_Classic() then
        -- Classic WoW UI: the icon in the vanilla cast border's plate, a
        -- fixed square at the plate's centre (the border's middle sits half
        -- a sheet row under the bar's); the offsets still nudge it.
        local C = ns.NP_CLASSIC
        local ix, iy = ns.NP_ClassicIconOffset(castH)
        icon:SetScale(1)
        icon:SetSize(C.icon * castH, C.icon * castH)
        icon:SetPoint("CENTER", plate.cast, "LEFT", ix + xOff, iy + yOff)
        return
    end
    if ns.GetCastIconFullSize() then
        local side = GetHealthBarHeight() + castH
        icon:SetScale(1)
        -- Link the icon's three shared edges DIRECTLY to the bar edges (top=health top,
        -- bottom=cast bottom, inner side=bars' outer edge) instead of deriving from its own
        -- size: anchored to the same points the health/cast borders use, they pixel-snap
        -- together and shift as ONE unit instead of rounding independently. SetWidth keeps it
        -- square (height is fixed by the top/bottom anchors = side).
        icon:SetWidth(side)
        if onRight then
            icon:SetPoint("TOPLEFT", plate.health, "TOPRIGHT", xOff, yOff)
            icon:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMRIGHT", xOff, yOff)
        else
            icon:SetPoint("TOPRIGHT", plate.health, "TOPLEFT", xOff, yOff)
            icon:SetPoint("BOTTOMRIGHT", plate.cast, "BOTTOMLEFT", xOff, yOff)
        end
    else
        icon:SetScale(GetCastIconScale() or 1)
        icon:SetSize(castH, castH)
        if onRight then
            icon:SetPoint("TOPLEFT", plate.cast, "TOPRIGHT", xOff, yOff)
        else
            icon:SetPoint("TOPRIGHT", plate.cast, "TOPLEFT", xOff, yOff)
        end
    end
end

-- How far the cast icon protrudes past the bar edge, plus that side ("left"/"right"). The
-- target arrow + side-slot core icons reserve this so they never land under the icon. Returns
-- 0 for left/normal and in-width-tucked icons. Optional `plate` matters only for the full-size
-- icon (a cast-bar child rendered only during a cast): its reserve is gated on the cast bar
-- being shown; a settings-only query (no plate) assumes the space is reserved.
function ns.GetCastIconReserve(plate)
    if not GetShowCastIcon() then return 0, nil end
    -- Classic WoW UI seats the icon inside the cast border's own plate, which
    -- ns.NP_ClassicBarReserve already accounts for, so a stored Icon on Right
    -- or Full Sized reserves a gap nothing occupies there.
    if ns.NP_Classic() then return 0, nil end
    local onRight = ns.GetCastIconOnRight()
    local side = onRight and "right" or "left"
    if ns.GetCastIconFullSize() then
        -- Reserve the full-size icon's footprint only while visible (cast bar up), so side
        -- elements sit flush against the bar when idle instead of shoved out by a phantom gap.
        if plate and plate.cast and not plate.cast:IsShown() then
            return 0, side
        end
        return GetHealthBarHeight() + GetCastBarHeight(), side
    end
    if onRight and not ns.GetCastIconInWidth() then
        return GetCastBarHeight() * (GetCastIconScale() or 1), side
    end
    return 0, side
end
local function GetKickTickEnabled()
    if p and p.kickTickEnabled ~= nil then return p.kickTickEnabled end
    return true
end
ns.GetKickTickEnabled = GetKickTickEnabled
local function GetKickTickColor()
    local c = (p and p.kickTickColor) or defaults.kickTickColor
    return c.r, c.g, c.b
end
ns.GetKickTickColor = GetKickTickColor
-- Optional element ("debuffs", "buffs", "ccs") selects per-element spacing; no arg
-- falls back to the global auraSpacing. One function, not two locals (200-local cap).
local function GetAuraSpacing(element)
    if element == "debuffs" then
        return (p and p.debuffSpacing) or defaults.debuffSpacing
    elseif element == "buffs" then
        return (p and p.buffSpacing) or defaults.buffSpacing
    elseif element == "ccs" then
        return (p and p.ccSpacing) or defaults.ccSpacing
    end
    return (p and p.auraSpacing) or defaults.auraSpacing
end
ns.GetAuraSpacing = GetAuraSpacing
local function GetDebuffYOffset()
    return (p and p.debuffYOffset) or defaults.debuffYOffset
end
ns.GetDebuffYOffset = GetDebuffYOffset
local function GetSideAuraXOffset()
    return (p and p.sideAuraXOffset) or defaults.sideAuraXOffset
end
ns.GetSideAuraXOffset = GetSideAuraXOffset
local function GetRaidMarkerPos()
    return (p and p.raidMarkerPos) or defaults.raidMarkerPos
end
ns.GetRaidMarkerPos = GetRaidMarkerPos
local function GetRaidMarkerSize()
    local pos = (p and p.raidMarkerPos) or defaults.raidMarkerPos
    if pos == "none" then return defaults.raidMarkerSize or 24 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 24
end
ns.GetRaidMarkerSize = GetRaidMarkerSize
local function GetRaidMarkerYOffset()
    return 0
end
ns.GetRaidMarkerYOffset = GetRaidMarkerYOffset
local function GetClassificationSlot()
    return (p and p.classificationSlot) or defaults.classificationSlot
end
ns.GetClassificationSlot = GetClassificationSlot
local function GetRareEliteIconSize()
    local pos = (p and p.classificationSlot) or defaults.classificationSlot
    if pos == "none" then return defaults.rareEliteIconSize or 20 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 20
end
ns.GetRareEliteIconSize = GetRareEliteIconSize
-- Faction badge slot and size (same per-slot size as every Core Positions element).
-- With "Rare/Quest + Faction" the badge rides the classification slot.
function ns.NP_GetFactionSlot()
    if p and p.classificationIncludeFaction then return GetClassificationSlot() end
    return (p and p.factionSlot) or defaults.factionSlot
end
function ns.NP_GetFactionIconSize()
    local pos = ns.NP_GetFactionSlot()
    if pos == "none" then return 20 end
    return (p and p[pos .. "SlotSize"]) or defaults[pos .. "SlotSize"] or 20
end
function ns.NP_GetFactionStyle()
    return (p and p.factionStyle) or defaults.factionStyle
end
-- Which faction badge a unit gets: its faction ("Horde"/"Alliance", drawn with
-- EllesmereUI.SetFactionArt in the Icon Style) and whether to dim it, or nil for none.
-- Neutral units and unreadable (secret) values show nothing; an unreadable PvP flag
-- counts as flagged, so nothing is hidden or greyed on a guess. Faction NPCs count
-- unless Players Only is on. Art matches Blizzard's Forever target frame badge.
function ns.NP_FactionBadge(unit)
    if not unit or ns.NP_GetFactionSlot() == "none" then return nil end
    -- Both toggles default off, so an unset key reads the same as its default.
    if p and p.factionPlayersOnly then
        local isPlayer = UnitIsPlayer(unit)
        if issecretvalue(isPlayer) or not isPlayer then return nil end
    end
    local fac = UnitFactionGroup(unit)
    if issecretvalue(fac) or (fac ~= "Horde" and fac ~= "Alliance") then return nil end
    if p and p.factionOppositeOnly then
        local mine = UnitFactionGroup("player")
        if issecretvalue(mine) then return nil end
        -- Mercenary mode: the player fights for the other faction.
        if UnitIsMercenary("player") then
            if mine == "Horde" then mine = "Alliance" elseif mine == "Alliance" then mine = "Horde" end
        end
        if mine == fac then return nil end
    end
    local dim = false
    local pvpMode = (p and p.factionPvP) or defaults.factionPvP
    if pvpMode ~= "ignore" then
        local pvp = UnitIsPVP(unit)
        local unflagged = not issecretvalue(pvp) and not pvp
        if unflagged and pvpMode == "only" then return nil end
        dim = unflagged and pvpMode == "dim"
    end
    return fac, dim
end
local function GetNameYOffset()
    return (p and p.nameYOffset) or defaults.nameYOffset
end
ns.GetNameYOffset = GetNameYOffset
local textSlotKeys = { "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
    "textSlotBottomLeft", "textSlotBottomRight" }
ns.textSlotKeys = textSlotKeys
-- The slots that share the bar's line for the name-width estimate.
ns._npBarTextKeys = { "textSlotRight", "textSlotLeft", "textSlotCenter" }

local function GetTextSlot(slotKey)
    return (p and p[slotKey]) or defaults[slotKey]
end
ns.GetTextSlot = GetTextSlot

local function FindSlotForElement(element)
    for _, key in ipairs(textSlotKeys) do
        if GetTextSlot(key) == element then return key end
    end
    return nil
end
ns.FindSlotForElement = FindSlotForElement

-- The four combined health-text elements (percent + number, either order, "|" or "-"
-- separator). One set so every eligibility check treating them as one category stays in sync.
local COMBO_HEALTH_ELEMENTS = {
    healthPctNum     = true, healthNumPct     = true,
    healthPctNumDash = true, healthNumPctDash = true,
    healthNumMax     = true,  -- current / max number; no percent
}
local function IsComboHealthText(element)
    return COMBO_HEALTH_ELEMENTS[element] == true
end
ns.IsComboHealthText = IsComboHealthText

local function SetCombinedHealthText(fs, element, pctText, numText, maxText)
    if element == "healthNumMax" then
        fs:SetFormattedText("%s / %s", numText, maxText or "")
    elseif element == "healthPctNum" then
        fs:SetFormattedText("%s | %s", pctText, numText)
    elseif element == "healthNumPct" then
        fs:SetFormattedText("%s | %s", numText, pctText)
    elseif element == "healthPctNumDash" then
        fs:SetFormattedText("%s - %s", pctText, numText)
    elseif element == "healthNumPctDash" then
        fs:SetFormattedText("%s - %s", numText, pctText)
    else
        fs:SetText("")
    end
end
ns.SetCombinedHealthText = SetCombinedHealthText

-- Name-family text elements: display variants rendered by the plate's single name FontString
-- (enemy name and level+name combos). Exactly one may occupy a slot at a time (enforced by the
-- options-side slot assignment). STANDALONE level is deliberately NOT in the family: it renders
-- on its own FontString (plate.levelText, via health-text slot machinery) so name and level can
-- occupy different slots. do/end + ns funcs: no new locals (cap).
do
    local NAME_FAMILY = {
        enemyName = true, levelName = true, nameLevel = true,
    }
    -- Per slot: its Text Coloring key names (prebuilt, so reads build no strings) and
    -- the materialized Level | Name / Name | Level format strings (NP_RefreshSlotNameParts).
    local SK, PARTS = {}, {}
    local PLAIN = { ln = "%s | %s", nl = "%s | %s", diff = false }
    for i = 1, #textSlotKeys do
        local s = textSlotKeys[i]
        SK[s] = {
            mode = s .. "ColorMode", class = s .. "ClassColor", color = s .. "Color",
            nameOn = s .. "NameColorOn", name = s .. "NameColor",
            lvlOn = s .. "LevelColorOn", lvl = s .. "LevelColor", diff = s .. "LevelDiffOn",
        }
        PARTS[s] = { ln = PLAIN.ln, nl = PLAIN.nl, diff = false }
    end
    function ns.IsNameElement(element)
        return NAME_FAMILY[element] == true
    end
    -- Slot currently holding a name-family element (nil when none is slotted).
    -- db: a profile to read instead of the live one.
    function ns.FindNameSlot(db)
        db = db or p
        for _, key in ipairs(textSlotKeys) do
            if NAME_FAMILY[(db and db[key]) or defaults[key]] then return key end
        end
        return nil
    end
    -- A slot's Core Text Coloring mode: "custom" (the slot colour),
    -- "class" (Hostility / Class, painted per unit) or "level" (Level Difficulty, the
    -- unit's level difficulty colour; any text but Target of Target, which names
    -- another unit). An unset <slot>ColorMode is derived from keys read
    -- here and never written: levelDifficultyColor makes a standalone level "level";
    -- <slot>ClassColor, or enemyNameTextReactionColor on the first name slot, makes
    -- "class". The one place modes are derived. db: a profile to read instead of the
    -- live one.
    function ns.NP_SlotColorMode(slotKey, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return "custom" end
        local el = db[slotKey] or defaults[slotKey]
        local m = db[k.mode]
        if m == "class" or m == "custom" then return m end
        if m == "level" then return (el ~= "targetOfTarget") and "level" or "custom" end
        if el == "level" and db.levelDifficultyColor == true then return "level" end
        if db[k.class] == true then return "class" end
        if db.enemyNameTextReactionColor == true and NAME_FAMILY[el]
            and ns.FindNameSlot(db) == slotKey then
            return "class"
        end
        return "custom"
    end
    -- Level | Name / Name | Level: the level part in the difficulty colour (applies
    -- while the slot's mode is not "level"). A custom level colour turns it off; unset
    -- follows levelDifficultyColor.
    function ns.NP_SlotLevelDiff(slotKey, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return false end
        if db[k.lvlOn] == true then return false end
        local v = db[k.diff]
        if v ~= nil then return v == true end
        return db.levelDifficultyColor == true
    end
    -- A combo part's stored colour (part "name" or "level"), falling back to the slot
    -- colour; r, g, b. Whether it applies is <slot>NameColorOn / <slot>LevelColorOn.
    function ns.NP_SlotPartColor(slotKey, part, db)
        db = db or p or defaults
        local k = SK[slotKey]
        if not k then return 1, 1, 1 end
        local c = db[part == "level" and k.lvl or k.name] or db[k.color] or defaults[k.color]
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
    -- Materializes every slot's combo format strings: a part with a custom colour is
    -- wrapped in its escape inside the format (the name stays a %s argument), and diff
    -- marks a level part drawn in the difficulty colour. Run by NP_RefreshSlotClassFlags.
    function ns.NP_RefreshSlotNameParts()
        local db = p or defaults
        for i = 1, #textSlotKeys do
            local s = textSlotKeys[i]
            local k, f = SK[s], PARTS[s]
            local nm, lv = "%s", "%s"
            if db[k.nameOn] == true then
                nm = EllesmereUI.HexColor(ns.NP_SlotPartColor(s, "name", db)) .. "%s|r"
            end
            if db[k.lvlOn] == true then
                lv = EllesmereUI.HexColor(ns.NP_SlotPartColor(s, "level", db)) .. "%s|r"
            end
            f.ln = lv .. " | " .. nm
            f.nl = nm .. " | " .. lv
            f.diff = ns.NP_SlotColorMode(s, db) ~= "level" and ns.NP_SlotLevelDiff(s, db)
        end
    end
    -- r, g, b for a readable level: the skull's colour below 0, else the difficulty
    -- colour (nil when attackability or the player's level is secret). "player" is the
    -- options preview's stand-in mob, ranked as attackable like a hostile mob.
    local function LevelRGB(unit, lvl)
        if lvl < 0 then return EllesmereUI.GetLevelDifficultyColor(-1) end
        return EllesmereUI.GetLevelColor(unit, lvl,
            unit == "player" or (p and p.levelDifficultyColorFriendly))
    end
    -- The unit's level difficulty colour, r, g, b; nil while its level cannot be read.
    function ns.NP_UnitLevelColor(unit)
        local lvl = UnitEffectiveLevel(unit)
        if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then return nil end
        return LevelRGB(unit, lvl)
    end
    -- Display string for the unit's EFFECTIVE level (so scaling/Chromie time read as the game
    -- ranks them). "??" for skull-ranked (-1) or unreadable (secret) levels, matching default UI.
    -- color "diff" wraps it in the difficulty colour (an unreadable level stays a plain
    -- "??"); any other value returns it plain.
    function ns.GetUnitLevelText(unit, color)
        local lvl = UnitEffectiveLevel(unit)
        if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl)) then
            return "??"
        end
        local txt = lvl < 0 and "??" or tostring(lvl)
        if color == "diff" then return EllesmereUI.ColorText(txt, LevelRGB(unit, lvl)) end
        return txt
    end
    -- Write a name-family element's text into a FontString (shared by runtime update and
    -- options preview). name may be SECRET: only ever passed as a %s display arg, never inspected.
    -- slotKey (nil = FindNameSlot's) picks the combo's materialized part colours; the rest
    -- of the text keeps the font string's colour.
    function ns.SetNameElementText(fs, element, name, unit, slotKey)
        if element == "levelName" or element == "nameLevel" then
            local f = PARTS[slotKey or ns.FindNameSlot()] or PLAIN
            local lvl = ns.GetUnitLevelText(unit, f.diff and "diff")
            if element == "levelName" then
                fs:SetFormattedText(f.ln, lvl, name)
            else
                fs:SetFormattedText(f.nl, name, lvl)
            end
        elseif element == "level" then
            fs:SetFormattedText("%s", ns.GetUnitLevelText(unit))
        else
            fs:SetText(name)
        end
    end
    -- WoW Forever: the name slot's Name Format (text-slot cog), the first or last word
    -- of the name; unset shows it whole. Defined only on Forever, so retail's name
    -- write pays one nil check. Keys prebuilt (no per-update string building); the
    -- split, its secret pass-through and its bounded cache live in ForeverShortName.
    if EllesmereUI.IS_FOREVER then
        local NAME_FORMAT_KEYS = {
            textSlotTop  = "textSlotTopNameFormat",  textSlotRight  = "textSlotRightNameFormat",
            textSlotLeft = "textSlotLeftNameFormat", textSlotCenter = "textSlotCenterNameFormat",
            textSlotBottomLeft  = "textSlotBottomLeftNameFormat",
            textSlotBottomRight = "textSlotBottomRightNameFormat",
        }
        local short = EllesmereUI.ForeverShortName
        function ns.NP_FormatName(name, slotKey)
            local key = slotKey and NAME_FORMAT_KEYS[slotKey]
            local mode = key and p and p[key]
            if mode then return short(name, mode) end
            return name
        end
    end
end

-- Estimate pixel width of health text per element. Actual rendered widths are
-- unreadable (secret values), so use flat worst-case pixel assumptions.
local HEALTH_TEXT_PADDING = 10  -- safety margin in px
local healthTextWidths = {
    healthPercent       = 38,
    healthPercentNoSign = 38,
    healthNumber  = 38,
    healthPctNum  = 75,
    healthNumPct  = 75,
    healthPctNumDash = 75,
    healthNumPctDash = 75,
    healthNumMax  = 75,
    level = 24,   -- standalone level: "70" / "??"
    targetOfTarget = 60,
}
local function EstimateHealthTextWidth(element)
    return (healthTextWidths[element] or 0) + HEALTH_TEXT_PADDING
end
ns.EstimateHealthTextWidth = EstimateHealthTextWidth

local function GetHealthBarWidth()
    local extra = (p and p.healthBarWidth) or defaults.healthBarWidth
    return BAR_W + extra
end
ns.GetHealthBarWidth = GetHealthBarWidth

-- Y offset for plate content relative to the nameplate frame. Always 0: the Blizzard nameplate
-- frame grows from its CENTER, not its base, so a taller SetNamePlateSize enlarges the hitbox
-- evenly above AND below the unit; anchoring content at the frame center needs no compensation.
local function GetHitboxYShift()
    return 0
end
ns.GetHitboxYShift = GetHitboxYShift
-- Slot-based size/offset getters. Key strings memoized per posKey (closed set of six literals,
-- lazy-filled) so these hot getters allocate nothing; VALUES still read live so profile swaps cannot stale.
ns._slotKeyMemo = ns._slotKeyMemo or {}
local function GetSlotKeys(posKey)
    local m = ns._slotKeyMemo[posKey]
    if not m then
        m = {
            size = posKey .. "SlotSize",
            x    = posKey .. "SlotXOffset",
            y    = posKey .. "SlotYOffset",
        }
        ns._slotKeyMemo[posKey] = m
    end
    return m
end
local function GetSlotSize(posKey)
    local m = GetSlotKeys(posKey)
    return (p and p[m.size]) or defaults[m.size] or 24
end
ns.GetSlotSize = GetSlotSize
local function GetSlotOffsets(posKey)
    local m = GetSlotKeys(posKey)
    local xOff = (p and p[m.x]) or defaults[m.x] or 0
    local yOff = (p and p[m.y]) or defaults[m.y] or 0
    return xOff, yOff
end
ns.GetSlotOffsets = GetSlotOffsets
local function GetDebuffIconSize()
    local slot = (p and p.debuffSlot) or defaults.debuffSlot
    if slot == "none" then return defaults.debuffIconSize or 26 end
    return GetSlotSize(slot)
end
ns.GetDebuffIconSize = GetDebuffIconSize
local function GetBuffIconSize()
    local slot = (p and p.buffSlot) or defaults.buffSlot
    if slot == "none" then return defaults.buffIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetBuffIconSize = GetBuffIconSize
local function GetCCIconSize()
    local slot = (p and p.ccSlot) or defaults.ccSlot
    if slot == "none" then return defaults.ccIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetCCIconSize = GetCCIconSize
-- Cropped aura icons (mirrors Unit Frames "Cropped Icons"). On: icon frame goes rectangular
-- (height = 80% of width), texture trimmed top/bottom so artwork is never squished; horizontal
-- zoom stays at the nameplate default (0.08). do/end + ns functions: no new main-chunk locals (cap).
do
    local AURA_CROP_HEIGHT = 0.80
    local AURA_ZOOM = 0.08
    -- Returns FALSE when uncropped, else the height FACTOR: 1 - 2*(cropPercent/100), so default
    -- 10% yields 0.80. Callers that only truth-test the result work unchanged.
    function ns.GetAuraCrop(element)
        local on, pct
        if element == "debuffs" then
            on = (p and p.debuffCropIcons) or defaults.debuffCropIcons
            pct = p and p.debuffCropPercent
        elseif element == "buffs" then
            on = (p and p.buffCropIcons) or defaults.buffCropIcons
            pct = p and p.buffCropPercent
        elseif element == "ccs" then
            on = (p and p.ccCropIcons) or defaults.ccCropIcons
            pct = p and p.ccCropPercent
        end
        if not on then return false end
        pct = tonumber(pct) or 10
        if pct < 5 then pct = 5 elseif pct > 25 then pct = 25 end
        return 1 - 2 * (pct / 100)
    end
    -- Frame height for an icon width: shorter when cropped, square when not. `cropped` is
    -- GetAuraCrop's result: a factor number, or plain true (falls back to AURA_CROP_HEIGHT).
    function ns.GetAuraCropHeight(cropped, w)
        if cropped then
            local factor = (type(cropped) == "number") and cropped or AURA_CROP_HEIGHT
            return math.floor(w * factor + 0.5)
        end
        return w
    end
    -- Texcoord trim. Cropped scales the vertical span to the rectangle's aspect
    -- so the texture keeps its proportions; uncropped is the original square zoom.
    function ns.SetAuraIconCrop(icon, cropped, w, h)
        if not icon then return end
        -- Stock styles draw the whole icon (zoom 0), as the engine cells do.
        local z = ns.NP_Blizz() and 0 or AURA_ZOOM
        if cropped and w and h and w > 0 then
            local uSpan = 1 - 2 * z
            local vSpan = uSpan * (h / w)
            local v0 = 0.5 - vSpan / 2
            icon:SetTexCoord(z, 1 - z, v0, 1 - v0)
        else
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
    -- Size + crop a single aura slot and its icon together so they never drift
    -- out of sync. Returns the applied width and height for spacing/positioning.
    function ns.ApplyAuraSlotCrop(slot, cropped, sizeW)
        local h = ns.GetAuraCropHeight(cropped, sizeW)
        PP.Size(slot, sizeW, h)
        ns.SetAuraIconCrop(slot.icon, cropped, sizeW, h)
        return sizeW, h
    end
end
local function GetTargetGlowStyle()
    if p and p.targetGlowStyle then return p.targetGlowStyle end
    return defaults.targetGlowStyle
end
ns.GetTargetGlowStyle = GetTargetGlowStyle
-- Multi-toggle target glow model (EllesmereUI / Border Color / Highlight). Live conversion, NO
-- migration: each toggle returns its own stored key when set, else derives from targetGlowStyle
-- (stays in defaults so the fallback source is always present). Mapping: ellesmereui ->
-- EllesmereUI; vibrant -> EllesmereUI + Border Color; none -> nothing. On ns (local budget).
function ns.GetTargetGlowEllesmereUI()
    if p and p.targetGlowEllesmereUI ~= nil then return p.targetGlowEllesmereUI end
    local style = (p and p.targetGlowStyle) or defaults.targetGlowStyle
    return style == "ellesmereui" or style == "vibrant"
end
function ns.GetTargetGlowBorderColor()
    if p and p.targetGlowBorderColor ~= nil then return p.targetGlowBorderColor end
    local style = (p and p.targetGlowStyle) or defaults.targetGlowStyle
    return style == "vibrant"
end
function ns.GetTargetGlowHighlight()
    if p and p.targetGlowHighlight ~= nil then return p.targetGlowHighlight end
    return false  -- no legacy equivalent
end
function ns.GetTargetGlowBorderSize()
    if p and p.targetGlowBorderSize ~= nil then return p.targetGlowBorderSize end
    return false  -- no legacy equivalent
end
-- nil until the effect's first enable snapshots the user's current border size (options side);
-- nil = applies nothing (fail-safe for imported partial profiles).
function ns.GetTargetBorderSizeValue()
    local v = p and p.targetBorderSizeValue
    return v
end
function ns.GetTargetBorderColor()
    return (p and p.targetBorderColor) or defaults.targetBorderColor
end
function ns.GetTargetGlowColor()
    return (p and p.targetGlowColor) or defaults.targetGlowColor
end
function ns.GetTargetGlowAlpha()
    local a = p and p.targetGlowAlpha
    if a == nil then return defaults.targetGlowAlpha end
    return a
end
function ns.GetTargetHighlightColor()
    return (p and p.targetHighlightColor) or defaults.targetHighlightColor
end
function ns.GetTargetHighlightAlpha()
    local a = p and p.targetHighlightAlpha
    if a == nil then return defaults.targetHighlightAlpha end
    return a
end
-- Hover Effect (mirrors the Target Effect model, user-directed 2026-08-16).
-- Highlight is the ONLY default-on channel and reuses the legacy
-- hoverColor/hoverAlpha keys as its color/opacity, so every existing AND new
-- profile renders EXACTLY the old flat hover highlight (including the alpha
-- 0 = invisible case) until other channels are opted in. New-channel colors
-- start from the target effect's defaults.
function ns.GetHoverGlowEllesmereUI() return (p and p.hoverGlowEllesmereUI) == true end
function ns.GetHoverGlowBorderColor() return (p and p.hoverGlowBorderColor) == true end
function ns.GetHoverGlowHighlight()
    if p and p.hoverGlowHighlight ~= nil then return p.hoverGlowHighlight == true end
    return true
end
function ns.GetHoverGlowBorderSize() return (p and p.hoverGlowBorderSize) == true end
-- nil until the effect's first enable snapshots the user's current border
-- size (options side); nil = applies nothing.
function ns.GetHoverBorderSizeValue() return p and p.hoverBorderSizeValue end
function ns.GetHoverBorderColor()
    return (p and p.hoverBorderColor) or defaults.targetBorderColor
end
function ns.GetHoverGlowColor()
    return (p and p.hoverGlowColor) or defaults.targetGlowColor
end
function ns.GetHoverGlowAlpha()
    local a = p and p.hoverGlowAlpha
    if a == nil then return defaults.targetGlowAlpha end
    return a
end
local function GetShowTargetGlow()
    return ns.GetTargetGlowEllesmereUI() or ns.GetTargetGlowBorderColor() or ns.GetTargetGlowHighlight()
end
ns.GetShowTargetGlow = GetShowTargetGlow
local function GetShowClassPower()
    if p and p.showClassPower ~= nil then return p.showClassPower end
    return defaults.showClassPower
end
ns.GetShowClassPower = GetShowClassPower
-- On ns, not file locals (Lua's 200-local limit); callers use ns.GetClassPower*().
ns.GetClassPowerPos = function()
    return (p and p.classPowerPos) or defaults.classPowerPos
end
ns.GetClassPowerYOffset = function()
    return (p and p.classPowerYOffset) or defaults.classPowerYOffset
end
ns.GetClassPowerXOffset = function()
    return (p and p.classPowerXOffset) or defaults.classPowerXOffset
end
ns.GetClassPowerScale = function()
    return (p and p.classPowerScale) or defaults.classPowerScale
end
ns.GetClassPowerGap = function()
    return (p and p.classPowerGap) or defaults.classPowerGap
end
local function GetClassPowerClassColors()
    if p and p.classPowerClassColors ~= nil then return p.classPowerClassColors end
    return defaults.classPowerClassColors
end
ns.GetClassPowerClassColors = GetClassPowerClassColors
local function GetClassPowerCustomColor()
    local c = (p and p.classPowerCustomColor) or defaults.classPowerCustomColor
    return c
end
ns.GetClassPowerCustomColor = GetClassPowerCustomColor
ns.GetClassPowerBgColor = function()
    local c = (p and p.classPowerBgColor) or defaults.classPowerBgColor
    return c
end
ns.GetClassPowerEmptyColor = function()
    local c = (p and p.classPowerEmptyColor) or defaults.classPowerEmptyColor
    return c
end
-- On ns, not file locals (Lua's 200 main-chunk local limit).
function ns.GetClassPowerShape()
    return (p and p.classPowerShape) or defaults.classPowerShape
end
function ns.GetClassPowerBorder()
    local v = p and p.classPowerBorder
    if v == nil then return defaults.classPowerBorder end
    return v
end
function ns.GetClassPowerBorderColor()
    return (p and p.classPowerBorderColor) or defaults.classPowerBorderColor
end
function ns.GetClassPowerBorderSize()
    return (p and p.classPowerBorderSize) or defaults.classPowerBorderSize
end
local function IsBorderEnabled()
    -- The stock styles carry their own art instead of an EUI border: the
    -- stock background art (Blizzard Style), the vanilla border sheets
    -- (Classic WoW UI, ns.NP_ApplyClassicHealthArt).
    if ns.NP_Blizz() then return false end
    local v = p and p.showBorder
    if v == nil then return defaults.showBorder end
    return v
end
ns.IsBorderEnabled = IsBorderEnabled
-- Per-icon 1px borders (cast / buff / debuff / CC). nil = border shown
-- (old profiles without the key keep their borders). Setting a hide key
-- to true hides the border; false shows it.
function ns.GetIconBorderEnabled(kind)
    -- Stock styles: the stock cast icon has no border, and the aura items
    -- carry the rounded ring overlay (Blizzard) or the stock dispel-type
    -- border (classic) instead of a 1px border.
    if ns.NP_Blizz() then return false end
    local key
    if kind == "cast" then
        key = "hideCastIconBorder"
    elseif kind == "debuffs" then
        key = "hideDebuffIconBorder"
    elseif kind == "buffs" then
        key = "hideBuffIconBorder"
    else
        key = "hideCCIconBorder"
    end
    local v = p and p[key]
    if v == nil then
        v = defaults[key]
        if v == nil then return true end  -- no default at all: border shown
    end
    return not v
end
function ns.ApplyFrameIconBorder(frame, enabled, adjustIconInset)
    local PP = EllesmereUI and EllesmereUI.PP
    if not (frame and PP and PP.GetBorders and PP.GetBorders(frame)) then return end
    if enabled then
        if PP.ShowBorder then PP.ShowBorder(frame) end
    elseif PP.HideBorder then
        PP.HideBorder(frame)
    end
    -- Aura slots keep a 1px icon inset for the border; borderless fills the
    -- icon to the edge so no bare rim shows (matches the options preview).
    -- OPT-IN: the cast icon (inset 0 by design, border draws on top) and the
    -- lockout icon own their geometry and must not be re-anchored here.
    if adjustIconInset and frame.icon then
        local px = enabled and 1 or 0
        frame.icon:ClearAllPoints()
        PP.Point(frame.icon, "TOPLEFT", frame, "TOPLEFT", px, -px)
        PP.Point(frame.icon, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    end
end
function ns.NP_CanShowCastIconSeparator(db)
    if not db or db.castbarIconInWidth ~= true or db.showCastIcon == false
        or db.castIconFullSize == true or ns.NP_Blizz() then return false end
    local tex = db.customBorderTexture or defaults.customBorderTexture
    return (db.customBorderSize or defaults.customBorderSize) > 0
        and (tex == "solid" or tex == "" or EllesmereUI.GetBorderCompanion(tex, "sepV") ~= nil)
end

-- Shared by live plates and the preview; the cast bar owns this lazy divider. It
-- does not follow the target or threat tint, so the border-colour passes that land
-- here (every threat repaint) change nothing: only a moved style input restyles it.
function ns.NP_ApplyCastIconSeparator(cast, icon, db, customOn, strata)
    local seam = cast._iconSeam
    if not (db and db.castIconSeparator == true and customOn and ns.NP_CanShowCastIconSeparator(db)) then
        if seam and seam:IsShown() then
            seam:Hide()
            EllesmereUI.RegisterPxReapply(seam, nil)
        end
        return
    end
    if not seam then
        seam = CreateFrame("Frame", nil, cast)
        seam:SetAllPoints(cast)
        seam:EnableMouse(false)
        seam._tex = seam:CreateTexture(nil, "OVERLAY", nil, 7)
        cast._iconSeam = seam
    end
    local st = strata or cast:GetFrameStrata()
    local lvl = icon:GetFrameLevel() + 5
    local key = db.customBorderTexture or defaults.customBorderTexture
    local size = db.customBorderSize or defaults.customBorderSize
    local px = EllesmereUI.BorderPx(db.customBorderSizePx, size, key)
    local right = db.castIconOnRight == true
    local c = db.customBorderColor or defaults.customBorderColor
    local a = db.customBorderAlpha or defaults.customBorderAlpha
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, side, the scale its width snaps to, and its colour.
    if seam:IsShown() and seam:GetFrameStrata() == st and seam:GetFrameLevel() == lvl
        and seam._key == key and seam._size == size and seam._px == px and seam._right == right
        and seam._es == seam:GetEffectiveScale()
        and seam._r == c.r and seam._g == c.g and seam._b == c.b and seam._a == a then
        return
    end
    seam:SetFrameStrata(st)
    seam:SetFrameLevel(lvl)
    seam._key, seam._size, seam._px, seam._right = key, size, px, right
    seam._r, seam._g, seam._b, seam._a = c.r, c.g, c.b, a
    seam._tex:SetVertexColor(c.r, c.g, c.b, a)
    ns.NP_LayoutCastIconSeparator(seam)
    seam:Show()
    EllesmereUI.RegisterPxReapply(seam, strata and ns.NP_LayoutCastIconSeparator or nil)
end

function ns.NP_LayoutCastIconSeparator(seam)
    local t, es = seam._tex, seam:GetEffectiveScale()
    seam._es = es
    if EllesmereUI.GetBorderCompanion(seam._key, "sepV") then
        EllesmereUI.PlaceBorderDividerV(t, seam, seam._right, false, seam._key, seam._size, seam._px, es)
        return
    end
    local onePixel = es > 0 and PP.perfect / es or PP.mult
    t:SetColorTexture(1, 1, 1, 1)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    local top = seam._right and "TOPRIGHT" or "TOPLEFT"
    local bottom = seam._right and "BOTTOMRIGHT" or "BOTTOMLEFT"
    t:SetPoint(top, seam, top, 0, 0)
    t:SetPoint(bottom, seam, bottom, 0, 0)
    t:SetWidth(math.max(1, math.floor((seam._px or seam._size) + 0.5)) * onePixel)
    t:Show()
end

-- Every write of the cast spell icon's border goes through here. Custom Border on
-- Spell Icon (castIconCustomBorder, Border = Custom): the icon wears the plate's custom
-- border in place of its 1px edge. The border is our own frame, a child of the cast bar
-- laid over the icon rather than a child of the icon, whose Scale would multiply an
-- exact pixel size; so it rides Casts In Front of Nameplates with the bar but does not
-- hide with the icon, and turns off through ApplyBorderStyle(frame, 0) so the UI scale
-- re-apply cannot bring it back. MEDIUM strata lifts it out of the plate's flattened
-- layer above the icon art (the lift's strata while the cast bar is lifted). Style
-- inputs restyle only when one moved; a colour change (Use Target Border Color on the
-- target) is a plain tint. Off, this is the 1px edge call plus the opt-in gates.
function ns.ApplyCastIconBorder(plate)
    local icon = plate and plate.castIconFrame
    if not icon then return end
    if (p and p.castIconSeparator) or plate.cast._iconSeam then
        ns.NP_ApplyCastIconSeparator(plate.cast, icon, p, ns.IsCustomBorderEnabled(),
            plate._castOverlayLifted and plate.cast:GetFrameStrata() or "MEDIUM")
    end
    local bf = plate._castIconBorder
    if not (p and p.castIconCustomBorder and ns.IsCustomBorderEnabled()
            and not ns.GetCastIconInWidth()
            and GetShowCastIcon() and ns.GetIconBorderEnabled("cast")) then
        if bf and bf:IsShown() then
            EllesmereUI.ApplyBorderStyle(bf, 0)
            bf:Hide()
        end
        ns.ApplyFrameIconBorder(icon, ns.GetIconBorderEnabled("cast"))
        return
    end
    ns.ApplyFrameIconBorder(icon, false)
    if not bf then
        bf = CreateFrame("Frame", nil, plate.cast)
        bf:SetAllPoints(icon)
        bf:EnableMouse(false)
        plate._castIconBorder = bf
    end
    local tex = p.customBorderTexture or defaults.customBorderTexture
    local sz = p.customBorderSize or defaults.customBorderSize
    local px = EllesmereUI.BorderPx(p.customBorderSizePx, sz, tex)
    local r, g, b, a
    if p.castIconTargetBorder and plate._isTarget and ns.GetTargetGlowBorderColor() then
        local c = ns.GetTargetBorderColor()
        r, g, b, a = c.r, c.g, c.b, 1
    else
        local c = p.customBorderColor or defaults.customBorderColor
        r, g, b, a = c.r, c.g, c.b, p.customBorderAlpha or defaults.customBorderAlpha or 1
    end
    local strata = plate._castOverlayLifted and plate.cast:GetFrameStrata() or "MEDIUM"
    local lvl = icon:GetFrameLevel() + 3
    local offX, offY = p.customBorderOffset, p.customBorderOffsetY
    local shX, shY = p.customBorderShiftX, p.customBorderShiftY
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, both offsets and both shifts. Anything else is colour.
    if not bf:IsShown() or bf:GetFrameStrata() ~= strata or bf:GetFrameLevel() ~= lvl
        or bf._sTex ~= tex or bf._sSz ~= sz or bf._sPx ~= px
        or bf._sOX ~= offX or bf._sOY ~= offY or bf._sSX ~= shX or bf._sSY ~= shY then
        bf:SetFrameStrata(strata)
        bf:SetFrameLevel(lvl)
        EllesmereUI.ApplyBorderStyle(bf, sz, r, g, b, a, tex, offX, offY, shX, shY, "nameplates", sz, nil, px)
        if PP.GetBorders(bf) then PP.CreateBorder(bf, nil, nil, nil, nil, nil, nil, nil, true) end
        bf._sTex, bf._sSz, bf._sPx = tex, sz, px
        bf._sOX, bf._sOY, bf._sSX, bf._sSY = offX, offY, shX, shY
    else
        EllesmereUI.SetBorderStyleColor(bf, r, g, b, a)
    end
end
local function GetBorderColor()
    -- Classic WoW UI: the plate's edge is always black.
    if ns.NP_Classic() then return 0, 0, 0 end
    local c = (p and p.borderColor) or defaults.borderColor
    return c.r, c.g, c.b
end
ns.GetBorderColor = GetBorderColor
-- Health border size: the classic plate's fixed 1px edge, else the profile's
-- Border Size. Friendly plates mirror it.
function ns.NP_BorderSize()
    if ns.NP_Classic() then return 1 end
    return (p and p.borderSize) or defaults.borderSize
end
-- Cast bar border colour: black under Classic WoW UI, else the profile's.
function ns.NP_CastBorderColor()
    if ns.NP_Classic() then return 0, 0, 0 end
    local c = (p and p.castBorderColor) or defaults.castBorderColor
    return c.r, c.g, c.b
end
-- "Wrap Border Around Castbar". The cast-visibility hook reads this on every
-- cast show/hide, so it must stay a trivial table lookup.
function ns.GetWrapBorderCastbar()
    local v = p and p.wrapBorderCastbar
    if v == nil then return defaults.wrapBorderCastbar end
    return v
end
local function GetAuraSlots()
    local ds = (p and p.debuffSlot) or defaults.debuffSlot
    local bs = (p and p.buffSlot)   or defaults.buffSlot
    local cs = (p and p.ccSlot)     or defaults.ccSlot
    return ds, bs, cs
end
ns.GetAuraSlots = GetAuraSlots

-- Raise Strata: per-slot Core Positions toggle. On, the element in that slot is bumped
-- MEDIUM -> HIGH so it renders above the rest of the plate. On ns (local budget).
function ns.GetSlotRaiseStrata(posKey)
    if not posKey or posKey == "none" then return false end
    local key = posKey .. "SlotRaiseStrata"
    if p and p[key] ~= nil then return p[key] end
    return defaults[key] or false
end

-- Apply each slot's Raise Strata setting to its element frame(s). Frames otherwise share MEDIUM
-- strata; HIGH lifts that element above the flattened text/aura/indicator tiers. Children
-- (cooldown, count carrier, border) inherit the frame's strata.
function ns.ApplySlotStrata(plate)
    if not plate then return end
    local function StrataFor(slot)
        return ns.GetSlotRaiseStrata(slot) and "HIGH" or "MEDIUM"
    end
    if plate.raidFrame then
        plate.raidFrame:SetFrameStrata(StrataFor(GetRaidMarkerPos()))
    end
    if plate.classFrame then
        plate.classFrame:SetFrameStrata(StrataFor(GetClassificationSlot()))
    end
    if plate.factionFrame then
        plate.factionFrame:SetFrameStrata(StrataFor(ns.NP_GetFactionSlot()))
    end
    local ds, bs, cs = GetAuraSlots()
    local dStr, bStr, cStr = StrataFor(ds), StrataFor(bs), StrataFor(cs)
    if plate.debuffs then
        for i = 1, #plate.debuffs do plate.debuffs[i]:SetFrameStrata(dStr) end
    end
    if plate.buffs then
        for i = 1, #plate.buffs do plate.buffs[i]:SetFrameStrata(bStr) end
    end
    if plate.cc then
        for i = 1, #plate.cc do plate.cc[i]:SetFrameStrata(cStr) end
    end
end

-- Pandemic glow engine: procedural ants, button glow, autocast shine, FlipBook. do...end keeps
-- internal locals out of the main chunk's 200-local budget; externally-needed items stored on ns.
do
-------------------------------------------------------------------------------
--  Glow engines from shared EllesmereUI_Glows.lua; aliases for the wrapper below.
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local StartProceduralAnts = _G_Glows.StartProceduralAnts
local StopProceduralAnts  = _G_Glows.StopProceduralAnts
local StartButtonGlow     = _G_Glows.StartButtonGlow
local StopButtonGlow      = _G_Glows.StopButtonGlow
local StartAutoCastShine  = _G_Glows.StartAutoCastShine
local StopAutoCastShine   = _G_Glows.StopAutoCastShine
local StartGlow           = _G_Glows.StartGlow
local StopAllGlows        = _G_Glows.StopAllGlows
ns.StartProceduralAnts = StartProceduralAnts
ns.StopProceduralAnts  = StopProceduralAnts
ns.StartButtonGlow     = StartButtonGlow
ns.StopButtonGlow      = StopButtonGlow
ns.StartAutoCastShine  = StartAutoCastShine
ns.StopAutoCastShine   = StopAutoCastShine
ns.StartGlow           = StartGlow
ns.StopAllGlows        = StopAllGlows

-------------------------------------------------------------------------------
--  Dispellable buff glow: highlights enemy buffs the player can purge/soothe
-------------------------------------------------------------------------------
local function StopDispelGlow(slot)
    local dg = slot.dispelGlow
    if not dg or not dg.active then return end
    _G_Glows.StopAllGlows(dg.wrapper)
    dg.wrapper:Hide()
    dg.active = false
end

-- Preview only: the live nameplate glow runs through EllesmereUI.Glows on the
-- engine buttons. dispelType is "magic" / "enrage" / nil. Same spec and engine
-- path as the live purge glow, so the preview is the live look.
-- slotH: the icon height (cropped icons).
local function StartDispelGlow(slot, slotSize, dispelType, slotH)
    local dg = slot.dispelGlow
    if not dg then
        local wrapper = CreateFrame("Frame", nil, slot)
        wrapper:SetAllPoints()
        wrapper:SetFrameLevel(slot:GetFrameLevel() + 5)
        wrapper:Show()
        dg = { wrapper = wrapper, active = false, spec = {} }
        slot.dispelGlow = dg
    end
    local sz = slotSize or 26
    ns.GetDispelGlowSpec(dispelType, dg.spec)
    dg.wrapper:Show()
    _G_Glows.StartSpecGlow(dg.wrapper, dg.spec, sz, slotH or sz, "engine", _G_Glows.PANEL_EXTRA)
    dg.active = true
    -- Always opaque. Visibility used to ride a per-aura dispel-type curve's
    -- alpha; dispellability is now decided by which aura GROUP the button
    -- belongs to, and this path only ever draws the options preview.
    dg.wrapper:SetAlpha(1)
end

ns.StopDispelGlow = StopDispelGlow
ns.StartDispelGlow = StartDispelGlow
end -- do (glow engine)

-- Forward declaration (assigned in EUI_Nameplates_ClassPower.lua, see SetClassPowerTopPush)
local GetClassPowerTopPush
-- Position aura frames into a slot (top/left/right/topleft/topright/bottom).
-- count: how many to show; sizeW/sizeH: icon dimensions; gap: gap between icons.
local function PositionAuraSlot(frames, count, slot, plate, sizeW, sizeH, gap, xOff, yOff)
    xOff = xOff or 0
    yOff = yOff or 0
    local spacing = gap + sizeW  -- horizontal center-to-center distance
    -- Vertical center-to-center; cropped icons are shorter so stacked slots (topleft/topright
    -- "up") pack tighter. sizeH falls back to sizeW when square (uncropped).
    local spacingV = gap + (sizeH or sizeW)
    -- Profile reads, anchor resolution and growth lookups are invariant across the icon loop:
    -- resolve once per slot branch, loop only ClearAllPoints + PP.Point. GetClassPowerTopPush
    -- reads target identity, so the left/right/bottom and top-with-text-element paths must never call it.
    if slot == "top" then
        local debuffY = GetDebuffYOffset()
        -- Determine anchor: resolve to whichever FontString is in the top slot
        local topElement = GetTextSlot("textSlotTop")
        local anchor
        if ns.IsNameElement(topElement) then
            anchor = plate.name
        elseif topElement == "healthNumber" then
            anchor = plate.hpNumber
        elseif topElement == "level" then
            anchor = plate.levelText
        elseif topElement == "targetOfTarget" then
            anchor = plate.totText or plate.health
        elseif topElement ~= "none" then
            anchor = plate.hpText  -- healthPercent, healthPctNum, healthNumPct
        else
            anchor = plate.health
        end
        -- Only add cpPush when anchoring to health bar (topElement is "none");
        -- text FontStrings already include cpPush in their own positioning.
        local cpPush = (topElement == "none") and GetClassPowerTopPush(plate) or 0
        local y = debuffY + cpPush + yOff
        for i = 1, count do
            frames[i]:ClearAllPoints()
            PP.Point(frames[i], "BOTTOM", anchor, "TOP",
                (i - (count + 1) / 2) * spacing + xOff, y)
        end
    elseif slot == "left" then
        -- Classic WoW UI: gap off the border art, not the bare bar edge.
        local sideOff = GetSideAuraXOffset() + ns.NP_ClassicSide("left")
        for i = 1, count do
            frames[i]:ClearAllPoints()
            PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "BOTTOMLEFT",
                -sideOff - (i - 1) * spacing + xOff, yOff)
        end
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset() + ns.NP_ClassicSide("right")
        for i = 1, count do
            frames[i]:ClearAllPoints()
            PP.Point(frames[i], "BOTTOMLEFT", plate.health, "BOTTOMRIGHT",
                sideOff + (i - 1) * spacing + xOff, yOff)
        end
    elseif slot == "topleft" then
        local debuffY = GetDebuffYOffset()
        local cpPush = GetClassPowerTopPush(plate)
        local growth = (p and p.topleftSlotGrowth) or defaults.topleftSlotGrowth
        -- Icon 1 is always flush with the health bar's top-left corner; growth only moves icons
        -- 2+. PP borders are inset, so the bar corner IS the nameplate's outer edge.
        local baseX = xOff
        local baseY = debuffY + cpPush + yOff
        for i = 1, count do
            frames[i]:ClearAllPoints()
            local idx = i - 1  -- 0 for icon 1, so it never moves
            if growth == "up" then
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX, baseY + idx * spacingV)
            elseif growth == "right" then
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX + idx * spacing, baseY)
            else
                -- Default: grow left
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX - idx * spacing, baseY)
            end
        end
    elseif slot == "topright" then
        local debuffY = GetDebuffYOffset()
        local cpPush = GetClassPowerTopPush(plate)
        local growth = (p and p.toprightSlotGrowth) or defaults.toprightSlotGrowth
        -- Icon 1 is always flush with the health bar's top-right corner; growth only moves
        -- icons 2+ (PP borders are inset, so offset 0 is true flush).
        local baseX = xOff
        local baseY = debuffY + cpPush + yOff
        for i = 1, count do
            frames[i]:ClearAllPoints()
            local idx = i - 1  -- 0 for icon 1, so it never moves
            if growth == "up" then
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX, baseY + idx * spacingV)
            elseif growth == "left" then
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX - idx * spacing, baseY)
            else
                -- Default: grow right
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX + idx * spacing, baseY)
            end
        end
    elseif slot == "bottom" then
        for i = 1, count do
            frames[i]:ClearAllPoints()
            -- Anchor below the cast bar, centered
            PP.Point(frames[i], "TOP", plate.cast, "BOTTOM",
                (i - (count + 1) / 2) * spacing + xOff, -2 + yOff)
        end
    else
        -- Unknown slot: clear points, re-anchor nothing.
        for i = 1, count do
            frames[i]:ClearAllPoints()
        end
    end
end
ns.PositionAuraSlot = PositionAuraSlot

-- XY offset for an aura slot key ("debuffSlot", "raidMarker", "classification").
local auraSlotToDBKey = {
    debuffSlot     = "debuffSlot",
    buffSlot       = "buffSlot",
    ccSlot         = "ccSlot",
    classification = "classificationSlot",
    raidMarker     = "raidMarkerPos",
    faction        = "factionSlot",
}
local function GetAuraSlotOffsets(slotKey)
    local dbKey = auraSlotToDBKey[slotKey]
    if not dbKey then return 0, 0 end
    local pos = (p and p[dbKey]) or defaults[dbKey]
    if not pos or pos == "none" then return 0, 0 end
    return GetSlotOffsets(pos)
end
-- 12.1 aura containers read layout inputs through these.
ns.GetAuraSlotOffsets = GetAuraSlotOffsets
function ns.NP_GetProfile() return p end
function ns.NP_GetDefaults() return defaults end
function ns.NP_ClassPowerTopPush(plate)
    if GetClassPowerTopPush then return GetClassPowerTopPush(plate) or 0 end
    return 0
end

-- Get XY offset for a text slot key (e.g. "textSlotTop")
local function GetTextSlotOffsets(slotKey)
    local xOff = (p and p[slotKey .. "XOffset"]) or 0
    local yOff = (p and p[slotKey .. "YOffset"]) or 0
    return xOff, yOff
end

-- Get font size for a text slot key (e.g. "textSlotTop")
local function GetTextSlotSize(slotKey)
    return (p and p[slotKey .. "Size"]) or defaults[slotKey .. "Size"] or 10
end
ns.GetTextSlotSize = GetTextSlotSize

-- Get color for a text slot key (e.g. "textSlotTop")
local function GetTextSlotColor(slotKey)
    local c = (p and p[slotKey .. "Color"]) or defaults[slotKey .. "Color"]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Per-slot host frame for a Core Text Position, honoring the slot's Strata
-- option. MEDIUM (the default) keeps today's shared text tier: the top slot
-- owns topTextFrame outright (its strata is applied directly), the other
-- slots share healthTextFrame. A non-default strata on a non-top slot gets
-- a lazily-created host so the four slots layer independently; hosts carry
-- only font strings (no child frames), so SetFrameStrata propagation is not
-- a concern -- except the name raid marker frame, whose caller re-asserts
-- its own strata after parenting.
ns.SlotTextHost = function(self, slotKey, strata)
    if slotKey == "textSlotTop" then
        local f = self.topTextFrame
        f:SetFrameStrata(strata)
        return f
    end
    if strata == "MEDIUM" then return self.healthTextFrame end
    local hosts = self._slotTextHosts
    if not hosts then hosts = {}; self._slotTextHosts = hosts end
    local f = hosts[slotKey]
    if not f then
        f = CreateFrame("Frame", nil, self)
        f:SetAllPoints(self.health)
        f:SetFrameLevel(900)
        hosts[slotKey] = f
    end
    f:SetFrameStrata(strata)
    return f
end

ns.DEFAULT_CAST_LOCKOUT_DURATION = 4
ns.CAST_LOCKOUT_ICON = "Interface\\Icons\\Ability_Kick"

function ns.ShowCastLockoutAsCrowdControl()
    if p and p.showCastLockoutAsCrowdControl ~= nil then return p.showCastLockoutAsCrowdControl end
    return defaults.showCastLockoutAsCrowdControl
end

function ns.GetActiveCastLockout(plate)
    local lockout = plate._castLockout
    if not lockout then return nil end
    if not ns.ShowCastLockoutAsCrowdControl() or lockout.expires <= GetTime() then
        plate._castLockout = nil
        return nil
    end
    return lockout
end

-- Position target arrows OUTSIDE the outermost side auras; call after all aura positioning is complete.
local PositionArrowsOutsideAuras
do
    -- Hoisted out of PositionArrowsOutsideAuras so no closure is allocated per call on the
    -- target plate: extents accumulate through params/returns (allocation-free, no shared state).
    local function AddSideExtent(slot, frames, maxIdx, sz, slotKey, gap, sideOff, leftExtent, rightExtent)
        local shown = 0
        for i = 1, maxIdx do
            if frames[i] and frames[i]:IsShown() then shown = shown + 1 end
        end
        if shown == 0 then return leftExtent, rightExtent end
        local sp = gap + sz
        local xOff = slotKey and (select(1, GetAuraSlotOffsets(slotKey))) or 0
        -- Classic WoW UI: the rows themselves sit past the border art, so the
        -- extent the arrow clears counts it too (same term the rows use).
        if slot == "left" then
            -- Left edge of leftmost icon: -(sideOff + (shown-1)*sp + sz) + xOff
            local ext = sideOff + ns.NP_ClassicSide("left") + (shown - 1) * sp + sz - xOff
            leftExtent = math.max(leftExtent, ext)
        elseif slot == "right" then
            local ext = sideOff + ns.NP_ClassicSide("right") + (shown - 1) * sp + sz + xOff
            rightExtent = math.max(rightExtent, ext)
        end
        return leftExtent, rightExtent
    end

PositionArrowsOutsideAuras = function(plate)
    if not plate.leftArrow then return end
    if not plate.leftArrow:IsShown() then return end
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    local sideOff = GetSideAuraXOffset()
    -- Track the furthest pixel extent on each side (accounts for per-slot X offsets)
    local leftExtent, rightExtent = 0, 0
    -- Cast spell icon: reserve on its side so the arrow + pushed side-slot core icons clear it.
    -- Normal-size icons always reserve (steady across cast start/stop); passing plate gates the
    -- full-size icon's large reserve on the cast bar being shown. Clean numbers, no secrets.
    local iconRes, iconSide = ns.GetCastIconReserve(plate)
    local leftPush = (iconRes > 0 and iconSide == "left") and iconRes or 0
    local rightPush = (iconRes > 0 and iconSide == "right") and iconRes or 0
    -- Classic WoW UI: the border art counts as part of the bar, so everything
    -- beside the bar clears its reach (mostly the level plate on the right).
    local classicL, classicR = ns.NP_ClassicBarReserve()
    leftPush, rightPush = leftPush + classicL, rightPush + classicR
    if leftPush > 0 then leftExtent = math.max(leftExtent, leftPush) end
    if rightPush > 0 then rightExtent = math.max(rightExtent, rightPush) end
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    leftExtent, rightExtent = AddSideExtent(debuffSlot, plate.debuffs or {}, 6, debuffSz, "debuffSlot", GetAuraSpacing("debuffs"), sideOff, leftExtent, rightExtent)
    leftExtent, rightExtent = AddSideExtent(buffSlot, plate.buffs or {}, 4, buffSz, "buffSlot", GetAuraSpacing("buffs"), sideOff, leftExtent, rightExtent)
    leftExtent, rightExtent = AddSideExtent(ccSlot, plate.cc or {}, 2, ccSz, "ccSlot", GetAuraSpacing("ccs"), sideOff, leftExtent, rightExtent)
    -- Account for raid marker in side slots
    local rmPos = GetRaidMarkerPos()
    if rmPos == "left" and plate.raidFrame and plate.raidFrame:IsShown() then
        local rmSz = GetRaidMarkerSize()
        local rxOff = select(1, GetAuraSlotOffsets("raidMarker"))
        leftExtent = math.max(leftExtent, sideOff + leftPush + rmSz - rxOff)
    elseif rmPos == "right" and plate.raidFrame and plate.raidFrame:IsShown() then
        local rmSz = GetRaidMarkerSize()
        local rxOff = select(1, GetAuraSlotOffsets("raidMarker"))
        rightExtent = math.max(rightExtent, sideOff + rightPush + rmSz + rxOff)
    end
    -- Account for classification icon in side slots
    local clSlot = GetClassificationSlot()
    local clSz = GetRareEliteIconSize()
    if clSlot == "left" and plate.classFrame and plate.classFrame:IsShown() then
        local cxOff = select(1, GetAuraSlotOffsets("classification"))
        leftExtent = math.max(leftExtent, sideOff + leftPush + clSz - cxOff)
    elseif clSlot == "right" and plate.classFrame and plate.classFrame:IsShown() then
        local cxOff = select(1, GetAuraSlotOffsets("classification"))
        rightExtent = math.max(rightExtent, sideOff + rightPush + clSz + cxOff)
    end
    -- Account for the faction badge in side slots (its own, or Rare/Quest + Faction)
    local fcSlot = ns.NP_GetFactionSlot()
    if (fcSlot == "left" or fcSlot == "right") and plate.factionFrame and plate.factionFrame:IsShown() then
        local fxOff = GetSlotOffsets(fcSlot)
        local fcSz = ns.NP_GetFactionIconSize()
        if fcSlot == "left" then
            leftExtent = math.max(leftExtent, sideOff + leftPush + fcSz - fxOff)
        else
            rightExtent = math.max(rightExtent, sideOff + rightPush + fcSz + fxOff)
        end
    end
    -- Restricted-tree rendering: inside the aspect-restricted nameplate subtree, SINGLE-POINT +
    -- SetSize regions render displaced from their anchor, while rects fully defined by anchors
    -- (fill, bg, hash line) render exactly. So both arrows pin TOP+BOTTOM to the health bar's
    -- CORNERS (hash-line pattern): bar edges resolve engine-side, offsets stay small numbers,
    -- nothing here reads geometry ("Can't measure restricted regions"). Result: inner edge
    -- (extent + 8) from the bar edge, vertically centered, 16*scale tall; symmetric +/-dy pair
    -- keeps centering exact under pixel-mult rounding.
    local st = ns.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw = math.floor(((st and st.w) or 16) * sc + 0.5)
    local ah = math.floor(16 * sc + 0.5)
    local dy = (ah - GetHealthBarHeight()) / 2
    local lox = -(leftExtent + 8 + aw / 2)
    local rox = (rightExtent + 8 + aw / 2)
    -- Stashed for EUI_Nameplates_AuraContainers ReanchorArrows, which re-points arrows to
    -- engine-sized aura container edges and needs these dimensions without re-deriving the style.
    plate._arrowW, plate._arrowH = aw, ah
    plate.leftArrow:ClearAllPoints()
    plate.rightArrow:ClearAllPoints()
    PP.Point(plate.leftArrow, "TOP", plate.health, "TOPLEFT", lox, dy)
    PP.Point(plate.leftArrow, "BOTTOM", plate.health, "BOTTOMLEFT", lox, -dy)
    PP.Width(plate.leftArrow, aw)
    PP.Point(plate.rightArrow, "TOP", plate.health, "TOPRIGHT", rox, dy)
    PP.Point(plate.rightArrow, "BOTTOM", plate.health, "BOTTOMRIGHT", rox, -dy)
    PP.Width(plate.rightArrow, aw)
end
end -- do (AddSideExtent scope)
ns.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras

I.EstimateHealthTextWidth, I.GetAuraSlotOffsets = EstimateHealthTextWidth, GetAuraSlotOffsets
I.GetAuraSlots, I.GetAuraSpacing = GetAuraSlots, GetAuraSpacing
I.GetBorderColor, I.GetBuffIconSize = GetBorderColor, GetBuffIconSize
I.GetCastBarHeight, I.GetCastScale = GetCastBarHeight, GetCastScale
I.GetCCIconSize, I.GetClassificationSlot = GetCCIconSize, GetClassificationSlot
I.GetClassPowerClassColors = GetClassPowerClassColors
I.GetClassPowerCustomColor, I.GetDebuffIconSize = GetClassPowerCustomColor, GetDebuffIconSize
I.GetDebuffTextColor, I.GetDebuffYOffset = GetDebuffTextColor, GetDebuffYOffset
I.GetEnemyNameTextSize, I.GetFocusCastHeight = GetEnemyNameTextSize, GetFocusCastHeight
I.GetHealthBarHeight, I.GetHealthBarWidth = GetHealthBarHeight, GetHealthBarWidth
I.GetHideEnemyNameWhileCasting = GetHideEnemyNameWhileCasting
I.GetHitboxYShift, I.GetKickTickColor = GetHitboxYShift, GetKickTickColor
I.GetKickTickEnabled, I.GetNameplateYOffset = GetKickTickEnabled, GetNameplateYOffset
I.GetNameYOffset, I.GetRaidMarkerPos = GetNameYOffset, GetRaidMarkerPos
I.GetRaidMarkerSize, I.GetRareEliteIconSize = GetRaidMarkerSize, GetRareEliteIconSize
I.GetShowCastIcon, I.GetShowClassPower = GetShowCastIcon, GetShowClassPower
I.GetSideAuraXOffset, I.GetSlotOffsets = GetSideAuraXOffset, GetSlotOffsets
I.GetStackSpacingScale, I.GetTargetScale = GetStackSpacingScale, GetTargetScale
I.GetTextSlot, I.GetTextSlotColor = GetTextSlot, GetTextSlotColor
I.GetTextSlotOffsets, I.GetTextSlotSize = GetTextSlotOffsets, GetTextSlotSize
I.IsBorderEnabled, I.IsComboHealthText = IsBorderEnabled, IsComboHealthText
I.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
I.PositionArrowsOutsideAuras, I.PositionAuraSlot = PositionArrowsOutsideAuras, PositionAuraSlot
I.SetCombinedHealthText = SetCombinedHealthText
I.SetClassPowerTopPush = function(f) GetClassPowerTopPush = f end
I.broken = false
