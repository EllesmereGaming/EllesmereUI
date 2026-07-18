local addon, ns = ...

local ENP = EllesmereUI.Lite.NewAddon("EllesmereUINameplates")

-- Profile alias: set in OnInitialize, nil before that.
-- Getters fall back to defaults when p is nil (brief window before init).
local p

local pairs, ipairs, type = pairs, ipairs, type
local PP = EllesmereUI.PP
-- Pre-hook SetTexture original for pooled aura-slot icons (snap-disabled
-- once at creation, so the pixel-snap hook is pure overhead for them).
-- Upgraded to PP.RawSetTexture in OnEnable; starts as a plain wrapper so
-- it is never nil.
local RawSetTex = function(t, v) t:SetTexture(v) end
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local C_UnitAuras = C_UnitAuras
local C_UnitAuras_GetAuraAppDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local C_UnitAuras_GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
-- Permanent / no-duration auras (enemy buffs in M+, until-dispelled debuffs)
-- return a degenerate (0,0) duration object whose armed CooldownFrame strobes:
-- the client internally shows the reversed swipe then self-hides on every aura
-- rescan, and Lua show/hide gating CANNOT stop it. Mask it with ALPHA (which is
-- orthogonal to the client's internal show/hide) so the strobe renders
-- invisibly -- the exact fix used at the raid-frame aura sites. IsZero() may be
-- a secret boolean for enemy auras, so it is only ever fed to SetAlphaFromBoolean,
-- never branched on. baseAlpha is 1 (the cd frame's normal opacity); the stack
-- count lives on a separate carrier so it survives the mask.
local function NP_ArmAuraCooldown(cd, durObj)
    if not (cd and durObj and cd.SetCooldownFromDurationObject) then return false end
    cd:SetCooldownFromDurationObject(durObj)
    if durObj.IsZero and cd.SetAlphaFromBoolean then
        cd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
    elseif cd.SetAlpha then
        cd:SetAlpha(1)
    end
    return true
end
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
    -- The `defaults` local is declared below this function, so it is not in
    -- scope here; fall back to the literal default font path.
    return (p and p.font) or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
end
local function GetNPOutline()
    -- Already slug-gated at the source (GetFontOutlineFlag); SetFSFont also
    -- gates the explicit-flag path, so aura literals are covered too.
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("nameplates")) or "OUTLINE, SLUG"
end
local function GetNPUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("nameplates")
end
local function SetFSFont(fs, size, flags)
  if not (fs and fs.SetFont) then return end
  local f = flags or GetNPOutline()
  -- "Never Show Slug": gate the explicit-flag path here so hardcoded aura
  -- "OUTLINE, SLUG" literals drop the slug too (body text is already gated).
  if EllesmereUI and EllesmereUI.SlugFlag then f = EllesmereUI.SlugFlag(f) end
  -- 12.0.7: drop shadows only render from a FontObject; prime before SetFont.
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

-- External weak-keyed table for nameplate Y-offset state (never write custom
-- keys onto Blizzard C_NamePlate frames -- causes taint).
local _npYOffsetState = setmetatable({}, { __mode = "k" })

-- Constant table for health text bar slots (hoisted to file scope to avoid
-- per-call allocation inside UpdateHealthValues).
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

-- Overflow for _displayPresetKeys: defined outside the main function
-- scope to stay under Lua 5.1's 200-local limit.
function ns._appendDisplayPresetKeys(t)
    for _, k in ipairs({
        "topSlotSize", "topSlotXOffset", "topSlotYOffset", "topSlotRaiseStrata",
        "rightSlotSize", "rightSlotXOffset", "rightSlotYOffset", "rightSlotRaiseStrata",
        "leftSlotSize", "leftSlotXOffset", "leftSlotYOffset", "leftSlotRaiseStrata",
        "toprightSlotSize", "toprightSlotXOffset", "toprightSlotYOffset", "toprightSlotGrowth", "toprightSlotRaiseStrata",
        "topleftSlotSize", "topleftSlotXOffset", "topleftSlotYOffset", "topleftSlotGrowth", "topleftSlotRaiseStrata",
        "textSlotTopSize", "textSlotTopXOffset", "textSlotTopYOffset",
        "textSlotRightSize", "textSlotRightXOffset", "textSlotRightYOffset",
        "textSlotLeftSize", "textSlotLeftXOffset", "textSlotLeftYOffset",
        "textSlotCenterSize", "textSlotCenterXOffset", "textSlotCenterYOffset",
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
        "castNameSize", "castNameColor", "castTargetSize", "castTargetClassColor", "castTargetColor",
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
        "showCastLockoutAsCrowdControl",
        "castIconOffsetX", "castIconOffsetY",
        "targetGlowEllesmereUI", "targetGlowBorderColor", "targetGlowHighlight", "targetBorderColor",
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
    -- When on, the empty portion of the bar shows the focus texture at full
    -- opacity instead of the dimmed (30%) default, so the pattern reads evenly.
    focusOverlayFullBgAlpha = false,
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
    -- When on, the empty portion of the bar shows the target texture at full
    -- opacity instead of the dimmed (30%) default, so the pattern reads evenly.
    targetOverlayFullBgAlpha = false,
    hoverOverlayTexture = "none",
    caster  = { r = 0.231, g = 0.510, b = 0.965 },
    miniboss = { r = 0.518, g = 0.243, b = 0.984 },
    boss = { r = 0.518, g = 0.243, b = 0.984 },
    enemyInCombat = { r = 0.800, g = 0.137, b = 0.137 },
    -- "Mini Enemies" (non-elite trash) has NO static default: when unset it views
    -- the user's enemyInCombat color, so it starts identical to "Enemies" and the
    -- user customizes from there (see GetReactionColor).
    -- Mini Coloring M+ Only: on = restrict the Mini Enemies color to 5-man
    -- dungeons; off = apply it everywhere (default; see GetReactionColor).
    miniColoringMPlusOnly = false,
    -- Full Coloring M+ Only (inline cog on Enemy Types): off by default.
    -- On: outside 5-man dungeons, the mob-type special colors (Mini Enemies,
    -- Spell Casters, Mini-Bosses, Bosses) collapse into the single flat
    -- owBasicColor; Neutral keeps its own color (see GetReactionColor).
    -- Keys keep their original owBasic* names (formerly "Open World Basic
    -- Coloring", which gated on any instance instead of dungeons).
    owBasicColoring = false,
    owBasicColor = { r = 0.800, g = 0.137, b = 0.137 },
    darkenEnemiesOOC = true,
    tankHasAggro = { r = 0.05, g = 0.82, b = 0.62 },
    tankHasAggroEnabled = false,
    -- When on, the tank has-aggro color overrides the Mini-Boss and Caster
    -- colors (promotes it above priority step 7); off = it stays low priority.
    tankHasAggroOverrideMobType = false,
    -- When on (default), the tank has-aggro color overrides the Boss color; off =
    -- the has-aggro color is held just below the Boss color in priority.
    tankHasAggroOverrideBoss = true,
    classicTankAggro = false,
    tankLosingAggro = { r = 0.81, g = 0.72, b = 0.19 },
    tankNoAggro = { r = 1.00, g = 0.22, b = 0.17 },
    dpsNearAggro = { r = 0.81, g = 0.72, b = 0.19 },
    dpsHasAggro = { r = 1.00, g = 0.50, b = 0.00 },
    offTankAggro = { r = 0.188, g = 0.761, b = 0.812 },
    offTankAggroEnabled = true,
    dpsNoAggro = { r = 0.35, g = 0.75, b = 0.35 },
    dpsNoAggroEnabled = false,
    -- When on, the DPS/healer No Aggro color overrides the Mini-Boss color
    -- (promotes it above priority step 7); off (default) = it stays low priority.
    dpsNoAggroOverrideMiniBoss = false,
    -- When on, the DPS/healer No Aggro color overrides the Caster color (promotes
    -- it above priority step 8); off (default) = Casters keep their own color.
    dpsNoAggroOverrideCaster = false,
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
    -- Per-element icon spacing (gap between icons). All default to the legacy
    -- auraSpacing value (2) so existing users are completely unaffected.
    debuffSpacing = 2,
    buffSpacing = 2,
    ccSpacing = 2,
    -- Cropped icons: trim the icon top/bottom so it becomes rectangular
    -- (height = 80% of width), mirroring the Unit Frames "Cropped Icons"
    -- option. Off by default so existing layouts are unchanged.
    debuffCropIcons = false,
    buffCropIcons = false,
    ccCropIcons = false,
    debuffIconSize = 26,
    buffIconSize = 24,
    buffTextSize = 12,
    buffTextColor = { r = 1, g = 1, b = 1 },
    ccIconSize = 24,
    ccTextSize = 12,
    ccTextColor = { r = 1, g = 1, b = 1 },
    targetGlowStyle = "ellesmereui",
    -- Target "Border Color" tint (default white), applied to the custom border
    -- when the Border Color toggle is on. The three multi-toggle keys
    -- (targetGlowEllesmereUI / targetGlowBorderColor / targetGlowHighlight) are
    -- intentionally NOT defaulted here: they stay nil so the getters can
    -- live-convert from the legacy targetGlowStyle string.
    targetBorderColor = { r = 1, g = 1, b = 1 },
    -- Target "Glow Color" + opacity for the EUI background glow (default = the
    -- signature blue at full opacity).
    targetGlowColor = { r = 0.4117, g = 0.6667, b = 1.0 },
    targetGlowAlpha = 1.0,
    -- Target Highlight wash color/opacity (defaults match the formerly
    -- hardcoded white at 30%, so existing users are unaffected).
    targetHighlightColor = { r = 1, g = 1, b = 1 },
    targetHighlightAlpha = 0.20,
    nameRaidMarkerEnabled = false,
    nameRaidMarkerSize = 14,
    raidMarkerPos = "topright",
    raidMarkerSize = 24,
    classificationSlot = "topleft",
    -- Rare/Quest Indicator "Show In Instances" (slot cog): lifts the
    -- open-world-only gates in UpdateClassification + IsQuestMob.
    classificationShowInInstances = false,
    rareEliteIconSize = 20,
    castBarHeight = 17,
    castBarOffsetY = 0,
    castOverlayEnabled = false,
    hideEnemyNameWhileCasting = false,
    castNameSize = 10,
    castNameColor = { r = 1, g = 1, b = 1 },
    castNameOffsetX = 0,
    castNameOffsetY = 0,
    -- Side the spell name occupies on the cast bar text line: "left" | "right" | "center" | "none".
    -- Default "left" reproduces the historical fixed layout.
    castNameSide = "left",
    -- Spell name truncation: width as a % of the cast bar width (default 42 reproduces
    -- the historical castW*0.42 clamp) and a wrap toggle (off = single line + ellipsis).
    castNameWidthPct = 42,
    castNameWrap = false,
    castTargetSize = 10,
    castTargetClassColor = true,
    castTargetColor = { r = 1, g = 1, b = 1 },
    castTargetOffsetX = 0,
    castTargetOffsetY = 0,
    -- Side the spell target occupies: "left" | "right" | "center" | "none". Default "right".
    castTargetSide = "right",
    -- Spell target truncation: % of cast bar width (default 42 = historical clamp) + wrap toggle.
    castTargetWidthPct = 42,
    castTargetWrap = false,
    showCastTimer = true,
    -- Side the cast timer occupies when shown: "left" | "right". Visibility stays governed
    -- by showCastTimer (the dropdown's "None" option simply sets showCastTimer = false).
    castTimerSide = "right",
    castTimerSize = 10,
    castTimerColor = { r = 1, g = 1, b = 1 },
    castTimerOffsetX = 0,
    castTimerOffsetY = 0,
    -- Enemy unit name truncation. Width is a % of the name's computed (bar-derived)
    -- width, so 100 reproduces the historical behaviour exactly (full available width
    -- minus raid-marker / classification reserves); lower = narrower / more truncation.
    -- Wrap off = single line + ellipsis; on = up to two lines.
    enemyNameWidthPct = 100,
    enemyNameWrap = false,
    targetScale = 100,
    showAllDebuffs = false,
    maxDebuffs = 5,
    showBorder = true,
    borderSize = 1,
    borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    -- "Wrap Border Around Castbar": when on, the main health border extends down
    -- to enclose the cast bar while the enemy is casting, forming one unified
    -- border around the health + cast stack. OFF by default and fully additive --
    -- nothing in the wrap machinery runs unless this is enabled.
    wrapBorderCastbar = false,
    -- Custom border (opt-in) -- reuses the shared EllesmereUI border engine
    -- (same system as Unit Frames, full SharedMedia support). When
    -- customBorderEnabled is false (the default) NONE of these keys are read
    -- and the simple border above is rendered exactly as before, so existing
    -- users see zero change.
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
    bgAlpha = 1.0,
    bgColor = { r = 0.12, g = 0.12, b = 0.12 },
    hoverColor = { r = 1, g = 1, b = 1 },
    hoverAlpha = 0.3,
    -- When on, the empty portion of the bar shows the hover texture at full
    -- opacity instead of the dimmed (30%) default, so the pattern reads evenly.
    hoverOverlayFullBgAlpha = false,
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
    -- Core Text Positions: slot-based colors
    textSlotTopColor = { r = 1, g = 1, b = 1 },
    textSlotRightColor = { r = 1, g = 1, b = 1 },
    textSlotLeftColor = { r = 1, g = 1, b = 1 },
    textSlotCenterColor = { r = 1, g = 1, b = 1 },
    -- Bar texture overlay
    healthBarTexture = "none",
    castBarTexture = "none",
}
local BAR_W = 150
ns.defaults = defaults
ns.BAR_W = BAR_W
local CAST_H = 17

-- Custom nameplate border (opt-in) -----------------------------------------
-- Register per-style/size offset defaults with the shared border engine,
-- mirroring the Unit Frames registration. Wrapped in do/end so no file-scope
-- locals leak (this file runs near Lua 5.1's main-chunk local cap).
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

-- Custom border apply helpers. They read the enemy profile `p` (friendly
-- plates intentionally mirror the enemy border settings 1:1) and route through
-- the shared EllesmereUI border engine. The custom border lives on a dedicated
-- child frame we own (plate._customBorder), so it never collides with the
-- simple PP.CreateBorder that decorates plate.health directly. Defined as ns
-- fields (not new file-scope locals) to respect the local cap.
function ns.IsCustomBorderEnabled()
    local v = p and p.customBorderEnabled
    if v == nil then return defaults.customBorderEnabled end
    return v
end
function ns.ApplyCustomBorderStyle(plate)
    if not plate or not plate.health then return end
    if not (EllesmereUI and EllesmereUI.ApplyBorderStyle) then return end
    local tex    = (p and p.customBorderTexture) or defaults.customBorderTexture
    local sz     = (p and p.customBorderSize) or defaults.customBorderSize
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
    -- Nameplate health bars flatten render layers, which voids inter-frame
    -- ordering -- a textured backdrop border drawn on the BORDER draw layer
    -- would be clipped by the ARTWORK health fill. Lift the border onto an
    -- explicit MEDIUM strata (the same flatten escape the plate uses for its
    -- text and aura layers) so it renders above the fill. Strata is set before
    -- ApplyBorderStyle so the backdrop child it may create inherits it; setting
    -- it again on reuse re-propagates to that child.
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
do
    local TB = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
    ns.healthBarTextures = {
        ["none"]          = nil,
        ["melli"]         = TB .. "melli.tga",
        ["beautiful"]     = TB .. "beautiful.tga",
        ["plating"]       = TB .. "plating.tga",
        ["atrocity"]      = TB .. "atrocity.tga",
        ["divide"]        = TB .. "divide.tga",
        ["glass"]         = TB .. "glass.tga",
        ["fade-right"]    = TB .. "fade-right.tga",
        ["thin-line-top"]    = TB .. "thin-line-top.tga",
        ["thin-line-bottom"] = TB .. "thin-line-bottom.tga",
        ["fade"]          = TB .. "fade.tga",
        ["gradient-lr"]   = TB .. "gradient-lr.tga",
        ["gradient-rl"]   = TB .. "gradient-rl.tga",
        ["gradient-bt"]   = TB .. "gradient-bt.tga",
        ["gradient-tb"]   = TB .. "gradient-tb.tga",
        ["matte"]         = TB .. "matte.tga",
        ["sheer"]         = TB .. "sheer.tga",
        ["blinkii-diamonds"] = TB .. "blinkii-diamonds.tga",
        ["kringel-window"]   = TB .. "kringel-window.tga",
    }
    ns.healthBarTextureOrder = {
        "none", "melli", "atrocity",
        "fade", "fade-right",
        "thin-line-top", "thin-line-bottom",
        "beautiful", "plating",
        "divide", "glass",
        "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
        "matte", "sheer",
        "blinkii-diamonds", "kringel-window",
    }
    ns.healthBarTextureNames = {
        ["none"]        = "None",
        ["melli"]       = "Melli (ElvUI)",
        ["beautiful"]   = "Beautiful",
        ["plating"]     = "Plating",
        ["atrocity"]    = "Atrocity",
        ["divide"]      = "Divide",
        ["glass"]       = "Glass",
        ["fade-right"]  = "Fade Right",
        ["thin-line-top"]    = "Thin Line Top",
        ["thin-line-bottom"] = "Thin Line Bottom",
        ["fade"]        = "Fade",
        ["gradient-lr"] = "Gradient Right",
        ["gradient-rl"] = "Gradient Left",
        ["gradient-bt"] = "Gradient Up",
        ["gradient-tb"] = "Gradient Down",
        ["matte"]       = "Matte",
        ["sheer"]       = "Sheer",
        ["blinkii-diamonds"] = "Blinkii Diamonds",
        ["kringel-window"]   = "Kringel Window",
    }
end

local function ApplyHealthBarTexture(plate)
    local health = plate.health
    if not health then return end
    local texKey = (p and p.healthBarTexture) or defaults.healthBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    health:SetStatusBarTexture(path)
end
ns.ApplyHealthBarTexture = ApplyHealthBarTexture

-- Cast bar texture -- mirrors ApplyHealthBarTexture exactly, using the same
-- texture set (EUI built-ins + SharedMedia, appended into ns.healthBarTextures
-- at options-build time). Attached to ns (no new file-scope local).
function ns.ApplyCastBarTexture(plate)
    local cast = plate.cast
    if not cast then return end
    local texKey = (p and p.castBarTexture) or defaults.castBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(ns.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    cast:SetStatusBarTexture(path)
    -- The uninterruptible overlay is a flat WHITE8x8 drawn over the fill (tinted
    -- grey, shown via SetAlphaFromBoolean), so it would hide the fill texture on
    -- uninterruptible casts. Give it the same texture so the pattern shows
    -- through in the uninterruptible colour. The per-cast SetVertexColor (grey)
    -- is re-applied on every cast start, so changing the texture here is safe.
    if plate.castBarOverlay then
        plate.castBarOverlay:SetTexture(path)
    end
end

function ns.ApplyAbsorbStyle(plate)
    local style = (p and p.absorbStyle) or defaults.absorbStyle
    -- blizzard/striped/clean live in NP_ABSORB_STYLE_TEX; the stripe keys
    -- (shared with the Focus Texture dropdown) resolve via ResolveOverlayTexPath.
    local tex   = ns.NP_ABSORB_STYLE_TEX[style] or ns.ResolveOverlayTexPath(style) or ns.NP_ABSORB_STYLE_TEX.blizzard
    -- Opacity applies to every style. absorbAlpha (0-100) is the single source
    -- of truth once the user touches the slider or picks a style; until then we
    -- fall back to the original per-style defaults so existing profiles are
    -- unchanged.
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

-- Pandemic glow style definitions (replaces LibCustomGlow)
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
-- Expose the nameplate glow-style list cross-addon so other modules (e.g. the
-- CDM "Apply Pandemic Glow to all" sync) can translate a style by NAME instead
-- of copying a raw index. Nameplates order their styles differently from CDM
-- (their list omits "Custom Shape Glow"), so a raw index means a different
-- style on each side.
if EllesmereUI then EllesmereUI.NameplatePandemicGlowStyles = PANDEMIC_GLOW_STYLES end

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
-- Namespaced (not file-scope locals) to stay under this file's Lua 5.1 200-local
-- cap; both still close over the p / defaults upvalues.
function ns.GetPandemicGlowBackground()
    return p and p.pandemicGlowBackground == true
end
function ns.GetPandemicGlowBackgroundColor()
    local c = (p and p.pandemicGlowBackgroundColor) or defaults.pandemicGlowBackgroundColor
    return c.r or 0, c.g or 0, c.b or 0
end

-- Dispellable buff glow: taint-safe detection via GetAuraDispelTypeColor
do
    -- Dispel type IDs from SpellDispelType (DB2)
    local DISPEL_NONE    = 0
    local DISPEL_MAGIC   = 1
    local DISPEL_CURSE   = 2
    local DISPEL_DISEASE = 3
    local DISPEL_POISON  = 4
    local DISPEL_ENRAGE  = 9

    -- Build a color curve for taint-safe dispel type detection.
    -- Magic → blue, Enrage → red, all others → transparent.
    -- Step curve: each point covers its exact ID; fill gaps with transparent.
    local dispelDetectionCurve
    if C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType then
        dispelDetectionCurve = C_CurveUtil.CreateColorCurve()
        dispelDetectionCurve:SetType(Enum.LuaCurveType.Step)
        local clear = CreateColor(0, 0, 0, 0)
        local blue  = CreateColor(0.2, 0.6, 1.0, 1)
        local red   = CreateColor(1.0, 0.2, 0.2, 1)
        dispelDetectionCurve:AddPoint(DISPEL_NONE,    clear)
        dispelDetectionCurve:AddPoint(DISPEL_MAGIC,   blue)
        dispelDetectionCurve:AddPoint(DISPEL_CURSE,   clear)
        dispelDetectionCurve:AddPoint(DISPEL_DISEASE, clear)
        dispelDetectionCurve:AddPoint(DISPEL_POISON,  clear)
        dispelDetectionCurve:AddPoint(DISPEL_ENRAGE,  red)
    end

    local _, playerClass = UnitClass("player")
    -- { spellID, category ("Magic", "Enrage", or "Both"), requiredClass or nil, requiredTalent or nil }
    local OFFENSIVE_DISPEL_SPELLS = {
        { 370,    "Magic",  nil       },  -- Purge (Shaman)
        { 378773, "Magic",  nil       },  -- Greater Purge (Shaman)
        { 528,    "Magic",  nil       },  -- Dispel Magic (Priest)
        { 278326, "Magic",  nil       },  -- Consume Magic (Demon Hunter)
        { 19505,  "Magic",  "WARLOCK" },  -- Devour Magic (Felhunter)
        { 19801,  "Both",   nil       },  -- Tranquilizing Shot (Hunter)
        { 2908,   "Enrage", nil       },  -- Soothe (Druid)
        { 30449,  "Magic",  nil       },  -- Spellsteal (Mage)
        { 115078, "Enrage", "MONK", 450432 },  -- Paralysis (w/ Pressure Points talent)
    }
    local canDispelMagic, canDispelEnrage = false, false
    local function RebuildDispelTypes()
        canDispelMagic, canDispelEnrage = false, false
        for _, entry in ipairs(OFFENSIVE_DISPEL_SPELLS) do
            local spellID, cat, reqClass, reqTalent = entry[1], entry[2], entry[3], entry[4]
            if reqClass and playerClass ~= reqClass then
                -- skip: wrong class for this spell
            else
                local known = false
                if reqClass and not reqTalent then
                    -- Class-gated pet spell: check via pet bank
                    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
                        and Enum and Enum.SpellBookSpellBank then
                        known = C_SpellBook.IsSpellKnownOrInSpellBook(spellID, Enum.SpellBookSpellBank.Pet)
                    elseif IsSpellKnown then
                        known = IsSpellKnown(spellID, true)
                    end
                elseif reqTalent then
                    -- Talent-gated: check if the talent is known
                    if IsPlayerSpell then
                        known = IsPlayerSpell(reqTalent)
                    elseif IsSpellKnown then
                        known = IsSpellKnown(reqTalent, false)
                    end
                elseif C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
                    known = C_SpellBook.IsSpellKnownOrInSpellBook(spellID)
                elseif IsSpellKnown then
                    known = IsSpellKnown(spellID, false)
                end
                if known then
                    if cat == "Magic" or cat == "Both" then canDispelMagic = true end
                    if cat == "Enrage" or cat == "Both" then canDispelEnrage = true end
                end
            end
        end
    end
    local dispelFrame = CreateFrame("Frame")
    dispelFrame:RegisterEvent("SPELLS_CHANGED")
    dispelFrame:RegisterEvent("UNIT_PET")
    dispelFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PET" and unit ~= "player" then return end
        RebuildDispelTypes()
    end)
    RebuildDispelTypes()

    -- Returns: shouldGlow, typeColor (ColorMixin or nil)
    -- All aura fields on enemy nameplates are secret in Midnight.
    -- The typeColor's alpha (from the detection curve) drives visibility:
    -- Magic/Enrage → alpha 1 (visible), everything else → alpha 0 (hidden).
    -- Secret RGBA values pass safely through C visual functions (SetAlpha,
    -- SetVertexColor) without Lua ever testing or comparing them.
    ns.CanDispelAura = function(unit, aura)
        if not (canDispelMagic or canDispelEnrage) then return false end
        local typeColor
        if dispelDetectionCurve and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
            local ok, c = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, aura.auraInstanceID, dispelDetectionCurve)
            if ok and c then typeColor = c end
        end
        return true, typeColor
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
    ns.GetDispelGlowColor = function(typeColor)
        local useType = (p and p.dispelGlowUseTypeColor)
        if useType == nil then useType = defaults.dispelGlowUseTypeColor end
        if useType and typeColor then
            return typeColor:GetRGBA()  -- secret values pass through to visual ops
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
-- "Make Icon Part of the Bar": when true (and the icon is shown), the spell
-- icon is counted inside the cast bar's width -- the bar is shifted right and
-- narrowed by the icon width so the icon (anchored to the bar's left edge)
-- sits inside the footprint. Default false (off for everyone, no migration).
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

-- Position + size the cast bar within `footprintW`, accounting for the
-- icon-in-width setting. A full-size icon spans the health band too (which the
-- cast bar cannot reserve), so in-width applies only at normal size. Left icon:
-- shift the bar right into the reserved gap. Right icon: keep the left edge
-- fixed and narrow only the right edge. iconW uses the icon's rendered size
-- (castH * icon scale) so a scaled icon reserves the right amount of space.
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
    -- Cast Bar Y Offset: positive = up, negative = down (default 0 = unchanged).
    -- 0 is truthy in Lua, so the `or` fallback only fires when the key is nil.
    local offsetY = (p and p.castBarOffsetY) or defaults.castBarOffsetY
    -- Snap to a whole number of PHYSICAL pixels at the PLATE's own scale (not
    -- UIParent's -- nameplates have their own scale stack), so the gap between the
    -- health bottom and cast top stays a constant integer-pixel count instead of
    -- oscillating +/-1px as the plate slides to fractional screen positions.
    if offsetY ~= 0 and PP then
        local plateES = plate:GetEffectiveScale()
        local onePx = (plateES and plateES > 0) and (PP.perfect / plateES) or (PP.mult or 1)
        offsetY = math.floor(offsetY / onePx + 0.5) * onePx
    end
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", shiftX, offsetY)
end

-- Size + anchor the cast spell icon for the current side / full-size settings.
-- Always a square. Normal: cast-bar height, hangs off the bar's left (default)
-- or right edge, top-aligned with the cast bar, scaled by the Scale setting.
-- Full: a (healthH + castH) square anchored to a cast BOTTOM corner -- the
-- zero-gap bar stack lands the top edge flush with the health top -- with scale
-- forced to 1 so it stays flush to both bar edges. The icon's frame level is
-- fixed at creation (health+1), so this never touches it. Clean profile
-- numbers only (no secret values).
function ns.LayoutCastIcon(plate, castH)
    local icon = plate.castIconFrame
    local onRight = ns.GetCastIconOnRight()
    local xOff = (p and p.castIconOffsetX) or defaults.castIconOffsetX
    local yOff = (p and p.castIconOffsetY) or defaults.castIconOffsetY
    icon:ClearAllPoints()
    if ns.GetCastIconFullSize() then
        local side = GetHealthBarHeight() + castH
        icon:SetScale(1)
        -- Link the icon's three shared edges DIRECTLY to the bar edges instead of
        -- deriving them from its own size: top = health top, bottom = cast bottom,
        -- inner side = the bars' outer edge. Anchored to the exact same points the
        -- health/cast borders use, those edges resolve to identical positions and
        -- pixel-snap together, so they stay flush and shift as ONE unit under
        -- nameplate motion instead of each rounding independently. SetWidth keeps
        -- the icon square (its height is fixed by the top/bottom anchors = side).
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

-- How far the cast icon protrudes past the bar edge on its side, plus that side
-- ("left"/"right"). The target arrow + side-slot core icons reserve this so
-- they never land under the icon. Returns 0 for the legacy default (left,
-- normal) and for in-width-tucked icons, so existing layouts are unchanged.
-- All inputs are clean profile numbers, safe to add.
-- The optional `plate` only matters for the full-size icon: that icon is a child
-- of the cast bar and only renders during a cast, so its (large) reserve is
-- gated on the plate's cast bar being shown. A settings-only query (no plate)
-- assumes the space is reserved.
function ns.GetCastIconReserve(plate)
    if not GetShowCastIcon() then return 0, nil end
    local onRight = ns.GetCastIconOnRight()
    local side = onRight and "right" or "left"
    if ns.GetCastIconFullSize() then
        -- Only reserve the full-size icon's footprint while it is actually
        -- visible (cast bar up), so side elements sit flush against the bar
        -- when nothing is casting instead of being shoved out by a phantom gap.
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
-- Optional element ("debuffs", "buffs", "ccs") selects per-element spacing;
-- no arg falls back to the legacy global auraSpacing. Kept as a single function
-- (not a second local) to respect this file's 200-local cap.
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

-- The four combined health-text elements (percent + number, either order,
-- "|" or "-" separator). Kept as one set so every eligibility check that treats
-- them as a single "combined health" category stays in lockstep.
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

-- Estimate pixel width of health text for a given element type.
-- We can't read actual rendered widths (WoW secret values), so we use
-- flat pixel assumptions based on typical worst-case rendered widths.
local HEALTH_TEXT_PADDING = 10  -- safety margin in px
local healthTextWidths = {
    healthPercent       = 38,
    healthPercentNoSign = 38,
    healthNumber  = 38,
    healthPctNum  = 75,
    healthNumPct  = 75,
    healthPctNumDash = 75,
    healthNumPctDash = 75,
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

-- Y offset for plate content relative to the nameplate frame. Always 0: the
-- Blizzard nameplate frame grows from its CENTER (not its base), so a taller
-- SetNamePlateSize enlarges the clickable hitbox evenly above AND below the
-- unit. Anchoring our content at the frame center therefore keeps the bar in
-- place AND keeps the hitbox centered on it -- no compensation needed.
-- (An earlier base-anchor assumption shifted content down by half the extra
-- height, which made the hitbox extend only above the bar.)
local function GetHitboxYShift()
    return 0
end
ns.GetHitboxYShift = GetHitboxYShift
-- Slot-based size/offset getters. Key strings are memoized per posKey
-- (closed set of six literals, lazy-filled) so these hot getters are
-- allocation-free; the VALUES are still read live from the profile, so
-- profile swaps cannot stale anything.
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
-- Cropped aura icons (mirrors the Unit Frames "Cropped Icons" option). When
-- on, the icon frame is made rectangular (height = 80% of width) and the
-- texture is trimmed top/bottom so the artwork is never squished. The
-- horizontal zoom stays at the nameplate aura default (0.08) so an uncropped
-- icon is pixel-identical to before. Wrapped in a do/end + ns functions so no
-- new main-chunk locals are added (this file is near the Lua 5.1 local cap).
do
    local AURA_CROP_HEIGHT = 0.80
    local AURA_ZOOM = 0.08
    function ns.GetAuraCrop(element)
        if element == "debuffs" then
            return (p and p.debuffCropIcons) or defaults.debuffCropIcons
        elseif element == "buffs" then
            return (p and p.buffCropIcons) or defaults.buffCropIcons
        elseif element == "ccs" then
            return (p and p.ccCropIcons) or defaults.ccCropIcons
        end
        return false
    end
    -- Frame height for a given icon width: shorter when cropped, square when not.
    function ns.GetAuraCropHeight(cropped, w)
        if cropped then return math.floor(w * AURA_CROP_HEIGHT + 0.5) end
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
-- Multi-toggle target glow model (EllesmereUI / Border Color / Highlight).
-- Live conversion, NO migration: each toggle returns its own stored key when
-- the user has set it, otherwise derives from the legacy targetGlowStyle
-- string. targetGlowStyle stays in defaults ("ellesmereui") so the fallback
-- source is always present. Legacy mapping: ellesmereui -> EllesmereUI;
-- vibrant -> EllesmereUI + Border Color; none -> nothing. Defined on ns (not
-- file-scope locals) to respect this file's near-cap local budget.
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
local function GetShowTargetGlow()
    return ns.GetTargetGlowEllesmereUI() or ns.GetTargetGlowBorderColor() or ns.GetTargetGlowHighlight()
end
ns.GetShowTargetGlow = GetShowTargetGlow
local function GetShowClassPower()
    if p and p.showClassPower ~= nil then return p.showClassPower end
    return defaults.showClassPower
end
ns.GetShowClassPower = GetShowClassPower
-- These getters live on ns (not file locals) to keep the main chunk under Lua's
-- 200-local limit; callers in this file use ns.GetClassPower*().
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
-- Defined on ns (not as file locals) to stay under Lua's 200 main-chunk local limit.
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
local function GetBorderColor()
    local c = (p and p.borderColor) or defaults.borderColor
    return c.r, c.g, c.b
end
ns.GetBorderColor = GetBorderColor
-- "Wrap Border Around Castbar" toggle. Defaults to false; the cast-visibility
-- hook reads this on each cast show/hide, so it stays a trivial table lookup.
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

-- Raise Strata: per-slot Core Positions toggle. When on, whichever element
-- occupies that slot is bumped one strata level (MEDIUM -> HIGH) so it renders
-- above the rest of the plate. Default off for every slot. Defined on ns (not a
-- file local) to respect this file's local budget.
function ns.GetSlotRaiseStrata(posKey)
    if not posKey or posKey == "none" then return false end
    local key = posKey .. "SlotRaiseStrata"
    if p and p[key] ~= nil then return p[key] end
    return defaults[key] or false
end

-- Apply each slot's Raise Strata setting to the element frame(s) sitting in it.
-- Element frames otherwise share MEDIUM strata (see the plate build comments);
-- raising to HIGH lifts that element above the flattened text/aura/indicator
-- tiers. Children (cooldown, count carrier, border) inherit the frame's strata.
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

-- Pandemic glow engine: procedural ants, button glow, autocast shine, FlipBook
-- Wrapped in do...end to keep all internal locals out of the main chunk's 200-local budget.
-- Externally-needed items are stored on ns.
do
-- Pandemic curve: step function returns 1 when remaining% <= 30% (pandemic window), 0 otherwise
-- Secret values from duration objects are passed ONLY to Blizzard widget APIs (SetAlpha) never compared in Lua
local pandemicCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    pandemicCurve = C_CurveUtil.CreateCurve()
    pandemicCurve:SetType(Enum.LuaCurveType.Step)
    pandemicCurve:AddPoint(0, 1)
    pandemicCurve:AddPoint(0.3, 0)
end
ns.pandemicCurve = pandemicCurve

-------------------------------------------------------------------------------
--  Glow Engines provided by shared EllesmereUI_Glows.lua
--  Local aliases for the pandemic glow wrapper below.
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local StartProceduralAnts = _G_Glows.StartProceduralAnts
local StopProceduralAnts  = _G_Glows.StopProceduralAnts
local StartButtonGlow     = _G_Glows.StartButtonGlow
local StopButtonGlow      = _G_Glows.StopButtonGlow
local StartAutoCastShine  = _G_Glows.StartAutoCastShine
local StopAutoCastShine   = _G_Glows.StopAutoCastShine
ns.StartProceduralAnts = StartProceduralAnts
ns.StopProceduralAnts  = StopProceduralAnts
ns.StartButtonGlow     = StartButtonGlow
ns.StopButtonGlow      = StopButtonGlow
ns.StartAutoCastShine  = StartAutoCastShine
ns.StopAutoCastShine   = StopAutoCastShine

-- Set of debuff slots with active pandemic glows; only these get alpha-ticked
local activePandemicSlots = {}
ns.activePandemicSlots = activePandemicSlots

local function StopPandemicGlow(slot)
    activePandemicSlots[slot] = nil
    local pg = slot.pandemicGlow
    if not pg or not pg.active then return end
    if pg.animGroup then pg.animGroup:Stop() end
    if pg.flipTex then pg.flipTex:Hide() end
    StopProceduralAnts(pg.wrapper)
    StopButtonGlow(pg.wrapper)
    StopAutoCastShine(pg.wrapper)
    pg.wrapper:Hide()
    pg.active = false
end

local function StartPandemicGlow(slot, slotSize)
    local pg = slot.pandemicGlow
    local styleIdx = GetPandemicGlowStyle()
    if styleIdx < 1 or styleIdx > #PANDEMIC_GLOW_STYLES then styleIdx = 1 end
    local entry = PANDEMIC_GLOW_STYLES[styleIdx]
    local sz = slotSize or 26

    if not pg then
        local wrapper = CreateFrame("Frame", nil, slot)
        wrapper:SetAllPoints()
        -- Sit ABOVE the cooldown frame (slot.cd at +2) so the duration swipe
        -- can't render on top of the pandemic border and dim it. Matches the
        -- dispel glow (slot+5); the glow is an edge border, so it doesn't
        -- meaningfully obscure the corner countdown / stack numbers. (At the old
        -- slot+1 the swipe drew over the glow, making it hard to see.)
        wrapper:SetFrameLevel(slot:GetFrameLevel() + 5)
        local flipTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        flipTex:SetPoint("CENTER")
        local animGroup = flipTex:CreateAnimationGroup()
        animGroup:SetLooping("REPEAT")
        local flipAnim = animGroup:CreateAnimation("FlipBook")
        wrapper:Show()
        wrapper:SetAlpha(0)
        pg = { wrapper = wrapper, flipTex = flipTex, animGroup = animGroup, flipAnim = flipAnim, active = false }
        slot.pandemicGlow = pg
    end

    -- Only restart glow if style changed or not active
    if pg.active and pg.styleIdx == styleIdx then
        pg.wrapper:Show()
        return
    end
    -- Stop previous style if switching
    if pg.active and pg.styleIdx ~= styleIdx then
        StopPandemicGlow(slot)
    end

    local cr, cg, cb = GetPandemicGlowColor()

    if entry.procedural then
        -- Pixel Glow: procedural ants mode
        pg.flipTex:Hide()
        pg.animGroup:Stop()
        StopButtonGlow(pg.wrapper)
        StopAutoCastShine(pg.wrapper)
        local N = GetPandemicGlowLines()
        local th = GetPandemicGlowThickness()
        local speed = GetPandemicGlowSpeed()
        local period = speed  -- speed IS the period in seconds per full orbit
        local lineLen = math.floor((sz + sz) * (2 / N - 0.1))
        lineLen = min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        local br, bg, bb = ns.GetPandemicGlowBackgroundColor()
        StartProceduralAnts(pg.wrapper, N, th, period, lineLen, cr, cg, cb, sz, nil,
            ns.GetPandemicGlowBackground() and br or nil, bg, bb)
    elseif entry.buttonGlow then
        -- Action Button Glow: animated ants texture
        pg.flipTex:Hide()
        pg.animGroup:Stop()
        StopProceduralAnts(pg.wrapper)
        StopAutoCastShine(pg.wrapper)
        StartButtonGlow(pg.wrapper, sz, cr, cg, cb, entry.scale or 1.36)
    elseif entry.autocast then
        -- Auto-Cast Shine: orbiting sparkle dots
        pg.flipTex:Hide()
        pg.animGroup:Stop()
        StopProceduralAnts(pg.wrapper)
        StopButtonGlow(pg.wrapper)
        StartAutoCastShine(pg.wrapper, sz, cr, cg, cb)
    else
        -- FlipBook mode: GCD, Modern WoW Glow, Classic WoW Glow
        StopProceduralAnts(pg.wrapper)
        StopButtonGlow(pg.wrapper)
        StopAutoCastShine(pg.wrapper)
        local texSz = sz * (entry.scale or 1)
        pg.flipTex:SetSize(texSz, texSz)
        if entry.atlas then
            pg.flipTex:SetAtlas(entry.atlas)
        elseif entry.texture then
            pg.flipTex:SetTexture(entry.texture)
        end
        pg.flipAnim:SetFlipBookRows(entry.rows or 6)
        pg.flipAnim:SetFlipBookColumns(entry.columns or 5)
        pg.flipAnim:SetFlipBookFrames(entry.frames or 30)
        pg.flipAnim:SetDuration(entry.duration or 1.0)
        pg.flipAnim:SetFlipBookFrameWidth(entry.frameW or 0)
        pg.flipAnim:SetFlipBookFrameHeight(entry.frameH or 0)

        -- Always apply color tint (fixes default FFEB96 showing as blue)
        pg.flipTex:SetDesaturated(true)
        pg.flipTex:SetVertexColor(cr, cg, cb)

        pg.flipTex:Show()
        pg.animGroup:Play()
    end

    pg.wrapper:Show()
    pg.active = true
    pg.styleIdx = styleIdx
end

-- Applies pandemic glow using the duration object's secret-safe methods.
-- Secret values from IsZero/EvaluateRemainingPercent go ONLY into Blizzard widget APIs (SetAlpha),
-- never into Lua comparisons. This is the standard secret-safe pattern.
-- Active pandemic slots register themselves for a lightweight alpha-only tick
-- instead of polling every plate globally.
-- The onset ticker frame lives on ns._pandemicTickFrame. It is created
-- AFTER this do/end block closes, so a block-local forward declaration
-- here can never see it -- that exact bug shipped the ticker dead: the
-- creation site assigned a global while ApplyPandemicGlow's captured
-- block-local stayed nil forever, so the ticker was never shown and
-- glow onset silently rode the (since-fixed) full-rebuild storm instead.
local function ApplyPandemicGlow(slot)
    local durObj = slot._durationObj
    if not durObj or not pandemicCurve then
        StopPandemicGlow(slot)
        return
    end
    StartPandemicGlow(slot, GetDebuffIconSize())
    -- Secret boolean/number EvaluateColorValueFromBoolean SetAlpha (all Blizzard APIs, no Lua comparisons)
    slot.pandemicGlow.wrapper:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, durObj:EvaluateRemainingPercent(pandemicCurve)))
    -- Register for alpha-only tick updates
    activePandemicSlots[slot] = true
    if ns._pandemicTickFrame then ns._pandemicTickFrame:Show() end
end
ns.StopPandemicGlow = StopPandemicGlow
ns.ApplyPandemicGlow = ApplyPandemicGlow

-------------------------------------------------------------------------------
--  Dispellable buff glow — highlights enemy buffs the player can purge/soothe
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

local function StartDispelGlow(slot, slotSize, typeColor)
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

    local cr, cg, cb = ns.GetDispelGlowColor(typeColor)

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
        -- FlipBook-based glow (GCD, Modern, Classic) — matches pandemic glow pattern
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
    -- Use the curve color's alpha to control visibility.
    -- Magic/Enrage → alpha 1 (visible), everything else → alpha 0 (hidden).
    -- The alpha is a secret number but SetAlpha (C function) accepts secrets.
    -- typeColor is nil in preview mode → fall back to alpha 1.
    if typeColor then
        local _, _, _, a = typeColor:GetRGBA()
        dg.wrapper:SetAlpha(a)
    else
        dg.wrapper:SetAlpha(1)
    end
end

ns.StopDispelGlow = StopDispelGlow
ns.StartDispelGlow = StartDispelGlow
end -- do (glow engine)

-- Forward declaration (defined later in the class power section)
local GetClassPowerTopPush
-- Position a set of aura frames into a slot ("top", "left", or "right")
-- frames: array of frame objects, count: how many to show, plate: the nameplate
-- sizeW/sizeH: icon dimensions, gap: pixel gap between icon edges
local function PositionAuraSlot(frames, count, slot, plate, sizeW, sizeH, gap, xOff, yOff)
    xOff = xOff or 0
    yOff = yOff or 0
    local spacing = gap + sizeW  -- horizontal center-to-center distance
    -- Vertical center-to-center distance. Cropped icons are shorter, so
    -- vertically stacked slots (topleft/topright "up") pack tighter. sizeH
    -- falls back to sizeW for square (uncropped) icons.
    local spacingV = gap + (sizeH or sizeW)
    -- Profile reads, anchor resolution, and growth lookups are invariant
    -- across the icon loop: resolve once per slot branch, loop only the
    -- ClearAllPoints + PP.Point calls. GetClassPowerTopPush keeps its
    -- exact original call conditions (it reads target identity; the
    -- left/right/bottom and top-with-text-element paths never call it).
    if slot == "top" then
        local debuffY = GetDebuffYOffset()
        -- Determine anchor: resolve to whichever FontString is in the top slot
        local topElement = GetTextSlot("textSlotTop")
        local anchor
        if topElement == "enemyName" then
            anchor = plate.name
        elseif topElement == "healthNumber" then
            anchor = plate.hpNumber
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
        -- Icon 1 is always flush with the top-left corner of the health bar.
        -- Growth direction only affects where icons 2+ go from there. (PP borders
        -- are inset, so the bar's corner IS the nameplate's outer edge -- anchor
        -- at offset 0 for true flush; xOff lets the user nudge.)
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
        -- Icon 1 is always flush with the top-right corner of the health bar.
        -- Growth direction only affects where icons 2+ go from there. (Offset 0 =
        -- flush; PP borders are inset so the bar corner is the outer edge.)
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
        -- Unknown slot: preserve original behavior (points cleared,
        -- nothing re-anchored)
        for i = 1, count do
            frames[i]:ClearAllPoints()
        end
    end
end
ns.PositionAuraSlot = PositionAuraSlot

-- Get XY offset for an aura slot key (now slot-based)
-- slotKey is the DB key like "debuffSlot", "raidMarker", "classification"
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

-- Clear a single aura slot (debuff/buff/cc). File-scope to avoid
-- closure allocation inside UpdateAuras.
local function ClearAuraSlot(slot)
    slot:Hide()
    RawSetTex(slot.icon, nil)
    if slot.pandemicGlow and slot.pandemicGlow.active then ns.StopPandemicGlow(slot) end
    if slot.dispelGlow and slot.dispelGlow.active then ns.StopDispelGlow(slot) end
    slot._durationObj = nil
    slot._auraId = nil
    local cd = slot.cd
    if cd then
        if cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
        if cd.Clear then cd:Clear()
        elseif CooldownFrame_Clear then CooldownFrame_Clear(cd)
        else cd:SetCooldown(0, 0) end
        cd:Hide()
    end
end

ns.CAST_LOCKOUT_SLOT_ID = "__EUI_CAST_LOCKOUT__"
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

function ns.ArmCastLockoutCooldown(cd, lockout)
    if cd then
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
        if cd.SetAlpha then cd:SetAlpha(1) end
        cd:SetCooldown(lockout.start, lockout.duration)
        cd:Show()
    end
end

function ns.ArmCastLockoutSlot(slot, lockout)
    RawSetTex(slot.icon, lockout.icon)
    slot.icon:Show()
    ns.ArmCastLockoutCooldown(slot.cd, lockout)
    slot:Show()
    slot._durationObj = nil
    slot._auraId = ns.CAST_LOCKOUT_SLOT_ID
end

-- Position target arrows OUTSIDE the outermost side auras (if arrows are shown).
-- Called after all aura positioning is complete.
local PositionArrowsOutsideAuras
do
    -- Hoisted out of PositionArrowsOutsideAuras: the old addSide closure
    -- (capturing gap/sideOff/extents) was allocated on every call on the
    -- target plate. Extents accumulate through params/returns instead --
    -- allocation-free, no shared mutable state.
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
    -- Cast spell icon: reserve on its side so the arrow + the (pushed) side-slot
    -- core icons all clear it. Normal-size icons reserve at all times (the small
    -- gap holds steady across cast start/stop); the full-size icon only renders
    -- during a cast, so passing the plate gates its (large) reserve on the cast
    -- bar being shown. Clean profile numbers, never secrets.
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
    -- 12.1 restricted-tree rendering (field-confirmed on PTR): inside the
    -- aspect-restricted nameplate subtree, SINGLE-POINT + SetSize regions
    -- render displaced from their anchor, while rects fully defined by
    -- anchors (fill, bg, hash line) render exactly. So both arrows pin
    -- TOP+BOTTOM to the health bar's CORNERS (hash-line pattern): the bar
    -- edges resolve engine-side, the offsets stay small numbers scaled
    -- exactly like the legacy single-point form (live-visual parity), and
    -- nothing here reads geometry ("Can't measure restricted regions").
    -- Same rendered result as before: inner edge (extent + 8) from the bar
    -- edge, vertically centered, 16 * scale tall. The symmetric +/-dy pair
    -- keeps centering exact regardless of pixel-mult rounding.
    local st = ns.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw = math.floor(((st and st.w) or 16) * sc + 0.5)
    local ah = math.floor(16 * sc + 0.5)
    local dy = (ah - GetHealthBarHeight()) / 2
    local lox = -(leftExtent + 8 + aw / 2)
    local rox = (rightExtent + 8 + aw / 2)
    -- Stashed for the 12.1 container reanchor (EUI_Nameplates_AuraContainers
    -- ReanchorArrows), which re-points arrows to engine-sized aura container
    -- edges and needs the same dimensions without re-deriving the style.
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
--  Lazy-creation helpers for target-only / focus-only UI objects.
--  These are only needed on 1 plate at a time, so creating them on every
--  pooled plate wastes memory. Each Ensure* is idempotent (no-ops if
--  already created on the plate).
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
    -- Glow tint + opacity come from the target "Glow Color" setting (default =
    -- signature blue at full opacity). Textures are collected so ApplyTarget can
    -- recolor them live.
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

-- Highlight target style: a fixed translucent white wash across the target's
-- health bar. Lazily created (only the target ever shows it) and kept SEPARATE
-- from plate.highlight (the mouseover highlight) so the two never fight over
-- show/hide state when a unit is both targeted and moused over.
local function EnsureTargetHighlight(plate)
    if plate.targetHighlight then return end
    local t = plate.health:CreateTexture(nil, "OVERLAY", nil, 5)
    t:SetAllPoints(plate.health)
    local c = ns.GetTargetHighlightColor()
    t:SetColorTexture(c.r, c.g, c.b, ns.GetTargetHighlightAlpha())
    t:Hide()
    plate.targetHighlight = t
end

-- Target arrow styles: key -> { l=left texture, r=right texture, w=drawn width at
-- height 16 (scale 1), label }. All source art is 66px tall; width preserves the
-- original 36px art = 11px drawn, i.e. w = round(nativeWidth * 11/36): 36->11,
-- 72->22, 90->28. Height is always 16. Shared by enemy/friendly plates + options.
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

-- Resolve a profile to its arrow style table. targetArrowStyle is the current key;
-- legacy profiles fall back to the old targetArrowDouble boolean (then Simple).
function ns.ResolveTargetArrowStyle(prof)
    local key = prof and (prof.targetArrowStyle or (prof.targetArrowDouble and "double")) or nil
    return ns.TARGET_ARROW_STYLES[key] or ns.TARGET_ARROW_STYLES.simple
end

-- Target arrow tint: the player's class color when targetArrowClassColor is on,
-- otherwise the custom targetArrowColor (default white).
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
    -- Regions OF the health bar (12.1: the plate subtree is aspect-restricted
    -- and unmeasurable). NO creation anchors: single-point + size rects render
    -- DISPLACED inside the restricted tree, so the only sanctioned anchor form
    -- is the fully-anchored TOP+BOTTOM scheme applied by
    -- PositionArrowsOutsideAuras -- which runs on every target apply, always
    -- after Show(). An unanchored hidden texture has no rect and draws
    -- nothing, so the creation state is safe. Rendering outside the bar rect
    -- is fine (health runs SetClipsChildren(false)).
    plate.leftArrow = plate.health:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
    plate.rightArrow = plate.health:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
    PP.Size(plate.leftArrow, aw, ah)
    plate.leftArrow:Hide()
    PP.Size(plate.rightArrow, aw, ah)
    plate.rightArrow:Hide()
end

-- Target/Focus overlay textures: the special stripe overlays live in the
-- nameplates Media folder (resolved by name); everything else is a regular bar
-- texture resolved through the shared health-bar texture lookup (EUI textures +
-- SharedMedia), so the overlay dropdowns can offer the full bar texture set.
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

-- Both overlays span the full bar width (anchored LEFT+RIGHT to the health bar)
-- so the pattern always covers the whole bar and follows Health Bar Width
-- changes automatically. Fill and bg share the identical geometry, so a stripe's
-- diagonal stays continuous across the fill/background split; the clip frames
-- still window the filled vs empty portions. (Previously stripe overlays used a
-- fixed 200px width, which left bars wider than 200 uncovered on the right.)
-- Stripes additionally CROP via texcoord to the bar's share of the pattern's
-- native 200px span, so the diagonal density stays pixel-identical to the old
-- fixed-200px look on every bar up to 200 wide. Wider bars stretch the full
-- pattern (that region was simply blank before the full-width fix, so there is
-- no legacy look to preserve there). Width comes from settings
-- (GetHealthBarWidth), never from measuring the plate subtree (12.1 restricted
-- regions forbid reads there).
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

-- Alpha for the empty (background) portion of an overlay. The per-state "Full
-- alpha on empty part of bar" toggle shows it at the same opacity as the filled
-- portion; otherwise it stays dimmed to 30% so the fill reads as "more filled".
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
    -- Vertical bounds come from the health bar itself (full nameplate height)
    -- so the overlay can never pixel-snap 1px short on the top or bottom edge
    -- as the plate floats at sub-pixel screen positions. Only the RIGHT edge
    -- tracks the fill so the stripes window the filled portion.
    plate.focusClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.focusClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.focusClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayFill = plate.focusClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Texture: full bar height and full bar width (anchored LEFT+RIGHT to the
    -- health bar) so the diagonal pattern stays continuous across the
    -- fill/background split (both overlays share the same geometry) and snaps
    -- with the clip's vertical edges.
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
    -- Creation-time texcoord for the STRIPE_TEX default (the state-gated apply
    -- re-runs this with the actual texture kind).
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
    -- Creation-time texcoord for the STRIPE_TEX default (the state-gated apply
    -- re-runs this with the actual texture kind).
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
    -- Vertical bounds come from the health bar itself (full nameplate height)
    -- so the overlay can never pixel-snap 1px short on the top or bottom edge
    -- as the plate floats at sub-pixel screen positions. Only the RIGHT edge
    -- tracks the fill so the stripes window the filled portion.
    plate.targetClipFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.targetClipFill:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.targetClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    plate.targetClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.targetOverlayFill = plate.targetClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Texture: full bar height and full bar width (anchored LEFT+RIGHT to the
    -- health bar) so the diagonal pattern stays continuous across the
    -- fill/background split (both overlays share the same geometry) and snaps
    -- with the clip's vertical edges.
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
    -- Creation-time texcoord for the STRIPE_TEX default (the state-gated apply
    -- re-runs this with the actual texture kind).
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
    -- Mask texture: constrains absorb rendering to exact health bar bounds
    -- at the GPU level. Prevents subpixel bleed where absorb textures
    -- extend 1px outside the health bar at certain nameplate positions.
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
    -- Target glow, target arrows, and focus overlay are lazy-created on
    -- demand (EnsureGlow / EnsureArrows / EnsureFocusOverlay) since only
    -- 1 plate at a time ever shows them. This saves ~14 objects per plate.
    -- Text overlay frame: renders above focus stripe overlay (level +1)
    plate.healthTextFrame = CreateFrame("Frame", nil, plate)
    plate.healthTextFrame:SetAllPoints(plate.health)
    -- TEXT TIER (top of the hierarchy). All three layered groups -- text (900),
    -- aura icons (800) and indicators (raid marker / classification, ~13-18) --
    -- use an explicit MEDIUM strata so they are pulled out of the plate's
    -- flattened render layer together and ordered purely by frame level. Without
    -- the explicit strata this frame would stay in the flattened pass and render
    -- BELOW the (strata-promoted) aura icons. Text > Auras > Indicators.
    plate.healthTextFrame:SetFrameStrata("MEDIUM")
    plate.healthTextFrame:SetFrameLevel(900)
    plate.hpText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpText, 10, GetNPOutline())
    PP.Point(plate.hpText, "RIGHT", plate.health, "RIGHT", -2, 0)
    plate.hpNumber = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpNumber, 10, GetNPOutline())
    plate.hpNumber:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.hpNumber:Hide()
    -- Mouseover highlight: parented to the health bar (not the higher-level
    -- text frame) so it renders BEHIND the border, which lives on a child
    -- frame at health level + 1.
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
    -- INDICATOR TIER (bottom of the three layered groups). Explicit MEDIUM strata
    -- like the aura icons and text, so frame level alone decides order within the
    -- pulled-out group: the marker (health+8 = 18) sits BELOW the aura icons (800)
    -- and the text (900) but above the flattened health bar. Sharing MEDIUM across
    -- all three tiers is what keeps the order predictable -- a no-strata frame
    -- would drop into the plate's flattened render layer instead.
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
    -- INDICATOR TIER (see raidFrame). MEDIUM strata + low level (health+3 = 13)
    -- so the classification/elite/rare/quest indicator sits below the aura icons
    -- (800) and text (900) but above the flattened health bar.
    plate.classFrame:SetFrameStrata("MEDIUM")
    plate.classFrame:SetFrameLevel(plate.health:GetFrameLevel() + 3)
    plate.classFrame:Hide()
    plate.class = plate.classFrame:CreateTexture(nil, "ARTWORK")
    plate.class:SetAllPoints()
    plate.cast = CreateFrame("StatusBar", nil, plate)
    -- Cast bar spans the health bar width. By default the icon hangs outside to
    -- the left; with "Make Icon Part of the Bar" the bar shrinks so the icon
    -- sits inside the width. LayoutCastBar handles both (must run after
    -- plate.health exists, which it does here).
    ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), CAST_H)
    plate.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.cast:SetMinMaxValues(0, 1)
    plate.cast:Hide()
    plate.castBG = plate.cast:CreateTexture(nil, "BACKGROUND")
    plate.castBG:SetAllPoints()
    local _cbg = (p and p.castBgColor) or defaults.castBgColor
    local _cba = (p and p.castBgAlpha) or defaults.castBgAlpha
    plate.castBG:SetColorTexture(_cbg.r, _cbg.g, _cbg.b, _cba)
    -- Cast bar border: pixel-perfect PP.CreateBorder, lazy-created (off by
    -- default at size 0, so it costs nothing unless the user enables it).
    -- Mirrors the nameplate health border. The border is a child of plate.cast
    -- so it shows/hides with the cast bar automatically.
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
    -- "Wrap Border Around Castbar" (opt-in, off by default). While the cast bar is
    -- shown and the feature is enabled, the health bar + cast bar are wrapped in one
    -- continuous border made of TWO pieces, one per bar: the REAL health border
    -- (top + sides of the health bar, untouched, so its colour is already correct)
    -- and a region frame for the lower half (sides + bottom, full footprint width,
    -- health bottom -> cast bottom). The touching edges are hidden so they read as a
    -- single outline; the region copies the health border's live colour.
    --
    -- The two pieces MUST live in their own bar's subtree. Each PP border is an
    -- OVERLAY-draw-layer texture that beats its OWN bar's ARTWORK fill within the
    -- plate's flattened render layer (reliable). A single frame spanning BOTH bars
    -- does NOT work: its health half would render over the health fill from
    -- plate.cast's subtree -- the unreliable cross-flatten case that put the border
    -- behind the bars (the "disappears" bug). The region (child of plate.cast) never
    -- overlaps the health fill, so it stays reliable, and it rides the "Casts In
    -- Front of Nameplates" lift natively.
    --
    -- The region (not the cast bar's own border) is what lets the lower half span the
    -- full footprint and bridge a Cast Bar Y gap / enclose an in-width icon: PP snaps
    -- a border's edges to the frame it belongs to (SnapBorderTextures), so the cast
    -- bar's own border can only ever hug the narrower / gapped cast bar.
    --
    -- Custom (textured) border = no-op: a textured backdrop is one piece, can't merge
    -- cleanly. shouldWrap requires the simple PP border. O(1) no-op when off.
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
                -- The REAL health border (child of plate.health) keeps drawing the top
                -- + sides of the health bar. The lower half is a separate region frame
                -- (child of plate.cast) spanning the FULL footprint width from the
                -- health bar's BOTTOM to the cast bar's BOTTOM -- bridging any Cast Bar
                -- Y-offset gap and enclosing an in-width cast icon. We hide the seam
                -- (health bottom + region top edges) so they read as one outline, and
                -- copy the health border's live colour onto the region (target
                -- highlight carries over). The two pieces MUST stay in their own bar's
                -- subtree: each renders over its own bar's fill, where OVERLAY-draw-
                -- layer beats ARTWORK reliably. A single frame spanning BOTH bars fails
                -- -- its health half would render over the health fill from plate.cast's
                -- subtree, the unreliable cross-flatten case (the "disappears" bug).
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
                -- Lift the region above the cast spell icon. The icon frame is itself
                -- raised to health-level+1 (so a full-size icon clears the health bar),
                -- which would otherwise draw an in-width "part of the bar" icon ON TOP
                -- of the wrap border. Putting the region (hence its OVERLAY border)
                -- above the icon makes the unified border draw over the icon's edge.
                -- Re-set every pass: a strata propagation from the cast-lift would
                -- collapse it otherwise.
                if plate.castIconFrame then
                    region:SetFrameLevel(plate.castIconFrame:GetFrameLevel() + 2)
                end
                if not PP.GetBorders(region) then
                    PP.CreateBorder(region, r, g, b, a, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
                end
                -- Set the seam flags on the containers BEFORE (re)snapping so
                -- SnapBorderTextures hides the two touching edges AND runs the side
                -- strips all the way to the seam (no edge line, no corner notch).
                -- Flags live on the container, so they survive every later re-snap
                -- (the create-border 2-tick OnUpdate, scale changes, RefreshBorder) --
                -- a one-shot :Hide() would be re-shown by the next snap.
                local rb = PP.GetBorders(region)
                if rb then rb._hideTop = true end
                hb._hideBottom = true
                PP.SetBorderSize(region, sz)
                PP.SetBorderColor(region, r, g, b, a)
                PP.ShowBorder(region)
                PP.SetBorderSize(plate.health, sz)
                -- Leave the cast bar's OWN border ACTIVE under the wrap (user wants it
                -- visible) -- the region border sits at a higher frame level so it
                -- draws over it. Only the icon-separator line is hidden so an in-width
                -- "part of the bar" icon stays seamless with the bar.
                if plate.castLeftBorder then plate.castLeftBorder:Hide() end
                -- Optional (off by default): tint the full-size icon's border with the
                -- live target border colour so it matches the wrapped bar on your
                -- current target. The else-branch keeps the icon border black in every
                -- other case, so turning the toggle off resets it on the next pass.
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
            -- Clear the seam flag and re-snap the health border so its bottom edge +
            -- side insets come back (the re-snap re-applies the live colour, so it
            -- stays correct). Drop the region and hand the cast border back.
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
    end
    plate:ApplyCastBorder()
    plate.castLeftBorder = plate.cast:CreateTexture(nil, "OVERLAY", nil, 7)
    plate.castLeftBorder:SetColorTexture(0, 0, 0, 1)
    plate.castLeftBorder:SetWidth(1)
    plate.castLeftBorder:SetPoint("TOPLEFT", plate.cast, "TOPLEFT", 0, 0)
    plate.castLeftBorder:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMLEFT", 0, 0)
    -- Icon frame hangs outside the cast bar's left edge.
    -- Parented to cast (auto-hides with cast) and anchored to cast (same frame
    -- = single-pass layout resolve, no cross-frame jitter).
    plate.castIconFrame = CreateFrame("Frame", nil, plate.cast)
    -- Lift above the health bar (level 10) once, so a full-size icon (which
    -- spans up into the health band) is never occluded by the health bar.
    -- Harmless for the normal case (the icon sits below the health bar there).
    plate.castIconFrame:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    ns.LayoutCastIcon(plate, CAST_H)
    AddBorder(plate.castIconFrame)
    plate.castIcon = plate.castIconFrame:CreateTexture(nil, "ARTWORK")
    -- Fill the frame (inset 0) so the 1px OVERLAY border draws ON TOP of the icon's
    -- rim -- the visible icon edge IS the border's inner edge, so no bare frame can
    -- ever show through as a gap. DisablePixelSnap matches the icon to the (now
    -- unsnapped) border strips so they translate together under plate motion instead
    -- of drifting apart by a pixel at fractional screen positions.
    plate.castIcon:SetPoint("TOPLEFT", plate.castIconFrame, "TOPLEFT", 0, 0)
    plate.castIcon:SetPoint("BOTTOMRIGHT", plate.castIconFrame, "BOTTOMRIGHT", 0, 0)
    if PP and PP.DisablePixelSnap then PP.DisablePixelSnap(plate.castIcon) end
    plate.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    plate.castSpark = plate.cast:CreateTexture(nil, "OVERLAY", nil, 1)
    plate.castSpark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    plate.castSpark:SetSize(8, CAST_H)
    plate.castSpark:SetPoint("CENTER", plate.cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    plate.castSpark:SetBlendMode("ADD")
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
    -- Kick tick: clip frame so the tick doesn't render outside the cast bar
    -- when kick CD exceeds remaining cast time. Only the kick elements live
    -- inside this clip frame; everything else (icon, text, shield, spark)
    -- stays on the unclipped cast bar so nothing gets cut off.
    plate.kickClip = CreateFrame("Frame", nil, plate.cast)
    plate.kickClip:SetAllPoints(plate.cast)
    plate.kickClip:SetClipsChildren(true)
    plate.kickPositioner = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    -- Pixel-snap OFF on the fill texture. The tick sits at positioner_width +
    -- marker_width; if either fill snaps its edge to the pixel grid
    -- independently, round(a) + round(b) flips by 1px as one width crosses a
    -- pixel boundary while the other does not, even though
    -- (elapsed + CD remaining) / total is invariant -- that is the jitter.
    -- Belt-and-suspenders only: the load-bearing unsnap is after each
    -- SetFillStyle in UpdateKickTick (SetFillStyle re-mints the inner fill to
    -- snap-ON and the global SetStatusBarTexture hook will not re-fire on a bar
    -- it has already cached).
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
    -- Interrupt-ready mid-cast fill: colors the cast-bar segment from the
    -- "kick ready here" point to the cast end (the window during which the
    -- player's interrupt will be available) when the kick is on cooldown now
    -- but comes off cooldown before the cast finishes. It rides the SAME
    -- kickMarker geometry as the tick: the "ready in time" two-secret-duration
    -- test is resolved purely by where the marker texture edge lands. When the
    -- kick will NOT be ready in time the fill left/right anchors cross and it
    -- collapses to zero width, so it self-hides with no Lua branch on a secret.
    -- It lives on plate.cast at ARTWORK sublevel 1 so it sits above the bar
    -- fill but below the OVERLAY cast text and below the uninterruptible grey
    -- overlay (sublevel 2). Anchors are (re)applied per cast in UpdateKickTick.
    plate.kickReadyFill = plate.cast:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.kickReadyFill:SetColorTexture(1, 1, 1, 1)
    plate.kickReadyFill:SetAlpha(0)
    plate.kickReadyFill:Hide()
    -- Cast bar text: three independent fixed zones
    -- [castName LEFT 50%] [castTarget CENTER-RIGHT 25%] [castTimer RIGHT 15%]
    -- Hosted on an explicit MEDIUM frame so the cast text is pulled out of the
    -- plate's flattened render layer and renders ABOVE the cast bar border (the
    -- border sits in the flattened pass and would otherwise cover the text).
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
    -- OnUpdate: tick the cast timer while a cast is active, throttled to
    -- 10 Hz -- the text renders %.1f precision, so the displayed tenth
    -- digit cannot change faster than every 0.1s and per-frame updates
    -- are pure waste (3 duration-object API calls + SetFormattedText per
    -- frame per casting plate at uncapped FPS).
    -- Uses UnitCastingDuration/UnitChannelDuration duration objects and their
    -- :GetRemainingDuration() method to avoid taint from UnitCastingInfo's
    -- secret endTime/startTime values, which cannot be used in arithmetic.
    plate.cast:SetScript("OnUpdate", function(self, elapsed)
        local owner = self._timerPlate
        if not owner or not owner.unit or not owner.isCasting then return end
        if not owner._showCastTimer then return end
        local acc = (self._timerAcc or 0.1) + elapsed
        if acc < 0.1 then
            self._timerAcc = acc
            return
        end
        self._timerAcc = 0
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
    end)
    plate.cast._timerPlate = plate
    -- Full-size cast icon: its side-slot reserve is only valid while the cast bar
    -- is shown, so re-anchor the reserving side elements on every cast show/hide.
    -- One chokepoint catches all show/hide paths (start, stop, channel stop,
    -- interrupt flash + its timer). RefreshCastIconSideReserve early-outs unless
    -- the full-size icon is enabled, so these scripts are ~free in the common case.
    local function OnCastVisibilityChanged(self)
        local owner = self._timerPlate
        if owner and owner.RefreshCastIconSideReserve then
            owner:RefreshCastIconSideReserve()
        end
        -- Wrap-border driver. Gated so that when the feature is off (and the
        -- plate is not currently wrapped) nothing beyond this cheap check runs:
        -- a field read, then -- only if needed -- a trivial setting lookup.
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
        d.icon = d:CreateTexture(nil, "ARTWORK")
        PP.Point(d.icon, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.icon, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Snap-disable ONCE at creation: the aura arm/clear hot paths use
        -- PP.RawSetTexture (pre-hook original), which never re-triggers
        -- the pixel-snap hook on this pooled texture.
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
        -- Stack count lives on a carrier ABOVE the cooldown so the zero-duration
        -- alpha mask on d.cd (which kills the permanent-aura swipe strobe) never
        -- hides the stack number.
        d.countCarrier = CreateFrame("Frame", nil, d)
        d.countCarrier:SetAllPoints(d)
        d.countCarrier:SetFrameLevel(d.cd:GetFrameLevel() + 1)
        d.count = d.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(d.count, 11, "OUTLINE, SLUG")
        PP.Point(d.count, "BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.count:SetJustifyH("RIGHT")
        local cdRegions = { d.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                d.cd.text = region
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
        -- Stack count on a carrier ABOVE the cooldown (see debuff slot) so the
        -- zero-duration alpha mask on b.cd never hides the stack number.
        b.countCarrier = CreateFrame("Frame", nil, b)
        b.countCarrier:SetAllPoints(b)
        b.countCarrier:SetFrameLevel(b.cd:GetFrameLevel() + 1)
        b.count = b.countCarrier:CreateFontString(nil, "OVERLAY")
        SetFSFont(b.count, 9, "OUTLINE, SLUG")
        PP.Point(b.count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        local bCdRegions = { b.cd:GetRegions() }
        for _, region in ipairs(bCdRegions) do
            if region:GetObjectType() == "FontString" then
                b.cd.text = region
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

-- Pre-warm the plate frame pool so AoE pulls don't pay the 2 ms+
-- per-frame creation cost (CreateFrame + child textures + cooldowns)
-- on every plate Acquire when many plates appear in the same engine
-- frame. Without prewarm, a 5-mob pack can stack 10+ ms of synchronous
-- frame setup into a single render frame -> visible stutter.
--
-- Spread the work over 2 seconds (1 plate / 100 ms) starting shortly
-- after PLAYER_LOGIN so login itself stays smooth. Each Acquire
-- runs the pool's creation function; Release returns the now-built
-- frame to the inactive list, ready for instant reuse.
do
    local prewarmFrame = CreateFrame("Frame")
    prewarmFrame:RegisterEvent("PLAYER_LOGIN")
    prewarmFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            -- Hold acquires until end so each one actually creates a new
            -- pool frame instead of recycling the same one.
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
    -- Legacy stub: NewDB + DeepMergeDefaults handles defaults now.
    -- Kept as a no-op so any stray call sites don't error.
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
-- Re-evaluate the cast-bar wrap on every enemy plate. Each plate self-decides
-- whether to wrap or unwrap, so this both applies and tears down. Called from
-- the option toggle (unconditionally, to catch toggle-off) and -- gated behind
-- the setting -- from the border refreshers, so border size/colour edits made
-- while a wrapped plate is mid-cast keep the unified border in sync.
function ns.ApplyBorderWrapToAll()
    for _, plate in pairs(ns.plates) do
        if plate.UpdateBorderWrap then plate:UpdateBorderWrap() end
    end
end
function ns.RefreshBorder()
    -- Bump appearance gen so pooled/off-screen plates pick up the
    -- change on their next SetUnit (cache-hit re-spawns check this).
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
    -- ApplyCastBorder re-shows/re-sizes the cast border from its own settings; a
    -- wrapped, mid-cast plate must re-merge so the cast portion tracks the health
    -- border again (mirrors RefreshBorder / RefreshBorderColor).
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
    -- Enemy stacking is always EUI-owned; apply it every time (login + runtime).
    -- This must NOT be gated on friendly players, or enemy plates stop stacking
    -- for anyone who hands friendly nameplates to Blizzard.
    C_CVar.SetCVarBitfield("nameplateStackingTypes", Enum.NamePlateStackType.Enemy, db.stackingEnabled ~= false)
    -- Friendly stacking is only ours to write while we manage friendly players.
    -- When friendly players are Blizzard-managed we leave the friendly bit
    -- untouched (login or runtime) so the user's Blizzard setting survives.
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
    -- The frame grows from its CENTER, so a taller size enlarges the clickable
    -- hitbox evenly above and below the unit. -10000 insets let the hit rect
    -- fill the full (centered) frame.
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

-- Hitbox visualizer: a translucent overlay matching each enemy nameplate's
-- clickable bounds (the frame sized by SetNamePlateSize above), so the Hitbox
-- Size sliders can be dialled in visually. Toggled by the eyeball next to the
-- sliders. Runtime-only (resets on reload); the overlay is created lazily the
-- first time a plate actually needs it, so this costs nothing when off.
-- Defined on ns (not a file-scope local) to stay under the Lua 5.1 200-local
-- cap on this file's main chunk.
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
        -- Re-parent + re-anchor each apply, since pooled plates get reused on a
        -- fresh Blizzard nameplate (mirrors the _stackBounds handling).
        ov:SetParent(np)
        ov:SetFrameLevel(np:GetFrameLevel() + 10)
        ov:ClearAllPoints()
        ov:SetAllPoints(np)
        ov:Show()
    elseif plate.hitboxOverlay then
        plate.hitboxOverlay:Hide()
    end
end

-- Toggle the hitbox visualizer across every active enemy plate. Driven by the
-- eyeball button beside the Hitbox Size sliders in options.
function ns.SetHitboxOverlayShown(show)
    ns._hitboxOverlayShown = show and true or false
    for _, plate in pairs(ns.plates) do
        ns._ApplyHitboxOverlay(plate)
    end
end

--- Full visual refresh for all plates called when an entire preset is applied.
--- Re-runs SetUnit on each active plate, which re-reads all DB values and applies
--- them.  Only runs on deliberate preset switch (not per-frame or per-event).
function ns.RefreshAllSettings()
    -- Re-read profile reference: RepointAllDBs may have swapped the
    -- profile table (spec-linked profiles). All color lookups via _C()
    -- read from this local.
    p = ENP.db.profile
    -- Bump the appearance generation so SetUnit re-runs ApplyAppearance
    -- on each plate. Without this bump, cache-hit re-spawns would skip
    -- the static appearance work and the new settings wouldn't apply.
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate.nameplate then
            plate:SetUnit(plate.unit, plate.nameplate)
        end
    end
    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
    if ns.ApplyClassPowerSetting then ns.ApplyClassPowerSetting() end
    -- 12.1 aura containers: fingerprint-guarded, near-free when no aura
    -- settings changed.
    if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
end

-------------------------------------------------------------------------------
--  Non-Target Opacity: while the player has a target, every skinned plate
--  that is not the target, the focus, or the player fades to the configured
--  opacity (profile key nonTargetAlpha, 0-100). 100 = feature OFF: every
--  hook below reduces to a single numeric compare, and no plate is ever
--  touched. The alpha rides the plate ROOT (our own frame, parented to the
--  Blizzard nameplate), so Blizzard's own occlusion fade still multiplies in.
-------------------------------------------------------------------------------
ns._ntAlpha = 1   -- cached 0..1 from the profile; 1 = inert

-- Applies the correct root alpha to ONE plate. Value-guarded via
-- _ntCurAlpha so redundant SetAlpha calls are skipped and pooled frames
-- reset cheaply (nil = never faded).
function ns.NT_Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local a = 1
    local nt = ns._ntAlpha
    if nt < 1 and UnitExists("target")
       and not UnitIsUnit(unit, "target")
       and not UnitIsUnit(unit, "focus")
       and not UnitIsUnit(unit, "player") then
        a = nt
    end
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

-- Re-derives the cached opacity from the profile and reapplies every plate
-- (also un-fades everything when the slider returns to 100). Called from
-- the options slider, OnInitialize, and RefreshAllSettings -- the latter
-- covers profile swaps and Spec Overrides applies.
function ns.NT_RefreshSetting()
    local v = tonumber(p and p.nonTargetAlpha) or 100
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    ns._ntAlpha = v / 100
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
        else
            ns.HideHoverEffect(plate)
        end
    end
    for _, plate in pairs(ns.friendlyPlates or {}) do
        if plate.highlight then
            plate.highlight:SetColorTexture(c.r, c.g, c.b, a)
        end
        if plate == ns._currentMouseoverPlate then
            ns.ShowHoverEffect(plate)
        else
            ns.HideHoverEffect(plate)
        end
    end
end

local kickWatcher = CreateFrame("Frame")
local activeCastCount = 0
-- PERF: set of plates currently casting so kick/color updates iterate only
-- the 1-3 casting plates instead of all 20+ plates in the scene.
-- Stored on ns to avoid 200-local pressure.
ns._castingPlates = {}
kickWatcher:SetScript("OnEvent", function(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        -- Diet: no per-event cast-info re-reads or geometry. Cast identity
        -- (protection/channel flags) is cached by UpdateKickTick at cast
        -- setup and by the INTERRUPTIBLE event handlers on mid-cast flips;
        -- cooldown events only need the marker value + alpha refresh.
        -- Hidden tick = re-setup from cache (kick learned mid-cast, CD
        -- info late, toggle flipped on) -- its own early-outs keep that
        -- cheap.
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
        -- Arm the throttled cast-timer OnUpdate to render on its first
        -- tick (accumulator starts at threshold) so the timer text is
        -- never blank for the first 0.1s of a cast.
        if plate.cast then plate.cast._timerAcc = 0.1 end
    end
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _castColorTicker then
            _castColorTicker = C_Timer.NewTicker(0.2, function()
                for pl in pairs(ns._castingPlates) do
                    -- type() is the safe existence check: _kickProtected
                    -- holds a possibly-SECRET boolean and equality
                    -- comparison against nil would evaluate it
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

-- PERF: cached plate references for target/focus so we can update only
-- the old + new plate on target/focus change instead of iterating all.
-- Stored on ns to avoid 200-local pressure (4 locals saved).
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
        -- Friendly player CVars are only written when EUI is managing
        -- friendly player nameplates. When the user disables the "Show EUI
        -- Friendly Player Nameplates" toggle we relinquish control fully
        -- and leave these CVars alone so Blizzard's own Nameplate settings
        -- own them. Friendly NPC and enemy pet CVars are always managed.
        if showPlayers then
            SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0)
            SetCVar("nameplateShowFriendlyPlayers", 1)
            SetCVar("UnitNameFriendlyPlayerName", 1)
            SetCVar("nameplateShowFriends", 1)
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
        -- nameplateOverlapV is intentionally left alone: it is the user's own
        -- vertical-spacing cvar (Blizzard default 1.10, same value we used to
        -- force here, so no existing plate spacing changes). Players who tune it
        -- themselves are no longer overwritten every login. Our "Stacked
        -- Nameplate Spacing" slider layers extra spacing on top via the
        -- stacking-bounds frame.
        SetCVar("nameplateMaxAlpha", 1)
        SetCVar("nameplateMaxAlphaDistance", 40)
        SetCVar("nameplateMinAlpha", 0.6)
        SetCVar("nameplateMinAlphaDistance", -100000)
        SetCVar("nameplateMaxDistance", 60)
        SetCVar("nameplateMaxScale", 1)
        -- Neutralize Blizzard's selected-target scaling. The EUI plate is a child
        -- of the base nameplate, so Blizzard scaling the selected plate shows
        -- through our own SetScale (same reason min/max are pinned to 1). Pinning
        -- this to 1 makes the "Scale Target Nameplate" slider the sole authority,
        -- so at 100% the target plate does not change size at all.
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
    -- Prevent Blizzard from resetting nameplate sizes on display changes,
    -- which causes bouncing/jitter.
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
        -- Hook OnNamePlateAdded to suppress Blizzard UnitFrame as early as
        -- possible before our NAME_PLATE_UNIT_ADDED fires.  This prevents
        -- the initial layout pass from affecting nameplate bounds.
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
--  Class Power Display (combo points, holy power, chi, etc.)
--  Zero cost when disabled: no events registered, no frames created.
--  When enabled, a single watcher frame handles UNIT_POWER_UPDATE for "player"
--  and shows pips only on the current target's nameplate.
-------------------------------------------------------------------------------
local classPowerWatcher
local classPowerType     -- Enum.PowerType value for the player's class resource, or nil
local classPowerMax = 0  -- max pips for the resource
local classPowerFormReq  -- required GetShapeshiftFormID() value, or nil if no form check needed
local CP_PIP_W, CP_PIP_H, CP_PIP_GAP = 8, 3, 2  -- pip geometry

-- Optional pip shapes. Rectangle (default) and square are plain boxes (no mask);
-- the rest are carved from a square fill by a portrait-set mask, with a matching
-- border texture. Reuses the same shape art the Cooldown Manager uses.
-- Packed onto ns (not file locals) to stay under Lua's 200 main-chunk local limit.
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

-- Resource-icon shapes: real Blizzard atlas art instead of a tinted shape.
-- Each draws a class's resource art (rune, holy power, soul shard, combo
-- points, chi, arcane charges, essence). All on ns (no main-chunk locals).
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

-- Resolve class/power color from EUI global system.
-- For bar-type power keys (_BAR suffix), returns power color.
-- For class resources, returns resource color > class color.
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

-- Map class { powerType, maxPips (fallback) }
-- Entries can be a simple table { type, max } or a spec-keyed table { [specID] = { type, max } }
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
                    [71]  = { "SWEEPING_STRIKES", 12 } },   -- Arms
    DEATHKNIGHT = { [250] = { Enum.PowerType.Runes, 6 },
                    [251] = { Enum.PowerType.Runes, 6 },
                    [252] = { Enum.PowerType.Runes, 6 } },
}

-- Apply the configured shape + optional border to one pip (and its bg).
-- rectangle/square: plain box, no mask; border (if on) is a single solid box
-- behind the pip. Other shapes: carve fill+bg with a mask and frame with the
-- matching border texture. Idempotent; safe to call every refresh. bSize is in
-- pip-local (already pixel-snapped) units.
function ns.ApplyPipShape(plate, pip, shape, borderOn, bc, bSize)
    local bg = pip._bg
    -- Icon shapes draw real atlas art (set in the render): drop mask, borders,
    -- and the dark bg so the art stands alone.
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
        -- Boxy shapes (rectangle/square): one solid box behind the pip, poking
        -- out bSize on every side as a uniform outline. A single texture rounds
        -- as one piece (no per-edge shimmer), staying crisp like the fill.
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

    -- Lock pip width / height / gap to exact physical pixel multiples in the
    -- PLATE'S local coords (pips are parented to the plate, so its effective
    -- scale is what determines screen pixels). PP.Scale snaps to UIParent's
    -- pixel grid, which is wrong here because nameplates have their own
    -- scale stack (nameplate scale * cast/target scale).
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
            -- (i-1) * stride is an exact integer multiple of physical pixels,
            -- so every pip lands on the same pixel grid as its neighbors.
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

            -- Shape mask + optional border (size/anchor are final by now). Skip the
            -- call entirely on the untouched default -- plain rectangle, no border, and
            -- this pip never wore shape decor -- so users who never enable a shape pay
            -- zero added cost here. A pip that ever had a mask/border keeps those fields,
            -- so it still routes through ApplyPipShape to clean up when reverted.
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
                    -- Desaturated socket as the (alpha-controlled) background, lit
                    -- rune on top when filled. Point 5 reuses point 4 mirrored.
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

-- Hide pips on a plate
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
        classPowerWatcher:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
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
-- Out-of-combat darkening, gated by the "Darken Enemies Out of Combat" option.
-- When on (default), enemies confirmed in combat (a clean boolean) keep full
-- colour while out-of-combat / secret states darken; when off, never darkened.
local function MaybeDarken(r, g, b, inCombat)
    local on = (p and p.darkenEnemiesOOC)
    if on == nil then on = defaults.darkenEnemiesOOC end
    if not on then return r, g, b end
    if type(inCombat) == "boolean" and inCombat then return r, g, b end
    return DarkenColor(r, g, b)
end
-- Cached threat-context state — updated at zone transitions and spec changes
local _inThreatContent = false
local _isTankRole      = false

local function RefreshThreatCache()
    -- Zone: party/raid instances and delves (difficultyID 204) are threat-relevant
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- Dungeon-only flag for the "Mini Enemies" trash color (5-man dungeons are
    -- instanceType "party"; excludes raids/delves/open world). Cached here so the
    -- per-plate color path costs one field read, not a GetInstanceInfo call.
    ns._inDungeon = (instanceType == "party")
    if difficultyID == 0
    or (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap()) then
        _inThreatContent = false
    else
        local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
        _inThreatContent = (instanceType == "party" or instanceType == "raid"
                            or isDelve)
    end
    -- Role: cache so we don't recalculate on every nameplate update
    local role = UnitGroupRolesAssigned("player")
    if role == "NONE" and GetSpecializationRole then
        local spec = GetSpecialization()
        if spec then role = GetSpecializationRole(spec) or "NONE" end
    end
    _isTankRole = (role == "TANK")
end

local function InRealInstancedContent()
    return _inThreatContent
end

-------------------------------------------------------------------------------
--  Quest Mob Detection
--  Uses C_TooltipInfo to scan unit tooltips for quest objective lines.
--  Cached per unit; invalidated on QUEST_LOG_UPDATE and NAME_PLATE_UNIT_REMOVED.
-------------------------------------------------------------------------------
local questMobCache = {}
-- Parallel cache of verified-clean "objectives remaining" strings, keyed by
-- unit. Populated only when replaceQuestIconWithObjective is ON; shares the
-- exact invalidation lifecycle as questMobCache. Stored on ns (not a new
-- file-scope local) because this file is near the Lua 5.1 local cap.
ns._questObjText = ns._questObjText or {}
local QUEST_LINE_TYPES
if Enum and Enum.TooltipDataLineType then
    QUEST_LINE_TYPES = {
        [Enum.TooltipDataLineType.QuestObjective] = true,
        [Enum.TooltipDataLineType.QuestTitle] = true,
        [Enum.TooltipDataLineType.QuestPlayer] = true,
    }
end

local function IsQuestMob(unit)
    if not C_TooltipInfo or not QUEST_LINE_TYPES then return false end
    if questMobCache[unit] ~= nil then return questMobCache[unit] end
    -- Quest mobs are open-world only, unless the indicator's "Show In
    -- Instances" opt-in lifts the gate (safe: every tooltip-line read below
    -- is pcall'd and escape values are issecretvalue-verified, so instanced
    -- combat cannot leak or error on secret text).
    if InRealInstancedContent() then
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if not show then
            questMobCache[unit] = false
            return false
        end
    end
    local info = C_TooltipInfo.GetUnit(unit)
    if not info then
        questMobCache[unit] = false
        return false
    end
    local playerName = UnitName("player")
    local isInGroup = IsInGroup()
    local ignoreUntilTitle = false
    for _, line in ipairs(info.lines or {}) do
        local lt = line.type
        if not QUEST_LINE_TYPES[lt] then
            -- skip non-quest lines
        elseif lt == Enum.TooltipDataLineType.QuestPlayer then
            -- In a group, only color for YOUR quests
            -- Use pcall to safely compare leftText — it may be a tainted secret
            -- string value in certain combat/nameplate contexts
            if isInGroup then
                local ok, result = pcall(function() return line.leftText ~= playerName end)
                ignoreUntilTitle = ok and result or false
            end
        elseif lt == Enum.TooltipDataLineType.QuestTitle then
            ignoreUntilTitle = false
        elseif lt == Enum.TooltipDataLineType.QuestObjective and not ignoreUntilTitle then
            -- leftText may be a tainted secret string; wrap in pcall
            local ok, isIncomplete = pcall(function()
                local txt = line.leftText or ""
                local c1, c2 = txt:match("(%d+)/(%d+)")
                if c1 and c1 ~= c2 then return true end
                local pct = txt:match("(%d+)%%")
                if pct and pct ~= "100" then return true end
                return false
            end)
            if ok and isIncomplete then
                questMobCache[unit] = true
                -- Optional progress extraction for the icon-replace feature.
                -- Fully gated by the setting: nothing here runs when OFF.
                -- Isolated in its own pcall so a secret/tainted leftText can
                -- never disturb the boolean decision above. We never branch on
                -- the (possibly secret) values; the count ("current/required")
                -- or percentage string escapes only if it is clean (issecretvalue
                -- + a strict digit pattern, both inside the pcall); otherwise
                -- nothing is cached and the icon is used.
                if p and p.replaceQuestIconWithObjective == true then
                    local okN, rem = pcall(function()
                        local txt = line.leftText or ""
                        local c1, c2 = txt:match("(%d+)/(%d+)")
                        if c1 and c2 and c1 ~= c2 then
                            local s = c1 .. "/" .. c2
                            if (not issecretvalue or not issecretvalue(s))
                               and s:match("^%d+/%d+$") then
                                return s
                            end
                        end
                        -- Percent-based objective (e.g. "50%") has no
                        -- current/required pair; show the percentage itself.
                        -- Same clean-value gate as the count path: the string
                        -- escapes only when verifiably non-secret.
                        local pct = txt:match("(%d+)%%")
                        if pct and pct ~= "100" then
                            local s = pct .. "%"
                            if (not issecretvalue or not issecretvalue(s))
                               and s:match("^%d+%%$") then
                                return s
                            end
                        end
                        return nil
                    end)
                    if okN and type(rem) == "string" then
                        ns._questObjText[unit] = rem
                    else
                        ns._questObjText[unit] = nil
                    end
                end
                return true
            end
        end
    end
    questMobCache[unit] = false
    return false
end
ns.IsQuestMob = IsQuestMob

-- Thin reader for the icon-replace feature. Returns a clean digit string or nil.
function ns.GetQuestObjectiveText(unit)
    return ns._questObjText[unit]
end

-- Live refresh for the options toggle. Wiping BOTH caches is required because
-- IsQuestMob short-circuits on questMobCache[unit] ~= nil; a unit cached while
-- the setting was OFF would never get its objective text extracted otherwise.
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
-- Neutral health-bar color: the enemy-in-combat tint while the unit is in combat,
-- otherwise the neutral color. Shared by every precedence step that resolves to
-- "neutral" so they stay in lockstep: high-priority step 5, the neutral+mini
-- carve-out (step 7b), and the deferred dungeon step 10d.
local function ResolveNeutralColor(unit)
    if UnitAffectingCombat(unit) then
        local c = _C("enemyInCombat")
        return c.r, c.g, c.b
    end
    local c = _C("neutral")
    return c.r, c.g, c.b
end
local function GetReactionColor(unit)
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
    -- Non-tank: has aggro, near aggro
    -- Tank: losing aggro, no aggro
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
                    local c = _C("dpsNearAggro")
                    return c.r, c.g, c.b
                end
                end
            else
                -- Tank: losing aggro / no aggro absolute priority
                if status < 3 and status >= 2 then
                    local c = _C("tankLosingAggro")
                    return c.r, c.g, c.b
                elseif status < 3 then
                    -- Only show no-aggro warning if a non-tank has it.
                    -- If another tank holds aggro, this is normal offtank positioning.
                    local unitTarget = unit .. "target"
                    local targetRole = UnitExists(unitTarget) and UnitGroupRolesAssigned(unitTarget) or "NONE"
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
    -- 5. Neutral (colored as an enemy while in combat with them). OUTSIDE dungeons
    -- this keeps its high priority. IN dungeons it is deferred to just above the
    -- enemy fallback (step 10d) so mob-type / threat colors win on neutral dungeon
    -- units and the neutral color becomes the near-last resort.
    local reaction = UnitReaction(unit, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player"))
    if isNeutral and not ns._inDungeon then
        return ResolveNeutralColor(unit)
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- Classify the unit's mob-type tier once, up front, so the tank has-aggro
    -- override steps below can reason about boss vs mini-boss vs caster
    -- independently. These are booleans only -- the actual mob-type colors are
    -- still returned at their own priority steps (7, 8, 10b) further down.
    local inCombat = UnitAffectingCombat(unit)
    local classification = UnitClassification(unit)
    -- Full Coloring M+ Only (inline cog on Enemy Types): outside 5-man
    -- dungeons, collapse the mob-type special colors (Mini Enemies, Spell
    -- Casters, Mini-Bosses, Bosses) into the single flat owBasicColor at the
    -- enemy fallback (step 11). Neutral is unaffected: outside dungeons it
    -- already returned at step 5. Off by default -- when off (or in a 5-man
    -- dungeon) every step below behaves exactly as before. Same dungeon gate
    -- as Mini Coloring M+ Only (ns._inDungeon).
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
        -- Effective level (handles level scaling / Chromie time), not raw level.
        local level = UnitEffectiveLevel(unit)
        local playerLevel = UnitEffectiveLevel("player")
        local lvlClean = level and not (issecretvalue and issecretvalue(level))
        local plvlClean = playerLevel and not (issecretvalue and issecretvalue(playerLevel))
        if lvlClean and (level == -1 or (plvlClean and level >= playerLevel + 1)) then
            -- Tier by effective-level delta (how the game ranks instance mobs):
            -- ?? (skull) or player+2 and up = boss; player+1 = mini-boss. World
            -- bosses are always bosses; a flagged lieutenant is always a mini-boss.
            local isBoss = (classification == "worldboss")
                or (level == -1)
                or (plvlClean and level >= playerLevel + 2)
            if level ~= -1 and UnitIsLieutenant and UnitIsLieutenant(unit) then
                isBoss = false
            end
            if isBoss then
                _isBossUnit = true
            else
                _isMiniBoss = true
            end
        end
    end
    local unitClass = UnitClassBase and UnitClassBase(unit)
    local _isCaster = not owBasic and (unitClass == "PALADIN")
    -- DPS/healer No Aggro override state (mirrors the tank has-aggro overrides at
    -- 6b). Each override independently promotes the No Aggro color above a single
    -- mob-type step (mini-boss step 7, caster step 8). Only active for a non-tank
    -- without aggro in a group -- the exact condition the low-priority No Aggro
    -- step (10) uses. Off by default, so default behavior is unchanged.
    local dpsNoAggroActive = isThreatUnit and (not _isTankRole) and threatStatus < 2 and IsInGroup()
    if dpsNoAggroActive then
        local en = defaults.dpsNoAggroEnabled
        if db.dpsNoAggroEnabled ~= nil then en = db.dpsNoAggroEnabled end
        dpsNoAggroActive = en
    end
    -- 6b. Tank has aggro -- "Override Mini-Boss and Caster colors" option.
    -- Promotes the has-aggro color above the mini-boss/caster steps (but still
    -- below target/focus/enemy-class). Boss units are excluded here -- they are
    -- governed by the separate "Override Boss colors" option (step 9/10b). Sits
    -- between the absolute-priority Classic Tank Aggro path (handled above) and
    -- the default low-priority path (step 9). Off by default, so the default
    -- behavior is unchanged.
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
    -- 7. Mini-boss. Boss is intentionally LOWER priority than the low-priority
    -- threat colors below, so it is deferred to step 10b (see _isBossUnit);
    -- mini-boss stays here, above threat.
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
    -- 7b. Mini Enemies promoted ABOVE Caster -- but ONLY for DPS/healers and for
    -- tanks that do NOT use the special Tank Has Aggro color. Tanks WITH that
    -- option enabled skip this and keep Mini Enemies at its original low priority
    -- (step 10c), so their has-aggro / caster / mob-type colors still win on trash.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        -- Neutral + mini-enemy: neutral coloring wins over the trash color, for
        -- ALL viewers. Placed above the tank-role gate, the DPS carve-out, and the
        -- Mini Enemies return below, so a neutral mini beats them (and Caster too,
        -- since 7b already sits above step 8). Non-trash neutral units are not
        -- caught here and still defer to step 10d.
        if isNeutral then return ResolveNeutralColor(unit) end
        local thae = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then thae = db.tankHasAggroEnabled end
        if not (_isTankRole and thae) then
            -- DPS "No Aggro" still wins over the promoted Mini Enemies color, so a
            -- DPS/healer without aggro sees the no-aggro warning on trash instead
            -- of the trash color. Scoped to this trash branch, so Caster still
            -- outranks DPS No Aggro on non-trash casters (step 10). Mirrors the
            -- step 10 condition exactly.
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
        -- DPS/healer No Aggro "Override Caster colors": promotes the No Aggro
        -- color above the caster color when enabled. Kept separate from the
        -- mini-boss override so Casters can stay their own color for contrast.
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
    -- 9. Tank has aggro (if enabled) below focus/caster/miniboss. Normally sits
    -- above the boss color (step 10b); when "Override Boss colors" is disabled the
    -- has-aggro color is held below the boss color instead (the 10b boss return
    -- wins for boss units, so the has-aggro color lands just below bosses).
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
    -- 10b. Boss (intentionally below the low-priority threat colors above, so a
    -- tank-has-aggro / dps-no-aggro color takes precedence over the boss color --
    -- unless the tank "Override Boss colors" option is disabled, in which case the
    -- has-aggro step above defers to this boss color for boss units).
    if _isBossUnit then
        local c = _C("boss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10c. Mini Enemies: non-elite trash (normal/minus), DUNGEONS ONLY. Gives
    -- 5-man trash its own color; outside dungeons these fall through to the enemy
    -- color below. Elites are handled at step 7, so same-level elites still use
    -- the enemy color. Sits below the threat colors so aggro state still wins.
    -- NOTE: DPS/healers and non-special-aggro tanks already returned at step 7b
    -- (Mini Enemies promoted above Caster); this low-priority path now only
    -- applies to tanks with the special "Has Aggro" color enabled.
    if miniColorScope
       and (classification == "normal" or classification == "minus" or classification == "trivial") then
        -- Views the user's "Enemies" color (enemyInCombat) until they explicitly
        -- set a Mini Enemies color, so trash starts identical to before.
        local c = (p and p.miniEnemy) or _C("enemyInCombat")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10d. Neutral, deferred (dungeons only -- step 5 skipped it there). The
    -- mob-type and threat colors above have had their turn; a neutral unit that
    -- matched none of them uses the neutral color here, just above the generic
    -- enemy fallback. (Outside dungeons, neutral already returned at step 5, so
    -- isNeutral can only be true here when in a dungeon.)
    if isNeutral then
        return ResolveNeutralColor(unit)
    end
    -- 11. Fallback: enemy in combat / out of combat. With Full Coloring M+
    -- Only active, every mob-type special above was suppressed, so all
    -- hostile mobs land here and share the flat "All Enemies" color.
    local eic = _C(owBasic and "owBasicColor" or "enemyInCombat")
    return MaybeDarken(eic.r, eic.g, eic.b, inCombat)
end
local hookedUFs = {}
local hookedHighlights = {}
local hookedAurasFrames = {}
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
    -- Suppress unconditionally -- if we're called, an EUI plate is taking
    -- over this nameplate. Never gate on UnitCanAttack: that API can return
    -- false on the first frame (unit not fully registered yet), which skips
    -- the entire block and leaves Blizzard's UnitFrame visible behind ours
    -- as a giant black box.
    uf:SetAlpha(0)
    if uf.healthBar then
        uf.healthBar:SetParent(npOffscreenParent)
    end
    -- Move visual children off the UnitFrame so Blizzard's layout engine
    -- stops recalculating bounds from them.
    MoveToOffscreen(uf.HealthBarsContainer, unit)
    MoveToOffscreen(uf.castBar, unit)
    MoveToOffscreen(uf.name, unit)
    MoveToOffscreen(uf.selectionHighlight, unit)
    MoveToOffscreen(uf.aggroHighlight, unit)
    MoveToOffscreen(uf.softTargetFrame, unit)
    MoveToOffscreen(uf.SoftTargetFrame, unit)
    MoveToOffscreen(uf.ClassificationFrame, unit)
    MoveToOffscreen(uf.RaidTargetFrame, unit)
    MoveToOffscreen(uf.PlayerLevelDiffFrame, unit)
    if uf.BuffFrame then uf.BuffFrame:SetAlpha(0) end
    -- Move AurasFrame list frames offscreen -- we query C_UnitAuras
    -- directly for debuff/CC data so these visual lists are unused.
    if uf.AurasFrame then
        MoveToOffscreen(uf.AurasFrame.DebuffListFrame, unit)
        MoveToOffscreen(uf.AurasFrame.BuffListFrame, unit)
        MoveToOffscreen(uf.AurasFrame.CrowdControlListFrame, unit)
        MoveToOffscreen(uf.AurasFrame.LossOfControlFrame, unit)
    end
    -- All visual children are reparented offscreen so layout
    -- recalculations won't shift bounds.
    -- Only silence the castBar events (we render our own cast bar).
    if uf.castBar then
        uf.castBar:UnregisterAllEvents()
    end
    -- Keep WidgetContainer functional but reparent it to the nameplate
    -- itself so its layout doesn't affect the UnitFrame's bounds.
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(nameplate)
    end
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            -- Only force alpha 0 while an EUI plate owns this nameplate.
            -- When the nameplate is recycled for a friendly unit, the EUI
            -- plate is released and ns.plates[unit] is nil, so the hook
            -- becomes a no-op and Blizzard can show the friendly frame.
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if not ufUnit or not ns.plates[ufUnit] then return end
            locked = true
            self:SetAlpha(0)
            locked = false
        end)
    end
    -- Hook RefreshAuras on Blizzard's AurasFrame so we refresh AFTER
    -- debuffList/buffList have been updated. This eliminates the race
    -- where our UNIT_AURA handler fires before Blizzard processes the
    -- event, leaving debuffList stale.
    -- DISPATCH-ORDER REALITY: the uf registers for UNIT_AURA below
    -- BEFORE the plate does, and WoW dispatches in registration order,
    -- so this hook usually fires BEFORE our handler has stashed the
    -- event payload. The hook therefore has three paths: stashed
    -- payload -> process with relevance gating; no stash + first paint
    -- -> immediate rebuild; no stash otherwise -> owe ONE deferred
    -- authoritative rebuild (never rebuild ungated per event -- that
    -- was the rebuild storm that negated every fast path).
    if uf.AurasFrame and not ns.NPC_OwnsAuras and not hookedAurasFrames[uf.AurasFrame] then
        hookedAurasFrames[uf.AurasFrame] = true
        hooksecurefunc(uf.AurasFrame, "RefreshAuras", function(af)
            if af:IsForbidden() then return end
            local parent = af:GetParent()
            if not parent then return end
            local ufUnit = parent.unit or (parent.GetUnit and parent:GetUnit())
            if not ufUnit then return end
            local plate = ns.plates[ufUnit]
            if plate and plate.unit then
                local pending = plate._pendingAuraUpdate
                if pending then
                    -- Our UNIT_AURA handler stashed this event's payload:
                    -- debuffList is now current, process with full
                    -- relevance gating.
                    plate._pendingAuraUpdate = nil
                    plate._auraFallbackPending = nil
                    plate:UpdateAuras(pending)
                elseif not plate._shownAuras then
                    -- First paint for this plate: rebuild immediately
                    plate:UpdateAuras(nil)
                else
                    -- No stash yet: either this RefreshAuras is about to be
                    -- paired with our UNIT_AURA handler, or it is a non-event
                    -- re-filter. Wait one frame so UNIT_AURA can supply a
                    -- gated payload; if it never arrives, drain does one full
                    -- rebuild.
                    plate._auraAwaitingUnitAura = true
                    plate:QueueAuraFallback()
                end
            end
        end)
    end
    -- PERF: mark plate as having the RefreshAuras hook so UNIT_AURA can
    -- stash its payload for the hook (or the next-frame dispatcher)
    -- instead of rebuilding directly -- avoids double processing and
    -- keeps debuffList reads on the post-refresh side.
    local plate2 = ns.plates[unit]
    if plate2 and uf.AurasFrame and hookedAurasFrames[uf.AurasFrame] then
        plate2._hasRefreshAurasHook = true
    end
    -- Keep Blizzard's UnitFrame processing UNIT_AURA so its
    -- debuffList/buffList stay current for our importance filter.
    -- (12.1 containers: those lists are taint-locked and unused -- skip.)
    if unit and uf.AurasFrame and not ns.NPC_OwnsAuras then
        uf:RegisterUnitEvent("UNIT_AURA", unit)
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
-- Restore Blizzard UnitFrame elements when a nameplate is removed, so the
-- recycled nameplate frame is in a clean state for the next unit.
local function RestoreBlizzardFrame(nameplate)
    if not nameplate then return end
    local uf = nameplate.UnitFrame
    if not uf then return end
    -- Restore reparented children
    if uf.healthBar and storedParents[uf.healthBar] then
        uf.healthBar:SetParent(storedParents[uf.healthBar])
        storedParents[uf.healthBar] = nil
    end
    RestoreFromOffscreen(uf.HealthBarsContainer)
    RestoreFromOffscreen(uf.castBar)
    RestoreFromOffscreen(uf.name)
    RestoreFromOffscreen(uf.selectionHighlight)
    RestoreFromOffscreen(uf.aggroHighlight)
    RestoreFromOffscreen(uf.softTargetFrame)
    RestoreFromOffscreen(uf.SoftTargetFrame)
    RestoreFromOffscreen(uf.ClassificationFrame)
    RestoreFromOffscreen(uf.RaidTargetFrame)
    RestoreFromOffscreen(uf.PlayerLevelDiffFrame)
    -- Restore WidgetContainer
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(uf)
    end
    -- Restore AurasFrame children
    if uf.AurasFrame then
        local af = uf.AurasFrame
        RestoreFromOffscreen(af.DebuffListFrame)
        RestoreFromOffscreen(af.BuffListFrame)
        RestoreFromOffscreen(af.CrowdControlListFrame)
        RestoreFromOffscreen(af.LossOfControlFrame)
    end
end
ns.HideBlizzardFrame = HideBlizzardFrame
local castFallbackFrame = CreateFrame("Frame")
local fallbackCastCount = 0
local _fallbackPlates = {}
castFallbackFrame._textAccum = 0.1
castFallbackFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Bar fill tracks every frame (smoothness); the target TEXT only
    -- refreshes at 10 Hz -- names do not change faster than that and
    -- SetText per frame is wasted, especially with secret strings.
    -- (accumulator lives on the frame: this file is at the 200-local cap)
    local textAccum = self._textAccum + elapsed
    local doText = textAccum >= 0.1
    self._textAccum = doText and 0 or textAccum
    for plate in pairs(_fallbackPlates) do
        if plate.isCasting and plate.unit and plate.nameplate then
            local bc = plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                plate.cast:SetMinMaxValues(bc:GetMinMaxValues())
                plate.cast:SetValue(bc:GetValue())
                -- Update cast target in fallback mode (not handled by UpdateCast)
                if doText and plate.castTarget then
                    local tgt
                    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(plate.unit) then
                        tgt = UnitSpellTargetName and UnitSpellTargetName(plate.unit)
                    end
                    -- tgt may be a SECRET string: truthiness (tgt or "")
                    -- would error; type() is the safe nil check and
                    -- SetText accepts secret strings natively.
                    if type(tgt) == "nil" then
                        plate.castTarget:SetText("")
                    else
                        plate.castTarget:SetText(tgt)
                    end
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

-- Pandemic glow alpha-only tick: only iterates slots with active pandemic
-- glows. Lives on ns (NOT a local): the registrar (ApplyPandemicGlow) is
-- inside the glow-engine do/end block and cannot see file locals declared
-- out here -- a block-local forward declaration shipped this ticker dead.
ns._pandemicTickFrame = CreateFrame("Frame")
local pandemicTickAccum = 0
ns._pandemicTickFrame:SetScript("OnUpdate", function(self, elapsed)
    pandemicTickAccum = pandemicTickAccum + elapsed
    if pandemicTickAccum < 0.2 then return end
    pandemicTickAccum = 0
    if not GetPandemicGlow() then self:Hide(); return end
    local anyActive = false
    for slot in pairs(ns.activePandemicSlots) do
        anyActive = true
        local durObj = slot._durationObj
        if durObj and slot.pandemicGlow and slot.pandemicGlow.active then
            slot.pandemicGlow.wrapper:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, durObj:EvaluateRemainingPercent(ns.pandemicCurve)))
        else
            ns.StopPandemicGlow(slot)
        end
    end
    if not anyActive then self:Hide() end
end)
ns._pandemicTickFrame:Hide()  -- start hidden; shown when pandemic glows activate

-- Shared cast-bar text anchoring. The cast bar text line holds three elements --
-- spell name, spell target, cast timer -- each assigned to a side ("left" |
-- "right" | "center"). The cast timer reserves a fixed slot of width on its side;
-- a non-center element sharing the timer's side is shifted inward by that width to
-- make room (mirrors how the target has always been pushed left by the timer).
-- Center elements anchor to the bar center and are never pushed.
--
--   side    : "left" | "right" | "center"
--   pushed  : true when the timer occupies this same side and this element must move inward
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

-- WoW does not visually re-lay-out a FontString when only its SetJustifyH changes;
-- a fresh build does, which is why a /reload looked right but an in-place side
-- change did not. Clearing then re-setting the text forces the new alignment to
-- take effect, and it MUST be a real change -- re-setting the identical string is
-- deduped and skips the re-layout. (Same trick as the raid frame name text.)
-- GetText may return a secret (enemy name, cast name/target). SetText accepts
-- secrets and never inspects the value, but truthiness/equality on a secret errors,
-- so the existence check uses type() rather than `t or ""`. This makes the helper
-- safe to call on the enemy-name FontString (whose text is a secret for hostile
-- units), not just the cast strings.
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

-- Appearance generation: bumped by RefreshAllSettings so plates re-apply
-- static appearance on next SetUnit. Plates stamp _appearanceGen after
-- applying so cache-hit re-spawns skip the work entirely.
ns._npAppearanceGen = ns._npAppearanceGen or 1

-- Static appearance: anchors, sizes, fonts, colors, and aura layout that
-- only depend on settings (not on the bound unit). Runs once per plate
-- after creation, then again only when RefreshAllSettings bumps the
-- generation counter. Cuts ~0.7 ms off every plate spawn.
function NameplateFrame:ApplyAppearance()
    self:SetSize(1, 1)
    local castH = GetCastBarHeight()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.absorb:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    -- Width may have changed: clear the overlay state gates so the next
    -- overlay apply re-runs geometry (the stripe texcoord crop is derived
    -- from the settings width, and the gates never watch width).
    self._ovTgtTex, self._ovFocTex, self._ovHoverTex = nil, nil, nil
    ns.LayoutCastBar(self, ns.GetHealthBarWidth(), castH)
    ns.LayoutCastIcon(self, castH)
    local showIcon = GetShowCastIcon()
    if showIcon then
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    self.castLeftBorder:SetWidth(1)
    self.castSpark:SetHeight(castH)
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot)
    local nameSlotKey = FindSlotForElement("enemyName")
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
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
            self.castName:SetWidth(castW * cnWPct / 100)
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
        -- timerW stays the layout reserve (it pushes name/target inward above), but
        -- the timer FontString itself auto-sizes (width 0) so a long value never
        -- truncates. The string is pinned by its outer edge (RIGHT for right side,
        -- LEFT for left side), so overflow grows inward past the reserved slot while
        -- the pinned edge -- and thus every element positioned off it -- stays fixed.
        self.castTimer:SetWidth(0)
        self.castTimer:SetJustifyH(tjh)
        self.castTimer:ClearAllPoints()
        self.castTimer:SetPoint(tpt, self.cast, tpt, txb + tmOX, tmOY)
    end
    -- Base visibility by side (UpdateCast refines the target per cast on hasTarget).
    self.castName:SetShown(nameSide ~= "none")
    self.castTarget:SetShown(targetSide ~= "none")
    self.castTimer:SetShown(showTimer)
    -- Force the new justify to take effect on text that is already rendered (e.g.
    -- changing the side while a plate is mid-cast). A fresh cast re-flows on its own
    -- because UpdateCast sets the text after this, but a live setting change does not.
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
    end
    for i = 1, 4 do
        ns.ApplyAuraSlotCrop(self.buffs[i], buffCrop, buffSz)
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
    -- Re-sync the cast-bar wrap LAST -- after the normal borders and the
    -- cast-overlay lift have been re-applied this pass. For a wrapped plate this
    -- re-hides the borders ApplyBorder/ApplyCastBorder just re-showed (no double
    -- border) and matches the host to the current lift state. Gated so it is a
    -- pure no-op unless the feature is enabled or this plate is already wrapped.
    if self.UpdateBorderWrap and (self._wrapActive or ns.GetWrapBorderCastbar()) then
        self:UpdateBorderWrap()
    end
    ns.ApplySlotStrata(self)
end

-- PERF: Set up health text font, position, color, and cache slot assignments.
-- Called from ApplyAppearance (settings change / fresh plate), NOT on every
-- health tick.  UpdateHealthValues only updates text content via the cache.
function NameplateFrame:ApplyHealthTextAppearance()
    self.hpText:Hide()
    self.hpNumber:Hide()
    if not self._cachedHealthSlots then
        self._cachedHealthSlots = { _count = 0 }
    end
    local ca = self._cachedHealthSlots
    local ci = 0

    for si = 1, #HP_BAR_SLOTS do
        local slot = HP_BAR_SLOTS[si]
        local element = GetTextSlot(slot.key)
        local txOff, tyOff = GetTextSlotOffsets(slot.key)
        local slotFontSz = GetTextSlotSize(slot.key)
        local sr, sg, sb = GetTextSlotColor(slot.key)
        if element == "healthPercent" or element == "healthPercentNoSign" then
            local fs = self.hpText
            fs:SetParent(self.healthTextFrame)
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
            fs:SetParent(self.healthTextFrame)
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
            fs:SetParent(self.healthTextFrame)
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
        fs:SetParent(self.topTextFrame)
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
    end
    ca._count = ci
    -- Per-slot health % decimal preference. Resolved here (appearance pass,
    -- rare) and cached on each entry + an _anyDecimal flag so the per-tick
    -- render in UpdateHealthValues stays lean.
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
        -- Per-slot Width % (of the health bar; default 100 = full bar width = no
        -- visible clip for normal-length health text) + Wrap. SetWidth/SetWordWrap
        -- re-flow the FontString on their own (only SetJustifyH needs an explicit
        -- ReflowFontString), and UpdateHealthValues re-sets the text right after
        -- this on the same SetUnit pass, so no reflow is needed here.
        -- Default 100% = unconstrained (SetWidth 0 = auto-size); a width box on a
        -- single-point-anchored FontString ignores SetJustifyH and would re-centre
        -- a right/left value. Only impose a box when the user narrows it (< 100%).
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
    -- Recycled/fresh plate: forget any prior eased scale so the first
    -- ApplyScale snaps to the right size instead of growing in from a stale one.
    self._curScale = nil
    ns._scaleAnim[self] = nil
    if ns._hitboxOverlayShown or self.hitboxOverlay then ns._ApplyHitboxOverlay(self) end
    -- Apply static appearance only when stale (settings changed or fresh
    -- pool plate). Cache-hit re-spawns skip this entirely.
    if self._appearanceGen ~= ns._npAppearanceGen then
        self:ApplyAppearance()
        self._appearanceGen = ns._npAppearanceGen
    end
    HideBlizzardFrame(nameplate, unit)
    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    -- 12.1 containers own the aura rows and the legacy UNIT_AURA handler
    -- chain ends in an inert UpdateAuras -- skip the registration entirely
    -- (dead event delivery per plate per aura change otherwise).
    if not ns.NPC_OwnsAuras then
        self:RegisterUnitEvent("UNIT_AURA", unit)
    end
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    -- 12.1: attach a pooled aura-container bundle for this unit.
    if ns.NPC_AttachPlate then ns.NPC_AttachPlate(self, unit) end
    -- Non-Target Opacity (zero cost while off: one numeric compare).
    if ns._ntAlpha < 1 then ns.NT_Apply(self) end
    -- Critical: health bar must display immediately
    self:UpdateHealth()
    -- PERF: defer non-critical work 1 frame. Stacking bounds, name, cast bar,
    -- classification, raid icon, target glow, mouseover -- all imperceptible
    -- if they appear 1 frame late. Cuts ~40% off the plate-add spike.
    self._castDirtyFull = true
    if not self._deferredSetupCB then
        self._deferredSetupCB = function()
            if not self.unit then return end
            local np = self.nameplate
            -- Stacking bounds
            if np and np.SetStackingBoundsFrame then
                if not self._stackBounds then
                    self._stackBounds = CreateFrame("Frame", nil, np)
                    -- Load-bearing: SetStackingBoundsFrame reads this frame's
                    -- rendered bounds (union of its regions), NOT its SetSize.
                    -- Without a full-size region the bounds rect is empty and
                    -- plates stop stacking. Alpha 0 so it never shows.
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
            self:UpdateAuras()
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
        ns.StopPandemicGlow(dSlot)
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
    -- 12.1: release this plate's aura-container bundle back to the pool.
    if ns.NPC_DetachPlate then ns.NPC_DetachPlate(self) end
    self.unit = nil
    self.nameplate = nil
    self._shownAuras = nil
    self._pendingAuraUpdate = nil
    self._pendingMeta = nil
    self._pendingCoalesced = nil
    self._auraFallbackPending = nil
    self._auraOwedFull = nil
    self._auraAwaitingUnitAura = nil
    self._lastFullRebuildT = nil
    self._absorbHidden = nil
    self._auraGroupMask = nil
    self._buffsBuiltAttackable = nil
    self._lastHCr, self._lastHCg, self._lastHCb = nil, nil, nil
    self._ovFocShown, self._ovTgtShown = nil, nil
    self._focusLetterShown = nil
    self._kickIsChannel = nil
    self._kickIsEmpowered = nil
    self._kickGeoDirty = nil
    self._castTex = nil
    self._castLockout = nil
    self._nameRaidMarkerShown = nil
    if ns._npDequeueAuraWork then ns._npDequeueAuraWork(self) end
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
            -- Token swap: this plate frame now represents a DIFFERENT
            -- mob. Any in-flight cast display belongs to the old unit;
            -- tear it down and re-evaluate for the new one. (The cooldown
            -- watcher no longer re-reads cast info per event, so this is
            -- the swap's only cast-state self-heal.)
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
            -- Only refresh auras for the lockout when one was actually active
            -- (zero cost when the Cast Lockout feature is off / no lockout).
            if self._castLockout then
                self._castLockout = nil
                self:UpdateAuras()
                if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
            end
            self:UpdateName()
            self._castDirtyFull = true
            self:UpdateCast()
        end
    end

    local curHealth, maxHealth, absorbAmt, maxWithAbsorbs

    if self.hpCalculator and self.hpCalculator.GetMaximumHealth and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)

        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        curHealth = self.hpCalculator:GetCurrentHealth()
        maxHealth = self.hpCalculator:GetMaximumHealth()
        absorbAmt = self.hpCalculator:GetDamageAbsorbs()

        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
        maxWithAbsorbs = self.hpCalculator:GetMaximumHealth()
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
    else
        curHealth = UnitHealth(unit)
        maxHealth = UnitHealthMax(unit)
        absorbAmt = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
        maxWithAbsorbs = maxHealth
    end

    local absorbIsSecret = issecretvalue and issecretvalue(absorbAmt)

    -- PERF: skip ALL absorb work when absorbs are 0 and were already 0.
    -- Most M+ mobs have no absorbs, so this skips ~10 widget calls per tick.
    local absorbZero = not absorbIsSecret and (not absorbAmt or absorbAmt <= 0)
    if absorbZero and self._absorbHidden then
        -- Fast path: absorbs were and still are zero
        self.health:SetMinMaxValues(0, maxHealth)
        self.health:SetValue(curHealth)
    elseif absorbIsSecret then
        self._absorbHidden = false
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

    -- Hash line positioning (target only).
    -- PERF: use cached _isTarget flag set by ApplyTarget instead of
    -- calling UnitIsUnit on every health tick for every plate.
    local hlEnabled = (p and p.hashLineEnabled)
    local hlPct = (p and p.hashLinePercent) or defaults.hashLinePercent
    if hlEnabled and hlPct and hlPct > 0 and self._isTarget then
        local barW = self.health:GetWidth()
        local xPos = barW * (hlPct / 100)
        self.hashLine:ClearAllPoints()
        self.hashLine:SetPoint("TOP", self.health, "TOPLEFT", xPos, 0)
        self.hashLine:SetPoint("BOTTOM", self.health, "BOTTOMLEFT", xPos, 0)
        local hlc = (p and p.hashLineColor) or defaults.hashLineColor
        self.hashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
        self.hashLine:Show()
    else
        self.hashLine:Hide()
    end

    -- PERF: Text content only -- appearance (font, position, color) is set in
    -- ApplyHealthTextAppearance, called from ApplyAppearance.  This path runs
    -- on every UNIT_HEALTH tick so it must be as lean as possible.
    local ca = self._cachedHealthSlots
    if ca and ca._count > 0 then
        local pctText, pctNoSignText, numText
        local pctTextDec, pctNoSignTextDec
        local anyDec = ca._anyDecimal
        if UnitIsDeadOrGhost(unit) then
            pctText = "0%"
            pctNoSignText = "0"
            numText = "0"
            if anyDec then pctTextDec = "0.0%"; pctNoSignTextDec = "0.0" end
        elseif UnitHealthPercent then
            local pctVal = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
            pctText = string.format("%d%%", pctVal)
            pctNoSignText = string.format("%d", pctVal)
            numText = AbbreviateNumbers(curHealth)
            -- Decimal variants computed only when at least one slot opts in.
            if anyDec then
                pctTextDec = string.format("%.1f%%", pctVal)
                pctNoSignTextDec = string.format("%.1f", pctVal)
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
            elseif IsComboHealthText(el) then
                SetCombinedHealthText(fs, el, entry.pctDecimal and pctTextDec or pctText, numText)
            end
        end
    end
end
function NameplateFrame:UpdateHealthColor()
    local unit = self.unit
    if not unit then return end
    -- Skip-if-unchanged: GetReactionColor returns plain profile-sourced
    -- numbers (every return path verified non-secret). Threat events fire
    -- constantly with an unchanged result -- compare against the last
    -- applied values and skip the setter when identical. Cache is nil'd
    -- in ClearUnit; settings edits self-correct via the value compare.
    local hr, hg, hb = GetReactionColor(unit)
    if hr ~= self._lastHCr or hg ~= self._lastHCg or hb ~= self._lastHCb then
        self._lastHCr, self._lastHCg, self._lastHCb = hr, hg, hb
        self.health:SetStatusBarColor(hr, hg, hb)
    end
    -- Focus overlay: show stripe textures on focus target's health bar
    -- Fill clip frame at full alpha, bg clip frame at half alpha.
    -- Apply is value-keyed: redone only when any component of the
    -- would-be state differs from what this plate last applied.
    local db2 = p or defaults
    local focusTex = db2.focusOverlayTexture or defaults.focusOverlayTexture
    if focusTex ~= "none" and UnitIsUnit(unit, "focus") then
        -- Texture path memoized by texture NAME (no per-call concat;
        -- live dropdown changes rebuild it via the name compare)
        if ns._focusOverlayTexName ~= focusTex then
            ns._focusOverlayTexName = focusTex
            ns._focusOverlayTexPath = ns.ResolveOverlayTexPath(focusTex)
        end
        local texPath = ns._focusOverlayTexPath
        local overlayAlpha = db2.focusOverlayAlpha or defaults.focusOverlayAlpha
        local oc = db2.focusOverlayColor or defaults.focusOverlayColor
        local bgAlpha = OverlayBgAlpha(db2.focusOverlayFullBgAlpha, overlayAlpha)
        if not self._ovFocShown or self._ovFocTex ~= texPath
            or self._ovFocAlpha ~= overlayAlpha or self._ovFocBgAlpha ~= bgAlpha
            or self._ovFocR ~= oc.r or self._ovFocG ~= oc.g or self._ovFocB ~= oc.b then
            EnsureFocusOverlay(self)
            self._ovFocShown = true
            self._ovFocTex, self._ovFocAlpha = texPath, overlayAlpha
            self._ovFocBgAlpha = bgAlpha
            self._ovFocR, self._ovFocG, self._ovFocB = oc.r, oc.g, oc.b
            ApplyOverlayGeometry(self.focusOverlayFill, self.focusOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[focusTex] == true)
            self.focusOverlayFill:SetTexture(texPath)
            self.focusOverlayFill:SetAlpha(overlayAlpha)
            self.focusOverlayFill:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipFill:Show()
            self.focusOverlayBg:SetTexture(texPath)
            self.focusOverlayBg:SetAlpha(bgAlpha)
            self.focusOverlayBg:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipBg:Show()
        end
    elseif self.focusClipFill then
        self._ovFocShown = nil
        self.focusClipFill:Hide()
        self.focusClipBg:Hide()
    end
    -- Focus letter: zero-cost when off. Gate the call so a disabled plate pays
    -- only two field reads here (no function call, no UnitIsUnit, no allocation).
    -- The _focusLetterShown term lets a letter that is currently up hide itself on
    -- the refresh that turns the feature off, after which this gate stays cold.
    if db2.focusLetterEnabled or self._focusLetterShown then
        ns.ApplyFocusLetter(self, unit, db2)
    end
    -- Target overlay: identical to focus overlay but for current target
    local targetTex = db2.targetOverlayTexture or defaults.targetOverlayTexture
    if targetTex ~= "none" and UnitIsUnit(unit, "target") then
        if ns._targetOverlayTexName ~= targetTex then
            ns._targetOverlayTexName = targetTex
            ns._targetOverlayTexPath = ns.ResolveOverlayTexPath(targetTex)
        end
        local texPath = ns._targetOverlayTexPath
        local overlayAlpha = db2.targetOverlayAlpha or defaults.targetOverlayAlpha
        local oc = db2.targetOverlayColor or defaults.targetOverlayColor
        local bgAlpha = OverlayBgAlpha(db2.targetOverlayFullBgAlpha, overlayAlpha)
        if not self._ovTgtShown or self._ovTgtTex ~= texPath
            or self._ovTgtAlpha ~= overlayAlpha or self._ovTgtBgAlpha ~= bgAlpha
            or self._ovTgtR ~= oc.r or self._ovTgtG ~= oc.g or self._ovTgtB ~= oc.b then
            ns.EnsureTargetOverlay(self)
            self._ovTgtShown = true
            self._ovTgtTex, self._ovTgtAlpha = texPath, overlayAlpha
            self._ovTgtBgAlpha = bgAlpha
            self._ovTgtR, self._ovTgtG, self._ovTgtB = oc.r, oc.g, oc.b
            ApplyOverlayGeometry(self.targetOverlayFill, self.targetOverlayBg, self.health, ns.OVERLAY_STRIPE_KEYS[targetTex] == true)
            self.targetOverlayFill:SetTexture(texPath)
            self.targetOverlayFill:SetAlpha(overlayAlpha)
            self.targetOverlayFill:SetVertexColor(oc.r, oc.g, oc.b)
            self.targetClipFill:Show()
            self.targetOverlayBg:SetTexture(texPath)
            self.targetOverlayBg:SetAlpha(bgAlpha)
            self.targetOverlayBg:SetVertexColor(oc.r, oc.g, oc.b)
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
        end
    end
    local name = UnitName(unit)
    if type(name) == "string" then
        self.name:SetText(name)
        if p and p.nameRaidMarkerEnabled == true then self:RefreshNamePosition(true) end
    end
end
function NameplateFrame:UpdateClassification()
    if not self.unit then return end
    local slot = GetClassificationSlot()
    local _, iType = GetInstanceInfo()
    local inInstance = (iType == "party" or iType == "raid" or iType == "pvp" or iType == "arena")
    if inInstance then
        -- "Show In Instances" (slot cog on the Rare/Quest Indicator) lifts
        -- the open-world-only gate.
        local show = p and p.classificationShowInInstances
        if show == nil then show = defaults.classificationShowInInstances end
        if show then inInstance = false end
    end
    if slot == "none" or inInstance then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    -- Quest mob indicator takes priority over elite/rare.
    -- When "Replace Quest Icon with Objective" is enabled and a clean remaining
    -- count was cached for this unit, draw that number in place of the crosshair
    -- icon; otherwise fall back to the existing icon untouched.
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
    local nameSlot = FindSlotForElement("enemyName")
    local nameMarkerReserve = (self.nameRaidFrame and self.nameRaidFrame:IsShown()) and (((p and p.nameRaidMarkerSize) or defaults.nameRaidMarkerSize or 14) + 3) or 0
    if nameSlot == "textSlotTop" then
        -- Above the bar: full bar width minus raid marker if shown
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
                if el ~= "none" and el ~= "enemyName" then
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
    local hasNameSlot = FindSlotForElement("enemyName") ~= nil
    local shown = hasNameSlot and not self.cast:IsShown()
    self.name:SetShown(shown)
    if self.nameRaidFrame then self.nameRaidFrame:SetShown(shown and self._nameRaidMarkerShown == true) end
end
-- The full-size cast icon (a child of the cast bar) only occupies its side-slot
-- space while a cast is up, so its reserve is gated on the cast bar being shown
-- (see GetCastIconReserve). Whenever the cast bar shows or hides, re-anchor the
-- side elements that reserve that space -- the target arrow, classification
-- icon, and raid marker -- so they track the icon instead of sitting shoved out
-- by a phantom gap. Zero cost unless the full-size icon is actually enabled;
-- each re-anchor helper no-ops on plates that don't show that element.
function NameplateFrame:RefreshCastIconSideReserve()
    if not (GetShowCastIcon() and ns.GetCastIconFullSize()) then return end
    self:UpdateClassification()
    self:UpdateRaidIcon()
    PositionArrowsOutsideAuras(self)
end

function NameplateFrame:RefreshNamePosition(localOnly)
    local nameSlot = FindSlotForElement("enemyName")
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
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlot == "textSlotLeft" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        PP.Point(self.name, "LEFT", self.health, "LEFT", 4 + txOff + nameMarkerReserve, tyOff)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlot == "textSlotCenter" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        self.name:SetPoint("CENTER", self.health, "CENTER", txOff + (nameMarkerReserve * 0.5), tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    elseif nameSlot == "textSlotRight" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotRight")
        SetFSFont(self.name, GetTextSlotSize("textSlotRight"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        PP.Point(self.name, "RIGHT", self.health, "RIGHT", -2 + txOff, tyOff)
        self.name:SetJustifyH("RIGHT")
        self.name:Show()
    elseif nameSlot == "textSlotTop" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        SetFSFont(self.name, GetTextSlotSize("textSlotTop"), GetNPOutline())
        self.name:SetParent(self.topTextFrame)
        local cpPush = GetClassPowerTopPush(self)
        PP.Point(self.name, "BOTTOM", self.health, "TOP", txOff + (nameMarkerReserve * 0.5), 4 + nameYOff + cpPush + tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
    -- Apply name wrap state here (not just at creation) so the cog toggle takes
    -- effect on the next settings refresh. Off = single line + ellipsis; on = up
    -- to two lines. Reflow so already-rendered text re-lays out under the new mode.
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
        nameRaid:SetParent((nameSlot == "textSlotTop") and self.topTextFrame or self.healthTextFrame)
        nameRaid:SetFrameStrata("MEDIUM")
        nameRaid:SetFrameLevel(901)
        nameRaid:ClearAllPoints()
        local textW = self.name:GetWidth() or 0
        local ok, renderedW = pcall(self.name.GetStringWidth, self.name)
        if ok and type(renderedW) == "number" and not (issecretvalue and issecretvalue(renderedW)) then
            textW = math.min(renderedW, textW)
        end
        if nameSlot == "textSlotLeft" then
            nameRaid:SetPoint("RIGHT", self.name, "LEFT", -3, 0)
        elseif nameSlot == "textSlotRight" then
            nameRaid:SetPoint("RIGHT", self.name, "RIGHT", -textW - 3, 0)
        else
            nameRaid:SetPoint("RIGHT", self.name, "CENTER", -(textW * 0.5) - 3, 0)
        end
        nameRaid:Show()
    elseif nameRaid then
        nameRaid:Hide()
    end
    if localOnly then return end
    self:UpdateAuras()
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
    -- Border Color: recolor the health bar border with the custom target color
    if isTarget and ns.GetTargetGlowBorderColor() then
        if PP then
            local bc = ns.GetTargetBorderColor()
            if ns.IsCustomBorderEnabled() then
                -- Custom border replaces the simple one; recolor it with the
                -- target color. Lazy-create it first if a plate is targeted
                -- before its first ApplyBorder ran.
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
    -- If this plate is currently wrapping its border around the cast bar, the
    -- colour we just set landed on the (hidden) health border -- re-sync the
    -- visible unified border to the new target state. Guarded so it is a pure
    -- no-op (one field read) unless a wrap is actually live.
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
        ns._currentMouseoverPlate = self
        if ns._EnsureMouseoverTicker then ns._EnsureMouseoverTicker() end
    else
        ns.HideHoverEffect(self)
    end
end
-- Per-category rebuild support: id -> group-membership bitmask
-- (1 = debuff, 2 = buff, 4 = cc). A player stun lives in BOTH the
-- debuff and cc results, and partial rebuilds reorder _shownAuras
-- writes, so the single-slot map can never carry group ownership --
-- the mask is the authoritative record of which groups display an id.
-- Clears one group's bit from every entry; ids reaching zero leave
-- _shownAuras too.
function ns._npClearGroupIds(plate, bit)
    local mask = plate._auraGroupMask
    if not mask then return end
    local shown = plate._shownAuras
    for id, m in pairs(mask) do
        local has
        if bit == 1 then
            has = m % 2 >= 1
        elseif bit == 2 then
            has = m % 4 >= 2
        else
            has = m >= 4
        end
        if has then
            local nm = m - bit
            if nm <= 0 then
                mask[id] = nil
                if shown then shown[id] = nil end
            else
                mask[id] = nm
            end
        end
    end
end

-- P3 same-membership early-out support. Phase-1 selection results live
-- in these shared scratch tables (ids + aura object refs, parallel),
-- reused per group within one UpdateAuras call and wiped after so no
-- aura tables stay pinned across frames.
ns._npScratchIDs = ns._npScratchIDs or {}
ns._npScratchAuras = ns._npScratchAuras or {}

-- Positional identity: the would-be-shown id list exactly matches the
-- group's displayed slots (slot._auraId stamped at arm time; plain
-- numeric instance ids, never secret).
function ns._npGroupMatches(frames, prevCount, ids)
    if #ids ~= prevCount then return false end
    for i = 1, prevCount do
        if frames[i]._auraId ~= ids[i] then return false end
    end
    return true
end

-- Recycle guard: an honest remove/add of a DISPLAYED id must change
-- membership, so a positional match in that situation can only mean
-- aura-instance-id recycling -- never skip then.
function ns._npGroupTouched(updateInfo, frames, count)
    local removed = updateInfo.removedAuraInstanceIDs
    local added = updateInfo.addedAuras
    if not removed and not added then return false end
    for i = 1, count do
        local sid = frames[i]._auraId
        if sid then
            if removed then
                for j = 1, #removed do
                    if removed[j] == sid then return true end
                end
            end
            if added then
                for j = 1, #added do
                    if added[j].auraInstanceID == sid then return true end
                end
            end
        end
    end
    return false
end

function NameplateFrame:UpdateAuras(updateInfo)
    -- 12.1: aura rows render via engine containers (see the containers
    -- file); this whole legacy path is inert.
    if ns.NPC_OwnsAuras then return end
    if not self.unit or not self.nameplate then return end
    local unit = self.unit

    local needsFullRefresh = not updateInfo or updateInfo.isFullUpdate or not self._shownAuras
    -- A coalesced stash (a second UNIT_AURA payload overwrote an
    -- unconsumed one while deferred) must rebuild everything AND bypass
    -- the in-place fast path: the surviving payload does not describe
    -- the lost event's changes.
    if self._pendingCoalesced then
        self._pendingCoalesced = nil
        needsFullRefresh = true
    end

    if not needsFullRefresh then
        -- FAST PATH: if the only changes are duration/stack updates on
        -- already-displayed auras (no adds, no removes), just refresh
        -- cooldown + stacks on the existing slots. Skips the full clear +
        -- rebuild + reposition that costs ~0.3ms per call.
        -- Only count added auras as relevant if any are from the player
        -- (or if showAllDebuffs is on, or if it's a buff/CC the filter would
        -- pick up). In a 20-man raid, other players' debuffs fire addedAuras
        -- constantly but none of them will be displayed on our plate.
        -- Reuse the handler's stashed classification when this updateInfo
        -- is the exact stashed event table (reference identity); classify
        -- fresh otherwise. allKnown is never stashed -- it depends on
        -- _shownAuras, which may have been rebuilt since the stash.
        local hasAdds, hasRemoves, hasUpdates
        local meta = self._pendingMeta
        if meta and meta.updateInfo == updateInfo then
            hasAdds, hasRemoves, hasUpdates = meta.hasAdds, meta.hasRemoves, meta.hasUpdates
            meta.updateInfo = nil
        else
            hasAdds, hasRemoves, hasUpdates = ns._npClassifyAuraUpdate(updateInfo)
        end

        if hasUpdates and not hasAdds and not hasRemoves then
            local allKnown = true
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if not self._shownAuras[id] then
                    allKnown = false; break
                end
            end
            if allKnown then
                -- Duration/stack refresh only: update existing slots in place
                for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                    local slot = self._shownAuras[id]
                    if slot then
                        if slot.cd and C_UnitAuras_GetAuraDuration then
                            local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                            if durObj and slot.cd.SetCooldownFromDurationObject then
                                NP_ArmAuraCooldown(slot.cd, durObj)
                            end
                            slot._durationObj = durObj
                        end
                        if slot.count and C_UnitAuras_GetAuraAppDisplayCount then
                            slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
                        end
                    end
                end
                return
            end
        end

        -- Standard relevance check for adds/removes/updates
        local hasRelevantChange = hasAdds
        if not hasRelevantChange and hasRemoves then
            for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
                if self._shownAuras[id] then
                    hasRelevantChange = true
                    break
                end
            end
        end
        if not hasRelevantChange and hasUpdates then
            -- Updates on non-displayed auras (allKnown was false above)
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if self._shownAuras[id] then
                    hasRelevantChange = true
                    break
                end
            end
        end
        if not hasRelevantChange then
            return
        end
    end

    -- Same-frame coalescing: at most one full rebuild per plate per frame.
    -- GetTime() is constant within a frame; a second rebuild request in
    -- the same frame becomes an owed authoritative rebuild next frame.
    -- The explicit owed flag (not a skippable pending) carries the
    -- obligation, so relevant changes can never be dropped.
    if self._lastFullRebuildT == GetTime() then
        self._auraOwedFull = true
        self:QueueAuraFallback()
        return
    end
    self._lastFullRebuildT = GetTime()

    -- Per-category dispatch: full rebuilds touch all three groups;
    -- incremental payloads rebuild only the groups they can affect.
    local rebuildD, rebuildB, rebuildC = true, true, true
    if not needsFullRefresh then
        rebuildD, rebuildB, rebuildC = false, false, false
        local mask = self._auraGroupMask
        if updateInfo.addedAuras then
            -- Union over the WHOLE payload (no early break): map each add
            -- to every group it could possibly enter. Superset by filter
            -- algebra: helpful auras never pass HARMFUL filters; non-player
            -- harmful never passes HARMFUL|PLAYER; player harmful can
            -- appear in BOTH debuff and cc results.
            for _, aura in ipairs(updateInfo.addedAuras) do
                if aura.isFromPlayerOrPlayerPet then rebuildD = true; rebuildC = true end
                if aura.isHelpful then rebuildB = true end
                if aura.dispelName and aura.isHarmful then rebuildC = true end
            end
        end
        if mask then
            if updateInfo.removedAuraInstanceIDs then
                for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
                    local m = mask[id]
                    if m then
                        if m % 2 >= 1 then rebuildD = true end
                        if m % 4 >= 2 then rebuildB = true end
                        if m >= 4 then rebuildC = true end
                    end
                end
            end
            if updateInfo.updatedAuraInstanceIDs then
                for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                    local m = mask[id]
                    if m then
                        if m % 2 >= 1 then rebuildD = true end
                        if m % 4 >= 2 then rebuildB = true end
                        if m >= 4 then rebuildC = true end
                    end
                end
            end
        end
        -- Attackability latch: UnitCanAttack gates the whole buff group,
        -- and charm/faction flips arrive ONLY as aura events in instanced
        -- content (UNIT_FACTION is unregistered there). A flip must force
        -- the buff group even when no displayed buff id was touched.
        local attackable = not not UnitCanAttack("player", unit)
        if attackable ~= self._buffsBuiltAttackable then rebuildB = true end
        -- Safety net: the relevance gate said this payload matters; if
        -- group derivation found nothing (e.g. mask lost), do everything.
        if not (rebuildD or rebuildB or rebuildC) then
            rebuildD, rebuildB, rebuildC = true, true, true
        end
    end

    if not self._auraGroupMask then self._auraGroupMask = {} end
    if needsFullRefresh then
        -- Full path: wholesale wipe is cheaper than (and equivalent to)
        -- per-group id clearing when every group rebuilds anyway.
        if not self._shownAuras then
            self._shownAuras = {}
        else
            wipe(self._shownAuras)
        end
        wipe(self._auraGroupMask)
    end

    -- Get slot assignments; skip processing for any slot set to "none".
    -- Slot clearing happens per group inside each rebuild section.
    local debuffSlotVal, buffSlotVal, ccSlotVal = GetAuraSlots()

    if rebuildD then
    -- PHASE 1 (P3): select the would-be-shown ids into the shared scratch
    -- with exact gate parity to the arm path; all widget work (clear,
    -- textures, positions, glows) is deferred to PHASE 2 below so an
    -- unchanged displayed set can skip it entirely.
    local skipIDs, skipAuras = ns._npScratchIDs, ns._npScratchAuras
    wipe(skipIDs); wipe(skipAuras)
    local dIdx = 1

    -----------------------------------------------------------------------
    --  Debuffs: build importantSet via cached callback (zero closure alloc),
    --  then iterate importantSet with GetAuraDataByAuraInstanceID (zero
    --  GetUnitAuras table alloc). showAll mode falls back to GetUnitAuras.
    -----------------------------------------------------------------------
    if debuffSlotVal ~= "none" then
    local maxDbfSlots = #self.debuffs
    local showAll = p and p.showAllDebuffs
    if showAll then
        -- showAll mode: must scan all player debuffs
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            local allDebuffs = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
            if allDebuffs then
                for _, aura in ipairs(allDebuffs) do
                    if dIdx > maxDbfSlots then break end
                    local id = aura and aura.auraInstanceID
                    if id and aura.icon then
                        skipIDs[dIdx] = id
                        skipAuras[dIdx] = aura
                        dIdx = dIdx + 1
                    end
                end
            end
        end
    else
        -- Normal mode: build importantSet from Blizzard's debuffList (cached
        -- callback), then intersect with HARMFUL|PLAYER (C-side filter handles
        -- secret isFromPlayerOrPlayerPet correctly). One GetUnitAuras call but
        -- only process the intersection.
        local uf = self.nameplate.UnitFrame
        if uf and uf.AurasFrame and uf.AurasFrame.debuffList and uf.AurasFrame.debuffList.Iterate then
            if not self._importantSet then self._importantSet = {} end
            local importantSet = self._importantSet
            wipe(importantSet)
            if not self._iterateCB then
                self._iterateCB = function(auraInstanceID)
                    self._importantSet[auraInstanceID] = true
                end
            end
            uf.AurasFrame.debuffList:Iterate(self._iterateCB)
            -- HARMFUL|PLAYER: C-side filter ensures only player debuffs.
            -- Intersect with importantSet to show only important player debuffs.
            if C_UnitAuras and C_UnitAuras.GetUnitAuras then
                local allPlayerDebuffs = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
                if allPlayerDebuffs then
                    for _, aura in ipairs(allPlayerDebuffs) do
                        if dIdx > maxDbfSlots then break end
                        local id = aura and aura.auraInstanceID
                        if id and aura.icon and importantSet[id] then
                            skipIDs[dIdx] = id
                            skipAuras[dIdx] = aura
                            dIdx = dIdx + 1
                        end
                    end
                end
            end
        end
    end
    end -- debuffSlotVal ~= "none" (phase 1)
    -- PHASE 2 (P3): same-membership early-out (delta events only) or
    -- rebuild consuming the phase-1 scratch -- never a second fetch.
    if not needsFullRefresh
        and ns._npGroupMatches(self.debuffs, self._prevDebuffCount or 0, skipIDs)
        and not ns._npGroupTouched(updateInfo, self.debuffs, self._prevDebuffCount or 0) then
        -- Displayed set unchanged: skip clear/texture/position/glow
        -- restarts. Re-arm durations + stacks on every shown slot
        -- (idempotent secret-safe sinks, none PP-hooked; keeps
        -- slot._durationObj fresh for the pandemic tick and heals any
        -- stale pending). Updated ids also refresh their texture for
        -- parity with a full repaint.
        local updated = updateInfo.updatedAuraInstanceIDs
        local dCrop, dCzW, dCzH
        if updated then
            dCrop = ns.GetAuraCrop("debuffs")
            dCzW = GetDebuffIconSize()
            dCzH = ns.GetAuraCropHeight(dCrop, dCzW)
        end
        for i = 1, #skipIDs do
            local slot = self.debuffs[i]
            local id = skipIDs[i]
            if slot.cd and C_UnitAuras_GetAuraDuration then
                local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                if durObj and slot.cd.SetCooldownFromDurationObject then
                    NP_ArmAuraCooldown(slot.cd, durObj)
                end
                slot._durationObj = durObj
            end
            if slot.count and C_UnitAuras_GetAuraAppDisplayCount then
                slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
            end
            if updated then
                for j = 1, #updated do
                    if updated[j] == id then
                        RawSetTex(slot.icon, skipAuras[i].icon)
                        -- SetTexture resets texcoord; re-apply the crop so a
                        -- hot-path texture swap never reverts a cropped icon.
                        ns.SetAuraIconCrop(slot.icon, dCrop, dCzW, dCzH)
                        break
                    end
                end
            end
        end
    else
        ns._npClearGroupIds(self, 1)
        local prevD = self._prevDebuffCount or #self.debuffs
        for i = 1, prevD do ClearAuraSlot(self.debuffs[i]) end
        local groupMask = self._auraGroupMask
        local debuffCount = dIdx - 1
        for i = 1, debuffCount do
            local aura = skipAuras[i]
            local id = skipIDs[i]
            local slot = self.debuffs[i]
            RawSetTex(slot.icon, aura.icon)
            -- Texcoord (square or cropped) is applied in the size loop below.
            if C_UnitAuras_GetAuraAppDisplayCount then
                slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
            end
            local cd = slot.cd
            if cd and C_UnitAuras_GetAuraDuration then
                local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                if durObj and cd.SetCooldownFromDurationObject then
                    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                    NP_ArmAuraCooldown(cd, durObj)
                    cd:Show()
                end
                slot._durationObj = durObj
            end
            slot:Show()
            slot._auraId = id
            self._shownAuras[id] = slot
            local m = groupMask[id] or 0
            if m % 2 < 1 then groupMask[id] = m + 1 end
        end
        self._prevDebuffCount = debuffCount
        if debuffCount > 0 then
            local spacing = GetAuraSpacing("debuffs")
            local cropped = ns.GetAuraCrop("debuffs")
            local debuffSz = GetDebuffIconSize()
            local debuffH = ns.GetAuraCropHeight(cropped, debuffSz)
            for i = 1, debuffCount do
                ns.ApplyAuraSlotCrop(self.debuffs[i], cropped, debuffSz)
            end
            PositionAuraSlot(self.debuffs, debuffCount, debuffSlotVal, self, debuffSz, debuffH, spacing, GetAuraSlotOffsets("debuffSlot"))
        end
        -- Pandemic glow registration for shown debuffs (zero work when off)
        if GetPandemicGlow() then
            for i = 1, debuffCount do
                ns.ApplyPandemicGlow(self.debuffs[i])
            end
        end
    end
    end -- rebuildD

    -----------------------------------------------------------------------
    --  Buffs: build importantBuffSet via cached callback, iterate with
    --  GetAuraDataByAuraInstanceID (same pattern as debuffs).
    -----------------------------------------------------------------------
    if rebuildB then
    -- PHASE 1 (P3): selection only, exact gate parity (slot "none",
    -- attackability, importantBuffSet, icon truthiness, cap 4).
    local skipIDs, skipAuras = ns._npScratchIDs, ns._npScratchAuras
    wipe(skipIDs); wipe(skipAuras)
    local bIdx = 1
    -- Latch the attackability the buff group was built under: the
    -- incremental dispatch forces a buff rebuild when it changes.
    local buffsAttackable = UnitCanAttack("player", unit)
    self._buffsBuiltAttackable = not not buffsAttackable
    if buffSlotVal ~= "none" then
    if buffsAttackable then
        local uf = self.nameplate.UnitFrame
        if uf and uf.AurasFrame and uf.AurasFrame.buffList and uf.AurasFrame.buffList.Iterate then
            if not self._importantBuffSet then self._importantBuffSet = {} end
            local importantBuffSet = self._importantBuffSet
            wipe(importantBuffSet)
            if not self._buffIterateCB then
                self._buffIterateCB = function(auraInstanceID)
                    self._importantBuffSet[auraInstanceID] = true
                end
            end
            uf.AurasFrame.buffList:Iterate(self._buffIterateCB)
            local _getAura = C_UnitAuras.GetAuraDataByAuraInstanceID
            for id in pairs(importantBuffSet) do
                if bIdx > 4 then break end
                local aura = _getAura(unit, id)
                if aura and aura.icon then
                    skipIDs[bIdx] = id
                    skipAuras[bIdx] = aura
                    bIdx = bIdx + 1
                end
            end
        end
    end
    end -- buffSlotVal ~= "none" (phase 1)
    -- PHASE 2 (P3): skip on identical membership, else rebuild from scratch
    if not needsFullRefresh
        and ns._npGroupMatches(self.buffs, self._prevBuffCount or 0, skipIDs)
        and not ns._npGroupTouched(updateInfo, self.buffs, self._prevBuffCount or 0) then
        -- Same membership: re-arm durations + stacks only (buff slots do
        -- not store _durationObj -- parity with the arm path). Dispel
        -- glow state persists with the unchanged aura.
        local updated = updateInfo.updatedAuraInstanceIDs
        local bCrop, bCzW, bCzH
        if updated then
            bCrop = ns.GetAuraCrop("buffs")
            bCzW = GetBuffIconSize()
            bCzH = ns.GetAuraCropHeight(bCrop, bCzW)
        end
        for i = 1, #skipIDs do
            local slot = self.buffs[i]
            local id = skipIDs[i]
            if slot.cd and C_UnitAuras_GetAuraDuration then
                local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                if durObj and slot.cd.SetCooldownFromDurationObject then
                    NP_ArmAuraCooldown(slot.cd, durObj)
                end
            end
            if slot.count and C_UnitAuras_GetAuraAppDisplayCount then
                slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
            end
            if updated then
                for j = 1, #updated do
                    if updated[j] == id then
                        RawSetTex(slot.icon, skipAuras[i].icon)
                        -- SetTexture resets texcoord; re-apply the crop so a
                        -- hot-path texture swap never reverts a cropped icon.
                        ns.SetAuraIconCrop(slot.icon, bCrop, bCzW, bCzH)
                        break
                    end
                end
            end
        end
    else
        ns._npClearGroupIds(self, 2)
        local prevB = self._prevBuffCount or 4
        for i = 1, prevB do ClearAuraSlot(self.buffs[i]) end
        local groupMask = self._auraGroupMask
        local dispelGlowOn = ns.GetDispelGlow()
        local buffGlowSz = GetBuffIconSize()
        local buffCount = bIdx - 1
        for i = 1, buffCount do
            local aura = skipAuras[i]
            local id = skipIDs[i]
            local slot = self.buffs[i]
            RawSetTex(slot.icon, aura.icon)
            -- Texcoord (square or cropped) is applied in the size loop below.
            if C_UnitAuras_GetAuraAppDisplayCount then
                slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
            end
            local cd = slot.cd
            if cd and C_UnitAuras_GetAuraDuration then
                local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                if durObj and cd.SetCooldownFromDurationObject then
                    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                    NP_ArmAuraCooldown(cd, durObj)
                    cd:Show()
                end
            end
            slot:Show()
            slot._auraId = id
            self._shownAuras[id] = slot
            local m = groupMask[id] or 0
            if m % 4 < 2 then groupMask[id] = m + 2 end
            if dispelGlowOn then
                local canDispel, typeColor = ns.CanDispelAura(unit, aura)
                if canDispel then
                    ns.StartDispelGlow(slot, buffGlowSz, typeColor)
                end
            end
        end
        self._prevBuffCount = buffCount
        -- Reposition buffs based on actual shown count
        if buffSlotVal ~= "none" and buffCount > 0 then
            local spacing = GetAuraSpacing("buffs")
            local cropped = ns.GetAuraCrop("buffs")
            local buffSz = GetBuffIconSize()
            local buffH = ns.GetAuraCropHeight(cropped, buffSz)
            for i = 1, buffCount do
                ns.ApplyAuraSlotCrop(self.buffs[i], cropped, buffSz)
            end
            PositionAuraSlot(self.buffs, buffCount, buffSlotVal, self, buffSz, buffH, spacing, GetAuraSlotOffsets("buffSlot"))
        end
    end
    end -- rebuildB

    -----------------------------------------------------------------------
    --  CC: still needs GetUnitAuras (no Blizzard list to iterate), but
    --  CC auras are rare (0-2 per unit). Minimal allocation cost.
    -----------------------------------------------------------------------
    if rebuildC then
    -- PHASE 1 (P3): selection only (slot "none" gate, id+icon truthiness,
    -- cap 2).
    local skipIDs, skipAuras = ns._npScratchIDs, ns._npScratchAuras
    wipe(skipIDs); wipe(skipAuras)
    local ccSel = 0
    if ccSlotVal ~= "none" then
        -- Short-circuit on the plain field so there's no call when no lockout is
        -- pending (i.e. always, when the feature is off).
        local lockout = self._castLockout and ns.GetActiveCastLockout(self)
        if lockout then
            ccSel = 1
            skipIDs[1] = ns.CAST_LOCKOUT_SLOT_ID
            skipAuras[1] = lockout
        end
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            local ccAuras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|CROWD_CONTROL")
            if ccAuras then
                for _, aura in ipairs(ccAuras) do
                    if ccSel >= 2 then break end
                    if aura and aura.auraInstanceID and aura.icon then
                        ccSel = ccSel + 1
                        skipIDs[ccSel] = aura.auraInstanceID
                        skipAuras[ccSel] = aura
                    end
                end
            end
        end
    end -- ccSlotVal ~= "none" (phase 1)
    -- PHASE 2 (P3): skip on identical membership, else rebuild from scratch
    if not needsFullRefresh
        and ns._npGroupMatches(self.cc, self._prevCCCount or 0, skipIDs)
        and not ns._npGroupTouched(updateInfo, self.cc, self._prevCCCount or 0) then
        -- Same membership: re-arm cooldowns only (CC slots have no count
        -- text and do not store _durationObj -- parity with the arm path)
        local updated = updateInfo.updatedAuraInstanceIDs
        local cCrop, cCzW, cCzH
        if updated then
            cCrop = ns.GetAuraCrop("ccs")
            cCzW = GetCCIconSize()
            cCzH = ns.GetAuraCropHeight(cCrop, cCzW)
        end
        for i = 1, #skipIDs do
            local slot = self.cc[i]
            local id = skipIDs[i]
            if id == ns.CAST_LOCKOUT_SLOT_ID then
                ns.ArmCastLockoutCooldown(slot.cd, skipAuras[i])
            elseif slot.cd and C_UnitAuras_GetAuraDuration then
                local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                if durObj and slot.cd.SetCooldownFromDurationObject then
                    NP_ArmAuraCooldown(slot.cd, durObj)
                end
            end
            if updated and id ~= ns.CAST_LOCKOUT_SLOT_ID then
                for j = 1, #updated do
                    if updated[j] == id then
                        RawSetTex(slot.icon, skipAuras[i].icon)
                        -- SetTexture resets texcoord; re-apply the crop so a
                        -- hot-path texture swap never reverts a cropped icon.
                        ns.SetAuraIconCrop(slot.icon, cCrop, cCzW, cCzH)
                        break
                    end
                end
            end
        end
    else
        ns._npClearGroupIds(self, 4)
        local prevCC = self._prevCCCount or 2
        for i = 1, prevCC do ClearAuraSlot(self.cc[i]) end
        local groupMask = self._auraGroupMask
        local ccShown = ccSel
        for i = 1, ccShown do
            local aura = skipAuras[i]
            local id = skipIDs[i]
            local slot = self.cc[i]
            if id == ns.CAST_LOCKOUT_SLOT_ID then
                ns.ArmCastLockoutSlot(slot, aura)
            else
                RawSetTex(slot.icon, aura.icon)
                -- Texcoord (square or cropped) is applied in the size loop below.
                slot.icon:Show()
                local cd = slot.cd
                if cd and C_UnitAuras_GetAuraDuration then
                    local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                    if durObj and cd.SetCooldownFromDurationObject then
                        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                        NP_ArmAuraCooldown(cd, durObj)
                        cd:Show()
                    end
                end
                slot:Show()
                slot._auraId = id
                self._shownAuras[id] = slot
                local m = groupMask[id] or 0
                if m < 4 then groupMask[id] = m + 4 end
            end
        end
        self._prevCCCount = ccShown
        -- Reposition CC based on actual shown count
        if ccSlotVal ~= "none" and ccShown > 0 then
            local spacing = GetAuraSpacing("ccs")
            local cropped = ns.GetAuraCrop("ccs")
            local ccSz = GetCCIconSize()
            local ccH = ns.GetAuraCropHeight(cropped, ccSz)
            for i = 1, ccShown do
                ns.ApplyAuraSlotCrop(self.cc[i], cropped, ccSz)
            end
            PositionAuraSlot(self.cc, ccShown, ccSlotVal, self, ccSz, ccH, spacing, GetAuraSlotOffsets("ccSlot"))
        end
    end
    end -- rebuildC

    -- Release phase-1 scratch so no aura tables stay pinned across frames
    wipe(ns._npScratchIDs)
    wipe(ns._npScratchAuras)

    -- Reposition target arrows outside the outermost side auras
    PositionArrowsOutsideAuras(self)
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
    if style ~= 1 and style ~= 4 then style = 1 end
    local c = cfg.importantCastGlowColor or defaults.importantCastGlowColor or { r = 1, g = 0.2, b = 0.2 }
    local bgColor = cfg.importantCastGlowBackgroundColor or defaults.importantCastGlowBackgroundColor or { r = 0, g = 0, b = 0 }
    local bgOn = cfg.importantCastGlowBackground == true
    local impN, impTh, impPeriod
    if style ~= 4 then
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
        if style == 4 then
            (StartAutoCastShine or Glows.StartAutoCastShine)(self._importantCastOverlay, pW, c.r, c.g, c.b, 1.0, pH)
        else
            local lineLen = math.floor((pW + pH) * (2 / impN - 0.1))
            lineLen = math.min(lineLen, math.min(pW, pH))
            if lineLen < 1 then lineLen = 1 end
            (StartProceduralAnts or Glows.StartProceduralAnts)(self._importantCastOverlay, impN, impTh, impPeriod, lineLen, c.r, c.g, c.b, pW, pH,
                bgOn and (bgColor.r or 0) or nil, bgColor.g or 0, bgColor.b or 0)
        end
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

    -- FAST PATH: on DELAYED/UPDATE events (not START), the icon, name,
    -- target, and glow haven't changed. Only the duration needs updating.
    -- _castDirtyFull is set by UNIT_SPELLCAST_START/CHANNEL_START/EMPOWER_START.
    local isFullSetup = self._castDirtyFull or not self.isCasting
    self._castDirtyFull = nil

    if isFullSetup then
        self.cast:Show()
        self:ApplyNameVisibility()
        local castW = self.cast:GetWidth()
        if castW and castW > 0 then
            local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
            self.castName:SetWidth(castW * cnWPct / 100)
        end
        -- Icon and name must describe the SAME cast. Both are taken from this
        -- UnitCastingInfo/UnitChannelInfo snapshot: the icon comes straight from
        -- the live texture (which may be a secret value -- SetTexture accepts
        -- secrets natively), so it is never rejected and never replaced by a
        -- cached or leftover icon from a previous cast or a recycled unit.
        if type(texture) ~= "nil" then
            self.castIcon:SetTexture(texture)
        elseif type(castSpellID) ~= "nil" then
            -- Texture genuinely absent (rare): fall back to THIS cast's spell
            -- icon. pcall guards an invalid/0/unknown spellID; iconID is fed
            -- straight to SetTexture and never branched on.
            local okInfo, info = pcall(C_Spell.GetSpellInfo, castSpellID)
            if okInfo and type(info) == "table" then
                self.castIcon:SetTexture(info.iconID)
            else
                self.castIcon:SetTexture(nil)
            end
        else
            self.castIcon:SetTexture(nil)
        end
        self.castName:SetText(type(name) ~= "nil" and name or "")

        local spellTarget, spellTargetClass
        if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(self.unit) then
            local rawTarget = UnitSpellTargetName and UnitSpellTargetName(self.unit)
            -- May be a SECRET string: type() is the only safe existence
            -- check (truthiness on a secret errors); SetText/SetTextColor
            -- accept secrets natively downstream.
            if type(rawTarget) ~= "nil" then
                spellTarget = rawTarget
                spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(self.unit)
            end
        end
        local hasTarget = type(spellTarget) ~= "nil"
        if hasTarget then
            self.castTarget:SetText(spellTarget)
        else
            self.castTarget:SetText("")
        end

        local db = p or defaults
        local useClassColor = defaults.castTargetClassColor
        if db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end
        if useClassColor then
            local appliedCTC = false
            -- spellTargetClass may be SECRET; GetClassColor accepts it and
            -- returns a clean color object whose components stay secret-safe
            -- through SetTextColor.
            if type(spellTargetClass) ~= "nil" and C_ClassColor then
                local c = C_ClassColor.GetClassColor(spellTargetClass)
                if c then
                    self.castTarget:SetTextColor(c:GetRGB())
                    appliedCTC = true
                end
            end
            if not appliedCTC then
                self.castTarget:SetTextColor(1, 1, 1, 1)
            end
        else
            local ctc = (db and db.castTargetColor) or defaults.castTargetColor
            self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
        end

        local nameSide   = db.castNameSide   or defaults.castNameSide
        local targetSide = db.castTargetSide or defaults.castTargetSide
        self.castName:SetShown(nameSide ~= "none")
        self.castTarget:SetShown(hasTarget and targetSide ~= "none")
        self.castTimer:SetShown(self._showCastTimer)

        if type(kickProtected) == "nil" then
            kickProtected = false
        end
        self._kickProtected = kickProtected
        -- Cache whether this cast is "important" (the game's flag) for the cast
        -- bar colour. May be SECRET, so it is stored raw and only ever fed to a
        -- boolean-curve evaluator (never branched on). pcall mirrors the glow
        -- path (the spellID can be 0/invalid). Persists across interruptible
        -- flips and the kick-cooldown ticker, which both reuse it via ApplyCastColor.
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
            -- Try empowered channel duration first (Evoker empower spells
            -- like Fire Breath, Eternity Surge, Dream Breath, Spiritbloom).
            -- Normal UnitChannelDuration can return nil during the empower
            -- phase, which would leave the bar unticked even though
            -- UnitChannelInfo did return a spell name.
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
        -- Cast timing changed mid-cast (delay/channel/empower update):
        -- re-derive the kick geometry from the cached cast identity
        self._kickGeoDirty = nil
        self:UpdateKickTick(self._kickProtected, self._kickIsChannel, self._kickIsEmpowered)
    end
end
-- Smooth scale transitions. A single shared OnUpdate eases every plate whose
-- displayed scale (_curScale) differs from its destination (_destScale). The
-- driver hides itself the instant no plate is animating, so it costs nothing at
-- idle; and because target/cast scale both default to 100, dest stays at 1 and
-- ApplyScale snaps (never enrolls) until the user actually sets a scale.
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
            -- The held "Interrupted" flash keeps the bar visible after
            -- isCasting clears; it must ride the shrink-back too.
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
    -- Lifted cast bar renders outside this plate's scale chain; keep its
    -- container pinned to the plate's effective scale.
    if ns.RefreshCastOverlay then ns.RefreshCastOverlay(self) end
end
function NameplateFrame:ApplyCastColor(uninterruptible)
    local cfg = p or defaults
    local kickReadyTint = cfg.interruptReady or defaults.interruptReady
    local normalCastTint = cfg.castBar or defaults.castBar
    -- Important Cast Color (opt-in): when enabled, a cast the game flags as
    -- important shows the Important colour in place of the Interruptible colour.
    -- The importance flag may be a SECRET boolean, so blend per channel via
    -- EvaluateColorValueFromBoolean (ifTrue = Important, ifFalse = Interruptible)
    -- instead of branching on it. Interrupt-on-CD still wins: ComputeCastBarTint
    -- layers the kick-ready tint on top of whatever base tint we hand it, so an
    -- interrupt on cooldown overrides the Important colour exactly as it overrides
    -- the Interruptible colour. Uninterruptible casts keep their look because the
    -- uninterruptible overlay draws over this fill regardless.
    local importantOn = cfg.importantCastColorEnabled
    if importantOn == nil then importantOn = defaults.importantCastColorEnabled end
    if importantOn and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local imp = cfg.castBarImportant or defaults.castBarImportant
        local isImp = self._castImportant
        if type(isImp) == "nil" then isImp = false end
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        normalCastTint = {
            r = ev(isImp, imp.r, normalCastTint.r),
            g = ev(isImp, imp.g, normalCastTint.g),
            b = ev(isImp, imp.b, normalCastTint.b),
        }
    end
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, normalCastTint)
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    -- Shield icon is opt-out: when disabled, it never shows, even on
    -- uninterruptible casts. The setting is a clean boolean, so it gates the
    -- (possibly SECRET) uninterruptible flag without ever evaluating it.
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
    -- Two independent CLEAN toggles drive this geometry: the visible tick
    -- (kickTickEnabled) and the interrupt-ready mid-cast fill
    -- (interruptMidCastEnabled). Either one needs the positioner/marker
    -- StatusBars built below; each visible element is gated on its own toggle.
    local tickOn = GetKickTickEnabled()
    local midOn = defaults.interruptMidCastEnabled
    if p and p.interruptMidCastEnabled ~= nil then midOn = p.interruptMidCastEnabled end
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        self:HideKickTick()
        return
    end
    -- kickProtected is a secret boolean on Midnight cannot branch on it.
    -- Store it so we can apply visibility via SetAlphaFromBoolean after setup.
    -- isChannel/isEmpowered are cached too: the cooldown watcher no longer
    -- re-reads cast info per event and re-setups from these on demand.
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
        -- Initial PAIRED snapshot: the tick's cast-bar position is
        -- positioner(elapsed) + marker(kick CD remaining), which equals
        -- the fixed "kick ready here" point only when both values are
        -- sampled at the same instant. RefreshKickTick re-pins the pair
        -- on every cooldown event. NEVER update one without the other:
        -- a marker-only refresh makes the tick drift left with the cast.
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
            -- LOAD-BEARING: SetFillStyle puts the inner fill back in the default
            -- snap-ON state and the global SetStatusBarTexture unsnap hook will
            -- NOT re-fire (it caches per StatusBar frame). Re-disable snap on the
            -- current fill texture so positioner(elapsed) + marker(CD remaining)
            -- stays an exact float and the tick does not dance on each re-pin.
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
            -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see
            -- the reverse branch) so the summed elapsed+remaining edge is exact
            -- and the tick is stationary across every re-pin.
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
            -- Standard fill (cast / empowered channel): the kick-ready point is
            -- the marker texture RIGHT edge; the "kick available" window runs
            -- from it to the cast end (bar right). Not-in-time pushes the marker
            -- edge past the right edge, crossing the anchors to zero width.
            self.kickReadyFill:ClearAllPoints()
            self.kickReadyFill:SetPoint("TOP", self.cast, "TOP", 0, 0)
            self.kickReadyFill:SetPoint("BOTTOM", self.cast, "BOTTOM", 0, 0)
            self.kickReadyFill:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
            self.kickReadyFill:SetPoint("RIGHT", self.cast, "RIGHT", 0, 0)
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility.
        -- Its alpha (the SECRET on-CD x interruptible gate) is applied with the
        -- tick alpha below. Geometry above runs whenever the tick OR the fill is
        -- enabled; SetShown gates each element to its own toggle so one feature
        -- never forces the other to appear.
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
        -- Ticker: tick ALPHA only at 10fps (kick-ready x interruptibility
        -- secret combine). Bar values are re-pinned as a PAIR by
        -- RefreshKickTick on SPELL_UPDATE_COOLDOWN/USABLE events, not here.
        if self._kickTicker then self._kickTicker:Cancel() end
        -- Self-identifying ticker: a superseded ticker cancels ITSELF
        -- instead of calling HideKickTick (which would cancel its
        -- successor). The watcher no longer recreates this per event.
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
            -- activeKickSpell can go nil mid-cast if a spec/talent change
            -- fires SPELLS_CHANGED and the new spec doesn't have a kick
            -- learned. Bail rather than pass nil to C_Spell.
            if not GetActiveKickSpell() then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans chain EvaluateColorValueFromBoolean calls
            -- to combine conditions into a single secret alpha.
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
-- Light per-cooldown-event refresh: bar values + tick alpha only. The
-- geometry (sizes, anchors, fill styles, colors) is cast-identity work
-- done once by UpdateKickTick.
-- CRITICAL: the tick's cast-bar position is positioner(elapsed) +
-- marker(remaining); that sum is only the true "kick ready here" point
-- when BOTH snapshots are taken at the same instant. Re-pinning the
-- marker alone makes the tick drift left by the cast time elapsed since
-- setup (reference implementations either snapshot both once or, like
-- the pre-diet watcher here, always re-pin both together).
function NameplateFrame:RefreshKickTick()
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not icd then
        -- Transient read miss during an ongoing cast: skip this refresh and
        -- keep the current tick/fill rather than hiding. Hiding here (and
        -- re-showing on the next SPELL_UPDATE_COOLDOWN) is what made the tick
        -- and the kick-ready bar blink during the player's rotation. Genuine
        -- cast-end is handled by the cast-stop/interrupt paths, not here.
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

    -- Resolve the interrupter's name + class from the GUID.
    local interrupterName
    local interrupterClass
    if interrupterGUID then
        if UnitNameFromGUID then
            interrupterName = UnitNameFromGUID(interrupterGUID)
            local _, class = GetPlayerInfoByGUID(interrupterGUID)
            interrupterClass = class
        else
            local unitToken = UnitTokenFromGUID(interrupterGUID)
            if unitToken then
                interrupterName = UnitName(unitToken)
                interrupterClass = UnitClassBase(unitToken)
            end
        end
    end
    local cfg = p or defaults
    local useClassColor = defaults.castTargetClassColor
    if cfg.castTargetClassColor ~= nil then useClassColor = cfg.castTargetClassColor end

    -- Show the interrupter inline as "Interrupted (Name)" in the single cast-name
    -- FontString; the cast-target / timer slots are cleared during the flash.
    local castW = self.cast:GetWidth()
    if castW and castW > 0 then
        local cnWPct = (p and p.castNameWidthPct) or defaults.castNameWidthPct
        self.castName:SetWidth(interrupterName and math.max(castW - 8, 20) or castW * cnWPct / 100)
    end

    local interruptedText = (EllesmereUI and EllesmereUI.L and EllesmereUI.L("Interrupted")) or "Interrupted"
    if interrupterName then
        local sourceText = interrupterName
        if useClassColor and interrupterClass and C_ClassColor then
            local c = C_ClassColor.GetClassColor(interrupterClass)
            if c then
                local hex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr
                if not hex and c.r and c.g and c.b then
                    hex = string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
                end
                if hex then sourceText = "|c" .. hex .. interrupterName .. "|r" end
            end
        end
        self.castName:SetText(interruptedText .. " (" .. sourceText .. ")")
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
    self:UpdateAuras()
    if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    C_Timer.After(ns.DEFAULT_CAST_LOCKOUT_DURATION, function()
        if self._castLockout ~= lockout or GetTime() < lockout.expires then return end
        self._castLockout = nil
        self:UpdateAuras()
        if ns.NPC_UpdateLockout then ns.NPC_UpdateLockout(self) end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    -- If the mob dies while the "Interrupted" flash is held up, Blizzard's
    -- nameplate death animation scales the still-shown cast bar and it looks
    -- squished/warped. Tear the flash down the instant death is detected.
    -- Gated on _interrupted first, so UnitIsDeadOrGhost is only ever called
    -- during the brief flash window -- ~free on normal health ticks. (Same
    -- safe death check already used by the health-text path.)
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
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_AURA(_, updateInfo)
    -- PERF: If we have the RefreshAuras hook installed (enemy plates), defer
    -- full rebuilds to the hook which fires AFTER Blizzard updates debuffList.
    -- The incremental fast path (updates to existing auras) runs here since
    -- it doesn't depend on debuffList.
    if self._hasRefreshAurasHook and updateInfo and not updateInfo.isFullUpdate and self._shownAuras then
        -- Try incremental fast path only (no full rebuilds from UNIT_AURA)
        local hasAdds, hasRemoves, hasUpdates = ns._npClassifyAuraUpdate(updateInfo)
        if hasUpdates and not hasAdds and not hasRemoves then
            local allKnown = true
            for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                if not self._shownAuras[id] then allKnown = false; break end
            end
            if allKnown then
                -- Duration/stack refresh only
                local unit = self.unit
                for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
                    local slot = self._shownAuras[id]
                    if slot then
                        if slot.cd and C_UnitAuras_GetAuraDuration then
                            local durObj = C_UnitAuras_GetAuraDuration(unit, id)
                            if durObj and slot.cd.SetCooldownFromDurationObject then
                                NP_ArmAuraCooldown(slot.cd, durObj)
                            end
                            slot._durationObj = durObj
                        end
                        if slot.count and C_UnitAuras_GetAuraAppDisplayCount then
                            slot.count:SetText(C_UnitAuras_GetAuraAppDisplayCount(unit, id, 2, 1000) or "")
                        end
                    end
                end
                return
            end
        end
        -- Adds/removes: defer to RefreshAuras hook where debuffList is
        -- guaranteed current. Reading debuffList here races with Blizzard's
        -- processing and causes auras to not display on other plates.
        if self._pendingAuraUpdate and self._pendingAuraUpdate ~= updateInfo then
            -- Overwriting an unconsumed stash: the eventual rebuild must
            -- cover BOTH events' changes (per-group dispatch would
            -- otherwise lose the first event's groups entirely).
            self._pendingCoalesced = true
        end
        self._pendingAuraUpdate = updateInfo
        -- Identity-paired classification stash: UpdateAuras reuses these
        -- flags ONLY when its updateInfo is this exact event table
        -- (reference equality), so a stale meta can never misclassify a
        -- different payload. The meta table is per-plate and reused.
        local meta = self._pendingMeta
        if not meta then meta = {}; self._pendingMeta = meta end
        meta.updateInfo = updateInfo
        meta.hasAdds, meta.hasRemoves, meta.hasUpdates = hasAdds, hasRemoves, hasUpdates
        self._auraAwaitingUnitAura = nil
        -- Fallback: if RefreshAuras doesn't fire (e.g. Blizzard's UnitFrame
        -- suppressed), process next frame.
        self:QueueAuraFallback()
        return
    end
    self:UpdateAuras(updateInfo)
end
-- Shared aura-update classification: the three updateInfo-pure flags.
-- allKnown is deliberately NOT computed here -- it depends on _shownAuras,
-- which can be rebuilt between a stash and its consumption, so consumers
-- must recompute it against the CURRENT _shownAuras.
function ns._npClassifyAuraUpdate(updateInfo)
    local hasAdds = false
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.isFromPlayerOrPlayerPet or aura.isHelpful or (aura.dispelName and aura.isHarmful) then
                hasAdds = true; break
            end
        end
    end
    local hasRemoves = updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0
    local hasUpdates = updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs > 0
    return hasAdds, hasRemoves, hasUpdates
end

-- Shared next-frame aura processing queue. Used by the UNIT_AURA stash
-- path, same-frame owed full rebuilds, and RefreshAuras re-filters. A
-- RefreshAuras event first waits for the paired UNIT_AURA payload; only
-- if no payload arrives does the drain do an authoritative full rebuild.
-- Zero-allocation dispatcher: one parentless frame + swap queues replace
-- a C_Timer.After timer object per deferred aura event. Parentless so
-- draining continues while UIParent is hidden (cinematics, alt-Z),
-- matching C_Timer semantics; hidden whenever idle.
do
    local queueA, queueB = {}, {}
    local active = queueA
    local dispatcher = CreateFrame("Frame")
    dispatcher:Hide()

    local function DrainPlate(plate)
        plate._auraFallbackPending = nil
        if plate._auraOwedFull or plate._auraAwaitingUnitAura then
            plate._auraOwedFull = nil
            plate._auraAwaitingUnitAura = nil
            plate._pendingAuraUpdate = nil
            if plate._pendingMeta then plate._pendingMeta.updateInfo = nil end
            if plate.unit then plate:UpdateAuras(nil) end
            return
        end
        local pending = plate._pendingAuraUpdate
        if pending then
            plate._pendingAuraUpdate = nil
            if plate.unit then
                plate:UpdateAuras(pending)
            elseif plate._pendingMeta then
                plate._pendingMeta.updateInfo = nil
            end
        end
    end

    dispatcher:SetScript("OnUpdate", function(self)
        -- Swap first: enqueues from inside a drain (e.g. the same-frame
        -- coalescing guard re-owing a rebuild) land in the other table
        -- and run next frame -- no pairs-mutation, no lost enqueues.
        local drained = active
        active = (drained == queueA) and queueB or queueA
        for plate in pairs(drained) do
            drained[plate] = nil
            DrainPlate(plate)
        end
        wipe(drained)
        if not next(active) then self:Hide() end
    end)

    function ns._npEnqueueAuraWork(plate)
        active[plate] = true
        dispatcher:Show()
    end

    -- Plate recycle hygiene: a released plate must not be drained
    function ns._npDequeueAuraWork(plate)
        queueA[plate] = nil
        queueB[plate] = nil
    end
end

function NameplateFrame:QueueAuraFallback()
    if self._auraFallbackPending then return end
    self._auraFallbackPending = true
    ns._npEnqueueAuraWork(self)
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
    -- Directly hide instead of UpdateCast: in restricted execution,
    -- UnitCastingInfo can return secret values (not nil) for a stale
    -- channel, making UpdateCast think a cast is still active.
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
    if interrupterGUID and ((issecretvalue and issecretvalue(protected)) or not protected) then
        self:ShowCastLockout()
    end
    self:ShowInterrupted(interrupterGUID)
end
-- Mid-cast interruptibility flips: re-read protection once, store it,
-- refresh color + kick tick + overlay. The cooldown watcher no longer
-- re-reads cast info per event, so these events are the only mid-cast
-- source of protection changes.
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
    self:UpdateCast()
end

-------------------------------------------------------------------------------
--  Centralized cast event dispatcher: registers all 13 SPELLCAST events ONCE
--  globally instead of 13 RegisterUnitEvent calls per plate. On each event,
--  looks up ns.plates[unit] (O(1) hash) and dispatches to the plate's handler.
--  Cast-identity caching: the full UpdateCast path caches _kickProtected /
--  _kickIsChannel / _kickIsEmpowered on the plate, so the SPELL_UPDATE_
--  COOLDOWN/USABLE watcher never re-reads cast info per event (it re-pins
--  the kick-tick value pair from the cache via RefreshKickTick). Cache
--  maintenance is event-driven:
--    * INTERRUPTIBLE/NOT_INTERRUPTIBLE -> KickProtectionChanged re-reads
--      protection once, stores it, refreshes color + tick + overlay
--    * DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE -> _kickGeoDirty makes the
--      next UpdateCast re-derive kick geometry from the cached identity
--    * START/CHANNEL_START/EMPOWER_START -> _castDirtyFull = full setup,
--      which refreshes every cached field
--    * ClearUnit and mid-cast plate token swaps (UpdateHealthValues)
--      tear down and invalidate all cast caches
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

-- Per-unit event watchers for pending friendly units.
-- Using per-unit frames avoids the global UNIT_FLAGS firehose.
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
        -- Remove friendly plate WITHOUT restoring Blizzard UF (we'll suppress it as enemy)
        if ns.RemoveFriendlyPlateNoRestore then
            ns.RemoveFriendlyPlateNoRestore(u)
        elseif ns.RemoveFriendlyPlate then
            ns.RemoveFriendlyPlate(u)
        end
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
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

-- Single shared UNIT_FACTION handler avoids N watchers each registering
-- the global event.  Dispatches to the correct watcher's OnEvent handler.
-- Only active in the open world (duels can't happen in instanced content).
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
factionFrame:SetScript("OnEvent", function(_, event, unit)
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
-- Unified mouseover monitor (enemy + friendly). UPDATE_MOUSEOVER_UNIT fires when
-- a mouseover STARTS but never when it clears, so a single shared 0.1s ticker
-- (alive only while a mouseover exists) watches for the mouse leaving. A held
-- mouse button transiently drops the mouseover unit, so in that case we wait for
-- GLOBAL_MOUSE_UP (handled on `manager`) and re-check.
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
end

function ns._UpdateMouseover()
    local cur = ns._currentMouseoverPlate
    if cur then
        ns.HideHoverEffect(cur)
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
        ns._currentMouseoverPlate = found
    end
    ns._EnsureMouseoverTicker()
end
-- Refresh Y-offset on all visible friendly name-only plates
function ns.RefreshFriendlyNameOnlyOffset()
    local db = p or defaults
    local nameOnly = (db.friendlyNameOnly ~= false)
    local yOff = nameOnly and (db.friendlyNameOnlyYOffset or 0) or 0
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
            -- Ensure the Blizzard UF is visible for name-only friendly plates.
            -- Nameplate frames are recycled a UF previously used for an enemy
            -- may still have alpha 0 or children parented offscreen.
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
                -- Apply Y-offset
                local yOff = db.friendlyNameOnlyYOffset or 0
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
        -- If this plate is the current target, update the cached ref so
        -- class power pips track it immediately (no PLAYER_TARGET_CHANGED
        -- fires when a nameplate is recycled for the same target unit).
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
        -- Non-Target Opacity: gaining/losing a target flips every plate's
        -- fade state, so this is the one full-iteration site. Zero cost
        -- while off (single compare); value-guarded SetAlpha when on.
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
--  Applies the correct spec-assigned preset on login and on spec change,
--  even before the options UI is ever opened.  Once the UI opens and
--  RegisterSpecAutoSwitch is called, the framework handler takes over for
--  PLAYER_SPECIALIZATION_CHANGED; this early handler ensures the first
--  login is covered.
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

    -- Store preset keys so the login handler can use them (set once, never changes).
    -- Split into two tables and concatenated to stay under Lua 5.1's
    -- per-function constant limit.
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
        -- Re-read profile reference: spec swap may have changed the
        -- active profile. Without this, all color lookups via _C()
        -- read stale data from the old spec's profile.
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
    -- Non-Target Opacity: derive the cached value at login (no plates exist
    -- yet, so the apply loop is a no-op; SetUnit fades new plates as they
    -- spawn).
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
    -- Re-read profile: PreSeedSpecProfile may have re-pointed db.profile
    -- to a different table between OnInitialize and OnEnable.
    p = ENP.db.profile
    RawSetTex = (PP and PP.RawSetTexture) or function(t, v) t:SetTexture(v) end
    SetupAuraCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if ns._ApplySpecPresetFromDB then ns._ApplySpecPresetFromDB() end
end
