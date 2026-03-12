local addon, ns = ...

local pairs, ipairs, type = pairs, ipairs, type
local PP = EllesmereUI.PP
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local C_UnitAuras = C_UnitAuras
local CooldownFrame_Clear = CooldownFrame_Clear
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
local function GetFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("nameplates")
    end
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.font or defaults.font
end
local function GetNPOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or "OUTLINE"
end
local function GetNPUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
end
local function SetFSFont(fs, size, flags)
  if not (fs and fs.SetFont) then return end
  local f = flags or GetNPOutline()
  fs:SetFont(GetFont(), size or 11, f)
  if f == "" then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
  else
    fs:SetShadowOffset(0, 0)
  end
end

ns.GetFont = GetFont
ns.GetNPOutline = GetNPOutline
ns.GetNPUseShadow = GetNPUseShadow
ns.SetFSFont = SetFSFont
ns.plates = {}
_G.EllesmereNameplates_NS = ns

-- Constant table for health text bar slots (hoisted to file scope to avoid
-- per-call allocation inside UpdateHealthValues).
local HP_BAR_SLOTS = {
    { key = "textSlotRight",  anchor = "RIGHT",  point = "RIGHT",  xOff = -2 },
    { key = "textSlotLeft",   anchor = "LEFT",   point = "LEFT",   xOff = 4 },
    { key = "textSlotCenter", anchor = "CENTER", point = "CENTER", xOff = 0 },
}

local defaults = {
    hostile = { r = 0.39, g = 0.11, b = 0.09 },
    neutral = { r = 0.81, g = 0.72, b = 0.19 },
    tapped  = { r = 0.50, g = 0.50, b = 0.50 },
    focus = { r = 0.051, g = 0.820, b = 0.620 },
    focusColorEnabled = true,
    focusOverlayTexture = "striped-v2",
    focusOverlayAlpha = 0.40,
    focusOverlayColor = { r = 1.0, g = 1.0, b = 1.0 },
    caster  = { r = 0.231, g = 0.510, b = 0.965 },
    miniboss = { r = 0.518, g = 0.243, b = 0.984 },
    enemyInCombat = { r = 0.800, g = 0.137, b = 0.137 },
    tankHasAggro = { r = 0.05, g = 0.82, b = 0.62 },
    tankHasAggroEnabled = false,
    tankLosingAggro = { r = 0.81, g = 0.72, b = 0.19 },
    tankNoAggro = { r = 1.00, g = 0.22, b = 0.17 },
    dpsNearAggro = { r = 0.81, g = 0.72, b = 0.19 },
    dpsHasAggro = { r = 1.00, g = 0.50, b = 0.00 },
    interruptReady = { r = 0.92, g = 0.35, b = 0.20 },  
    castBar = { r = 0.70, g = 0.40, b = 0.90 },
    castBarUninterruptible = { r = 0.45, g = 0.45, b = 0.45 },
    healthBarHeight = 17,
    friendlyNameOnly = true,
    friendlyNameOnlyYOffset = -20,
    friendlyPlateYOffset = 0,
    friendlyHealthBarHeight = 17,
    friendlyHealthBarWidth = 150,
    showFriendlyNPCs = false,
    showFriendlyPlayers = true,
    friendlyShowDefaultNames = false,
    classColorFriendly = true,
    showEnemyPets = false,
    font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF",
    showHealthNumber = false,
    hpPercentPos = "right",
    hpNumberPos = "none",
    textSlotTop = "enemyName",
    textSlotRight = "healthPercent",
    textSlotLeft = "none",
    textSlotCenter = "none",
    healthTextColor = { r = 1, g = 1, b = 1 },
    showTargetArrows = false,
    targetArrowScale = 1.0,
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
    healthBarWidth = 6,
    nameplateOverlapV = 1.05,
    stackSpacingScale = 50,
    stackingEnabled = true,
    nameplateYOffset = 0,
    enemyNameTextSize = 11,
    enemyNameColor = { r = 1, g = 1, b = 1 },
    debuffTextWhite = false,
    debuffTimerColor = { r = 1, g = 1, b = 1 },
    debuffTextPosition = "topleft",
    auraTextPosition = "topleft",
    debuffTimerPosition = "topleft",
    buffTimerPosition = "topleft",
    ccTimerPosition = "topleft",
    auraDurationTextSize = 11,
    auraDurationTextColor = { r = 1, g = 1, b = 1 },
    auraStackTextSize = 11,
    auraStackTextColor = { r = 1, g = 1, b = 1 },
    debuffSlot = "top",
    buffSlot = "left",
    ccSlot = "right",
    debuffYOffset = 2,
    sideAuraXOffset = 2,
    nameYOffset = 0,
    enemyNamePos = "top",
    auraSpacing = 2,
    debuffIconSize = 26,
    buffIconSize = 24,
    buffTextSize = 12,
    buffTextColor = { r = 1, g = 1, b = 1 },
    ccIconSize = 24,
    ccTextSize = 12,
    ccTextColor = { r = 1, g = 1, b = 1 },
    showTargetGlow = true,  -- legacy compat (true = "ellesmereui")
    targetGlowStyle = "ellesmereui",
    raidMarkerPos = "topright",
    raidMarkerSize = 24,
    raidMarkerYOffset = 2,
    classificationSlot = "topleft",
    rareEliteIconSize = 20,
    rareEliteIconYOffset = 0,
    rareEliteIconXOffset = 0,
    castBarHeight = 17,
    castNameSize = 10,
    castNameColor = { r = 1, g = 1, b = 1 },
    castTargetSize = 10,
    castTargetClassColor = true,
    castTargetColor = { r = 1, g = 1, b = 1 },
    healthTextSize = 10,
    showAllDebuffs = false,
    borderStyle = "ellesmere",
    borderColor = { r = 0.067, g = 0.067, b = 0.067 },
    pandemicGlow = false,
    pandemicGlowStyle = 1,
    pandemicGlowColor = { r = 1.0, g = 0.800, b = 0.329 },
    pandemicGlowLines = 8,
    pandemicGlowThickness = 1,
    pandemicGlowSpeed = 4,
    castScale = 100,
    focusCastHeight = 100,
    questMobColorEnabled = false,
    questMobColor = { r = 0.157, g = 0.855, b = 0.475 },
    showCastIcon = true,
    castIconScale = 1,
    hashLineEnabled = false,
    hashLinePercent = 30,
    hashLineColor = { r = 1, g = 1, b = 1 },
    kickTickEnabled = true,
    kickTickColor = { r = 1, g = 1, b = 1 },
    -- Core Positions: slot-based size + XY offsets
    topSlotSize = 26,        topSlotXOffset = 0,      topSlotYOffset = 0,
    rightSlotSize = 24,      rightSlotXOffset = 0,    rightSlotYOffset = 0,
    leftSlotSize = 24,       leftSlotXOffset = 0,     leftSlotYOffset = 0,
    toprightSlotSize = 24,   toprightSlotXOffset = 0, toprightSlotYOffset = 0, toprightSlotGrowth = "right",
    topleftSlotSize = 24,    topleftSlotXOffset = 0,  topleftSlotYOffset = 0,  topleftSlotGrowth = "left",
    bottomSlotSize = 26,     bottomSlotXOffset = 0,   bottomSlotYOffset = 0,
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
}
local BAR_W = 150
ns.defaults = defaults
ns.BAR_W = BAR_W
local CAST_H = 17

-- Health bar texture overlay tables (stored on ns to avoid local count pressure)
do
    local TB = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
    ns.healthBarTextures = {
        ["none"]          = nil,
        ["beautiful"]     = TB .. "beautiful.tga",
        ["plating"]       = TB .. "plating.tga",
        ["atrocity"]      = TB .. "atrocity.tga",
        ["divide"]        = TB .. "divide.tga",
        ["glass"]         = TB .. "glass.tga",
        ["gradient-lr"]   = TB .. "gradient-lr.tga",
        ["gradient-rl"]   = TB .. "gradient-rl.tga",
        ["gradient-bt"]   = TB .. "gradient-bt.tga",
        ["gradient-tb"]   = TB .. "gradient-tb.tga",
        ["matte"]         = TB .. "matte.tga",
        ["sheer"]         = TB .. "sheer.tga",
    }
    ns.healthBarTextureOrder = {
        "none", "beautiful", "plating",
        "atrocity", "divide", "glass",
        "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
        "matte", "sheer",
    }
    ns.healthBarTextureNames = {
        ["none"]        = "None",
        ["beautiful"]   = "Beautiful",
        ["plating"]     = "Plating",
        ["atrocity"]    = "Atrocity",
        ["divide"]      = "Divide",
        ["glass"]       = "Glass",
        ["gradient-lr"] = "Gradient Right",
        ["gradient-rl"] = "Gradient Left",
        ["gradient-bt"] = "Gradient Up",
        ["gradient-tb"] = "Gradient Down",
        ["matte"]       = "Matte",
        ["sheer"]       = "Sheer",
    }
end

local function ApplyHealthBarTexture(plate)
    local health = plate.health
    if not health then return end
    local db = EllesmereUINameplatesDB
    local texKey = (db and db.healthBarTexture) or defaults.healthBarTexture or "none"
    local path   = ns.healthBarTextures[texKey]

    if path then
        health:SetStatusBarTexture(path)
    else
        health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    end
end
ns.ApplyHealthBarTexture = ApplyHealthBarTexture

local HOVER_ALPHA = 0.3
local function GetNameplateYOffset()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.nameplateYOffset or defaults.nameplateYOffset
end
ns.GetNameplateYOffset = GetNameplateYOffset
local function GetStackSpacingScale()
    return (EllesmereUINameplatesDB and EllesmereUINameplatesDB.stackSpacingScale) or defaults.stackSpacingScale
end
ns.GetStackSpacingScale = GetStackSpacingScale
local function GetCastScale()
    return (EllesmereUINameplatesDB and EllesmereUINameplatesDB.castScale) or defaults.castScale
end
ns.GetCastScale = GetCastScale
local function GetHealthBarHeight()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.healthBarHeight or defaults.healthBarHeight
end
ns.GetHealthBarHeight = GetHealthBarHeight
local function GetFriendlyHealthBarHeight()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyHealthBarHeight or defaults.friendlyHealthBarHeight
end
ns.GetFriendlyHealthBarHeight = GetFriendlyHealthBarHeight
local function GetFriendlyHealthBarWidth()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.friendlyHealthBarWidth or defaults.friendlyHealthBarWidth
end
ns.GetFriendlyHealthBarWidth = GetFriendlyHealthBarWidth
local function GetEnemyNameTextSize()
    -- Returns the font size of the top text slot (used for stacking gap calculations)
    local db = EllesmereUINameplatesDB
    return (db and db.textSlotTopSize) or defaults.textSlotTopSize or 10
end
ns.GetEnemyNameTextSize = GetEnemyNameTextSize
local function GetDebuffTextColor()
    local db = EllesmereUINameplatesDB
    -- Legacy support: if debuffTextWhite was set but debuffTimerColor wasn't customized, use white
    if db and db.debuffTimerColor then
        local c = db.debuffTimerColor
        return c.r, c.g, c.b, 1
    end
    local useWhite = db and db.debuffTextWhite or defaults.debuffTextWhite
    if useWhite then
        return 1, 1, 1, 1
    else
        return defaults.debuffTimerColor.r, defaults.debuffTimerColor.g, defaults.debuffTimerColor.b, 1
    end
end
ns.GetDebuffTextColor = GetDebuffTextColor
local function GetPandemicGlow()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.pandemicGlow or defaults.pandemicGlow
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

local function GetPandemicGlowStyle()
    local db = EllesmereUINameplatesDB
    local raw = db and db.pandemicGlowStyle
    if raw == nil then return defaults.pandemicGlowStyle end
    -- One-time legacy migration: old string keys or old numeric indices new order
    -- The flag _pandemicGlowMigrated prevents re-migration after the user picks a new value
    if not db._pandemicGlowMigrated then
        local migrated
        if raw == "pixel" or raw == "ants" then migrated = 1
        elseif raw == "button" or raw == "proc" then migrated = 5
        elseif raw == "autocast" then migrated = 3
        elseif type(raw) == "number" and raw <= 4 then
            local map = { [1] = 5, [2] = 5, [3] = 6, [4] = 1 }
            migrated = map[raw]
        end
        if migrated then
            db.pandemicGlowStyle = migrated
            raw = migrated
        end
        db._pandemicGlowMigrated = true
    end
    if type(raw) == "number" then return raw end
    return 1
end
ns.GetPandemicGlowStyle = GetPandemicGlowStyle
local function GetPandemicGlowColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.pandemicGlowColor) or defaults.pandemicGlowColor
    return c.r, c.g, c.b
end
local function GetPandemicGlowLines()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.pandemicGlowLines or defaults.pandemicGlowLines
end
ns.GetPandemicGlowLines = GetPandemicGlowLines
local function GetPandemicGlowThickness()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.pandemicGlowThickness or defaults.pandemicGlowThickness
end
ns.GetPandemicGlowThickness = GetPandemicGlowThickness
local function GetPandemicGlowSpeed()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.pandemicGlowSpeed or defaults.pandemicGlowSpeed
end
ns.GetPandemicGlowSpeed = GetPandemicGlowSpeed
local function GetCastBarHeight()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.castBarHeight or defaults.castBarHeight
end
ns.GetCastBarHeight = GetCastBarHeight
local function GetFocusCastHeight()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.focusCastHeight or defaults.focusCastHeight
end
ns.GetFocusCastHeight = GetFocusCastHeight
local function GetShowCastIcon()
    local db = EllesmereUINameplatesDB
    if db and db.showCastIcon ~= nil then return db.showCastIcon end
    return defaults.showCastIcon
end
local function GetCastIconScale()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.castIconScale or defaults.castIconScale
end
local function GetKickTickEnabled()
    local db = EllesmereUINameplatesDB
    if db and db.kickTickEnabled ~= nil then return db.kickTickEnabled end
    return true
end
local function GetKickTickColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.kickTickColor) or defaults.kickTickColor
    return c.r, c.g, c.b
end
local function GetAuraSpacing()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.auraSpacing or defaults.auraSpacing
end
ns.GetAuraSpacing = GetAuraSpacing
local function GetDebuffYOffset()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.debuffYOffset or defaults.debuffYOffset
end
ns.GetDebuffYOffset = GetDebuffYOffset
local function GetSideAuraXOffset()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.sideAuraXOffset or defaults.sideAuraXOffset
end
ns.GetSideAuraXOffset = GetSideAuraXOffset
local function GetRaidMarkerPos()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.raidMarkerPos or defaults.raidMarkerPos
end
ns.GetRaidMarkerPos = GetRaidMarkerPos
local function GetRaidMarkerSize()
    local pos = EllesmereUINameplatesDB and EllesmereUINameplatesDB.raidMarkerPos or defaults.raidMarkerPos
    if pos == "none" then return defaults.raidMarkerSize or 24 end
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB[pos .. "SlotSize"] or defaults[pos .. "SlotSize"] or 24
end
ns.GetRaidMarkerSize = GetRaidMarkerSize
local function GetRaidMarkerYOffset()
    return 0  -- legacy stub; slot Y offset used instead
end
ns.GetRaidMarkerYOffset = GetRaidMarkerYOffset
local function GetClassificationSlot()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.classificationSlot or defaults.classificationSlot
end
ns.GetClassificationSlot = GetClassificationSlot
local function GetRareEliteIconSize()
    local pos = EllesmereUINameplatesDB and EllesmereUINameplatesDB.classificationSlot or defaults.classificationSlot
    if pos == "none" then return defaults.rareEliteIconSize or 20 end
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB[pos .. "SlotSize"] or defaults[pos .. "SlotSize"] or 20
end
ns.GetRareEliteIconSize = GetRareEliteIconSize
local function GetRareEliteIconYOffset()
    return 0  -- legacy stub; slot Y offset used instead
end
ns.GetRareEliteIconYOffset = GetRareEliteIconYOffset
local function GetRareEliteIconXOffset()
    return 0  -- legacy stub; slot X offset used instead
end
ns.GetRareEliteIconXOffset = GetRareEliteIconXOffset
local function GetNameYOffset()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.nameYOffset or defaults.nameYOffset
end
ns.GetNameYOffset = GetNameYOffset
local textSlotKeys = { "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter" }
ns.textSlotKeys = textSlotKeys

local function GetTextSlot(slotKey)
    local db = EllesmereUINameplatesDB
    return (db and db[slotKey]) or defaults[slotKey]
end
ns.GetTextSlot = GetTextSlot

local function FindSlotForElement(element)
    for _, key in ipairs(textSlotKeys) do
        if GetTextSlot(key) == element then return key end
    end
    return nil
end
ns.FindSlotForElement = FindSlotForElement

local function FormatCombinedHealth(element, pctText, numText)
    if element == "healthPctNum" then return pctText .. " | " .. numText
    elseif element == "healthNumPct" then return numText .. " | " .. pctText
    end
    return ""
end

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
}
local function EstimateHealthTextWidth(element)
    return (healthTextWidths[element] or 0) + HEALTH_TEXT_PADDING
end
ns.EstimateHealthTextWidth = EstimateHealthTextWidth

local function GetHealthBarWidth()
    local extra = EllesmereUINameplatesDB and EllesmereUINameplatesDB.healthBarWidth or defaults.healthBarWidth
    return BAR_W + extra
end
ns.GetHealthBarWidth = GetHealthBarWidth
-- Slot-based size/offset getters
local function GetSlotSize(posKey)
    local db = EllesmereUINameplatesDB
    return (db and db[posKey .. "SlotSize"]) or defaults[posKey .. "SlotSize"] or 24
end
ns.GetSlotSize = GetSlotSize
local function GetSlotOffsets(posKey)
    local db = EllesmereUINameplatesDB
    local xOff = (db and db[posKey .. "SlotXOffset"]) or defaults[posKey .. "SlotXOffset"] or 0
    local yOff = (db and db[posKey .. "SlotYOffset"]) or defaults[posKey .. "SlotYOffset"] or 0
    return xOff, yOff
end
ns.GetSlotOffsets = GetSlotOffsets
local function GetDebuffIconSize()
    local db = EllesmereUINameplatesDB
    local slot = (db and db.debuffSlot) or defaults.debuffSlot
    if slot == "none" then return defaults.debuffIconSize or 26 end
    return GetSlotSize(slot)
end
ns.GetDebuffIconSize = GetDebuffIconSize
local function GetBuffIconSize()
    local db = EllesmereUINameplatesDB
    local slot = (db and db.buffSlot) or defaults.buffSlot
    if slot == "none" then return defaults.buffIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetBuffIconSize = GetBuffIconSize
local function GetCCIconSize()
    local db = EllesmereUINameplatesDB
    local slot = (db and db.ccSlot) or defaults.ccSlot
    if slot == "none" then return defaults.ccIconSize or 24 end
    return GetSlotSize(slot)
end
ns.GetCCIconSize = GetCCIconSize
local function GetTargetGlowStyle()
    local db = EllesmereUINameplatesDB
    if db and db.targetGlowStyle then return db.targetGlowStyle end
    -- Backward compat: old boolean showTargetGlow
    if db and db.showTargetGlow == false then return "none" end
    return defaults.targetGlowStyle
end
ns.GetTargetGlowStyle = GetTargetGlowStyle
-- Legacy wrapper
local function GetShowTargetGlow()
    return GetTargetGlowStyle() ~= "none"
end
ns.GetShowTargetGlow = GetShowTargetGlow
local function GetShowClassPower()
    local db = EllesmereUINameplatesDB
    if db and db.showClassPower ~= nil then return db.showClassPower end
    return defaults.showClassPower
end
ns.GetShowClassPower = GetShowClassPower
local function GetClassPowerPos()
    local db = EllesmereUINameplatesDB
    return (db and db.classPowerPos) or defaults.classPowerPos
end
ns.GetClassPowerPos = GetClassPowerPos
local function GetClassPowerYOffset()
    local db = EllesmereUINameplatesDB
    return (db and db.classPowerYOffset) or defaults.classPowerYOffset
end
ns.GetClassPowerYOffset = GetClassPowerYOffset
local function GetClassPowerXOffset()
    local db = EllesmereUINameplatesDB
    return (db and db.classPowerXOffset) or defaults.classPowerXOffset
end
ns.GetClassPowerXOffset = GetClassPowerXOffset
local function GetClassPowerScale()
    local db = EllesmereUINameplatesDB
    return (db and db.classPowerScale) or defaults.classPowerScale
end
ns.GetClassPowerScale = GetClassPowerScale
local function GetClassPowerGap()
    local db = EllesmereUINameplatesDB
    return (db and db.classPowerGap) or defaults.classPowerGap
end
ns.GetClassPowerGap = GetClassPowerGap
local function GetClassPowerClassColors()
    local db = EllesmereUINameplatesDB
    if db and db.classPowerClassColors ~= nil then return db.classPowerClassColors end
    return defaults.classPowerClassColors
end
ns.GetClassPowerClassColors = GetClassPowerClassColors
local function GetClassPowerCustomColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.classPowerCustomColor) or defaults.classPowerCustomColor
    return c
end
ns.GetClassPowerCustomColor = GetClassPowerCustomColor
local function GetClassPowerBgColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.classPowerBgColor) or defaults.classPowerBgColor
    return c
end
ns.GetClassPowerBgColor = GetClassPowerBgColor
local function GetClassPowerEmptyColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.classPowerEmptyColor) or defaults.classPowerEmptyColor
    return c
end
ns.GetClassPowerEmptyColor = GetClassPowerEmptyColor
local function GetBorderStyle()
    return EllesmereUINameplatesDB and EllesmereUINameplatesDB.borderStyle or defaults.borderStyle
end
ns.GetBorderStyle = GetBorderStyle
local function GetBorderColor()
    local db = EllesmereUINameplatesDB
    local c = (db and db.borderColor) or defaults.borderColor
    return c.r, c.g, c.b
end
ns.GetBorderColor = GetBorderColor
local function GetAuraSlots()
    local db = EllesmereUINameplatesDB
    local ds = (db and db.debuffSlot) or defaults.debuffSlot
    local bs = (db and db.buffSlot)   or defaults.buffSlot
    local cs = (db and db.ccSlot)     or defaults.ccSlot
    return ds, bs, cs
end
ns.GetAuraSlots = GetAuraSlots

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
        wrapper:SetFrameLevel(slot:GetFrameLevel() + 1)
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
        StartProceduralAnts(pg.wrapper, N, th, period, lineLen, cr, cg, cb, sz)
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
end
ns.StopPandemicGlow = StopPandemicGlow
ns.ApplyPandemicGlow = ApplyPandemicGlow
end -- do (glow engine)

-- Forward declaration (defined later in the class power section)
local GetClassPowerTopPush
-- Position a set of aura frames into a slot ("top", "left", or "right")
-- frames: array of frame objects, count: how many to show, plate: the nameplate
-- sizeW/sizeH: icon dimensions, gap: pixel gap between icon edges
local function PositionAuraSlot(frames, count, slot, plate, sizeW, sizeH, gap, xOff, yOff)
    xOff = xOff or 0
    yOff = yOff or 0
    local spacing = gap + sizeW  -- center-to-center distance
    for i = 1, count do
        frames[i]:ClearAllPoints()
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
            PP.Point(frames[i], "BOTTOM", anchor, "TOP",
                (i - (count + 1) / 2) * spacing + xOff, debuffY + cpPush + yOff)
        elseif slot == "left" then
            local sideOff = GetSideAuraXOffset()
            PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "BOTTOMLEFT",
                -sideOff - (i - 1) * spacing + xOff, yOff)
        elseif slot == "right" then
            local sideOff = GetSideAuraXOffset()
            PP.Point(frames[i], "BOTTOMLEFT", plate.health, "BOTTOMRIGHT",
                sideOff + (i - 1) * spacing + xOff, yOff)
        elseif slot == "topleft" then
            local debuffY = GetDebuffYOffset()
            local cpPush = GetClassPowerTopPush(plate)
            local db = EllesmereUINameplatesDB
            local growth = (db and db.topleftSlotGrowth) or defaults.topleftSlotGrowth
            -- Icon 1 is always flush with the top-left corner of the health bar.
            -- Growth direction only affects where icons 2+ go from there.
            local baseX = -2 + xOff
            local baseY = debuffY + cpPush + yOff
            local idx = i - 1  -- 0 for icon 1, so it never moves
            if growth == "up" then
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX, baseY + idx * spacing)
            elseif growth == "right" then
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX + idx * spacing, baseY)
            else
                -- Default: grow left
                PP.Point(frames[i], "BOTTOMLEFT", plate.health, "TOPLEFT",
                    baseX - idx * spacing, baseY)
            end
        elseif slot == "topright" then
            local debuffY = GetDebuffYOffset()
            local cpPush = GetClassPowerTopPush(plate)
            local db = EllesmereUINameplatesDB
            local growth = (db and db.toprightSlotGrowth) or defaults.toprightSlotGrowth
            -- Icon 1 is always flush with the top-right corner of the health bar.
            -- Growth direction only affects where icons 2+ go from there.
            local baseX = 2 + xOff
            local baseY = debuffY + cpPush + yOff
            local idx = i - 1  -- 0 for icon 1, so it never moves
            if growth == "up" then
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX, baseY + idx * spacing)
            elseif growth == "left" then
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX - idx * spacing, baseY)
            else
                -- Default: grow right
                PP.Point(frames[i], "BOTTOMRIGHT", plate.health, "TOPRIGHT",
                    baseX + idx * spacing, baseY)
            end
        elseif slot == "bottom" then
            -- Anchor below the cast bar, centered
            PP.Point(frames[i], "TOP", plate.cast, "BOTTOM",
                (i - (count + 1) / 2) * spacing + xOff, -2 + yOff)
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
    local db = EllesmereUINameplatesDB
    local pos = (db and db[dbKey]) or defaults[dbKey]
    if not pos or pos == "none" then return 0, 0 end
    return GetSlotOffsets(pos)
end

-- Get XY offset for a text slot key (e.g. "textSlotTop")
local function GetTextSlotOffsets(slotKey)
    local db = EllesmereUINameplatesDB
    local xOff = (db and db[slotKey .. "XOffset"]) or 0
    local yOff = (db and db[slotKey .. "YOffset"]) or 0
    return xOff, yOff
end

-- Get font size for a text slot key (e.g. "textSlotTop")
local function GetTextSlotSize(slotKey)
    local db = EllesmereUINameplatesDB
    return (db and db[slotKey .. "Size"]) or defaults[slotKey .. "Size"] or 10
end
ns.GetTextSlotSize = GetTextSlotSize

-- Get color for a text slot key (e.g. "textSlotTop")
local function GetTextSlotColor(slotKey)
    local db = EllesmereUINameplatesDB
    local c = (db and db[slotKey .. "Color"]) or defaults[slotKey .. "Color"]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Position target arrows OUTSIDE the outermost side auras (if arrows are shown).
-- Called after all aura positioning is complete.
local function PositionArrowsOutsideAuras(plate)
    if not plate.leftArrow then return end
    if not plate.leftArrow:IsShown() then return end
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    local gap = GetAuraSpacing()
    local sideOff = GetSideAuraXOffset()
    -- Track the furthest pixel extent on each side (accounts for per-slot X offsets)
    local leftExtent, rightExtent = 0, 0
    local function addSide(slot, frames, maxIdx, sz, slotKey)
        local shown = 0
        for i = 1, maxIdx do
            if frames[i] and frames[i]:IsShown() then shown = shown + 1 end
        end
        if shown == 0 then return end
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
    end
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    addSide(debuffSlot, plate.debuffs or {}, 6, debuffSz, "debuffSlot")
    addSide(buffSlot, plate.buffs or {}, 4, buffSz, "buffSlot")
    addSide(ccSlot, plate.cc or {}, 2, ccSz, "ccSlot")
    -- Account for raid marker in side slots
    local rmPos = GetRaidMarkerPos()
    if rmPos == "left" and plate.raidFrame and plate.raidFrame:IsShown() then
        local rmSz = GetRaidMarkerSize()
        local rxOff = select(1, GetAuraSlotOffsets("raidMarker"))
        leftExtent = math.max(leftExtent, sideOff + rmSz - rxOff)
    elseif rmPos == "right" and plate.raidFrame and plate.raidFrame:IsShown() then
        local rmSz = GetRaidMarkerSize()
        local rxOff = select(1, GetAuraSlotOffsets("raidMarker"))
        rightExtent = math.max(rightExtent, sideOff + rmSz + rxOff)
    end
    -- Account for classification icon in side slots
    local clSlot = GetClassificationSlot()
    local clSz = GetRareEliteIconSize()
    if clSlot == "left" and plate.classFrame and plate.classFrame:IsShown() then
        local cxOff = select(1, GetAuraSlotOffsets("classification"))
        leftExtent = math.max(leftExtent, sideOff + clSz - cxOff)
    elseif clSlot == "right" and plate.classFrame and plate.classFrame:IsShown() then
        local cxOff = select(1, GetAuraSlotOffsets("classification"))
        rightExtent = math.max(rightExtent, sideOff + clSz + cxOff)
    end
    plate.leftArrow:ClearAllPoints()
    plate.rightArrow:ClearAllPoints()
    if leftExtent > 0 then
        PP.Point(plate.leftArrow, "RIGHT", plate.health, "LEFT", -(leftExtent + 8), 0)
    else
        PP.Point(plate.leftArrow, "RIGHT", plate.health, "LEFT", -8, 0)
    end
    if rightExtent > 0 then
        PP.Point(plate.rightArrow, "LEFT", plate.health, "RIGHT", rightExtent + 8, 0)
    else
        PP.Point(plate.rightArrow, "LEFT", plate.health, "RIGHT", 8, 0)
    end
end
ns.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras

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
    plate.healthBG:SetColorTexture(0.12, 0.12, 0.12, 1.0)
    -- Hash line: thin vertical marker at a configurable health percentage
    plate.hashLine = plate.health:CreateTexture(nil, "OVERLAY", nil, 3)
    plate.hashLine:SetColorTexture(1, 1, 1, 0.8)
    plate.hashLine:SetWidth(2)
    plate.hashLine:SetPoint("TOP", plate.health, "TOP", 0, 0)
    plate.hashLine:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, 0)
    plate.hashLine:Hide()
    -- Focus target overlay: two non-overlapping textures at the same fixed scale
    -- Fill overlay: full alpha, clipped to the fill region via a child frame
    -- Bg overlay: half alpha, covers only the empty region (fill right edge to bar right edge)
    local overlayAlpha = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.focusOverlayAlpha) or defaults.focusOverlayAlpha
    local overlayColor = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.focusOverlayColor) or defaults.focusOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\striped-v2.png"
    local fillTex = plate.health:GetStatusBarTexture()
    -- Fill overlay: clip frame sized to the fill texture, contains a fixed-size stripe texture
    plate.focusClipFill = CreateFrame("Frame", nil, plate.health)
    plate.focusClipFill:SetClipsChildren(true)
    plate.focusClipFill:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, -1)
    plate.focusClipFill:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 1)
    plate.focusClipFill:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayFill = plate.focusClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    plate.focusOverlayFill:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayFill:SetSize(200, 24)
    plate.focusOverlayFill:SetTexture(STRIPE_TEX)
    plate.focusOverlayFill:SetAlpha(overlayAlpha)
    plate.focusOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.focusClipFill:Hide()
    -- Bg overlay: clip frame covering only the empty region, contains a fixed-size stripe texture
    plate.focusClipBg = CreateFrame("Frame", nil, plate.health)
    plate.focusClipBg:SetClipsChildren(true)
    plate.focusClipBg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, -1)
    plate.focusClipBg:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", 0, 1)
    plate.focusClipBg:SetFrameLevel(plate.health:GetFrameLevel() + 1)
    plate.focusOverlayBg = plate.focusClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    plate.focusOverlayBg:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    plate.focusOverlayBg:SetSize(200, 24)
    plate.focusOverlayBg:SetTexture(STRIPE_TEX)
    plate.focusOverlayBg:SetAlpha(overlayAlpha * 0.3)
    plate.focusOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    plate.focusClipBg:Hide()
    plate.absorb = CreateFrame("StatusBar", nil, plate.health)
    plate.absorb:SetStatusBarTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\absorb-default.png")
    plate.absorb:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    plate.absorb:SetStatusBarColor(1, 1, 1, 0.8)
    plate.absorb:SetReverseFill(true)
    plate.absorb:SetPoint("TOPRIGHT", plate.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    plate.absorb:SetPoint("BOTTOMRIGHT", plate.health:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    plate.absorb:SetWidth(GetHealthBarWidth())
    plate.absorb:SetHeight(GetHealthBarHeight())
    plate.absorb:SetFrameLevel(plate.health:GetFrameLevel())
    plate.absorbOverflow = CreateFrame("StatusBar", nil, plate.health)
    plate.absorbOverflow:SetStatusBarTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\absorb-default.png")
    plate.absorbOverflow:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    plate.absorbOverflow:SetStatusBarColor(1, 1, 1, 0.8)
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
            PP.CreateBorder(parent, 0, 0, 0, 1, 1, "OVERLAY", 5)
        end
    end
    local BORDER_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-colorless.png"
    local BORDER_TEX_SIMPLE = "Interface\\AddOns\\EllesmereUINameplates\\Media\\border-simple.png"
    local BORDER_CORNER = 6

    local function CreateBorderSet(parent, tex, color)
        local f = CreateFrame("Frame", nil, parent)
        f:SetFrameLevel(parent:GetFrameLevel() + 5)
        f:SetAllPoints()
        f._texs = {}
        local function Mk()
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture(tex)
            t:SetVertexColor(color.r, color.g, color.b)
            f._texs[#f._texs + 1] = t
            return t
        end
        local tl = Mk(); tl:SetSize(BORDER_CORNER, BORDER_CORNER); tl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); tl:SetTexCoord(0, 0.5, 0, 0.5)
        local tr = Mk(); tr:SetSize(BORDER_CORNER, BORDER_CORNER); tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); tr:SetTexCoord(0.5, 1, 0, 0.5)
        local bl = Mk(); bl:SetSize(BORDER_CORNER, BORDER_CORNER); bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); bl:SetTexCoord(0, 0.5, 0.5, 1)
        local br = Mk(); br:SetSize(BORDER_CORNER, BORDER_CORNER); br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); br:SetTexCoord(0.5, 1, 0.5, 1)
        local top = Mk(); top:SetHeight(BORDER_CORNER); top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0); top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0); top:SetTexCoord(0.5, 0.5, 0, 0.5)
        local bot = Mk(); bot:SetHeight(BORDER_CORNER); bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0); bot:SetTexCoord(0.5, 0.5, 0.5, 1)
        local lft = Mk(); lft:SetWidth(BORDER_CORNER); lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0); lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0); lft:SetTexCoord(0, 0.5, 0.5, 0.5)
        local rgt = Mk(); rgt:SetWidth(BORDER_CORNER); rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0); rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0); rgt:SetTexCoord(0.5, 1, 0.5, 0.5)
        return f
    end

    local bc = { r = 0, g = 0, b = 0 }
    bc.r, bc.g, bc.b = GetBorderColor()
    plate.borderFrame = CreateBorderSet(plate.health, BORDER_TEX, bc)
    plate._simpleBorderFrame = CreateBorderSet(plate.health, BORDER_TEX_SIMPLE, bc)

    function plate:ApplyBorderStyle()
        local style = GetBorderStyle()
        if style == "none" then
            plate.borderFrame:Hide()
            plate._simpleBorderFrame:Hide()
        elseif style == "simple" then
            plate.borderFrame:Hide()
            plate._simpleBorderFrame:Show()
        else
            plate.borderFrame:Show()
            plate._simpleBorderFrame:Hide()
        end
    end
    function plate:ApplyBorderColor()
        local cr, cg, cb = GetBorderColor()
        for _, tex in ipairs(plate.borderFrame._texs) do tex:SetVertexColor(cr, cg, cb) end
        for _, tex in ipairs(plate._simpleBorderFrame._texs) do tex:SetVertexColor(cr, cg, cb) end
    end
    plate:ApplyBorderStyle()
    local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
    local GLOW_MARGIN = 0.48
    local GLOW_CORNER = 12
    local GLOW_EXTEND = 6
    plate.glowFrame = CreateFrame("Frame", nil, plate)  
    plate.glowFrame:SetFrameStrata("BACKGROUND")
    plate.glowFrame:SetFrameLevel(1)  
    plate.glowFrame:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    plate.glowFrame:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    local function CreateGlowTex()
        local t = plate.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(0.4117, 0.6667, 1.0, 1.0)
        t:SetBlendMode("ADD")
        return t
    end
    plate.glowTL = CreateGlowTex()
    plate.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTL:SetPoint("TOPLEFT")
    plate.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowTR = CreateGlowTex()
    plate.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTR:SetPoint("TOPRIGHT")
    plate.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    plate.glowBL = CreateGlowTex()
    plate.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBL:SetPoint("BOTTOMLEFT")
    plate.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowBR = CreateGlowTex()
    plate.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBR:SetPoint("BOTTOMRIGHT")
    plate.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    plate.glowTop = CreateGlowTex()
    plate.glowTop:SetHeight(GLOW_CORNER)
    plate.glowTop:SetPoint("TOPLEFT", plate.glowTL, "TOPRIGHT")
    plate.glowTop:SetPoint("TOPRIGHT", plate.glowTR, "TOPLEFT")
    plate.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowBottom = CreateGlowTex()
    plate.glowBottom:SetHeight(GLOW_CORNER)
    plate.glowBottom:SetPoint("BOTTOMLEFT", plate.glowBL, "BOTTOMRIGHT")
    plate.glowBottom:SetPoint("BOTTOMRIGHT", plate.glowBR, "BOTTOMLEFT")
    plate.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowLeft = CreateGlowTex()
    plate.glowLeft:SetWidth(GLOW_CORNER)
    plate.glowLeft:SetPoint("TOPLEFT", plate.glowTL, "BOTTOMLEFT")
    plate.glowLeft:SetPoint("BOTTOMLEFT", plate.glowBL, "TOPLEFT")
    plate.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glowRight = CreateGlowTex()
    plate.glowRight:SetWidth(GLOW_CORNER)
    plate.glowRight:SetPoint("TOPRIGHT", plate.glowTR, "BOTTOMRIGHT")
    plate.glowRight:SetPoint("BOTTOMRIGHT", plate.glowBR, "TOPRIGHT")
    plate.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glow = plate.glowFrame
    plate.glowFrame:Hide()  
    -- Text overlay frame: renders above focus stripe overlay (level +1)
    plate.healthTextFrame = CreateFrame("Frame", nil, plate)
    plate.healthTextFrame:SetAllPoints(plate.health)
    plate.healthTextFrame:SetFrameLevel(plate.health:GetFrameLevel() + 2)
    plate.hpText = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpText, 10, GetNPOutline())
    PP.Point(plate.hpText, "RIGHT", plate.health, "RIGHT", -2, 0)
    plate.hpNumber = plate.healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.hpNumber, 10, GetNPOutline())
    plate.hpNumber:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.hpNumber:Hide()
    plate.highlight = plate.healthTextFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    plate.highlight:SetAllPoints()
    plate.highlight:SetColorTexture(1, 1, 1, HOVER_ALPHA)
    plate.highlight:Hide()
    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    plate.topTextFrame = CreateFrame("Frame", nil, plate)
    plate.topTextFrame:SetAllPoints(plate.health)
    plate.topTextFrame:SetFrameLevel(plate.health:GetFrameLevel() + 6)
    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, GetEnemyNameTextSize(), GetNPOutline())
    PP.Point(plate.name, "BOTTOM", plate.health, "TOP", 0, 4)
    PP.Width(plate.name, math.max(GetHealthBarWidth(), 20))
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)
    plate.leftArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\arrow_left.png")
    plate.rightArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\arrow_right.png")
    do
        local sc = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.targetArrowScale) or 1.0
        local aw, ah = math.floor(11 * sc + 0.5), math.floor(16 * sc + 0.5)
        PP.Size(plate.leftArrow,  aw, ah)
        PP.Point(plate.leftArrow,  "RIGHT", plate.health, "LEFT",  -8, 0)
        plate.leftArrow:Hide()
        PP.Size(plate.rightArrow, aw, ah)
        PP.Point(plate.rightArrow, "LEFT",  plate.health, "RIGHT",  8, 0)
        plate.rightArrow:Hide()
    end
    plate.raidFrame = CreateFrame("Frame", nil, plate)
    local rmSize = GetRaidMarkerSize()
    PP.Size(plate.raidFrame, rmSize, rmSize)
    plate.raidFrame:SetFrameLevel(plate.health:GetFrameLevel() + 6)
    plate.raidFrame:Hide()
    plate.raid = plate.raidFrame:CreateTexture(nil, "ARTWORK")
    plate.raid:SetAllPoints()
    plate.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.classFrame = CreateFrame("Frame", nil, plate)
    local _reIconSz = GetRareEliteIconSize()
    PP.Size(plate.classFrame, _reIconSz, _reIconSz)
    PP.Point(plate.classFrame, "LEFT", plate.health, "LEFT", 2, 0)
    plate.classFrame:SetFrameLevel(plate.health:GetFrameLevel() + 3)
    plate.classFrame:Hide()
    plate.class = plate.classFrame:CreateTexture(nil, "ARTWORK")
    plate.class:SetAllPoints()
    plate.cast = CreateFrame("StatusBar", nil, plate)
    -- Cast bar is full health bar width; icon hangs outside to the left
    plate.cast:SetSize(GetHealthBarWidth(), CAST_H)
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", 0, 0)
    plate.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.cast:SetMinMaxValues(0, 1)
    plate.cast:Hide()
    plate.castBG = plate.cast:CreateTexture(nil, "BACKGROUND")
    plate.castBG:SetAllPoints()
    plate.castBG:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    plate.castLeftBorder = plate.cast:CreateTexture(nil, "OVERLAY", nil, 7)
    plate.castLeftBorder:SetColorTexture(0, 0, 0, 1)
    plate.castLeftBorder:SetWidth(1)
    plate.castLeftBorder:SetPoint("TOPLEFT", plate.cast, "TOPLEFT", 0, 0)
    plate.castLeftBorder:SetPoint("BOTTOMLEFT", plate.cast, "BOTTOMLEFT", 0, 0)
    -- Icon frame hangs outside the cast bar's left edge.
    -- Parented to cast (auto-hides with cast) and anchored to cast (same frame
    -- = single-pass layout resolve, no cross-frame jitter).
    plate.castIconFrame = CreateFrame("Frame", nil, plate.cast)
    plate.castIconFrame:SetSize(CAST_H, CAST_H)
    plate.castIconFrame:SetPoint("TOPRIGHT", plate.cast, "TOPLEFT", 0, 0)
    AddBorder(plate.castIconFrame)
    plate.castIcon = plate.castIconFrame:CreateTexture(nil, "ARTWORK")
    plate.castIcon:SetPoint("TOPLEFT", plate.castIconFrame, "TOPLEFT", 1, -1)
    plate.castIcon:SetPoint("BOTTOMRIGHT", plate.castIconFrame, "BOTTOMRIGHT", -1, 1)
    plate.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    plate.castSpark = plate.cast:CreateTexture(nil, "OVERLAY", nil, 1)
    plate.castSpark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
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
    -- Kick tick mark: clip frame + two invisible StatusBars + one visible tick texture
    -- interruptPositioner tracks cast elapsed; interruptMarker tracks kick cooldown remaining
    -- The tick texture sits at the right edge of interruptMarker's fill
    plate.kickClip = CreateFrame("Frame", nil, plate.cast)
    plate.kickClip:SetAllPoints(plate.cast)
    plate.kickClip:SetClipsChildren(true)
    plate.kickPositioner = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickPositioner:GetStatusBarTexture():SetAlpha(0)
    plate.kickPositioner:SetPoint("CENTER", plate.cast)
    plate.kickPositioner:SetFrameLevel(plate.cast:GetFrameLevel() + 1)
    plate.kickPositioner:Hide()
    plate.kickMarker = CreateFrame("StatusBar", nil, plate.kickClip)
    plate.kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    plate.kickMarker:GetStatusBarTexture():SetAlpha(0)
    plate.kickMarker:SetClipsChildren(true)
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
    plate.castName = plate.cast:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castName, 10, GetNPOutline())
    plate.castName:SetPoint("LEFT", plate.cast, "LEFT", 5, 0)
    plate.castName:SetJustifyH("LEFT")
    plate.castName:SetWordWrap(false)
    plate.castName:SetMaxLines(1)
    plate.castTarget = plate.cast:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.castTarget, 10, GetNPOutline())
    plate.castTarget:SetPoint("RIGHT", plate.cast, "RIGHT", -3, 0)
    plate.castTarget:SetJustifyH("RIGHT")
    plate.castTarget:SetWordWrap(false)
    plate.castTarget:SetMaxLines(1)
    plate.debuffs = {}
    for i = 1, 4 do
        local d = CreateFrame("Frame", nil, plate)
        d:SetFrameStrata("MEDIUM")
        d:SetFrameLevel(800)
        PP.Size(d, 26, 26)
        PP.Point(d, "BOTTOM", plate.name, "TOP", (i - 2.5) * 30, 2)
        AddBorder(d)
        d.icon = d:CreateTexture(nil, "ARTWORK")
        PP.Point(d.icon, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.icon, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
        PP.Point(d.cd, "TOPLEFT", d, "TOPLEFT", 1, -1)
        PP.Point(d.cd, "BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
        d.cd:SetFrameLevel(d:GetFrameLevel() + 2)
        if d.cd.SetDrawSwipe then d.cd:SetDrawSwipe(true) end
        if d.cd.SetDrawEdge then d.cd:SetDrawEdge(false) end
        if d.cd.SetDrawBling then d.cd:SetDrawBling(false) end
        if d.cd.SetReverse then d.cd:SetReverse(true) end
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(false) end
        d.count = d.cd:CreateFontString(nil, "OVERLAY")
        SetFSFont(d.count, 11, "OUTLINE")
        PP.Point(d.count, "BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.count:SetJustifyH("RIGHT")
        local cdRegions = { d.cd:GetRegions() }
        for _, region in ipairs(cdRegions) do
            if region:GetObjectType() == "FontString" then
                d.cd.text = region
                SetFSFont(region, 11, "OUTLINE")
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
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        PP.Point(b.cd, "TOPLEFT", b, "TOPLEFT", 1, -1)
        PP.Point(b.cd, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b.cd:SetFrameLevel(b:GetFrameLevel() + 2)
        if b.cd.SetDrawSwipe then b.cd:SetDrawSwipe(true) end
        if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
        if b.cd.SetDrawBling then b.cd:SetDrawBling(false) end
        if b.cd.SetReverse then b.cd:SetReverse(true) end
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
        b.count = b.cd:CreateFontString(nil, "OVERLAY")
        SetFSFont(b.count, 9, "OUTLINE")
        PP.Point(b.count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        local bCdRegions = { b.cd:GetRegions() }
        for _, region in ipairs(bCdRegions) do
            if region:GetObjectType() == "FontString" then
                b.cd.text = region
                SetFSFont(region, 12, "OUTLINE")
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
                SetFSFont(region, 12, "OUTLINE")
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
        if handler then
            handler(self, ...)
        end
    end)
end)
local function InitDB()
    if not EllesmereUINameplatesDB then
        EllesmereUINameplatesDB = {}
    end
    -- Migrate font path from old location to EllesmereUI/media
    if EllesmereUINameplatesDB.font == "Interface\\AddOns\\EllesmereUINameplates\\Expressway.TTF" then
        EllesmereUINameplatesDB.font = defaults.font
    end
    -- Migrate font path from old media root to fonts subfolder
    if EllesmereUINameplatesDB.font == "Interface\\AddOns\\EllesmereUI\\media\\Expressway.TTF" then
        EllesmereUINameplatesDB.font = defaults.font
    end
    -- Migrate auraSpacing from old raw pixel value (>=22) to new gap-only value
    if EllesmereUINameplatesDB.auraSpacing and EllesmereUINameplatesDB.auraSpacing >= 22 then
        EllesmereUINameplatesDB.auraSpacing = math.max(EllesmereUINameplatesDB.auraSpacing - 28, 0)
    end
    -- Migrate debuffIconW/H to single debuffIconSize (use the larger of the two)
    if EllesmereUINameplatesDB.debuffIconW or EllesmereUINameplatesDB.debuffIconH then
        local w = EllesmereUINameplatesDB.debuffIconW or 28
        local h = EllesmereUINameplatesDB.debuffIconH or 24
        EllesmereUINameplatesDB.debuffIconSize = math.max(w, h)
        EllesmereUINameplatesDB.debuffIconW = nil
        EllesmereUINameplatesDB.debuffIconH = nil
    end
    -- Migrate debuffTextPosition auraTextPosition (timer position now applies to all auras)
    if EllesmereUINameplatesDB.debuffTextPosition and not EllesmereUINameplatesDB.auraTextPosition then
        EllesmereUINameplatesDB.auraTextPosition = EllesmereUINameplatesDB.debuffTextPosition
    end
    -- Migrate unified auraTextPosition per-type timer positions
    if EllesmereUINameplatesDB.auraTextPosition and not EllesmereUINameplatesDB.debuffTimerPosition then
        local pos = EllesmereUINameplatesDB.auraTextPosition
        EllesmereUINameplatesDB.debuffTimerPosition = pos
        EllesmereUINameplatesDB.buffTimerPosition = pos
        EllesmereUINameplatesDB.ccTimerPosition = pos
    end
    -- Migrate old per-type text color unified auraDurationTextColor
    if not EllesmereUINameplatesDB.auraDurationTextColor then
        if EllesmereUINameplatesDB.debuffTimerColor then
            local c = EllesmereUINameplatesDB.debuffTimerColor
            EllesmereUINameplatesDB.auraDurationTextColor = { r = c.r, g = c.g, b = c.b }
        end
    end
    -- Migrate showHealthNumber toggle hpNumberPos dropdown
    if EllesmereUINameplatesDB.showHealthNumber ~= nil and not EllesmereUINameplatesDB.hpNumberPos then
        if EllesmereUINameplatesDB.showHealthNumber then
            EllesmereUINameplatesDB.hpNumberPos = "center"
        else
            EllesmereUINameplatesDB.hpNumberPos = "none"
        end
    end
    -- Migrate old text position keys new slot-based system
    if EllesmereUINameplatesDB.textSlotTop == nil
       and (EllesmereUINameplatesDB.enemyNamePos ~= nil
         or EllesmereUINameplatesDB.hpPercentPos ~= nil
         or EllesmereUINameplatesDB.hpNumberPos ~= nil) then
        local db = EllesmereUINameplatesDB
        db.textSlotTop = "none"
        db.textSlotRight = "none"
        db.textSlotLeft = "none"
        db.textSlotCenter = "none"
        local posToSlot = {
            top = "textSlotTop", right = "textSlotRight",
            left = "textSlotLeft", center = "textSlotCenter",
        }
        -- Enemy name first (highest priority)
        local namePos = db.enemyNamePos or defaults.enemyNamePos
        local nameSlot = posToSlot[namePos]
        if nameSlot then db[nameSlot] = "enemyName" end
        -- Health percent
        local pctPos = db.hpPercentPos or defaults.hpPercentPos
        if pctPos ~= "none" then
            local pctSlot = posToSlot[pctPos]
            if pctSlot and db[pctSlot] == "none" then
                db[pctSlot] = "healthPercent"
            end
        end
        -- Health number
        local numPos = db.hpNumberPos or defaults.hpNumberPos
        if numPos ~= "none" then
            local numSlot = posToSlot[numPos]
            if numSlot and db[numSlot] == "none" then
                db[numSlot] = "healthNumber"
            end
        end
        -- Clean up old keys
        db.enemyNamePos = nil
        db.hpPercentPos = nil
        db.hpNumberPos = nil
    end
    -- Migrate old global text colors per-slot colors
    if EllesmereUINameplatesDB.textSlotTopColor == nil then
        local db = EllesmereUINameplatesDB
        local oldNameC = db.enemyNameColor or defaults.enemyNameColor
        local oldHealthC = db.healthTextColor or defaults.healthTextColor
        for _, sk in ipairs(textSlotKeys) do
            local element = db[sk] or defaults[sk]
            if element == "enemyName" then
                db[sk .. "Color"] = { r = oldNameC.r, g = oldNameC.g, b = oldNameC.b }
            elseif element ~= "none" then
                db[sk .. "Color"] = { r = oldHealthC.r, g = oldHealthC.g, b = oldHealthC.b }
            end
        end
    end
    for k, v in pairs(defaults) do
        if EllesmereUINameplatesDB[k] == nil then
            if type(v) == "table" then
                EllesmereUINameplatesDB[k] = { r = v.r, g = v.g, b = v.b }
            else
                EllesmereUINameplatesDB[k] = v
            end
        end
    end
end
local kickSpellsByClass = {
    DEATHKNIGHT = {47528},
    WARRIOR = {6552},
    WARLOCK = {19647, 89766, 119910, 1276467, 132409},
    SHAMAN = {57994},
    ROGUE = {1766},
    PRIEST = {15487},
    PALADIN = {31935, 96231},
    MONK = {116705},
    MAGE = {2139},
    HUNTER = {187707, 147362},
    EVOKER = {351338},
    DRUID = {38675, 78675, 106839},
    DEMONHUNTER = {183752},
}
local activeKickSpell
local function RefreshKickAbility()
    local playerClass = UnitClassBase("player")
    local classKicks = kickSpellsByClass[playerClass]
    activeKickSpell = nil
    if not classKicks then return end
    for i = 1, #classKicks do
        local spellId = classKicks[i]
        if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
            local known = C_SpellBook.IsSpellKnownOrInSpellBook(spellId)
            local petKnown = Enum and Enum.SpellBookSpellBank and C_SpellBook.IsSpellKnownOrInSpellBook(spellId, Enum.SpellBookSpellBank.Pet)
            if known or petKnown then activeKickSpell = spellId end
        elseif IsSpellKnown and IsSpellKnown(spellId) then
            activeKickSpell = spellId
        end
    end
end
local function ComputeCastBarTint(readyTint, baseTint)
    if not activeKickSpell then return baseTint.r, baseTint.g, baseTint.b end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return baseTint.r, baseTint.g, baseTint.b end
    if not (C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) then return baseTint.r, baseTint.g, baseTint.b end
    local cdTime = C_Spell.GetSpellCooldownDuration(activeKickSpell)
    if not (cdTime and cdTime.IsZero) then return baseTint.r, baseTint.g, baseTint.b end
    local offCooldown = cdTime:IsZero()
    local rVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.r, readyTint.r)
    local gVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.g, readyTint.g)
    local bVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.b, readyTint.b)
    return rVal, gVal, bVal
end
function ns.RefreshBorderStyle()
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorderStyle then
            plate:ApplyBorderStyle()
        end
    end
end
function ns.RefreshBorderColor()
    for _, plate in pairs(ns.plates) do
        if plate.ApplyBorderColor then
            plate:ApplyBorderColor()
        end
    end
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
    if not SetCVar then return end
    local db = EllesmereUINameplatesDB or defaults
    local enabled = (db.stackingEnabled ~= false)
    SetCVar("nameplateMotion", enabled and 1 or 0)
end

--- Full visual refresh for all plates called when an entire preset is applied.
--- Re-runs SetUnit on each active plate, which re-reads all DB values and applies
--- them.  Only runs on deliberate preset switch (not per-frame or per-event).
function ns.RefreshAllSettings()
    for _, plate in pairs(ns.plates) do
        if plate.unit and plate.nameplate then
            plate:SetUnit(plate.unit, plate.nameplate)
        end
    end
    if ns.ApplyClassPowerSetting then ns.ApplyClassPowerSetting() end
end
local kickWatcher = CreateFrame("Frame")
kickWatcher:RegisterEvent("PLAYER_LOGIN")
kickWatcher:RegisterEvent("SPELLS_CHANGED")
local activeCastCount = 0
kickWatcher:SetScript("OnEvent", function(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        for _, plate in pairs(ns.plates) do
            if plate.isCasting and plate.unit then
                local kickProtected
                local isChannel = false
                local sName, _, _, _, _, _, _, kp = UnitCastingInfo(plate.unit)
                if type(sName) ~= "nil" then
                    kickProtected = kp
                else
                    _, _, _, _, _, _, kp = UnitChannelInfo(plate.unit)
                    kickProtected = kp
                    isChannel = true
                end
                if type(kickProtected) == "nil" then kickProtected = false end
                plate._kickProtected = kickProtected
                plate:ApplyCastColor(kickProtected)
                -- Re-snapshot kick tick position when kick CD state changes mid-cast
                plate:UpdateKickTick(kickProtected, isChannel)
            end
        end
    else
        -- Migrate old overlay texture names to v2 (once, at login)
        if event == "PLAYER_LOGIN" and EllesmereUINameplatesDB then
            local old = EllesmereUINameplatesDB.focusOverlayTexture
            if old == "striped" then EllesmereUINameplatesDB.focusOverlayTexture = "striped-v2"
            elseif old == "striped-wide" then EllesmereUINameplatesDB.focusOverlayTexture = "striped-wide-v2"
            end
            local presets = EllesmereUINameplatesDB._color_presets
            if presets then
                for _, preset in pairs(presets) do
                    local pt = preset.focusOverlayTexture
                    if pt == "striped" then preset.focusOverlayTexture = "striped-v2"
                    elseif pt == "striped-wide" then preset.focusOverlayTexture = "striped-wide-v2"
                    end
                end
            end
        end
        -- Blizzard options panel is registered centrally in EllesmereUI.lua
        RefreshKickAbility()
    end
end)
local _castColorTicker
local function NotifyCastStarted()
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        -- Poll cast bar color at 5fps while any cast is active.
        -- SPELL_UPDATE_COOLDOWN/USABLE don't reliably fire when a CD naturally
        -- expires, so we need this lightweight poll fallback.
        -- Only runs while casts are visible.
        if activeKickSpell and not _castColorTicker then
            _castColorTicker = C_Timer.NewTicker(0.2, function()
                for _, plate in pairs(ns.plates) do
                    if plate.isCasting and plate.unit and plate._kickProtected ~= nil then
                        plate:ApplyCastColor(plate._kickProtected)
                    end
                end
            end)
        end
    end
end
local function NotifyCastEnded()
    activeCastCount = activeCastCount - 1
    if activeCastCount <= 0 then
        activeCastCount = 0
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _castColorTicker then
            _castColorTicker:Cancel()
            _castColorTicker = nil
        end
    end
end
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
        local db = EllesmereUINameplatesDB or defaults
        local nameOnly = (db.friendlyNameOnly ~= false)
        local showPlayers = (db.showFriendlyPlayers ~= false)
        local showNPCs = (db.showFriendlyNPCs == true)
        local showDefaultNames = (db.friendlyShowDefaultNames == true)
        SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0)
        SetCVar("nameplateShowFriendlyPlayers", showPlayers and 1 or 0)
        SetCVar("nameplateShowFriendlyPlayerUnits", showPlayers and 1 or 0)
        SetCVar("UnitNameFriendlyPlayerName", (showPlayers or showDefaultNames) and 1 or 0)
        SetCVar("nameplateShowFriends", showPlayers and 1 or 0)
        SetCVar("nameplateShowFriendlyNPCs", showNPCs and 1 or 0)
        SetCVar("nameplateShowFriendlyNpcs", showNPCs and 1 or 0)
        SetCVar("nameplateShowEnemyPets", (db.showEnemyPets == true) and 1 or 0)
        SetCVar("ShowClassColorInFriendlyNameplate", (db.classColorFriendly ~= false) and 1 or 0)
        SetCVar("ShowClassColorInNameplate", 1)
        SetCVar("nameplateSize", 3)
        SetCVar("nameplateShowAll", 1)
        SetCVar("nameplatePlayerLargerScale", 1)
        SetCVar("nameplateLargerScale", 1)
        SetCVar("nameplateTargetRadialPosition", 1)
        SetCVar("nameplateMinScale", 1)
        SetCVar("nameplateOverlapH", 1)
        SetCVar("nameplateOverlapV", EllesmereUINameplatesDB and EllesmereUINameplatesDB.nameplateOverlapV or defaults.nameplateOverlapV)
        SetCVar("nameplateMotion", (db.stackingEnabled ~= false) and 1 or 0)
        SetCVar("nameplateGlobalScale", 1)
        SetCVar("NamePlateHorizontalScale", 1)
        SetCVar("NamePlateVerticalScale", 1)
        SetCVar("nameplateLargeBottomInset", 0.15)
        SetCVar("nameplateMaxAlpha", 1)
        SetCVar("nameplateMaxAlphaDistance", 40)
        SetCVar("nameplateMinAlpha", 0.6)
        SetCVar("nameplateMinAlphaDistance", -100000)
        SetCVar("nameplateMaxDistance", 60)
        SetCVar("nameplateMaxScale", 1)
        SetCVar("nameplateMotionSpeed", 0.025)
        SetCVar("nameplateTargetBehindMaxDistance", 30)
        SetCVar("clampTargetNameplateToScreen", 1)
        SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", (db.classColorFriendly ~= false) and 1 or 0)
    end
    local function ApplyNamePlateClickArea()
        if InCombatLockdown() then return end
        if C_NamePlate and C_NamePlate.SetNamePlateSize then
            -- Size the nameplate to the health bar only so the click/target
            -- region matches the bar exactly. Stacking uses a separate
            -- SetStackingBoundsFrame that covers the full visual footprint
            -- (name + health + cast), so this won't cause jitter.
            C_NamePlate.SetNamePlateSize(GetHealthBarWidth(), GetHealthBarHeight())
        end
        -- On Midnight the default hit-test region can be smaller than the
        -- nameplate frame. Expand it with large negative insets so the
        -- entire frame area (which we just sized to the health bar) is
        -- clickable.
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

-- Per-class filled pip colors (official WoW class colors)
local CP_CLASS_COLORS = {
    ROGUE       = { 1.00, 0.96, 0.41 },
    DRUID       = { 1.00, 0.49, 0.04 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    MONK        = { 0.00, 1.00, 0.60 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    MAGE        = { 0.25, 0.78, 0.92 },
    EVOKER      = { 0.20, 0.58, 0.50 },
    DEMONHUNTER = { 0.34, 0.06, 0.46 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    WARRIOR     = { 0.78, 0.61, 0.43 },
}
local CP_DEFAULT_COLOR = { 1.00, 0.84, 0.30 }  -- fallback gold

-- Map class { powerType, maxPips (fallback) }
-- Entries can be a simple table { type, max } or a spec-keyed table { [specID] = { type, max } }
local CLASS_POWER_MAP = {
    ROGUE       = { Enum.PowerType.ComboPoints, 5 },
    DRUID       = { Enum.PowerType.ComboPoints, 5 },
    PALADIN     = { Enum.PowerType.HolyPower,   5 },
    MONK        = { [268] = { "BREWMASTER_STAGGER", 1 },
                    [269] = { Enum.PowerType.Chi, 5 } },
    WARLOCK     = { Enum.PowerType.SoulShards,   5 },
    MAGE        = { Enum.PowerType.ArcaneCharges, 4 },
    EVOKER      = { Enum.PowerType.Essence,      5 },
    DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 } },  -- Vengeance only (secret value)
    SHAMAN      = { [263] = { "MAELSTROM_WEAPON", 10 } },  -- Enhancement only
    PRIEST      = { [258] = { "INSANITY_BAR", 100 } },     -- Shadow only
    HUNTER      = { [253] = { "FOCUS_BAR", 100 },
                    [254] = { "FOCUS_BAR", 100 },
                    [255] = { "TIP_OF_THE_SPEAR", 3 } },   -- Survival only
    WARRIOR     = { [72]  = { "WHIRLWIND_STACKS", 4 } },    -- Fury only
}

-- Lazy-create pip textures on a plate (done once, then reused via show/hide)
local function EnsureClassPowerPips(plate)
    if plate._cpPips then return end
    plate._cpPips = {}
    local maxPossible = 10  -- safe upper bound (Maelstrom Weapon = 10)
    for i = 1, maxPossible do
        local bg = plate:CreateTexture(nil, "OVERLAY", nil, 2)
        bg:SetColorTexture(0.082, 0.082, 0.082, 1)
        bg:Hide()
        local pip = plate:CreateTexture(nil, "OVERLAY", nil, 3)
        pip:SetColorTexture(1, 1, 1, 1)
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
    if not classPowerType then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
        end
        if plate._cpBar then plate._cpBar:Hide() end
        return
    end

    local cpScale = GetClassPowerScale()
    local cpYOff = GetClassPowerYOffset()
    local cpXOff = GetClassPowerXOffset()
    local cpPos = GetClassPowerPos()
    local bgCol = GetClassPowerBgColor()

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
            local _, pClass = UnitClass("player")
            local cpColor = CP_CLASS_COLORS[pClass] or CP_DEFAULT_COLOR
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

        local _, pClass = UnitClass("player")
        local cpColor = CP_CLASS_COLORS[pClass] or CP_DEFAULT_COLOR
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

        local _, pClass = UnitClass("player")
        local cpColor = CP_CLASS_COLORS[pClass] or CP_DEFAULT_COLOR
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
    else
        cur = UnitPower("player", classPowerType) or 0
        maxP = UnitPowerMax("player", classPowerType) or classPowerMax
        if maxP <= 0 then maxP = classPowerMax end
    end
    if maxP <= 0 then
        for i = 1, #plate._cpPips do
            plate._cpPips[i]:Hide()
            if plate._cpPips[i]._bg then plate._cpPips[i]._bg:Hide() end
        end
        return
    end

    local scaledW = PP.Scale(CP_PIP_W * cpScale)
    local scaledH = PP.Scale(CP_PIP_H * cpScale)
    local scaledGap = PP.Scale(GetClassPowerGap() * cpScale)
    -- Pre-compute each pip's left-edge X in group-local coords.
    -- Position by BOTTOMLEFT/TOPLEFT to avoid half-pixel center offsets.
    local pipPositions = {}
    for idx = 1, maxP do
        pipPositions[idx] = PP.Scale((idx - 1) * (scaledW + scaledGap))
    end
    local groupW = pipPositions[maxP] + scaledW
    local halfGroup = PP.Scale(groupW / 2)

    local _, pClass = UnitClass("player")
    local cpColor = CP_DEFAULT_COLOR
    if GetClassPowerClassColors() then
        cpColor = CP_CLASS_COLORS[pClass] or CP_DEFAULT_COLOR
    else
        local cc = GetClassPowerCustomColor()
        cpColor = { cc.r, cc.g, cc.b }
    end

    local emptyCol = GetClassPowerEmptyColor()

    local leftAnchor = (anchorPoint == "BOTTOM") and "BOTTOMLEFT" or "TOPLEFT"

    for i = 1, #plate._cpPips do
        local pip = plate._cpPips[i]
        if i <= maxP then
            pip:ClearAllPoints()
            PP.Size(pip, scaledW, scaledH)
            local pipLeftX = PP.Scale(pipPositions[i] - halfGroup + cpXOff)
            pip:SetPoint(leftAnchor, anchorFrame, anchorRelPoint,
                pipLeftX, PP.Scale(yDir * cpYOff))

            -- Background texture behind each pip
            local bg = pip._bg
            if bg then
                bg:ClearAllPoints()
                bg:SetAllPoints(pip)
                bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                bg:Show()
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
                pip:SetColorTexture(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                pip:Show()
            else
                if pip._secretBar then pip._secretBar:Hide() end
                if i <= cur then
                    pip:SetColorTexture(cpColor[1], cpColor[2], cpColor[3], 1)
                else
                    pip:SetColorTexture(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                end
                pip:Show()
            end
        else
            pip:Hide()
            if pip._bg then pip._bg:Hide() end
            if pip._secretBar then pip._secretBar:Hide() end
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
    end
    if plate._cpBar then plate._cpBar:Hide() end
end

-- Return the extra Y offset that elements above the health bar need to clear
-- the class power pips (when pips are on top and visible on this plate).
GetClassPowerTopPush = function(plate)
    if not GetShowClassPower() or not classPowerType then return 0 end
    if GetClassPowerPos() ~= "top" then return 0 end
    if not plate or not plate.unit or not UnitIsUnit(plate.unit, "target") then return 0 end
    local cpScale = GetClassPowerScale()
    local cpYOff = GetClassPowerYOffset()
    return CP_PIP_H * cpScale + cpYOff
end

-- Find the target plate and update pips
local function RefreshClassPower()
    -- Form check (e.g. Druid combo points only in cat form)
    if classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq then
        for _, plate in pairs(ns.plates) do
            HideClassPowerOnPlate(plate)
        end
        return
    end
    local plates = ns.plates
    for _, plate in pairs(plates) do
        if plate.unit and UnitIsUnit(plate.unit, "target") then
            EnsureClassPowerPips(plate)
            UpdateClassPowerOnPlate(plate)
        else
            HideClassPowerOnPlate(plate)
        end
    end
end

-- Full refresh including repositioning of elements above the health bar.
-- Called on target change and settings change (not on every power tick).
local function RefreshClassPowerFull()
    -- Form check (e.g. Druid combo points only in cat form)
    local formHidden = classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq
    local plates = ns.plates
    for _, plate in pairs(plates) do
        if not formHidden and plate.unit and UnitIsUnit(plate.unit, "target") then
            EnsureClassPowerPips(plate)
            UpdateClassPowerOnPlate(plate)
        else
            HideClassPowerOnPlate(plate)
        end
        -- Reposition elements above the health bar so they clear (or un-clear) the pips
        if plate.unit then
            plate:RefreshNamePosition()
            plate:UpdateRaidIcon()
        end
    end
end

-- Forward declarations for mutual recursion on spec change
local DisableClassPowerWatcher
local ApplyClassPowerSetting

-- Enable/disable the class power watcher
local function EnableClassPowerWatcher()
    if classPowerWatcher then return end  -- already active
    local _, playerClass = UnitClass("player")
    local info = CLASS_POWER_MAP[playerClass]
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
    classPowerFormReq = (playerClass == "DRUID") and 1 or nil  -- Druid: cat form only
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
                end
                RefreshClassPower()
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not _G._ERB_AceDB and EllesmereUI and EllesmereUI.HandleWhirlwindStacks then
                    EllesmereUI.HandleWhirlwindStacks(event)
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
        classPowerWatcher:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
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
    -- Hide all pips on all plates and reposition elements that were pushed
    for _, plate in pairs(ns.plates) do
        HideClassPowerOnPlate(plate)
        if plate.unit then
            plate:RefreshNamePosition()
            plate:UpdateRaidIcon()
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
-- Cached threat-context state — updated at zone transitions and spec changes
local _inThreatContent = false
local _isTankRole      = false

local function RefreshThreatCache()
    -- Zone: party/raid instances and delves (difficultyID 204) are threat-relevant
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    if difficultyID == 0
    or (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap()) then
        _inThreatContent = false
    else
        _inThreatContent = (instanceType == "party" or instanceType == "raid"
                            or difficultyID == 204)  -- delve difficulty
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
    -- Skip inside instances quest mobs are open-world only
    if InRealInstancedContent() then
        questMobCache[unit] = false
        return false
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
                return true
            end
        end
    end
    questMobCache[unit] = false
    return false
end
ns.IsQuestMob = IsQuestMob

-- Invalidate quest cache on quest log changes
local questCacheWatcher = CreateFrame("Frame")
questCacheWatcher:RegisterEvent("QUEST_LOG_UPDATE")
questCacheWatcher:SetScript("OnEvent", function()
    wipe(questMobCache)
    -- Refresh colors on all visible plates
    for _, plate in pairs(ns.plates) do
        plate:UpdateHealthColor()
    end
end)

local function GetReactionColor(unit)
    local db = EllesmereUINameplatesDB or defaults
    local function C(key)
        return db[key] or defaults[key]
    end
    -- 1. Tapped always highest
    if UnitIsTapDenied(unit) then
        local c = C("tapped")
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
                    local c = C("dpsHasAggro")
                    return c.r, c.g, c.b
                elseif status >= 2 then
                    local c = C("dpsNearAggro")
                    return c.r, c.g, c.b
                end
                end
            else
                -- Tank: losing aggro / no aggro absolute priority
                if status < 3 and status >= 2 then
                    local c = C("tankLosingAggro")
                    return c.r, c.g, c.b
                elseif status < 3 then
                    -- Only show no-aggro warning if a non-tank has it.
                    -- If another tank holds aggro, this is normal offtank positioning.
                    local unitTarget = unit .. "target"
                    local targetRole = UnitExists(unitTarget) and UnitGroupRolesAssigned(unitTarget) or "NONE"
                    if targetRole ~= "TANK" then
                        local c = C("tankNoAggro")
                        return c.r, c.g, c.b
                    end
                    -- Another tank has aggro -- fall through, no warning color
                end
                -- Tank has aggro falls through to be handled below focus/caster/miniboss
            end
        end
    end
    -- 4. Focus color (if enabled)
    local focusC = C("focus")
    if focusC and UnitIsUnit(unit, "focus") then
        local enabled = defaults.focusColorEnabled
        if db.focusColorEnabled ~= nil then enabled = db.focusColorEnabled end
        if enabled then
            return focusC.r, focusC.g, focusC.b
        end
    end
    -- 5. Neutral
    local reaction = UnitReaction(unit, "player")
    if reaction and reaction == 4 then
        local c = C("neutral")
        return c.r, c.g, c.b
    end
    if UnitCanAttack("player", unit) and not UnitIsEnemy(unit, "player") then
        local c = C("neutral")
        return c.r, c.g, c.b
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unit) and UnitCanAttack("player", unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- 7. Miniboss
    local inCombat = UnitAffectingCombat(unit)
    local classification = UnitClassification(unit)
    if classification == "elite" or classification == "worldboss" or classification == "rareelite" then
        local level = UnitLevel(unit)
        local playerLevel = UnitLevel("player")
        if level == -1 or (playerLevel and level >= playerLevel + 1) then
            local c = C("miniboss")
            if type(inCombat) == "boolean" and inCombat then
                return c.r, c.g, c.b
            else
                return DarkenColor(c.r, c.g, c.b)
            end
        end
    end
    -- 8. Caster
    local unitClass = UnitClassBase and UnitClassBase(unit)
    if unitClass == "PALADIN" then
        local c = C("caster")
        if type(inCombat) == "boolean" and inCombat then
            return c.r, c.g, c.b
        else
            return DarkenColor(c.r, c.g, c.b)
        end
    end
    -- 9. Tank has aggro (if enabled) below focus/caster/miniboss
    if isThreatUnit and _isTankRole and threatStatus >= 3 then
        local enabled = defaults.tankHasAggroEnabled
        if db.tankHasAggroEnabled ~= nil then enabled = db.tankHasAggroEnabled end
        if enabled then
            local c = C("tankHasAggro")
            return c.r, c.g, c.b
        end
    end
    -- 10. Fallback: enemy in combat / out of combat
    local eic = C("enemyInCombat")
    if type(inCombat) == "boolean" and inCombat then
        return eic.r, eic.g, eic.b
    end
    return DarkenColor(eic.r, eic.g, eic.b)
end
local hookedUFs = {}
local hookedHighlights = {}
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
    if unit and UnitCanAttack("player", unit) then
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
    end
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            locked = true
            local ufUnit = self.unit or (self.GetUnit and self:GetUnit())
            if ufUnit and UnitExists(ufUnit) and UnitCanAttack("player", ufUnit) then
                self:SetAlpha(0)
            end
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
castFallbackFrame:SetScript("OnUpdate", function()
    for _, plate in pairs(ns.plates) do
        if plate._castFallback and plate.isCasting and plate.unit and plate.nameplate then
            local bc = plate.nameplate.UnitFrame and plate.nameplate.UnitFrame.castBar
            if bc and bc:IsShown() then
                plate.cast:SetMinMaxValues(bc:GetMinMaxValues())
                plate.cast:SetValue(bc:GetValue())
            else
                if not plate._interrupted then
                    plate.cast:Hide()
                end
                plate.isCasting = false
                plate._castFallback = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then
                    fallbackCastCount = 0
                    castFallbackFrame:Hide()
                end
                NotifyCastEnded()
            end
        end
    end
end)
castFallbackFrame:Hide()

-- Pandemic glow alpha-only tick: only iterates slots with active pandemic glows
local pandemicTickFrame = CreateFrame("Frame")
local pandemicTickAccum = 0
pandemicTickFrame:SetScript("OnUpdate", function(_, elapsed)
    pandemicTickAccum = pandemicTickAccum + elapsed
    if pandemicTickAccum < 0.2 then return end
    pandemicTickAccum = 0
    if not GetPandemicGlow() then return end
    for slot in pairs(ns.activePandemicSlots) do
        local durObj = slot._durationObj
        if durObj and slot.pandemicGlow and slot.pandemicGlow.active then
            slot.pandemicGlow.wrapper:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(durObj:IsZero(), 0, durObj:EvaluateRemainingPercent(ns.pandemicCurve)))
        else
            ns.StopPandemicGlow(slot)
        end
    end
end)

local NameplateFrame = {}
function NameplateFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    -- Single center anchor: the entire plate moves as one unit when the
    -- nameplate bounces by 1px, preventing individual edges from rounding
    -- independently (the "pixel shimmer" / bouncing-sides issue).
    self:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    self:SetSize(1, 1)
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()
    -- Stacking bounds: tell WoW to use our visual footprint for stacking,
    -- not the Blizzard UnitFrame's layout bounds (which include AurasFrame).
    -- Height covers name text above + health bar + cast bar below.
    if nameplate.SetStackingBoundsFrame then
        if not self._stackBounds then
            self._stackBounds = CreateFrame("Frame", nil, nameplate)
            -- WoW needs renderable content to measure frame bounds
            local tex = self._stackBounds:CreateTexture(nil, "BACKGROUND")
            tex:SetColorTexture(1, 0, 0, 0)
            tex:SetAllPoints(self._stackBounds)
        end
        self._stackBounds:SetParent(nameplate)
        self._stackBounds:ClearAllPoints()
        local barH = GetHealthBarHeight()
        local castH2 = GetCastBarHeight()
        local nameGap = 4 + GetEnemyNameTextSize()
        local totalH = nameGap + barH + castH2
        local scale = GetStackSpacingScale() / 100
        -- Anchor directly to nameplate to avoid any influence from our
        -- plate frame's scale changes (ApplyCastScale).
        self._stackBounds:SetPoint("CENTER", nameplate, "CENTER", 0, GetNameplateYOffset())
        self._stackBounds:SetSize(GetHealthBarWidth(), totalH * scale)
        self._stackBounds:Show()
        nameplate:SetStackingBoundsFrame(self._stackBounds)
    end
    local castH = GetCastBarHeight()
    -- Focus cast height multiplier
    if unit and UnitIsUnit(unit, "focus") then
        local pct = GetFocusCastHeight()
        if pct ~= 100 then
            castH = math.floor(castH * pct / 100 + 0.5)
        end
    end
    local gap = GetAuraSpacing()
    local debuffY = GetDebuffYOffset()
    self.health:ClearAllPoints()
    self.health:SetPoint("CENTER", self, "CENTER", 0, GetNameplateYOffset())
    self.health:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.absorb:SetSize(GetHealthBarWidth(), GetHealthBarHeight())
    self.cast:SetSize(GetHealthBarWidth(), castH)
    self.cast:ClearAllPoints()
    self.cast:SetPoint("TOPLEFT", self.health, "BOTTOMLEFT", 0, 0)
    self.castIconFrame:SetSize(castH, castH)
    self.castIconFrame:ClearAllPoints()
    self.castIconFrame:SetPoint("TOPRIGHT", self.cast, "TOPLEFT", 0, 0)
    -- Apply cast icon visibility and scale
    local showIcon = GetShowCastIcon()
    if showIcon then
        local iconScale = GetCastIconScale()
        self.castIconFrame:SetScale(iconScale)
        self.castIconFrame:Show()
    else
        self.castIconFrame:Hide()
    end
    self.castLeftBorder:SetWidth(1)
    self.castSpark:SetHeight(castH)
    -- Kick tick marker sizing
    self.kickMarker:SetSize(GetHealthBarWidth(), castH)
    -- Enemy name color (per-slot)
    local db = EllesmereUINameplatesDB
    local nameSlotKey = FindSlotForElement("enemyName")
    if nameSlotKey then
        local nr, ng, nb = GetTextSlotColor(nameSlotKey)
        self.name:SetTextColor(nr, ng, nb, 1)
    end
    -- Name position (top = above bar, left/center/right = inside bar)
    self:RefreshNamePosition()
    -- Cast text sizes and colors
    local cns = (db and db.castNameSize) or defaults.castNameSize
    local cts = (db and db.castTargetSize) or defaults.castTargetSize
    local cnc = (db and db.castNameColor) or defaults.castNameColor
    SetFSFont(self.castName, cns, GetNPOutline())
    SetFSFont(self.castTarget, cts, GetNPOutline())
    self.castName:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
    -- Cast target color: class-colored if enabled and target is a player, otherwise use castTargetColor
    local useClassColor = defaults.castTargetClassColor
    if db and db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end
    if useClassColor then
        local appliedCTC = false
        if self.unit then
            local classToken
            if UnitSpellTargetClass then
                classToken = UnitSpellTargetClass(self.unit)
            end
            if not classToken then
                local targetUnit = self.unit .. "target"
                if UnitIsPlayer(targetUnit) then
                    classToken = UnitClassBase(targetUnit)
                end
            end
            if classToken and C_ClassColor then
                local c = C_ClassColor.GetClassColor(classToken)
                if c then
                    self.castTarget:SetTextColor(c:GetRGB())
                    appliedCTC = true
                end
            end
        end
        if not appliedCTC then
            self.castTarget:SetTextColor(1, 1, 1, 1)
        end
    else
        local ctc = (db and db.castTargetColor) or defaults.castTargetColor
        self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
    end
    -- Aura duration text settings (unified across debuffs, buffs, CCs)
    local auraDurSize = (db and db.auraDurationTextSize) or defaults.auraDurationTextSize
    local auraDurColor = (db and db.auraDurationTextColor) or defaults.auraDurationTextColor
    local auraStackSize = (db and db.auraStackTextSize) or defaults.auraStackTextSize
    local auraStackColor = (db and db.auraStackTextColor) or defaults.auraStackTextColor
    -- Aura timer positions (per-type: debuffs, buffs, CCs with "none" to hide)
    local debuffTPos = (db and db.debuffTimerPosition) or (db and db.auraTextPosition) or defaults.debuffTimerPosition
    local buffTPos   = (db and db.buffTimerPosition)   or (db and db.auraTextPosition) or defaults.buffTimerPosition
    local ccTPos     = (db and db.ccTimerPosition)     or (db and db.auraTextPosition) or defaults.ccTimerPosition

    -- Helper: apply timer position to a duration text fontstring
    -- For "none", uses SetHideCountdownNumbers(true) to tell the Blizzard cooldown
    -- system to suppress the text entirely, which is more reliable than hiding the
    -- FontString directly (Blizzard re-shows it) or zeroing alpha/font size (gets
    -- overridden by the cooldown system).
    local function ApplyTimerPosition(durText, auraFrame, pos)
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
        SetFSFont(durText, auraDurSize, "OUTLINE")
        durText:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
        durText:ClearAllPoints()
        if pos == "center" then
            durText:SetPoint("CENTER", auraFrame, "CENTER", 0, 0)
            durText:SetJustifyH("CENTER")
        elseif pos == "topright" then
            PP.Point(durText, "TOPRIGHT", auraFrame, "TOPRIGHT", 3, 4)
            durText:SetJustifyH("RIGHT")
        else -- topleft (default)
            PP.Point(durText, "TOPLEFT", auraFrame, "TOPLEFT", -3, 4)
            durText:SetJustifyH("LEFT")
        end
    end

    -- Debuff duration text + position + stack count styling
    for i = 1, 4 do
        if self.debuffs[i] and self.debuffs[i].cd and self.debuffs[i].cd.text then
            SetFSFont(self.debuffs[i].cd.text, auraDurSize, "OUTLINE")
            self.debuffs[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.debuffs[i].cd.text, self.debuffs[i], debuffTPos)
        end
        if self.debuffs[i] and self.debuffs[i].count then
            SetFSFont(self.debuffs[i].count, auraStackSize, "OUTLINE")
            self.debuffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
        end
    end
    -- Icon sizes from DB
    local debuffSz = GetDebuffIconSize()
    local buffSz = GetBuffIconSize()
    local ccSz = GetCCIconSize()
    local debuffSlot, buffSlot, ccSlot = GetAuraSlots()
    -- Debuff icon sizes (positions handled in UpdateAuras via PositionAuraSlot)
    for i = 1, 4 do
        PP.Size(self.debuffs[i], debuffSz, debuffSz)
    end
    -- Buff spacing + size + duration/stack text styling + timer position
    for i = 1, 4 do
        PP.Size(self.buffs[i], buffSz, buffSz)
        if self.buffs[i].cd and self.buffs[i].cd.text then
            SetFSFont(self.buffs[i].cd.text, auraDurSize, "OUTLINE")
            self.buffs[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.buffs[i].cd.text, self.buffs[i], buffTPos)
        end
        if self.buffs[i].count then
            SetFSFont(self.buffs[i].count, auraStackSize, "OUTLINE")
            self.buffs[i].count:SetTextColor(auraStackColor.r, auraStackColor.g, auraStackColor.b, 1)
        end
    end
    PositionAuraSlot(self.buffs, 4, buffSlot, self, buffSz, buffSz, gap, GetAuraSlotOffsets("buffSlot"))
    -- CC spacing + size + duration/stack text styling + timer position
    for i = 1, 2 do
        PP.Size(self.cc[i], ccSz, ccSz)
        if self.cc[i].cd and self.cc[i].cd.text then
            SetFSFont(self.cc[i].cd.text, auraDurSize, "OUTLINE")
            self.cc[i].cd.text:SetTextColor(auraDurColor.r, auraDurColor.g, auraDurColor.b, 1)
            ApplyTimerPosition(self.cc[i].cd.text, self.cc[i], ccTPos)
        end
    end
    PositionAuraSlot(self.cc, 2, ccSlot, self, ccSz, ccSz, gap, GetAuraSlotOffsets("ccSlot"))
if self.absorbOverflow then
    self.absorbOverflow:SetHeight(GetHealthBarHeight())
end
    HideBlizzardFrame(nameplate, unit)
    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_AURA", unit)
    self:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", unit)
    self:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", unit)
    self:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_FLAGS", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unit)
    self:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unit)
    self:UpdateHealth()
    self:UpdateName()
    self:UpdateClassification()
    self:UpdateRaidIcon()
    self:ApplyTarget()
    self:ApplyMouseover()
    self:UpdateAuras()
    self:UpdateCast()
    ApplyHealthBarTexture(self)
end
function NameplateFrame:ClearUnit()
    self:UnregisterAllEvents()
    
    if self.isCasting then
        self.isCasting = false
        if self._castFallback then
            self._castFallback = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded()
    end
    
    self.name:SetText("")
    for i = 1, 2 do
        local slot = self.cc[i]
        if slot.cd then
            if slot.cd.SetDrawSwipe then slot.cd:SetDrawSwipe(false) end
            if slot.cd.Clear then
                slot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(slot.cd)
            else
                slot.cd:SetCooldown(0, 0)
            end
        end
        slot.icon:SetTexture(nil)
        slot:Hide()
    end
    for i = 1, 4 do
        local dSlot = self.debuffs[i]
        if dSlot.cd then
            if dSlot.cd.SetDrawSwipe then dSlot.cd:SetDrawSwipe(false) end
            if dSlot.cd.Clear then
                dSlot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(dSlot.cd)
            else
                dSlot.cd:SetCooldown(0, 0)
            end
        end
        dSlot.icon:SetTexture(nil)
        dSlot:Hide()
        ns.StopPandemicGlow(dSlot)
        dSlot._durationObj = nil
        local bSlot = self.buffs[i]
        if bSlot.cd then
            if bSlot.cd.SetDrawSwipe then bSlot.cd:SetDrawSwipe(false) end
            if bSlot.cd.Clear then
                bSlot.cd:Clear()
            elseif CooldownFrame_Clear then
                CooldownFrame_Clear(bSlot.cd)
            else
                bSlot.cd:SetCooldown(0, 0)
            end
        end
        bSlot.icon:SetTexture(nil)
        bSlot:Hide()
    end
    self.unit = nil
    self.nameplate = nil
    self._shownAuras = nil
    self.cast:Hide()
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.isCasting = false
    self._castFallback = nil
    self._kickProtected = nil
    self:HideKickTick()
    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end
    self._interrupted = nil
    self.glow:Hide()
    self.highlight:Hide()
    self.raidFrame:Hide()
    self.classFrame:Hide()
    self.leftArrow:Hide()
    self.rightArrow:Hide()
    HideClassPowerOnPlate(self)
    self.absorb:Hide()
    if self.absorbOverflow then
    self.absorbOverflow:Hide()
    self.absorbOverflow:SetWidth(0)
end
if self.absorbOverflowDivider then
    self.absorbOverflowDivider:Hide()
end
    self:Hide()
    self:SetScale(1)
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
            self.unit = actualUnit
            unit = actualUnit
            self:UpdateName()
        end
    end
    if false and self.hpCalculator and self.hpCalculator.GetMaximumHealth then
        -- NOTE: Disabled because hpCalculator methods now return secret/protected values
        -- on the beta, which cannot be passed to StatusBar:SetValue().
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
        local maxWithAbsorbs = self.hpCalculator:GetMaximumHealth()
        self.health:SetMinMaxValues(0, maxWithAbsorbs)
        self.absorb:SetMinMaxValues(0, maxWithAbsorbs)
        self.absorb:SetValue(self.hpCalculator:GetDamageAbsorbs())
        self.absorb:Show()
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        self.health:SetValue(self.hpCalculator:GetCurrentHealth())
    else
        local maxHealth = UnitHealthMax(unit)
        self.health:SetMinMaxValues(0, maxHealth)
        self.health:SetValue(UnitHealth(unit))
        self.absorb:SetMinMaxValues(0, maxHealth)
        self.absorb:SetValue(UnitGetTotalAbsorbs(unit))
        self.absorb:Show()
    end

    -- Hash line positioning (target only)
    local hlEnabled = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLineEnabled)
    local hlPct = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLinePercent) or defaults.hashLinePercent
    local isTarget = unit and UnitIsUnit(unit, "target")
    if hlEnabled and hlPct and hlPct > 0 and isTarget then
        local barW = self.health:GetWidth()
        local xPos = barW * (hlPct / 100)
        self.hashLine:ClearAllPoints()
        self.hashLine:SetPoint("TOP", self.health, "TOPLEFT", xPos, 0)
        self.hashLine:SetPoint("BOTTOM", self.health, "BOTTOMLEFT", xPos, 0)
        local hlc = (EllesmereUINameplatesDB and EllesmereUINameplatesDB.hashLineColor) or defaults.hashLineColor
        self.hashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
        self.hashLine:Show()
    else
        self.hashLine:Hide()
    end

    -- Compute text strings
    local pctText, pctNoSignText, numText
    if UnitIsDeadOrGhost(unit) then
        pctText = "0%"
        pctNoSignText = "0"
        numText = "0"
    elseif UnitHealthPercent then
        local pctVal = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
        pctText = string.format("%d%%", pctVal)
        pctNoSignText = string.format("%d", pctVal)
        numText = AbbreviateLargeNumbers(UnitHealth(unit))
    else
        pctText = ""
        pctNoSignText = ""
        numText = ""
    end

    local db = EllesmereUINameplatesDB

    -- Hide all health text first
    self.hpText:Hide()
    self.hpNumber:Hide()

    for _, slot in ipairs(HP_BAR_SLOTS) do
        local element = GetTextSlot(slot.key)
        local txOff, tyOff = GetTextSlotOffsets(slot.key)
        local slotFontSz = GetTextSlotSize(slot.key)
        local sr, sg, sb = GetTextSlotColor(slot.key)
        if element == "healthPercent" or element == "healthPercentNoSign" then
            self.hpText:SetParent(self.healthTextFrame)
            SetFSFont(self.hpText, slotFontSz, GetNPOutline())
            self.hpText:SetText(element == "healthPercentNoSign" and pctNoSignText or pctText)
            self.hpText:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpText:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpText, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpText:SetJustifyH(slot.anchor)
            self.hpText:SetTextColor(sr, sg, sb, 1)
            self.hpText:Show()
        elseif element == "healthNumber" then
            self.hpNumber:SetParent(self.healthTextFrame)
            SetFSFont(self.hpNumber, slotFontSz, GetNPOutline())
            self.hpNumber:SetText(numText)
            self.hpNumber:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpNumber:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpNumber, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpNumber:SetJustifyH(slot.anchor)
            self.hpNumber:SetTextColor(sr, sg, sb, 1)
            self.hpNumber:Show()
        elseif element == "healthPctNum" or element == "healthNumPct" then
            self.hpText:SetParent(self.healthTextFrame)
            SetFSFont(self.hpText, slotFontSz, GetNPOutline())
            self.hpText:SetText(FormatCombinedHealth(element, pctText, numText))
            self.hpText:ClearAllPoints()
            if slot.anchor == "CENTER" then
                self.hpText:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
            else
                PP.Point(self.hpText, slot.anchor, self.health, slot.point, slot.xOff + txOff, tyOff)
            end
            self.hpText:SetJustifyH(slot.anchor)
            self.hpText:SetTextColor(sr, sg, sb, 1)
            self.hpText:Show()
        end
    end

    -- Process top slot for health elements
    local topElement = GetTextSlot("textSlotTop")
    if topElement == "healthPercent" or topElement == "healthPercentNoSign" or topElement == "healthNumber"
       or topElement == "healthPctNum" or topElement == "healthNumPct" then
        local nameYOff = GetNameYOffset()
        local cpPush = GetClassPowerTopPush(self)
        local txOff, tyOff = GetTextSlotOffsets("textSlotTop")
        local topFontSz = GetTextSlotSize("textSlotTop")
        local tr, tg, tb = GetTextSlotColor("textSlotTop")
        local fs
        if topElement == "healthNumber" then
            fs = self.hpNumber
            fs:SetText(numText)
        else
            fs = self.hpText
            if topElement == "healthPercent" then
                fs:SetText(pctText)
            elseif topElement == "healthPercentNoSign" then
                fs:SetText(pctNoSignText)
            else
                fs:SetText(FormatCombinedHealth(topElement, pctText, numText))
            end
        end
        SetFSFont(fs, topFontSz, GetNPOutline())
        fs:SetParent(self.topTextFrame)
        fs:ClearAllPoints()
        PP.Point(fs, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        fs:SetJustifyH("CENTER")
        fs:SetTextColor(tr, tg, tb, 1)
        fs:Show()
    end
end
function NameplateFrame:UpdateHealthColor()
    local unit = self.unit
    if not unit then return end
    self.health:SetStatusBarColor(GetReactionColor(unit))
    -- Focus overlay: show stripe textures on focus target's health bar
    -- Fill clip frame at full alpha, bg clip frame at half alpha
    if self.focusClipFill then
        local db = EllesmereUINameplatesDB or defaults
        local tex = db.focusOverlayTexture or defaults.focusOverlayTexture
        if tex ~= "none" and UnitIsUnit(unit, "focus") then
            local MEDIA = "Interface\\AddOns\\EllesmereUINameplates\\Media\\"
            local texPath = MEDIA .. tex .. ".png"
            local overlayAlpha = db.focusOverlayAlpha or defaults.focusOverlayAlpha
            local oc = db.focusOverlayColor or defaults.focusOverlayColor
            self.focusOverlayFill:SetTexture(texPath)
            self.focusOverlayFill:SetAlpha(overlayAlpha)
            self.focusOverlayFill:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipFill:Show()
            self.focusOverlayBg:SetTexture(texPath)
            self.focusOverlayBg:SetAlpha(overlayAlpha * 0.3)
            self.focusOverlayBg:SetVertexColor(oc.r, oc.g, oc.b)
            self.focusClipBg:Show()
        else
            self.focusClipFill:Hide()
            self.focusClipBg:Hide()
        end
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
    end
end
function NameplateFrame:UpdateClassification()
    if not self.unit then return end
    local slot = GetClassificationSlot()
    if slot == "none" or InRealInstancedContent() then
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
    end
    local c = UnitClassification(self.unit)
    if c == "elite" or c == "worldboss" then
        self.class:SetAtlas("nameplates-icon-elite-gold")
    elseif c == "rareelite" then
        self.class:SetAtlas("nameplates-icon-elite-silver")
    elseif c == "rare" then
        self.class:SetAtlas("nameplates-icon-star")
    else
        self.classFrame:Hide()
        self:UpdateNameWidth()
        return
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
        PP.Point(self.classFrame, "RIGHT", self.health, "LEFT",
            -sideOff + cxOff, cyOff)
    elseif slot == "right" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.classFrame, "LEFT", self.health, "RIGHT",
            sideOff + cxOff, cyOff)
    elseif slot == "topleft" then
        PP.Point(self.classFrame, "BOTTOMLEFT", self.health, "TOPLEFT", -2 + cxOff, 2 + cpPush + cyOff)
    elseif slot == "topright" then
        PP.Point(self.classFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", 2 + cxOff, 2 + cpPush + cyOff)
    end
    self.classFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:UpdateNameWidth()
    local barW = GetHealthBarWidth()
    local nameSlot = FindSlotForElement("enemyName")
    if nameSlot == "textSlotTop" then
        -- Above the bar: full bar width minus raid marker if shown
        local nameW = barW
        local rmPos = GetRaidMarkerPos()
        if rmPos ~= "none" and self.raidFrame:IsShown() then
            nameW = nameW - 2 * (GetRaidMarkerSize() - 2) - 7
        end
        local clSlot = GetClassificationSlot()
        if clSlot ~= "none" and self.classFrame:IsShown() then
            nameW = nameW - (GetRareEliteIconSize() + 4)
        end
        PP.Width(self.name, math.max(nameW, 20))
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
        local nameW = barW - usedWidth
        PP.Width(self.name, math.max(nameW, 20))
    else
        -- Name not in any slot, use minimal width
        PP.Width(self.name, math.max(barW, 20))
    end
end
function NameplateFrame:RefreshNamePosition()
    local nameSlot = FindSlotForElement("enemyName")
    local nameYOff = GetNameYOffset()
    self:UpdateNameWidth()
    self.name:ClearAllPoints()
    if nameSlot == "textSlotLeft" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotLeft")
        SetFSFont(self.name, GetTextSlotSize("textSlotLeft"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        PP.Point(self.name, "LEFT", self.health, "LEFT", 4 + txOff, tyOff)
        self.name:SetJustifyH("LEFT")
        self.name:Show()
    elseif nameSlot == "textSlotCenter" then
        local txOff, tyOff = GetTextSlotOffsets("textSlotCenter")
        SetFSFont(self.name, GetTextSlotSize("textSlotCenter"), GetNPOutline())
        self.name:SetParent(self.healthTextFrame)
        self.name:SetPoint("CENTER", self.health, "CENTER", txOff, tyOff)
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
        PP.Point(self.name, "BOTTOM", self.health, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
        self.name:SetJustifyH("CENTER")
        self.name:Show()
    else
        -- Name not assigned to any slot
        self.name:Hide()
    end
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
        PP.Point(self.raidFrame, "RIGHT", self.health, "LEFT",
            -sideOff + rxOff, ryOff)
    elseif pos == "right" then
        local sideOff = GetSideAuraXOffset()
        PP.Point(self.raidFrame, "LEFT", self.health, "RIGHT",
            sideOff + rxOff, ryOff)
    elseif pos == "topleft" then
        PP.Point(self.raidFrame, "BOTTOMLEFT", self.health, "TOPLEFT", -2 + rxOff, cpPush + ryOff)
    elseif pos == "topright" then
        PP.Point(self.raidFrame, "BOTTOMRIGHT", self.health, "TOPRIGHT", 2 + rxOff, cpPush + ryOff)
    end
    self.raidFrame:Show()
    self:UpdateNameWidth()
end
function NameplateFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    local style = GetTargetGlowStyle()
    if isTarget and style ~= "none" then
        self.glow:Show()
    else
        self.glow:Hide()
    end
    -- Vibrant: override health bar border to white on selected target
    if isTarget and style == "vibrant" then
        for _, tex in ipairs(self.borderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
        for _, tex in ipairs(self._simpleBorderFrame._texs) do tex:SetVertexColor(1, 1, 1) end
    else
        self:ApplyBorderColor()
    end
    if EllesmereUINameplatesDB and EllesmereUINameplatesDB.showTargetArrows then
        if isTarget then
            local sc = EllesmereUINameplatesDB.targetArrowScale or 1.0
            local aw, ah = math.floor(11 * sc + 0.5), math.floor(16 * sc + 0.5)
            PP.Size(self.leftArrow,  aw, ah)
            PP.Size(self.rightArrow, aw, ah)
            self.leftArrow:Show()
            self.rightArrow:Show()
        else
            self.leftArrow:Hide()
            self.rightArrow:Hide()
        end
    else
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
end
function NameplateFrame:ApplyMouseover()
    if not self.unit then return end
    if UnitExists("mouseover") and UnitIsUnit(self.unit, "mouseover") then
        self.highlight:Show()
        currentMouseoverPlate = self
    else
        self.highlight:Hide()
    end
end
function NameplateFrame:UpdateAuras(updateInfo)
    if not self.unit or not self.nameplate then return end
    local unit = self.unit

    local needsFullRefresh = not updateInfo or updateInfo.isFullUpdate or not self._shownAuras
    
    if not needsFullRefresh then
        local hasRelevantChange = false
        if updateInfo.addedAuras and #updateInfo.addedAuras > 0 then
            -- Always refresh when auras are added so the new debuff/buff
            -- can be evaluated against IsAuraFilteredOutByInstanceID.
            hasRelevantChange = true
        end
        if not hasRelevantChange and updateInfo.removedAuraInstanceIDs then
            for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
                if self._shownAuras[id] then
                    hasRelevantChange = true
                    break
                end
            end
        end
        if not hasRelevantChange and updateInfo.updatedAuraInstanceIDs then
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

    if not self._shownAuras then
        self._shownAuras = {}
    else
        wipe(self._shownAuras)
    end

    for i = 1, 4 do
        local dSlot = self.debuffs[i]
        local bSlot = self.buffs[i]
        dSlot:Hide()
        dSlot.icon:SetTexture(nil)
        if dSlot.pandemicGlow and dSlot.pandemicGlow.active then
            ns.StopPandemicGlow(dSlot)
        end
        dSlot._durationObj = nil
        bSlot:Hide()
        bSlot.icon:SetTexture(nil)
        local dCd = dSlot.cd
        if dCd then
            if dCd.SetDrawSwipe then dCd:SetDrawSwipe(false) end
            if dCd.Clear then dCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(dCd)
            else dCd:SetCooldown(0, 0) end
        end
        local bCd = bSlot.cd
        if bCd then
            if bCd.SetDrawSwipe then bCd:SetDrawSwipe(false) end
            if bCd.Clear then bCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(bCd)
            else bCd:SetCooldown(0, 0) end
        end
    end
    for i = 1, 2 do
        local ccSlot = self.cc[i]
        ccSlot:Hide()
        ccSlot.icon:SetTexture(nil)
        local cCd = ccSlot.cd
        if cCd then
            if cCd.SetDrawSwipe then cCd:SetDrawSwipe(false) end
            if cCd.Clear then cCd:Clear()
            elseif CooldownFrame_Clear then CooldownFrame_Clear(cCd)
            else cCd:SetCooldown(0, 0) end
        end
    end
    -- Get slot assignments; skip processing for any slot set to "none"
    local debuffSlotVal, buffSlotVal, ccSlotVal = GetAuraSlots()
    local dIdx = 1
    local db = EllesmereUINameplatesDB
    local npUseAuraFilter = db and db.useAuraFilter and EllesmereUI.IsSpellFiltered
    if debuffSlotVal ~= "none" then
    local showAll = db and db.showAllDebuffs
    -- Build the important set from Blizzard's debuffList synchronously.
    -- The debuffList is already current when UNIT_AURA fires -- Blizzard's
    -- UnitFrame processes the same event in the same dispatch cycle.
    local importantSet
    if not showAll and self.nameplate then
        importantSet = {}
        local uf = self.nameplate.UnitFrame
        if uf and uf.AurasFrame and uf.AurasFrame.debuffList and uf.AurasFrame.debuffList.Iterate then
            uf.AurasFrame.debuffList:Iterate(function(auraInstanceID)
                importantSet[auraInstanceID] = true
            end)
        end
    end
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local allDebuffs = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")
        if allDebuffs then
            local GetCount = C_UnitAuras.GetAuraApplicationDisplayCount
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(allDebuffs) do
                if dIdx > 4 then break end
                local id = aura and aura.auraInstanceID
                if id and aura.icon and (showAll or (importantSet and importantSet[id]))
                    and not (npUseAuraFilter and npUseAuraFilter(aura.spellId)) then
                        local slot = self.debuffs[dIdx]
                        slot.icon:SetTexture(aura.icon)
                        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        if GetCount then
                            slot.count:SetText(GetCount(unit, id, 2, 1000) or "")
                        end
                        local cd = slot.cd
                        if cd and GetDur then
                            local durObj = GetDur(unit, id)
                            if durObj and cd.SetCooldownFromDurationObject then
                                if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                                cd:SetCooldownFromDurationObject(durObj)
                                cd:Show()
                            end
                            slot._durationObj = durObj
                        else
                            slot._durationObj = nil
                        end
                        slot:Show()
                        self._shownAuras[id] = true
                        dIdx = dIdx + 1
                end
            end
        end
    end
    local debuffCount = dIdx - 1
    if debuffCount > 0 then
        local spacing = GetAuraSpacing()
        local debuffSz = GetDebuffIconSize()
        for i = 1, debuffCount do
            PP.Size(self.debuffs[i], debuffSz, debuffSz)
        end
        PositionAuraSlot(self.debuffs, debuffCount, debuffSlotVal, self, debuffSz, debuffSz, spacing, GetAuraSlotOffsets("debuffSlot"))
    end
    -- Pandemic glow check for debuffs
    local pandemicEnabled = GetPandemicGlow()
    for i = 1, 4 do
        local slot = self.debuffs[i]
        local pg = slot.pandemicGlow
        if i <= (dIdx - 1) and pandemicEnabled then
            ns.ApplyPandemicGlow(slot)
        else
            if pg and pg.active then
                ns.StopPandemicGlow(slot)
            end
        end
    end
    end -- debuffSlotVal ~= "none"
    if buffSlotVal ~= "none" then
    if UnitCanAttack("player", unit) and C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local allBuffs = C_UnitAuras.GetUnitAuras(unit, "HELPFUL|INCLUDE_NAME_PLATE_ONLY")
        local bIdx = 1
        if allBuffs then
            local GetCount = C_UnitAuras.GetAuraApplicationDisplayCount
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(allBuffs) do
                if bIdx > 4 then break end
                local id = aura and aura.auraInstanceID
                if id and type(aura.dispelName) ~= "nil" and aura.icon
                    and not (npUseAuraFilter and npUseAuraFilter(aura.spellId)) then
                    local slot = self.buffs[bIdx]
                    slot.icon:SetTexture(aura.icon)
                    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    if GetCount then
                        slot.count:SetText(GetCount(unit, id, 2, 1000) or "")
                    end
                    local cd = slot.cd
                    if cd and GetDur then
                        local durObj = GetDur(unit, id)
                        if durObj and cd.SetCooldownFromDurationObject then
                            if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                            cd:SetCooldownFromDurationObject(durObj)
                            cd:Show()
                        end
                    end
                    slot:Show()
                    self._shownAuras[id] = true
                    bIdx = bIdx + 1
                end
            end
        end
    end
    end -- buffSlotVal ~= "none"
    local ccShown = 0
    if ccSlotVal ~= "none" then
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ccAuras = C_UnitAuras.GetUnitAuras(unit, "HARMFUL|CROWD_CONTROL")
        if ccAuras then
            local GetDur = C_UnitAuras.GetAuraDuration
            for _, aura in ipairs(ccAuras) do
                if ccShown >= 2 then break end
                if aura and aura.auraInstanceID and aura.icon
                    and not (npUseAuraFilter and npUseAuraFilter(aura.spellId)) then
                    ccShown = ccShown + 1
                    local slot = self.cc[ccShown]
                    slot.icon:SetTexture(aura.icon)
                    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    slot.icon:Show()
                    local cd = slot.cd
                    if cd and GetDur then
                        local durObj = GetDur(unit, aura.auraInstanceID)
                        if durObj and cd.SetCooldownFromDurationObject then
                            if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
                            cd:SetCooldownFromDurationObject(durObj)
                            cd:Show()
                        end
                    end
                    slot:Show()
                    self._shownAuras[aura.auraInstanceID] = true
                end
            end
        end
    end
    end -- ccSlotVal ~= "none"
    -- Reposition buffs and CC based on actual shown counts (important when in "top" slot for centering)
    if buffSlotVal ~= "none" then
        local buffCount = 0
        for i = 1, 4 do if self.buffs[i]:IsShown() then buffCount = buffCount + 1 end end
        if buffCount > 0 then
            local spacing = GetAuraSpacing()
            local buffSz = GetBuffIconSize()
            for i = 1, buffCount do
                PP.Size(self.buffs[i], buffSz, buffSz)
            end
            PositionAuraSlot(self.buffs, buffCount, buffSlotVal, self, buffSz, buffSz, spacing, GetAuraSlotOffsets("buffSlot"))
        end
    end
    if ccSlotVal ~= "none" and ccShown > 0 then
        local spacing = GetAuraSpacing()
        local ccSz = GetCCIconSize()
        for i = 1, ccShown do
            PP.Size(self.cc[i], ccSz, ccSz)
        end
        PositionAuraSlot(self.cc, ccShown, ccSlotVal, self, ccSz, ccSz, spacing, GetAuraSlotOffsets("ccSlot"))
    end
    -- Reposition target arrows outside the outermost side auras
    PositionArrowsOutsideAuras(self)
end
function NameplateFrame:UpdateCast()
    if not self.unit then
        self.cast:Hide()
        return
    end
    local name, _, texture, _, _, _, _, kickProtected = UnitCastingInfo(self.unit)
    local isChannel = false
    if type(name) == "nil" then
        name, _, texture, _, _, _, kickProtected = UnitChannelInfo(self.unit)
        isChannel = true
    end
    if type(name) == "nil" then
        if not self._interrupted then
            self.cast:Hide()
        end
        if self.isCasting then
            if self._castFallback then
                self._castFallback = nil
                fallbackCastCount = fallbackCastCount - 1
                if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
            end
            NotifyCastEnded()
        end
        self.isCasting = false
        self:HideKickTick()
        self:ApplyCastScale()
        -- Reposition class power pips (cast bar gone, pips move back to health bar)
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

    self.cast:Show()
    if type(texture) ~= "nil" then
        self.castIcon:SetTexture(texture)
    end
    self.castName:SetText(type(name) ~= "nil" and name or "")
    
    local spellTarget
    local spellTargetClass
    if UnitSpellTargetName then
        spellTarget = UnitSpellTargetName(self.unit)
        if UnitSpellTargetClass then
            spellTargetClass = UnitSpellTargetClass(self.unit)
        end
    end
    if type(spellTarget) == "nil" then
        spellTarget = UnitName(self.unit .. "target")
        spellTargetClass = UnitClassBase(self.unit .. "target")
    end
    self.castTarget:SetText(type(spellTarget) ~= "nil" and spellTarget or "")

    -- Apply class color to cast target text if enabled and target is a player
    local db = EllesmereUINameplatesDB or defaults
    local useClassColor = defaults.castTargetClassColor
    if db.castTargetClassColor ~= nil then useClassColor = db.castTargetClassColor end
    if useClassColor then
        local appliedCTC = false
        if spellTargetClass and C_ClassColor then
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

    -- Two-point anchor: castName stretches from LEFT+5 to 5px before castTarget's left edge
    -- This avoids GetStringWidth() which returns tainted secret values on nameplates
    self.castName:SetWidth(0)  -- clear any fixed width
    self.castName:ClearAllPoints()
    self.castName:SetPoint("LEFT", self.cast, "LEFT", 5, 0)
    self.castName:SetPoint("RIGHT", self.castTarget, "LEFT", -5, 0)

    if type(kickProtected) == "nil" then
        kickProtected = false
    end
    self._kickProtected = kickProtected
    local cfg = EllesmereUINameplatesDB or defaults
    local unintColor = cfg.castBarUninterruptible or defaults.castBarUninterruptible
    self.castBarOverlay:SetVertexColor(unintColor.r, unintColor.g, unintColor.b)
    self.castShieldFrame:Show()
    self:ApplyCastColor(kickProtected)
    
    if UnitCastingDuration and self.cast.SetTimerDuration then
        if isChannel then
            local castDuration = UnitChannelDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.RemainingTime)
                if not self.isCasting then NotifyCastStarted() end
                self.isCasting = true
            end
        else
            local castDuration = UnitCastingDuration(self.unit)
            if castDuration then
                self.cast:SetReverseFill(false)
                self.cast:SetTimerDuration(castDuration, nil, Enum.StatusBarTimerDirection.ElapsedTime)
            end
            if not self.isCasting then NotifyCastStarted() end
            self.isCasting = true
        end
    else
        if not self.isCasting then
            self.isCasting = true
            self._castFallback = true
            fallbackCastCount = fallbackCastCount + 1
            castFallbackFrame:Show()
            NotifyCastStarted()
        end
    end
    self:ApplyCastScale()
    self:UpdateKickTick(kickProtected, isChannel)
    -- Reposition class power pips (cast bar now visible, pips move below it)
    if GetShowClassPower() and classPowerType and self._cpPips and self.unit and UnitIsUnit(self.unit, "target") then
        UpdateClassPowerOnPlate(self)
    end
end
function NameplateFrame:ApplyCastScale()
    local s = GetCastScale() / 100
    if self.isCasting and s ~= 1 then
        self:SetScale(s)
    else
        self:SetScale(1)
    end
end
function NameplateFrame:ApplyCastColor(uninterruptible)
    local cfg = EllesmereUINameplatesDB or defaults
    local kickReadyTint = cfg.interruptReady or defaults.interruptReady
    local normalCastTint = cfg.castBar or defaults.castBar
    local cr, cg, cb = ComputeCastBarTint(kickReadyTint, normalCastTint)
    self.cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)
    if self.castBarOverlay.SetAlphaFromBoolean then
        self.castBarOverlay:SetAlphaFromBoolean(uninterruptible)
        self.castShieldFrame:SetAlphaFromBoolean(uninterruptible)
    else
        local a = uninterruptible and 1 or 0
        self.castBarOverlay:SetAlpha(a)
        self.castShieldFrame:SetAlpha(a)
    end
end
function NameplateFrame:HideKickTick()
    self.kickPositioner:Hide()
    self.kickMarker:Hide()
    if self._kickTicker then
        self._kickTicker:Cancel()
        self._kickTicker = nil
    end
end
function NameplateFrame:UpdateKickTick(kickProtected, isChannel)
    if not GetKickTickEnabled() or not activeKickSpell then
        self:HideKickTick()
        return
    end
    -- kickProtected is a secret boolean on Midnight cannot branch on it.
    -- Store it so we can apply visibility via SetAlphaFromBoolean after setup.
    self._kickProtected = kickProtected
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        self:HideKickTick()
        return
    end
    -- Midnight path: use secret duration objects
    if UnitCastingDuration and self.cast.SetTimerDuration then
        local castDuration = isChannel and UnitChannelDuration(self.unit) or UnitCastingDuration(self.unit)
        if not castDuration then
            self:HideKickTick()
            return
        end
        local totalDur = castDuration:GetTotalDuration()
        local interruptCD = C_Spell.GetSpellCooldownDuration(activeKickSpell)
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
        -- Both values set ONCE at cast start, never updated in ticker.
        -- (positioner is a static snapshot of elapsed time,
        -- marker's secret duration naturally counts down via the engine.)
        self.kickPositioner:SetValue(castDuration:GetElapsedDuration())
        self.kickMarker:SetValue(interruptCD:GetRemainingDuration())
        -- Apply color
        local kr, kg, kb = GetKickTickColor()
        self.kickTick:SetColorTexture(kr, kg, kb, 1)
        -- Handle channel vs cast fill direction
        if isChannel then
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("RIGHT", self.kickPositioner:GetStatusBarTexture(), "LEFT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("RIGHT", self.kickMarker:GetStatusBarTexture(), "LEFT")
        else
            self.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
            self.kickMarker:ClearAllPoints()
            self.kickTick:ClearAllPoints()
            self.kickMarker:SetPoint("LEFT", self.kickPositioner:GetStatusBarTexture(), "RIGHT")
            self.kickTick:SetPoint("TOP", self.kickMarker, "TOP", 0, 0)
            self.kickTick:SetPoint("BOTTOM", self.kickMarker, "BOTTOM", 0, 0)
            self.kickTick:SetPoint("LEFT", self.kickMarker:GetStatusBarTexture(), "RIGHT")
        end
        self.kickPositioner:Show()
        self.kickMarker:Show()
        -- Compute initial tick alpha immediately (avoids split-second delay
        -- from waiting for the first ticker fire at 0.1s).
        if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
            local kickReady = interruptCD:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            self.kickTick:SetAlpha(alpha)
        else
            self.kickTick:SetAlpha(0)
        end
        -- Ticker: only updates tick alpha at 10fps.
        -- Neither positioner nor marker values are updated both are set once
        -- at cast start and left alone.  The marker's
        -- secret duration naturally counts down via the engine, moving the
        -- tick mark as the kick CD expires.
        if self._kickTicker then self._kickTicker:Cancel() end
        self._kickTicker = C_Timer.NewTicker(0.1, function()
            if not self.isCasting or not self.unit then
                self:HideKickTick()
                return
            end
            -- Compute tick visibility: show only when kick is on CD AND cast is interruptible.
            -- Both are secret booleans chain EvaluateColorValueFromBoolean calls
            -- to combine conditions into a single secret alpha.
            local icd = C_Spell.GetSpellCooldownDuration(activeKickSpell)
            if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
                local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(self._kickProtected, 0, 1)
                local kickReady = icd:IsZero()
                local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
                self.kickTick:SetAlpha(alpha)
            end
        end)
    else
        -- Legacy path (non-Midnight): use GetTime() math
        -- Not implementing legacy path since user is on Midnight
        self:HideKickTick()
    end
end
function NameplateFrame:ShowInterrupted(interrupterGUID)
    if self.isCasting then
        if self._castFallback then
            self._castFallback = nil
            fallbackCastCount = fallbackCastCount - 1
            if fallbackCastCount <= 0 then fallbackCastCount = 0; castFallbackFrame:Hide() end
        end
        NotifyCastEnded()
    end
    self.isCasting = false
    self:HideKickTick()
    self:ApplyCastScale()

    self._interrupted = true
    self.cast:SetReverseFill(false)
    self.cast:SetMinMaxValues(0, 1)
    self.cast:SetValue(1)
    self.cast:GetStatusBarTexture():SetVertexColor(0.8, 0.0, 0.0)
    self.castName:SetText("Interrupted")

    -- Show interrupter name (class-colored) in cast target position
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
    if interrupterName then
        self.castTarget:SetText(interrupterName)
        local cfg = EllesmereUINameplatesDB or defaults
        local useClassColor = defaults.castTargetClassColor
        if cfg.castTargetClassColor ~= nil then useClassColor = cfg.castTargetClassColor end
        if useClassColor then
            if interrupterClass and C_ClassColor then
                local c = C_ClassColor.GetClassColor(interrupterClass)
                if c then
                    self.castTarget:SetTextColor(c:GetRGB())
                else
                    self.castTarget:SetTextColor(1, 1, 1, 1)
                end
            else
                self.castTarget:SetTextColor(1, 1, 1, 1)
            end
        else
            local ctc = (cfg and cfg.castTargetColor) or defaults.castTargetColor
            self.castTarget:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
        end
    else
        self.castTarget:SetText("")
    end

    self.castName:SetWidth(0)
    self.castName:ClearAllPoints()
    self.castName:SetPoint("LEFT", self.cast, "LEFT", 5, 0)
    self.castName:SetPoint("RIGHT", self.castTarget, "LEFT", -5, 0)
    self.castShieldFrame:Hide()
    self.castShieldFrame:SetAlpha(1)
    self.castBarOverlay:SetAlpha(0)
    self.cast:Show()

    if self._interruptTimer then
        self._interruptTimer:Cancel()
        self._interruptTimer = nil
    end

    self._interruptTimer = C_Timer.NewTimer(1.0, function()
        if self._interrupted then
            self._interrupted = nil
            self._interruptTimer = nil
            self.cast:Hide()
        end
    end)
end
function NameplateFrame:UNIT_HEALTH()
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_ABSORB_AMOUNT_CHANGED()
    self:UpdateHealthValues()
end
function NameplateFrame:UNIT_AURA(_, updateInfo)
    self:UpdateAuras(updateInfo)
end
function NameplateFrame:UNIT_NAME_UPDATE()
    self:UpdateName()
end
function NameplateFrame:LOSS_OF_CONTROL_UPDATE()
    self:UpdateAuras()
end
function NameplateFrame:LOSS_OF_CONTROL_ADDED()
    self:UpdateAuras()
end
function NameplateFrame:UNIT_THREAT_LIST_UPDATE()
    self:UpdateHealthColor()
end
function NameplateFrame:UNIT_FLAGS()
    self:UpdateHealthColor()
end
function NameplateFrame:UNIT_SPELLCAST_START()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_START()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_DELAYED()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_UPDATE()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_STOP()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_CHANNEL_STOP()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_FAILED()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTED(_, _, _, interrupterGUID)
    self:ShowInterrupted(interrupterGUID)
end
function NameplateFrame:UNIT_SPELLCAST_INTERRUPTIBLE()
    self:UpdateCast()
end
function NameplateFrame:UNIT_SPELLCAST_NOT_INTERRUPTIBLE()
    self:UpdateCast()
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

-- Register for aura filter changes so nameplates refresh when mode/list changes
if EllesmereUI and EllesmereUI.RegisterAuraFilterCallback then
    EllesmereUI.RegisterAuraFilterCallback(function()
        local plates = ns.plates
        for _, plate in pairs(plates) do
            plate:UpdateAuras()
        end
    end)
end

local pendingUnits = {}
ns.pendingUnits = pendingUnits
local currentMouseoverPlate = nil
local mouseoverTicker = nil

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
            if currentMouseoverPlate == plate then
                currentMouseoverPlate = nil
                if mouseoverTicker then
                    mouseoverTicker:Cancel()
                    mouseoverTicker = nil
                end
            end
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

factionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
factionFrame:RegisterEvent("ROLE_CHANGED_INFORM")
factionFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
factionFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD"
    or event == "ROLE_CHANGED_INFORM"
    or event == "GROUP_ROSTER_UPDATE" then
        RefreshThreatCache()
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateFactionFrameForZone()
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
local function UpdateMouseover()
    if currentMouseoverPlate then
        currentMouseoverPlate.highlight:Hide()
        currentMouseoverPlate = nil
    end
    if UnitExists("mouseover") then
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "mouseover") then
                plate.highlight:Show()
                currentMouseoverPlate = plate
                break
            end
        end
        if not mouseoverTicker then
            mouseoverTicker = C_Timer.NewTicker(0.1, function()
                if not UnitExists("mouseover") then
                    if mouseoverTicker then
                        mouseoverTicker:Cancel()
                        mouseoverTicker = nil
                    end
                    UpdateMouseover()
                end
            end)
        end
    end
end
-- Refresh Y-offset on all visible friendly name-only plates
function ns.RefreshFriendlyNameOnlyOffset()
    local db = EllesmereUINameplatesDB or defaults
    local nameOnly = (db.friendlyNameOnly ~= false)
    local yOff = nameOnly and (db.friendlyNameOnlyYOffset or 0) or 0
    for unit, nameplate in pairs(pendingUnits) do
        if nameplate.UnitFrame then
            local uf = nameplate.UnitFrame
            if yOff ~= 0 then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                nameplate._enoYOffset = true
            elseif nameplate._enoYOffset then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
                nameplate._enoYOffset = nil
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
            local db = EllesmereUINameplatesDB or defaults
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
                end
                -- Apply Y-offset
                local yOff = db.friendlyNameOnlyYOffset or 0
                if yOff ~= 0 and nameplate.UnitFrame then
                    nameplate.UnitFrame:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                    nameplate.UnitFrame:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                    nameplate._enoYOffset = true
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
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        questMobCache[unit] = nil
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
        if nameplate and nameplate._enoYOffset then
            local uf = nameplate.UnitFrame
            if uf then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
            end
            nameplate._enoYOffset = nil
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
            if currentMouseoverPlate == plate then
                currentMouseoverPlate = nil
                if mouseoverTicker then
                    mouseoverTicker:Cancel()
                    mouseoverTicker = nil
                end
            end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[unit] = nil
        end
        if ns.RemoveFriendlyPlate then ns.RemoveFriendlyPlate(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, plate in pairs(ns.plates) do
            plate:ApplyTarget()
        end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        local focusPct = GetFocusCastHeight()
        for _, plate in pairs(ns.plates) do
            plate:UpdateHealthColor()
            -- Refresh cast bar height for focus multiplier (old + new focus)
            if focusPct ~= 100 then
                local castH = GetCastBarHeight()
                if plate.unit and UnitIsUnit(plate.unit, "focus") then
                    castH = math.floor(castH * focusPct / 100 + 0.5)
                end
                plate.cast:SetHeight(castH)
                plate.castIconFrame:SetSize(castH, castH)
                plate.castSpark:SetHeight(castH)
                plate.kickMarker:SetHeight(castH)
            end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        UpdateMouseover()
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateRaidIcon()
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
        local db = EllesmereUINameplatesDB
        if not db then return end

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

        local specMap = db[K_ASSIGN]
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
        if not targetKey and db[K_DEFAULT] then
            targetKey = db[K_DEFAULT]
        end
        if not targetKey then return end

        local currentActive = db[K_ACTIVE] or "ellesmereui"
        if currentActive == targetKey then return end  -- already correct

        -- Apply the snapshot for targetKey
        local presetKeys = ns._displayPresetKeys  -- set below
        if not presetKeys then return end

        if targetKey == "ellesmereui" then
            for _, key in ipairs(presetKeys) do
                local def = ns.defaults[key]
                if type(def) == "table" and def.r then
                    db[key] = { r = def.r, g = def.g, b = def.b }
                else
                    db[key] = def
                end
            end
            db[K_SNAP] = nil
        elseif targetKey == "custom" then
            if db[K_CUSTOM] then
                for _, key in ipairs(presetKeys) do
                    local v = db[K_CUSTOM][key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            db[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            db[key] = v
                        end
                    end
                end
            end
        elseif targetKey:sub(1, 5) == "user:" then
            local name = targetKey:sub(6)
            local snap = db[K_PRESETS] and db[K_PRESETS][name]
            if snap then
                for _, key in ipairs(presetKeys) do
                    local v = snap[key]
                    if v ~= nil then
                        if type(v) == "table" and v.r then
                            db[key] = { r = v.r, g = v.g, b = v.b }
                        else
                            db[key] = v
                        end
                    end
                end
            end
        end

        db[K_ACTIVE] = targetKey
        db[K_SNAP] = nil
    end

    -- Store preset keys so the login handler can use them (set once, never changes)
    ns._displayPresetKeys = {
        "borderStyle", "borderColor", "targetGlowStyle", "showTargetArrows",
        "showClassPower", "classPowerPos", "classPowerYOffset", "classPowerXOffset", "classPowerScale",
        "classPowerClassColors", "classPowerCustomColor", "classPowerGap",
        "textSlotTop", "textSlotRight", "textSlotLeft", "textSlotCenter",
        "nameYOffset",
        "healthBarHeight", "healthBarWidth", "castBarHeight",
        "castNameSize", "castNameColor", "castTargetSize", "castTargetClassColor", "castTargetColor",
        "debuffSlot", "buffSlot", "ccSlot",
        "debuffYOffset", "sideAuraXOffset", "auraSpacing",
        "debuffTimerPosition", "buffTimerPosition", "ccTimerPosition",
        "auraDurationTextSize", "auraDurationTextColor",
        "auraStackTextSize", "auraStackTextColor",
        "buffTextSize", "buffTextColor", "ccTextSize", "ccTextColor",
        "raidMarkerPos",
        "classificationSlot",
        -- Slot-based size + XY offsets
        "topSlotSize", "topSlotXOffset", "topSlotYOffset",
        "rightSlotSize", "rightSlotXOffset", "rightSlotYOffset",
        "leftSlotSize", "leftSlotXOffset", "leftSlotYOffset",
        "toprightSlotSize", "toprightSlotXOffset", "toprightSlotYOffset", "toprightSlotGrowth",
        "topleftSlotSize", "topleftSlotXOffset", "topleftSlotYOffset", "topleftSlotGrowth",
        -- Text slot size + XY offsets
        "textSlotTopSize", "textSlotTopXOffset", "textSlotTopYOffset",
        "textSlotRightSize", "textSlotRightXOffset", "textSlotRightYOffset",
        "textSlotLeftSize", "textSlotLeftXOffset", "textSlotLeftYOffset",
        "textSlotCenterSize", "textSlotCenterXOffset", "textSlotCenterYOffset",
        -- Text slot color keys
        "textSlotTopColor", "textSlotRightColor", "textSlotLeftColor", "textSlotCenterColor",
    }

    -- Also handle spec changes that happen before the UI is ever opened
    local specLoginFrame = CreateFrame("Frame")
    specLoginFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specLoginFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then return end
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

local npAddon = EllesmereUI.Lite.NewAddon("EllesmereUINameplatesInit")
function npAddon:OnInitialize()
    InitDB()
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
    SetupAuraCVars()
    ApplyClassPowerSetting()
    -- Apply spec-assigned preset on login (before UI is opened)
    if ns._ApplySpecPresetFromDB then ns._ApplySpecPresetFromDB() end
end
