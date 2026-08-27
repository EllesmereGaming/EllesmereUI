if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addon, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[addon] = ns  -- LOD options files read this module ns via the registry

local ENP = EllesmereUI.Lite.NewAddon("EllesmereUINameplates")

-- Profile alias: set in OnInitialize; getters fall back to defaults while nil.
local p

local pairs, ipairs, type = pairs, ipairs, type
local PP = EllesmereUI.PP
-- Pre-hook SetTexture for pooled aura-slot icons (snap-disabled at creation, so
-- the pixel-snap hook is pure overhead). Upgraded to PP.RawSetTexture in
-- OnEnable; starts as a plain wrapper so it is never nil.
local RawSetTex = function(t, v) t:SetTexture(v) end
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local C_UnitAuras = C_UnitAuras
local UnitName, UnitGUID = UnitName, UnitGUID
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitIsEnemy, UnitIsTapDenied = UnitIsEnemy, UnitIsTapDenied

local UnitAffectingCombat, UnitClassification = UnitAffectingCombat, UnitClassification
local UnitIsDeadOrGhost, UnitReaction = UnitIsDeadOrGhost, UnitReaction
local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass
local UnitCreatureType, UnitClassBase, UnitLevel = UnitCreatureType, UnitClassBase, UnitLevel
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local GetTime = GetTime
local C_NamePlate = C_NamePlate
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture
local C_CVar, NamePlateConstants, Enum = C_CVar, NamePlateConstants, Enum
local _, PLAYER_CLASS = UnitClass("player")

local function GetFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("nameplates")
    end
    -- `defaults` is declared below this function, so use the literal path.
    return (p and p.font) or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
end
local function GetNPOutline()
    -- Slug-gated at the source (GetFontOutlineFlag); SetFSFont gates the
    -- explicit-flag path too, so aura literals are covered.
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("nameplates")) or "OUTLINE, SLUG"
end
local function GetNPUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("nameplates")
end
local function SetFSFont(fs, size, flags)
  if not (fs and fs.SetFont) then return end
  local f = flags or GetNPOutline()
  -- "Never Show Slug": gates the explicit-flag path so hardcoded aura
  -- "OUTLINE, SLUG" literals drop the slug (body text is gated at the source).
  if EllesmereUI and EllesmereUI.SlugFlag then f = EllesmereUI.SlugFlag(f) end
  -- Drop shadows only render from a FontObject; prime before SetFont.
  if EllesmereUI and EllesmereUI.PrimeFontShadow then
    EllesmereUI.PrimeFontShadow(fs, f == "")
  end
  fs:SetFont(GetFont(), size or 11, f)
end

ns.GetFont = GetFont
ns.GetNPOutline = GetNPOutline
ns.GetNPUseShadow = GetNPUseShadow
ns.SetFSFont = SetFSFont
ns.plates = {}
_G.EllesmereNameplates_NS = ns

-- Weak-keyed external state for nameplate Y-offsets: never write custom keys
-- onto Blizzard C_NamePlate frames (taint).
local _npYOffsetState = setmetatable({}, { __mode = "k" })

-- Health text bar slots; file scope to avoid per-call alloc in UpdateHealthValues.
local HP_BAR_SLOTS = {
    { key = "textSlotRight",  anchor = "RIGHT",  point = "RIGHT",  xOff = -2 },
    { key = "textSlotLeft",   anchor = "LEFT",   point = "LEFT",   xOff = 4 },
    { key = "textSlotCenter", anchor = "CENTER", point = "CENTER", xOff = 0 },
}

ns.NP_ABSORB_STYLE_TEX = {
    blizzard = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard-nameplates.png",
    striped  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
    clean    = "Interface\\Buttons\\WHITE8X8",
}
ns.NP_ABSORB_STYLE_ALPHA = {
    blizzard = 0.8,
    striped  = 0.8,
    clean    = 0.3,
}

-- Overflow for _displayPresetKeys; outside the main function scope to stay
-- under Lua 5.1's 200-local limit.
function ns._appendDisplayPresetKeys(t)
    for _, k in ipairs({
        "topSlotSize", "topSlotXOffset", "topSlotYOffset", "topSlotRaiseStrata",
        "rightSlotSize", "rightSlotXOffset", "rightSlotYOffset", "rightSlotRaiseStrata",
        "leftSlotSize", "leftSlotXOffset", "leftSlotYOffset", "leftSlotRaiseStrata",
        "toprightSlotSize", "toprightSlotXOffset", "toprightSlotYOffset", "toprightSlotGrowth", "toprightSlotRaiseStrata",
        "topleftSlotSize", "topleftSlotXOffset", "topleftSlotYOffset", "topleftSlotGrowth", "topleftSlotRaiseStrata",
        "textSlotTopSize", "textSlotTopXOffset", "textSlotTopYOffset", "textSlotTopStrata",
        "textSlotRightSize", "textSlotRightXOffset", "textSlotRightYOffset", "textSlotRightStrata",
        "textSlotLeftSize", "textSlotLeftXOffset", "textSlotLeftYOffset", "textSlotLeftStrata",
        "textSlotCenterSize", "textSlotCenterXOffset", "textSlotCenterYOffset", "textSlotCenterStrata",
        "textSlotTopColor", "textSlotRightColor", "textSlotLeftColor", "textSlotCenterColor",
        "tankHasAggroEnabled", "tankHasAggro", "classicTankAggro", "tankHasAggroOverrideMobType",
        "tankHasAggroOverrideBoss",
        "dpsHasAggro", "dpsNearAggro", "offTankAggroEnabled", "offTankAggro",
        "dpsNoAggroEnabled", "dpsNoAggro", "dpsNoAggroOverrideMiniBoss", "dpsNoAggroOverrideCaster",
        "targetArrowDouble", "targetArrowStyle", "targetArrowColor", "targetArrowClassColor",
        "auraStackTextSize", "auraStackTextColor",
        "auraStackTextPosition", "auraStackTextX", "auraStackTextY",
        "auraDurationTextX", "auraDurationTextY",
        "debuffDurationTextSize", "debuffDurationTextX", "debuffDurationTextY", "debuffDurationTextColor",
        "buffDurationTextSize", "buffDurationTextX", "buffDurationTextY", "buffDurationTextColor",
        "ccDurationTextSize", "ccDurationTextX", "ccDurationTextY", "ccDurationTextColor",
        "buffTextSize", "buffTextColor", "ccTextSize", "ccTextColor",
        "raidMarkerPos", "classificationSlot", "classificationShowInInstances",
        "castNameSize", "castNameColor", "castCombineNameTarget",
        "castTargetSize", "castTargetClassColor", "castTargetColor",
        "showCastTimer", "castTimerSize", "castTimerColor", "targetScale",
        "castNameSide", "castTargetSide", "castTimerSide",
        "castNameWidthPct", "castNameWrap", "castTargetWidthPct", "castTargetWrap",
        "enemyNameWidthPct", "enemyNameWrap", "wrapBorderCastbar",
        "debuffSlot", "buffSlot", "ccSlot",
        "debuffYOffset", "sideAuraXOffset", "auraSpacing",
        "debuffSpacing", "buffSpacing", "ccSpacing",
        "debuffTimerPosition", "buffTimerPosition", "ccTimerPosition",
        "auraDurationTextSize", "auraDurationTextColor",
        "debuffCropIcons", "buffCropIcons", "ccCropIcons",
        "debuffCropPercent", "buffCropPercent", "ccCropPercent",
        "hideCastIconBorder", "hideDebuffIconBorder", "hideBuffIconBorder", "hideCCIconBorder",
        "showCastLockoutAsCrowdControl",
        "castIconOffsetX", "castIconOffsetY",
        "targetGlowEllesmereUI", "targetGlowBorderColor", "targetGlowHighlight", "targetBorderColor",
        "targetGlowBorderSize", "targetBorderSizeValue",
    }) do t[#t + 1] = k end
end

local defaults = {
    absorbStyle = "blizzard",
    absorbCleanAlpha = 30,
    absorbColor = { r = 1, g = 1, b = 1 },
    hostile = { r = 0.39, g = 0.11, b = 0.09 },
    neutral = { r = 0.81, g = 0.72, b = 0.19 },
    tapped  = { r = 0.50, g = 0.50, b = 0.50 },
    focus = { r = 0.051, g = 0.820, b = 0.620 },
    focusColorEnabled = true,
    focusOverlayTexture = "striped-v2",
    focusOverlayAlpha = 1.0,
    focusOverlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    focusOverlayFullBgAlpha = false,  -- on: empty bar shows focus texture at full opacity (vs dimmed 30% default)
    focusOverlayNoTint = false,  -- on: overlay tints with the bar's health color instead of focusOverlayColor
    focusLetterEnabled = false,
    focusLetterAnchor = "CENTER",
    focusLetterX = 0,
    focusLetterY = 0,
    focusLetterSize = 18,
    target = { r = 0.459, g = 0.890, b = 0.580 },
    targetColorEnabled = false,
    targetOverlayTexture = "none",
    targetOverlayAlpha = 1.0,
    targetOverlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    targetOverlayFullBgAlpha = false,  -- on: empty bar shows target texture at full opacity instead of dimmed 30%
    targetOverlayNoTint = false,  -- mirrors focusOverlayNoTint, for the target overlay
    hoverOverlayTexture = "none",
    caster  = { r = 0.231, g = 0.510, b = 0.965 },
    miniboss = { r = 0.518, g = 0.243, b = 0.984 },
    boss = { r = 0.518, g = 0.243, b = 0.984 },
    enemyInCombat = { r = 0.800, g = 0.137, b = 0.137 },
    -- "Mini Enemies" (non-elite trash) has no static default: unset views enemyInCombat, so it
    -- starts identical to "Enemies" (see GetReactionColor).
    miniColoringMPlusOnly = false,  -- on = Mini Enemies color only in 5-mans; off = everywhere
    -- Full Coloring M+ Only (inline cog on Enemy Types): outside 5-mans, mob-type colors (Mini
    -- Enemies/Casters/Mini-Bosses/Bosses) collapse to owBasicColor; Neutral stays own color.
    owBasicColoring = false,
    owBasicColor = { r = 0.800, g = 0.137, b = 0.137 },
    darkenEnemiesOOC = true,
    darkenOOCRecolor = false,  -- "Change Color Instead": recolor OOC enemies rather than dimming
    darkenOOCColor   = { r = 0.5, g = 0.5, b = 0.5 },
    tankHasAggro = { r = 0.05, g = 0.82, b = 0.62 },
    tankHasAggroEnabled = false,
    tankHasAggroOverrideMobType = false,  -- on: overrides Mini-Boss/Caster (above priority step 7); off = stays low
    tankHasAggroOverrideBoss = true,  -- on (default): overrides Boss color; off = held just below Boss
    classicTankAggro = false,
    tankLosingAggro = { r = 0.81, g = 0.72, b = 0.19 },
    tankNoAggro = { r = 1.00, g = 0.22, b = 0.17 },
    dpsNearAggro = { r = 0.81, g = 0.72, b = 0.19 },
    threatNearAggroGlow = false,  -- Non-Tank Threat cog: red glow while the Near Aggro color is active
    dpsHasAggro = { r = 1.00, g = 0.50, b = 0.00 },
    offTankAggro = { r = 0.188, g = 0.761, b = 0.812 },
    offTankAggroEnabled = true,
    dpsNoAggro = { r = 0.35, g = 0.75, b = 0.35 },
    dpsNoAggroEnabled = false,
    dpsNoAggroOverrideMiniBoss = false,  -- on: overrides Mini-Boss (above priority step 7); off = stays low
    dpsNoAggroOverrideCaster = false,  -- on: overrides Caster (above priority step 8); off = Casters keep own color
    interruptReady = { r = 0.92, g = 0.35, b = 0.20 },  
    castBar = { r = 0.70, g = 0.40, b = 0.90 },
    interruptMidCastEnabled = false,
    interruptMidCastColor = { r = 0.318, g = 0.820, b = 0.357 },
    castBarUninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
    castBarImportant = { r = 1, g = 0.2, b = 0.2 },
    importantCastColorEnabled = false,
    castBarShieldEnabled = true,
    interruptedFlashEnabled = true,
    interruptedFlashColor = { r = 0.8, g = 0.0, b = 0.0 },
    showCastLockoutAsCrowdControl = false,
    healthBarHeight = 17,
    friendlyNameOnly = true,
    friendlyNameOnlyYOffset = -20,
    friendlyNameSize = 15,
    friendlyPlateYOffset = 0,
    friendlyHealthBarHeight = 17,
    friendlyHealthBarWidth = 150,
    showFriendlyNPCs = false,
    showNPCTitles = true,
    showFriendlyPlayers = true,
    friendlyClickThrough = false,
    friendlyShowDefaultNames = false,
    classColorFriendly = true,
    friendlyBarColor = { r = 0.314, g = 0.800, b = 0.408 },
    friendlyNPCColor = { r = 0, g = 1, b = 0 },
    friendlyNPCNameSize = 13,
    friendlyNameTextSize = 12,
    friendlyBelowName = "none",
    friendlyBelowNameSize = 12,
    friendlyBelowNameColor = { r = 0.8, g = 0.8, b = 0.8 },
    friendlyBelowNameClassColor = false,
    friendlyBelowNameGuildBrackets = true,
    showEnemyPets = false,
    font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF",
    textSlotTop = "enemyName",
    textSlotRight = "healthPercent",
    textSlotLeft = "none",
    textSlotCenter = "none",
    showTargetArrows = false,
    targetArrowDouble = false,
    targetArrowScale = 1.0,
    targetArrowColor = { r = 1, g = 1, b = 1 },
    targetArrowClassColor = false,
    showClassPower = false,
    classPowerPos = "bottom",
    classPowerYOffset = 1,
    classPowerXOffset = 0,
    classPowerScale = 1.0,
    classPowerClassColors = true,
    classPowerCustomColor = { r = 1.00, g = 0.84, b = 0.30 },
    classPowerBgColor = { r = 0.082, g = 0.082, b = 0.082, a = 1.0 },
    classPowerEmptyColor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
    classPowerGap = 2,
    classPowerShape = "rectangle",  -- rectangle | square | circle | diamond | hexagon | shield
    classPowerBorder = false,
    classPowerBorderColor = { r = 0, g = 0, b = 0, a = 1.0 },
    classPowerBorderSize = 1,
    healthBarWidth = 6,
    stackSpacingScale = 100,
    stackingEnabled = true,
    stackingFriendly = false,
    hitboxScaleX = 100,
    hitboxScaleY = 100,
    nameplateYOffset = 0,
    enemyNameTextSize = 11,
    enemyNameTextReactionColor = false,
    debuffTimerColor = { r = 1, g = 1, b = 1 },
    auraTextPosition = "topleft",
    debuffTimerPosition = "topleft",
    buffTimerPosition = "topleft",
    ccTimerPosition = "topleft",
    auraDurationTextSize = 11,
    auraDurationTextX = 0,
    auraDurationTextY = 0,
    auraDurationTextColor = { r = 1, g = 1, b = 1 },
    auraStackTextSize = 11,
    auraStackTextColor = { r = 1, g = 1, b = 1 },
    auraStackTextPosition = "bottomright",
    auraStackTextX = 0,
    auraStackTextY = 0,
    debuffSlot = "top",
    buffSlot = "left",
    ccSlot = "right",
    debuffYOffset = 2,
    sideAuraXOffset = 2,
    nameYOffset = 0,
    auraSpacing = 2,
    debuffSpacing = 2,  -- per-element icon gap; all default to the global auraSpacing value
    buffSpacing = 2,
    ccSpacing = 2,
    debuffCropIcons = false,  -- cropped icons: trim top/bottom to rectangular (80% of width), mirrors Unit Frames
    buffCropIcons = false,
    ccCropIcons = false,
    debuffCropPercent = 10,  -- per-side trim % for cropped mode (5-25); 10 == the fixed 80%-of-width crop
    buffCropPercent = 10,
    ccCropPercent = 10,
    hideDebuffIconBorder = false,
    hideBuffIconBorder = false,
    hideCCIconBorder = false,
    debuffIconSize = 26,
    buffIconSize = 24,
    buffTextSize = 12,
    buffTextColor = { r = 1, g = 1, b = 1 },
    ccIconSize = 24,
    ccTextSize = 12,
    ccTextColor = { r = 1, g = 1, b = 1 },
    targetGlowStyle = "ellesmereui",
    -- Target "Border Color" tint for the custom border when Border Color toggle is on.
    -- targetGlowEllesmereUI/targetGlowBorderColor/targetGlowHighlight deliberately have NO
    -- default: they stay nil so getters can live-convert from the targetGlowStyle string.
    targetBorderColor = { r = 1, g = 1, b = 1 },
    targetGlowColor = { r = 0.4117, g = 0.6667, b = 1.0 },  -- "Glow Color" for the EUI background glow (signature blue)
    targetGlowAlpha = 1.0,
    targetHighlightColor = { r = 1, g = 1, b = 1 },  -- Target Highlight wash color/opacity
    targetHighlightAlpha = 0.20,
    nameRaidMarkerEnabled = false,
    nameRaidMarkerSize = 14,
    raidMarkerPos = "topright",
    raidMarkerSize = 24,
    classificationSlot = "topleft",
    classificationShowInInstances = false,  -- Rare/Quest "Show In Instances" (slot cog): lifts the open-world-only gate in UpdateClassification + IsQuestMob
    rareEliteIconSize = 20,
    castBarHeight = 17,
    castBarOffsetY = 0,
    castBarSparkEnabled = true,
    castOverlayEnabled = false,
    hideEnemyNameWhileCasting = false,
    castNameSize = 10,
    castNameColor = { r = 1, g = 1, b = 1 },
    castNameOffsetX = 0,
    castNameOffsetY = 0,
    castNameSide = "left",  -- cast bar text line side for spell name: left|right|center|none
    -- Spell name truncation: width as a % of cast bar width; wrap off = single line + ellipsis.
    castNameWidthPct = 42,
    castNameWrap = false,
    castCombineNameTarget = false,
    castTargetSize = 10,
    castTargetClassColor = true,
    castTargetColor = { r = 1, g = 1, b = 1 },
    castTargetOffsetX = 0,
    castTargetOffsetY = 0,
    castTargetSide = "right",  -- side the spell target occupies: left|right|center|none
    -- Spell target truncation: % of cast bar width + wrap toggle.
    castTargetWidthPct = 42,
    castTargetWrap = false,
    showCastTimer = true,
    castTimerSide = "right",  -- side when shown; visibility governed by showCastTimer
    castTimerSize = 10,
    castTimerColor = { r = 1, g = 1, b = 1 },
    castTimerOffsetX = 0,
    castTimerOffsetY = 0,
    -- Enemy name truncation: % of the name's computed (bar-derived) width (100 = full width
    -- minus raid-marker/classification reserves). Wrap off = single line + ellipsis, on = 2 lines.
    enemyNameWidthPct = 100,
    enemyNameWrap = false,
    targetScale = 100,
    nonTargetKeepFocus = true,
    outOfRangeAlpha = 50,
    outOfRangeMode = "disabled",
    showAllDebuffs = false,
    rangeTextEnabled = false,  -- Distance to Target Text (range bucket on the target's nameplate)
    rangeTextSize = 11,
    rangeTextOffsetX = 0,
    rangeTextOffsetY = 0,
    rangeTextColor = { r = 0.816, g = 0.357, b = 0.220 },  -- #D05B38
    maxDebuffs = 5,
    showBorder = true,
    borderSize = 1,
    borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    -- "Wrap Border Around Castbar": health border extends down to enclose the cast bar while casting,
    -- forming one unified border. Fully additive: no wrap machinery runs unless enabled.
    wrapBorderCastbar = false,
    -- Custom border (opt-in): shared EllesmereUI border engine (same as Unit Frames, full
    -- SharedMedia). When false, NONE of these keys are read; the simple border above renders instead.
    customBorderEnabled = false,
    customBorderTexture = "solid",
    customBorderSize = 1,
    customBorderColor = { r = 0.067, g = 0.067, b = 0.067 },
    customBorderAlpha = 1,
    customBorderBehind = false,
    pandemicGlow = false,
    pandemicGlowStyle = 1,
    pandemicGlowColor = { r = 1.0, g = 0.800, b = 0.329 },
    pandemicGlowLines = 8,
    pandemicGlowThickness = 1,
    pandemicGlowSpeed = 4,
    pandemicGlowBackground = false,
    pandemicGlowBackgroundColor = { r = 0, g = 0, b = 0 },
    lowHpGlow = false,  -- Execute Pulse Glow (Extras): red glow around plates below 30% health
    hideBloodPlagueCopies = true,  -- Extras (Blood DK only): collapse the Blood Plague copies to one debuff icon
    dispelGlow = false,
    dispelGlowStyle = 2,
    dispelGlowColor = { r = 1.0, g = 1.0, b = 1.0 },
    dispelGlowUseTypeColor = false,
    castScale = 100,
    focusCastHeight = 100,
    questMobColorEnabled = false,
    questMobColor = { r = 0.157, g = 0.855, b = 0.475 },
    replaceQuestIconWithObjective = false,
    questObjectiveTextSize = 14,
    showCastIcon = true,
    castIconScale = 1,
    castIconOffsetX = 0,
    castIconOffsetY = 0,
    castbarIconInWidth = false,
    castIconOnRight = false,
    castIconFullSize = false,
    castIconTargetBorder = false,
    hideCastIconBorder = false,
    bgAlpha = 1.0,
    bgColor = { r = 0.12, g = 0.12, b = 0.12 },
    hoverColor = { r = 1, g = 1, b = 1 },
    hoverAlpha = 0.3,
    hoverOverlayFullBgAlpha = false,  -- on: empty bar shows hover texture at full opacity instead of dimmed 30%
    castBgAlpha = 0.9,
    castBgColor = { r = 0.1, g = 0.1, b = 0.1 },
    castBorderSize = 0,
    castBorderColor = { r = 0, g = 0, b = 0 },
    hashLineEnabled = false,
    hashLinePercent = 30,
    hashLineColor = { r = 1, g = 1, b = 1 },
    kickTickEnabled = true,
    kickTickColor = { r = 1, g = 1, b = 1 },
    importantCastGlow = true,
    importantCastGlowStyle = 1,
    importantCastGlowColor = { r = 1, g = 0.2, b = 0.2 },
    importantCastGlowLines = 8,
    importantCastGlowThickness = 2,
    importantCastGlowSpeed = 4,
    importantCastGlowBackground = false,
    importantCastGlowBackgroundColor = { r = 0, g = 0, b = 0 },
    -- Core Positions: slot-based size + XY offsets
    topSlotSize = 26,        topSlotXOffset = 0,      topSlotYOffset = 0,      topSlotRaiseStrata = false,
    rightSlotSize = 24,      rightSlotXOffset = 0,    rightSlotYOffset = 0,    rightSlotRaiseStrata = false,
    leftSlotSize = 24,       leftSlotXOffset = 0,     leftSlotYOffset = 0,     leftSlotRaiseStrata = false,
    toprightSlotSize = 24,   toprightSlotXOffset = 0, toprightSlotYOffset = 0, toprightSlotGrowth = "right", toprightSlotRaiseStrata = false,
    topleftSlotSize = 24,    topleftSlotXOffset = 0,  topleftSlotYOffset = 0,  topleftSlotGrowth = "left",   topleftSlotRaiseStrata = false,
    bottomSlotSize = 26,     bottomSlotXOffset = 0,   bottomSlotYOffset = 0,   bottomSlotRaiseStrata = false,
    -- Core Text Positions: slot-based size + XY offsets
    textSlotTopSize = 10,    textSlotTopXOffset = 0,  textSlotTopYOffset = 0,
    textSlotRightSize = 10,  textSlotRightXOffset = 0, textSlotRightYOffset = 0,
    textSlotLeftSize = 10,   textSlotLeftXOffset = 0,  textSlotLeftYOffset = 0,
    textSlotCenterSize = 10, textSlotCenterXOffset = 0, textSlotCenterYOffset = 0,
    -- Core Text Positions: slot-based strata (MEDIUM = the shared text tier)
    textSlotTopStrata = "MEDIUM",  textSlotRightStrata = "MEDIUM",
    textSlotLeftStrata = "MEDIUM", textSlotCenterStrata = "MEDIUM",
    -- Core Text Positions: slot-based colors
    textSlotTopColor = { r = 1, g = 1, b = 1 },
    textSlotRightColor = { r = 1, g = 1, b = 1 },
    textSlotLeftColor = { r = 1, g = 1, b = 1 },
    textSlotCenterColor = { r = 1, g = 1, b = 1 },
    healthBarTexture = "none",  -- bar texture overlay
    castBarTexture = "none",
}
local BAR_W = 150
ns.defaults = defaults
ns.BAR_W = BAR_W
local CAST_H = 17

-- Custom nameplate border (opt-in) -----------------------------------------
-- Per-style/size offset defaults for the shared border engine (mirrors Unit Frames). do/end
-- keeps these locals from leaking (file is near Lua 5.1's main-chunk local cap).
do
    if EllesmereUI and EllesmereUI.RegisterBorderDefaults then
        local function AllSizes(ox, oy, sx, sy)
            local t = {}
            for k = 0, 4 do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
            return t
        end
        EllesmereUI.RegisterBorderDefaults("nameplates", {
            ["glow"]  = { defaultSize = 1, sizes = AllSizes(0, 0, 0, 0) },
            ["blizz"] = {
                defaultSize = 4,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 3, offsetY = 1, shiftX = 1, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                    [4] = { offsetX = 5, offsetY = 3, shiftX = 2, shiftY = 0 },
                },
            },
            ["dialog"] = {
                defaultSize = 2,
                sizes = {
                    [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                    [1] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [2] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                    [3] = { offsetX = 4, offsetY = 4, shiftX = 0, shiftY = 0 },
                    [4] = { offsetX = 8, offsetY = 8, shiftX = 0, shiftY = 0 },
                },
            },
            ["sm:Blizzard Achievement Wood"] = { defaultSize = 1, sizes = AllSizes(1, 1, 0, 0) },
        })
    end
end

-- Custom border apply helpers. Read the enemy profile `p` (friendly plates mirror it 1:1) and
-- route through the shared border engine. Lives on plate._customBorder (a child frame we own)
-- so it never collides with the simple PP.CreateBorder on plate.health. ns fields, not new
-- file-scope locals (local cap).
function ns.IsCustomBorderEnabled()
    local v = p and p.customBorderEnabled
    if v == nil then return defaults.customBorderEnabled end
    return v
end
-- szOverride: optional size for the "Border Size" target effect (rebuilds at that size).
function ns.ApplyCustomBorderStyle(plate, szOverride)
    if not plate or not plate.health then return end
    if not (EllesmereUI and EllesmereUI.ApplyBorderStyle) then return end
    local tex    = (p and p.customBorderTexture) or defaults.customBorderTexture
    local sz     = szOverride or (p and p.customBorderSize) or defaults.customBorderSize
    local col    = (p and p.customBorderColor) or defaults.customBorderColor
    local a      = (p and p.customBorderAlpha) or defaults.customBorderAlpha or 1
    local behind = p and p.customBorderBehind
    if behind == nil then behind = defaults.customBorderBehind end
    local bf = plate._customBorder
    if not bf then
        bf = CreateFrame("Frame", nil, plate.health)
        bf:SetAllPoints(plate.health)
        plate._customBorder = bf
    end
    -- Health bars flatten render layers: a BORDER-layer backdrop would be clipped by the
    -- ARTWORK health fill, so lift it onto MEDIUM strata (same escape the plate uses for
    -- text/aura layers). Set before ApplyBorderStyle so any backdrop child it creates inherits it.
    bf:SetFrameStrata("MEDIUM")
    bf:SetFrameLevel(behind and math.max(1, plate.health:GetFrameLevel() - 1) or (plate.health:GetFrameLevel() + 1))
    EllesmereUI.ApplyBorderStyle(bf, sz, col.r, col.g, col.b, a, tex,
        p and p.customBorderOffset, p and p.customBorderOffsetY,
        p and p.customBorderShiftX, p and p.customBorderShiftY,
        "nameplates", sz)
end
function ns.ApplyCustomBorderColor(plate)
    if not plate or not plate._customBorder then return end
    if not (EllesmereUI and EllesmereUI.SetBorderStyleColor) then return end
    local col = (p and p.customBorderColor) or defaults.customBorderColor
    local a   = (p and p.customBorderAlpha) or defaults.customBorderAlpha or 1
    EllesmereUI.SetBorderStyleColor(plate._customBorder, col.r, col.g, col.b, a)
end
function ns.HideCustomBorder(plate)
    local bf = plate and plate._customBorder
    if bf and EllesmereUI and EllesmereUI.ApplyBorderStyle then
        EllesmereUI.ApplyBorderStyle(bf, 0)
        bf:Hide()
    end
end

-- Health bar texture overlay tables (stored on ns to avoid local count pressure)
ns.healthBarTextures, ns.healthBarTextureNames, ns.healthBarTextureOrder =
    EllesmereUI.BuildBarTextureTables(true)

local function NoTintFlag(db, key)
    local v = db and db[key]
    if v == nil then v = defaults[key] end
    return v
end

local function ApplyHealthBarTexture(plate)
    local health = plate.health
    if not health then return end
    local texKey = (p and p.healthBarTexture) or defaults.healthBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    health:SetStatusBarTexture(path)
end
ns.ApplyHealthBarTexture = ApplyHealthBarTexture

-- Cast bar texture: mirrors ApplyHealthBarTexture with the same texture set (EUI built-ins +
-- SharedMedia, appended into ns.healthBarTextures at options-build time). On ns (local cap).
function ns.ApplyCastBarTexture(plate)
    local cast = plate.cast
    if not cast then return end
    local texKey = (p and p.castBarTexture) or defaults.castBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    cast:SetStatusBarTexture(path)
    -- The uninterruptible overlay is a flat WHITE8x8 (grey tint via SetAlphaFromBoolean) that
    -- would hide the fill texture; give it the same texture so the pattern shows through. The
    -- per-cast grey SetVertexColor is re-applied on every cast start, so this is safe.
    if plate.castBarOverlay then
        plate.castBarOverlay:SetTexture(path)
    end
end

function ns.ApplyAbsorbStyle(plate)
    local style = (p and p.absorbStyle) or defaults.absorbStyle
    -- blizzard/striped/clean live in NP_ABSORB_STYLE_TEX; the stripe keys
    -- (shared with the Focus Texture dropdown) resolve via ResolveOverlayTexPath.
    local tex   = ns.NP_ABSORB_STYLE_TEX[style] or ns.ResolveOverlayTexPath(style) or ns.NP_ABSORB_STYLE_TEX.blizzard
    -- Opacity applies to every style. absorbAlpha (0-100) is the single source of truth
    -- once set (slider touched or style picked); until then, per-style defaults.
    local alpha = p and p.absorbAlpha
    if alpha then
        alpha = alpha / 100
    elseif style == "clean" then
        alpha = ((p and p.absorbCleanAlpha) or defaults.absorbCleanAlpha or 30) / 100
    else
        alpha = ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8
    end
    -- Tint applies to every style EXCEPT Blizzard, which keeps its own coloring.
    local r, g, b = 1, 1, 1
    if style ~= "blizzard" then
        local c = (p and p.absorbColor) or defaults.absorbColor
        if c then r, g, b = c.r, c.g, c.b end
    end
    local mask = plate._absorbMask
    for _, bar in ipairs({ plate.absorb, plate.absorbForward, plate.absorbOverflow }) do
        if bar then
            bar:SetStatusBarTexture(tex)
            bar:SetStatusBarColor(r, g, b, alpha)
            local fill = bar:GetStatusBarTexture()
            if fill then
                fill:SetDrawLayer("ARTWORK", 1)
                if mask then fill:AddMaskTexture(mask) end
            end
        end
    end
end

function ns.ApplyAbsorbStyleAll()
    for _, plate in pairs(ns.plates) do
        ns.ApplyAbsorbStyle(plate)
    end
end

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
local function GetPandemicGlow()
    return (p and p.pandemicGlow) or defaults.pandemicGlow
end

-- Pandemic glow style definitions.
-- 1 = Pixel Glow (procedural ants), 2 = Action Button Glow (animated ants texture),
-- 3 = Auto-Cast Shine (orbiting sparkles), 4 = GCD (FlipBook atlas),
-- 5 = Modern WoW Glow (FlipBook atlas), 6 = Classic WoW Glow (FlipBook texture)
local PANDEMIC_GLOW_STYLES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Action Button Glow",   buttonGlow = true, scale = 1.36, previewScale = 1.28 },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  scale = 1.47, previewScale = 1.47 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  scale = 1.34, previewScale = 1.34 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, scale = 1.47, previewScale = 1.47 },
}
ns.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
-- Exposed cross-addon (e.g. CDM "Apply Pandemic Glow to all" sync) so styles translate by NAME,
-- never raw index: this list omits "Custom Shape Glow", so the same index differs per side.
if EllesmereUI then EllesmereUI.NameplatePandemicGlowStyles = PANDEMIC_GLOW_STYLES end

-- PANDEMIC_GLOW_STYLES index -> shared EllesmereUI.Glows.STYLES index. The NP
-- list omits Shape Glow (shared index 4), so every flipbook entry sits one lower
-- here. Lives beside the list it translates FROM on purpose: a second copy is how
-- the two drift the first time a style is inserted into either one. On ns, not
-- a file local: this chunk sits at the Lua 5.1 200-local cap.
ns.NP_TO_SHARED_GLOW = { 1, 2, 3, 5, 6, 7 }

local function GetPandemicGlowStyle()
    local raw = p and p.pandemicGlowStyle
    if raw == nil then return defaults.pandemicGlowStyle end
    if type(raw) == "number" then return raw end
    return 1
end
ns.GetPandemicGlowStyle = GetPandemicGlowStyle
local function GetPandemicGlowColor()
    local c = (p and p.pandemicGlowColor) or defaults.pandemicGlowColor
    return c.r, c.g, c.b
end
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
-- On ns, not file-scope locals (Lua 5.1 200-local cap); both still close over the p/defaults upvalues.
function ns.GetPandemicGlowBackground()
    return p and p.pandemicGlowBackground == true
end
function ns.GetPandemicGlowBackgroundColor()
    local c = (p and p.pandemicGlowBackgroundColor) or defaults.pandemicGlowBackgroundColor
    return c.r or 0, c.g or 0, c.b or 0
end

-- Offensive dispel capability. This asks what the PLAYER knows, never what an
-- aura is, so it keeps working in restricted content, where a tainted addon's
-- aura reads are denied outright rather than merely classified.
do
    local _, playerClass = UnitClass("player")
    -- { spellID, category ("Magic", "Enrage", or "Both"), requiredClass or nil, requiredTalent or nil }
    local OFFENSIVE_DISPEL_SPELLS = {
        { 370,    "Magic",  nil       },  -- Purge (Shaman)
        { 378773, "Magic",  nil       },  -- Greater Purge (Shaman)
        { 528,    "Magic",  nil       },  -- Dispel Magic (Priest)
        { 32375,  "Magic",  nil       },  -- Mass Dispel (Priest)
        { 278326, "Magic",  nil       },  -- Consume Magic (Demon Hunter)
        { 19505,  "Magic",  "WARLOCK" },  -- Devour Magic (Felhunter)
        { 19801,  "Both",   nil       },  -- Tranquilizing Shot (Hunter)
        { 2908,   "Enrage", nil       },  -- Soothe (Druid)
        { 30449,  "Magic",  nil       },  -- Spellsteal (Mage)
        { 115078, "Enrage", "MONK", 450432 },  -- Paralysis (w/ Pressure Points talent)
    }
    local canDispelMagic, canDispelEnrage = false, false
    local built = false
    local BANK = Enum and Enum.SpellBookSpellBank

    -- IsSpellKnown answers "does the player have this", which is the question a
    -- PASSIVE talent needs -- IsSpellInSpellBook says no for one. The globals
    -- this used to call (IsPlayerSpell, IsSpellKnown) exist only in
    -- Blizzard_DeprecatedSpellBook, behind the loadDeprecationFallbacks CVar and
    -- removed next expansion; with that CVar off the talent branch never fired.
    local function Knows(spellID, bank)
        if not (C_SpellBook and C_SpellBook.IsSpellKnown and BANK) then return false end
        local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID, bank or BANK.Player)
        return ok and v == true
    end
    local function InBook(spellID, bank)
        if not (C_SpellBook and BANK) then return false end
        if not C_SpellBook.IsSpellKnownOrInSpellBook then return Knows(spellID, bank) end
        local ok, v = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID, bank or BANK.Player)
        return ok and v == true
    end

    local function RebuildDispelTypes()
        local wasMagic, wasEnrage = canDispelMagic, canDispelEnrage
        canDispelMagic, canDispelEnrage = false, false
        for _, entry in ipairs(OFFENSIVE_DISPEL_SPELLS) do
            local spellID, cat, reqClass, reqTalent = entry[1], entry[2], entry[3], entry[4]
            if not (reqClass and playerClass ~= reqClass) then
                local known
                if reqTalent then
                    known = Knows(reqTalent)
                elseif reqClass then
                    -- Pet bank: true only while that pet is actually out, which
                    -- is why UNIT_PET is registered below.
                    known = InBook(spellID, BANK and BANK.Pet)
                else
                    known = InBook(spellID)
                end
                if known then
                    if cat == "Magic" or cat == "Both" then canDispelMagic = true end
                    if cat == "Enrage" or cat == "Both" then canDispelEnrage = true end
                end
            end
        end
        -- Capability picks the buff row's candidate filter, so a change has to
        -- rebuild the containers, not merely repaint them. The first pass has
        -- nothing to compare against and nothing built yet, so it never
        -- notifies -- the pool build reads capability when it runs.
        if built and (wasMagic ~= canDispelMagic or wasEnrage ~= canDispelEnrage) then
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end
        built = true
    end
    local dispelFrame = CreateFrame("Frame")
    dispelFrame:RegisterEvent("SPELLS_CHANGED")
    dispelFrame:RegisterEvent("UNIT_PET")
    -- A talent swap does not reliably reach SPELLS_CHANGED first, and without
    -- these a talent-gated entry is only correct after a /reload.
    dispelFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    dispelFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    dispelFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PET" and unit ~= "player" then return end
        RebuildDispelTypes()
    end)
    RebuildDispelTypes()

    -- canDispelMagic, canDispelEnrage. Consumed by the buff row to pick its
    -- candidate filter and by the glow gate.
    ns.GetOffensiveDispelTypes = function()
        return canDispelMagic, canDispelEnrage
    end

    ns.GetDispelGlow = function()
        return (p and p.dispelGlow) or defaults.dispelGlow
    end
    ns.GetDispelGlowStyle = function()
        local raw = p and p.dispelGlowStyle
        if raw == nil then return defaults.dispelGlowStyle end
        if type(raw) == "number" then return raw end
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
        local c = (p and p.dispelGlowColor) or defaults.dispelGlowColor
        return c.r, c.g, c.b
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
    if GetShowCastIcon() and ns.GetCastIconInWidth() and not ns.GetCastIconFullSize() then
        iconW = castH * (GetCastIconScale() or 1)
        if not ns.GetCastIconOnRight() then
            shiftX = iconW
        end
    end
    plate.cast:ClearAllPoints()
    plate.cast:SetSize(math.max(1, footprintW - iconW), castH)
    -- Cast Bar Y Offset: + up, - down; `or` fallback only fires when nil (0 is truthy in Lua).
    local offsetY = (p and p.castBarOffsetY) or defaults.castBarOffsetY
    -- Snap to whole physical pixels at the plate's own scale (nameplates have their own scale
    -- stack, not UIParent's) so the health-bottom/cast-top gap stays constant instead of
    -- oscillating +/-1px as the plate slides to fractional screen positions.
    if offsetY ~= 0 and PP then
        local plateES = plate:GetEffectiveScale()
        local onePx = (plateES and plateES > 0) and (PP.perfect / plateES) or (PP.mult or 1)
        offsetY = math.floor(offsetY / onePx + 0.5) * onePx
    end
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", shiftX, offsetY)
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
local function GetNameYOffset()
    return (p and p.nameYOffset) or defaults.nameYOffset
end
ns.GetNameYOffset = GetNameYOffset
local textSlotKeys = { "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter" }
ns.textSlotKeys = textSlotKeys

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
}
local function IsComboHealthText(element)
    return COMBO_HEALTH_ELEMENTS[element] == true
end
ns.IsComboHealthText = IsComboHealthText

local function SetCombinedHealthText(fs, element, pctText, numText)
    if element == "healthPctNum" then
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
    function ns.IsNameElement(element)
        return NAME_FAMILY[element] == true
    end
    -- Slot currently holding a name-family element (nil when none is slotted).
    function ns.FindNameSlot()
        for _, key in ipairs(textSlotKeys) do
            if NAME_FAMILY[GetTextSlot(key)] then return key end
        end
        return nil
    end
    -- Display string for the unit's EFFECTIVE level (so scaling/Chromie time read as the game
    -- ranks them). "??" for skull-ranked (-1) or unreadable (secret) levels, matching default UI.
    function ns.GetUnitLevelText(unit)
        local lvl = UnitEffectiveLevel(unit)
        if type(lvl) ~= "number" or (issecretvalue and issecretvalue(lvl))
           or lvl < 0 then
            return "??"
        end
        return tostring(lvl)
    end
    -- Write a name-family element's text into a FontString (shared by runtime update and
    -- options preview). name may be SECRET: only ever passed as a %s display arg, never inspected.
    function ns.SetNameElementText(fs, element, name, unit)
        if element == "level" then
            fs:SetFormattedText("%s", ns.GetUnitLevelText(unit))
        elseif element == "levelName" then
            fs:SetFormattedText("%s | %s", ns.GetUnitLevelText(unit), name)
        elseif element == "nameLevel" then
            fs:SetFormattedText("%s | %s", name, ns.GetUnitLevelText(unit))
        else
            fs:SetText(name)
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
    level = 24,   -- standalone level: "70" / "??"
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
        if cropped and w and h and w > 0 then
            local uSpan = 1 - 2 * AURA_ZOOM
            local vSpan = uSpan * (h / w)
            local v0 = 0.5 - vSpan / 2
            icon:SetTexCoord(AURA_ZOOM, 1 - AURA_ZOOM, v0, 1 - v0)
        else
            icon:SetTexCoord(AURA_ZOOM, 1 - AURA_ZOOM, AURA_ZOOM, 1 - AURA_ZOOM)
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
    local v = p and p.showBorder
    if v == nil then return defaults.showBorder end
    return v
end
ns.IsBorderEnabled = IsBorderEnabled
-- Per-icon 1px borders (cast / buff / debuff / CC). nil = border shown
-- (old profiles without the key keep their borders). Setting a hide key
-- to true hides the border; false shows it.
function ns.GetIconBorderEnabled(kind)
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
local function GetBorderColor()
    local c = (p and p.borderColor) or defaults.borderColor
    return c.r, c.g, c.b
end
ns.GetBorderColor = GetBorderColor
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
    if dg.animGroup then dg.animGroup:Stop() end
    if dg.flipTex then dg.flipTex:Hide() end
    StopProceduralAnts(dg.wrapper)
    StopButtonGlow(dg.wrapper)
    StopAutoCastShine(dg.wrapper)
    dg.wrapper:Hide()
    dg.active = false
end

-- Preview only: the live nameplate glow runs through EllesmereUI.Glows on the
-- engine buttons. dispelType is "magic" / "enrage" / nil.
local function StartDispelGlow(slot, slotSize, dispelType)
    local dg = slot.dispelGlow
    local styleIdx = ns.GetDispelGlowStyle()
    local styles = PANDEMIC_GLOW_STYLES
    if styleIdx < 1 or styleIdx > #styles then styleIdx = 2 end
    local entry = styles[styleIdx]
    local sz = slotSize or 26

    if not dg then
        local wrapper = CreateFrame("Frame", nil, slot)
        wrapper:SetAllPoints()
        wrapper:SetFrameLevel(slot:GetFrameLevel() + 5)
        local flipTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        flipTex:SetPoint("CENTER")
        local animGroup = flipTex:CreateAnimationGroup()
        animGroup:SetLooping("REPEAT")
        local flipAnim = animGroup:CreateAnimation("FlipBook")
        wrapper:Show()
        dg = { wrapper = wrapper, flipTex = flipTex, animGroup = animGroup, flipAnim = flipAnim, active = false }
        slot.dispelGlow = dg
    end

    -- Only restart glow if style changed or not active
    if dg.active and dg.styleIdx == styleIdx then
        dg.wrapper:Show()
        return
    end
    -- Stop previous style if switching
    if dg.active then
        StopDispelGlow(slot)
    end

    local cr, cg, cb = ns.GetDispelGlowColor(dispelType)

    if entry.procedural then
        dg.flipTex:Hide()
        dg.animGroup:Stop()
        StopButtonGlow(dg.wrapper)
        StopAutoCastShine(dg.wrapper)
        -- Fixed values (no user sub-options for dispel glow pixel style)
        local N = 8; local th = 1; local speed = 4
        local period = speed
        local lineLen = math.floor((sz + sz) * (2 / N - 0.1))
        lineLen = min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        StartProceduralAnts(dg.wrapper, N, th, period, lineLen, cr, cg, cb, sz)
    elseif entry.buttonGlow then
        dg.flipTex:Hide()
        dg.animGroup:Stop()
        StopProceduralAnts(dg.wrapper)
        StopAutoCastShine(dg.wrapper)
        StartButtonGlow(dg.wrapper, sz, cr, cg, cb, entry.scale or 1.36)
    elseif entry.autocast then
        dg.flipTex:Hide()
        dg.animGroup:Stop()
        StopProceduralAnts(dg.wrapper)
        StopButtonGlow(dg.wrapper)
        StartAutoCastShine(dg.wrapper, sz, cr, cg, cb)
    else
        -- FlipBook-based glow (GCD, Modern, Classic); matches the pandemic pattern
        StopProceduralAnts(dg.wrapper)
        StopButtonGlow(dg.wrapper)
        StopAutoCastShine(dg.wrapper)
        local flipTex = dg.flipTex
        local animGroup = dg.animGroup
        local flipAnim = dg.flipAnim

        local texSz = sz * (entry.scale or 1)
        flipTex:SetSize(texSz, texSz)
        if entry.atlas then
            flipTex:SetAtlas(entry.atlas)
        elseif entry.texture then
            flipTex:SetTexture(entry.texture)
        end
        flipAnim:SetFlipBookRows(entry.rows or 6)
        flipAnim:SetFlipBookColumns(entry.columns or 5)
        flipAnim:SetFlipBookFrames(entry.frames or 30)
        flipAnim:SetDuration(entry.duration or 1.0)
        flipAnim:SetFlipBookFrameWidth(entry.frameW or 0)
        flipAnim:SetFlipBookFrameHeight(entry.frameH or 0)

        flipTex:SetDesaturated(true)
        flipTex:SetVertexColor(cr, cg, cb)
        flipTex:Show()
        animGroup:Play()
    end

    dg.wrapper:Show()
    dg.active = true
    dg.styleIdx = styleIdx
    -- Always opaque. Visibility used to ride a per-aura dispel-type curve's
    -- alpha; dispellability is now decided by which aura GROUP the button
    -- belongs to, and this path only ever draws the options preview.
    dg.wrapper:SetAlpha(1)
end

ns.StopDispelGlow = StopDispelGlow
ns.StartDispelGlow = StartDispelGlow
end -- do (glow engine)

-- Forward declaration (defined later in the class power section)
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
        local sideOff = GetSideAuraXOffset()
        for i = 1, count do
            frames[i]:ClearAllPoints()
            PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "BOTTOMLEFT",
                -sideOff - (i - 1) * spacing + xOff, yOff)
        end
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset()
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
        if slot == "left" then
            -- Left edge of leftmost icon: -(sideOff + (shown-1)*sp + sz) + xOff
            local ext = sideOff + (shown - 1) * sp + sz - xOff
            leftExtent = math.max(leftExtent, ext)
        elseif slot == "right" then
            local ext = sideOff + (shown - 1) * sp + sz + xOff
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

-------------------------------------------------------------------------------
--  Lazy-creation helpers for target-only/focus-only UI objects: needed on 1 plate at a time,
--  so building them on every pooled plate wastes memory. Each Ensure* is idempotent.
-------------------------------------------------------------------------------
local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
local GLOW_MARGIN = 0.48
local GLOW_CORNER = 12
local GLOW_EXTEND = 6

local function EnsureGlow(plate)
    if plate.glow then return end
    plate.glowFrame = CreateFrame("Frame", nil, plate)
    plate.glowFrame:SetFrameStrata("BACKGROUND")
    plate.glowFrame:SetFrameLevel(1)
    plate.glowFrame:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    plate.glowFrame:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    -- Glow tint/opacity come from the target "Glow Color" setting; textures are collected so ApplyTarget can recolor them live.
    plate.glowTextures = {}
    local gc = ns.GetTargetGlowColor()
    local ga = ns.GetTargetGlowAlpha()
    local function MkTex()
        local t = plate.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(gc.r, gc.g, gc.b, ga)
        t:SetBlendMode("ADD")
        plate.glowTextures[#plate.glowTextures + 1] = t
        return t
    end
    plate.glowTL = MkTex(); plate.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowTL:SetPoint("TOPLEFT"); plate.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowTR = MkTex(); plate.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowTR:SetPoint("TOPRIGHT"); plate.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    plate.glowBL = MkTex(); plate.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowBL:SetPoint("BOTTOMLEFT"); plate.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowBR = MkTex(); plate.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER); plate.glowBR:SetPoint("BOTTOMRIGHT"); plate.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    plate.glowTop = MkTex(); plate.glowTop:SetHeight(GLOW_CORNER); plate.glowTop:SetPoint("TOPLEFT", plate.glowTL, "TOPRIGHT"); plate.glowTop:SetPoint("TOPRIGHT", plate.glowTR, "TOPLEFT"); plate.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowBottom = MkTex(); plate.glowBottom:SetHeight(GLOW_CORNER); plate.glowBottom:SetPoint("BOTTOMLEFT", plate.glowBL, "BOTTOMRIGHT"); plate.glowBottom:SetPoint("BOTTOMRIGHT", plate.glowBR, "BOTTOMLEFT"); plate.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowLeft = MkTex(); plate.glowLeft:SetWidth(GLOW_CORNER); plate.glowLeft:SetPoint("TOPLEFT", plate.glowTL, "BOTTOMLEFT"); plate.glowLeft:SetPoint("BOTTOMLEFT", plate.glowBL, "TOPLEFT"); plate.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glowRight = MkTex(); plate.glowRight:SetWidth(GLOW_CORNER); plate.glowRight:SetPoint("TOPRIGHT", plate.glowTR, "BOTTOMRIGHT"); plate.glowRight:SetPoint("BOTTOMRIGHT", plate.glowBR, "TOPRIGHT"); plate.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Center fill: covers the gap between top/bottom edges inside the health bar
    plate.glowCenter = MkTex(); plate.glowCenter:SetPoint("TOPLEFT", plate.glowLeft, "TOPRIGHT"); plate.glowCenter:SetPoint("BOTTOMRIGHT", plate.glowRight, "BOTTOMLEFT"); plate.glowCenter:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glow = plate.glowFrame
    plate.glowFrame:Hide()
end

-- Execute Pulse Glow (Extras, default off): red glow around the health bar pulsing while the
-- unit is inside the PLAYER'S execute window (health fraction below which their spec's execute
-- becomes usable; per-spec, talent-adjusted, table below). A no-execute spec disables the
-- feature outright: no frame/texture/animation/per-update work. Secret-value design: the
-- below-threshold gate is a C_CurveUtil color curve evaluated C-side by UnitHealthPercent,
-- feeding SetVertexColor (accepts secret components) directly, so Lua never branches on health.
-- The pulse is a looping C-side Alpha animation (no Lua ticks), so it renders identically inside
-- and outside restricted (secret) combat. Frame alpha (pulse) and texture vertex alpha (gate)
-- are separate channels that multiply, so they never fight. Cache lives in a do-block (no
-- main-chunk local slots, near-cap file).
do
    -- Execute windows by SPEC ID: requires = gate spell ids (none = no execute at all);
    -- base = health fraction once gated; talents = ids that RAISE the window (any one enough);
    -- talentPct = the raised fraction. A spec absent from this table has no execute; inert.
    -- Keyed by id, never by localized name.
    local EXEC = {
        [252] = { base = 0.35 },  -- Death Knight: Unholy only
        -- Hunter: Marksmanship always; Beast Mastery needs its gate talent; Survival has none.
        [253] = { requires = { 466930 }, base = 0.20 },
        [254] = { base = 0.20 },
        [63]  = { base = 0.30 },  -- Mage: Fire only
        -- Monk/Rogue: DISABLED (entries removed, both absent from EXEC_CLASSES below). To
        -- restore: Monk gate 322113/base 0.15 all specs; Rogue (Assassination) gate 381798/base 0.35.
        -- Priest: all three specs.
        [256] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [257] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [258] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        -- Warlock: Affliction (Drain Soul gate) and Destruction (Shadowburn gate); Demonology none.
        [265] = { requires = { 388667 }, base = 0.20 },
        [267] = { requires = { 17877 }, base = 0.20 },
        -- Warrior: all three specs; either talent raises the window.
        [71]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [72]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [73]  = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        -- No entries for Demon Hunter, Druid, Evoker, Paladin or Shaman.
    }
    -- Classes with at least one execute spec; everyone else never registers the watcher (threshold
    -- stays nil all session, every entry point early-outs on one upvalue read). Must stay in step
    -- with EXEC -- a class listed here with no specs there registers a watcher for nothing.
    local EXEC_CLASSES = {
        DEATHKNIGHT = true, HUNTER = true, MAGE = true,
        PRIEST = true, WARLOCK = true, WARRIOR = true,
        -- MONK = true,
        -- ROGUE = true,
    }

    local threshold = nil     -- current execute fraction; nil = no execute
    local lowCurve, curveAt   -- cached curve + the threshold it was built for

    local function AnyKnown(ids)
        local sb = C_SpellBook
        if not (sb and sb.IsSpellKnown) then return false end
        for i = 1, #ids do
            if sb.IsSpellKnown(ids[i]) then return true end
        end
        return false
    end

    local function Resolve()
        local specID = EllesmereUI._specID
        if (not specID or specID == 0) and EllesmereUI._RefreshSpecID then
            EllesmereUI._RefreshSpecID()
            specID = EllesmereUI._specID
        end
        local def = specID and EXEC[specID]
        if not def then return nil end
        -- Gate first: an unmet requirement means no execute exists at all.
        if def.requires and not AnyKnown(def.requires) then return nil end
        local pct = def.base
        if def.talents and AnyKnown(def.talents) then
            if not pct or def.talentPct > pct then pct = def.talentPct end
        end
        return pct
    end

    --- The player's current execute-window fraction, or nil when this spec
    --- and talent build has no execute (feature fully disabled).
    function ns.GetExecuteThreshold()
        return threshold
    end

    function ns.GetLowHpGlowCurve()
        local t = threshold
        if not t then return nil end
        if lowCurve and curveAt == t then return lowCurve end
        if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent) then return nil end
        local curve = C_CurveUtil.CreateColorCurve()
        local EPSILON = 0.0001
        -- At or below the execute threshold -> red; above -> BLACK, which contributes
        -- nothing under the glow textures' ADD blend, so the glow disappears. Alpha
        -- stays 1 at every point and only RGB varies: curve alpha interpolation is
        -- deliberately never relied on. Rebuilt only when the threshold itself changes.
        curve:AddPoint(0.0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t + EPSILON, CreateColor(0, 0, 0, 1))
        curve:AddPoint(1.0, CreateColor(0, 0, 0, 1))
        lowCurve, curveAt = curve, t
        return curve
    end

    -- Spec + talent watcher, built ONLY for a class that can have an execute. Talents cannot
    -- change in combat, so these events cost nothing at runtime.
    do
        local _, cls = UnitClass("player")
        if EXEC_CLASSES[cls] then
            local watcher = CreateFrame("Frame")
            watcher:RegisterEvent("PLAYER_LOGIN")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
            watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
            watcher:SetScript("OnEvent", function()
                local new = Resolve()
                if new == threshold then return end
                threshold = new
                lowCurve, curveAt = nil, nil
                -- Re-apply per plate: the gate creates/tears down the whole effect, so
                -- gaining/losing an execute flips the glow with no settings change.
                if ns.plates and ns.ApplyLowHpGlow then
                    for _, plate in pairs(ns.plates) do
                        ns.ApplyLowHpGlow(plate)
                    end
                end
            end)
        end
    end
end

function ns.EnsureLowHpGlow(plate)
    if plate.lowHpGlowFrame then return end
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    plate.lowHpGlowFrame = f
    local texs = {}
    plate.lowHpGlowTextures = texs
    local function MkTex()
        local t = f:CreateTexture(nil, "BACKGROUND")
        -- Dedicated art (not the shared target-glow texture) so brightness can be tuned without touching the target glow.
        t:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(0, 0, 0, 1)  -- black = invisible under ADD blend until the first health eval
        t:SetBlendMode("ADD")
        texs[#texs + 1] = t
        return t
    end
    -- Same 9-slice layout as the target glow (EnsureGlow) so the two effects share one visual language.
    local tl = MkTex(); tl:SetSize(GLOW_CORNER, GLOW_CORNER); tl:SetPoint("TOPLEFT"); tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex(); tr:SetSize(GLOW_CORNER, GLOW_CORNER); tr:SetPoint("TOPRIGHT"); tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex(); bl:SetSize(GLOW_CORNER, GLOW_CORNER); bl:SetPoint("BOTTOMLEFT"); bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex(); br:SetSize(GLOW_CORNER, GLOW_CORNER); br:SetPoint("BOTTOMRIGHT"); br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local top = MkTex(); top:SetHeight(GLOW_CORNER); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT"); top:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex(); bot:SetHeight(GLOW_CORNER); bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT"); bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex(); lft:SetWidth(GLOW_CORNER); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT"); lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex(); rgt:SetWidth(GLOW_CORNER); rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT"); rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex(); ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT"); ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT"); ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Pulse: C-side alpha loop on the frame; only advances while shown.
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.55)
    a:SetSmoothing("IN_OUT")
    plate.lowHpGlowPulse = ag
end

function ns.ApplyLowHpGlow(plate)
    -- Two hard gates: setting on AND spec/talents have an execute window. Failing either,
    -- nothing is created; the health-update eval short-circuits on a nil texture list.
    if not (p and p.lowHpGlow == true) or not ns.GetExecuteThreshold() then
        if plate.lowHpGlowFrame then
            plate.lowHpGlowPulse:Stop()
            plate.lowHpGlowFrame:Hide()
        end
        return
    end
    ns.EnsureLowHpGlow(plate)
    plate.lowHpGlowFrame:Show()
    if not plate.lowHpGlowPulse:IsPlaying() then plate.lowHpGlowPulse:Play() end
end

-- Near-aggro glow (Non-Tank Threat cog): the execute glow's exact 9-slice
-- visual -- same art, extend, corner geometry, ADD blend -- at STATIC
-- full-alpha red: no pulse animation and no health curve. Visibility alone is
-- the signal, driven from UpdateHealthColor's own Near Aggro color decision
-- (clean threat booleans, so it behaves identically in and out of restriction).
function ns.EnsureNearAggroGlow(plate)
    if plate.naGlowFrame then return end
    local f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    f:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    f:Hide()
    plate.naGlowFrame = f
    local function MkTex()
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(1, 0, 0, 1)  -- static execute red, full alpha
        t:SetBlendMode("ADD")
        return t
    end
    local tl = MkTex(); tl:SetSize(GLOW_CORNER, GLOW_CORNER); tl:SetPoint("TOPLEFT"); tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex(); tr:SetSize(GLOW_CORNER, GLOW_CORNER); tr:SetPoint("TOPRIGHT"); tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex(); bl:SetSize(GLOW_CORNER, GLOW_CORNER); bl:SetPoint("BOTTOMLEFT"); bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex(); br:SetSize(GLOW_CORNER, GLOW_CORNER); br:SetPoint("BOTTOMRIGHT"); br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local top = MkTex(); top:SetHeight(GLOW_CORNER); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT"); top:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex(); bot:SetHeight(GLOW_CORNER); bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT"); bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex(); lft:SetWidth(GLOW_CORNER); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT"); lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex(); rgt:SetWidth(GLOW_CORNER); rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT"); rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex(); ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT"); ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT"); ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
end

-- Highlight target style: translucent wash across the target's health bar. Lazy (only the
-- target ever shows it), kept SEPARATE from plate.highlight (mouseover) so the two never fight.
local function EnsureTargetHighlight(plate)
    if plate.targetHighlight then return end
    local t = plate.health:CreateTexture(nil, "OVERLAY", nil, 5)
    t:SetAllPoints(plate.health)
    local c = ns.GetTargetHighlightColor()
    t:SetColorTexture(c.r, c.g, c.b, ns.GetTargetHighlightAlpha())
    t:Hide()
    plate.targetHighlight = t
end

-- Target arrow styles: key -> { l=left texture, r=right texture, w=drawn width at height 16
-- (scale 1), label }. All source art is 66px tall; w = round(nativeWidth * 11/36): 36->11,
-- 72->22, 90->28. Height always 16. Shared by enemy/friendly plates + options.
ns.TARGET_ARROW_DIR = "Interface\\AddOns\\EllesmereUINameplates\\Media\\Arrows\\"
ns.TARGET_ARROW_STYLES = {
    simple    = { l = "arrow_left",      r = "arrow_right",      w = 11, label = "Simple Arrows" },
    double    = { l = "arrow_leftx2",    r = "arrow_rightx2",    w = 22, label = "Double Arrows" },
    barbed    = { l = "barbed-left",     r = "barbed-right",     w = 28, label = "Barbed" },
    bracket   = { l = "bracket-left",    r = "bracket-right",    w = 22, label = "Bracket" },
    celestial = { l = "celestial-left",  r = "celestial-right",  w = 28, label = "Celestial" },
    classic   = { l = "classic-left",    r = "classic-right",    w = 22, label = "Classic" },
    crystal   = { l = "crystal-left",    r = "crystal-right",    w = 22, label = "Crystal" },
    curved    = { l = "curved-left",     r = "curved-right",     w = 22, label = "Curved" },
    demon     = { l = "demon-left",      r = "demon-right",      w = 28, label = "Demon" },
    diamond   = { l = "diamond-left",    r = "diamond-right",    w = 28, label = "Diamond" },
    feathered = { l = "feathered-left",  r = "feathered-right",  w = 22, label = "Feathered" },
    halo      = { l = "halo-left",       r = "halo-right",       w = 22, label = "Halo" },
    holyspear = { l = "holy-spear-left", r = "holy-spear-right", w = 28, label = "Holy Spear" },
    rune      = { l = "rune-left",       r = "rune-right",       w = 22, label = "Rune" },
    split     = { l = "split-left",      r = "split-right",      w = 22, label = "Split" },
    winged    = { l = "winged-left",     r = "winged-right",     w = 28, label = "Winged" },
}
ns.TARGET_ARROW_ORDER = {
    "simple", "double", "winged", "feathered", "split", "celestial", "rune", "demon",
    "halo", "curved", "barbed", "holyspear", "bracket", "diamond", "crystal", "classic",
}

-- Resolve a profile to its arrow style table. targetArrowStyle is the current key; legacy profiles fall back to targetArrowDouble (then Simple).
function ns.ResolveTargetArrowStyle(prof)
    local key = prof and (prof.targetArrowStyle or (prof.targetArrowDouble and "double")) or nil
    return ns.TARGET_ARROW_STYLES[key] or ns.TARGET_ARROW_STYLES.simple
end

-- Target arrow tint: the player's class color when targetArrowClassColor is on, else the custom targetArrowColor (default white).
function ns.GetTargetArrowColor(prof)
    if prof and prof.targetArrowClassColor then
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[PLAYER_CLASS]
        if cc then return cc.r, cc.g, cc.b end
        return 1, 1, 1
    end
    local c = prof and prof.targetArrowColor
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function EnsureArrows(plate)
    if plate.leftArrow then return end
    local st = ns.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw, ah = math.floor(st.w * sc + 0.5), math.floor(16 * sc + 0.5)
    -- Regions OF the health bar (the plate subtree is aspect-restricted and unmeasurable). NO
    -- creation anchors: single-point + size rects render DISPLACED inside the restricted tree,
    -- so the only sanctioned form is the fully-anchored TOP+BOTTOM scheme from
    -- PositionArrowsOutsideAuras (runs on every target apply, after Show()). An unanchored
    -- hidden texture has no rect and draws nothing, so the creation state is safe. Rendering
    -- outside the bar rect is fine (health SetClipsChildren(false)).
    local arrowParent = plate.health
        -- Aura containers carry UntrustedLayoutScriptExecution once they hold a group, and only
        -- aspect-bearing objects may anchor to them. Aspects cannot be gained later
        -- (SetParent/SetPoint inheritance is blocked), so arrows must be BORN inside a template
        -- holder to inherit its aspect; the containers file then anchors them to the side aura
        -- containers. Clients without the template keep the plain parent (no aspect needed).
        local ok, holder = pcall(CreateFrame, "Frame", nil, plate.health,
            "DisableUntrustedLayoutScriptsTemplate")
        if ok and holder then
            holder:SetAllPoints(plate.health)
            holder:SetFrameLevel(plate.health:GetFrameLevel())
            plate.arrowHost = holder
            arrowParent = holder
        end
    plate.leftArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
    plate.rightArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
    PP.Size(plate.leftArrow, aw, ah)
    plate.leftArrow:Hide()
    PP.Size(plate.rightArrow, aw, ah)
    plate.rightArrow:Hide()
end

-- Target/Focus overlay textures: stripe overlays live in the nameplates Media folder (resolved
-- by name); everything else resolves through the shared health-bar lookup (EUI + SharedMedia).
ns.OVERLAY_STRIPE_KEYS = {
    ["striped-v2"] = true, ["striped-wide-v2"] = true, ["stripes-medium"] = true,
    ["stripes-small-close"] = true, ["stripes-small-spread"] = true, ["striped-tiny"] = true,
}
function ns.ResolveOverlayTexPath(key)
    if not key or key == "none" then return nil end
    if ns.OVERLAY_STRIPE_KEYS[key] then
        return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
    end
    if EllesmereUI.ResolveTexturePath then
        return EllesmereUI.ResolveTexturePath(ns.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    end
    return nil
end

-- Both overlays span the full bar width (anchored LEFT+RIGHT to the health bar) so the pattern
-- covers the whole bar and follows Health Bar Width changes. Fill and bg share identical
-- geometry so a stripe's diagonal stays continuous across the fill/background split; clip
-- frames window the filled vs empty portions. Stripes additionally CROP via texcoord to the
-- bar's share of the pattern's native 200px span (constant density up to 200 wide, wider bars
-- stretch the full pattern). Width comes from settings, never from measuring the plate subtree
-- (restricted regions forbid reads there).
local STRIPE_NATIVE_W = 200
local function ApplyOverlayGeometry(fillT, bgT, health, isStripe)
    fillT:ClearAllPoints(); bgT:ClearAllPoints()
    fillT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    fillT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    fillT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    bgT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    bgT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    bgT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    local u = 1
    if isStripe then
        u = GetHealthBarWidth() / STRIPE_NATIVE_W
        if u > 1 then u = 1 end
    end
    fillT:SetTexCoord(0, u, 0, 1)
    bgT:SetTexCoord(0, u, 0, 1)
end

-- Alpha for the empty (background) portion of an overlay. The "Full alpha on empty part of
-- bar" toggle matches the filled portion's opacity; else dimmed to 30% so fill reads as "more filled".
local function OverlayBgAlpha(fullFlag, fillAlpha)
    if fullFlag then return fillAlpha end
    return fillAlpha * 0.3
end

local function EnsureFocusOverlay(plate)
    if plate.focusClipFill then return end
    local overlayAlpha = (p and p.focusOverlayAlpha) or defaults.focusOverlayAlpha
    local overlayColor = (p and p.focusOverlayColor) or defaults.focusOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.focusClipFill = CreateFrame("Frame", nil, plate.health)
    plate.focusClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    plate.focusClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.focusClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayFill = plate.focusClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    plate.focusOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.focusOverlayFill:SetTexture(STRIPE_TEX)
    plate.focusOverlayFill:SetAlpha(overlayAlpha)
    plate.focusOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.focusClipFill:Hide()
    plate.focusClipBg = CreateFrame("Frame", nil, plate.health)
    plate.focusClipBg:SetClipsChildren(true)
    plate.focusClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.focusClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.focusClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.focusClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayBg = plate.focusClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.focusOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.focusOverlayBg:SetTexture(STRIPE_TEX)
    plate.focusOverlayBg:SetAlpha(OverlayBgAlpha(p and p.focusOverlayFullBgAlpha, overlayAlpha))
    plate.focusOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.focusOverlayFill, plate.focusOverlayBg, plate.health, true)
    plate.focusClipBg:Hide()
end

ns.FOCUS_LETTER_ANCHORS = {
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    BOTTOM = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

function ns.GetFocusLetterAnchor(db)
    local anchor = (db and db.focusLetterAnchor) or defaults.focusLetterAnchor
    return ns.FOCUS_LETTER_ANCHORS[anchor] and anchor or defaults.focusLetterAnchor
end

function ns.EnsureFocusLetter(plate)
    if plate.focusLetter then return end
    plate.focusLetter = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    plate.focusLetter:SetJustifyH("CENTER")
    plate.focusLetter:SetJustifyV("MIDDLE")
    plate.focusLetter:Hide()
end

function ns.ApplyFocusLetter(plate, unit, db)
    if db.focusLetterEnabled == true and UnitIsUnit(unit, "focus") then
        ns.EnsureFocusLetter(plate)
        local size = db.focusLetterSize or defaults.focusLetterSize
        local anchor = ns.GetFocusLetterAnchor(db)
        local x = db.focusLetterX or defaults.focusLetterX
        local y = db.focusLetterY or defaults.focusLetterY
        local font = GetFont()
        local outline = GetNPOutline()
        if not plate._focusLetterShown
            or plate._focusLetterSize ~= size
            or plate._focusLetterAnchor ~= anchor
            or plate._focusLetterX ~= x
            or plate._focusLetterY ~= y
            or plate._focusLetterFont ~= font
            or plate._focusLetterOutline ~= outline then
            plate._focusLetterShown = true
            plate._focusLetterSize = size
            plate._focusLetterAnchor = anchor
            plate._focusLetterX = x
            plate._focusLetterY = y
            plate._focusLetterFont = font
            plate._focusLetterOutline = outline
            SetFSFont(plate.focusLetter, size, outline)
            plate.focusLetter:SetText("F")
            plate.focusLetter:ClearAllPoints()
            plate.focusLetter:SetPoint(anchor, plate.health, anchor, x, y)
            plate.focusLetter:SetTextColor(1, 1, 1, 1)
        end
        plate.focusLetter:Show()
    elseif plate.focusLetter then
        plate._focusLetterShown = nil
        plate.focusLetter:Hide()
    end
end

ns.EnsureHoverOverlay = function(plate)
    if plate.hoverClipFill then return end
    local overlayAlpha = (p and p.hoverAlpha) or defaults.hoverAlpha
    local overlayColor = (p and p.hoverColor) or defaults.hoverColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.hoverClipFill = CreateFrame("Frame", nil, plate.health)
    plate.hoverClipFill:SetClipsChildren(true)
    plate.hoverClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.hoverClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.hoverOverlayFill = plate.hoverClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.hoverOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.hoverOverlayFill:SetTexture(STRIPE_TEX)
    plate.hoverOverlayFill:SetAlpha(overlayAlpha)
    plate.hoverOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.hoverClipFill:Hide()
    plate.hoverClipBg = CreateFrame("Frame", nil, plate.health)
    plate.hoverClipBg:SetClipsChildren(true)
    plate.hoverClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.hoverClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.hoverClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.hoverClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.hoverOverlayBg = plate.hoverClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.hoverOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.hoverOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.hoverOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.hoverOverlayBg:SetTexture(STRIPE_TEX)
    plate.hoverOverlayBg:SetAlpha(OverlayBgAlpha(p and p.hoverOverlayFullBgAlpha, overlayAlpha))
    plate.hoverOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.hoverOverlayFill, plate.hoverOverlayBg, plate.health, true)
    plate.hoverClipBg:Hide()
end

ns.EnsureTargetOverlay = function(plate)
    if plate.targetClipFill then return end
    local overlayAlpha = (p and p.targetOverlayAlpha) or defaults.targetOverlayAlpha
    local overlayColor = (p and p.targetOverlayColor) or defaults.targetOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    plate.targetClipFill = CreateFrame("Frame", nil, plate.health)
    plate.targetClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    plate.targetClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.targetClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.targetOverlayFill = plate.targetClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    plate.targetOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetOverlayFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetOverlayFill:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.targetOverlayFill:SetTexture(STRIPE_TEX)
    plate.targetOverlayFill:SetAlpha(overlayAlpha)
    plate.targetOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.targetClipFill:Hide()
    plate.targetClipBg = CreateFrame("Frame", nil, plate.health)
    plate.targetClipBg:SetClipsChildren(true)
    plate.targetClipBg:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.targetClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.targetClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    plate.targetClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.targetOverlayBg = plate.targetClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.targetOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetOverlayBg:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetOverlayBg:SetPoint("RIGHT", plate.health, "RIGHT", 0, 0)
    plate.targetOverlayBg:SetTexture(STRIPE_TEX)
    plate.targetOverlayBg:SetAlpha(OverlayBgAlpha(p and p.targetOverlayFullBgAlpha, overlayAlpha))
    plate.targetOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(plate.targetOverlayFill, plate.targetOverlayBg, plate.health, true)
    plate.targetClipBg:Hide()
end

local frameCache = CreateFramePool("Frame", UIParent, nil, nil, false, function(plate)
    plate:SetFlattensRenderLayers(true)
    plate.health = CreateFrame("StatusBar", nil, plate)
    plate.health:SetFrameLevel(10)
    plate.health:SetPoint("CENTER", plate, "CENTER", 0, GetNameplateYOffset())
    plate.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    plate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.health:SetClipsChildren(false)
    plate.healthBG = plate.health:CreateTexture(nil, "BACKGROUND")
    plate.healthBG:SetAllPoints()
    local _bg = (p and p.bgColor) or defaults.bgColor
    local _bga = (p and p.bgAlpha) or defaults.bgAlpha
    plate.healthBG:SetColorTexture(_bg.r, _bg.g, _bg.b, _bga)
    -- Hash line: thin vertical marker at a configurable health percentage
    plate.hashLine = plate.health:CreateTexture(nil, "OVERLAY", nil, 3)
    plate.hashLine:SetColorTexture(1, 1, 1, 0.8)
    plate.hashLine:SetWidth(2)
    plate.hashLine:SetPoint("TOP", plate.health, "TOP", 0, 0)
    plate.hashLine:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, 0)
    plate.hashLine:Hide()
    -- Mask texture: constrains absorb rendering to exact health bar bounds at the GPU level,
    -- preventing the 1px subpixel bleed absorb textures show at certain nameplate positions.
    local absorbMask = plate.health:CreateMaskTexture()
    absorbMask:SetAllPoints(plate.health)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    plate._absorbMask = absorbMask

    plate.absorb = CreateFrame("StatusBar", nil, plate.health)
    plate.absorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    plate.absorb:GetStatusBarTexture():AddMaskTexture(absorbMask)
    plate.absorb:SetReverseFill(true)
    plate.absorb:SetPoint("TOPRIGHT", plate.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    plate.absorb:SetPoint("BOTTOMRIGHT", plate.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    plate.absorb:SetWidth(GetHealthBarWidth())
    plate.absorb:SetHeight(GetHealthBarHeight())
    plate.absorb:SetFrameLevel(plate.health:GetFrameLevel())
    plate.absorbForward = CreateFrame("StatusBar", nil, plate.health)
    plate.absorbForward:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    plate.absorbForward:GetStatusBarTexture():AddMaskTexture(absorbMask)
    plate.absorbForward:SetReverseFill(false)
    plate.absorbForward:SetPoint("TOPLEFT", plate.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    plate.absorbForward:SetPoint("BOTTOMLEFT", plate.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    plate.absorbForward:SetWidth(GetHealthBarWidth())
    plate.absorbForward:SetHeight(GetHealthBarHeight())
    plate.absorbForward:SetFrameLevel(plate.health:GetFrameLevel())
    plate.absorbForward:Hide()
    plate.absorbOverflow = CreateFrame("StatusBar", nil, plate.health)
    plate.absorbOverflow:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    plate.absorbOverflow:SetReverseFill(false)
    plate.absorbOverflow:SetPoint("TOPLEFT", plate.health, "TOPRIGHT", 0, 0)
    plate.absorbOverflow:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.absorbOverflow:SetWidth(0)
    plate.absorbOverflow:SetFrameLevel(plate.health:GetFrameLevel())
    plate.absorbOverflow:Hide()
    plate.absorbOverflowDivider = plate.health:CreateTexture(nil, "OVERLAY", nil, 7)
    plate.absorbOverflowDivider:SetColorTexture(0, 0, 0, 1)
    plate.absorbOverflowDivider:SetPoint("TOPRIGHT", plate.health, "TOPRIGHT", 0, 0)
    plate.absorbOverflowDivider:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
    plate.absorbOverflowDivider:SetWidth(1)
    plate.absorbOverflowDivider:Hide()
    if CreateUnitHealPredictionCalculator then
        plate.hpCalculator = CreateUnitHealPredictionCalculator()
        if plate.hpCalculator.SetMaximumHealthMode then
            plate.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            plate.hpCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
        end
    end
    local function AddBorder(parent)
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            PP.CreateBorder(parent, 0, 0, 0, 1, 1, "OVERLAY", 5, true)  -- scaleGuard: NP frame
        end
    end
    -- Border: single pixel-perfect PP.CreateBorder (BackdropTemplate).
    -- Two settings: showBorder (bool) and borderSize (physical pixels).
    local PP = EllesmereUI and EllesmereUI.PP
    local bc = { r = 0, g = 0, b = 0 }
    bc.r, bc.g, bc.b = GetBorderColor()
    if PP and PP.CreateBorder then
        local sz = (p and p.borderSize) or defaults.borderSize
        PP.CreateBorder(plate.health, bc.r, bc.g, bc.b, 1, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
        if not IsBorderEnabled() then PP.HideBorder(plate.health) end
    end

    function plate:ApplyBorder()
        if not PP then return end
        if ns.IsCustomBorderEnabled() then
            -- Custom border replaces the simple one: hide the PP strips on the
            -- health bar and render the custom border on its own child frame.
            PP.HideBorder(plate.health)
            ns.ApplyCustomBorderStyle(plate)
        else
            ns.HideCustomBorder(plate)
            if IsBorderEnabled() then
                local sz = (p and p.borderSize) or defaults.borderSize
                PP.SetBorderSize(plate.health, sz)
                PP.ShowBorder(plate.health)
            else
                PP.HideBorder(plate.health)
            end
        end
    end
    function plate:ApplyBorderColor()
        if not PP then return end
        if ns.IsCustomBorderEnabled() then
            ns.ApplyCustomBorderColor(plate)
        else
            local cr, cg, cb = GetBorderColor()
            PP.SetBorderColor(plate.health, cr, cg, cb, 1)
        end
    end
    -- Target glow, arrows and focus overlay are lazy (EnsureGlow / EnsureArrows /
    -- EnsureFocusOverlay): only 1 plate shows them, saving ~14 objects per plate.
    plate.healthTextFrame = CreateFrame("Frame", nil, plate)
    plate.healthTextFrame:SetAllPoints(plate.health)
    -- TEXT TIER (top). All three layered groups -- text (900), aura icons (800), indicators
    -- (raid marker/classification, ~13-18) -- use explicit MEDIUM strata so they are pulled out
    -- of the plate's flattened render layer together, ordered purely by frame level. Without
    -- it this frame stays flattened and renders BELOW the aura icons. Text > Auras > Ind.
    plate.healthTextFrame:SetFrameStrata("MEDIUM")
    plate.healthTextFrame:SetFrameLevel(900)
    plate.hpText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpText, 10, GetNPOutline())
    PP.Point(plate.hpText, "RIGHT", plate.health, "RIGHT", -2, 0)
    plate.hpNumber = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpNumber, 10, GetNPOutline())
    plate.hpNumber:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.hpNumber:Hide()
    -- Standalone level text: its own FontString so it can share the plate
    -- with the name (see the NAME_FAMILY note). Content is static per unit.
    plate.levelText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.levelText, 10, GetNPOutline())
    plate.levelText:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.levelText:Hide()
    -- Mouseover highlight: parented to the health bar (not the higher-level text
    -- frame) so it renders BEHIND the border (a child at health level + 1).
    plate.highlight = plate.health:CreateTexture(nil, "OVERLAY", nil, 6)
    plate.highlight:SetAllPoints(plate.health)
    local _hc = (p and p.hoverColor) or defaults.hoverColor
    local _ha = (p and p.hoverAlpha) or defaults.hoverAlpha
    plate.highlight:SetColorTexture(_hc.r, _hc.g, _hc.b, _ha)
    plate.highlight:Hide()
    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    plate.topTextFrame = CreateFrame("Frame", nil, plate)
    plate.topTextFrame:SetAllPoints(plate.health)
    -- TEXT TIER (see healthTextFrame). MEDIUM + level 900 so name text renders
    -- above the aura icons (the name/health fontstrings are reparented between
    -- this frame and healthTextFrame depending on the chosen text slot).
    plate.topTextFrame:SetFrameStrata("MEDIUM")
    plate.topTextFrame:SetFrameLevel(900)
    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, GetEnemyNameTextSize(), GetNPOutline())
    PP.Point(plate.name, "BOTTOM", plate.health, "TOP", 0, 4)
    PP.Width(plate.name, math.max(GetHealthBarWidth(), 20))
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)
    plate.nameRaidFrame = CreateFrame("Frame", nil, plate)
    local nameRmSize = (p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14
    PP.Size(plate.nameRaidFrame, nameRmSize, nameRmSize)
    plate.nameRaidFrame:SetFrameStrata("MEDIUM")
    plate.nameRaidFrame:SetFrameLevel(901)
    plate.nameRaidFrame:Hide()
    plate.nameRaid = plate.nameRaidFrame:CreateTexture(nil, "ARTWORK")
    plate.nameRaid:SetAllPoints()
    plate.nameRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.raidFrame = CreateFrame("Frame", nil, plate)
    local rmSize = GetRaidMarkerSize()
    PP.Size(plate.raidFrame, rmSize, rmSize)
    -- INDICATOR TIER (bottom of the three groups). Explicit MEDIUM strata like the aura icons
    -- and text, so frame level alone orders the pulled-out group: the marker (health+8=18)
    -- sits BELOW auras (800) and text (900) but above the flattened health bar. Sharing MEDIUM
    -- across all three tiers keeps order predictable -- a no-strata frame drops into flattening.
    plate.raidFrame:SetFrameStrata("MEDIUM")
    plate.raidFrame:SetFrameLevel(plate.health:GetFrameLevel() + 8)
    plate.raidFrame:Hide()
    plate.raid = plate.raidFrame:CreateTexture(nil, "ARTWORK")
    plate.raid:SetAllPoints()
    plate.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.classFrame = CreateFrame("Frame", nil, plate)
    local _reIconSz = GetRareEliteIconSize()
    PP.Size(plate.classFrame, _reIconSz, _reIconSz)
    PP.Point(plate.classFrame, "LEFT", plate.health, "LEFT", 2, 0)
    -- INDICATOR TIER (see raidFrame). MEDIUM strata + low level (health+3=13) so the
    -- classification/elite/rare/quest indicator sits below auras/text but above the flattened bar.
    plate.classFrame:SetFrameStrata("MEDIUM")
    plate.classFrame:SetFrameLevel(plate.health:GetFrameLevel() + 3)
    plate.classFrame:Hide()
    plate.class = plate.classFrame:CreateTexture(nil, "ARTWORK")
    plate.class:SetAllPoints()
    plate.cast = CreateFrame("StatusBar", nil, plate)
    -- Cast bar spans the health bar width; by default the icon hangs outside left, and with
    -- "Make Icon Part of the Bar" the bar shrinks to fit it. Must run after plate.health exists.
    ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), CAST_H)
    plate.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.cast:SetMinMaxValues(0, 1)
    plate.cast:Hide()
    plate.castBG = plate.cast:CreateTexture(nil, "BACKGROUND")
    plate.castBG:SetAllPoints()
    local _cbg = (p and p.castBgColor) or defaults.castBgColor
    local _cba = (p and p.castBgAlpha) or defaults.castBgAlpha
    plate.castBG:SetColorTexture(_cbg.r, _cbg.g, _cbg.b, _cba)
    -- Cast bar border: pixel-perfect PP.CreateBorder, lazy-created (size 0 default, costs
    -- nothing unless enabled). Mirrors the health border; a child of plate.cast.
    function plate:ApplyCastBorder()
        if not PP or not PP.CreateBorder then return end
        local sz = (p and p.castBorderSize) or defaults.castBorderSize or 0
        if sz and sz > 0 then
            if PP.GetBorders(plate.cast) then
                PP.SetBorderSize(plate.cast, sz)
                PP.ShowBorder(plate.cast)
            else
                local cc = (p and p.castBorderColor) or defaults.castBorderColor
                PP.CreateBorder(plate.cast, cc.r, cc.g, cc.b, 1, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
            end
        elseif PP.GetBorders(plate.cast) then
            PP.HideBorder(plate.cast)
        end
    end
    function plate:ApplyCastBorderColor()
        if not PP or not PP.GetBorders or not PP.GetBorders(plate.cast) then return end
        local cc = (p and p.castBorderColor) or defaults.castBorderColor
        PP.SetBorderColor(plate.cast, cc.r, cc.g, cc.b, 1)
    end
    -- "Wrap Border Around Castbar" (opt-in). While cast bar shown + feature on, health + cast
    -- get ONE continuous border from two pieces: the REAL health border (top+sides, untouched
    -- colour) and a region frame for the lower half (sides+bottom, full footprint width, health
    -- bottom -> cast bottom). Touching edges hidden so they read as one outline; region copies
    -- the health border's colour. Each piece MUST live in its own bar's subtree: a PP border is
    -- an OVERLAY texture that reliably beats its OWN bar's ARTWORK fill in the flattened render
    -- layer -- one frame spanning BOTH bars does NOT work (health half would render over the
    -- cast fill, the unreliable cross-flatten case). The region rides "Casts In Front of
    -- Nameplates" natively and lets the lower half bridge a Cast Bar Y gap / enclose an
    -- in-width icon: PP snaps a border's edges to its own frame (SnapBorderTextures), so the
    -- cast bar's own border could only hug the narrower/gapped cast bar. Custom (textured)
    -- border = no-op (one piece, cannot merge). shouldWrap requires the simple PP border.
    function plate:UpdateBorderWrap()
        if not PP or not PP.GetBorders then return end
        local shouldWrap = ns.GetWrapBorderCastbar()
            and plate.cast and plate.cast:IsShown()
            and IsBorderEnabled() and not ns.IsCustomBorderEnabled()
        if shouldWrap then
            local hb = PP.GetBorders(plate.health)
            if hb then
                local sz = (p and p.borderSize) or defaults.borderSize
                local col = hb._bdColor
                local r, g, b, a = 0, 0, 0, 1
                if col then r, g, b, a = col[1], col[2], col[3], col[4] or 1 end
                -- Region frame (child of plate.cast) spans the FULL footprint width from the
                -- health bar's BOTTOM to the cast bar's BOTTOM, bridging any Cast Bar Y-offset
                -- gap and enclosing an in-width cast icon; health border keeps top+sides. The
                -- seam (health bottom + region top) is hidden to read as one outline, and the
                -- health border's live colour is copied onto the region (target highlight carries over).
                local region = plate.castWrapRegion
                if not region then
                    region = CreateFrame("Frame", nil, plate.cast)
                    plate.castWrapRegion = region
                end
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", 0, 0)
                region:SetPoint("TOPRIGHT", plate.health, "BOTTOMRIGHT", 0, 0)
                region:SetPoint("BOTTOM", plate.cast, "BOTTOM", 0, 0)
                region:Show()
                -- Lift the region above the cast spell icon (raised to health-level+1 so a
                -- full-size icon clears the health bar), else an in-width icon draws ON TOP of
                -- the wrap border. Re-set every pass -- a strata propagation from the cast-lift would collapse it.
                if plate.castIconFrame then
                    region:SetFrameLevel(plate.castIconFrame:GetFrameLevel() + 2)
                end
                if not PP.GetBorders(region) then
                    PP.CreateBorder(region, r, g, b, a, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
                end
                -- Seam flags go on the containers BEFORE (re)snapping so SnapBorderTextures
                -- hides the two touching edges AND runs the side strips to the seam (no edge
                -- line, no corner notch). Flags survive every later re-snap (create-border
                -- 2-tick OnUpdate, scale changes, RefreshBorder); a one-shot :Hide() would not.
                local rb = PP.GetBorders(region)
                if rb then rb._hideTop = true end
                hb._hideBottom = true
                PP.SetBorderSize(region, sz)
                PP.SetBorderColor(region, r, g, b, a)
                PP.ShowBorder(region)
                PP.SetBorderSize(plate.health, sz)
                -- Leave the cast bar's OWN border ACTIVE under the wrap (region border sits
                -- higher and draws over it); only the icon-separator line is hidden so an
                -- in-width icon stays seamless.
                if plate.castLeftBorder then plate.castLeftBorder:Hide() end
                -- Optional: tint the full-size icon's border with the live target border colour
                -- to match the wrapped bar; else-branch keeps it black so toggling off resets it.
                if plate.castIconFrame and PP.GetBorders(plate.castIconFrame) then
                    if p and p.castIconTargetBorder
                        and GetShowCastIcon() and ns.GetCastIconFullSize()
                        and plate.unit and UnitIsUnit(plate.unit, "target")
                        and ns.GetTargetGlowBorderColor()
                    then
                        PP.SetBorderColor(plate.castIconFrame, r, g, b, a)
                    else
                        PP.SetBorderColor(plate.castIconFrame, 0, 0, 0, 1)
                    end
                end
            end
            plate._wrapActive = true
        elseif plate._wrapActive then
            plate._wrapActive = false
            -- Clear the seam flag and re-snap the health border so its bottom edge/side insets
            -- come back (re-applies the live colour). Drop the region, hand the cast border back.
            local hb = PP.GetBorders(plate.health)
            if hb then
                hb._hideBottom = nil
                PP.SetBorderSize(plate.health, (p and p.borderSize) or defaults.borderSize)
            end
            if plate.castWrapRegion then
                local crb = PP.GetBorders(plate.castWrapRegion)
                if crb then crb._hideTop = nil end
                if crb then PP.HideBorder(plate.castWrapRegion) end
                plate.castWrapRegion:Hide()
            end
            if plate.castLeftBorder then plate.castLeftBorder:Show() end
            if plate.castIconFrame and PP.GetBorders(plate.castIconFrame) then
                PP.SetBorderColor(plate.castIconFrame, 0, 0, 0, 1)
            end
            plate:ApplyCastBorder()
            plate:ApplyCastBorderColor()
        end
        if plate.castIconFrame then
            ns.ApplyFrameIconBorder(plate.castIconFrame, ns.GetIconBorderEnabled("cast"))
        end
    end
    plate:ApplyCastBorder()
    plate.castLeftBorder = plate.cast:CreateTexture(nil, "OVERLAY", nil, 7)
    plate.castLeftBorder:SetColorTexture(0, 0, 0, 1)
    plate.castLeftBorder:SetWidth(1)
    plate.castLeftBorder:SetPoint("TOPLEFT", plate.cast, "TOPLEFT", 0, 0)
    plate.castLeftBorder:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMLEFT", 0, 0)
    -- Icon frame hangs outside the cast bar's left edge. Parented AND anchored to cast
    -- (auto-hides with it; same frame = single-pass resolve, no jitter).
    plate.castIconFrame = CreateFrame("Frame", nil, plate.cast)
    -- Lift above the health bar (level 10) once so a full-size icon is never occluded.
    plate.castIconFrame:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    ns.LayoutCastIcon(plate, CAST_H)
    AddBorder(plate.castIconFrame)
    ns.ApplyFrameIconBorder(plate.castIconFrame, ns.GetIconBorderEnabled("cast"))
    plate.castIcon = plate.castIconFrame:CreateTexture(nil, "ARTWORK")
    -- Fill the frame (inset 0) so the 1px OVERLAY border draws ON TOP of the icon's rim: the
    -- visible edge IS the border's inner edge, no bare frame gap. DisablePixelSnap matches the
    -- icon to the unsnapped border strips so they translate together under plate motion.
    plate.castIcon:SetPoint("TOPLEFT", plate.castIconFrame, "TOPLEFT", 0, 0)
    plate.castIcon:SetPoint("BOTTOMRIGHT", plate.castIconFrame, "BOTTOMRIGHT", 0, 0)
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(plate.castIcon) end
    plate.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    plate.castSpark = plate.cast:CreateTexture(nil, "OVERLAY", nil, 1)
    plate.castSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    plate.castSpark:SetSize(8, CAST_H)
    plate.castSpark:SetPoint("CENTER", plate.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    plate.castSpark:SetBlendMode("ADD")
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    plate.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    local shieldHeight = CAST_H * 0.75
    local shieldWidth = shieldHeight * (29 / 35)
    plate.castShieldFrame = CreateFrame("Frame", nil, plate.cast)
    plate.castShieldFrame:SetSize(shieldWidth, shieldHeight)
    plate.castShieldFrame:SetPoint("CENTER", plate.cast, "LEFT", 0, 0)
    plate.castShieldFrame:SetFrameLevel(plate.castIconFrame:GetFrameLevel() + 5)
    plate.castShieldFrame:Hide()
    plate.castShield = plate.castShieldFrame:CreateTexture(nil, "OVERLAY")
    plate.castShield:SetAllPoints()
    plate.castShield:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\shield.png")
    plate.castBarOverlay = plate.cast:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.castBarOverlay:SetAllPoints(plate.cast:GetStatusBarTexture())
    plate.castBarOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    plate.castBarOverlay:SetAlpha(0)
    -- Kick tick: clip frame so the tick never renders outside the cast bar when kick CD exceeds
    -- remaining cast time. ONLY kick elements go here; icon/text/shield/spark stay unclipped.
    plate.kickClip = CreateFrame("Frame", nil, plate.cast)
    plate.kickClip:SetAllPoints(plate.cast)
    plate.kickClip:SetClipsChildren(true)
    plate.kickPositioner = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    -- Pixel-snap OFF on the fill texture. The tick sits at positioner_width + marker_width; if
    -- either fill snaps independently, round(a)+round(b) flips by 1px when one width crosses a
    -- pixel boundary and the other does not, even though the ratio is invariant -- that's the
    -- jitter. Belt-and-suspenders: the load-bearing unsnap is after each SetFillStyle in
    -- UpdateKickTick (SetFillStyle re-mints the fill to snap-ON; the global SetStatusBarTexture
    -- hook won't re-fire on an already-cached bar).
    if plate.kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
        plate.kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
        plate.kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    plate.kickPositioner:SetPoint("CENTER", plate.cast)
    plate.kickPositioner:SetFrameLevel(plate.cast:GetFrameLevel() + 1)
    plate.kickPositioner:Hide()
    plate.kickMarker = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickMarker:GetStatusBarTexture():SetAlpha(0)
    if plate.kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
        plate.kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
        plate.kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
    end
    plate.kickMarker:SetPoint("LEFT", plate.kickPositioner:GetStatusBarTexture(), "RIGHT")
    plate.kickMarker:SetSize(1, 1) -- sized later in UpdateKickTick
    plate.kickMarker:SetFrameLevel(plate.cast:GetFrameLevel() + 2)
    plate.kickMarker:Hide()
    plate.kickTick = plate.kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
    plate.kickTick:SetColorTexture(1, 1, 1, 1)
    plate.kickTick:SetWidth(2)
    plate.kickTick:SetPoint("TOP", plate.kickMarker, "TOP", 0, 0)
    plate.kickTick:SetPoint("BOTTOM", plate.kickMarker, "BOTTOM", 0, 0)
    plate.kickTick:SetPoint("LEFT", plate.kickMarker:GetStatusBarTexture(), "RIGHT")
    -- Interrupt-ready mid-cast fill: colors the cast-bar segment from "kick ready here" to cast
    -- end (window where the interrupt is available) when kick is on CD now but comes off before
    -- the cast finishes. Rides the SAME kickMarker geometry as the tick, so the "ready in time"
    -- two-secret-duration test resolves purely by where the marker texture edge lands: if the
    -- kick will NOT be ready the left/right anchors cross, the fill collapses to zero width and
    -- self-hides with no Lua branch on a secret. On plate.cast at ARTWORK sublevel 1: above the
    -- bar fill, below the OVERLAY cast text and uninterruptible grey overlay (sublevel 2).
    -- Anchors (re)applied per cast in UpdateKickTick.
    plate.kickReadyFill = plate.cast:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    plate.kickReadyFill:SetAlpha(0)
    plate.kickReadyFill:Hide()
    -- Cast bar text: three independent fixed zones [castName LEFT 50%] [castTarget
    -- CENTER-RIGHT 25%] [castTimer RIGHT 15%]. Explicit MEDIUM frame so text leaves the
    -- plate's flattened render layer and draws ABOVE the cast bar border.
    plate.castTextFrame = CreateFrame("Frame", nil, plate.cast)
    plate.castTextFrame:SetAllPoints(plate.cast)
    plate.castTextFrame:SetFrameStrata("MEDIUM")
    plate.castTextFrame:SetFrameLevel(900)
    plate.castName = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castName, 10, GetNPOutline())
    plate.castName:SetPoint("LEFT", plate.cast, "LEFT", 5, 0)
    plate.castName:SetJustifyH("LEFT")
    plate.castName:SetWordWrap(false)
    plate.castName:SetMaxLines(1)
    plate.castTarget = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castTarget, 10, GetNPOutline())
    plate.castTarget:SetJustifyH("RIGHT")
    plate.castTarget:SetWordWrap(false)
    plate.castTarget:SetNonSpaceWrap(false)
    plate.castTarget:SetMaxLines(1)
    plate.castTimer = plate.castTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castTimer, 10, GetNPOutline())
    plate.castTimer:SetPoint("RIGHT", plate.cast, "RIGHT", -3, 0)
    plate.castTimer:SetJustifyH("RIGHT")
    plate.castTimer:SetWordWrap(false)
    plate.castTimer:SetMaxLines(1)
    plate.castTimer:SetTextColor(1, 1, 1, 1)
    -- Cast timer on a 10Hz ANIM TICKER (engine sleeps between fires), never a per-frame
    -- OnUpdate: text is %.1f, so the displayed tenth cannot change faster than 0.1s, and a
    -- per-render-frame entry per casting plate at uncapped FPS is pure dispatch-floor cost for
    -- a 10Hz job (old accumulator measured 60.8ms/min in a caster-heavy pull). Armed by
    -- NotifyCastStarted; body self-stops at cast end. Uses
    -- UnitCastingDuration/UnitChannelDuration objects + :GetRemainingDuration(), since
    -- UnitCastingInfo's endTime/startTime are secret and unusable in arithmetic.
    plate.cast._timerTick = function(force)
        local self = plate.cast
        local owner = self._timerPlate
        -- force = the synchronous arm-time paint from NotifyCastStarted, which fires BEFORE
        -- the caller sets isCasting (Notify IS the rising-edge detector).
        if not owner or not owner.unit or (not owner.isCasting and not force) then return end
        if not owner._showCastTimer then return true end
        if UnitCastingDuration then
            local durObj = UnitCastingDuration(owner.unit)
                or (UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration(owner.unit, true))
                or (UnitChannelDuration and UnitChannelDuration(owner.unit))
            if durObj then
                local remaining = durObj:GetRemainingDuration()
                owner.castTimer:SetFormattedText("%.1f", remaining)
            else
                owner.castTimer:SetText("")
            end
        else
            local min, max = owner.cast:GetMinMaxValues()
            local val = owner.cast:GetValue()
            if max and max > 0 then
                local remaining = max - val
                if remaining < 0 then remaining = 0 end
                owner.castTimer:SetFormattedText("%.1f", remaining)
            else
                owner.castTimer:SetText("")
            end
        end
        return true
    end
    plate.cast._timerTicker = EllesmereUI.Tick.NewAnimTicker(plate.cast, plate.cast._timerTick, 0.1)
    plate.cast._timerPlate = plate
    -- Full-size cast icon: side-slot reserve is valid only while the cast bar is shown, so
    -- re-anchor reserving side elements on every cast show/hide. One chokepoint catches every
    -- path (start/stop/channel stop/interrupt flash+timer); RefreshCastIconSideReserve
    -- early-outs unless full-size is on.
    local function OnCastVisibilityChanged(self)
        local owner = self._timerPlate
        if owner and owner.RefreshCastIconSideReserve then
            owner:RefreshCastIconSideReserve()
        end
        -- Wrap-border driver, gated so when the feature is off (plate not wrapped) nothing
        -- runs beyond a field read + setting lookup.
        if owner and owner.UpdateBorderWrap and (owner._wrapActive or ns.GetWrapBorderCastbar()) then
            owner:UpdateBorderWrap()
        end
    end
    plate.cast:HookScript("OnShow", OnCastVisibilityChanged)
    plate.cast:HookScript("OnHide", OnCastVisibilityChanged)
    plate.debuffs = {}
    local maxDbf = (p and p.maxDebuffs) or defaults.maxDebuffs
    for i = 1, maxDbf do
        local d = CreateFrame("Frame", nil, plate)
        d:SetFrameStrata("MEDIUM")
        d:SetFrameLevel(800)
        PP.Size(d, 26, 26)
        PP.Point(d, "BOTTOM", plate.name, "TOP", (i - (maxDbf + 1) / 2) * 30, 2)
        AddBorder(d)
        ns.ApplyFrameIconBorder(d, ns.GetIconBorderEnabled("debuffs"), true)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        PP.Point(d.icon, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.icon, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Snap-disable ONCE at creation: aura arm/clear hot paths use PP.RawSetTexture (pre-hook original), which never re-triggers the pixel-snap hook.
        PP.DisablePixelSnap(d.icon)
        d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
        PP.Point(d.cd, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.cd, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.cd:SetFrameLevel(d:GetFrameLevel() + 2)
        if d.cd.SetDrawSwipe then d.cd:SetDrawSwipe(true) end
        if d.cd.SetDrawEdge then d.cd:SetDrawEdge(false) end
        if d.cd.SetDrawBling then d.cd:SetDrawBling(false) end
        if d.cd.SetReverse then d.cd:SetReverse(true) end
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(false) end
        -- Stack count + countdown text on a carrier ABOVE the cooldown so the zero-duration
        -- alpha mask on d.cd (kills the permanent-aura swipe strobe) never hides them. Carrier
        -- at slot+6, above the pandemic/dispel glow wrappers (slot+5).
        d.countCarrier = CreateFrame("Frame", nil, d)
        d.countCarrier:SetAllPoints(d)
        d.countCarrier:SetFrameLevel(d:GetFrameLevel() + 6)
        d.count = d.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(d.count, 11, "OUTLINE, SLUG")
        PP.Point(d.count, "BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.count:SetJustifyH("RIGHT")
        local cdRegions = { d.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                d.cd.text = region
                region:SetParent(d.countCarrier)
                SetFSFont(region, 11, "OUTLINE, SLUG")
                region:ClearAllPoints()
                PP.Point(region, "TOPLEFT", d, "TOPLEFT", -3, 4)
                region:SetJustifyH("LEFT")
                region:SetTextColor(GetDebuffTextColor())
                break
            end
        end
        d:Hide()
        plate.debuffs[i] = d
    end
    plate.buffs = {}
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, plate)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(800)
        PP.Size(b, 24, 24)
        PP.Point(b, "RIGHT", plate.health, "LEFT", -2 - (i - 1) * 26, 0)
        AddBorder(b)
        ns.ApplyFrameIconBorder(b, ns.GetIconBorderEnabled("buffs"), true)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        PP.Point(b.icon, "TOPLEFT", b, "TOPLEFT", 1, -1)
        PP.Point(b.icon, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        PP.DisablePixelSnap(b.icon)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        PP.Point(b.cd, "TOPLEFT", b, "TOPLEFT", 1, -1)
        PP.Point(b.cd, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.cd:SetFrameLevel(b:GetFrameLevel() + 2)
        if b.cd.SetDrawSwipe then b.cd:SetDrawSwipe(true) end
        if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
        if b.cd.SetDrawBling then b.cd:SetDrawBling(false) end
        if b.cd.SetReverse then b.cd:SetReverse(true) end
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
        -- Stack count + countdown text on a carrier ABOVE the cooldown (see debuff slot) so
        -- b.cd's zero-duration alpha mask never hides them. Carrier at slot+6, above dispel glow.
        b.countCarrier = CreateFrame("Frame", nil, b)
        b.countCarrier:SetAllPoints(b)
        b.countCarrier:SetFrameLevel(b:GetFrameLevel() + 6)
        b.count = b.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(b.count, 9, "OUTLINE, SLUG")
        PP.Point(b.count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        local bCdRegions = { b.cd:GetRegions() }
        for _, region in ipairs(bCdRegions) do
            if region:GetObjectType() == "FontString" then
                b.cd.text = region
                region:SetParent(b.countCarrier)
                SetFSFont(region, 12, "OUTLINE, SLUG")
                region:ClearAllPoints()
                region:SetPoint("CENTER", b, "CENTER", 0, 0)
                break
            end
        end
        b:Hide()
        plate.buffs[i] = b
    end
    plate.cc = {}
    for i = 1, 2 do
        local c = CreateFrame("Frame", nil, plate)
        c:SetFrameStrata("MEDIUM")
        c:SetFrameLevel(800)
        PP.Size(c, 24, 24)
        PP.Point(c, "LEFT", plate.health, "RIGHT", 2 + (i - 1) * 26, 0)
        AddBorder(c)
        ns.ApplyFrameIconBorder(c, ns.GetIconBorderEnabled("ccs"), true)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        PP.Point(c.icon, "TOPLEFT", c, "TOPLEFT", 1, -1)
        PP.Point(c.icon, "BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        PP.DisablePixelSnap(c.icon)
        c.cd = CreateFrame("Cooldown", nil, c, "CooldownFrameTemplate")
        PP.Point(c.cd, "TOPLEFT", c, "TOPLEFT", 1, -1)
        PP.Point(c.cd, "BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
        c.cd:SetFrameLevel(c:GetFrameLevel() + 2)
        if c.cd.SetDrawSwipe then c.cd:SetDrawSwipe(true) end
        if c.cd.SetDrawEdge then c.cd:SetDrawEdge(false) end
        if c.cd.SetDrawBling then c.cd:SetDrawBling(false) end
        if c.cd.SetReverse then c.cd:SetReverse(true) end
        if c.cd.SetHideCountdownNumbers then c.cd:SetHideCountdownNumbers(false) end
        local cdRegions = { c.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                c.cd.text = region
                SetFSFont(region, 12, "OUTLINE, SLUG")
                region:ClearAllPoints()
                region:SetPoint("CENTER", c, "CENTER", 0, 0)
                break
            end
        end
        c:Hide()
        plate.cc[i] = c
    end
    plate:SetScript("OnEvent", function(self, event, ...)
        local handler = self[event]
        if handler then handler(self, ...) end
    end)
end)

-- Pre-warm the plate frame pool so AoE pulls don't pay the 2ms+ per-plate creation cost
-- (CreateFrame + child textures + cooldowns) on every Acquire when many plates appear in one
-- engine frame; a 5-mob pack can otherwise stack 10+ms of synchronous setup -> visible stutter.
-- Spread over 2 seconds (1 plate/100ms) after PLAYER_LOGIN so login stays smooth. Each Acquire
-- runs the pool's creation function; Release returns the frame for instant reuse.
do
    local prewarmFrame = CreateFrame("Frame")
    prewarmFrame:RegisterEvent("PLAYER_LOGIN")
    prewarmFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            -- Hold acquires until end so each one actually creates a new pool frame.
            local held = {}
            local made = 0
            local target = 20
            local ticker
            ticker = C_Timer.NewTicker(0.1, function()
                made = made + 1
                if made > target then
                    for i = 1, #held do frameCache:Release(held[i]) end
                    ticker:Cancel()
                    return
                end
                held[made] = frameCache:Acquire()
            end)
        end)
    end)
end

local function InitDB()
    -- No-op stub (NewDB + DeepMergeDefaults handles defaults); kept so stray call sites don't error.
end
function ns.GetActiveKickSpell()
    return EllesmereUI and EllesmereUI.GetActiveKickSpell and EllesmereUI.GetActiveKickSpell()
end
-- Cast overlay uses the same tint as the on-plate cast bar.
ns.ComputeCastBarTint = function(readyTint, baseTint)
    if EllesmereUI and EllesmereUI.ComputeCastBarTint then
        return EllesmereUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function GetActiveKickSpell()
    return ns.GetActiveKickSpell()
end
local ComputeCastBarTint = ns.ComputeCastBarTint
-- Re-evaluate the cast-bar wrap on every enemy plate; each plate self-decides to wrap or
-- unwrap, so this both applies and tears down. Called unconditionally from the option toggle
-- (catches toggle-off) and, gated on the setting, from the border refreshers, so size/colour
-- edits during a wrapped mid-cast plate keep the unified border in sync.
function ns.ApplyBorderWrapToAll()
    for _, plate in pairs(ns.plates) do
        if plate.UpdateBorderWrap then plate:UpdateBorderWrap() end
    end
end
function ns.RefreshBorder()
    -- Bump appearance gen so pooled/off-screen plates pick up the change on their next SetUnit.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorder then plate:ApplyBorder() end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if ns.friendlyPlates then
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.ApplyBorder then plate:ApplyBorder() end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end
ns.RefreshBorderStyle = ns.RefreshBorder
ns.RefreshSimpleBorderSize = ns.RefreshBorder
function ns.RefreshBorderColor()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorderColor then plate:ApplyBorderColor() end
    end
    -- Friendly plates mirror the enemy border settings 1:1.
    if ns.friendlyPlates then
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.ApplyBorderColor then plate:ApplyBorderColor() end
        end
    end
    -- Additive: no-op unless the wrap feature is enabled.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end
function ns.RefreshCastBorder()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyCastBorder then plate:ApplyCastBorder() end
    end
    -- ApplyCastBorder re-shows/re-sizes the cast border, so a wrapped mid-cast plate must re-merge.
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end
function ns.RefreshCastBorderColor()
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.ApplyCastBorderColor then plate:ApplyCastBorderColor() end
    end
    if ns.GetWrapBorderCastbar() then ns.ApplyBorderWrapToAll() end
end
function ns.RefreshNameplateYOffset()
    local yOff = GetNameplateYOffset()
    for _, plate in pairs(ns.plates) do
        plate.health:ClearAllPoints()
        plate.health:SetPoint("CENTER", plate, "CENTER", 0, yOff)
    end
end

function ns.RefreshStackingBounds()
    local scale = GetStackSpacingScale() / 100
    local barH = GetHealthBarHeight()
    local castH2 = GetCastBarHeight()
    local nameGap = 4 + GetEnemyNameTextSize()
    local totalH = nameGap + barH + castH2
    local w = GetHealthBarWidth()
    for _, plate in pairs(ns.plates) do
        if plate._stackBounds then
            plate._stackBounds:SetSize(w, totalH * scale)
        end
    end
end

function ns.RefreshStackingMotion()
    if not C_CVar or not C_CVar.SetCVarBitfield then return end
    if not (Enum and Enum.NamePlateStackType) then return end
    local db = p or defaults
    -- Enemy stacking is always EUI-owned; apply every time. Must NOT be gated on friendly
    -- players, or enemy plates stop stacking for anyone who hands friendly plates to Blizzard.
    C_CVar.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Enemy, db.stackingEnabled ~= false)
    -- Friendly stacking is only ours to write while we manage friendly players; when
    -- Blizzard-managed, leave the friendly bit untouched so the user's setting survives.
    if (db.showFriendlyPlayers ~= false) then
        C_CVar.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Friendly, db.stackingFriendly == true)
    end
end

function ns.RefreshHitboxSize()
    if InCombatLockdown() then return end
    if not C_NamePlate or not C_NamePlate.SetNamePlateSize then return end
    local db = p or defaults
    local sx = (db.hitboxScaleX or 100) / 100
    local sy = (db.hitboxScaleY or 100) / 100
    local baseW = GetHealthBarWidth()
    local baseH = GetHealthBarHeight()
    local newH  = baseH * sy
    C_NamePlate.SetNamePlateSize(baseW * sx, newH)
    -- The frame grows from its CENTER, so a taller size enlarges the hitbox evenly above and
    -- below the unit. -10000 insets let the hit rect fill the full (centered) frame.
    if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets
       and Enum and Enum.NamePlateType then
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)
        C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, -10000, -10000, -10000, -10000)
    end
    -- Anchor content at the frame center (GetHitboxYShift is 0): the frame grows
    -- centered, so the bar stays put and the hitbox stays centered on it.
    local yShift = GetHitboxYShift()
    for _, plate in pairs(ns.plates) do
        plate:ClearAllPoints()
        plate:SetPoint("CENTER", plate.nameplate, "CENTER", 0, yShift)
    end
end

-- Hitbox visualizer: translucent overlay matching each enemy nameplate's clickable bounds (the
-- frame sized by SetNamePlateSize), so the Hitbox Size sliders can be dialled in visually.
-- Runtime-only (resets on reload), created lazily so it costs nothing when off. On ns (cap).
function ns._ApplyHitboxOverlay(plate)
    local np = plate and plate.nameplate
    if not np then return end
    if ns._hitboxOverlayShown then
        local ov = plate.hitboxOverlay
        if not ov then
            ov = CreateFrame("Frame", nil, np)
            local fill = ov:CreateTexture(nil, "BACKGROUND")
            fill:SetAllPoints()
            fill:SetColorTexture(0.047, 0.824, 0.624, 0.18)
            local function Edge()
                local t = ov:CreateTexture(nil, "BORDER")
                t:SetColorTexture(0.047, 0.824, 0.624, 0.85)
                return t
            end
            local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
            top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
            bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
            left:SetPoint("TOPLEFT");   left:SetPoint("BOTTOMLEFT");  left:SetWidth(1)
            right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
            plate.hitboxOverlay = ov
        end
        -- Re-parent + re-anchor each apply: pooled plates get reused on a fresh nameplate.
        ov:SetParent(np)
        ov:SetFrameLevel(np:GetFrameLevel() + 10)
        ov:ClearAllPoints()
        ov:SetAllPoints(np)
        ov:Show()
    elseif plate.hitboxOverlay then
        plate.hitboxOverlay:Hide()
    end
end

-- Toggle the hitbox visualizer across every active enemy plate; driven by the eyeball button
-- beside the Hitbox Size sliders in options.
function ns.SetHitboxOverlayShown(show)
    ns._hitboxOverlayShown = show and true or false
    for _, plate in pairs(ns.plates) do
        ns._ApplyHitboxOverlay(plate)
    end
end

--- Full visual refresh for all plates when an entire preset is applied: re-runs SetUnit on each
--- active plate (re-reads all DB values). Deliberate switch only, never per-frame or per-event.
function ns.RefreshAllSettings()
    -- Re-read the profile reference: RepointAllDBs may have swapped the profile table
    -- (spec-linked profiles). All color lookups via _C() read this local.
    p = ENP.db.profile
    -- Bump the appearance generation so SetUnit re-runs ApplyAppearance per plate; without it,
    -- cache-hit re-spawns skip the static appearance work and new settings never apply.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate.nameplate then
            plate:SetUnit(plate.unit, plate.nameplate)
        end
    end
    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
    if ns.RangeText_Apply then ns.RangeText_Apply() end
    if ns.ApplyClassPowerSetting then ns.ApplyClassPowerSetting() end
    -- Aura containers: fingerprint-guarded, near-free when no aura setting changed.
    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
    -- Hide Enemy Nameplates OOC is CVar + event driven, and its options setter plus
    -- PLAYER_LOGIN were its only callers: a value written straight into the profile
    -- (override group, profile switch, import) flipped the checkbox while plates kept
    -- the old behaviour. Self-guarded, so an unchanged key costs nothing.
    if ns.ApplyOOCPlates then ns.ApplyOOCPlates() end
end

-------------------------------------------------------------------------------
--  Non-Target Opacity: while the player has a target, every skinned plate that is not the
--  target, focus or player fades to nonTargetAlpha (0-100). 100 = OFF: every hook below
--  reduces to one numeric compare. Out-of-range alpha composes into the same root multiplier.
--  Alpha rides the plate ROOT (our own frame, parented to the Blizzard nameplate), so
--  Blizzard's own occlusion fade still multiplies in.
-------------------------------------------------------------------------------
ns._ntAlpha = 1   -- cached 0..1 from the profile; 1 = inert
ns._ntKeepFocus = true   -- cached "Keep Focus Full Opacity" (default on)
ns._oorAlpha = 1  -- cached out-of-range alpha; 1 = inert

-- Applies the correct root alpha to ONE plate. Value-guarded via _ntCurAlpha so redundant
-- SetAlpha calls are skipped and pooled frames reset cheaply (nil = never faded).
function ns.NT_Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local a = 1
    local nt = ns._ntAlpha
    if nt < 1 and UnitExists("target")
       and not UnitIsUnit(unit, "target")
       and not (ns._ntKeepFocus and UnitIsUnit(unit, "focus"))
       and not UnitIsUnit(unit, "player") then
        a = nt
    end
    a = a * (plate._oorCurAlpha or 1)
    if (plate._ntCurAlpha or 1) ~= a then
        plate._ntCurAlpha = a
        plate:SetAlpha(a)
    end
end

function ns.NT_ApplyAll()
    for _, plate in pairs(ns.plates) do
        ns.NT_Apply(plate)
    end
end

-- Re-derives the cached opacity from the profile and reapplies every plate (un-fades at
-- slider=100). Called from the options slider, OnInitialize, and RefreshAllSettings.
function ns.NT_RefreshSetting()
    local v = tonumber(p and p.nonTargetAlpha) or 100
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    ns._ntAlpha = v / 100
    ns._ntKeepFocus = not (p and p.nonTargetKeepFocus == false)
    ns.NT_ApplyAll()
end

function ns.HideHoverEffect(plate)
    if not plate then return end
    if plate.highlight then plate.highlight:Hide() end
    if plate.hoverClipFill then plate.hoverClipFill:Hide() end
    if plate.hoverClipBg then plate.hoverClipBg:Hide() end
    plate._ovHoverShown = nil
end

function ns.ShowHoverEffect(plate)
    if not plate or not plate.health then return end
    -- Highlight channel gate (the Hover Effect dropdown's Highlight box): off
    -- = both the flat wash and the Hover Texture overlay stay hidden; the
    -- extra channels render independently via ns.ApplyHoverExtras.
    if not ns.GetHoverGlowHighlight() then
        ns.HideHoverEffect(plate)
        return
    end
    local db2 = p or defaults
    local hoverTex = db2.hoverOverlayTexture or defaults.hoverOverlayTexture
    local hc = db2.hoverColor or defaults.hoverColor
    local ha = db2.hoverAlpha or defaults.hoverAlpha
    if hoverTex ~= "none" then
        if ns._hoverOverlayTexName ~= hoverTex then
            ns._hoverOverlayTexName = hoverTex
            ns._hoverOverlayTexPath = ns.ResolveOverlayTexPath(hoverTex)
        end
        local texPath = ns._hoverOverlayTexPath
        local bgAlpha = OverlayBgAlpha(db2.hoverOverlayFullBgAlpha, ha)
        ns.EnsureHoverOverlay(plate)
        if not plate._ovHoverShown or plate._ovHoverTex ~= texPath
            or plate._ovHoverAlpha ~= ha or plate._ovHoverBgAlpha ~= bgAlpha
            or plate._ovHoverR ~= hc.r or plate._ovHoverG ~= hc.g or plate._ovHoverB ~= hc.b then
            plate._ovHoverShown = true
            plate._ovHoverTex, plate._ovHoverAlpha = texPath, ha
            plate._ovHoverBgAlpha = bgAlpha
            plate._ovHoverR, plate._ovHoverG, plate._ovHoverB = hc.r, hc.g, hc.b
            ApplyOverlayGeometry(plate.hoverOverlayFill, plate.hoverOverlayBg, plate.health, ns.OVERLAY_STRIPE_KEYS[hoverTex] == true)
            plate.hoverOverlayFill:SetTexture(texPath)
            plate.hoverOverlayFill:SetAlpha(ha)
            plate.hoverOverlayFill:SetVertexColor(hc.r, hc.g, hc.b)
            plate.hoverOverlayBg:SetTexture(texPath)
            plate.hoverOverlayBg:SetAlpha(bgAlpha)
            plate.hoverOverlayBg:SetVertexColor(hc.r, hc.g, hc.b)
        end
        if plate.highlight then plate.highlight:Hide() end
        plate.hoverClipFill:Show()
        plate.hoverClipBg:Show()
        return
    end
    if plate.hoverClipFill then plate.hoverClipFill:Hide() end
    if plate.hoverClipBg then plate.hoverClipBg:Hide() end
    plate._ovHoverShown = nil
    if plate.highlight then
        plate.highlight:SetColorTexture(hc.r, hc.g, hc.b, ha)
        plate.highlight:Show()
    end
end

-- Recolor the mouseover highlight on every live plate (enemy + friendly).
function ns.RefreshHoverEffect()
    local c = (p and p.hoverColor) or defaults.hoverColor
    local a = (p and p.hoverAlpha) or defaults.hoverAlpha
    for _, plate in pairs(ns.plates) do
        if plate.highlight then
            plate.highlight:SetColorTexture(c.r, c.g, c.b, a)
        end
        if plate == ns._currentMouseoverPlate then
            ns.ShowHoverEffect(plate)
            ns.ApplyHoverExtras(plate)
        else
            ns.HideHoverEffect(plate)
            ns.ClearHoverExtras(plate)
        end
    end
    for _, plate in pairs(ns.friendlyPlates or {}) do
        if plate.highlight then
            plate.highlight:SetColorTexture(c.r, c.g, c.b, a)
        end
        if plate == ns._currentMouseoverPlate then
            ns.ShowHoverEffect(plate)
            ns.ApplyHoverExtras(plate)
        else
            ns.HideHoverEffect(plate)
            ns.ClearHoverExtras(plate)
        end
    end
end

local kickWatcher = CreateFrame("Frame")
local activeCastCount = 0
-- PERF: set of plates currently casting, so kick/color updates iterate only the
-- 1-3 casting plates instead of all 20+ in the scene. On ns (200-local pressure).
ns._castingPlates = {}
kickWatcher:SetScript("OnEvent", function(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        -- No per-event cast-info re-reads or geometry: cast identity (protection/channel
        -- flags) is cached by UpdateKickTick at setup and by INTERRUPTIBLE handlers on
        -- mid-cast flips, so cooldown events only refresh marker value + alpha. A hidden tick
        -- means re-setup from cache (kick learned mid-cast, late CD info, toggle on).
        for plate in pairs(ns._castingPlates) do
            if plate.isCasting and plate.unit and type(plate._kickProtected) ~= "nil" then
                plate:ApplyCastColor(plate._kickProtected)
                if not plate.kickPositioner:IsShown() then
                    plate:UpdateKickTick(plate._kickProtected, plate._kickIsChannel, plate._kickIsEmpowered)
                else
                    plate:RefreshKickTick()
                end
            end
        end
    end
end)
local _castColorTicker
local function NotifyCastStarted(plate)
    if plate then
        ns._castingPlates[plate] = true
        -- Arm the 10Hz cast-timer ticker (engine-slept between fires; self-stops at cast end)
        -- and paint ONCE synchronously, or the ticker's first fire alone leaves text blank 0.1s.
        if plate.cast and plate.cast._timerTicker then
            if plate.cast._timerTick then plate.cast._timerTick(true) end
            plate.cast._timerTicker.Start()
        end
    end
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _castColorTicker then
            _castColorTicker = C_Timer.NewTicker(0.2, function()
                for pl in pairs(ns._castingPlates) do
                    -- type() is the safe existence check: _kickProtected holds a possibly-SECRET
                    -- boolean, and == nil would evaluate it
                    if pl.isCasting and pl.unit and type(pl._kickProtected) ~= "nil" then
                        pl:ApplyCastColor(pl._kickProtected)
                    end
                end
            end)
        end
    end
end
local function NotifyCastEnded(plate)
    if plate then ns._castingPlates[plate] = nil end
    activeCastCount = activeCastCount - 1
    if activeCastCount <= 0 then
        activeCastCount = 0
        wipe(ns._castingPlates)
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _castColorTicker then
            _castColorTicker:Cancel()
            _castColorTicker = nil
        end
    end
end

-- PERF: cached target/focus plate refs, so a target/focus change updates only
-- the old + new plate instead of iterating all. On ns (200-local pressure).
ns._cachedTargetPlate = nil
ns._cachedFocusPlate  = nil

local function SetupAuraCVars()
    if C_CVar and C_CVar.SetCVarBitfield and NamePlateConstants and Enum then
        local npcCVar = NamePlateConstants.ENEMY_NPC_AURA_DISPLAY_CVAR
        local npcEnum = Enum.NamePlateEnemyNpcAuraDisplay
        if npcCVar and npcEnum then
            if npcEnum.Debuffs then C_CVar.SetCVarBitfield(npcCVar, npcEnum.Debuffs, true) end
            if npcEnum.CrowdControl then C_CVar.SetCVarBitfield(npcCVar, npcEnum.CrowdControl, true) end
        end
        local plyCVar = NamePlateConstants.ENEMY_PLAYER_AURA_DISPLAY_CVAR
        local plyEnum = Enum.NamePlateEnemyPlayerAuraDisplay
        if plyCVar and plyEnum then
            if plyEnum.Debuffs then C_CVar.SetCVarBitfield(plyCVar, plyEnum.Debuffs, true) end
            if plyEnum.LossOfControl then C_CVar.SetCVarBitfield(plyCVar, plyEnum.LossOfControl, true) end
        end
    end
    if SetCVar then
        local db = p or defaults
        local nameOnly = (db.friendlyNameOnly ~= false)
        local showPlayers = (db.showFriendlyPlayers ~= false)
        local showNPCs = (db.showFriendlyNPCs == true)
        -- Friendly player CVars are written ONLY while EUI manages friendly player nameplates;
        -- with "Show EUI Friendly Player Nameplates" off we relinquish them entirely to
        -- Blizzard's own settings. Friendly NPC and enemy pet CVars are always managed.
        if showPlayers then
            SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0)
            SetCVar("UnitNameFriendlyPlayerName", 1)
            -- Visibility is NOT re-asserted: nameplateShowFriends/nameplateShowFriendlyPlayers
            -- persist across sessions, so forcing them each login would re-show plates the user
            -- deliberately hid. The one-time seed below covers a first install only.
            if EllesmereUIDB and not EllesmereUIDB.friendlyPlateVisSeeded then
                EllesmereUIDB.friendlyPlateVisSeeded = true
                -- Fresh install only: an existing install is stamped WITHOUT forcing, so a
                -- user who already hid friendly plates keeps that.
                if EllesmereUI._firstInstallPending and ns.ForceFriendlyPlayerCVarsOn then
                    ns.ForceFriendlyPlayerCVarsOn()
                end
            end
        end
        SetCVar("nameplateShowFriendlyNPCs", showNPCs and 1 or 0)
        SetCVar("nameplateShowFriendlyNpcs", showNPCs and 1 or 0)
        SetCVar("nameplateShowEnemyPets", (db.showEnemyPets == true) and 1 or 0)
        if showPlayers then
            SetCVar("ShowClassColorInFriendlyNameplate", (db.classColorFriendly ~= false) and 1 or 0)
        end
        SetCVar("ShowClassColorInNameplate", 1)
        SetCVar("nameplateSize", 3)
        SetCVar("nameplateShowAll", 1)
        SetCVar("nameplateMinScale", 1)
        SetCVar("nameplateOverlapH", 1)
        -- nameplateOverlapV is deliberately left alone: it's the user's own vertical-spacing
        -- cvar (Blizzard default 1.10). Our "Stacked Nameplate Spacing" slider layers extra
        -- spacing on top via the stacking-bounds frame.
        SetCVar("nameplateMaxAlpha", 1)
        SetCVar("nameplateMaxAlphaDistance", 40)
        SetCVar("nameplateMinAlpha", 0.6)
        SetCVar("nameplateMinAlphaDistance", -100000)
        SetCVar("nameplateMaxDistance", 60)
        SetCVar("nameplateMaxScale", 1)
        -- Neutralize Blizzard's selected-target scaling: the EUI plate is a child of the base
        -- nameplate, so Blizzard's scaling shows through our own SetScale (min/max pinned to 1
        -- for the same reason). Pinned to 1, "Scale Target Nameplate" is the sole authority.
        SetCVar("nameplateSelectedScale", 1)
        SetCVar("nameplateTargetBehindMaxDistance", 30)
        SetCVar("clampTargetNameplateToScreen", 1)
        if showPlayers then
            SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", (db.classColorFriendly ~= false) and 1 or 0)
        end
    end
    -- Hide realm names on friendly nameplates inside instances
    if NamePlateFriendlyFrameOptions and TextureLoadingGroupMixin then
        if NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName then
            local wrapper = { textures = NamePlateFriendlyFrameOptions }
            NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName = 0
            TextureLoadingGroupMixin.RemoveTexture(wrapper, "updateNameUsesGetUnitName")
        end
    end
    -- Apply stacking state via the Midnight bitfield CVar.
    ns.RefreshStackingMotion()
    local function ApplyNamePlateClickArea()
        if InCombatLockdown() then return end
        local db = p or defaults
        local sx = (db.hitboxScaleX or 100) / 100
        local sy = (db.hitboxScaleY or 100) / 100
        local baseH = GetHealthBarHeight()
        local newH  = baseH * sy
        if C_NamePlate and C_NamePlate.SetNamePlateSize then
            C_NamePlate.SetNamePlateSize(GetHealthBarWidth() * sx, newH)
        end
        if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets and Enum and Enum.NamePlateType then
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, -10000, -10000, -10000, -10000)
        end
    end
    ApplyNamePlateClickArea()
    -- Prevent Blizzard resetting nameplate sizes on display changes (jitter).
    if NamePlateDriverFrame then
        NamePlateDriverFrame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        NamePlateDriverFrame:UnregisterEvent("CVAR_UPDATE")
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", ApplyNamePlateClickArea)
        -- Suppress Blizzard class resource bar setup on our nameplates
        if NamePlateDriverFrame.SetupClassNameplateBars then
            hooksecurefunc(NamePlateDriverFrame, "SetupClassNameplateBars", function(self)
                if self.classNamePlatePowerBar then
                    self.classNamePlatePowerBar:Hide()
                    self.classNamePlatePowerBar:UnregisterAllEvents()
                end
                if self.classNamePlateMechanicFrame then
                    self.classNamePlateMechanicFrame:Hide()
                    self.classNamePlateMechanicFrame:UnregisterAllEvents()
                end
                if self.classNamePlateAlternatePowerBar then
                    self.classNamePlateAlternatePowerBar:Hide()
                    self.classNamePlateAlternatePowerBar:UnregisterAllEvents()
                end
            end)
        end
        -- Suppress the Blizzard UnitFrame before our NAME_PLATE_UNIT_ADDED fires
        -- so its initial layout pass never affects nameplate bounds.
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, addedUnit)
            if addedUnit == "preview" then return end
            local np = C_NamePlate.GetNamePlateForUnit(addedUnit)
            if np and addedUnit and UnitCanAttack("player", addedUnit) then
                ns.HideBlizzardFrame(np, addedUnit)
            end
        end)
    end
    ns.ApplyNamePlateClickArea = ApplyNamePlateClickArea
end
-------------------------------------------------------------------------------
--  Class Power Display (combo points, holy power, chi, etc.). Zero cost when disabled: no
--  events registered, no frames created. When on, a single watcher handles player
--  UNIT_POWER_UPDATE and shows pips only on the current target's nameplate.
-------------------------------------------------------------------------------
local classPowerWatcher
local classPowerType     -- Enum.PowerType value for the player's class resource, or nil
local classPowerMax = 0  -- max pips for the resource
local classPowerFormReq  -- required GetShapeshiftFormID() value, or nil if no form check needed
local CP_PIP_W, CP_PIP_H, CP_PIP_GAP = 8, 3, 2  -- pip geometry

-- Optional pip shapes. Rectangle (default) and square are plain boxes (no mask); the rest are
-- carved from a square fill by a portrait-set mask with a matching border texture (same shape
-- art as the Cooldown Manager). On ns (cap).
ns.CP_SHAPE = {
    WHITE = "Interface\\Buttons\\WHITE8X8",
    MASKS = {
        circle  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga",
        diamond = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\diamond_mask.tga",
        hexagon = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\hexagon_mask.tga",
        shield  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\shield_mask.tga",
    },
    BORDERS = {
        circle  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_border.tga",
        diamond = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\diamond_border.tga",
        hexagon = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\hexagon_border.tga",
        shield  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\shield_border.tga",
    },
    -- Shapes drawn on a 1:1 (square) footprint instead of the wide pip rectangle.
    SQUARE = { square = true, circle = true, diamond = true, hexagon = true, shield = true },
}

-- Resource-icon shapes: real Blizzard atlas art instead of a tinted shape. On ns.
ns.CP_ICON_SHAPE = { rune = true, holypower = true, shard = true,
                     combo = true, chi = true, arcane = true, essence = true }
-- Single-atlas resources have no distinct empty art, so dim their empty pips.
ns.CP_ICON_DIM_EMPTY = { arcane = true }
ns.CP_RUNE_SPEC = { [250] = "Blood", [251] = "Frost", [252] = "Unholy" }
-- Icon kind for a shape ("rune", "holypower", "essence", etc.), or nil if geometric.
function ns.GetPipIconKind(shape)
    return ns.CP_ICON_SHAPE[shape] and shape or nil
end
-- Atlas for a pip of the given icon kind, filled (active) or empty (background).
function ns.GetPipIconAtlas(kind, filled, index)
    if kind == "shard" then
        return filled and "Warlock-ReadyShard" or "Warlock-EmptyShard"
    elseif kind == "rune" then
        if not filled then return "DK-Rune-CD" end
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        return "DK-" .. (ns.CP_RUNE_SPEC[specID or 0] or "Blood") .. "-Rune-Ready"
    elseif kind == "combo" then
        return filled and "uf-roguecp-icon-red" or "uf-roguecp-bg"
    elseif kind == "chi" then
        return filled and "uf-chi-icon" or "uf-chi-bg"
    elseif kind == "arcane" then
        return "Mage-ArcaneCharge"  -- one atlas for both states; empty is dimmed by the caller
    elseif kind == "essence" then
        return filled and "UF-Essence-Icon-Active" or "UF-Essence-BG"
    end
    return nil
end

-- Class/power color from the EUI global system. Bar-type keys (_BAR suffix)
-- return the power color; class resources return resource color > class color.
local CP_DEFAULT_COLOR = { 1.00, 0.84, 0.30 }
local function GetClassPipColor(classFile, powerKey)
    if EllesmereUI then
        if powerKey then
            local alias = powerKey:match("^(.+)_BAR$")
            local key = alias or powerKey
            local c = EllesmereUI.GetPowerColor and EllesmereUI.GetPowerColor(key)
            if c then return { c.r, c.g, c.b } end
        end
        local rc = EllesmereUI.GetResourceColor and EllesmereUI.GetResourceColor(classFile)
        if rc then return { rc.r, rc.g, rc.b } end
        local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(classFile)
        if cc then return { cc.r, cc.g, cc.b } end
    end
    return CP_DEFAULT_COLOR
end

-- Map class { powerType, maxPips (fallback) }; entries can be simple { type, max } or spec-keyed { [specID] = { type, max } }.
local CLASS_POWER_MAP = {
    ROGUE       = { Enum.PowerType.ComboPoints, 5 },
    DRUID       = { [103] = { Enum.PowerType.ComboPoints, 5 },    -- Feral (always)
                    [105] = { Enum.PowerType.ComboPoints, 5 } }, -- Resto (cat form only)
    PALADIN     = { Enum.PowerType.HolyPower,   5 },
    MONK        = { [268] = { "BREWMASTER_STAGGER", 1 },
                    [269] = { Enum.PowerType.Chi, 5 } },
    WARLOCK     = { Enum.PowerType.SoulShards,   5 },
    MAGE        = { [62]  = { Enum.PowerType.ArcaneCharges, 4 },  -- Arcane
                    [64]  = { "ICICLES", 5 } },                 -- Frost
    EVOKER      = { Enum.PowerType.Essence,      5 },
    DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 },
                    [1480] = { "SOUL_FRAGMENTS_DEVOURER", 50 } },
    SHAMAN      = { [263] = { "MAELSTROM_WEAPON", 10 } },  -- Enhancement only
    PRIEST      = { [258] = { "INSANITY_BAR", 100 } },     -- Shadow only
    HUNTER      = { [255] = { "TIP_OF_THE_SPEAR", 3 } },   -- Survival only
    WARRIOR     = { [72]  = { "WHIRLWIND_STACKS", 4 },     -- Fury
                    [71]  = { "SWEEPING_STRIKES", 18 } },   -- Arms (12.1 cap: 12 + 6 Broad Strokes)
    DEATHKNIGHT = { [250] = { Enum.PowerType.Runes, 6 },
                    [251] = { Enum.PowerType.Runes, 6 },
                    [252] = { Enum.PowerType.Runes, 6 } },
}

-- Apply the configured shape + optional border to one pip (and its bg). rectangle/square: plain
-- box, no mask, border = one solid box behind the pip. Other shapes: carve fill+bg with a mask,
-- frame with the matching border texture. Idempotent. bSize is pip-local (pixel-snapped) units.
function ns.ApplyPipShape(plate, pip, shape, borderOn, bc, bSize)
    local bg = pip._bg
    -- Icon shapes draw real atlas art (set in the render): drop mask, borders, and the dark bg.
    if ns.CP_ICON_SHAPE[shape] then
        if pip._shapeMask then
            pcall(pip.RemoveMaskTexture, pip, pip._shapeMask)
            if bg then pcall(bg.RemoveMaskTexture, bg, pip._shapeMask) end
            pip._shapeMask:Hide()
        end
        if pip._border then pip._border:Hide() end
        if pip._borderBox then pip._borderBox:Hide() end
        if bg then bg:Hide() end
        return
    end
    local maskPath = ns.CP_SHAPE.MASKS[shape]
    if maskPath then
        if not pip._shapeMask then pip._shapeMask = plate:CreateMaskTexture() end
        local m = pip._shapeMask
        m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:ClearAllPoints()
        m:SetAllPoints(pip)
        m:Show()
        pcall(pip.RemoveMaskTexture, pip, m); pip:AddMaskTexture(m)
        if bg then pcall(bg.RemoveMaskTexture, bg, m); bg:AddMaskTexture(m) end
    elseif pip._shapeMask then
        pcall(pip.RemoveMaskTexture, pip, pip._shapeMask)
        if bg then pcall(bg.RemoveMaskTexture, bg, pip._shapeMask) end
        pip._shapeMask:Hide()
    end

    local borderPath = ns.CP_SHAPE.BORDERS[shape]
    if borderOn and borderPath then
        -- Masked shapes: matching outline texture, sized to the pip.
        if not pip._border then pip._border = plate:CreateTexture(nil, "OVERLAY", nil, 4) end
        local b = pip._border
        b:SetTexture(borderPath)
        b:SetVertexColor(bc.r, bc.g, bc.b, bc.a or 1)
        b:ClearAllPoints()
        b:SetAllPoints(pip)
        b:Show()
        if pip._borderBox then pip._borderBox:Hide() end
    elseif borderOn then
        -- Boxy shapes (rectangle/square): one solid box behind the pip, poking out bSize on
        -- every side as a uniform outline. A single texture rounds as one piece, staying crisp.
        if pip._border then pip._border:Hide() end
        if not pip._borderBox then
            pip._borderBox = plate:CreateTexture(nil, "OVERLAY", nil, 1)
            pip._borderBox:SetTexture(ns.CP_SHAPE.WHITE)
        end
        local box = pip._borderBox
        box:SetVertexColor(bc.r, bc.g, bc.b, bc.a or 1)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", pip, "TOPLEFT", -bSize, bSize)
        box:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", bSize, -bSize)
        box:Show()
    else
        if pip._border then pip._border:Hide() end
        if pip._borderBox then pip._borderBox:Hide() end
    end
end

-- Hide a pip's shape decorations (textured border + solid border box).
function ns.HidePipDecor(pip)
    if pip._border then pip._border:Hide() end
    if pip._borderBox then pip._borderBox:Hide() end
end

-- Lazy-create pip textures on a plate (done once, then reused via show/hide)
local function EnsureClassPowerPips(plate)
    if plate._cpPips then return end
    plate._cpPips = {}
    local maxPossible = 10  -- safe upper bound (Maelstrom Weapon = 10)
    for i = 1, maxPossible do
        local bg = plate:CreateTexture(nil, "OVERLAY", nil, 2)
        bg:SetTexture(ns.CP_SHAPE.WHITE)
        bg:SetVertexColor(0.082, 0.082, 0.082, 1)
        bg:Hide()
        local pip = plate:CreateTexture(nil, "OVERLAY", nil, 3)
        pip:SetTexture(ns.CP_SHAPE.WHITE)
        pip:SetVertexColor(1, 1, 1, 1)
        PP.Size(pip, CP_PIP_W, CP_PIP_H)
        pip:Hide()
        pip._bg = bg
        plate._cpPips[i] = pip
    end
end

-- Lazy-create a single StatusBar for bar-type class resources (e.g. stagger)
local function EnsureClassPowerBar(plate)
    if plate._cpBar then return end
    local bar = CreateFrame("StatusBar", nil, plate)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetFrameLevel(plate:GetFrameLevel() + 5)
    bar:Hide()
    -- Background texture behind the bar
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.082, 0.082, 0.082, 1)
    bar._bg = bg
    plate._cpBar = bar
end

-- Update pip display on a plate (or hide if plate is nil)
local function UpdateClassPowerOnPlate(plate)
    if not plate or not plate._cpPips then return end
    if not classPowerType
       or (classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq) then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
        end
        if plate._cpBar then plate._cpBar:Hide() end
        return
    end

    local cpScale = ns.GetClassPowerScale()
    local cpYOff = ns.GetClassPowerYOffset()
    local cpXOff = ns.GetClassPowerXOffset()
    local cpPos = ns.GetClassPowerPos()
    local bgCol = ns.GetClassPowerBgColor()

    -- Determine anchor: top or bottom of health bar, with cast bar avoidance
    local anchorPoint, anchorRelPoint, anchorFrame, yDir
    if cpPos == "top" then
        anchorPoint = "BOTTOM"
        anchorRelPoint = "TOP"
        anchorFrame = plate.health
        yDir = 1
    else
        if plate.isCasting and plate.cast:IsShown() then
            anchorPoint = "TOP"
            anchorRelPoint = "BOTTOM"
            anchorFrame = plate.cast
            yDir = -1
        else
            anchorPoint = "TOP"
            anchorRelPoint = "BOTTOM"
            anchorFrame = plate.health
            yDir = -1
        end
    end

    -- Bar-type resource (Brewmaster Stagger): single StatusBar instead of pips
    if classPowerType == "BREWMASTER_STAGGER" then
        -- Hide all pips
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            if plate._cpPips[i]._secretBar then plate._cpPips[i]._secretBar:Hide() end
        end
        EnsureClassPowerBar(plate)
        local bar = plate._cpBar
        local staggerCur = UnitStagger("player")
        local staggerMax = UnitHealthMax("player")
        local isSecretVal = issecretvalue and (issecretvalue(staggerCur) or issecretvalue(staggerMax))
        if not staggerCur then staggerCur = 0 end
        if not staggerMax or staggerMax <= 0 then staggerMax = 1 end

        local scaledW = CP_PIP_W * cpScale * 6  -- bar width: ~6 pips wide
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchorFrame, anchorRelPoint,
            cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, staggerMax)
        bar:SetValue(staggerCur)

        -- Stagger color thresholds: green < 30%, yellow 30-60%, red > 60%
        if isSecretVal then
            -- Secret value: can't compare, use class color
            local cpColor = GetClassPipColor(PLAYER_CLASS)
            if not GetClassPowerClassColors() then
                local cc = GetClassPowerCustomColor()
                cpColor = { cc.r, cc.g, cc.b }
            end
            bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)
        else
            local pct = staggerCur / staggerMax
            if pct >= 0.6 then
                bar:SetStatusBarColor(1.0, 0.2, 0.2, 1)   -- red (heavy)
            elseif pct >= 0.3 then
                bar:SetStatusBarColor(1.0, 0.85, 0.2, 1)  -- yellow (moderate)
            else
                bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)   -- green (light)
            end
        end

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Shadow Priest Insanity): single StatusBar
    if classPowerType == "INSANITY_BAR" then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            if plate._cpPips[i]._secretBar then plate._cpPips[i]._secretBar:Hide() end
        end
        EnsureClassPowerBar(plate)
        local bar = plate._cpBar
        local cur = UnitPower("player", 13) or 0  -- Enum.PowerType.Insanity = 13
        local maxI = UnitPowerMax("player", 13) or 100
        if issecretvalue and issecretvalue(maxI) then maxI = 100 end
        if not maxI or maxI <= 0 then maxI = 100 end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchorFrame, anchorRelPoint,
            cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxI)
        bar:SetValue(cur)

        local cpColor = GetClassPipColor(PLAYER_CLASS, "INSANITY_BAR")
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Hunter Focus for BM/MM): single StatusBar
    if classPowerType == "FOCUS_BAR" then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            if plate._cpPips[i]._secretBar then plate._cpPips[i]._secretBar:Hide() end
        end
        EnsureClassPowerBar(plate)
        local bar = plate._cpBar
        local cur = UnitPower("player", 2) or 0  -- Enum.PowerType.Focus = 2
        local maxF = UnitPowerMax("player", 2) or 100
        if issecretvalue and issecretvalue(maxF) then maxF = 100 end
        if not maxF or maxF <= 0 then maxF = 100 end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchorFrame, anchorRelPoint,
            cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxF)
        bar:SetValue(cur)

        local cpColor = GetClassPipColor(PLAYER_CLASS, "FOCUS_BAR")
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Devourer soul fragments): single StatusBar
    if classPowerType == "SOUL_FRAGMENTS_DEVOURER" then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            if plate._cpPips[i]._secretBar then plate._cpPips[i]._secretBar:Hide() end
        end
        EnsureClassPowerBar(plate)
        local bar = plate._cpBar
        local cur, maxC = 0, 50
        if EllesmereUI and EllesmereUI.GetSoulFragments then
            cur, maxC = EllesmereUI.GetSoulFragments()
            if not maxC or maxC <= 0 then maxC = 50 end
        end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchorFrame, anchorRelPoint,
            cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxC)
        bar:SetValue(cur or 0)

        local cpColor = GetClassPipColor(PLAYER_CLASS)
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Hide bar if switching from bar-type to pip-type
    if plate._cpBar then plate._cpBar:Hide() end

    local cur, maxP
    local isSecret = false
    if classPowerType == "SOUL_FRAGMENTS_VENGEANCE" then
        cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
        maxP = 6
        isSecret = true
    elseif classPowerType == "MAELSTROM_WEAPON" then
        cur, maxP = EllesmereUI.GetMaelstromWeapon()
    elseif classPowerType == "TIP_OF_THE_SPEAR" then
        cur, maxP = EllesmereUI.GetTipOfTheSpear()
    elseif classPowerType == "WHIRLWIND_STACKS" then
        cur, maxP = EllesmereUI.GetWhirlwindStacks()
        if not maxP or maxP <= 0 then
            for i = 1, #plate._cpPips do
                plate._cpPips[i]:Hide()
                if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            end
            return
        end
    elseif classPowerType == "SWEEPING_STRIKES" then
        cur, maxP = EllesmereUI.GetSweepingStrikes()
        if not maxP or maxP <= 0 then
            for i = 1, #plate._cpPips do
                plate._cpPips[i]:Hide()
                if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
            end
            return
        end
    elseif classPowerType == "ICICLES" then
        local count = 0
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(205473)
            if aura then
                count = aura.applications or aura.charges or 0
                if count > 5 then count = 5 end
            end
        end
        cur, maxP = count, 5
    else
        cur = UnitPower("player", classPowerType) or 0
        maxP = UnitPowerMax("player", classPowerType) or classPowerMax
        if maxP <= 0 then maxP = classPowerMax end
        -- Runes: UnitPower doesn't return ready-rune count; iterate cooldowns
        if classPowerType == Enum.PowerType.Runes then
            cur = 0
            for i = 1, maxP do
                local _, _, ready = GetRuneCooldown(i)
                if ready then cur = cur + 1 end
            end
        end
    end
    if maxP <= 0 then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
        end
        return
    end

    -- Lock pip width/height/gap to exact physical pixel multiples in the PLATE'S local coords
    -- (pips are parented to the plate, so its effective scale decides screen pixels). PP.Scale
    -- snaps to UIParent's grid, wrong here: nameplates have their own scale stack.
    local cpShape     = ns.GetClassPowerShape()
    local cpBorderOn  = ns.GetClassPowerBorder()
    local cpBorderCol = ns.GetClassPowerBorderColor()
    -- isSecret (DH Vengeance partial fill) keeps a plain rectangle: its StatusBar
    -- overlay can't follow a shape mask cleanly.
    if isSecret then cpShape = "rectangle" end
    -- Icon shapes (rune/holypower/shard) draw real Blizzard art.
    local iconKind = ns.GetPipIconKind(cpShape)
    local squareShape = ns.CP_SHAPE.SQUARE[cpShape] or (iconKind ~= nil)
    local plateES = plate:GetEffectiveScale()
    local onePx = (plateES and plateES > 0) and (PP.perfect / plateES) or PP.mult or 1
    local pipWPx   = math.floor((CP_PIP_W * cpScale) / onePx + 0.5)
    -- Non-rectangle shapes render on a square footprint (1:1).
    local pipHPx   = squareShape and pipWPx or math.floor((CP_PIP_H * cpScale) / onePx + 0.5)
    local pipGapPx = math.floor((ns.GetClassPowerGap() * cpScale) / onePx + 0.5)
    local borderPx = cpBorderOn and (ns.GetClassPowerBorderSize() * onePx) or 0
    local scaledW   = pipWPx   * onePx
    local scaledH   = pipHPx   * onePx
    local scaledGap = pipGapPx * onePx
    local stride = scaledW + scaledGap
    local groupW = maxP * scaledW + (maxP - 1) * scaledGap
    local halfGroup = math.floor((groupW / 2) / onePx + 0.5) * onePx

    local cpColor = CP_DEFAULT_COLOR
    if GetClassPowerClassColors() then
        cpColor = GetClassPipColor(PLAYER_CLASS)
    else
        local cc = GetClassPowerCustomColor()
        cpColor = { cc.r, cc.g, cc.b }
    end

    local emptyCol = ns.GetClassPowerEmptyColor()

    local leftAnchor = (anchorPoint == "BOTTOM") and "BOTTOMLEFT" or "TOPLEFT"

    for i = 1, #plate._cpPips do
        local pip = plate._cpPips[i]
        if i <= maxP then
            pip:ClearAllPoints()
            pip:SetSize(scaledW, scaledH)
            -- (i-1)*stride is an exact integer multiple of physical pixels, so every pip lands on the same grid.
            local pipLeftX = (i - 1) * stride - halfGroup + cpXOff
            pip:SetPoint(leftAnchor, anchorFrame, anchorRelPoint,
                pipLeftX, yDir * cpYOff)

            -- Background texture behind each pip
            local bg = pip._bg
            if bg then
                bg:ClearAllPoints()
                bg:SetAllPoints(pip)
                -- Reset from any prior icon socket; holy power re-sets these below.
                bg:SetTexture(ns.CP_SHAPE.WHITE)
                bg:SetTexCoord(0, 1, 0, 1)
                bg:SetDesaturated(false)
                bg:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                bg:Show()
            end

            -- Shape mask + optional border (size/anchor final by now). Skipped entirely on the
            -- untouched default (plain rectangle, no border, no prior shape decor) so users who
            -- never enable a shape pay nothing; a pip that ever had a mask/border keeps those
            -- fields so it still routes through ApplyPipShape to clean up when reverted.
            if cpShape ~= "rectangle" or cpBorderOn
               or pip._shapeMask or pip._border or pip._borderBox then
                ns.ApplyPipShape(plate, pip, cpShape, cpBorderOn, cpBorderCol, borderPx)
            end

            if isSecret then
                if not pip._secretBar then
                    local sb = CreateFrame("StatusBar", nil, plate)
                    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                    sb:SetFrameLevel(plate:GetFrameLevel() + 5)
                    pip._secretBar = sb
                end
                local sb = pip._secretBar
                sb:ClearAllPoints()
                sb:SetAllPoints(pip)
                sb:SetMinMaxValues(i - 1, i)
                sb:SetValue(cur)
                sb:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)
                sb:Show()
                pip:SetTexture(ns.CP_SHAPE.WHITE)
                pip:SetTexCoord(0, 1, 0, 1)
                pip:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                pip:Show()
            else
                if pip._secretBar then pip._secretBar:Hide() end
                if iconKind == "holypower" then
                    -- Desaturated socket as the background, lit rune on top when filled. Point 5 reuses point 4 mirrored.
                    local n = (i - 1) % 5 + 1
                    local flip = (n == 5)
                    local idx = flip and 4 or n
                    if bg then
                        bg:SetAtlas("nameplates-holypower" .. idx .. "-off")
                        bg:SetDesaturated(true)
                        if flip then bg:SetTexCoord(1, 0, 0, 1) end
                        bg:SetVertexColor(1, 1, 1, bgCol.a)
                        bg:Show()
                    end
                    if i <= cur then
                        pip:SetAtlas("nameplates-holypower" .. idx .. "-on")
                        if flip then pip:SetTexCoord(1, 0, 0, 1) end
                        pip:SetVertexColor(1, 1, 1, 1)
                        pip:Show()
                    else
                        pip:Hide()
                    end
                elseif iconKind then
                    -- Real resource art: the atlas defines the look, no tint.
                    pip:SetAtlas(ns.GetPipIconAtlas(iconKind, i <= cur, i))
                    if (i > cur) and ns.CP_ICON_DIM_EMPTY[iconKind] then
                        pip:SetVertexColor(0.35, 0.35, 0.35, 1)  -- dim single-atlas empties
                    else
                        pip:SetVertexColor(1, 1, 1, 1)
                    end
                    pip:Show()
                else
                    pip:SetTexture(ns.CP_SHAPE.WHITE)
                    pip:SetTexCoord(0, 1, 0, 1)
                    if i <= cur then
                        pip:SetVertexColor(cpColor[1], cpColor[2], cpColor[3], 1)
                    else
                        pip:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                    end
                    pip:Show()
                end
            end
        else
            pip:Hide()
            if pip._bg then pip._bg:Hide() end
            if pip._secretBar then pip._secretBar:Hide() end
            ns.HidePipDecor(pip)
        end
    end
end

local function HideClassPowerOnPlate(plate)
    if not plate or not plate._cpPips then return end
    for i = 1, #plate._cpPips do
        plate._cpPips[i]:Hide()
        if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
        if plate._cpPips[i]._secretBar then plate._cpPips[i]._secretBar:Hide() end
        ns.HidePipDecor(plate._cpPips[i])
    end
    if plate._cpBar then plate._cpBar:Hide() end
end

-- Return the extra Y offset that elements above the health bar need to clear
-- the class power pips (when pips are on top and visible on this plate).
GetClassPowerTopPush = function(plate)
    if not GetShowClassPower() or not classPowerType then return 0 end
    if ns.GetClassPowerPos() ~= "top" then return 0 end
    if not plate or not plate.unit or not UnitIsUnit(plate.unit, "target") then return 0 end
    local cpScale = ns.GetClassPowerScale()
    local cpYOff = ns.GetClassPowerYOffset()
    -- Square-footprint shapes are taller than the flat rectangle pip.
    local h = ns.CP_SHAPE.SQUARE[ns.GetClassPowerShape()] and CP_PIP_W or CP_PIP_H
    return h * cpScale + cpYOff
end

-- Find the target plate and update pips
local function RefreshClassPower()
    -- Form check (e.g. Druid combo points only in cat form)
    if classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq then
        -- Only need to hide pips on the target plate (others never have them)
        if ns._cachedTargetPlate then HideClassPowerOnPlate(ns._cachedTargetPlate) end
        return
    end
    -- PERF: only the target plate shows class power; skip iterating all plates
    if ns._cachedTargetPlate and ns._cachedTargetPlate.unit and UnitIsUnit(ns._cachedTargetPlate.unit, "target") then
        EnsureClassPowerPips(ns._cachedTargetPlate)
        UpdateClassPowerOnPlate(ns._cachedTargetPlate)
    end
end

-- Full refresh including repositioning of elements above the health bar.
-- Called on target change and settings change (not on every power tick).
local function RefreshClassPowerFull()
    -- Form check (e.g. Druid combo points only in cat form)
    local formHidden = classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq
    -- PERF: only the target plate shows pips; only it needs reposition for cpPush
    local tp = ns._cachedTargetPlate
    if tp and tp.unit then
        if not formHidden and UnitIsUnit(tp.unit, "target") then
            EnsureClassPowerPips(tp)
            UpdateClassPowerOnPlate(tp)
        else
            HideClassPowerOnPlate(tp)
        end
        tp:RefreshNamePosition()
        tp:UpdateRaidIcon()
    end
end

-- Forward declarations for mutual recursion on spec change
local DisableClassPowerWatcher
local ApplyClassPowerSetting

-- Enable/disable the class power watcher
local function EnableClassPowerWatcher()
    if classPowerWatcher then return end  -- already active
    local info = CLASS_POWER_MAP[PLAYER_CLASS]
    if not info then return end  -- class has no trackable resource

    -- Resolve spec-specific entries: if info has numeric specID keys, look up current spec
    if info[1] == nil then
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        info = specID and info[specID]
        if not info then return end  -- current spec has no trackable resource
    end

    classPowerType = info[1]
    classPowerMax = info[2]
    -- Druid Resto: cat form required. Feral always shows.
    local specIdx = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local isResto = (PLAYER_CLASS == "DRUID" and specIdx == 4)
    classPowerFormReq = isResto and 1 or nil
    classPowerWatcher = CreateFrame("Frame")

    -- String-type resources (custom-tracked): use OnUpdate poll + events
    if type(classPowerType) == "string" then
        local elapsed = 0
        classPowerWatcher:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then return end
            elapsed = 0
            RefreshClassPower()
        end)
        classPowerWatcher:RegisterUnitEvent("UNIT_AURA", "player")
        classPowerWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        classPowerWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        -- Manual tracker events (TotS, Whirlwind, Bladestorm/Unhinged)
        -- so tracking works even without EllesmereUIResourceBars loaded.
        classPowerWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        classPowerWatcher:RegisterEvent("PLAYER_DEAD")
        classPowerWatcher:RegisterEvent("PLAYER_ALIVE")
        classPowerWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- Stagger max is based on player health, so track health changes too
        if classPowerType == "BREWMASTER_STAGGER" then
            classPowerWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
            classPowerWatcher:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        end
        classPowerWatcher:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                -- The event carries a unit and is delivered for GROUP MEMBERS too, so
                -- without this filter a raid full of spec swaps rebuilds the watcher
                -- (and every pip on the personal plate) over and over for nothing.
                local specUnit = ...
                if specUnit ~= "player" then return end
                -- Spec changed: tear down and rebuild (spec may no longer have this resource)
                DisableClassPowerWatcher()
                ApplyClassPowerSetting()
            elseif event == "PLAYER_TARGET_CHANGED" then
                RefreshClassPowerFull()
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- Route to manual trackers so they work standalone.
                -- Skip if EllesmereUIResourceBars is loaded (it handles routing).
                if _G._ERB_AceDB then
                    RefreshClassPower()
                    return
                end
                local unit, castGUID, spellID = ...
                if unit == "player" and EllesmereUI then
                    if EllesmereUI.HandleTipOfTheSpear then
                        EllesmereUI.HandleTipOfTheSpear(event, unit, castGUID, spellID)
                    end
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
                    end
                    if EllesmereUI.HandleSweepingStrikes then
                        EllesmereUI.HandleSweepingStrikes(event, unit, castGUID, spellID)
                    end
                end
                RefreshClassPower()
            elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                if not _G._ERB_AceDB and EllesmereUI then
                    if EllesmereUI.HandleTipOfTheSpear then
                        EllesmereUI.HandleTipOfTheSpear(event)
                    end
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event)
                    end
                    if EllesmereUI.HandleSweepingStrikes then
                        EllesmereUI.HandleSweepingStrikes(event)
                    end
                end
                RefreshClassPower()
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not _G._ERB_AceDB and EllesmereUI then
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event)
                    end
                    if EllesmereUI.HandleSweepingStrikes then
                        EllesmereUI.HandleSweepingStrikes(event)
                    end
                end
                RefreshClassPower()
            else
                RefreshClassPower()
            end
        end)
    else
        classPowerWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        classPowerWatcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        classPowerWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        classPowerWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        if classPowerFormReq then
            classPowerWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
        -- Runes need their own event for per-rune cooldown changes
        if classPowerType == Enum.PowerType.Runes then
            classPowerWatcher:RegisterEvent("RUNE_POWER_UPDATE")
        end
        classPowerWatcher:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                -- Group members' spec events land here too; see the filter note in the
                -- string-resource branch above.
                if unit ~= "player" then return end
                DisableClassPowerWatcher()
                ApplyClassPowerSetting()
            elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
                RefreshClassPowerFull()
            else
                RefreshClassPower()
            end
        end)
    end
    RefreshClassPowerFull()
end

DisableClassPowerWatcher = function()
    if not classPowerWatcher then return end
    classPowerWatcher:UnregisterAllEvents()
    classPowerWatcher:SetScript("OnEvent", nil)
    classPowerWatcher:SetScript("OnUpdate", nil)
    classPowerWatcher:Hide()
    classPowerWatcher = nil
    classPowerFormReq = nil
    -- PERF: only target plate had pips; only it needs cleanup
    local tp = ns._cachedTargetPlate
    if tp then
        HideClassPowerOnPlate(tp)
        if tp.unit then
            tp:RefreshNamePosition()
            tp:UpdateRaidIcon()
        end
    end
end

-- Called at startup and when the setting changes
ApplyClassPowerSetting = function()
    if GetShowClassPower() then
        EnableClassPowerWatcher()
    else
        DisableClassPowerWatcher()
    end
end
ns.ApplyClassPowerSetting = ApplyClassPowerSetting
ns.RefreshClassPower = RefreshClassPowerFull
local function DarkenColor(r, g, b, factor)
    factor = factor or 0.60
    return r * factor, g * factor, b * factor
end
-- Out-of-combat darkening, gated by "Darken Enemies Out of Combat". On (default): enemies
-- confirmed in combat (clean boolean) keep full colour, out-of-combat/secret states darken --
-- or, with "Change Color Instead", take the flat Out of Combat Color rather than dimming.
local function MaybeDarken(r, g, b, inCombat)
    local on = (p and p.darkenEnemiesOOC)
    if on == nil then on = defaults.darkenEnemiesOOC end
    if not on then return r, g, b end
    if type(inCombat) == "boolean" and inCombat then return r, g, b end
    local recolor = (p and p.darkenOOCRecolor)
    if recolor == nil then recolor = defaults.darkenOOCRecolor end
    if recolor then
        local c = (p and p.darkenOOCColor) or defaults.darkenOOCColor
        return c.r, c.g, c.b
    end
    return DarkenColor(r, g, b)
end
-- Cached threat-context state; updated at zone transitions and spec changes
local _inThreatContent = false
local _isTankRole      = false

-- Off-tank color under identity restriction: the mob-target ROLE is secret, so
-- the question flips sides -- "is any OTHER tank tanking this mob" -- via
-- UnitDetailedThreatSituation(tankToken, mob) (plain tokens in; isTanking
-- boolean out, plain or secret; field-probed real boolean in keys) folded
-- through C_CurveUtil.EvaluateColorValueFromBoolean so no secret is ever read
-- in Lua. Returns ok plus possibly-SECRET r,g,b: the caller must hand them to
-- SETTERS ONLY -- never compare, cache, multiply or format them. Tank tokens
-- rebuild lazily off ns._otherTanksDirty (set by RefreshThreatCache's existing
-- roster/role/zone events -- zero new registrations; own-group role reads are
-- plain). On ns (file is at the 200-local cap).
function ns.ComputeOffTankFold(unit, br, bg, bb, otr, otg, otb)
    local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not eval then return false end
    if ns._otherTanksDirty or not ns._otherTankTokens then
        ns._otherTanksDirty = false
        local t = ns._otherTankTokens
        if t then wipe(t) else t = {}; ns._otherTankTokens = t end
        local n = 0
        local prefix, count
        if IsInRaid() then prefix, count = "raid", GetNumGroupMembers()
        elseif IsInGroup() then prefix, count = "party", GetNumGroupMembers() - 1 end
        if prefix then
            for i = 1, count do
                if n >= 3 then break end
                local tok = prefix .. i
                if not UnitIsUnit(tok, "player")
                    and UnitGroupRolesAssigned(tok) == "TANK" then
                    n = n + 1; t[n] = tok
                end
            end
        end
    end
    local toks = ns._otherTankTokens
    if not toks[1] then return false end
    -- All colors arrive from the caller: the _C accessor is declared far BELOW
    -- this function, so resolving colors here read a nil global (field crash).
    local r, g, b = br, bg, bb
    if not (r and otr) then return false end
    for i = 1, #toks do
        local isTanking = UnitDetailedThreatSituation(toks[i], unit)
        -- type() is legal on secrets and reports the underlying type, so one
        -- check admits both plain and secret booleans; a refused call (nil)
        -- skips and the accumulator keeps the safe tankNoAggro color.
        if type(isTanking) == "boolean" then
            r = eval(isTanking, otr, r)
            g = eval(isTanking, otg, g)
            b = eval(isTanking, otb, b)
        end
    end
    return true, r, g, b
end

local function RefreshThreatCache()
    ns._otherTanksDirty = true
    -- Zone: party/raid instances and delves (difficultyID 204) are threat-relevant
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- Dungeon-only flag for the "Mini Enemies" trash color (instanceType "party"; excludes
    -- raids/delves/open world). Cached so the per-plate color path costs one field read.
    ns._inDungeon = (instanceType == "party")
    if difficultyID == 0
    or (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap()) then
        _inThreatContent = false
    else
        local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
        _inThreatContent = (instanceType == "party" or instanceType == "raid"
                            or isDelve)
    end
    -- Role: cache so we don't recalculate on every nameplate update. Effective
    -- role (EllesmereUI.UnitEffectiveRole): the player's spec wins over a stale
    -- premade-listing role (listed as tank, playing dps), and still covers the
    -- solo "NONE" case the old spec fallback existed for.
    local role = EllesmereUI.UnitEffectiveRole("player")
    _isTankRole = (role == "TANK")
end

local function InRealInstancedContent()
    return _inThreatContent
end

-------------------------------------------------------------------------------
--  Quest Mob Detection: C_TooltipInfo scans unit tooltips for quest objective lines. Cached
--  per unit; invalidated on QUEST_LOG_UPDATE and NAME_PLATE_UNIT_REMOVED.
-------------------------------------------------------------------------------
local questMobCache = {}
-- Parallel cache of verified-clean "objectives remaining" strings, keyed by unit. Populated
-- only when replaceQuestIconWithObjective is ON; same invalidation lifecycle. On ns (cap).
ns._questObjText = ns._questObjText or {}
-- Is this unit one of the local player's active quest objectives with work remaining? Read
-- from the tooltip's structured data: a QuestObjective line carries `completed` plus
-- numFulfilled/numRequired, a QuestTitle line the quest id, so completion needs no
-- progress-string parsing. Ownership goes through the player's own quest log (only their
-- quests answer C_QuestLog.IsOnQuest), so a group member's objective is ignored. Every
-- structured value is possibly secret and issecretvalue-checked before use. Cached per unit;
-- cleared on QUEST_LOG_UPDATE and plate removal.
local function IsQuestMob(unit)
    if not (C_TooltipInfo and Enum and Enum.TooltipDataLineType) then return false end
    local cached = questMobCache[unit]
    if cached ~= nil then return cached end

    -- Open-world only, unless the indicator's "Show In Instances" opt-in lifts it.
    if InRealInstancedContent() then
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if not show then
            questMobCache[unit] = false
            return false
        end
    end

    local info = C_TooltipInfo.GetUnit(unit)
    if not (info and info.lines) then
        questMobCache[unit] = false
        return false
    end

    local LT = Enum.TooltipDataLineType
    local onQuest = C_QuestLog and C_QuestLog.IsOnQuest
    local wantText = (p and p.replaceQuestIconWithObjective == true) or false
    local questID  -- id carried by the most recent QuestTitle line
    local isQuest, objText = false, nil

    for _, line in ipairs(info.lines) do
        local kind = line.type
        if kind == LT.QuestTitle then
            local id = line.id
            if id and not (issecretvalue and issecretvalue(id)) then
                questID = id
            else
                questID = nil
            end
        elseif kind == LT.QuestObjective then
            local done = line.completed
            -- An incomplete objective the player is actually on: their quest log scopes out a
            -- group member's objectives. Fail open when the id is unreadable so a real quest
            -- mob is never silently skipped.
            if not (issecretvalue and issecretvalue(done)) and done == false
               and (not questID or not onQuest or onQuest(questID)) then
                isQuest = true
                if wantText then
                    local have, need = line.numFulfilled, line.numRequired
                    if have and need
                       and not (issecretvalue and (issecretvalue(have) or issecretvalue(need))) then
                        -- Percent-style objectives (area progress bars)
                        -- degenerate to 0/1 in the structured fields; the
                        -- real progress lives only in the line text. Show
                        -- the extracted percent when readable, else the
                        -- count (real 0/1 kill objectives keep their count).
                        local lt = line.leftText
                        local pct
                        if lt and not (issecretvalue and issecretvalue(lt))
                           and type(lt) == "string" then
                            pct = lt:match("(%d+)%s*%%")
                        end
                        objText = pct and (pct .. "%") or (have .. "/" .. need)
                    end
                end
                break
            end
        end
    end

    questMobCache[unit] = isQuest
    if wantText then
        ns._questObjText[unit] = isQuest and objText or nil
    end
    return isQuest
end
ns.IsQuestMob = IsQuestMob

-- Thin reader for the icon-replace feature. Returns a clean digit string or nil.
function ns.GetQuestObjectiveText(unit)
    return ns._questObjText[unit]
end

-- Live refresh for the options toggle. Wiping BOTH caches is required: IsQuestMob short-circuits
-- on questMobCache[unit] ~= nil, so a unit cached while OFF never gets objective text extracted.
function ns.RefreshQuestObjective()
    wipe(questMobCache)
    wipe(ns._questObjText)
    for _, plate in pairs(ns.plates) do
        if plate.UpdateClassification then
            plate:UpdateClassification()
        end
    end
end

-- Invalidate quest cache on quest log changes (throttled to avoid
-- recoloring all plates on every QUEST_LOG_UPDATE burst).
local questCacheWatcher = CreateFrame("Frame")
questCacheWatcher:RegisterEvent("QUEST_LOG_UPDATE")
ns._questDirty = false
questCacheWatcher:SetScript("OnEvent", function()
    wipe(questMobCache)
    wipe(ns._questObjText)
    if not ns._questDirty then
        ns._questDirty = true
        C_Timer.After(0.5, function()
            ns._questDirty = false
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
                plate:UpdateClassification()
            end
        end)
    end
end)

local function _C(key)
    return (p and p[key]) or defaults[key]
end
-- Neutral health-bar color: enemyInCombat tint while in combat, else neutral color. Shared by
-- every precedence step resolving to "neutral" (step 5, neutral+mini carve-out 7b, dungeon 10d).
local function ResolveNeutralColor(unit)
    if UnitAffectingCombat(unit) then
        local c = _C("enemyInCombat")
        return c.r, c.g, c.b
    end
    local c = _C("neutral")
    return c.r, c.g, c.b
end
-- Enemy Name Text "Reaction Color" (EXTRAS toggle, default off): colors the name text
-- Hostile or Neutral to match the unit's reaction, independent of the health-bar palette.
-- Every NameplateFrame unit is an enemy (HideBlizzardFrame only suppresses Blizzard's frame
-- on UnitCanAttack units), so only these two reactions are ever relevant here. Same
-- reaction/UnitCanAttack idiom as the health-bar Neutral check below (GetReactionColor step 5)
-- so a secret reaction read (identity-restricted units) falls through safely instead of erroring.
local function GetEnemyNameReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player"))
    local db = p or defaults
    local c
    if isNeutral then
        c = db.enemyNameNeutralColor or defaults.neutral
    else
        c = db.enemyNameHostileColor or defaults.hostile
    end
    return c.r, c.g, c.b
end
-- Blizzard's own plate for this unit, colored by untainted code. Under HideBlizzardFrame the
-- UnitFrame keeps its unit and its events (only castBar is silenced), so its health bar still
-- carries whatever CompactUnitFrame_UpdateHealthColor last resolved -- including the class
-- color we are not allowed to look up ourselves. Returns a PLAIN "have it" boolean plus three
-- numbers that may be secret: never branch on the numbers, only ever hand them to a setter.
-- On ns (module file is at the 200-local cap).
function ns.GetBlizzardBarColor(frame)
    local np = frame.nameplate
    local uf = np and np.UnitFrame
    -- Blizzard's plates are pooled too. Until ITS CompactUnitFrame_SetUnit has run for our
    -- unit, that bar still wears the previous occupant's colour, and latching onto it would
    -- paint a confidently WRONG class colour. No match, no mirror: the plain fallback applies
    -- and the next pass retries.
    if not uf or uf.unit ~= frame.unit then return false end
    local hb = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
    if not hb or not hb.GetStatusBarColor then return false end
    -- Same filter HideBlizzardFrame applies to this frame's children: reading a forbidden
    -- widget throws, which would abort the rest of UpdateHealthColor on every health event.
    if hb.IsForbidden and hb:IsForbidden() then return false end
    local r, g, b = hb:GetStatusBarColor()
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
    return true, r, g, b
end
local function GetReactionColor(unit)
    -- Per-call marker read SYNCHRONOUSLY by UpdateHealthColor right after this
    -- returns: true only when this resolution landed on the non-tank Near
    -- Aggro color, so the near-aggro glow rides the exact same decision.
    -- On ns (module file is at the 200-local cap).
    ns._reactionNearAggro = false
    -- Same idiom, for the enemy player class color at step 6: set when the class token
    -- came back redacted, so UpdateHealthColor knows to mirror Blizzard's bar instead.
    ns._reactionMirrorClass = false
    -- Same idiom, for the off-tank color under identity restriction: set when the
    -- mob-target ROLE read came back secret with Off-Tank Color enabled, so
    -- UpdateHealthColor asks ns.ComputeOffTankFold for a C-folded color instead
    -- of the plain tankNoAggro fallback this function returns.
    ns._reactionOffTankFold = false
    local db = p or defaults
    -- 1. Tapped always highest
    if UnitIsTapDenied(unit) then
        local c = _C("tapped")
        return c.r, c.g, c.b
    end
    -- 2. Quest mob second highest
    if db.questMobColorEnabled and IsQuestMob(unit) then
        local qc = db.questMobColor or defaults.questMobColor
        return qc.r, qc.g, qc.b
    end
    -- Threat colors that can NEVER be overwritten:
    -- Non-tank: has aggro, near aggro Tank: losing aggro, no aggro
    local isThreatUnit = false   -- set true when threat data exists
    local threatStatus = 0
    if InRealInstancedContent() then
        local status = UnitThreatSituation("player", unit)
        if status then
            isThreatUnit = true
            threatStatus = status
            if not _isTankRole then
                -- Non-tank: has aggro / near aggro absolute priority
                -- Only apply when in a group (solo players always have aggro)
                if IsInGroup() then
                if status >= 3 then
                    local c = _C("dpsHasAggro")
                    return c.r, c.g, c.b
                elseif status >= 2 then
                    ns._reactionNearAggro = true
                    local c = _C("dpsNearAggro")
                    return c.r, c.g, c.b
                end
                end
            else
                -- Tank arm. 12.1 field facts (side-by-side dump): the situation
                -- API pins 3 on plate tokens while the DETAILED API returns
                -- SECRET booleans for plate pairings (plain only for "target"
                -- pairings) -- no Lua branch can know who holds the mob. With
                -- Off-Tank Color on, mark EVERY tank-arm paint for the C-side
                -- fold: it starts from the plain color this function returns
                -- and overrides toward offTankAggro exactly when a co-tank's
                -- isTanking folds true. One tank holds per mob, so the fold
                -- self-resolves with zero secret reads.
                local otE = db.offTankAggroEnabled
                if otE == nil then otE = defaults.offTankAggroEnabled end
                if otE then ns._reactionOffTankFold = true end
                if status < 3 and status >= 2 then
                    local c = _C("tankLosingAggro")
                    return c.r, c.g, c.b
                elseif status < 3 then
                    -- Only show no-aggro warning if a non-tank has it.
                    -- If another tank holds aggro, this is normal offtank positioning.
                    local unitTarget = unit .. "target"
                    -- Role reads on identity-restricted units return SECRET values: never
                    -- truthiness-chain or compare one. Unreadable role reads as non-tank.
                    local targetRole = "NONE"
                    local roleSecret = false
                    if UnitExists(unitTarget) then
                        local r = UnitGroupRolesAssigned(unitTarget)
                        if issecretvalue(r) then roleSecret = true
                        elseif r then targetRole = r end
                    end
                    -- Role unreadable (identity restriction): the plain path
                    -- below lands on tankNoAggro, but mark the frame so
                    -- UpdateHealthColor can answer the REAL question from the
                    -- other side -- "is any other tank tanking this mob" via
                    -- UnitDetailedThreatSituation + the C_CurveUtil color fold
                    -- (field-probed: returns a real boolean in keys).
                    if roleSecret then
                        local otE = db.offTankAggroEnabled
                        if otE == nil then otE = defaults.offTankAggroEnabled end
                        if otE then ns._reactionOffTankFold = true end
                    end
                    if targetRole ~= "TANK" then
                        local c = _C("tankNoAggro")
                        return c.r, c.g, c.b
                    end
                    -- Another tank has aggro -- show off-tank color if enabled
                    local otEnabled = db.offTankAggroEnabled
                    if otEnabled == nil then otEnabled = defaults.offTankAggroEnabled end
                    if otEnabled then
                        local c = _C("offTankAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Classic tank aggro: has-aggro overrides all mob-type colors
                if status >= 3 then
                    local classic = db.classicTankAggro
                    if classic == nil then classic = defaults.classicTankAggro end
                    if classic then
                        local c = _C("tankHasAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Default: tank has aggro falls through to caster/miniboss colors
            end
        end
    end
    -- 4. Target color (if enabled)
    local targetC = _C("target")
    if targetC and UnitIsUnit(unit, "target") then
        local tEnabled = defaults.targetColorEnabled
        if db.targetColorEnabled ~= nil then tEnabled = db.targetColorEnabled end
        if tEnabled then
            return targetC.r, targetC.g, targetC.b
        end
    end
    -- 5. Focus color (if enabled)
    local focusC = _C("focus")
    if focusC and UnitIsUnit(unit, "focus") then
        local enabled = defaults.focusColorEnabled
        if db.focusColorEnabled ~= nil then enabled = db.focusColorEnabled end
        if enabled then
            return focusC.r, focusC.g, focusC.b
        end
    end
    -- 5. Neutral (colored as an enemy while in combat with them). OUTSIDE dungeons keeps its
    -- high priority; IN dungeons deferred to just above the enemy fallback (step 10d) so
    -- mob-type/threat colors win on neutral dungeon units and neutral becomes near-last resort.
    local reaction = UnitReaction(unit, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player"))
    if isNeutral and not ns._inDungeon then
        return ResolveNeutralColor(unit)
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
        local _, class = UnitClass(unit)
        -- A secret class token (identity-restricted, i.e. instanced PvP) cannot key a
        -- color table. Blizzard resolves the same lookup UNTAINTED on its own plate and
        -- its bar keeps updating under our suppression, so flag the plate here and let
        -- UpdateHealthColor copy that color across without ever inspecting it. We still
        -- fall through to the reaction color so every plain-number consumer downstream
        -- (the skip-if-unchanged compare, the No Tint overlay tints) keeps plain numbers.
        -- Gated on the CVar because that is what decides whether Blizzard's bar is a class
        -- color at all: with it off the bar carries a selection/threat color, and copying
        -- that would overwrite the user's Enemy Types color with red.
        if issecretvalue(class) then
            ns._reactionMirrorClass = GetCVarBool("nameplateShowClassColor") == true
            class = nil
        end
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- Classify the mob-type tier once up front so the tank has-aggro overrides can reason about
    -- boss vs mini-boss vs caster independently. Booleans only: mob-type colors still return at
    -- their own priority steps (7, 8, 10b).
    local inCombat = UnitAffectingCombat(unit)
    local classification = UnitClassification(unit)
    -- Full Coloring M+ Only (inline cog on Enemy Types): outside 5-man dungeons, collapse the
    -- mob-type colors (Mini Enemies, Spell Casters, Mini-Bosses, Bosses) into flat owBasicColor
    -- at the enemy fallback (step 11). Neutral unaffected (already returned at step 5 outside
    -- dungeons). Same dungeon gate as Mini Coloring M+ Only (ns._inDungeon).
    local owBasic = false
    if not ns._inDungeon then
        owBasic = defaults.owBasicColoring
        if db.owBasicColoring ~= nil then owBasic = db.owBasicColoring end
    end
    -- Mini Enemies color scope: restricted to 5-man dungeons when "Mini Coloring
    -- M+ Only" is on (default), applied everywhere when it is off.
    local miniMPlusOnly = defaults.miniColoringMPlusOnly
    if db.miniColoringMPlusOnly ~= nil then miniMPlusOnly = db.miniColoringMPlusOnly end
    local miniColorScope = not owBasic and (ns._inDungeon or not miniMPlusOnly)
    local _isBossUnit = false  -- deferred: boss color is applied at step 10b
    local _isMiniBoss = false
    if not owBasic
       and (classification == "elite" or classification == "worldboss" or classification == "rareelite") then
        -- Effective level (handles scaling / Chromie time), not raw level, so
        -- the tier tracks how the game ranks the mob against the player.
        local level = UnitEffectiveLevel(unit)
        local lvlClean = level and not (issecretvalue and issecretvalue(level))
        local isSkull = lvlClean and level == -1
        local playerLevel = UnitEffectiveLevel("player")
        local plvlClean = playerLevel and not (issecretvalue and issecretvalue(playerLevel))
        -- A skull, or an elite ranked at least one effective level above the
        -- player, gets a tier; ordinary same/lower-level elites are left alone.
        local aboveOne = plvlClean and lvlClean and level >= playerLevel + 1
        if isSkull or aboveOne then
            -- Boss when it reads as boss-ranked: a skull, a world boss, or two+ effective
            -- levels up. UnitIsLieutenant is the client's mini-boss marker, so a non-skull
            -- lieutenant is pinned to mini-boss.
            local aboveTwo = plvlClean and lvlClean and level >= playerLevel + 2
            local lieutenant = (not isSkull) and UnitIsLieutenant and UnitIsLieutenant(unit)
            if not lieutenant and (isSkull or aboveTwo or classification == "worldboss") then
                _isBossUnit = true
            else
                _isMiniBoss = true
            end
        end
    end
    -- Caster = the unit actually has a mana pool, rather than a class match. Second arg is
    -- typed PowerType (enum NUMBER), not the global MANA (localized "Mana" string, never
    -- matches). hasPower carries no secrecy flag, so it is safe to branch on directly.
    local _isCaster = not owBasic and UnitHasPowerType(unit, Enum.PowerType.Mana)
    -- DPS/healer No Aggro override state (mirrors tank has-aggro overrides at 6b). Each
    -- override independently promotes the No Aggro color above one mob-type step (mini-boss 7,
    -- caster 8). Active only for a non-tank without aggro in a group (matches step 10).
    local dpsNoAggroActive = isThreatUnit and (not _isTankRole) and threatStatus < 2 and IsInGroup()
    if dpsNoAggroActive then
        local en = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then en = db.dpsNoAggroEnabled end
        dpsNoAggroActive = en
    end
    -- 6b. Tank has aggro -- "Override Mini-Boss and Caster colors" option. Promotes the
    -- has-aggro color above the mini-boss/caster steps, still below target/focus/enemy-class.
    -- Boss units excluded (governed by "Override Boss colors", step 9/10b). Sits between the
    -- absolute-priority Classic Tank Aggro path above and low-priority step 9.
    if isThreatUnit and _isTankRole and threatStatus >= 3 and not _isBossUnit then
        local hae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then hae = db.tankHasAggroEnabled end
        local ovr = defaults.tankHasAggroOverrideMobType
        if db.tankHasAggroOverrideMobType ~= nil then ovr = db.tankHasAggroOverrideMobType end
        if hae and ovr then
            local c = _C("tankHasAggro")
            return c.r, c.g, c.b
        end
    end
    -- 7. Mini-boss. Boss is intentionally LOWER priority than the low-priority threat colors
    -- below, so it is deferred to step 10b (see _isBossUnit); mini-boss stays here, above threat.
    if _isMiniBoss then
        -- DPS/healer No Aggro "Override Mini-Boss colors": promotes the No Aggro
        -- color above the mini-boss color when enabled.
        if dpsNoAggroActive then
            local ovr = defaults.dpsNoAggroOverrideMiniBoss
            if db.dpsNoAggroOverrideMiniBoss ~= nil then ovr = db.dpsNoAggroOverrideMiniBoss end
            if ovr then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("miniboss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 7b. Mini Enemies promoted ABOVE Caster -- but ONLY for DPS/healers and tanks that do NOT
    -- use the special Tank Has Aggro color. Tanks WITH that option enabled skip this and keep
    -- Mini Enemies at its original low priority (step 10c), so has-aggro/caster/mob-type colors
    -- still win on trash.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        local thae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then thae = db.tankHasAggroEnabled end
        -- Neutral + mini-enemy: neutral coloring wins over the trash color, EXCEPT for a tank
        -- holding aggro with Tank Has Aggro enabled -- that viewer falls through so step 9
        -- paints the has-aggro color; otherwise in-combat neutral blocks threat coloring and
        -- neutral mobs stay enemy-red for tanks. Other viewers: neutral beats trash/DPS
        -- carve-out/Caster (7b sits above step 8). Non-trash neutral units defer to 10d.
        local tankAggroPending = isThreatUnit and _isTankRole and threatStatus >= 3 and thae
        if isNeutral and not tankAggroPending then return ResolveNeutralColor(unit) end
        if not (_isTankRole and thae) then
            -- DPS "No Aggro" still wins over the promoted Mini Enemies color, so a DPS/healer
            -- without aggro sees the warning on trash. Scoped to this trash branch so Caster
            -- still outranks DPS No Aggro on non-trash casters (step 10, same condition).
            if isThreatUnit and not _isTankRole and threatStatus < 2 and IsInGroup() then
                local dpsNA = defaults.dpsNoAggroEnabled
                if db.dpsNoAggroEnabled ~= nil then dpsNA = db.dpsNoAggroEnabled end
                if dpsNA then
                    local c = _C("dpsNoAggro")
                    return c.r, c.g, c.b
                end
            end
            local c = (p and p.miniEnemy) or _C("enemyInCombat")
            return MaybeDarken(c.r, c.g, c.b, inCombat)
        end
    end
    -- 8. Caster
    if _isCaster then
        -- DPS/healer No Aggro "Override Caster colors": promotes No Aggro above the caster
        -- color when enabled. Kept separate from the mini-boss override for contrast.
        if dpsNoAggroActive then
            local ovr = defaults.dpsNoAggroOverrideCaster
            if db.dpsNoAggroOverrideCaster ~= nil then ovr = db.dpsNoAggroOverrideCaster end
            if ovr then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("caster")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 9. Tank has aggro (if enabled) below focus/caster/miniboss. Normally sits above the boss
    -- color (step 10b); with "Override Boss colors" disabled it's held below boss instead (the
    -- 10b return wins for boss units, so has-aggro lands just below bosses).
    if isThreatUnit and _isTankRole and threatStatus >= 3 then
        local enabled = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then enabled = db.tankHasAggroEnabled end
        if enabled then
            local ovrBoss = defaults.tankHasAggroOverrideBoss
            if db.tankHasAggroOverrideBoss ~= nil then ovrBoss = db.tankHasAggroOverrideBoss end
            if ovrBoss or not _isBossUnit then
                local c = _C("tankHasAggro")
                return c.r, c.g, c.b
            end
        end
    end
    -- 10. Non-tank no aggro (if enabled) below focus/caster/miniboss
    if isThreatUnit and not _isTankRole and threatStatus < 2 and IsInGroup() then
        local enabled = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then enabled = db.dpsNoAggroEnabled end
        if enabled then
            local c = _C("dpsNoAggro")
            return c.r, c.g, c.b
        end
    end
    -- 10b. Boss (intentionally below the low-priority threat colors above, so tank-has-aggro/
    -- dps-no-aggro takes precedence over boss -- unless "Override Boss colors" is disabled, in
    -- which case the has-aggro step above defers to this boss color for boss units).
    if _isBossUnit then
        local c = _C("boss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10c. Mini Enemies: non-elite trash (normal/minus), DUNGEONS ONLY -- outside dungeons
    -- these fall through to the enemy color below. Elites handled at step 7, so same-level
    -- elites still use the enemy color. Below the threat colors, so aggro still wins.
    -- DPS/healers and non-special-aggro tanks already returned at 7b; this path only serves
    -- tanks with "Has Aggro" on.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        -- Views "Enemies" (enemyInCombat) until the user sets a Mini Enemies color explicitly.
        local c = (p and p.miniEnemy) or _C("enemyInCombat")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10d. Neutral, deferred (dungeons only -- step 5 skipped it there): a neutral unit
    -- matching no mob-type/threat color lands here, just above the generic enemy fallback.
    if isNeutral then
        return ResolveNeutralColor(unit)
    end
    -- 11. Fallback: enemy in/out of combat. With Full Coloring M+ Only active, every mob-type
    -- special above was suppressed, so all hostile mobs share the flat "All Enemies" color.
    local eic = _C(owBasic and "owBasicColor" or "enemyInCombat")
    return MaybeDarken(eic.r, eic.g, eic.b, inCombat)
end
local hookedUFs = {}
local hookedHighlights = {}
local hookedSoftTargetIcons = {}
local npOffscreenParent = CreateFrame("Frame")
npOffscreenParent:Hide()
local storedParents = {}
local function HideBlizzardElement(element)
    if element then
        element:SetAlpha(0)
        element:Hide()
        if element.SetScale then element:SetScale(0.001) end
    end
end
local function MoveToOffscreen(element, unit)
    if not element then return end
    -- PERF: skip SetParent if already offscreen (saves ~14 calls per plate respawn)
    if element:GetParent() == npOffscreenParent then return end
    if not storedParents[element] then
        storedParents[element] = element:GetParent()
    end
    element:SetParent(npOffscreenParent)
end
local function RestoreFromOffscreen(element)
    if not element then return end
    local origParent = storedParents[element]
    if origParent then
        element:SetParent(origParent)
        storedParents[element] = nil
    end
end
local function HideBlizzardFrame(nameplate, unit)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    -- Suppress unconditionally: if we are called, an EUI plate is taking over this nameplate.
    -- NEVER gate on UnitCanAttack -- it can return false on the first frame (unit not fully
    -- registered), skipping the whole block and leaving Blizzard's UnitFrame visible as a
    -- giant black box.
    uf:SetAlpha(0)
    -- The AurasFrame rides offscreen with the other children (WidgetContainer is the one child
    -- kept live, below): our containers own plate auras and these lists are taint-locked and
    -- unused. Alpha-0 keep-alive is NOT enough -- its item frames are mouse-enabled Blizzard
    -- templates with tooltip handlers, an invisible tooltip/click trap parked above every plate.
    if uf.AurasFrame then
        MoveToOffscreen(uf.AurasFrame, unit)
    end
    -- Park the UnitFrame's child frames on the hidden holder, discovered generically:
    -- whatever Blizzard parents under the UnitFrame is swept, no per-widget list to maintain.
    -- The UnitFrame ITSELF must stay on the nameplate where Blizzard placed it (alpha 0 above)
    -- -- parking the whole frame under a hidden holder flips every plate's content to
    -- IsVisible()==false and breaks click target selection between overlapping plates in packs.
    -- Exclusions: kept-live frames, plus protected/forbidden children (alpha 0 hides them).
    for i = 1, uf:GetNumChildren() do
        local child = select(i, uf:GetChildren())
        if child and child ~= uf.WidgetContainer and child ~= uf.AurasFrame
        and child ~= uf.SoftTargetFrame
           and not child:IsForbidden() and not child:IsProtected() then
            if not storedParents[child] then storedParents[child] = uf end
            child:SetParent(npOffscreenParent)
        end
    end
    -- All visual children are reparented offscreen so layout recalculations cannot shift
    -- bounds.
    -- Kill the CompactUnitFrame's ENTIRE event surface (raid-frames-style
    -- takeover): Blizzard registers ~27 unit events (incl. UNIT_AURA) plus
    -- ~20 globals (incl. UPDATE_MOUSEOVER_UNIT) per plate, and its dirty
    -- flags arm a real OnUpdate on this alpha-0 frame -- none of which our
    -- rendering uses, all of which was running under every plate all combat
    -- long. Self-healing: our restore runs only on NAME_PLATE_UNIT_REMOVED,
    -- and the driver's next secure CompactUnitFrame_SetUnit re-registers
    -- everything on reacquisition. The soft-target trio comes back below:
    -- the kept-alive SoftTargetFrame icon is driven by exactly those events
    -- (the OnEvent script itself stays -- Blizzard set it, and
    -- UnregisterAllEvents clears registrations only).
    uf:UnregisterAllEvents()
    uf:RegisterEvent("PLAYER_TARGET_CHANGED")
    uf:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
    uf:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
    -- The castBar is its own frame with its own registrations (we render our own).
    if uf.castBar then
        uf.castBar:UnregisterAllEvents()
    end
    -- Keep WidgetContainer functional but reparent to the nameplate itself so its layout
    -- doesn't affect the UnitFrame's bounds.
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(nameplate)
    end
    -- Keep the soft-target cursor icon working: reparent it live instead of sweeping it
    -- offscreen or leaving it under uf's forced alpha-0.
    if uf.SoftTargetFrame then
        uf.SoftTargetFrame:SetParent(nameplate)
        uf.SoftTargetFrame:SetAlpha(1)
        -- Same icon is reused for enemy/friend/interact soft-targets; only allow the
        -- interact case through. The hook cannot be uninstalled, so it gates on the
        -- reparented state: while WE hold the frame its grandparent is the plate BASE,
        -- which carries namePlateUnitToken (the field this file already uses for
        -- base->unit resolution); after RestoreBlizzardFrame the grandparent is the
        -- UnitFrame, the token read misses, and Blizzard's stock behavior stands.
        local icon = uf.SoftTargetFrame.Icon
        if icon and not hookedSoftTargetIcons[icon] then
            hookedSoftTargetIcons[icon] = true
            hooksecurefunc(icon, "Show", function(self)
                local stf = self:GetParent()
                local base = stf and stf:GetParent()
                local ufUnit = base and base.namePlateUnitToken
                if not ufUnit then return end
                -- Hide only for attackable enemies. NPCs and non-attackable
                -- objects, even hostile ones, keep the icon.
                local canAttack = UnitCanAttack("player", ufUnit)
                if issecretvalue and issecretvalue(canAttack) then return end
                if canAttack then self:Hide() end
            end)
        end
    end
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            -- Force alpha 0 only while an EUI plate owns this nameplate. On recycle to a
            -- friendly unit the plate is released and ns.plates[unit] is nil, so the hook no-ops.
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if not ufUnit or not ns.plates[ufUnit] then return end
            locked = true
            self:SetAlpha(0)
            locked = false
        end)
    end
    if uf.selectionHighlight and not hookedHighlights[uf.selectionHighlight] then
        hookedHighlights[uf.selectionHighlight] = true
        hooksecurefunc(uf.selectionHighlight, "Show", function(self)
            local parent = self:GetParent()
            if parent == npOffscreenParent then return end
            if parent then
                local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                    self:SetAlpha(0)
                    self:Hide()
                end
            end
        end)
        hooksecurefunc(uf.selectionHighlight, "SetShown", function(self, shown)
            if shown then
                local parent = self:GetParent()
                if parent == npOffscreenParent then return end
                if parent then
                    local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
                    if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                        self:SetAlpha(0)
                        self:Hide()
                    end
                end
            end
        end)
    end
end
-- Restore Blizzard UnitFrame elements when a nameplate is removed, so the recycled frame is
-- clean for the next unit.
local function RestoreBlizzardFrame(nameplate)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    -- Return this UnitFrame's parked children from the hidden holder (shared by every plate,
    -- filter by recorded owner), then re-home the kept-live frames.
    for i = npOffscreenParent:GetNumChildren(), 1, -1 do
        local child = select(i, npOffscreenParent:GetChildren())
        if child and storedParents[child] == uf then
            child:SetParent(uf)
            storedParents[child] = nil
        end
    end
    -- Safety if the whole UnitFrame was ever parked; normally a no-op.
    if storedParents[uf] then
        uf:SetParent(storedParents[uf])
        storedParents[uf] = nil
    end
    uf:SetAlpha(1)
    if uf.AurasFrame then
        if storedParents[uf.AurasFrame] then
            uf.AurasFrame:SetParent(storedParents[uf.AurasFrame])
            storedParents[uf.AurasFrame] = nil
        end
        uf.AurasFrame:SetAlpha(1)
    end
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(uf)
    end
    if uf.SoftTargetFrame then
        uf.SoftTargetFrame:SetParent(uf)
    end
end
ns.HideBlizzardFrame = HideBlizzardFrame
local castFallbackFrame = CreateFrame("Frame")
local fallbackCastCount = 0
local _fallbackPlates = {}
castFallbackFrame._textAccum = 0.1
castFallbackFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Bar fill tracks every frame (smoothness); target TEXT refreshes at 10Hz -- names never
    -- change faster and per-frame SetText is wasted, especially on secret strings.
    local textAccum = self._textAccum + elapsed
    local doText = textAccum >= 0.1
    self._textAccum = doText and 0 or textAccum
    for plate in pairs(_fallbackPlates) do
        if plate.isCasting and plate.unit and plate.nameplate then
            local bc = plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                plate.cast:SetMinMaxValues(bc:GetMinMaxValues())
                plate.cast:SetValue(bc:GetValue())
                -- Keep spell name + target current in fallback mode.
                if doText and plate.UpdateCastText then
                    local castName = UnitCastingInfo(plate.unit)
                    if type(castName) == "nil" then castName = UnitChannelInfo(plate.unit) end
                    plate:UpdateCastText(castName)
                end
            else
                if not plate._interrupted then
                    plate.cast:Hide()
                end
                plate.isCasting = false
                plate._castFallback = nil
                _fallbackPlates[plate] = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then
                    fallbackCastCount = 0
                    castFallbackFrame:Hide()
                end
                NotifyCastEnded(plate)
            end
        end
    end
end)
castFallbackFrame:Hide()

-- Shared cast-bar text anchoring. The text line holds three elements (spell name, spell
-- target, cast timer), each assigned to a side. The timer reserves a fixed width on its side;
-- a non-center element sharing that side shifts inward by that width. Center elements anchor
-- to the bar center and are never pushed.
--   side    : "left" | "right" | "center"
--   pushed  : true when the timer shares this side and this element must move in
--   reserve : timer reserved width (only consumed when pushed)
--   isTimer : the timer uses slightly tighter base insets than text
-- Returns: point (anchor), xOff (base, before the user X offset), justify
function ns.GetCastTextAnchor(side, pushed, reserve, isTimer)
    if side == "center" then
        return "CENTER", 0, "CENTER"
    elseif side == "left" then
        local base = isTimer and 3 or 5
        if pushed then base = base + reserve end
        return "LEFT", base, "LEFT"
    else -- "right"
        local base = -3
        if pushed then base = base - reserve end
        return "RIGHT", base, "RIGHT"
    end
end

-- WoW does not visually re-lay-out a FontString when only SetJustifyH changes (only a fresh
-- build does), so clear then re-set the text to force realignment -- and it MUST be a real
-- change, since re-setting an identical string is deduped and skips the re-layout. GetText may
-- return a secret (enemy name, cast name/target): SetText accepts secrets without inspecting
-- them, but truthiness/equality on a secret errors, so the existence check uses type() rather
-- than `t or ""`.
function ns.ReflowFontString(fs)
    local t = fs:GetText()
    fs:SetText("")
    if type(t) == "nil" then
        fs:SetText("")
    else
        fs:SetText(t)
    end
end

local NameplateFrame = {}

function NameplateFrame:UpdateCastText(spellName)
    local spellTarget, spellTargetClass
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(self.unit) then
        local rawTarget = UnitSpellTargetName and UnitSpellTargetName(self.unit)
        -- Names may be SECRET: type() is safe, and SetText/SetFormattedText accept secret
        -- strings without exposing them to Lua.
        if type(rawTarget) ~= "nil" then
            spellTarget = rawTarget
            spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(self.unit)
        end
    end

    local hasTarget = type(spellTarget) ~= "nil"
    local db = p or defaults
    local combine = db.castCombineNameTarget == true
    local useClassColor = defaults.castTargetClassColor
    if db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end

    local targetColor
    if useClassColor then
        if type(spellTargetClass) ~= "nil" and C_ClassColor then
            targetColor = C_ClassColor.GetClassColor(spellTargetClass)
        end
    end

    local nameColor = db.castNameColor or defaults.castNameColor
    -- Combined mode paints the target color onto the cast NAME string (the target rides
    -- in it as a format arg); separate mode paints its own FontString.
    local targetText
    if combine and hasTarget then
        targetText = self.castName
    else
        targetText = self.castTarget
    end
    if useClassColor then
        if targetColor then
            targetText:SetTextColor(targetColor:GetRGB())
        else
            targetText:SetTextColor(1, 1, 1, 1)
        end
    else
        local c = db.castTargetColor or defaults.castTargetColor
        targetText:SetTextColor(c.r, c.g, c.b, 1)
    end
    if not combine or not hasTarget then
        self.castName:SetTextColor(nameColor.r, nameColor.g, nameColor.b, 1)
    end

    if type(spellName) == "nil" then
        self.castName:SetText("")
    elseif combine and hasTarget then
        -- 12.1 class RGB may be SECRET: use it as the FontString's base color,
        -- then override only the spell prefix with a clean profile-color escape.
        local nameHex = string.format("ff%02x%02x%02x",
            math.floor(nameColor.r * 255 + 0.5), math.floor(nameColor.g * 255 + 0.5),
            math.floor(nameColor.b * 255 + 0.5))
        self.castName:SetFormattedText("|c" .. nameHex .. "%s - |r%s", spellName, spellTarget)
    else
        self.castName:SetText(spellName)
    end
    if combine or not hasTarget then
        self.castTarget:SetText("")
    else
        self.castTarget:SetText(spellTarget)
    end

    local castW = self.cast:GetWidth()
    if castW and castW > 0 then
        local nameWidth = combine and 80 or (db.castNameWidthPct or defaults.castNameWidthPct)
        self.castName:SetWidth(castW * nameWidth / 100)
    end
    self.castName:SetShown((db.castNameSide or defaults.castNameSide) ~= "none")
    self.castTarget:SetShown(not combine and hasTarget
        and (db.castTargetSide or defaults.castTargetSide) ~= "none")
end

-- Appearance generation: bumped by RefreshAllSettings so plates re-apply static appearance on
-- next SetUnit. Plates stamp _appearanceGen after applying so cache-hit re-spawns skip the work.
ns._npAppearanceGen = ns._npAppearanceGen or 1

-- Static appearance: anchors, sizes, fonts, colors and aura layout depending only on settings,
-- not the bound unit. Runs once per plate after creation, then only when RefreshAllSettings
-- bumps the generation. Saves ~0.7ms per spawn.
function NameplateFrame:ApplyAppearance()
    self:SetSize(1, 1)
    local castH = GetCastBarHeight()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.absorb:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    ns.ApplyLowHpGlow(self)
    -- Width may have changed: clear the overlay gates so the next apply re-runs geometry (the
    -- stripe texcoord crop derives from the settings width, which the gates never watch).
    self._ovTgtTex, self._ovFocTex, self._ovHoverTex = nil, nil, nil
    ns.LayoutCastBar(self, ns.GetHealthBarWidth(), castH)
    ns.LayoutCastIcon(self, castH)
    ns.ApplyFrameIconBorder(self.castIconFrame, ns.GetIconBorderEnabled("cast"))
    local showIcon = GetShowCastIcon()
    if showIcon then
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    self.castLeftBorder:SetWidth(1)
    self.castSpark:SetHeight(castH)
    -- Show Spark (Cast Color cog): default on; explicit false hides it.
    self.castSpark:SetShown(not (p and p.castBarSparkEnabled == false))
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot; any name-family variant)
    local nameSlotKey = ns.FindNameSlot()
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
    -- Enemy Name Text "Reaction Color" cache: ApplyAppearance is a second writer of
    -- self.name's color (the slot-color line above), so invalidate the skip-if-unchanged
    -- cache here too -- otherwise a stale cache can wrongly skip re-applying the reaction
    -- color on the very next UpdateHealthColor call (which always runs immediately after
    -- this, from the same SetUnit), leaving the plate showing this slot color instead.
    self._lastNameReactR, self._lastNameReactG, self._lastNameReactB = nil, nil, nil
    self:RefreshNamePosition()
    -- Cast text sizes, colors, and offsets
    local cns = (p and p.castNameSize) or defaults.castNameSize
    local cts = (p and p.castTargetSize) or defaults.castTargetSize
    local cnc = (p and p.castNameColor) or defaults.castNameColor
    local ctmSz = (p and p.castTimerSize) or defaults.castTimerSize
    local ctmC = (p and p.castTimerColor) or defaults.castTimerColor
    local cnOX = (p and p.castNameOffsetX) or defaults.castNameOffsetX
    local cnOY = (p and p.castNameOffsetY) or defaults.castNameOffsetY
    local ctOX = (p and p.castTargetOffsetX) or defaults.castTargetOffsetX
    local ctOY = (p and p.castTargetOffsetY) or defaults.castTargetOffsetY
    local tmOX = (p and p.castTimerOffsetX) or defaults.castTimerOffsetX
    local tmOY = (p and p.castTimerOffsetY) or defaults.castTimerOffsetY
    SetFSFont(self.castName, cns, GetNPOutline())
    SetFSFont(self.castTarget, cts, GetNPOutline())
    SetFSFont(self.castTimer, ctmSz, GetNPOutline())
    self.castTimer:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
    local showTimer = defaults.showCastTimer
    if p and p.showCastTimer ~= nil then showTimer = p.showCastTimer end
    self._showCastTimer = showTimer
    local nameSide   = (p and p.castNameSide)   or defaults.castNameSide
    local targetSide = (p and p.castTargetSide) or defaults.castTargetSide
    local timerSide  = (p and p.castTimerSide)  or defaults.castTimerSide
    local combineNameTarget = p and p.castCombineNameTarget == true
    local castW = self.cast:GetWidth()
    local timerW = ctmSz * 2.2
    -- Per-element truncation: width as a % of the cast bar, plus a wrap toggle.
    local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
    local ctWPct = (p and p.castTargetWidthPct) or defaults.castTargetWidthPct
    local cnWrap = defaults.castNameWrap
    if p and p.castNameWrap ~= nil then cnWrap = p.castNameWrap end
    local ctWrap = defaults.castTargetWrap
    if p and p.castTargetWrap ~= nil then ctWrap = p.castTargetWrap end
    self.castName:SetWordWrap(cnWrap)
    self.castName:SetMaxLines(cnWrap and 2 or 1)
    self.castTarget:SetWordWrap(ctWrap)
    self.castTarget:SetNonSpaceWrap(false)
    self.castTarget:SetMaxLines(ctWrap and 2 or 1)
    if castW and castW > 0 then
        if nameSide ~= "none" then
            local pt, xb, jh = ns.GetCastTextAnchor(nameSide, showTimer and timerSide == nameSide, timerW, false)
            self.castName:SetWidth(castW * (combineNameTarget and 80 or cnWPct) / 100)
            self.castName:SetJustifyH(jh)
            self.castName:ClearAllPoints()
            self.castName:SetPoint(pt, self.cast, pt, xb + cnOX, cnOY)
        end
        if targetSide ~= "none" then
            local pt, xb, jh = ns.GetCastTextAnchor(targetSide, showTimer and timerSide == targetSide, timerW, false)
            self.castTarget:SetWidth(castW * ctWPct / 100)
            self.castTarget:SetJustifyH(jh)
            self.castTarget:ClearAllPoints()
            self.castTarget:SetPoint(pt, self.cast, pt, xb + ctOX, ctOY)
        end
        -- Timer side is only "left"/"right"; visibility stays governed by showTimer.
        local tpt, txb, tjh = ns.GetCastTextAnchor(timerSide, false, timerW, true)
        -- timerW stays the layout reserve (pushes name/target inward above), but the timer
        -- FontString auto-sizes (width 0) so a long value never truncates. Pinned by its outer
        -- edge (RIGHT on the right side, LEFT on the left), so overflow grows inward past the
        -- reserved slot while the pinned edge holds.
        self.castTimer:SetWidth(0)
        self.castTimer:SetJustifyH(tjh)
        self.castTimer:ClearAllPoints()
        self.castTimer:SetPoint(tpt, self.cast, tpt, txb + tmOX, tmOY)
    end
    -- Base visibility by side (UpdateCast refines the target per cast on hasTarget).
    self.castName:SetShown(nameSide ~= "none")
    self.castTarget:SetShown(not combineNameTarget and targetSide ~= "none")
    self.castTimer:SetShown(showTimer)
    -- Force the new justify onto already-rendered text (side changed mid-cast): a fresh cast
    -- re-flows itself via UpdateCast, a live setting change does not.
    ns.ReflowFontString(self.castName)
    ns.ReflowFontString(self.castTarget)
    ns.ReflowFontString(self.castTimer)
    self.castName:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    local function GetAuraDurationCfg(kind)
        local sizeKey = kind .. "DurationTextSize"
        local xKey = kind .. "DurationTextX"
        local yKey = kind .. "DurationTextY"
        local colorKey = kind .. "DurationTextColor"
        return {
            size = (p and p[sizeKey]) or (p and p.auraDurationTextSize) or defaults.auraDurationTextSize,
            x = (p and p[xKey]) or (p and p.auraDurationTextX) or defaults.auraDurationTextX,
            y = (p and p[yKey]) or (p and p.auraDurationTextY) or defaults.auraDurationTextY,
            color = (p and p[colorKey]) or (p and p.auraDurationTextColor) or defaults.auraDurationTextColor,
        }
    end
    local debuffDur = GetAuraDurationCfg("debuff")
    local buffDur = GetAuraDurationCfg("buff")
    local ccDur = GetAuraDurationCfg("cc")
    local auraStackSize = (p and p.auraStackTextSize) or defaults.auraStackTextSize
    local auraStackColor = (p and p.auraStackTextColor) or defaults.auraStackTextColor
    local auraStackX = (p and p.auraStackTextX) or defaults.auraStackTextX
    local auraStackY = (p and p.auraStackTextY) or defaults.auraStackTextY
    local auraStackPos = (p and p.auraStackTextPosition) or defaults.auraStackTextPosition
    local debuffTPos = (p and p.debuffTimerPosition) or (p and p.auraTextPosition) or defaults.debuffTimerPosition
    local buffTPos   = (p and p.buffTimerPosition)   or (p and p.auraTextPosition) or defaults.buffTimerPosition
    local ccTPos     = (p and p.ccTimerPosition)     or (p and p.auraTextPosition) or defaults.ccTimerPosition
    local function ApplyTimerPosition(durText, auraFrame, pos, cfg)
        local cd = auraFrame.cd
        if pos == "none" then
            if cd and cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(true)
            end
            return
        end
        if cd and cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(false)
        end
        SetFSFont(durText, cfg.size, "OUTLINE, SLUG")
        durText:SetTextColor(cfg.color.r, cfg.color.g, cfg.color.b, 1)
        durText:ClearAllPoints()
        if pos == "center" then
            durText:SetPoint("CENTER", auraFrame, "CENTER", cfg.x, cfg.y)
            durText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(durText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3 + cfg.x, 4 + cfg.y)
            durText:SetJustifyH("RIGHT")
        elseif pos == "bottomleft" then
            PP.Point(durText, "BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + cfg.x, -4 + cfg.y)
            durText:SetJustifyH("LEFT")
        elseif pos == "bottomright" then
            PP.Point(durText, "BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + cfg.x, -4 + cfg.y)
            durText:SetJustifyH("RIGHT")
        else
            PP.Point(durText, "TOPLEFT", auraFrame, "TOPLEFT", -3 + cfg.x, 4 + cfg.y)
            durText:SetJustifyH("LEFT")
        end
    end
    local function ApplyStackPosition(countText, auraFrame, pos)
        if pos == "none" then
            countText:Hide()
            return
        end
        countText:Show()
        countText:ClearAllPoints()
        if pos == "center" then
            countText:SetPoint("CENTER", auraFrame, "CENTER", auraStackX, auraStackY)
            countText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(countText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3 + auraStackX, 4 + auraStackY)
            countText:SetJustifyH("RIGHT")
        elseif pos == "bottomleft" then
            PP.Point(countText, "BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + auraStackX, -4 + auraStackY)
            countText:SetJustifyH("LEFT")
        elseif pos == "topleft" then
            PP.Point(countText, "TOPLEFT", auraFrame, "TOPLEFT", -3 + auraStackX, 4 + auraStackY)
            countText:SetJustifyH("LEFT")
        else
            PP.Point(countText, "BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + auraStackX, -4 + auraStackY)
            countText:SetJustifyH("RIGHT")
        end
    end
    for i = 1, #self.debuffs do
        if self.debuffs[i] and self.debuffs[i].cd and self.debuffs[i].cd.text then
            SetFSFont(self.debuffs[i].cd.text, debuffDur.size, "OUTLINE, SLUG")
            self.debuffs[i].cd.text:SetTextColor(debuffDur.color.r, debuffDur.color.g, debuffDur.color.b, 1)
            ApplyTimerPosition(self.debuffs[i].cd.text, self.debuffs[i], debuffTPos, debuffDur)
        end
        if self.debuffs[i] and self.debuffs[i].count then
            SetFSFont(self.debuffs[i].count, auraStackSize, "OUTLINE, SLUG")
            self.debuffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
            ApplyStackPosition(self.debuffs[i].count, self.debuffs[i], auraStackPos)
        end
    end
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    local debuffCrop = ns.GetAuraCrop("debuffs")
    local buffCrop = ns.GetAuraCrop("buffs")
    local ccCrop = ns.GetAuraCrop("ccs")
    local debuffH = ns.GetAuraCropHeight(debuffCrop, debuffSz)
    local buffH = ns.GetAuraCropHeight(buffCrop, buffSz)
    local ccH = ns.GetAuraCropHeight(ccCrop, ccSz)
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    for i = 1, #self.debuffs do
        ns.ApplyAuraSlotCrop(self.debuffs[i], debuffCrop, debuffSz)
        ns.ApplyFrameIconBorder(self.debuffs[i], ns.GetIconBorderEnabled("debuffs"), true)
    end
    for i = 1, 4 do
        ns.ApplyAuraSlotCrop(self.buffs[i], buffCrop, buffSz)
        ns.ApplyFrameIconBorder(self.buffs[i], ns.GetIconBorderEnabled("buffs"), true)
        if self.buffs[i].cd and self.buffs[i].cd.text then
            SetFSFont(self.buffs[i].cd.text, buffDur.size, "OUTLINE, SLUG")
            self.buffs[i].cd.text:SetTextColor(buffDur.color.r, buffDur.color.g, buffDur.color.b, 1)
            ApplyTimerPosition(self.buffs[i].cd.text, self.buffs[i], buffTPos, buffDur)
        end
        if self.buffs[i].count then
            SetFSFont(self.buffs[i].count, auraStackSize, "OUTLINE, SLUG")
            self.buffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
            ApplyStackPosition(self.buffs[i].count, self.buffs[i], auraStackPos)
        end
    end
    PositionAuraSlot(self.buffs, 4, buffSlot, self, buffSz, buffH, GetAuraSpacing("buffs"), GetAuraSlotOffsets("buffSlot"))
    for i = 1, 2 do
        ns.ApplyAuraSlotCrop(self.cc[i], ccCrop, ccSz)
        ns.ApplyFrameIconBorder(self.cc[i], ns.GetIconBorderEnabled("ccs"), true)
        if self.cc[i].cd and self.cc[i].cd.text then
            SetFSFont(self.cc[i].cd.text, ccDur.size, "OUTLINE, SLUG")
            self.cc[i].cd.text:SetTextColor(ccDur.color.r, ccDur.color.g, ccDur.color.b, 1)
            ApplyTimerPosition(self.cc[i].cd.text, self.cc[i], ccTPos, ccDur)
        end
    end
    PositionAuraSlot(self.cc, 2, ccSlot, self, ccSz, ccH, GetAuraSpacing("ccs"), GetAuraSlotOffsets("ccSlot"))
    if self.absorbForward then
        self.absorbForward:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    end
    if self.absorbOverflow then
        self.absorbOverflow:SetHeight(GetHealthBarHeight())
    end
    ApplyHealthBarTexture(self)
    ns.ApplyCastBarTexture(self)
    ns.ApplyAbsorbStyle(self)
    self:ApplyBorder()
    self:ApplyBorderColor()
    if self.ApplyCastBorder then self:ApplyCastBorder() end
    if self.ApplyCastBorderColor then self:ApplyCastBorderColor() end
    self:ApplyHealthTextAppearance()
    if ns.RefreshCastOverlay then ns.RefreshCastOverlay(self) end
    -- Re-sync the cast-bar wrap LAST, after normal borders and cast-overlay lift are
    -- re-applied: for a wrapped plate this re-hides the borders ApplyBorder/ApplyCastBorder
    -- just re-showed (no double border). Pure no-op unless enabled or wrapped.
    if self.UpdateBorderWrap and (self._wrapActive or ns.GetWrapBorderCastbar()) then
        self:UpdateBorderWrap()
    end
    ns.ApplySlotStrata(self)
end

-- PERF: health text font/position/color + cached slot assignments. Called from ApplyAppearance
-- (settings change/fresh plate), NEVER per health tick; UpdateHealthValues only rewrites text
-- content via the cache.
function NameplateFrame:ApplyHealthTextAppearance()
    self.hpText:Hide()
    self.hpNumber:Hide()
    if self.levelText then self.levelText:Hide() end
    -- Slot assignments may change element kinds: drop the value memo so the
    -- next UpdateHealthValues rewrites every slot's content.
    self._hpTxtPct, self._hpTxtCur = nil, nil
    if not self._cachedHealthSlots then
        self._cachedHealthSlots = { _count = 0 }
    end
    local ca = self._cachedHealthSlots
    -- Slot kinds may change: re-derive the lazily-computed number/combo flag.
    ca._anyNum = nil
    local ci = 0

    for si = 1, #HP_BAR_SLOTS do
        local slot = HP_BAR_SLOTS[si]
        local element = GetTextSlot(slot.key)
        local txOff, tyOff = GetTextSlotOffsets(slot.key)
        local slotFontSz = GetTextSlotSize(slot.key)
        local sr, sg, sb = GetTextSlotColor(slot.key)
        local slotStrata = (p and p[slot.key .. "Strata"]) or "MEDIUM"
        if element == "healthPercent" or element == "healthPercentNoSign" then
            local fs = self.hpText
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            fs:ClearAllPoints()
            if slot.anchor == "CENTER" then
                fs:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            fs:SetJustifyH(slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
        elseif element == "healthNumber" then
            local fs = self.hpNumber
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            fs:ClearAllPoints()
            if slot.anchor == "CENTER" then
                fs:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            fs:SetJustifyH(slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
        elseif IsComboHealthText(element) then
            local fs = self.hpText
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            fs:ClearAllPoints()
            if slot.anchor == "CENTER" then
                fs:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            fs:SetJustifyH(slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            fs:Show()
            ci = ci + 1
            if not ca[ci] then ca[ci] = {} end
            ca[ci].element = element
            ca[ci].fs = fs
            ca[ci].slotKey = slot.key
        elseif element == "level" then
            -- Standalone level: own FontString, NOT in the health slot cache (content is
            -- static per unit -- written here and by UpdateName on acquire, never on health
            -- ticks). Width/wrap applied inline since the cache loop below skips it.
            local fs = self.levelText
            fs:SetParent(ns.SlotTextHost(self, slot.key, slotStrata))
            SetFSFont(fs, slotFontSz, GetNPOutline())
            fs:ClearAllPoints()
            if slot.anchor == "CENTER" then
                fs:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(fs, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            fs:SetJustifyH(slot.anchor)
            fs:SetTextColor(sr, sg, sb, 1)
            if self.unit then fs:SetText(ns.GetUnitLevelText(self.unit)) end
            local lwpct = (p and p[slot.key .. "WidthPct"]) or 100
            fs:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
            local lwrap = (p and p[slot.key .. "Wrap"]) and true or false
            fs:SetWordWrap(lwrap)
            fs:SetMaxLines(lwrap and 2 or 1)
            fs:Show()
        end
    end

    -- Top slot health text
    local topElement = GetTextSlot("textSlotTop")
    if topElement == "healthPercent" or topElement == "healthPercentNoSign" or topElement == "healthNumber"
       or IsComboHealthText(topElement) then
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fs
        if topElement == "healthNumber" then
            fs = self.hpNumber
        else
            fs = self.hpText
        end
        SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(ns.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        fs:Show()
        ci = ci + 1
        if not ca[ci] then ca[ci] = {} end
        ca[ci].element = topElement
        ca[ci].fs = fs
        ca[ci].slotKey = "textSlotTop"
    elseif topElement == "level" then
        -- Standalone level in the top slot: same shape as the health block
        -- above, on levelText, no cache entry (static content).
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fs = self.levelText
        SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(ns.SlotTextHost(self, "textSlotTop", (p and p.textSlotTopStrata) or "MEDIUM"))
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        if self.unit then fs:SetText(ns.GetUnitLevelText(self.unit)) end
        local lwpct = (p and p.textSlotTopWidthPct) or 100
        fs:SetWidth(lwpct < 100 and (GetHealthBarWidth() * lwpct / 100) or 0)
        local lwrap = (p and p.textSlotTopWrap) and true or false
        fs:SetWordWrap(lwrap)
        fs:SetMaxLines(lwrap and 2 or 1)
        fs:Show()
    end
    ca._count = ci
    -- Per-slot health % decimal preference, resolved in this rare appearance pass and cached
    -- per entry + an _anyDecimal flag, so the per-tick render in UpdateHealthValues stays lean.
    local barW = GetHealthBarWidth()
    local anyDec = false
    for i = 1, ci do
        local e = ca[i]
        local el = e.element
        if el == "healthPercent" or el == "healthPercentNoSign"
           or IsComboHealthText(el) then
            local dec = (p and e.slotKey and p[e.slotKey .. "PctDecimal"]) and true or false
            e.pctDecimal = dec
            if dec then anyDec = true end
        else
            e.pctDecimal = false
        end
        -- Per-slot Width % of the health bar + Wrap. SetWidth/SetWordWrap re-flow the
        -- FontString themselves (only SetJustifyH needs ReflowFontString), and
        -- UpdateHealthValues re-sets text on the same SetUnit pass, so no reflow here. Default
        -- 100 = unconstrained (SetWidth 0 = auto-size): a width box on a single-point-anchored
        -- FontString ignores SetJustifyH and would re-centre a right/left value, so only box
        -- it when narrowed.
        local wpct = (p and e.slotKey and p[e.slotKey .. "WidthPct"]) or 100
        e.fs:SetWidth(wpct < 100 and (barW * wpct / 100) or 0)
        local wrap = false
        if p and e.slotKey and p[e.slotKey .. "Wrap"] ~= nil then wrap = p[e.slotKey .. "Wrap"] end
        e.fs:SetWordWrap(wrap)
        e.fs:SetMaxLines(wrap and 2 or 1)
    end
    ca._anyDecimal = anyDec
end

function NameplateFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    self:SetPoint("CENTER", nameplate, "CENTER", 0, GetHitboxYShift())
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()
    -- Recycled/fresh plate: forget any prior eased scale so the first ApplyScale snaps instead of growing in from a stale one.
    self._curScale = nil
    ns._scaleAnim[self] = nil
    if ns._hitboxOverlayShown or self.hitboxOverlay then ns._ApplyHitboxOverlay(self) end
    -- Apply static appearance only when stale (settings changed or fresh pool plate).
    if self._appearanceGen ~= ns._npAppearanceGen then
        self:ApplyAppearance()
        self._appearanceGen = ns._npAppearanceGen
    end
    HideBlizzardFrame(nameplate, unit)
    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    -- Attach a pooled aura-container bundle for this unit.
    if ns.NPC_AttachPlate then ns.NPC_AttachPlate(self, unit) end
    -- Non-Target Opacity (zero cost while off: one numeric compare).
    if ns._ntAlpha < 1 then ns.NT_Apply(self) end
    -- Execute glow is per-spawn state, not appearance: ApplyAppearance is generation-cached
    -- (skipped on recycled plates) and the threshold watcher only reaches plates active at flip
    -- time, so a plate pooled during a no-execute window would return glowless. Re-assert.
    ns.ApplyLowHpGlow(self)
    -- Critical: health bar must display immediately
    self:UpdateHealth()
    -- PERF: defer non-critical work 1 frame. Stacking bounds, name, cast bar, classification,
    -- raid icon, target glow, mouseover -- all imperceptible 1 frame late. Cuts ~40% off spike.
    self._castDirtyFull = true
    if not self._deferredSetupCB then
        self._deferredSetupCB = function()
            if not self.unit then return end
            local np = self.nameplate
            -- Stacking bounds
            if np and np.SetStackingBoundsFrame then
                if not self._stackBounds then
                    self._stackBounds = CreateFrame("Frame", nil, np)
                    -- Load-bearing: SetStackingBoundsFrame reads this frame's rendered bounds
                    -- (union of its regions), NOT its SetSize. Without a full-size region the
                    -- bounds rect is empty and plates stop stacking. Alpha 0 so it never shows.
                    local tex = self._stackBounds:CreateTexture(nil, "BACKGROUND")
                    tex:SetColorTexture(1, 0, 0, 0)
                    tex:SetAllPoints(self._stackBounds)
                end
                self._stackBounds:SetParent(np)
                self._stackBounds:ClearAllPoints()
                local barH = GetHealthBarHeight()
                local castH2 = GetCastBarHeight()
                local nameGap = 4 + GetEnemyNameTextSize()
                local totalH = nameGap + barH + castH2
                local scale = GetStackSpacingScale() / 100
                self._stackBounds:SetPoint("CENTER", np, "CENTER", 0, GetNameplateYOffset())
                self._stackBounds:SetSize(GetHealthBarWidth(), totalH * scale)
                self._stackBounds:Show()
                np:SetStackingBoundsFrame(self._stackBounds)
            end
            -- Focus cast height override
            if UnitIsUnit(self.unit, "focus") then
                local pct = GetFocusCastHeight()
                if pct ~= 100 then
                    local castH = math.floor(GetCastBarHeight() * pct / 100 + 0.5)
                    ns.LayoutCastBar(self, ns.GetHealthBarWidth(), castH)
                    ns.LayoutCastIcon(self, castH)
                    self.castSpark:SetHeight(castH)
                    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
                end
            end
            -- Cast target color
            local useClassColor = defaults.castTargetClassColor
            if p and p.castTargetClassColor ~= nil then useClassColor = p.castTargetClassColor end
            if useClassColor then
                local appliedCTC = false
                local classToken
                if UnitSpellTargetClass then
                    classToken = UnitSpellTargetClass(self.unit)
                end
                -- classToken may be SECRET: type() is the safe nil check
                if type(classToken) == "nil" then
                    local targetUnit = self.unit .. "target"
                    if UnitIsPlayer(targetUnit) then
                        classToken = UnitClassBase(targetUnit)
                    end
                end
                if type(classToken) ~= "nil" and C_ClassColor then
                    local c = C_ClassColor.GetClassColor(classToken)
                    if c then
                        self.castTarget:SetTextColor(c:GetRGB())
                        appliedCTC = true
                    end
                end
                if not appliedCTC then
                    self.castTarget:SetTextColor(1, 1, 1, 1)
                end
            else
                local ctc = (p and p.castTargetColor) or defaults.castTargetColor
                self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            end
            self:UpdateName()
            self:UpdateClassification()
            self:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
            self:ApplyTarget()
            self:ApplyMouseover()
            self:UpdateCast()
            -- Mirrored class colour only: on a fresh plate Blizzard's own SetUnit may not have
            -- run yet, in which case the same-unit guard refused to mirror and the plate is
            -- wearing the plain fallback. Retry once a frame later so it does not sit there
            -- until the unit's next health event.
            if self._mirrorPending then self:UpdateHealthColor() end
        end
    end
    C_Timer.After(0, self._deferredSetupCB)
end
function NameplateFrame:ClearUnit()
    self:UnregisterAllEvents()

    -- Non-Target Opacity: released pool frames always go back at full
    -- alpha (nil _ntCurAlpha = never faded, keeps this a no-op).
    if self._ntCurAlpha and self._ntCurAlpha < 1 then
        self:SetAlpha(1)
    end
    self._ntCurAlpha = nil
    self._oorCurAlpha = nil

    if self.isCasting then
        self.isCasting = false
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end

    self.name:SetText("")
    for i = 1, 2 do
        local slot = self.cc[i]
        if slot.cd then
            if slot.cd.SetDrawSwipe then slot.cd:SetDrawSwipe(false) end
            if slot.cd.Clear then slot.cd:Clear() else slot.cd:SetCooldown(0, 0) end
            slot.cd:Hide()
        end
        RawSetTex(slot.icon, nil)
        slot:Hide()
        slot._auraId = nil
    end
    for i = 1, #self.debuffs do
        local dSlot = self.debuffs[i]
        if dSlot.cd then
            if dSlot.cd.SetDrawSwipe then dSlot.cd:SetDrawSwipe(false) end
            if dSlot.cd.Clear then dSlot.cd:Clear() else dSlot.cd:SetCooldown(0, 0) end
            dSlot.cd:Hide()
        end
        RawSetTex(dSlot.icon, nil)
        dSlot:Hide()
        dSlot._durationObj = nil
        dSlot._auraId = nil
    end
    for i = 1, 4 do
        local bSlot = self.buffs[i]
        if bSlot.cd then
            if bSlot.cd.SetDrawSwipe then bSlot.cd:SetDrawSwipe(false) end
            if bSlot.cd.Clear then bSlot.cd:Clear() else bSlot.cd:SetCooldown(0, 0) end
            bSlot.cd:Hide()
        end
        RawSetTex(bSlot.icon, nil)
        bSlot:Hide()
        if bSlot.dispelGlow and bSlot.dispelGlow.active then
            ns.StopDispelGlow(bSlot)
        end
        bSlot._auraId = nil
    end
    -- Release this plate's aura-container bundle back to the pool.
    if ns.NPC_DetachPlate then ns.NPC_DetachPlate(self) end
    self.unit = nil
    self.nameplate = nil
    self._absorbHidden = nil
    self._maxHPValid = nil
    self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
    self._mirrorPending = nil
    -- Health-text value memo (UpdateHealthValues): a recycled plate must
    -- always write its first values, never skip against the old unit's.
    self._hpTxtPct, self._hpTxtCur = nil, nil
    self._ovFocShown, self._ovTgtShown = nil, nil
    self._focusLetterShown = nil
    self._kickIsChannel = nil
    self._kickIsEmpowered = nil
    self._kickGeoDirty = nil
    self._castTex = nil
    self._castLockout = nil
    self._nameRaidMarkerShown = nil
    self.cast:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.isCasting = false
    self._castFallback = nil
    _fallbackPlates[self] = nil
    self._kickProtected = nil
    self._castImportant = false
    self:HideKickTick()
    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end
    self._interrupted = nil
    if self.glow then self.glow:Hide() end
    if self.targetHighlight then self.targetHighlight:Hide() end
    ns.HideHoverEffect(self)
    if self.nameRaidFrame then self.nameRaidFrame:Hide() end
    self.raidFrame:Hide()
    self.classFrame:Hide()
    if self.classText then self.classText:Hide() end
    if self.focusLetter then self.focusLetter:Hide() end
    if self.leftArrow then self.leftArrow:Hide() end
    if self.rightArrow then self.rightArrow:Hide() end
    HideClassPowerOnPlate(self)
    self.absorb:Hide()
    if self.absorbForward then
        self.absorbForward:Hide()
    end
    if self.absorbOverflow then
        self.absorbOverflow:Hide()
        self.absorbOverflow:SetWidth(0)
    end
    if self.absorbOverflowDivider then
        self.absorbOverflowDivider:Hide()
    end
    self:Hide()
    self:SetScale(1)
    self._curScale = nil
    ns._scaleAnim[self] = nil
    self:SetParent(UIParent)
    self:ClearAllPoints()
    -- Detach stacking bounds from the old nameplate so it doesn't
    -- confuse the stacking engine when the nameplate is recycled.
    if self._stackBounds then
        self._stackBounds:ClearAllPoints()
        self._stackBounds:SetParent(self)
        self._stackBounds:Hide()
    end
end
function NameplateFrame:UpdateHealthValues()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            -- Token swap: this plate now represents a DIFFERENT mob. Any in-flight cast display
            -- belongs to the old unit: tear it down and re-evaluate. The cooldown watcher does
            -- not re-read cast info per event, so this is the swap's only cast-state self-heal.
            if self.isCasting then
                if self._castFallback then
                    self._castFallback = nil
                    _fallbackPlates[self] = nil
                    fallbackCastCount = fallbackCastCount - 1
                    if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
                end
                NotifyCastEnded(self)
                self.isCasting = false
                self:HideKickTick()
                self:ClearImportantCastGlow()
                if not self._interrupted then self.cast:Hide() end
                self.castTimer:SetText("")
                self._castTex = nil
            end
            self.unit = actualUnit
            unit = actualUnit
            -- New occupant: its absorb state is unknown. Nil the lean-gate flag
            -- so this pass takes the full absorb path and re-seeds it; the
            -- cached max belongs to the old unit, drop it too.
            self._absorbHidden = nil
            self._maxHPValid = nil
            -- Only refresh auras for the lockout when one was actually active
            -- (zero cost when the Cast Lockout feature is off / no lockout).
            if self._castLockout then
                self._castLockout = nil
                if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
            end
            self:UpdateName()
            self._castDirtyFull = true
            self:UpdateCast()
            -- Unit changed without an add/remove cycle: the old occupant's
            -- target/hover border styling would otherwise stick to the plate.
            -- The one-shot flags MUST stay set going in -- ClearHoverExtras
            -- early-outs on _hoverFxOn and ApplyTarget's size restore is
            -- gated on _targetBorderSized; clearing them first skips both
            -- restores. ClearHoverExtras restores hover size then re-runs
            -- ApplyTarget; the direct call covers its no-hover-fx early-out
            -- and re-evaluates target state for the new unit.
            if ns.ClearHoverExtras then ns.ClearHoverExtras(self) end
            self:ApplyTarget()
        end
    end

    local curHealth, maxHealth, absorbAmt, maxWithAbsorbs

    -- LEAN PATH: the last full pass proved this unit carries no absorb, and no
    -- UNIT_ABSORB_AMOUNT_CHANGED edge has fired since (that handler arms
    -- _absorbEdge; ClearUnit and both token-swap sites nil _absorbHidden so a
    -- new occupant always takes the full pass). The gate reads only OUR OWN
    -- booleans -- never unit state -- so combat secrecy cannot poison it.
    -- Shieldless units, the vast majority of health events, pay two unit reads
    -- and two bar pushes here instead of the calculator fetch + absorb branch.
    if self._absorbHidden and not self._absorbEdge then
        curHealth = UnitHealth(unit)
        -- Bar bounds ride UNIT_MAXHEALTH: the cached max (possibly secret --
        -- stored but never compared; _maxHPValid is OUR plain flag) pushes
        -- once on change/seed/absorb-teardown instead of every paint. The
        -- steady-state health paint is one read + one SetValue, matching
        -- Blizzard's own per-event bar cost.
        if not self._maxHPValid then
            maxHealth = UnitHealthMax(unit)
            self._maxHP = maxHealth
            self._maxHPValid = true
            self.health:SetMinMaxValues(0, maxHealth)
        else
            maxHealth = self._maxHP
        end
        self.health:SetValue(curHealth)
    else
    self._absorbEdge = nil

    if self.hpCalculator and self.hpCalculator.GetMaximumHealth and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)

        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        curHealth = self.hpCalculator:GetCurrentHealth()
        maxHealth = self.hpCalculator:GetMaximumHealth()
        absorbAmt = self.hpCalculator:GetDamageAbsorbs()
        -- maxWithAbsorbs is fetched LAZILY in the secret-absorb branch below (its only
        -- consumer): the dominant no-absorb path must not pay two mode swaps + a getter.
    else
        curHealth = UnitHealth(unit)
        maxHealth = UnitHealthMax(unit)
        absorbAmt = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
        maxWithAbsorbs = maxHealth
    end

    local absorbIsSecret = issecretvalue and issecretvalue(absorbAmt)

    -- PERF: skip ALL absorb work when absorbs are 0 and were already 0 (most M+ mobs have none).
    local absorbZero = not absorbIsSecret and (not absorbAmt or absorbAmt <= 0)
    if absorbZero and self._absorbHidden then
        -- Fast path: absorbs were and still are zero
        self.health:SetMinMaxValues(0, maxHealth)
        self.health:SetValue(curHealth)
    elseif absorbIsSecret then
        self._absorbHidden = false
        if maxWithAbsorbs == nil and self.hpCalculator and self.hpCalculator.GetMaximumHealth then
            self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            maxWithAbsorbs = self.hpCalculator:GetMaximumHealth()
            self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        end
        self.absorb:ClearAllPoints()
        if self.absorbForward then self.absorbForward:ClearAllPoints() end
        self.health:SetMinMaxValues(0, maxWithAbsorbs or maxHealth)
        self.health:SetValue(curHealth)
        self.absorb:SetMinMaxValues(0, maxWithAbsorbs or maxHealth)
        self.absorb:SetReverseFill(false)
        self.absorb:SetPoint("TOPLEFT", self.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        self.absorb:SetPoint("BOTTOMLEFT", self.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        self.absorb:SetValue(absorbAmt)
        self.absorb:Show()
        if self.absorbForward then self.absorbForward:Hide() end
        if self.absorbOverflow then self.absorbOverflow:Hide(); self.absorbOverflow:SetWidth(0) end
        if self.absorbOverflowDivider then self.absorbOverflowDivider:Hide() end
    else
        self.absorb:ClearAllPoints()
        if self.absorbForward then self.absorbForward:ClearAllPoints() end
        self.health:SetMinMaxValues(0, maxHealth)
        self.health:SetValue(curHealth)
        self.absorb:SetMinMaxValues(0, maxHealth)
        if self.absorbForward then self.absorbForward:SetMinMaxValues(0, maxHealth) end

        local absorbValue = absorbAmt or 0
        if absorbValue <= 0 then
            self._absorbHidden = true
            -- Entering the lean path: the bar bounds may still be an absorb-
            -- extended max from the secret branch -- force one clean re-push.
            self._maxHPValid = nil
            self.absorb:Hide()
            if self.absorbForward then self.absorbForward:Hide() end
            if self.absorbOverflow then self.absorbOverflow:Hide(); self.absorbOverflow:SetWidth(0) end
            if self.absorbOverflowDivider then self.absorbOverflowDivider:Hide() end
        else
            self._absorbHidden = false
            local missing = maxHealth - curHealth
            if missing < 0 then missing = 0 end
            local forwardAbsorb = math.min(absorbValue, missing)
            local remainingAbsorb = absorbValue - forwardAbsorb
            if remainingAbsorb < 0 then remainingAbsorb = 0 end
            local backfillAbsorb = math.min(remainingAbsorb, curHealth or 0)
            local overflowAbsorb = remainingAbsorb - backfillAbsorb
            if overflowAbsorb < 0 then overflowAbsorb = 0 end

            if self.absorbForward then
                self.absorbForward:SetReverseFill(false)
                self.absorbForward:SetPoint("TOPLEFT", self.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                self.absorbForward:SetPoint("BOTTOMLEFT", self.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                self.absorbForward:SetValue(forwardAbsorb)
                if forwardAbsorb > 0 then self.absorbForward:Show() else self.absorbForward:Hide() end
            end
            self.absorb:SetReverseFill(true)
            self.absorb:SetPoint("TOPRIGHT", self.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            self.absorb:SetPoint("BOTTOMRIGHT", self.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            self.absorb:SetValue(backfillAbsorb)
            if backfillAbsorb > 0 then self.absorb:Show() else self.absorb:Hide() end

            if self.absorbOverflow then
                self.absorbOverflow:SetMinMaxValues(0, maxHealth)
                self.absorbOverflow:SetValue(overflowAbsorb)
                if overflowAbsorb > 0 then
                    self.absorbOverflow:Show()
                    self.absorbOverflow:SetWidth(self.health:GetWidth())
                    if self.absorbOverflowDivider then self.absorbOverflowDivider:Show() end
                else
                    self.absorbOverflow:Hide()
                    self.absorbOverflow:SetWidth(0)
                    if self.absorbOverflowDivider then self.absorbOverflowDivider:Hide() end
                end
            elseif self.absorbOverflowDivider then
                self.absorbOverflowDivider:Hide()
            end
        end
    end
    end -- lean-gate else (full absorb path)

    -- Hash line positioning (target only). PERF: uses cached _isTarget, not UnitIsUnit per tick.
    local hlEnabled = (p and p.hashLineEnabled)
    local hlPct = (p and p.hashLinePercent) or defaults.hashLinePercent
    if hlEnabled and hlPct and hlPct > 0 and self._isTarget then
        -- Input-gated: anchor/color pushes only depend on bar width and settings (bar width is
        -- our frame -- never secret), re-pushed only when an input moves.
        local barW = self.health:GetWidth()
        local hlc = (p and p.hashLineColor) or defaults.hashLineColor
        if self._hlW ~= barW or self._hlPct ~= hlPct
           or self._hlR ~= hlc.r or self._hlG ~= hlc.g or self._hlB ~= hlc.b then
            self._hlW = barW; self._hlPct = hlPct
            self._hlR, self._hlG, self._hlB = hlc.r, hlc.g, hlc.b
            local xPos = barW * (hlPct / 100)
            self.hashLine:ClearAllPoints()
            self.hashLine:SetPoint("TOP", self.health, "TOPLEFT", xPos, 0)
            self.hashLine:SetPoint("BOTTOM", self.health, "BOTTOMLEFT", xPos, 0)
            self.hashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
        end
        self.hashLine:Show()
        self._hashHidden = nil
    else
        -- Own-flag gate: non-target plates were paying a Hide() every paint.
        -- nil flag (fresh/recycled plate, unknown widget state) hides once.
        if not self._hashHidden then
            self.hashLine:Hide()
            self._hashHidden = true
        end
    end

    -- PERF: text content only -- font/position/color live in ApplyHealthTextAppearance. Runs
    -- on every UNIT_HEALTH tick: stay lean.
    local ca = self._cachedHealthSlots
    if ca and ca._count > 0 then
        -- Value memo: health ticks land on the same DISPLAYED values constantly, and
        -- string.format + SetText churn is the hottest allocation source on plates. Keys MUST
        -- be quantized to display granularity -- the raw percent is a FLOAT that moves every
        -- tick, so a raw key never repeats and the memo never hits. Raw health gates the skip
        -- ONLY when a slot renders it (number/combo): a percent-only layout then keeps its hits
        -- through raw churn. Secret values cannot be compared or floored: any secret input
        -- fails open to writing and clears its key.
        local isSec = issecretvalue
        local dead = UnitIsDeadOrGhost(unit)
        local anyDec = ca._anyDecimal
        local pctVal
        if not dead and UnitHealthPercent then
            pctVal = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
        end
        local pctKey
        if dead then
            pctKey = -1
        elseif pctVal ~= nil and not (isSec and isSec(pctVal)) then
            pctKey = anyDec and math.floor(pctVal * 10 + 0.5) or math.floor(pctVal)
        end
        local anyNum = ca._anyNum
        if anyNum == nil then
            anyNum = false
            local anyNoSign = false
            for si = 1, ca._count do
                local entry = ca[si]
                local el = entry.element
                -- Stamp the combo classification once per appearance build:
                -- the write loop below runs per paint and must not pay a
                -- classification call per slot per paint.
                entry.combo = IsComboHealthText(el) or false
                if el == "healthNumber" or entry.combo then anyNum = true end
                if el == "healthPercentNoSign" then anyNoSign = true end
            end
            ca._anyNum = anyNum
            ca._anyNoSign = anyNoSign
        end
        local hpKey
        if not anyNum then
            hpKey = 0
        elseif dead then
            hpKey = -1
        elseif curHealth ~= nil and not (isSec and isSec(curHealth)) then
            hpKey = curHealth
        end
        local skipText = pctKey ~= nil and hpKey ~= nil
            and self._hpTxtPct == pctKey and self._hpTxtCur == hpKey
        if not skipText then
        self._hpTxtPct = pctKey
        self._hpTxtCur = hpKey
        local pctText, pctNoSignText, numText
        local pctTextDec, pctNoSignTextDec
        local anyDec = ca._anyDecimal
        if dead then
            pctText = "0%"
            pctNoSignText = "0"
            numText = "0"
            if anyDec then pctTextDec = "0.0%"; pctNoSignTextDec = "0.0" end
        elseif pctVal ~= nil then
            pctText = string.format("%d%%", pctVal)
            -- No-sign variant only when a slot actually renders it.
            if ca._anyNoSign then pctNoSignText = string.format("%d", pctVal) end
            numText = AbbreviateNumbers(curHealth)
            -- Decimal variants computed only when at least one slot opts in.
            if anyDec then
                pctTextDec = string.format("%.1f%%", pctVal)
                if ca._anyNoSign then pctNoSignTextDec = string.format("%.1f", pctVal) end
            end
        else
            pctText = ""
            pctNoSignText = ""
            numText = ""
            if anyDec then pctTextDec = ""; pctNoSignTextDec = "" end
        end
        for si = 1, ca._count do
            local entry = ca[si]
            local el = entry.element
            local fs = entry.fs
            if el == "healthPercent" then
                fs:SetText(entry.pctDecimal and pctTextDec or pctText)
            elseif el == "healthPercentNoSign" then
                fs:SetText(entry.pctDecimal and pctNoSignTextDec or pctNoSignText)
            elseif el == "healthNumber" then
                fs:SetText(numText)
            elseif entry.combo then
                SetCombinedHealthText(fs, el, entry.pctDecimal and pctTextDec or pctText, numText)
            end
        end
        end -- skipText
    end

    -- Execute Pulse Glow gate: evaluate the execute-window curve C-side and feed the color
    -- straight into the glow textures (alpha 1 below threshold, 0 above -- never branched on in
    -- Lua). Parent frame's pulse multiplies on top. No-execute specs never build textures.
    local lg = self.lowHpGlowTextures
    if lg and self.lowHpGlowFrame:IsShown() then
        local curve = ns.GetLowHpGlowCurve()
        if curve then
            if UnitIsDeadOrGhost(unit) then
                for i = 1, #lg do lg[i]:SetVertexColor(0, 0, 0, 1) end
            else
                local ok, col = pcall(UnitHealthPercent, unit, true, curve)
                if ok and col and col.GetRGBA then
                    local r, g, b, a = col:GetRGBA()
                    for i = 1, #lg do lg[i]:SetVertexColor(r, g, b, a) end
                end
            end
        end
    end
end
function NameplateFrame:UpdateHealthColor()
    local unit = self.unit
    if not unit then return end
    -- Skip-if-unchanged: GetReactionColor returns plain profile-sourced numbers (every return
    -- path verified non-secret). Threat events fire constantly with an unchanged result, so
    -- compare against the last applied values and skip the setter. Cache nil'd in ClearUnit.
    local hr, hg, hb = GetReactionColor(unit)
    -- Enemy player whose class token was redacted (instanced PvP): paint the bar from
    -- Blizzard's plate instead. A secret cannot go through the skip-if-unchanged compare, so
    -- this re-reads and re-applies every pass rather than latching -- a latch would freeze the
    -- bar on a stale colour when Blizzard's changes (a disconnect greys it, the CVar is
    -- toggled mid-match). Two C calls against the dozen GetReactionColor already spent, on
    -- the few plates that take this path. hr/hg/hb stay the plain fallback for the tints below.
    local mirrored, mr, mg, mb = false
    if ns._reactionMirrorClass then
        mirrored, mr, mg, mb = ns.GetBlizzardBarColor(self)
        -- Wanted to mirror but Blizzard's plate was not on this unit yet: the deferred
        -- setup pass retries. Only ever set on the plates that take this path.
        self._mirrorPending = not mirrored or nil
    else
        self._mirrorPending = nil
    end
    -- Off-tank fold: same shape as mirror -- the folded components can be
    -- SECRET, so they bypass the value compare, never enter the caches, and
    -- reach setters only. hr/hg/hb stay the plain tankNoAggro fallback.
    local folded, fr, fg, fb = false
    if not mirrored and ns._reactionOffTankFold and ns.ComputeOffTankFold then
        local otc = _C("offTankAggro")
        folded, fr, fg, fb = ns.ComputeOffTankFold(unit, hr, hg, hb, otc.r, otc.g, otc.b)
    end
    if mirrored then
        -- Cache invalidated, never written with a secret: the next plain colour must reapply.
        self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
        self.health:SetStatusBarColor(mr, mg, mb)
    elseif folded then
        self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
        self.health:SetStatusBarColor(fr, fg, fb)
    elseif hr ~= self._lastHCr or hg ~= self._lastHCg or hb ~= self._lastHCb then
        self._lastHCr, self._lastHCg, self._lastHCb = hr, hg, hb
        self.health:SetStatusBarColor(hr, hg, hb)
    end
    -- Enemy Name Text "Reaction Color" (EXTRAS toggle): zero cost while off (one field read),
    -- other than the one-time restore below for a plate that was previously colored by this
    -- feature. Piggybacks on this function's existing event-driven calls rather than
    -- registering anything of its own.
    if p and p.enemyNameTextReactionColor then
        local nnr, nng, nnb = GetEnemyNameReactionColor(unit)
        if nnr ~= self._lastNameReactR or nng ~= self._lastNameReactG or nnb ~= self._lastNameReactB then
            self._lastNameReactR, self._lastNameReactG, self._lastNameReactB = nnr, nng, nnb
            self.name:SetTextColor(nnr, nng, nnb, 1)
        end
    elseif self._lastNameReactR then
        -- Toggled off after having been applied to this plate: restore the slot color
        -- directly here rather than depending on ApplyAppearance re-running elsewhere.
        self._lastNameReactR, self._lastNameReactG, self._lastNameReactB = nil, nil, nil
        local nameSlotKey = ns.FindNameSlot()
        if nameSlotKey then
            local nr, ng, nb = GetTextSlotColor(nameSlotKey)
            self.name:SetTextColor(nr, ng, nb, 1)
        end
    end
    -- Near-aggro glow (Non-Tank Threat cog): ns._reactionNearAggro was written
    -- by the GetReactionColor call ABOVE (same decision that picked the color).
    -- Own state cache, so constant same-result threat events are one compare;
    -- feature off = one boolean read on top of that.
    local naGlow = false
    if ns._reactionNearAggro then
        local dbg = p or defaults
        naGlow = dbg.threatNearAggroGlow == true
    end
    if naGlow ~= (self._naGlowOn or false) then
        self._naGlowOn = naGlow
        if naGlow then
            ns.EnsureNearAggroGlow(self)
            self.naGlowFrame:Show()
        elseif self.naGlowFrame then
            self.naGlowFrame:Hide()
        end
    end
    -- Focus overlay: stripe textures on the focus target's health bar (fill clip at full alpha,
    -- bg clip at half). Value-keyed: reapplied only when a component differs from the last
    -- applied state. No Tint keeps the whole pipeline and only swaps the tint source to the
    -- bar's current health color (hr/hg/hb above). NEVER use these overlay textures as the
    -- bar's own fill texture: they are pattern-on-transparent art, so transparent ground
    -- renders as holes and darkens the whole bar.
    local db2 = p or defaults
    local focusTex = db2.focusOverlayTexture or defaults.focusOverlayTexture
    if focusTex ~= "none" and UnitIsUnit(unit, "focus") then
        -- Texture path memoized by texture NAME (no per-call concat); live dropdown changes rebuild it.
        if ns._focusOverlayTexName ~= focusTex then
            ns._focusOverlayTexName = focusTex
            ns._focusOverlayTexPath = ns.ResolveOverlayTexPath(focusTex)
        end
        local texPath = ns._focusOverlayTexPath
        local overlayAlpha = db2.focusOverlayAlpha or defaults.focusOverlayAlpha
        local ocr, ocg, ocb
        -- No Tint means "wear the bar's colour", so on a mirrored plate it has to take the
        -- mirrored values, not the plain fallback -- tinting from hr/hg/hb there would show
        -- the exact mismatch No Tint exists to avoid. Secrets cannot be value-keyed, so
        -- forced re-applies every pass and the cache is left unset (the `or` below
        -- short-circuits before any compare touches them).
        local forced = false
        if NoTintFlag(db2, "focusOverlayNoTint") then
            if mirrored then
                ocr, ocg, ocb, forced = mr, mg, mb, true
            elseif folded then
                ocr, ocg, ocb, forced = fr, fg, fb, true
            else
                ocr, ocg, ocb = hr, hg, hb
            end
        else
            local oc = db2.focusOverlayColor or defaults.focusOverlayColor
            ocr, ocg, ocb = oc.r, oc.g, oc.b
        end
        local bgAlpha = OverlayBgAlpha(db2.focusOverlayFullBgAlpha, overlayAlpha)
        if forced or not self._ovFocShown or self._ovFocTex ~= texPath
            or self._ovFocAlpha ~= overlayAlpha or self._ovFocBgAlpha ~= bgAlpha
            or self._ovFocR ~= ocr or self._ovFocG ~= ocg or self._ovFocB ~= ocb then
            EnsureFocusOverlay(self)
            self._ovFocShown = true
            self._ovFocTex, self._ovFocAlpha = texPath, overlayAlpha
            self._ovFocBgAlpha = bgAlpha
            if forced then
                self._ovFocR, self._ovFocG, self._ovFocB = nil, nil, nil
            else
                self._ovFocR, self._ovFocG, self._ovFocB = ocr, ocg, ocb
            end
            ApplyOverlayGeometry(self.focusOverlayFill, self.focusOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[focusTex] == true)
            self.focusOverlayFill:SetTexture(texPath)
            self.focusOverlayFill:SetAlpha(overlayAlpha)
            self.focusOverlayFill:SetVertexColor(ocr, ocg, ocb)
            self.focusClipFill:Show()
            self.focusOverlayBg:SetTexture(texPath)
            self.focusOverlayBg:SetAlpha(bgAlpha)
            self.focusOverlayBg:SetVertexColor(ocr, ocg, ocb)
            self.focusClipBg:Show()
        end
    elseif self.focusClipFill then
        self._ovFocShown = nil
        self.focusClipFill:Hide()
        self.focusClipBg:Hide()
    end
    -- Focus letter: zero cost when off -- a disabled plate pays two field reads (no call, no
    -- UnitIsUnit, no allocation). _focusLetterShown lets a live letter hide itself when turned off.
    if db2.focusLetterEnabled or self._focusLetterShown then
        ns.ApplyFocusLetter(self, unit, db2)
    end
    -- Target overlay: identical to focus overlay but for current target,
    -- including the No Tint bar-color tint source.
    local targetTex = db2.targetOverlayTexture or defaults.targetOverlayTexture
    if targetTex ~= "none" and UnitIsUnit(unit, "target") then
        if ns._targetOverlayTexName ~= targetTex then
            ns._targetOverlayTexName = targetTex
            ns._targetOverlayTexPath = ns.ResolveOverlayTexPath(targetTex)
        end
        local texPath = ns._targetOverlayTexPath
        local overlayAlpha = db2.targetOverlayAlpha or defaults.targetOverlayAlpha
        local ocr, ocg, ocb
        -- Mirrored plate: same reasoning as the focus overlay above.
        local forced = false
        if NoTintFlag(db2, "targetOverlayNoTint") then
            if mirrored then
                ocr, ocg, ocb, forced = mr, mg, mb, true
            elseif folded then
                ocr, ocg, ocb, forced = fr, fg, fb, true
            else
                ocr, ocg, ocb = hr, hg, hb
            end
        else
            local oc = db2.targetOverlayColor or defaults.targetOverlayColor
            ocr, ocg, ocb = oc.r, oc.g, oc.b
        end
        local bgAlpha = OverlayBgAlpha(db2.targetOverlayFullBgAlpha, overlayAlpha)
        if forced or not self._ovTgtShown or self._ovTgtTex ~= texPath
            or self._ovTgtAlpha ~= overlayAlpha or self._ovTgtBgAlpha ~= bgAlpha
            or self._ovTgtR ~= ocr or self._ovTgtG ~= ocg or self._ovTgtB ~= ocb then
            ns.EnsureTargetOverlay(self)
            self._ovTgtShown = true
            self._ovTgtTex, self._ovTgtAlpha = texPath, overlayAlpha
            self._ovTgtBgAlpha = bgAlpha
            if forced then
                self._ovTgtR, self._ovTgtG, self._ovTgtB = nil, nil, nil
            else
                self._ovTgtR, self._ovTgtG, self._ovTgtB = ocr, ocg, ocb
            end
            ApplyOverlayGeometry(self.targetOverlayFill, self.targetOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[targetTex] == true)
            self.targetOverlayFill:SetTexture(texPath)
            self.targetOverlayFill:SetAlpha(overlayAlpha)
            self.targetOverlayFill:SetVertexColor(ocr, ocg, ocb)
            self.targetClipFill:Show()
            self.targetOverlayBg:SetTexture(texPath)
            self.targetOverlayBg:SetAlpha(bgAlpha)
            self.targetOverlayBg:SetVertexColor(ocr, ocg, ocb)
            self.targetClipBg:Show()
        end
    elseif self.targetClipFill then
        self._ovTgtShown = nil
        self.targetClipFill:Hide()
        self.targetClipBg:Hide()
    end
end
function NameplateFrame:UpdateHealth()
    self:UpdateHealthValues()
    self:UpdateHealthColor()
end
function NameplateFrame:UpdateName()
    local unit = self.unit
    if not unit then return end
    if self.nameplate then
        local actualUnit = self.nameplate.namePlateUnitToken
        if actualUnit and actualUnit ~= unit then
            self.unit = actualUnit
            unit = actualUnit
            -- Occupant changed: nil the absorb lean-gate flag so the next health
            -- paint takes the full absorb path for the new unit; the cached max
            -- belongs to the old unit, drop it too.
            self._absorbHidden = nil
            self._maxHPValid = nil
        end
    end
    -- Standalone level renders on its own FontString and can share the plate with a
    -- name-family slot. Refreshed here (plate acquire/unit swap) so pooled reuse never stales.
    if self.levelText and self.levelText:IsShown() then
        self.levelText:SetText(ns.GetUnitLevelText(unit))
    end
    -- The slotted name-family variant decides what renders: name or a level+name
    -- combo. A nil slot keeps the plain-name write (RefreshNamePosition hides it).
    local el = ns.FindNameSlot()
    el = el and GetTextSlot(el) or "enemyName"
    local name = UnitName(unit)
    if type(name) == "string" then
        ns.SetNameElementText(self.name, el, name, unit)
        if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
    end
end
function NameplateFrame:UpdateClassification()
    if not self.unit then return end
    local slot = GetClassificationSlot()
    local _, iType = GetInstanceInfo()
    local inInstance = (iType == "party" or iType == "raid" or iType == "pvp" or iType == "arena")
    if inInstance then
        -- "Show In Instances" (Rare/Quest Indicator slot cog) lifts the
        -- open-world-only gate.
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if show then inInstance = false end
    end
    if slot == "none" or inInstance then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- Quest mob indicator takes priority over elite/rare. With "Replace Quest Icon with
    -- Objective" on and a clean remaining count cached, draw that number instead of the icon.
    if ns.IsQuestMob and ns.IsQuestMob(self.unit) then
        local objText = (p and p.replaceQuestIconWithObjective == true)
            and ns.GetQuestObjectiveText and ns.GetQuestObjectiveText(self.unit) or nil
        if objText then
            -- classFrame and classText are our own frames, custom keys are safe.
            self.class:Hide()
            if not self.classText then
                self.classText = self.classFrame:CreateFontString(nil, "OVERLAY")
                self.classText:SetPoint("CENTER", self.classFrame, "CENTER", 0, 0)
                self.classText:SetJustifyH("CENTER")
                self.classText:SetJustifyV("MIDDLE")
            end
            local fsz = (p and p.questObjectiveTextSize) or defaults.questObjectiveTextSize
            SetFSFont(self.classText, fsz, GetNPOutline())
            -- SetFormattedText("%s", ...) is the secret-safe text path; the value
            -- was already verified clean (issecretvalue + ^%d+/%d+$) before caching.
            self.classText:SetFormattedText("%s", objText)
            self.classText:Show()
        else
            -- No clean count (quest-giver / percent / secret value) -> icon.
            if self.classText then self.classText:Hide() end
            self.class:Show()
            self.class:SetAtlas("Crosshair_Quest_64")
        end
    else
        if self.classText then self.classText:Hide() end
        self.class:Show()
        local c = UnitClassification(self.unit)
        if c == "elite" or c == "worldboss" then
            self.class:SetAtlas("nameplates-icon-elite-gold")
        elseif c == "rareelite" then
            self.class:SetAtlas("nameplates-icon-elite-silver")
        elseif c == "rare" then
            self.class:SetAtlas("nameplates-icon-rareelite")
        else
            self.classFrame:Hide()
            self:UpdateNameWidth()
            return
        end
    end
    local cpPush = GetClassPowerTopPush(self)
    local cxOff, cyOff = GetAuraSlotOffsets("classification")
    local reSize = GetRareEliteIconSize()
    PP.Size(self.classFrame, reSize, reSize)
    self.classFrame:ClearAllPoints()
    if slot == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.classFrame, "BOTTOM", self.health, "TOP",
            cxOff, debuffY + cpPush + cyOff)
    elseif slot == "left" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local iconPush = (iconSide == "left") and iconRes or 0
        PP.Point(self.classFrame, "RIGHT", self.health, "LEFT",
            -sideOff - iconPush + cxOff, cyOff)
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local iconPush = (iconSide == "right") and iconRes or 0
        PP.Point(self.classFrame, "LEFT", self.health, "RIGHT",
            sideOff + iconPush + cxOff, cyOff)
    elseif slot == "topleft" then
        PP.Point(self.classFrame, "BOTTOMLEFT", self.health, "TOPLEFT", cxOff, 2 + cpPush + cyOff)
    elseif slot == "topright" then
        PP.Point(self.classFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", cxOff, 2 + cpPush + cyOff)
    elseif slot == "bottom" then
        PP.Point(self.classFrame, "TOP", self.cast, "BOTTOM", cxOff, -2 + cyOff)
    end
    self.classFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:UpdateNameWidth()
    local barW = GetHealthBarWidth()
    -- Width % scales the computed (bar-derived) width; 100 = historical behaviour.
    local pct = (p and p.enemyNameWidthPct) or defaults.enemyNameWidthPct
    local nameSlot = ns.FindNameSlot()
    local nameMarkerReserve = self._nameRaidMarkerShown == true
        and (((p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14) + 3) or 0
    if nameSlot == "textSlotTop" then
        -- Above the bar: reserve a fixed slot for the inline raid marker.
        local nameW = barW - nameMarkerReserve
        local rmPos = GetRaidMarkerPos()
        if rmPos ~= "none" and self.raidFrame:IsShown() then
            nameW = nameW - 2 * (GetRaidMarkerSize() - 2) - 7
        end
        local clSlot = GetClassificationSlot()
        if clSlot ~= "none" and self.classFrame:IsShown() then
            nameW = nameW - (GetRareEliteIconSize() + 4)
        end
        PP.Width(self.name, math.max(nameW * pct / 100, 20))
    elseif nameSlot then
        -- Inside the bar: estimate how much space health text occupies in
        -- opposing slots, then give the name everything that remains.
        local usedWidth = 0
        local barKeys = { "textSlotRight", "textSlotLeft", "textSlotCenter" }
        for _, key in ipairs(barKeys) do
            if key ~= nameSlot then
                local el = GetTextSlot(key)
                if el ~= "none" and not ns.IsNameElement(el) then
                    usedWidth = usedWidth + EstimateHealthTextWidth(el)
                end
            end
        end
        local nameW = barW - usedWidth - nameMarkerReserve
        PP.Width(self.name, math.max(nameW * pct / 100, 20))
    else
        -- Name not in any slot, use minimal width
        PP.Width(self.name, math.max(barW * pct / 100, 20))
    end
end
function NameplateFrame:ApplyNameVisibility()
    -- Zero cost when off: the name's shown state is owned by RefreshNamePosition;
    -- only override it (hide while the cast bar is up) when the feature is on.
    if not GetHideEnemyNameWhileCasting() then return end
    local hasNameSlot = ns.FindNameSlot() ~= nil
    local shown = hasNameSlot and not self.cast:IsShown()
    self.name:SetShown(shown)
    if self.nameRaidFrame then self.nameRaidFrame:SetShown(shown and self._nameRaidMarkerShown == true) end
end
-- The full-size cast icon (a cast-bar child) occupies its side-slot space only while a cast is
-- up, so its reserve is gated on the cast bar being shown (see GetCastIconReserve). On every
-- cast show/hide, re-anchor the side elements that reserve it (target arrow, classification
-- icon, raid marker) so they track the icon instead of sitting shoved out by a phantom gap.
-- Zero cost unless the full-size icon is enabled.
function NameplateFrame:RefreshCastIconSideReserve()
    if not (GetShowCastIcon() and ns.GetCastIconFullSize()) then return end
    self:UpdateClassification()
    self:UpdateRaidIcon()
    PositionArrowsOutsideAuras(self)
end

function NameplateFrame:RefreshNamePosition(localOnly)
    local nameSlot = ns.FindNameSlot()
    local nameYOff = GetNameYOffset()
    local nameMarkerShown
    local nameMarkerSize = (p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14
    if self.nameRaidFrame then
        local idx
        if p and p.nameRaidMarkerEnabled == true and nameSlot and self.unit then
            idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
        end
        if type(idx) == "nil" then
            self._nameRaidMarkerShown = nil
            self.nameRaidFrame:Hide()
        else
            SetRaidTargetIconTexture(self.nameRaid, idx)
            PP.Size(self.nameRaidFrame, nameMarkerSize, nameMarkerSize)
            self._nameRaidMarkerShown = true
            self.nameRaidFrame:Show()
            nameMarkerShown = true
        end
    end
    local nameMarkerReserve = nameMarkerShown and (nameMarkerSize + 3) or 0
    local nameStrata = (p and nameSlot and p[nameSlot .. "Strata"]) or "MEDIUM"
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlot == "textSlotLeft" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        PP.Point(self.name, "LEFT", self.health, "LEFT", 4 + txOff + nameMarkerReserve, tyOff)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlot == "textSlotCenter" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        self.name:SetPoint("CENTER", self.health, "CENTER", txOff + (nameMarkerReserve * 0.5), tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    elseif nameSlot == "textSlotRight" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotRight")
        SetFSFont(self.name, GetTextSlotSize("textSlotRight"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        PP.Point(self.name, "RIGHT", self.health, "RIGHT", -2 + txOff, tyOff)
        self.name:SetJustifyH("RIGHT")
        self.name:Show()
    elseif nameSlot == "textSlotTop" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        SetFSFont(self.name, GetTextSlotSize("textSlotTop"), GetNPOutline())
        self.name:SetParent(ns.SlotTextHost(self, "textSlotTop", nameStrata))
        local cpPush = GetClassPowerTopPush(self)
        PP.Point(self.name, "BOTTOM", self.health, "TOP", txOff + (nameMarkerReserve * 0.5), 4 + nameYOff + cpPush + tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
    -- Apply name wrap here (not only at creation) so the cog toggle takes effect on the next
    -- settings refresh. Off = single line + ellipsis, on = up to two lines; reflow re-lays out.
    local nameWrap = defaults.enemyNameWrap
    if p and p.enemyNameWrap ~= nil then nameWrap = p.enemyNameWrap end
    self.name:SetWordWrap(nameWrap)
    self.name:SetNonSpaceWrap(false)
    self.name:SetMaxLines(nameWrap and 2 or 1)
    ns.ReflowFontString(self.name)
    self:ApplyNameVisibility()
    local nameRaid = self.nameRaidFrame
    if nameRaid and self._nameRaidMarkerShown and self.name:IsShown() then
        PP.Size(nameRaid, nameMarkerSize, nameMarkerSize)
        -- Follows the name's host so the marker rides the slot's strata; the
        -- host's own SetFrameStrata (SlotTextHost) resets child frames, so
        -- re-assert AFTER parenting.
        nameRaid:SetParent(ns.SlotTextHost(self, nameSlot, nameStrata))
        nameRaid:SetFrameStrata(nameStrata)
        nameRaid:SetFrameLevel(901)
        nameRaid:ClearAllPoints()
        nameRaid:SetPoint("RIGHT", self.name, "LEFT", -3, 0)
        nameRaid:Show()
    elseif nameRaid then
        nameRaid:Hide()
    end
    if localOnly then return end
    self:UpdateClassification()
end
function NameplateFrame:UpdateRaidIcon()
    if not self.unit then return end
    local pos = GetRaidMarkerPos()
    if pos == "none" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- type() is taint-safe: returns "nil"/"number" without reading the secret value
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    if type(idx) == "nil" then
        self.raidFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    SetRaidTargetIconTexture(self.raid, idx)
    local sz = GetRaidMarkerSize()
    PP.Size(self.raidFrame, sz, sz)
    local cpPush = GetClassPowerTopPush(self)
    local rxOff, ryOff = GetAuraSlotOffsets("raidMarker")
    self.raidFrame:ClearAllPoints()
    if pos == "top" then
        local debuffY = GetDebuffYOffset()
        PP.Point(self.raidFrame, "BOTTOM", self.health, "TOP",
            rxOff, debuffY + cpPush + ryOff)
    elseif pos == "left" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local iconPush = (iconSide == "left") and iconRes or 0
        PP.Point(self.raidFrame, "RIGHT", self.health, "LEFT",
            -sideOff - iconPush + rxOff, ryOff)
    elseif pos == "right" then
        local sideOff = GetSideAuraXOffset()
        local iconRes, iconSide = ns.GetCastIconReserve(self)
        local iconPush = (iconSide == "right") and iconRes or 0
        PP.Point(self.raidFrame, "LEFT", self.health, "RIGHT",
            sideOff + iconPush + rxOff, ryOff)
    elseif pos == "topleft" then
        PP.Point(self.raidFrame, "BOTTOMLEFT", self.health, "TOPLEFT", rxOff, cpPush + ryOff)
    elseif pos == "topright" then
        PP.Point(self.raidFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", rxOff, cpPush + ryOff)
    elseif pos == "bottom" then
        -- Below the cast bar, centered (matches PositionAuraSlot "bottom" convention).
        PP.Point(self.raidFrame, "TOP", self.cast, "BOTTOM", rxOff, -2 + ryOff)
    end
    self.raidFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    self._isTarget = isTarget  -- cached for hot-path hash line check
    -- EllesmereUI: background glow around the plate, tinted + faded with the
    -- target Glow Color/Opacity (re-applied on show so live edits update).
    if isTarget and ns.GetTargetGlowEllesmereUI() then
        EnsureGlow(self)
        if self.glowTextures then
            local gc = ns.GetTargetGlowColor()
            local ga = ns.GetTargetGlowAlpha()
            for _, t in ipairs(self.glowTextures) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
        end
        self.glow:Show()
    elseif self.glow then
        self.glow:Hide()
    end
    -- Border Size: resize the health border while targeted. tbsz stays nil unless the effect is
    -- on AND a size was snapshotted. Runs BEFORE Border Color so a rebuilt custom border gets
    -- its target tint right after. Restore is one-shot via self._targetBorderSized.
    local tbsz
    if isTarget and ns.GetTargetGlowBorderSize() then tbsz = ns.GetTargetBorderSizeValue() end
    if tbsz then
        if ns.IsCustomBorderEnabled() then
            ns.ApplyCustomBorderStyle(self, tbsz)
        elseif PP and IsBorderEnabled() then
            PP.SetBorderSize(self.health, tbsz)
        end
        self._targetBorderSized = true
    elseif self._targetBorderSized then
        self._targetBorderSized = nil
        self:ApplyBorder()
    end
    -- Border Color: recolor the health bar border with the custom target color
    if isTarget and ns.GetTargetGlowBorderColor() then
        if PP then
            local bc = ns.GetTargetBorderColor()
            if ns.IsCustomBorderEnabled() then
                -- Custom border replaces the simple one; recolor with the target color,
                -- lazy-creating it if this plate is targeted before its first ApplyBorder ran.
                if not self._customBorder then ns.ApplyCustomBorderStyle(self) end
                if self._customBorder and EllesmereUI.SetBorderStyleColor then
                    EllesmereUI.SetBorderStyleColor(self._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                PP.SetBorderColor(self.health, bc.r, bc.g, bc.b, 1)
            end
        end
    else
        self:ApplyBorderColor()
    end
    -- If this plate is wrapping its border around the cast bar, the colour just set landed on
    -- the HIDDEN health border: re-sync the visible unified border. One field read unless live.
    if self._wrapActive then self:UpdateBorderWrap() end
    -- Highlight: translucent wash across the health bar (color + opacity are
    -- configurable; re-applied on show so live edits and pooled textures update)
    if isTarget and ns.GetTargetGlowHighlight() then
        EnsureTargetHighlight(self)
        local c = ns.GetTargetHighlightColor()
        self.targetHighlight:SetColorTexture(c.r, c.g, c.b, ns.GetTargetHighlightAlpha())
        self.targetHighlight:Show()
    elseif self.targetHighlight then
        self.targetHighlight:Hide()
    end
    if p and p.showTargetArrows then
        if isTarget then
            EnsureArrows(self)
            local sc = p.targetArrowScale or 1.0
            local st = ns.ResolveTargetArrowStyle(p)
            self.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
            self.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
            local acr, acg, acb = ns.GetTargetArrowColor(p)
            self.leftArrow:SetVertexColor(acr, acg, acb)
            self.rightArrow:SetVertexColor(acr, acg, acb)
            local aw, ah = math.floor(st.w * sc + 0.5), math.floor(16 * sc + 0.5)
            PP.Size(self.leftArrow,  aw, ah)
            PP.Size(self.rightArrow, aw, ah)
            self.leftArrow:Show()
            self.rightArrow:Show()
            PositionArrowsOutsideAuras(self)
        elseif self.leftArrow then
            self.leftArrow:Hide()
            self.rightArrow:Hide()
        end
    elseif self.leftArrow then
        self.leftArrow:Hide()
        self.rightArrow:Hide()
    end
    -- Class power pips: show on target, hide on others
    if GetShowClassPower() and classPowerType then
        if isTarget then
            EnsureClassPowerPips(self)
            UpdateClassPowerOnPlate(self)
        else
            HideClassPowerOnPlate(self)
        end
    end
    self:ApplyScale()
end
function NameplateFrame:ApplyMouseover()
    if not self.unit then return end
    if UnitExists("mouseover") and UnitIsUnit(self.unit, "mouseover") then
        ns.ShowHoverEffect(self)
        ns.ApplyHoverExtras(self)
        ns._currentMouseoverPlate = self
        if ns._EnsureMouseoverTicker then ns._EnsureMouseoverTicker() end
    else
        ns.HideHoverEffect(self)
        ns.ClearHoverExtras(self)
    end
end

-- Hover Effect extra channels (EUI Glow / Border Color / Border Size --
-- mirrors ApplyTarget's branches; the Highlight channel lives inside
-- ShowHoverEffect). TARGET PRECEDENCE per shared visual: while this plate is
-- the target and the TARGET effect drives the same channel, hover leaves it
-- alone -- and ApplyTarget runs after every target change, so the target
-- state always reasserts over a stale hover write.
function ns.ApplyHoverExtras(plate)
    if not plate or not plate.unit or not plate.health then return end
    local isTarget = plate._isTarget
    local any = false
    -- EUI Glow (shared self.glow visual).
    if ns.GetHoverGlowEllesmereUI() and not (isTarget and ns.GetTargetGlowEllesmereUI()) then
        EnsureGlow(plate)
        if plate.glowTextures then
            local gc = ns.GetHoverGlowColor()
            local ga = ns.GetHoverGlowAlpha()
            for _, t in ipairs(plate.glowTextures) do t:SetVertexColor(gc.r, gc.g, gc.b, ga) end
        end
        plate.glow:Show()
        any = true
    end
    -- Border Size (a target-sized border wins; restore is ClearHoverExtras').
    if ns.GetHoverGlowBorderSize() and not plate._targetBorderSized then
        local hbsz = ns.GetHoverBorderSizeValue()
        if hbsz then
            if ns.IsCustomBorderEnabled() then
                ns.ApplyCustomBorderStyle(plate, hbsz)
            elseif PP and IsBorderEnabled() then
                PP.SetBorderSize(plate.health, hbsz)
            end
            plate._hoverBorderSized = true
            any = true
        end
    end
    -- Border Color (the target color wins).
    if ns.GetHoverGlowBorderColor() and not (isTarget and ns.GetTargetGlowBorderColor()) then
        if PP then
            local bc = ns.GetHoverBorderColor()
            if ns.IsCustomBorderEnabled() then
                if not plate._customBorder then ns.ApplyCustomBorderStyle(plate) end
                if plate._customBorder and EllesmereUI.SetBorderStyleColor then
                    EllesmereUI.SetBorderStyleColor(plate._customBorder, bc.r, bc.g, bc.b, 1)
                end
            else
                PP.SetBorderColor(plate.health, bc.r, bc.g, bc.b, 1)
            end
            any = true
        end
        if plate._wrapActive then plate:UpdateBorderWrap() end
    end
    if any then plate._hoverFxOn = true end
end

-- One-shot restore of every shared channel to the target/base state: the
-- hover-sized border resets explicitly (ApplyTarget only restores its OWN
-- sizing flag), then ApplyTarget's else-branches reset glow/border color.
-- Early-out keeps the no-extras case (the shipped default) zero-cost.
function ns.ClearHoverExtras(plate)
    if not plate or not plate._hoverFxOn then return end
    plate._hoverFxOn = nil
    if plate._hoverBorderSized then
        plate._hoverBorderSized = nil
        plate:ApplyBorder()
    end
    plate:ApplyTarget()
end
function NameplateFrame:UpdateImportantCastGlow(spellID)
    local cfg = p or defaults
    local enabled = cfg.importantCastGlow
    if enabled == nil then enabled = defaults.importantCastGlow end
    if not enabled then self:ClearImportantCastGlow(); return end

    if not C_Spell or not C_Spell.IsSpellImportant then
        self:ClearImportantCastGlow(); return
    end

    if not self._importantCastOverlay then
        local ov = CreateFrame("Frame", nil, self.cast)
        ov:SetAllPoints(self.cast)
        ov:SetFrameLevel(self.cast:GetFrameLevel() + 5)
        ov:EnableMouse(false)
        self._importantCastOverlay = ov
    end

    local Glows = _G_Glows or EllesmereUI.Glows
    if not Glows then return end

    local style = cfg.importantCastGlowStyle or defaults.importantCastGlowStyle or 1
    if type(style) ~= "number" or style < 1 or style > #PANDEMIC_GLOW_STYLES then style = 1 end
    local c = cfg.importantCastGlowColor or defaults.importantCastGlowColor or { r = 1, g = 0.2, b = 0.2 }
    local bgColor = cfg.importantCastGlowBackgroundColor or defaults.importantCastGlowBackgroundColor or { r = 0, g = 0, b = 0 }
    local bgOn = cfg.importantCastGlowBackground == true
    -- Lines/thickness/speed and the background are Pixel Glow's own knobs; every
    -- other style ignores them, so they stay nil and out of the cache key below.
    local impN, impTh, impPeriod
    if style == 1 then
        impN = cfg.importantCastGlowLines or defaults.importantCastGlowLines or 8
        impTh = cfg.importantCastGlowThickness or defaults.importantCastGlowThickness or 2
        impPeriod = cfg.importantCastGlowSpeed or defaults.importantCastGlowSpeed or 4
    end

    -- Ensure glow animation is running (idempotent if already active)
    if not self._importantGlowActive or self._importantGlowStyle ~= style
       or self._importantGlowR ~= c.r or self._importantGlowG ~= c.g or self._importantGlowB ~= c.b
       or self._importantGlowBgOn ~= bgOn or self._importantGlowBgR ~= bgColor.r
       or self._importantGlowBgG ~= bgColor.g or self._importantGlowBgB ~= bgColor.b
       or self._importantGlowN ~= impN or self._importantGlowTh ~= impTh
       or self._importantGlowPeriod ~= impPeriod then
        Glows.StopAllGlows(self._importantCastOverlay)
        local pW, pH = self.cast:GetWidth(), self.cast:GetHeight()
        if pW < 5 then pW = 100 end
        if pH < 5 then pH = 14 end
        -- StartGlow owns the per-style engine pick. Its Pixel Glow path reproduces
        -- the old direct call exactly: same lineLen formula, and an unset bg alpha
        -- resolves to 1 there, which is what omitting the argument used to do.
        local Start = StartGlow or Glows.StartGlow
        Start(self._importantCastOverlay, ns.NP_TO_SHARED_GLOW[style] or 1, pW, c.r, c.g, c.b,
            style == 1 and {
                N = impN, th = impTh, period = impPeriod,
                bg = bgOn and { r = bgColor.r or 0, g = bgColor.g or 0, b = bgColor.b or 0 } or nil,
            } or nil, pH)
        self._importantGlowActive = true
        self._importantGlowStyle = style
        self._importantGlowR, self._importantGlowG, self._importantGlowB = c.r, c.g, c.b
        self._importantGlowBgOn = bgOn
        self._importantGlowBgR, self._importantGlowBgG, self._importantGlowBgB = bgColor.r, bgColor.g, bgColor.b
        self._importantGlowN, self._importantGlowTh, self._importantGlowPeriod = impN, impTh, impPeriod
    end

    -- SetAlphaFromBoolean handles the secret boolean taint-free.
    -- Important = alpha 1 (glow visible), not important = alpha 0 (glow hidden).
    self._importantCastOverlay:Show()
    local ok, isImportant = pcall(C_Spell.IsSpellImportant, spellID or 0)
    if ok then
        self._importantCastOverlay:SetAlphaFromBoolean(isImportant)
    else
        self._importantCastOverlay:SetAlpha(0)
    end
end

function NameplateFrame:ClearImportantCastGlow()
    if self._importantGlowActive and self._importantCastOverlay then
        local Glows = _G_Glows or EllesmereUI.Glows
        if Glows then Glows.StopAllGlows(self._importantCastOverlay) end
        self._importantCastOverlay:SetAlpha(0)
        self._importantCastOverlay:Hide()
        self._importantGlowActive = false
        self._importantGlowStyle = nil
    end
end

function NameplateFrame:UpdateCast()
    if not self.unit then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end
    local name, _, texture, _, _, _, _, kickProtected, castSpellID = UnitCastingInfo(self.unit)
    local isChannel = false
    local isEmpowered = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected, castSpellID = UnitChannelInfo(self.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        if not self._interrupted then
            self.cast:Hide()
        end
        self:ApplyNameVisibility()
        self.castTimer:SetText("")
        if self.isCasting then
            if self._castFallback then
                self._castFallback = nil
                _fallbackPlates[self] = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
            end
            NotifyCastEnded(self)
        end
        self.isCasting = false
        self._castTex = nil
        self._castDirtyFull = nil
        self:HideKickTick()
        self:ClearImportantCastGlow()
        self:ApplyScale()
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
        return
    end

    if self._interrupted then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
    end

    -- FAST PATH: on DELAYED/UPDATE events (not START), the icon, name, target, and glow
    -- haven't changed; only duration needs updating. _castDirtyFull is set by
    -- UNIT_SPELLCAST_START/CHANNEL_START/EMPOWER_START.
    local isFullSetup = self._castDirtyFull or not self.isCasting
    self._castDirtyFull = nil

    if isFullSetup then
        self.cast:Show()
        self:ApplyNameVisibility()
        -- Icon and name MUST describe the SAME cast: both come from this UnitCastingInfo/
        -- UnitChannelInfo snapshot. The icon uses the live texture (possibly SECRET --
        -- SetTexture accepts secrets natively), never a cached/leftover icon.
        if type(texture) ~= "nil" then
            self.castIcon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            -- Texture genuinely absent (rare): fall back to THIS cast's spell icon. pcall
            -- guards an invalid/0/unknown spellID; iconID feeds SetTexture, never branched on.
            local okInfo, info = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(info) == "table" then
                self.castIcon:SetTexture(info.iconID)
            else
                self.castIcon:SetTexture(nil)
            end
        else
            self.castIcon:SetTexture(nil)
        end
        self:UpdateCastText(name)
        self.castTimer:SetShown(self._showCastTimer)

        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        self._kickProtected = kickProtected
        -- Cache the game's "important" flag for the cast bar colour. May be SECRET, so it is
        -- stored raw and only fed to a boolean-curve evaluator, never branched on. pcall
        -- guards a 0/invalid spellID. Persists across interruptible flips/kick ticker reuse.
        self._castImportant = false
        if C_Spell and C_Spell.IsSpellImportant then
            local impOK, imp = pcall(C_Spell.IsSpellImportant, castSpellID or 0)
            if impOK then self._castImportant = imp end
        end
        local cfg = p or defaults
        local unintColor = cfg.castBarUninterruptible or defaults.castBarUninterruptible
        self.castBarOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
        self.castShieldFrame:Show()
        self:ApplyCastColor(kickProtected)
    end
    
    if UnitCastingDuration and self.cast.SetTimerDuration then
        if isChannel then
            local castDuration
            -- Empowered channel duration first (Evoker empower spells): normal UnitChannelDuration
            -- can return nil during the empower phase, leaving the bar unticked despite a name.
            if UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
                if castDuration then isEmpowered = true end
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
            if castDuration then
                self.cast:SetReverseFill(false)
                -- Empowered channels fill forward (elapsed time / stages);
                -- normal channels fill backward (remaining time).
                local direction = isEmpowered
                    and Enum.StatusBarTimerDirection.ElapsedTime
                    or Enum.StatusBarTimerDirection.RemainingTime
                self.cast:SetTimerDuration(castDuration, nil, direction)
                if not self.isCasting then NotifyCastStarted(self) end
                self.isCasting = true
            end
        else
            local castDuration = UnitCastingDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            end
            if not self.isCasting then NotifyCastStarted(self) end
            self.isCasting = true
        end
    else
        if not self.isCasting then
            self.isCasting = true
            self._castFallback = true
            _fallbackPlates[self] = true
            fallbackCastCount = fallbackCastCount + 1
            castFallbackFrame:Show()
            NotifyCastStarted(self)
        end
    end
    if isFullSetup then
        self._kickGeoDirty = nil
        self:ApplyScale()
        self:UpdateKickTick(kickProtected, isChannel, isEmpowered)
        self:UpdateImportantCastGlow(castSpellID)
        if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
            UpdateClassPowerOnPlate(self)
        end
    elseif self._kickGeoDirty then
        -- Cast timing changed mid-cast (delay/channel/empower update): re-derive kick
        -- geometry from the cached cast identity
        self._kickGeoDirty = nil
        self:UpdateKickTick(self._kickProtected, self._kickIsChannel, self._kickIsEmpowered)
    end
end
-- Smooth scale transitions: one shared OnUpdate eases every plate whose displayed scale
-- (_curScale) differs from its destination (_destScale). Driver hides itself the instant no
-- plate is animating, so idle costs nothing; at target/cast scale 100 dest stays 1 and
-- ApplyScale snaps without enrolling.
ns._scaleAnim = {}  -- [plate] = true while its scale is easing
do
    local SPEED = 11     -- exponential approach rate (higher = snappier)
    local SNAP  = 0.004  -- within this of dest -> finish and drop from set
    local anim  = ns._scaleAnim
    local driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function(_, elapsed)
        -- Frame-rate independent ease: same settle time at any FPS.
        local t = 1 - math.exp(-SPEED * elapsed)
        for plate in pairs(anim) do
            local cur  = plate._curScale or 1
            local dest = plate._destScale or 1
            local nv = cur + (dest - cur) * t
            if nv - dest < SNAP and dest - nv < SNAP then
                nv = dest
                anim[plate] = nil
            end
            plate._curScale = nv
            plate:SetScale(nv)
            -- The held "Interrupted" flash keeps the bar visible after isCasting clears; it must ride the shrink-back too.
            if (plate.isCasting or plate._interrupted) and ns.RefreshCastOverlay then ns.RefreshCastOverlay(plate) end
        end
        if not next(anim) then driver:Hide() end
    end)
    ns._ScaleDriverShow = function() driver:Show() end
end
function NameplateFrame:ApplyScale()
    local base = 1
    if self.unit and UnitIsUnit(self.unit, "target") then
        local ts = GetTargetScale() / 100
        if ts ~= 1 then base = ts end
    end
    local cs = GetCastScale() / 100
    local dest = base
    if self.isCasting and cs ~= 1 then dest = base * cs end
    self._destScale = dest
    local cur = self._curScale
    if cur == nil or (dest - cur < 0.004 and cur - dest < 0.004) then
        -- Fresh/recycled plate, or already at the destination: snap instantly.
        self._curScale = dest
        ns._scaleAnim[self] = nil
        self:SetScale(dest)
    else
        -- Ease toward the new destination via the shared OnUpdate driver.
        ns._scaleAnim[self] = true
        ns._ScaleDriverShow()
    end
    -- Lifted cast bar renders outside this plate's scale chain; keep its container pinned to the plate's effective scale.
    if ns.RefreshCastOverlay then ns.RefreshCastOverlay(self) end
end
function NameplateFrame:ApplyCastColor(uninterruptible)
    local cfg = p or defaults
    local kickReadyTint = cfg.interruptReady or defaults.interruptReady
    local normalCastTint = cfg.castBar or defaults.castBar
    -- Important Cast Color (opt-in): a cast the game flags important shows the Important
    -- colour instead of Interruptible. The flag may be SECRET, so blend per channel via
    -- EvaluateColorValueFromBoolean (ifTrue=Important, ifFalse=Interruptible), never branch on
    -- it. Interrupt-on-CD still wins: ComputeCastBarTint layers the kick-ready tint over any
    -- base tint. Uninterruptible casts keep their look (overlay on top).
    local importantOn = cfg.importantCastColorEnabled
    if importantOn == nil then importantOn = defaults.importantCastColorEnabled end
    if importantOn and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local imp = cfg.castBarImportant or defaults.castBarImportant
        local isImp = self._castImportant
        if type(isImp) == "nil" then isImp = false end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        -- Scratch table (same pattern as _dispelScratch): runs per cast event per plate, a fresh color table per call was pure GC churn.
        local sc = ns._castImpScratch
        if not sc then sc = {}; ns._castImpScratch = sc end
        sc.r = ev(isImp, imp.r, normalCastTint.r)
        sc.g = ev(isImp, imp.g, normalCastTint.g)
        sc.b = ev(isImp, imp.b, normalCastTint.b)
        normalCastTint = sc
    end
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, normalCastTint)

    -- Match the base cast fill to uninterruptible casts so plate opacity
    -- doesn't reveal the interruptible color underneath the overlay.
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local unintColor = cfg.castBarUninterruptible or defaults.castBarUninterruptible
        -- The settings-refresh callers pass the stored _kickProtected stamp,
        -- which is nil until the first cast event -- and a nil reaching the
        -- fold throws. type() is the secret-legal nil test (a plain == nil
        -- compare throws on a secret boolean), same idiom as the Important
        -- Cast block above.
        local isUnint = uninterruptible
        if type(isUnint) == "nil" then isUnint = false end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        cr = ev(isUnint, unintColor.r, cr)
        cg = ev(isUnint, unintColor.g, cg)
        cb = ev(isUnint, unintColor.b, cb)
    end
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    -- Shield icon is opt-out: when disabled it never shows, even on uninterruptible casts. The
    -- setting is a clean boolean, so it gates the (possibly SECRET) flag without evaluating it.
    local showShield = true
    if cfg.castBarShieldEnabled ~= nil then showShield = cfg.castBarShieldEnabled end
    if self.castBarOverlay.SetAlphaFromBoolean then
        self.castBarOverlay:SetAlphaFromBoolean(uninterruptible)
        if showShield then
            self.castShieldFrame:SetAlphaFromBoolean(uninterruptible)
        else
            self.castShieldFrame:SetAlpha(0)
        end
    else
        local a = uninterruptible and 1 or 0
        self.castBarOverlay:SetAlpha(a)
        self.castShieldFrame:SetAlpha(showShield and a or 0)
    end
end
function NameplateFrame:HideKickTick()
    self.kickPositioner:Hide()
    self.kickMarker:Hide()
    self.kickReadyFill:Hide()
    if self._kickTicker then
        self._kickTicker:Cancel()
        self._kickTicker = nil
    end
end
function NameplateFrame:UpdateKickTick(kickProtected, isChannel, isEmpowered)
    -- Two independent CLEAN toggles drive this geometry: the visible tick (kickTickEnabled)
    -- and the interrupt-ready mid-cast fill (interruptMidCastEnabled). Either needs the
    -- positioner/marker StatusBars below; each visible element is gated on its own toggle.
    local tickOn = GetKickTickEnabled()
    local midOn = defaults.interruptMidCastEnabled
    if p and p.interruptMidCastEnabled ~= nil then midOn = p.interruptMidCastEnabled end
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        self:HideKickTick()
        return
    end
    -- kickProtected is a SECRET boolean: never branch on it. Store it and apply visibility via
    -- SetAlphaFromBoolean after setup. isChannel/isEmpowered cached too (cooldown watcher
    -- re-setups from these).
    self._kickProtected = kickProtected
    self._kickIsChannel = isChannel
    self._kickIsEmpowered = isEmpowered
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    -- Midnight path: use secret duration objects
    if UnitCastingDuration and self.cast.SetTimerDuration then
        local castDuration
        if isChannel then
            if isEmpowered and UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
        else
            castDuration = UnitCastingDuration(self.unit)
        end
        if not castDuration then
            self:HideKickTick()
            return
        end
        local totalDur = castDuration:GetTotalDuration()
        local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if not interruptCD then
            self:HideKickTick()
            return
        end
        -- Size the StatusBars to match the cast bar (positioner uses SetPoint("CENTER"), not SetAllPoints)
        local castH = GetCastBarHeight()
        local barW = self.cast:GetWidth()
        self.kickPositioner:SetSize(barW, castH)
        self.kickPositioner:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetMinMaxValues(0, totalDur)
        self.kickMarker:SetSize(barW, castH)
        -- Initial PAIRED snapshot: the tick's position is positioner(elapsed) +
        -- marker(kick CD remaining), which equals the fixed "kick ready here" point only when
        -- both are sampled at the same instant. RefreshKickTick re-pins the pair on every
        -- cooldown event. NEVER update one without the other -- a marker-only refresh drifts
        -- the tick left.
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
        self.kickMarker:SetValue(interruptCD:GetRemainingDuration())
        -- Apply color
        local kr, kg, kb = GetKickTickColor()
        self.kickTick:SetColorTexture(kr, kg, kb, 1)
        -- Handle channel vs cast fill direction. Empowered channels fill
        -- forward (like a normal cast), so treat them as non-channel here.
        if isChannel and not isEmpowered then
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
            -- SetStatusBarTexture unsnap hook will NOT re-fire (caches per StatusBar frame).
            -- Re-disable snap so positioner(elapsed) + marker(CD remaining) stays an exact
            -- float and the tick holds still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("RIGHT", self.kickPositioner:GetStatusBarTexture(), "LEFT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
            -- Reverse fill (draining channel): the kick-ready point is the
            -- marker texture LEFT edge; the "kick available" window runs from
            -- the channel end (bar left) to that point. Not-in-time pushes the
            -- marker edge past the left edge, crossing the anchors to zero width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.cast, "LEFT", 0, 0)
            self.kickReadyFill:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
        else
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the reverse
            -- branch) so the summed elapsed+remaining edge is exact and the tick stays still.
            local pt = self.kickPositioner:GetStatusBarTexture()
            if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
            local mt = self.kickMarker:GetStatusBarTexture()
            if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("LEFT", self.kickPositioner:GetStatusBarTexture(), "RIGHT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            -- Standard fill (cast/empowered channel): the kick-ready point is the marker
            -- texture RIGHT edge; the "kick available" window runs from it to cast end (bar
            -- right). Not-in-time pushes the marker edge past the right edge, zeroing width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            self.kickReadyFill:SetPoint("RIGHT", self.cast, "RIGHT", 0, 0)
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility. Its alpha (the
        -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
        -- above runs when the tick OR the fill is enabled; SetShown gates each independently.
        local mc = (p and p.interruptMidCastColor) or defaults.interruptMidCastColor
        self.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
        self.kickTick:SetShown(tickOn)
        self.kickReadyFill:SetShown(midOn)
        -- Compute initial tick alpha immediately (avoids split-second delay
        -- from waiting for the first ticker fire at 0.1s).
        if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
            local kickReady = interruptCD:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            self.kickTick:SetAlpha(alpha)
            self.kickReadyFill:SetAlpha(alpha)
        else
            self.kickTick:SetAlpha(0)
            self.kickReadyFill:SetAlpha(0)
        end
        -- Ticker: tick ALPHA only at 10fps (kick-ready x interruptibility secret combine). Bar
        -- values are re-pinned as a PAIR by RefreshKickTick on cooldown events, not here.
        if self._kickTicker then self._kickTicker:Cancel() end
        -- Self-identifying ticker: a superseded ticker cancels ITSELF rather than
        -- calling HideKickTick, which would cancel its successor.
        local myTicker
        myTicker = C_Timer.NewTicker(0.1, function()
            if self._kickTicker ~= myTicker then
                myTicker:Cancel()
                return
            end
            if not self.isCasting or not self.unit then
                self:HideKickTick()
                return
            end
            -- activeKickSpell can go nil mid-cast if a spec/talent change fires SPELLS_CHANGED
            -- and the new spec has no kick learned. Bail rather than pass nil to C_Spell.
            if not GetActiveKickSpell() then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans, chain EvaluateColorValueFromBoolean calls to combine.
            local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
            if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
                local kickReady = icd:IsZero()
                local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
                self.kickTick:SetAlpha(alpha)
                self.kickReadyFill:SetAlpha(alpha)
            end
        end)
        self._kickTicker = myTicker
    else
        -- API not available; hide tick
        self:HideKickTick()
    end
end
-- Light per-cooldown-event refresh: bar values + tick alpha only; geometry (sizes, anchors,
-- fill styles, colors) is cast-identity work done once by UpdateKickTick. CRITICAL: the tick
-- position is positioner(elapsed) + marker(remaining), the true "kick ready here" point only
-- when BOTH snapshots are taken at the same instant -- re-pinning the marker alone drifts the
-- tick left. Always re-pin both together.
function NameplateFrame:RefreshKickTick()
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not icd then
        -- Transient read miss during an ongoing cast: skip this refresh and keep the current
        -- tick/fill. Hiding here would make the tick and kick-ready bar blink through the
        -- rotation. Genuine cast-end is handled by cast-stop/interrupt paths.
        return
    end
    if UnitCastingDuration and self.unit then
        local castDuration
        if self._kickIsChannel then
            if self._kickIsEmpowered and UnitEmpoweredChannelDuration then
                castDuration = UnitEmpoweredChannelDuration(self.unit, true)
            end
            if not castDuration then
                castDuration = UnitChannelDuration(self.unit)
            end
        else
            castDuration = UnitCastingDuration(self.unit)
        end
        if not castDuration then
            -- Transient read miss (see above): skip, do not hide.
            return
        end
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    end
    self.kickMarker:SetValue(icd:GetRemainingDuration())
    if icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(icd:IsZero(), 0, interruptible)
        self.kickTick:SetAlpha(alpha)
        self.kickReadyFill:SetAlpha(alpha)
    end
end
function NameplateFrame:ShowInterrupted(interrupterGUID)
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ApplyScale()

    -- If the interrupted flash effect is disabled, end the cast like a normal
    -- stop (hide the bar) without the flash + held "Interrupted" text.
    local flashOn = defaults.interruptedFlashEnabled
    if p and p.interruptedFlashEnabled ~= nil then flashOn = p.interruptedFlashEnabled end
    if not flashOn then
        self.cast:Hide()
        self:ApplyNameVisibility()
        return
    end

    self._interrupted = true
    self.cast:SetReverseFill(false)
    self.cast:SetMinMaxValues(0, 1)
    self.cast:SetValue(1)
    local fc = (p and p.interruptedFlashColor) or defaults.interruptedFlashColor
    self.cast:GetStatusBarTexture():SetVertexColor(fc.r, fc.g, fc.b)

    -- GetPlayerInfoByGUID accepts the event's SECRET interrupter GUID and may
    -- return a SECRET name/class. Keep those values opaque until native sinks.
    local interrupterName
    local interrupterClass
    if type(interrupterGUID) ~= "nil" then
        local _, class, _, _, _, name = GetPlayerInfoByGUID(interrupterGUID)
        interrupterClass = class
        interrupterName = name
        if type(interrupterName) == "nil" then
            -- Fallback for a NON-player interrupter GUID (pet or NPC): GetPlayerInfoByGUID
            -- only resolves players, so pull the name from the GUID's live unit token instead.
            -- Non-players have no class, so interrupterClass stays nil and the class-color path
            -- is skipped. A SECRET GUID resolves to a SECRET token/name; both pass straight to
            -- SetFormattedText as display args, so the name still shows. type() is the only legal check.
            local token = UnitTokenFromGUID(interrupterGUID)
            if type(token) ~= "nil" then
                interrupterName = UnitName(token)
            end
        end
    end
    local cfg = p or defaults
    local useClassColor = defaults.castTargetClassColor
    if cfg.castTargetClassColor ~= nil then useClassColor = cfg.castTargetClassColor end
    local castNameColor = cfg.castNameColor or defaults.castNameColor
    local interrupterColor
    if useClassColor and type(interrupterClass) ~= "nil" and C_ClassColor then
        interrupterColor = C_ClassColor.GetClassColor(interrupterClass)
    end
    if interrupterColor then
        self.castName:SetTextColor(interrupterColor:GetRGB())
    else
        self.castName:SetTextColor(castNameColor.r, castNameColor.g, castNameColor.b, 1)
    end

    -- Show the interrupter inline as "Interrupted (Name)" in the single cast-name
    -- FontString; the cast-target / timer slots are cleared during the flash.
    local hasInterrupter = type(interrupterName) ~= "nil"
    local castW = self.cast:GetWidth()
    if castW and castW > 0 then
        local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
        self.castName:SetWidth(hasInterrupter and math.max(castW - 8, 20) or castW * cnWPct / 100)
    end

    local interruptedText = (EllesmereUI and EllesmereUI.L and EllesmereUI.L("Interrupted")) or "Interrupted"
    if hasInterrupter then
        -- The base FontString color carries SECRET class RGB; only the clean
        -- localized label/punctuation uses an inline profile-color escape.
        local nameHex = string.format("ff%02x%02x%02x",
            math.floor(castNameColor.r * 255 + 0.5), math.floor(castNameColor.g * 255 + 0.5),
            math.floor(castNameColor.b * 255 + 0.5))
        self.castName:SetFormattedText("|c" .. nameHex .. "%s (|r%s|c" .. nameHex .. ")|r",
            interruptedText, interrupterName)
    else
        self.castName:SetText(interruptedText)
    end

    self.castTarget:SetText("")
    self.castTarget:Hide()
    self.castTimer:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.cast:Show()
    self:ApplyNameVisibility()

    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end

    self._interruptTimer = C_Timer.NewTimer(1.0, function()
        if self._interrupted then
            self._interrupted = nil
            self._interruptTimer = nil
            self.cast:Hide()
            self:ApplyNameVisibility()
        end
    end)
end
function NameplateFrame:ShowCastLockout()
    if not ns.ShowCastLockoutAsCrowdControl() or not self.unit then return end
    local now = GetTime()
    local lockout = {
        icon = ns.CAST_LOCKOUT_ICON,
        start = now,
        duration = ns.DEFAULT_CAST_LOCKOUT_DURATION,
        expires = now + ns.DEFAULT_CAST_LOCKOUT_DURATION,
    }
    self._castLockout = lockout
    if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    C_Timer.After(ns.DEFAULT_CAST_LOCKOUT_DURATION, function()
        if self._castLockout ~= lockout or GetTime() < lockout.expires then return end
        self._castLockout = nil
        if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    -- If the mob dies while the "Interrupted" flash is held up, Blizzard's death animation
    -- scales the still-shown cast bar and it looks warped, so tear the flash down on death.
    -- Gated on _interrupted first, so UnitIsDeadOrGhost only runs during the flash window.
    if self._interrupted and self.unit and UnitIsDeadOrGhost(self.unit) then
        self._interrupted = nil
        if self._interruptTimer then
            self._interruptTimer:Cancel()
            self._interruptTimer = nil
        end
        self.cast:Hide()
        self:ApplyNameVisibility()
    end
    self:UpdateHealthValues()
end
-- Max health changed: drop the cached max so the next paint re-derives it and
-- re-pushes the bar bounds (per-paint SetMinMaxValues is gone from the lean
-- path; bounds ride this event, exactly like Blizzard's CompactUnitFrame).
function NameplateFrame:UNIT_MAXHEALTH()
    self._maxHPValid = nil
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    -- The dedicated absorb edge: force the next paint onto the full absorb
    -- path so the lean-gate flag re-derives from a fresh read.
    self._absorbEdge = true
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_NAME_UPDATE()
    self:UpdateName()
end
function NameplateFrame:UNIT_THREAT_LIST_UPDATE()
    self:UpdateHealthColor()
end
function NameplateFrame:UNIT_SPELLCAST_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_DELAYED()
    -- Cast timing changed: the kick-tick geometry (min/max, positioner
    -- snapshot) must re-derive even on the non-full UpdateCast path
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_STOP()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_STOP()
    -- Directly hide instead of UpdateCast: in restricted execution, UnitCastingInfo can
    -- return secret values (not nil) for a stale channel, making UpdateCast think it's active.
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ApplyScale()
    if not self._interrupted then
        self.cast:Hide()
    end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
end
function NameplateFrame:UNIT_SPELLCAST_FAILED()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTED(_, _, _, interrupterGUID)
    local protected = self._kickProtected
    if type(interrupterGUID) ~= "nil"
        and ((issecretvalue and issecretvalue(protected)) or not protected) then
        self:ShowCastLockout()
    end
    self:ShowInterrupted(interrupterGUID)
end
-- Mid-cast interruptibility flips: re-read protection once, store it, refresh
-- color + kick tick + overlay. The cooldown watcher never re-reads cast info per
-- event, so these events are the only mid-cast source of protection changes.
function NameplateFrame:KickProtectionChanged()
    if not self.unit then return end
    local kickProtected
    local sName, _, _, _, _, _, _, kp = UnitCastingInfo(self.unit)
    if type(sName) ~= "nil" then
        kickProtected = kp
    else
        local chName
        chName, _, _, _, _, _, kp = UnitChannelInfo(self.unit)
        if type(chName) == "nil" then return end
        kickProtected = kp
    end
    if type(kickProtected) == "nil" then kickProtected = false end
    self._kickProtected = kickProtected
    self:ApplyCastColor(kickProtected)
    self:RefreshKickTick()
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_NOT_INTERRUPTIBLE()
    self:KickProtectionChanged()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_START()
    self._castDirtyFull = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_UPDATE()
    self._kickGeoDirty = true
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_EMPOWER_STOP()
    -- Stop directly. Re-checking cast info here can return a stale secret
    -- value in PvP and look like the cast is still going.
    local wasCasting = self.isCasting
    self.isCasting = false
    self:HideKickTick()
    self:ClearImportantCastGlow()
    self:ApplyScale()
    if not self._interrupted then
        self.cast:Hide()
    end
    self:ApplyNameVisibility()
    self.castTimer:SetText("")
    if wasCasting then
        if self._castFallback then
            self._castFallback = nil
            _fallbackPlates[self] = nil
            fallbackCastCount = math.max(0, fallbackCastCount - 1)
            if fallbackCastCount == 0 then castFallbackFrame:Hide() end
        end
        NotifyCastEnded(self)
    end
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
end

-------------------------------------------------------------------------------
--  Centralized cast event dispatcher: registers all 13 SPELLCAST events ONCE globally instead
--  of 13 RegisterUnitEvent calls per plate, then looks up ns.plates[unit] (O(1) hash) and
--  dispatches to the plate's handler.
--  Cast-identity caching: the full UpdateCast path caches _kickProtected/_kickIsChannel/
--  _kickIsEmpowered on the plate, so the SPELL_UPDATE_COOLDOWN/USABLE watcher never re-reads
--  cast info per event (it re-pins the kick-tick value pair via RefreshKickTick). Cache
--  maintenance: INTERRUPTIBLE/NOT_INTERRUPTIBLE -> KickProtectionChanged re-reads and stores
--  protection, refreshes color+tick+overlay; DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE ->
--  _kickGeoDirty (next UpdateCast re-derives geometry from cached identity);
--  START/CHANNEL_START/EMPOWER_START -> _castDirtyFull = full setup; ClearUnit and mid-cast
--  token swaps (UpdateHealthValues) tear down and invalidate all cast caches.
-------------------------------------------------------------------------------
do
    local castDispatcher = CreateFrame("Frame")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_FAILED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    castDispatcher:SetScript("OnEvent", function(_, event, unit, ...)
        local plate = ns.plates[unit]
        if not plate then return end
        local handler = plate[event]
        if handler then handler(plate, unit, ...) end
    end)
    ns._castDispatcher = castDispatcher
end

local manager = CreateFrame("Frame")
manager:RegisterEvent("NAME_PLATE_UNIT_ADDED")
manager:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
manager:RegisterEvent("PLAYER_TARGET_CHANGED")
manager:RegisterEvent("PLAYER_FOCUS_CHANGED")
manager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
manager:RegisterEvent("RAID_TARGET_UPDATE")
manager:RegisterEvent("PLAYER_REGEN_DISABLED")
manager:RegisterEvent("PLAYER_REGEN_ENABLED")
manager:RegisterEvent("DISPLAY_SIZE_CHANGED")
manager:RegisterEvent("UI_SCALE_CHANGED")

local pendingUnits = {}
ns.pendingUnits = pendingUnits
-- Mouseover-highlight state lives on ns (unified enemy+friendly monitor below).

-- Per-unit event watchers for pending friendly units: per-unit frames avoid the
-- global UNIT_FLAGS firehose.
local pendingWatchers = {}
-- Forward declarations so the two watcher creators can reference each other
local CreatePendingWatcher, CreateEnemyWatcher

-- Watches a friendly/pending unit for becoming attackable (e.g. duel start)
local enemyWatchers = {}
CreatePendingWatcher = function(unit, nameplate)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if not UnitCanAttack("player", u) then return end
        -- Unit became attackable promote to enemy plate
        self:UnregisterAllEvents()
        pendingWatchers[u] = nil
        pendingUnits[u] = nil
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        -- Name-only friendly NPCs are suppressed via a nameplate-keyed name
        -- overlay, not the friendlyPlates[] pool the calls below clean up.
        -- Tear it down here or the old friendly name text is left rendering
        -- on top of the new enemy plate/bar.
        if ns.RemoveFriendlyNPCOverlayForUnit then
            ns.RemoveFriendlyNPCOverlayForUnit(u, currentPlate)
        end
        -- Remove friendly plate WITHOUT restoring Blizzard UF (we'll suppress it as enemy)
        if ns.RemoveFriendlyPlateNoRestore then
            ns.RemoveFriendlyPlateNoRestore(u)
        elseif ns.RemoveFriendlyPlate then
            ns.RemoveFriendlyPlate(u)
        end
        if currentPlate then
            local plate = frameCache:Acquire()
            if not plate._mixedIn then
                Mixin(plate, NameplateFrame)
                plate._mixedIn = true
            end
            ns.plates[u] = plate
            plate:SetUnit(u, currentPlate)
        end
        -- Watch for the reverse transition (enemy friendly, e.g. duel end)
        enemyWatchers[u] = CreateEnemyWatcher(u)
    end)
    return watcher
end

-- Watches a promoted-enemy unit for becoming friendly again (e.g. duel end)
CreateEnemyWatcher = function(unit)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if UnitCanAttack("player", u) then return end
        -- Unit became friendly again tear down enemy plate, restore to pending
        self:UnregisterAllEvents()
        enemyWatchers[u] = nil
        local plate = ns.plates[u]
        if plate then
            if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[u] = nil
        end
        -- Re-add as pending friendly
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        if currentPlate then
            pendingUnits[u] = currentPlate
            pendingWatchers[u] = CreatePendingWatcher(u, currentPlate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(u) end
        end
    end)
    return watcher
end

-- Single shared UNIT_FACTION handler avoids N watchers each registering the global event;
-- dispatches to the correct watcher's OnEvent handler. Only active in the open world.
local factionFrame = CreateFrame("Frame")
local factionFrameActive = false

local function UpdateFactionFrameForZone()
    local _, instanceType = IsInInstance()
    local shouldBeActive = (instanceType == "none" or instanceType == nil)
    if shouldBeActive and not factionFrameActive then
        factionFrame:RegisterEvent("UNIT_FACTION")
        factionFrameActive = true
    elseif not shouldBeActive and factionFrameActive then
        factionFrame:UnregisterEvent("UNIT_FACTION")
        factionFrameActive = false
    end
end

local function RefreshThreatContextAndPlateColors()
    RefreshThreatCache()
    -- Unit tokens are recycled across zone/instance transitions; clear any
    -- stale quest-mob decisions that were made under a different context.
    wipe(questMobCache)
    wipe(ns._questObjText)
    for _, plate in pairs(ns.plates) do
        plate:UpdateHealthColor()
    end
end

factionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
factionFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
factionFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
factionFrame:RegisterEvent("ROLE_CHANGED_INFORM")
factionFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
factionFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- The cached tank-role verdict is spec-derived for the player (effective
-- role), so the player's own spec swap must refresh it; the event also fires
-- for other units' spec updates, which change nothing here.
factionFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
factionFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Never fall through: the dispatch below keys watchers by unit token,
        -- and this event's unit args are not faction-watcher units.
        if unit == "player" then RefreshThreatContextAndPlateColors() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD"
    or event == "ZONE_CHANGED_NEW_AREA"
    or event == "PLAYER_DIFFICULTY_CHANGED"
    or event == "ROLE_CHANGED_INFORM"
    or event == "PLAYER_ROLES_ASSIGNED"
    or event == "GROUP_ROSTER_UPDATE" then
        RefreshThreatContextAndPlateColors()
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            UpdateFactionFrameForZone()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            -- Initial PEW can fire before difficulty/instance data settles.
            C_Timer.After(0.6, function()
                RefreshThreatContextAndPlateColors()
                UpdateFactionFrameForZone()
            end)
        end
        return
    end
    -- UNIT_FACTION dispatch
    if pendingWatchers[unit] then
        local w = pendingWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    elseif enemyWatchers[unit] then
        local w = enemyWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    end
end)
-- Unified mouseover monitor (enemy + friendly). UPDATE_MOUSEOVER_UNIT fires when a mouseover
-- STARTS but never when it clears, so a single shared 0.1s ticker (alive only while a mouseover
-- exists) watches for the mouse leaving. A held mouse button transiently drops the mouseover
-- unit, so in that case we wait for GLOBAL_MOUSE_UP (handled on `manager`) and re-check.
function ns._EnsureMouseoverTicker()
    if ns._mouseoverTicker then return end
    ns._mouseoverTicker = C_Timer.NewTicker(0.1, function()
        if not UnitExists("mouseover") then
            if ns._mouseoverTicker then ns._mouseoverTicker:Cancel(); ns._mouseoverTicker = nil end
            ns._UpdateMouseover()
            if IsMouseButtonDown() then manager:RegisterEvent("GLOBAL_MOUSE_UP") end
        end
    end)
end

-- Drop the highlight tracking if `plate` is the one currently highlighted.
-- Called from both enemy and friendly plate removal.
function ns._ClearMouseoverPlate(plate)
    if ns._currentMouseoverPlate == plate then
        ns._currentMouseoverPlate = nil
        if ns._mouseoverTicker then ns._mouseoverTicker:Cancel(); ns._mouseoverTicker = nil end
    end
    -- Pooled frames recycle: drop the hover-extras flags without a restore
    -- pass (the reuse path re-runs ApplyBorder/ApplyTarget anyway).
    plate._hoverFxOn = nil
    plate._hoverBorderSized = nil
end

function ns._UpdateMouseover()
    local cur = ns._currentMouseoverPlate
    if cur then
        ns.HideHoverEffect(cur)
        ns.ClearHoverExtras(cur)
        ns._currentMouseoverPlate = nil
    end
    if not UnitExists("mouseover") then return end
    local found
    for _, plate in pairs(ns.plates) do
        if plate.unit and UnitIsUnit(plate.unit, "mouseover") then found = plate; break end
    end
    if not found and ns.friendlyPlates then
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.unit and UnitIsUnit(plate.unit, "mouseover") then found = plate; break end
        end
    end
    if found then
        ns.ShowHoverEffect(found)
        ns.ApplyHoverExtras(found)
        ns._currentMouseoverPlate = found
    end
    ns._EnsureMouseoverTicker()
end
-- Baseline lift for friendly plates, applied to BOTH distance settings: Name Distance
-- (name-only) and the friendly plate cog's Distance slider (full plate). Name-only needs it
-- because the friendly module collapses Blizzard's two-point name anchor onto the UnitFrame
-- centre (so long names stop truncating and the guild line has room), landing the name this
-- far below Blizzard's own anchor; the full plate carries the same lift so switching modes
-- does not jump. On ns (local cap).
ns.FRIENDLY_Y_BASE = 26

-- Refresh Y-offset on all visible friendly name-only plates
function ns.RefreshFriendlyNameOnlyOffset()
    local db = p or defaults
    local nameOnly = (db.friendlyNameOnly ~= false)
    local yOff = nameOnly and ((db.friendlyNameOnlyYOffset or 0) + ns.FRIENDLY_Y_BASE) or 0
    for unit, nameplate in pairs(pendingUnits) do
        if nameplate.UnitFrame then
            local uf = nameplate.UnitFrame
            if yOff ~= 0 then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                _npYOffsetState[nameplate] = true
            elseif _npYOffsetState[nameplate] then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
                _npYOffsetState[nameplate] = nil
            end
        end
    end
end

manager:SetScript("OnEvent", function(self, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if not nameplate then return end
        if not UnitCanAttack("player", unit) then
            pendingUnits[unit] = nameplate
            pendingWatchers[unit] = CreatePendingWatcher(unit, nameplate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(unit) end
            -- Color NPC names green in name-only mode
            if ns.TryColorFriendlyNPCName then ns.TryColorFriendlyNPCName(unit, nameplate) end
            -- Hide NPC health bars in name-only mode (show name only)
            if ns.TrySuppressNPCHealthBar then ns.TrySuppressNPCHealthBar(unit, nameplate) end
            -- Ensure the Blizzard UF is visible for name-only friendly plates. Nameplate
            -- frames are recycled; a UF previously used for an enemy may still have alpha 0
            -- or children parented offscreen.
            local db = p or defaults
            if db.friendlyNameOnly ~= false then
                local uf = nameplate.UnitFrame
                if uf then
                    -- Restore alpha in case the recycled UF was suppressed
                    if uf:GetAlpha() < 0.01 then
                        uf:SetAlpha(1)
                    end
                    -- Restore name FontString if it was moved offscreen
                    if uf.name and uf.name:GetParent() ~= uf then
                        uf.name:SetParent(uf)
                    end
                    -- Ensure UF is parented to the nameplate (not hidden frame)
                    if uf:GetParent() ~= nameplate then
                        uf:SetParent(nameplate)
                        uf:SetAlpha(1)
                        uf:Show()
                    end
                    -- Restore RaidTargetFrame if it was moved offscreen by a
                    -- previous enemy plate on this recycled nameplate.
                    if uf.RaidTargetFrame then
                        RestoreFromOffscreen(uf.RaidTargetFrame)
                    end
                end
                -- Apply Y-offset (+ the name-only baseline lift; see
                -- ns.FRIENDLY_Y_BASE)
                local yOff = (db.friendlyNameOnlyYOffset or 0) + ns.FRIENDLY_Y_BASE
                if yOff ~= 0 and nameplate.UnitFrame then
                    nameplate.UnitFrame:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                    nameplate.UnitFrame:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                    _npYOffsetState[nameplate] = true
                end
                -- Font is applied globally via SystemFont_NamePlate override
            end
            return
        end
        pendingUnits[unit] = nil
        local plate = frameCache:Acquire()
        if not plate._mixedIn then
            Mixin(plate, NameplateFrame)
            plate._mixedIn = true
        end
        ns.plates[unit] = plate
        plate:SetUnit(unit, nameplate)
        -- If this plate is the current target, update the cached ref so class power pips
        -- track it immediately: no PLAYER_TARGET_CHANGED fires on recycle for the same target.
        if UnitIsUnit(unit, "target") then
            ns._cachedTargetPlate = plate
        end
        if UnitIsUnit(unit, "focus") then
            ns._cachedFocusPlate = plate
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        questMobCache[unit] = nil
        ns._questObjText[unit] = nil
        -- Restore Blizzard UnitFrame elements so the recycled nameplate is clean
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate then
            RestoreBlizzardFrame(nameplate)
        end
        -- Restore NPC name color if we tinted it
        if nameplate and ns.RestoreFriendlyNPCNameColor then
            ns.RestoreFriendlyNPCNameColor(nameplate)
        end
        -- Restore NPC health bar if we suppressed it
        if nameplate and ns.RestoreNPCHealthBar then
            ns.RestoreNPCHealthBar(nameplate)
        end
        -- Restore name-only Y-offset if we applied one
        if nameplate and _npYOffsetState[nameplate] then
            local uf = nameplate.UnitFrame
            if uf then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
            end
            _npYOffsetState[nameplate] = nil
        end
        pendingUnits[unit] = nil
        if pendingWatchers[unit] then
            pendingWatchers[unit]:UnregisterAllEvents()
            pendingWatchers[unit] = nil
        end
        if enemyWatchers[unit] then
            enemyWatchers[unit]:UnregisterAllEvents()
            enemyWatchers[unit] = nil
        end
        local plate = ns.plates[unit]
        if plate then
            if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
            -- Clear cached refs before release
            if ns._cachedTargetPlate == plate then ns._cachedTargetPlate = nil end
            if ns._cachedFocusPlate  == plate then ns._cachedFocusPlate  = nil end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[unit] = nil
        end
        if ns.RemoveFriendlyPlate then ns.RemoveFriendlyPlate(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- PERF: only update old + new target plates instead of iterating all
        local oldTarget = ns._cachedTargetPlate
        ns._cachedTargetPlate = nil
        -- Find new target plate
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "target") then
                ns._cachedTargetPlate = plate
                break
            end
        end
        if oldTarget and oldTarget.unit then
            oldTarget:ApplyTarget()
            oldTarget:UpdateHealthColor()
        end
        if ns._cachedTargetPlate and ns._cachedTargetPlate ~= oldTarget then
            ns._cachedTargetPlate:ApplyTarget()
            ns._cachedTargetPlate:UpdateHealthColor()
        end
        -- Non-Target Opacity: gaining/losing a target flips every plate's fade state, so this
        -- is the one full-iteration site. Zero cost while off (single compare).
        if ns._ntAlpha < 1 then ns.NT_ApplyAll() end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        -- PERF: only update old + new focus plates instead of iterating all
        local oldFocus = ns._cachedFocusPlate
        ns._cachedFocusPlate = nil
        local focusPct = GetFocusCastHeight()
        -- Find new focus plate
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "focus") then
                ns._cachedFocusPlate = plate
                break
            end
        end
        local function UpdateFocusPlate(plate)
            if not plate or not plate.unit then return end
            plate:UpdateHealthColor()
            if focusPct ~= 100 then
                local castH = GetCastBarHeight()
                if UnitIsUnit(plate.unit, "focus") then
                    castH = math.floor(castH * focusPct / 100 + 0.5)
                end
                ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), castH)
                ns.LayoutCastIcon(plate, castH)
                plate.castSpark:SetHeight(castH)
                plate.kickMarker:SetHeight(castH)
            end
        end
        UpdateFocusPlate(oldFocus)
        if ns._cachedFocusPlate and ns._cachedFocusPlate ~= oldFocus then
            UpdateFocusPlate(ns._cachedFocusPlate)
        end
        -- Non-Target Opacity: only the old and new focus plates change
        -- fade state on a focus swap.
        if ns._ntAlpha < 1 then
            if oldFocus then ns.NT_Apply(oldFocus) end
            if ns._cachedFocusPlate and ns._cachedFocusPlate ~= oldFocus then
                ns.NT_Apply(ns._cachedFocusPlate)
            end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ns._UpdateMouseover()
    elseif event == "GLOBAL_MOUSE_UP" then
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        ns._UpdateMouseover()
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then plate:RefreshNamePosition(true) end
            -- A marker appearing/clearing in a side slot changes the side extents the target
            -- arrows sit outside of, so re-run arrow positioning (no-op without arrows), then
            -- reanchor the container-bearing sides -- same order as the target-swap path.
            ns.PositionArrowsOutsideAuras(plate)
            if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(plate) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateHealthColor()
        end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if ns.ApplyNamePlateClickArea then
            ns.ApplyNamePlateClickArea()
        end
    end
end)

-------------------------------------------------------------------------------
--  SPEC PRESET LOGIN HANDLER
--  Applies the spec-assigned preset on login and spec change, even before the
--  options UI is ever opened. Once the UI opens and RegisterSpecAutoSwitch runs,
--  the framework handler takes over PLAYER_SPECIALIZATION_CHANGED.
-------------------------------------------------------------------------------
do
    local function ApplySpecPresetFromDB()
        if not p then return end

        local specIndex = GetSpecialization and GetSpecialization() or 0
        local specID = specIndex and specIndex > 0
                       and GetSpecializationInfo(specIndex) or nil
        if not specID then return end

        local K_ASSIGN  = "_specAssignments"
        local K_ACTIVE  = "_activePreset"
        local K_DEFAULT = "_specDefaultPreset"
        local K_PRESETS = "_presets"
        local K_SNAP    = "_builtinSnapshot"
        local K_CUSTOM  = "_customPreset"

        local specMap = p[K_ASSIGN]
        if not specMap then return end

        -- Check if any spec assignment exists at all
        local hasAny = false
        for _, specList in pairs(specMap) do
            if next(specList) then hasAny = true; break end
        end
        if not hasAny then return end

        -- Find which preset owns this specID
        local targetKey
        for presetKey, specList in pairs(specMap) do
            if specList[specID] then targetKey = presetKey; break end
        end
        -- Fall back to default preset if no direct match
        if not targetKey and p[K_DEFAULT] then
            targetKey = p[K_DEFAULT]
        end
        if not targetKey then return end

        local currentActive = p[K_ACTIVE] or "ellesmereui"
        if currentActive == targetKey then return end  -- already correct

        -- Apply the snapshot for targetKey
        local presetKeys = ns._displayPresetKeys  -- set below
        if not presetKeys then return end

        if targetKey == "ellesmereui" then
            for _, key in ipairs(presetKeys) do
                local def = ns.defaults[key]
                if type(def) == "table" and def.r then
                    p[key] = { r = def.r, g = def.g, b = def.b }
                else
                    p[key] = def
                end
            end
            p[K_SNAP] = nil
        elseif targetKey == "custom" then
            if p[K_CUSTOM] then
                for _, key in ipairs(presetKeys) do
                    local v = p[K_CUSTOM][key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            p[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            p[key] = v
                        end
                    end
                end
            end
        elseif targetKey:sub(1, 5) == "user:" then
            local name = targetKey:sub(6)
            local snap = p[K_PRESETS] and p[K_PRESETS][name]
            if snap then
                for _, key in ipairs(presetKeys) do
                    local v = snap[key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            p[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            p[key] = v
                        end
                    end
                end
            end
        end

        p[K_ACTIVE] = targetKey
        p[K_SNAP] = nil
    end

    -- Preset keys for the login handler (set once, never changes). Split into two
    -- tables and concatenated to stay under Lua 5.1's per-function constant limit.
    ns._displayPresetKeys = {
        "showBorder", "borderSize", "borderColor", "castBorderSize", "castBorderColor", "targetGlowStyle", "showTargetArrows",
        "showClassPower", "classPowerPos", "classPowerYOffset", "classPowerXOffset", "classPowerScale",
        "classPowerClassColors", "classPowerCustomColor", "classPowerGap",
        "classPowerShape", "classPowerBorder", "classPowerBorderColor", "classPowerBorderSize",
        "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
        "nameYOffset",
        "healthBarHeight", "healthBarWidth", "castBarHeight",
    }
    ns._appendDisplayPresetKeys(ns._displayPresetKeys)

    -- Also handle spec changes that happen before the UI is ever opened
    local specLoginFrame = CreateFrame("Frame")
    specLoginFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specLoginFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then return end
        -- Re-read the profile reference: a spec swap may have changed the active
        -- profile, and _C() color lookups would read the old spec's stale data.
        p = ENP.db.profile
        RefreshThreatCache()
        -- If the framework handler is registered, let it handle this
        if EllesmereUI and EllesmereUI._specSwitchRegistry
           and #EllesmereUI._specSwitchRegistry > 0 then
            return
        end
        ApplySpecPresetFromDB()
        if ns.RefreshAllSettings then ns.RefreshAllSettings() end
    end)

    -- Expose for calling from OnEnable (login time)
    ns._ApplySpecPresetFromDB = ApplySpecPresetFromDB
    _G._ENP_RefreshAllSettings = function() if ns.RefreshAllSettings then ns.RefreshAllSettings() end end
end

local npAddon = ENP
function npAddon:OnInitialize()
    ENP.db = EllesmereUI.Lite.NewDB("EllesmereUINameplatesDB", { profile = defaults })
    p = ENP.db.profile
    ns.db = ENP.db
    -- Non-Target Opacity: derive the cached value at login (no plates exist yet,
    -- so the apply loop no-ops; SetUnit fades new plates as they spawn).
    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
    -- Append SharedMedia textures to runtime tables so SM texture keys resolve at runtime
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames,
            ns.healthBarTextureOrder,
            nil,
            ns.healthBarTextures
        )
    end
end
function npAddon:OnEnable()
    -- Re-read profile: PreSeedSpecProfile may have re-pointed db.profile between OnInitialize and OnEnable.
    p = ENP.db.profile
    RawSetTex = (PP and PP.RawSetTexture) or function(t, v) t:SetTexture(v) end
    SetupAuraCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if ns._ApplySpecPresetFromDB then ns._ApplySpecPresetFromDB() end
    if ns.RangeText_Apply then ns.RangeText_Apply() end
end

-------------------------------------------------------------------------------
--  Nameplate range features: target distance text plus out-of-range plate alpha.
--  Distance text is a range BUCKET on the target's nameplate -- "15+" =
--  beyond the 15yd rung, inside the next longer one. The API exposes no exact enemy distance;
--  the lower bound comes from the shared range engine's spell ladder (EllesmereUI_Range.lua),
--  active only while either feature is enabled. Distance-text anchoring: 5px left of whatever
--  text occupies the Right Text core slot, else just outside the health bar's right edge. Zero
--  cost while both are disabled; enabled, one OnUpdate driver ticks 5x/s. Secret range results
--  are skipped -- fail-open to no text or fade, never an error.
-------------------------------------------------------------------------------
do
    -- Single-table state: this file sits at Lua 5.1's 200-local cap, so the whole feature uses ONE chunk local (RT), everything else as table fields.
    local RT = { acc = 0 }

    function RT.Anchor(plate)
        RT.fs:ClearAllPoints()
        local offX = (p and p.rangeTextOffsetX) or 0
        local offY = (p and p.rangeTextOffsetY) or 0
        local rightEl = GetTextSlot("textSlotRight")
        local anchorTo
        if ns.IsNameElement(rightEl) then
            anchorTo = plate.name
        elseif rightEl == "level" then
            anchorTo = plate.levelText
        elseif rightEl and rightEl ~= "none" then
            local ca = plate._cachedHealthSlots
            if ca then
                for i = 1, ca._count or 0 do
                    local e = ca[i]
                    if e and e.slotKey == "textSlotRight" and e.fs then
                        anchorTo = e.fs
                        break
                    end
                end
            end
        end
        if anchorTo and anchorTo.IsShown and anchorTo:IsShown() then
            RT.fs:SetPoint("RIGHT", anchorTo, "LEFT", -5 + offX, offY)
        else
            RT.fs:SetPoint("LEFT", plate.health or plate, "RIGHT", 5 + offX, offY)
        end
    end

    function RT.Appearance()
        SetFSFont(RT.fs, (p and p.rangeTextSize) or defaults.rangeTextSize, GetNPOutline())
        local c = (p and p.rangeTextColor) or defaults.rangeTextColor
        RT.fs:SetTextColor(c.r, c.g, c.b, 1)
    end

    function RT.Detach()
        RT.plate = nil
        if RT.carrier then
            RT.carrier:Hide()
            RT.carrier:SetParent(nil)
        end
    end

    function RT.Tick()
        local plate = ns._cachedTargetPlate
        if not plate or not plate.unit or not plate:IsShown() then
            if RT.plate then RT.Detach() end
            return
        end
        if plate ~= RT.plate then
            if not RT.carrier then
                RT.carrier = CreateFrame("Frame")
                RT.carrier:SetSize(2, 2)
                RT.fs = RT.carrier:CreateFontString(nil, "OVERLAY")
            end
            RT.carrier:SetParent(plate)
            RT.carrier:SetPoint("CENTER", plate, "CENTER", 0, 0)
            -- Well above the health bar/text frames: with the Right Text slot occupied the
            -- text sits ON the bar, and a low frame level would draw it underneath the fill.
            RT.carrier:SetFrameLevel(plate:GetFrameLevel() + 30)
            RT.plate = plate
            RT.Appearance()
            RT.Anchor(plate)
            RT.carrier:Show()
        end
        -- "0+" (basically melee) shows nothing: the indicator only matters at distance. Queried
        -- as "target" rather than plate.unit -- this is the target's plate by definition, and
        -- the token lets the shared engine serve the QoL text from one cached walk.
        local lower = EllesmereUI.Range_LowerBound("target")
        if lower and lower > 0 then
            RT.fs:SetText(lower .. "+")
            RT.fs:Show()
        else
            RT.fs:Hide()
        end
    end

    -- Round-robin BUDGETED sweep: each range verdict is a multi-C-call probe
    -- walk, so classifying every plate every tick is unbounded in crowded
    -- scenes (40 plates x 5Hz x spell+item probes was thousands of C calls
    -- per second). 8 plates per 0.2s tick = full coverage inside ~1s at a
    -- full plate cap, imperceptible for a fade; small scenes still resolve
    -- every tick. Verdicts come from Range_SweepBeyond (per-unit short-TTL
    -- cache; never touches the crosshair/QoL single-slot target caches).
    -- Melee note: at cutoff 5 verdicts rely on the protection-gated item
    -- walk, so in instanced combat the fade can degrade to "no fade" for
    -- melee specs -- deliberate fail-open, never a blocked action.
    function RT.FadeTick()
        local customCutoff = p and p.outOfRangeMode == "custom" and p.outOfRangeCustomRange
        local cutoff = EllesmereUI.Range_GetAttackCutoff(customCutoff)
        local q = RT.fadeQ
        if not q then q = {}; RT.fadeQ = q end
        if not RT.fadeIdx or RT.fadeIdx > #q then
            -- New cycle: snapshot the live plate set (reused table, one wipe
            -- per cycle). Plates that detach mid-cycle are re-checked below.
            wipe(q)
            for _, plate in pairs(ns.plates) do q[#q + 1] = plate end
            RT.fadeIdx = 1
        end
        local budget = 8
        while RT.fadeIdx <= #q and budget > 0 do
            local plate = q[RT.fadeIdx]
            RT.fadeIdx = RT.fadeIdx + 1
            budget = budget - 1
            local unit = plate.unit
            if unit and ns.plates[unit] == plate then
                local beyond
                -- Cleanly-non-attackable plates (friendly/neutral NPCs) can
                -- never answer an attack-range probe; skip the whole walk.
                -- Only a READABLY-false flag skips -- a secret answer falls
                -- through to the probes, whose own gates fail open.
                local okAtt, att = pcall(UnitCanAttack, "player", unit)
                local skip = okAtt and not (issecretvalue and issecretvalue(att)) and att == false
                if not skip then
                    beyond = EllesmereUI.Range_SweepBeyond(unit, cutoff)
                end
                local alpha = beyond == true and ns._oorAlpha or 1
                if (plate._oorCurAlpha or 1) ~= alpha then
                    plate._oorCurAlpha = alpha
                    ns.NT_Apply(plate)
                end
            end
        end
    end

    function RT.ResetFade()
        -- Drop the round-robin cursor and its plate snapshot too: a disable
        -- mid-cycle must not pin recycled plates in the reused queue.
        if RT.fadeQ then wipe(RT.fadeQ) end
        RT.fadeIdx = nil
        for _, plate in pairs(ns.plates) do
            if plate._oorCurAlpha then
                plate._oorCurAlpha = nil
                ns.NT_Apply(plate)
            end
        end
    end

    -- Options: re-apply font/color/anchor on the live attachment.
    ns.RangeText_Refresh = function()
        if RT.plate and RT.fs then
            RT.Appearance()
            RT.Anchor(RT.plate)
        end
    end

    ns.RangeText_Apply = function()
        local alpha = tonumber(p and p.outOfRangeAlpha) or defaults.outOfRangeAlpha
        if alpha < 0 then alpha = 0 elseif alpha > 100 then alpha = 100 end
        ns._oorAlpha = alpha / 100
        local textEnabled = p and p.rangeTextEnabled
        ns._oorFadeEnabled = ((p and p.outOfRangeMode) or defaults.outOfRangeMode) ~= "disabled" and ns._oorAlpha < 1
        local fadeEnabled = ns._oorFadeEnabled
        if textEnabled or fadeEnabled then
            if not RT.drv then
                RT.drv = CreateFrame("Frame")
                RT.drv:Hide()
                RT.drv:SetScript("OnUpdate", function(_, dt)
                    RT.acc = RT.acc + dt
                    if RT.acc < 0.2 then return end
                    RT.acc = 0
                    if p and p.rangeTextEnabled then RT.Tick() end
                    if ns._oorFadeEnabled then RT.FadeTick() end
                end)
            end
            -- Ladder builds and invalidation live in the shared range engine.
            EllesmereUI.Range_SetActive("npRange", true)
            RT.drv:Show()
        else
            EllesmereUI.Range_SetActive("npRange", false)
            if RT.drv then RT.drv:Hide() end
        end
        if not textEnabled then RT.Detach() end
        if not fadeEnabled then RT.ResetFade() end
    end

end

-------------------------------------------------------------------------------
--  Hide Enemy Nameplates Out of Combat (EXTRAS): drives nameplateShowEnemies,
--  the same CVar behind Blizzard's combat-legal "Show Enemy Name Plates"
--  keybind, so plates flip cleanly at the combat edges. The combat events are
--  registered only while the setting is on (zero cost off); disabling the
--  setting restores plates ON only if this feature ever hid them. All state
--  lives on ns -- this chunk is at the 200-local cap.
-------------------------------------------------------------------------------
ns._oocPlatesCtl = CreateFrame("Frame")
ns.ApplyOOCPlates = function()
    local ctl = ns._oocPlatesCtl
    local on = p and p.hideEnemyPlatesOOC == true
    if on then
        ctl:RegisterEvent("PLAYER_REGEN_DISABLED")
        ctl:RegisterEvent("PLAYER_REGEN_ENABLED")
        ctl:RegisterEvent("PLAYER_ENTERING_WORLD")
        ns._oocPlatesOwned = true
        -- Read-guarded: RefreshAllSettings calls this on every nameplate settings
        -- change, and a redundant SetCVar broadcasts CVAR_UPDATE to the whole UI.
        local want = InCombatLockdown() and "1" or "0"
        if GetCVar("nameplateShowEnemies") ~= want then
            SetCVar("nameplateShowEnemies", want)
        end
    else
        ctl:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ctl:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ctl:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if ns._oocPlatesOwned then
            ns._oocPlatesOwned = nil
            SetCVar("nameplateShowEnemies", "1")
        end
    end
end
ns._oocPlatesCtl:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ns.ApplyOOCPlates()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        SetCVar("nameplateShowEnemies", "1")
    elseif not InCombatLockdown() then
        -- REGEN_ENABLED, or a world entry that lands out of combat.
        SetCVar("nameplateShowEnemies", "0")
    end
end)
ns._oocPlatesCtl:RegisterEvent("PLAYER_LOGIN")


