local addonName, ns = ...

local math_floor, math_ceil, math_max, math_min, math_abs =
    math.floor, math.ceil, math.max, math.min, math.abs
local string_format = string.format

local oUF = ns.oUF or oUF
local PP = EllesmereUI.PP

-- Per-addon border texture defaults (size key = borderSize 0-4)
do
    local ALL_SIZES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for k in pairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("unitframes", {
        ["glow"] = {
            defaultSize = 1,
            sizes = AllSizes(0, 0, 0, 0),
        },
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
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = AllSizes(1, 1, 0, 0),
        },
    })
end

if not oUF then
    error("EllesmereUIUnitFrames: oUF library not found! Please install oUF to Libraries\\oUF\\ folder.")
    return
end

-- Portrait UNIT_MODEL_CHANGED on eventless frames (TargetTarget) triggers
-- UnitIsUnit which returns secret booleans in protected instances. Rather
-- than patching the global, we unregister the problematic event after oUF
-- sets up eventless frames. See PostCreateTargetTarget below.

-- External lookup for portrait side per frame. Avoids writing custom
-- properties onto oUF frames which taints their secure execution chain.
EllesmereUI._ufPortraitSide = EllesmereUI._ufPortraitSide or setmetatable({}, { __mode = "k" })

local db
local defaults = {
    profile = {
        playerAuras = {
            enabled       = false,
            iconSize      = 32,
            showText      = true,
            textSize      = 11,
            borderSize    = 1,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            noBorderDebuffs = true,
        },
        castbarOpacity = 1.0,
        castbarColor = { r = 0.114, g = 0.655, b = 0.514 },
        portraitMode = "2d",
        portraitStyle = "attached",
        healthBarTexture = "none",
        darkTheme = false,
        player = {
            frameWidth = 181,
            healthHeight = 46,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = -4,
            powerPercentText = "none",
            powerTextFormat = "perpp",
            powerShowPercent = true,
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = true,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            healthDisplay = "both",
            showBuffs = false,
            maxBuffs = 4,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            buffSize = 22,
            buffOffsetX = 0,
            buffOffsetY = 0,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffAnchor = "none",
            debuffGrowth = "auto",
            maxDebuffs = 10,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            namePosition = "left",
            healthTextPosition = "right",
            leftTextContent = "name",
            rightTextContent = "both",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitStyle = "attached",
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "left",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            healthBarOpacity = 90,
            powerBarOpacity = 100,
            showPlayerAbsorb = "none",
            absorbCleanAlpha = 30,
            showPlayerCastbar = false,
            showPlayerCastIcon = true,
            castReverseFill = false,
            castbarHideWhenInactive = true,
            lockCastbarToFrame = true,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 181,
            playerCastbarHeight = 14,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 10,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castSpellNameX = 0,
            castSpellNameY = 0,
            castSpellTargetSize = 11,
            castSpellTargetColor = { r = 1, g = 1, b = 1 },
            castSpellTargetX = 0,
            castSpellTargetY = 0,
            castDurationX = 0,
            castDurationY = 0,
            showCastDuration = true,
            showCastTarget = true,
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            showClassPowerBar = false,
            lockClassPowerToFrame = true,
            classPowerStyle = "none",
            classPowerPosition = "top",
            classPowerBarX = 0,
            classPowerBarY = 0,
            classPowerSize = 8,
            classPowerSpacing = 2,
            classPowerClassColor = true,
            classPowerCustomColor = { r = 1, g = 0.82, b = 0 },
            classPowerBgColor = { r = 0.082, g = 0.082, b = 0.082, a = 1.0 },
            classPowerEmptyColor = { r = 0.2, g = 0.2, b = 0.2, a = 1.0 },
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            combatIndicatorStyle = "class",
            combatIndicatorColor = "custom",
            combatIndicatorCustomColor = { r = 1, g = 1, b = 1 },
            combatIndicatorPosition = "healthbar",
            combatIndicatorSize = 22,
            combatIndicatorX = 0,
            combatIndicatorY = 0,
            showInRaid = true,
            showInParty = true,
            showSolo = true,
            barVisibility = "always",
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            raidMarkerEnabled = false,
            raidMarkerSize = 28,
            raidMarkerAlign = "right",
            raidMarkerX = 0,
            raidMarkerY = 0,
            leaderIndicatorEnabled = true,
            leaderIndicatorSize = 16,
            leaderIndicatorPosition = "topleft",
            leaderIndicatorX = 0,
            leaderIndicatorY = 0,
            healthReverseFill = false,
            powerReverseFill = false,
        },
        target = {
            frameWidth = 181,
            healthHeight = 46,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = -4,
            powerPercentText = "none",
            powerTextFormat = "perpp",
            powerShowPercent = true,
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = true,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            castbarHeight = 14,
            castbarWidth = 181,
            showCastbar = true,
            showCastIcon = true,
            castReverseFill = false,
            castbarHideWhenInactive = true,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 10,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castSpellNameX = 0,
            castSpellNameY = 0,
            castSpellTargetSize = 11,
            castSpellTargetColor = { r = 1, g = 1, b = 1 },
            castSpellTargetX = 0,
            castSpellTargetY = 0,
            castDurationX = 0,
            castDurationY = 0,
            showCastDuration = true,
            showCastTarget = true,
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            healthDisplay = "both",
            showBuffs = true,
            onlyPlayerDebuffs = false,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            maxBuffs = 4,
            maxDebuffs = 20,
            buffSize = 22,
            buffOffsetX = 0,
            buffOffsetY = 0,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            namePosition = "left",
            healthTextPosition = "right",
            leftTextContent = "name",
            rightTextContent = "both",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitStyle = "attached",
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            healthBarOpacity = 90,
            powerBarOpacity = 100,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            showInRaid = true,
            showInParty = true,
            showSolo = true,
            barVisibility = "always",
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            raidMarkerEnabled = false,
            raidMarkerSize = 28,
            raidMarkerAlign = "right",
            raidMarkerX = 0,
            raidMarkerY = 0,
            leaderIndicatorEnabled = true,
            leaderIndicatorSize = 16,
            leaderIndicatorPosition = "topleft",
            leaderIndicatorX = 0,
            leaderIndicatorY = 0,
            healthReverseFill = false,
            powerReverseFill = false,
        },
        playerTarget = {
            frameWidth = 181,
            healthHeight = 46,
            powerHeight = 6,
            powerY = -4,
            powerPercentText = "none",
            powerTextFormat = "perpp",
            powerShowPercent = true,
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = true,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            castbarHeight = 14,
            maxBuffs = 4,
            maxDebuffs = 20,
            buffSize = 22,
            buffOffsetX = 0,
            buffOffsetY = 0,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            healthDisplay = "both",
            showBuffs = true,
            onlyPlayerDebuffs = false,
            showPlayerAbsorb = "none",
            absorbCleanAlpha = 30,
            showPlayerCastbar = false,
            showClassPowerBar = false,
            classPowerBarX = 0,
            classPowerBarY = 0,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 181,
            playerCastbarHeight = 14,
            healthReverseFill = false,
            powerReverseFill = false,
        },
        totPet = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            showPortrait = false,
            portraitSide = "left",
            portraitMode = "2d",
            healthBarOpacity = 90,
            textSize = 12,
            leftTextContent = "name",
            leftTextClassColor = false,
            leftTextColorR = 1, leftTextColorG = 1, leftTextColorB = 1,
            leftTextX = 0, leftTextY = 0,
            rightTextContent = "none",
            rightTextClassColor = false,
            rightTextColorR = 1, rightTextColorG = 1, rightTextColorB = 1,
            rightTextX = 0, rightTextY = 0,
            centerTextContent = "none",
            centerTextClassColor = false,
            centerTextColorR = 1, centerTextColorG = 1, centerTextColorB = 1,
            centerTextX = 0, centerTextY = 0,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
            healthReverseFill = false,
        },
        pet = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            showPortrait = false,
            portraitSide = "left",
            portraitMode = "2d",
            healthBarOpacity = 90,
            textSize = 12,
            leftTextContent = "name",
            leftTextClassColor = false,
            leftTextColorR = 1, leftTextColorG = 1, leftTextColorB = 1,
            leftTextX = 0, leftTextY = 0,
            rightTextContent = "none",
            rightTextClassColor = false,
            rightTextColorR = 1, rightTextColorG = 1, rightTextColorB = 1,
            rightTextX = 0, rightTextY = 0,
            centerTextContent = "none",
            centerTextClassColor = false,
            centerTextColorR = 1, centerTextColorG = 1, centerTextColorB = 1,
            centerTextX = 0, centerTextY = 0,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
            healthReverseFill = false,
        },
        focus = {
            frameWidth = 160,
            healthHeight = 34,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = -4,
            powerPercentText = "none",
            powerTextFormat = "perpp",
            powerShowPercent = true,
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = true,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            castbarHeight = 14,
            castbarWidth = 160,
            showCastbar = true,
            showCastIcon = true,
            castReverseFill = false,
            castbarHideWhenInactive = true,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 10,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castSpellNameX = 0,
            castSpellNameY = 0,
            castSpellTargetSize = 11,
            castSpellTargetColor = { r = 1, g = 1, b = 1 },
            castSpellTargetX = 0,
            castSpellTargetY = 0,
            castDurationX = 0,
            castDurationY = 0,
            showCastDuration = true,
            showCastTarget = true,
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            healthDisplay = "perhp",
            leftTextContent = "name",
            rightTextContent = "perhp",
            leftTextSize = 12,
            leftTextX = 0,
            leftTextY = 0,
            rightTextSize = 12,
            rightTextX = 0,
            rightTextY = 0,
            leftTextClassColor = false,
            rightTextClassColor = false,
            centerTextContent = "none",
            centerTextSize = 12,
            centerTextX = 0,
            centerTextY = 0,
            centerTextClassColor = false,
            bottomTextBar = false,
            bottomTextBarHeight = 16,
            btbPosition = "bottom",
            btbWidth = 0,
            btbX = 0,
            btbY = 0,
            btbLeftContent = "none",
            btbLeftSize = 11,
            btbLeftX = 0,
            btbLeftY = 0,
            btbLeftClassColor = false,
            btbLeftPowerColor = false,
            btbRightContent = "none",
            btbRightSize = 11,
            btbRightX = 0,
            btbRightY = 0,
            btbRightClassColor = false,
            btbRightPowerColor = false,
            btbCenterContent = "none",
            btbCenterSize = 11,
            btbCenterX = 0,
            btbCenterY = 0,
            btbCenterClassColor = false,
            btbCenterPowerColor = false,
            btbClassIcon = "none",
            btbClassIconSize = 14,
            btbClassIconLocation = "left",
            btbClassIconX = 0,
            btbClassIconY = 0,
            showPortrait = true,
            portraitStyle = "attached",
            portraitMode = "2d",
            classThemeStyle = "modern",
            portraitSide = "right",
            portraitSize = 0,
            portraitX = 0,
            portraitY = 0,
            detachedPortraitShape = "portrait",
            detachedPortraitBorderColor = { r = 0, g = 0, b = 0 },
            detachedPortraitClassColor = true,
            detachedPortraitBorder = true,
            detachedPortraitBorderOpacity = 100,
            detachedPortraitBorderSize = 7,
            btbBgColor = { r = 0.2, g = 0.2, b = 0.2 },
            btbBgOpacity = 1.0,
            healthBarOpacity = 90,
            powerBarOpacity = 100,
            showPlayerAbsorb = "none",
            absorbCleanAlpha = 30,
            onlyPlayerDebuffs = true,
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            maxDebuffs = 10,
            showBuffs = false,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            maxBuffs = 4,
            buffSize = 22,
            buffOffsetX = 0,
            buffOffsetY = 0,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            textSize = 12,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            showInRaid = true,
            showInParty = true,
            showSolo = true,
            barVisibility = "always",
            visHideHousing = false,
            visOnlyInstances = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            raidMarkerEnabled = false,
            raidMarkerSize = 28,
            raidMarkerAlign = "right",
            raidMarkerX = 0,
            raidMarkerY = 0,
            healthReverseFill = false,
            powerReverseFill = false,
        },
        boss = {
            frameWidth = 160,
            healthHeight = 34,
            powerHeight = 6,
            powerPosition = "below",
            powerWidth = 0,
            powerX = 0,
            powerY = -4,
            powerPercentText = "none",
            powerTextFormat = "perpp",
            powerShowPercent = true,
            powerPercentSize = 9,
            powerPercentX = 0,
            powerPercentY = 0,
            powerPercentPowerColor = true,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            castbarHeight = 14,
            showCastbar = true,
            showCastIcon = true,
            castReverseFill = false,
            castbarHideWhenInactive = true,
            castSpellNameSize = 11,
            castSpellNameColor = { r = 1, g = 1, b = 1 },
            castDurationSize = 10,
            castDurationColor = { r = 1, g = 1, b = 1 },
            castSpellNameX = 0,
            castSpellNameY = 0,
            castSpellTargetSize = 11,
            castSpellTargetColor = { r = 1, g = 1, b = 1 },
            castSpellTargetX = 0,
            castSpellTargetY = 0,
            castDurationX = 0,
            castDurationY = 0,
            showCastDuration = true,
            showCastTarget = false,
            castbarFillColor = { r = 0.863, g = 0.820, b = 0.639 },
            castbarClassColored = false,
            healthDisplay = "perhp",
            showPortrait = false,
            portraitSide = "right",
            portraitMode = "2d",
            healthBarOpacity = 90,
            powerBarOpacity = 100,
            onlyPlayerDebuffs = true,
            debuffAnchor = "bottomleft",
            debuffGrowth = "auto",
            maxDebuffs = 10,
            showBuffs = false,
            buffAnchor = "topleft",
            buffGrowth = "auto",
            maxBuffs = 4,
            buffSize = 22,
            buffOffsetX = 0,
            buffOffsetY = 0,
            debuffSize = 22,
            debuffOffsetX = 0,
            debuffOffsetY = 0,
            buffShowCooldownText = false,
            buffCooldownTextSize = 10,
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            simpleDebuffShowCooldownText = false,
            simpleDebuffCooldownTextSize = 14,
            simpleDebuffs = true,  -- forces Left anchor + frame-height-matched debuff size
            textSize = 12,
            leftTextContent = "name",
            leftTextClassColor = false,
            leftTextColorR = 1, leftTextColorG = 1, leftTextColorB = 1,
            leftTextX = 0, leftTextY = 0,
            rightTextContent = "perhp",
            rightTextClassColor = false,
            rightTextColorR = 1, rightTextColorG = 1, rightTextColorB = 1,
            rightTextX = 0, rightTextY = 0,
            centerTextContent = "none",
            centerTextClassColor = false,
            centerTextColorR = 1, centerTextColorG = 1, centerTextColorB = 1,
            centerTextX = 0, centerTextY = 0,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            raidMarkerEnabled = true,
            raidMarkerSize = 28,
            raidMarkerAlign = "left",
            raidMarkerX = 0,
            raidMarkerY = 0,
            healthReverseFill = false,
        },
        enabledFrames = {
            player = true,
            target = true,
            focus = true,
            pet = true,
            targettarget = true,
            focustarget = false,
            boss = true,
        },
        positions = {
            player = { point = "CENTER", relPoint = "CENTER", x = -317, y = -193.5 },
            target = { point = "CENTER", relPoint = "CENTER", x = 317, y = -201 },
            focus = { point = "CENTER", relPoint = "CENTER", x = 0, y = -285 },
            pet = { point = "CENTER", relPoint = "CENTER", x = -300, y = -260 },
            targettarget = { point = "CENTER", relPoint = "CENTER", x = 383, y = -152.5 },
            focustarget = { point = "CENTER", relPoint = "CENTER", x = 50, y = -261 },
            boss = { point = "CENTER", relPoint = "CENTER", x = 661, y = 251 },
            classPower = { point = "CENTER", relPoint = "CENTER", x = 0, y = -220 },
        },
        bossSpacing = 80,
    }
}
local frames = {}
local SpecHasClassPower  -- forward declaration; defined after CLASS_POWER_TYPES

local CASTBAR_COLOR = { r = 0.114, g = 0.655, b = 0.514 }
local function GetCastbarColor()
    if db and db.profile and db.profile.castbarColor then
        return db.profile.castbarColor
    end
    return CASTBAR_COLOR
end
local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }

-- Locale system font override: for CJK/Cyrillic clients, bypass all custom
-- fonts and use the WoW built-in font that supports the locale's glyphs.
local LOCALE_FONT_OVERRIDE = EllesmereUI and EllesmereUI.LOCALE_FONT_FALLBACK

local cachedFontPath = LOCALE_FONT_OVERRIDE or (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local cachedFontPaths = {}  -- per-unit font cache
local function ResolveFontPath(unitKey)
    -- Locale override takes absolute priority ? no custom font can render CJK/Cyrillic
    if LOCALE_FONT_OVERRIDE then
        cachedFontPath = LOCALE_FONT_OVERRIDE
        for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "totPet"}) do
            cachedFontPaths[uKey] = LOCALE_FONT_OVERRIDE
        end
        return
    end
    -- Global font system
    local gPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    cachedFontPath = gPath
    for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "totPet"}) do
        cachedFontPaths[uKey] = gPath
    end
end

local function GetSelectedFont(unitKey)
    if unitKey and cachedFontPaths[unitKey] then
        return cachedFontPaths[unitKey]
    end
    return cachedFontPath
end

local function GetUFUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("unitFrames")
end

local function SetFSFont(fs, size, flags)
  if not (fs and fs.SetFont) then return end
  local f = flags or (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("unitFrames")) or ""
  fs:SetFont(GetSelectedFont(), size or 12, f)
  if f == "" then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
  else
    fs:SetShadowOffset(0, 0)
  end
end

-- Disable WoW's automatic pixel snapping on a texture (prevents sub-pixel jitter)
local function UnsnapTex(tex)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.DisablePixelSnap(tex)
    elseif tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
end

-- Health bar texture overlay lookup
local TEXTURE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local healthBarTextures = {
    ["none"]          = nil,
    ["melli"]         = TEXTURE_BASE .. "melli.tga",
    ["beautiful"]     = TEXTURE_BASE .. "beautiful.tga",
    ["plating"]       = TEXTURE_BASE .. "plating.tga",
    ["atrocity"]      = TEXTURE_BASE .. "atrocity.tga",
    ["divide"]        = TEXTURE_BASE .. "divide.tga",
    ["glass"]         = TEXTURE_BASE .. "glass.tga",
    ["fade-right"]    = TEXTURE_BASE .. "fade-right.tga",
    ["thin-line-top"]    = TEXTURE_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = TEXTURE_BASE .. "thin-line-bottom.tga",
    ["fade"]          = TEXTURE_BASE .. "fade.tga",
    ["gradient-lr"]   = TEXTURE_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TEXTURE_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TEXTURE_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TEXTURE_BASE .. "gradient-tb.tga",
    ["matte"]         = TEXTURE_BASE .. "matte.tga",
    ["sheer"]         = TEXTURE_BASE .. "sheer.tga",
}
local healthBarTextureOrder = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local healthBarTextureNames = {
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
}
ns.healthBarTextures = healthBarTextures
ns.healthBarTextureOrder = healthBarTextureOrder
ns.healthBarTextureNames = healthBarTextureNames

-- Map a WoW unit ID ("player", "target", "boss1", "targettarget", etc.)
-- to the settings sub-table key in db.profile.
local function UnitToSettingsKey(unit)
    if not unit then return nil end
    if unit:match("^boss%d$") then return "boss" end
    if unit == "targettarget" or unit == "focustarget" then return "totPet" end
    if unit == "pet" then return "pet" end
    if db.profile[unit] then return unit end
    return nil
end

local function ApplyHealthBarTexture(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local texKey = (s and s.healthBarTexture) or db.profile.healthBarTexture or "none"
    local path   = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    health:SetStatusBarTexture(path)
    local hFill = health:GetStatusBarTexture()
    if hFill then UnsnapTex(hFill) end

    -- Power bar: same texture. Walk up from health to find the oUF frame
    -- (health may be parented to a clip container, not the oUF frame directly).
    local frame = health:GetParent()
    if frame and not frame.Power and frame:GetParent() then
        frame = frame:GetParent()
    end
    local power = frame and frame.Power
    if power then
        if path then
            power:SetStatusBarTexture(path)
        else
            power:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end
        local pFill = power:GetStatusBarTexture()
        if pFill then UnsnapTex(pFill) end
    end
end

-------------------------------------------------------------------------------
--  Health Bar Opacity ? controls the overall alpha of the health bar fill
-------------------------------------------------------------------------------
local function ApplyHealthBarAlpha(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.healthBarOpacity or 90) or 90
    -- Handle old profiles that stored opacity as a 0-1 float instead of 0-100 int
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = health:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(fillA) end
    if health.bg then health.bg:SetAlpha(fillA) end
end

-------------------------------------------------------------------------------
--  Power Bar Opacity ? controls the overall alpha of the power bar
-------------------------------------------------------------------------------
local function ApplyPowerBarAlpha(power, unitKey)
    if not power then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.powerBarOpacity or 100) or 100
    -- Handle old profiles that stored opacity as a 0-1 float instead of 0-100 int
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = power:GetStatusBarTexture()
    if fillTex then fillTex:SetAlpha(fillA) end
    if power.bg then power.bg:SetAlpha(fillA) end
end

-------------------------------------------------------------------------------
--  Dark Mode ? flat dark health bar with gray background
-------------------------------------------------------------------------------
local DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B = 0x11/255, 0x11/255, 0x11/255  -- #111111
local DARK_HEALTH_A = 1.0
local DARK_BG_R, DARK_BG_G, DARK_BG_B = 0x4f/255, 0x4f/255, 0x4f/255  -- #4f4f4f

local function ApplyDarkTheme(health)
    if not health then return end
    local isDark = db and db.profile and db.profile.darkTheme
    if isDark then
        health.colorClass = false
        health.colorReaction = false
        health.colorTapped = false
        health.colorDisconnected = false
        health:SetStatusBarColor(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, DARK_HEALTH_A)
        local darkFillTex = health:GetStatusBarTexture()
        if darkFillTex then darkFillTex:SetAlpha(0.9) end
        if health.bg then
            -- Anchor bg to only cover the empty (missing-health) portion so the
            -- bar opacity fill shows the world behind it, not the bg color.
            health.bg:ClearAllPoints()
            health.bg:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
            health.bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            health.bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
            health.bg:SetAlpha(1)
        end
        -- PostUpdateColor: re-apply dark color after oUF tries to class-color,
        -- and re-anchor bg to track the fill edge.
        -- Alpha is NOT re-applied here ? SetStatusBarColor(r,g,b) with 3 args
        -- preserves existing texture alpha, so the alpha set by
        -- ApplyHealthBarAlpha persists through oUF recolors.
        health.PostUpdateColor = function(self)
            self:SetStatusBarColor(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, DARK_HEALTH_A)
            if self.bg then
                self.bg:ClearAllPoints()
                self.bg:SetPoint("TOPLEFT", self:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                self.bg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
            end
        end
    else
        health.colorClass = true
        health.colorReaction = true
        health.colorTapped = true
        health.colorDisconnected = true
        -- Check for custom fill/bg colors on this unit
        local unitKey = health._euiUnitKey
        local unitSettings = unitKey and db.profile[unitKey]
        local customFill = unitSettings and unitSettings.customFillColor
        local customBg   = unitSettings and unitSettings.customBgColor
        if customFill then
            -- Custom fill overrides class coloring; skip if class color is enabled
            if not (unitSettings and unitSettings.healthClassColored) then
                health.colorClass = false
                health.colorReaction = false
                health.colorTapped = false
                health.colorDisconnected = false
                health:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
            end
        end
        -- Tint bg to 20% of the class/reaction color, or use custom bg color.
        -- Alpha is NOT re-applied ? SetStatusBarColor(r,g,b) preserves
        -- existing texture alpha through oUF recolors.
        health.PostUpdateColor = function(self, _, color)
            local uKey = self._euiUnitKey
            local uSettings = uKey and db.profile[uKey]
            local cFill = uSettings and uSettings.customFillColor
            local cBg   = uSettings and uSettings.customBgColor
            local classColored = uSettings and uSettings.healthClassColored
            if cFill and not classColored then
                self:SetStatusBarColor(cFill.r, cFill.g, cFill.b)
            end
            if self.bg then
                if cBg then
                    self.bg:SetColorTexture(cBg.r, cBg.g, cBg.b, 1)
                elseif cFill and not classColored then
                    self.bg:SetColorTexture(cFill.r * 0.2, cFill.g * 0.2, cFill.b * 0.2, 1)
                elseif color and color.GetRGB then
                    local r, g, b = color:GetRGB()
                    self.bg:SetColorTexture(r * 0.2, g * 0.2, b * 0.2, 1)
                else
                    -- No color source available (e.g. no target) -- use default bg
                    self.bg:SetColorTexture(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, 1)
                end
            end
        end
        if health.bg then
            -- Restore bg to cover the full bar area
            health.bg:ClearAllPoints()
            PP.Point(health.bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
            PP.Point(health.bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            if customBg then
                health.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
            elseif customFill then
                health.bg:SetColorTexture(customFill.r * 0.2, customFill.g * 0.2, customFill.b * 0.2, 1)
            else
                -- No custom colors set -- use default dark bg (#111)
                health.bg:SetColorTexture(DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B, 1)
            end
        end
    end
end
ns.ApplyDarkTheme = ApplyDarkTheme

-- Smart power text: percent for healers/prot pally/arcane mage, numeric for everyone else.
-- Shared helper used by both the oUF tag and the resource bars renderer.
local function EUI_IsSmartPowerPercent()
    local _, cls = UnitClass("player")
    if not cls then return false end
    -- Druids: Restoration always uses percent (mana healer, % is always
    -- what matters -- including Incarnation: Tree of Life, which lands on
    -- a form index that varies by spec/talent loadout). Other specs use
    -- percent in caster/travel form and raw value in cat/bear.
    if cls == "DRUID" then
        local spec = GetSpecialization()
        if spec == 4 then return true end
        local form = GetShapeshiftForm()
        return form == nil or form == 0 or form == 3
    end
    if cls == "PRIEST" or cls == "SHAMAN" or cls == "MONK" then
        return true
    end
    -- Paladin: Holy and Protection (mana-based specs)
    if cls == "PALADIN" then
        local spec = GetSpecialization()
        return spec == 1 or spec == 2  -- Holy, Protection
    end
    -- Mage: only Arcane
    if cls == "MAGE" then
        local spec = GetSpecialization()
        return spec == 1  -- Arcane
    end
    -- Evoker: only Preservation
    if cls == "EVOKER" then
        local spec = GetSpecialization()
        return spec == 2  -- Preservation
    end
    return false
end
ns.EUI_IsSmartPowerPercent = EUI_IsSmartPowerPercent
EllesmereUI.IsSmartPowerPercent = EUI_IsSmartPowerPercent

do
  local tagName = "curhpshort"
  local function AbbrevHP(unit)
    if not unit or not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if UnitIsDeadOrGhost(unit) then return "DEAD" end
    local hp = UnitHealth(unit) or 0
    return AbbreviateNumbers(hp)
  end

  oUF.Tags.Methods[tagName] = AbbrevHP
  oUF.Tags.Events[tagName] = "UNIT_HEALTH UNIT_MAXHEALTH"
end

do
  oUF.Tags.Methods["perhpnosign"] = function(unit)
    if not unit or not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if UnitIsDeadOrGhost(unit) then return "DEAD" end
    local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    if not pct then return "0" end
    return string_format("%d", pct)
  end
  oUF.Tags.Events["perhpnosign"] = "UNIT_HEALTH UNIT_MAXHEALTH"
end

-- Resolved power type per unit. Updated by GetDisplayPower override so
-- tags match the power bar when powerTypeOverride is active (e.g. Balance
-- Druid showing Mana instead of Astral Power).
_G._EUI_ResolvedPowerType = _G._EUI_ResolvedPowerType or {}

-- eui-perpp: power percent using resolved power type (runs in oUF _PROXY env)
oUF.Tags.Methods["eui-perpp"] = [[function(u)
    local pType = _EUI_ResolvedPowerType[u] or UnitPowerType(u)
    return string.format('%d', UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100))
end]]
oUF.Tags.Events["eui-perpp"] = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"

-- eui-curpp: current power as abbreviated number
oUF.Tags.Methods["eui-curpp"] = [[function(u)
    local pType = _EUI_ResolvedPowerType[u] or UnitPowerType(u)
    return AbbreviateNumbers(UnitPower(u, pType))
end]]
oUF.Tags.Events["eui-curpp"] = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"

local optionsFrame
local optionsCategoryID
_G.EllesmereUF_StylesRegistered = _G.EllesmereUF_StylesRegistered or false

local unitSettingsMap
local function GetSettingsForUnit(unit)
    if not unitSettingsMap then
        unitSettingsMap = {
            player = db.profile.player,
            target = db.profile.target,
            targettarget = db.profile.totPet,
            pet = db.profile.pet,
            focus = db.profile.focus,
            focustarget = db.profile.totPet,
        }
        for i = 1, 5 do
            unitSettingsMap["boss" .. i] = db.profile.boss
        end
    end
    return unitSettingsMap[unit] or db.profile.player
end

-- Returns the donor settings table for mini frames (focus ? target ? player)
-- Used to inherit border, texture, and font settings
local function GetMiniDonorSettings()
    local ef = db.profile.enabledFrames
    if ef.focus ~= false and db.profile.focus then return db.profile.focus end
    if ef.target ~= false and db.profile.target then return db.profile.target end
    return db.profile.player
end

-- Resolve buff anchor + growth direction into oUF aura properties
-- Returns: anchorPoint (on frame), initialAnchor, growthX, growthY, offsetX, offsetY
-- initialAnchor is ALWAYS derived from the anchor position (first icon pinned to anchor corner).
-- Growth direction only affects where icons 2+ are placed.
-- oUF's Aura element tiles icons in a grid using `element.maxCols` as the
-- per-row count (falls back to element:GetWidth() / iconSize if nil).
-- For explicit vertical growth ("up" / "down") the user expects a single
-- column, so maxCols = 1. For explicit horizontal growth ("left" / "right")
-- a single row is expected, so maxCols must be large enough that icons
-- never wrap. "auto" or anything else returns nil so oUF keeps its default
-- width-based grid.
local function AuraMaxCols(growth, maxCount)
    if growth == "up" or growth == "down" then
        return 1
    elseif growth == "left" or growth == "right" then
        return math.max(maxCount or 1, 100)
    end
    return nil
end

local function ResolveBuffLayout(anchor, growth)
    anchor = anchor or "topleft"
    growth = growth or "auto"

    -- initialAnchor: first icon always starts at the anchor corner
    local iaMap = {
        topleft     = "BOTTOMLEFT",
        topright    = "BOTTOMRIGHT",
        bottomleft  = "TOPLEFT",
        bottomright = "TOPRIGHT",
        left        = "BOTTOMRIGHT",
        right       = "BOTTOMLEFT",
    }
    local ia = iaMap[anchor] or "BOTTOMLEFT"

    -- Auto growth rules: determines where icons 2+ go
    local autoMap = {
        topleft     = { gx = "RIGHT", gy = "UP" },
        topright    = { gx = "LEFT",  gy = "UP" },
        bottomleft  = { gx = "RIGHT", gy = "DOWN" },
        bottomright = { gx = "LEFT",  gy = "DOWN" },
        left        = { gx = "LEFT",  gy = "DOWN" },
        right       = { gx = "RIGHT", gy = "DOWN" },
    }

    local gx, gy
    if growth == "auto" then
        local a = autoMap[anchor] or autoMap.topleft
        gx, gy = a.gx, a.gy
    elseif growth == "right" then
        gx, gy = "RIGHT", "UP"
    elseif growth == "left" then
        gx, gy = "LEFT", "UP"
    elseif growth == "up" then
        gx, gy = "RIGHT", "UP"
    elseif growth == "down" then
        gx, gy = "RIGHT", "DOWN"
    else
        gx, gy = "RIGHT", "UP"
    end

    -- Map anchor to frame attachment point and offset direction
    -- fp = point on the PARENT frame where the buffs container attaches
    local fpMap = {
        topleft     = { fp = "TOPLEFT",     ox = 0,  oy = 1 },
        topright    = { fp = "TOPRIGHT",    ox = 0,  oy = 1 },
        bottomleft  = { fp = "BOTTOMLEFT",  ox = 0,  oy = -1 },
        bottomright = { fp = "BOTTOMRIGHT", ox = 0,  oy = -1 },
        left        = { fp = "LEFT",         ox = -1, oy = 0 },
        right       = { fp = "RIGHT",        ox = 1,  oy = 0 },
    }
    local m = fpMap[anchor] or fpMap.topleft
    return m.fp, ia, gx, gy, m.ox, m.oy
end

local function GetPlayerTargetHealthTag(unit)
    local tbl = (unit == "target") and db.profile.target or db.profile.player
    local display = tbl.healthDisplay or "both"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "perhp" then
        return "[perhp]%"
    else
        return "[curhpshort] | [perhp]%"
    end
end

local function GetFocusHealthTag()
    local display = db.profile.focus.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [perhp]%"
    else
        return "[perhp]%"
    end
end

local function GetBossHealthTag()
    local display = db.profile.boss.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [perhp]%"
    else
        return "[perhp]%"
    end
end

-- Resolve a leftTextContent / rightTextContent value to an oUF tag string.
-- content: "name", "both", "curhpshort", "perhp", "perhpnosign", "perhpnum", "none"
local function ContentToTag(content)
    if content == "name" then return "[name]"
    elseif content == "both" then return "[curhpshort] | [perhp]%"
    elseif content == "perhpnum" then return "[perhp]% | [curhpshort]"
    elseif content == "curhpshort" then return "[curhpshort]"
    elseif content == "perhp" then return "[perhp]%"
    elseif content == "perhpnosign" then return "[perhpnosign]"
    elseif content == "perpp" then return "[perpp]%"
    elseif content == "curpp" then return "[curpp]"
    elseif content == "curhp_curpp" then return "[curhpshort] | [curpp]"
    elseif content == "perhp_perpp" then return "[perhp]% | [perpp]%"
    else return nil end
end

-- Estimate pixel width of a text content type for name truncation.
-- Flat pixel assumptions matching the nameplate system.
local UF_TEXT_PADDING = 10
local ufTextWidths = {
    both        = 75,  -- "132 K | 86%"
    perhpnum    = 75,  -- "86% | 132 K"
    curhpshort  = 38,  -- "132 K"
    perhp       = 38,  -- "86%"
    perhpnosign = 30,  -- "86"
    perpp       = 38,  -- "86%"
    curpp       = 38,  -- "132"
    curhp_curpp = 75,  -- "132 K | 132"
    perhp_perpp = 75,  -- "86% | 86%"
}
local function EstimateUFTextWidth(content)
    return (ufTextWidths[content] or 0) + UF_TEXT_PADDING
end

-- Apply class color to a FontString based on the unit
local function ApplyClassColor(fs, unit, useClassColor, customR, customG, customB)
    if not fs then return end
    if useClassColor then
        local _, class = UnitClass(unit)
        if class then
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if c then fs:SetTextColor(c.r, c.g, c.b); return end
        end
    end
    fs:SetTextColor(customR or 1, customG or 1, customB or 1)
end

local UF_ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CLASS_FULL_SPRITE_BASE = UF_ICONS_PATH .. "class-full\\"
local CLASS_FULL_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- Helper: apply class icon from sprite sheet
local function ApplyClassIconTexture(tex, classToken, style)
    local coords = CLASS_FULL_COORDS[classToken]
    if not coords then return false end
    tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    return true
end


-- Portrait mask and border paths for detached portrait shapes
local PORTRAIT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local PORTRAIT_MASKS = {
    portrait = PORTRAIT_MEDIA .. "portrait_mask.tga",
    circle   = PORTRAIT_MEDIA .. "circle_mask.tga",
    square   = PORTRAIT_MEDIA .. "square_mask.tga",
    csquare  = PORTRAIT_MEDIA .. "csquare_mask.tga",
    diamond  = PORTRAIT_MEDIA .. "diamond_mask.tga",
    hexagon  = PORTRAIT_MEDIA .. "hexagon_mask.tga",
    shield   = PORTRAIT_MEDIA .. "shield_mask.tga",
}
local PORTRAIT_BORDERS = {
    portrait = PORTRAIT_MEDIA .. "portrait_border.tga",
    circle   = PORTRAIT_MEDIA .. "circle_border.tga",
    square   = PORTRAIT_MEDIA .. "square_border.tga",
    csquare  = PORTRAIT_MEDIA .. "csquare_border.tga",
    diamond  = PORTRAIT_MEDIA .. "diamond_border.tga",
    hexagon  = PORTRAIT_MEDIA .. "hexagon_border.tga",
    shield   = PORTRAIT_MEDIA .. "shield_border.tga",
}

-- Top pixel inset for each mask shape (px from edge to visible portrait area in 128px mask)
local MASK_INSETS = {
    circle   = 17,
    csquare  = 17,
    diamond  = 14,
    hexagon  = 17,
    portrait = 17,
    shield   = 13,
    square   = 17,
}

-- Apply detached portrait shape (mask + border overlay) to a portrait backdrop.
-- Creates mask/border textures on first call, then updates them.
-- backdrop: the portrait backdrop frame
-- uSettings: per-unit DB table
-- unitToken: the unit this portrait belongs to (e.g. "player", "target")
local function ApplyDetachedPortraitShape(backdrop, uSettings, unitToken)
    -- Mini frames never use detached portraits
    local isMini = unitToken and (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget" or unitToken:match("^boss%d$"))
    local isDetached = not isMini and ((uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached") == "detached"
    local shape = (uSettings and uSettings.detachedPortraitShape) or "portrait"
    local showBorder = true
    local borderOpacity = ((uSettings and uSettings.detachedPortraitBorderOpacity) or 100) / 100
    local borderColor = (uSettings and uSettings.detachedPortraitBorderColor) or { r = 0, g = 0, b = 0 }
    local useClassColor = (uSettings and uSettings.detachedPortraitClassColor) or false
    local rawBorderSize = (uSettings and uSettings.detachedPortraitBorderSize) or 7
    -- Border art is naturally 7px. Scale UP by (7 - rawBorderSize) so the mask
    -- clips the inner portion, leaving rawBorderSize px visible.
    local bExp = 7 - rawBorderSize

    -- Resolve border color (class color overrides manual color)
    local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
    if useClassColor then
        local isDark = db and db.profile and db.profile.darkTheme
        if isDark then
            -- Dark mode: always use the player's own class color
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        elseif unitToken and UnitExists(unitToken) then
            -- Non-dark: use the unit's health bar color (class for players,
            -- reaction for NPCs, tapped grey, etc.)
            local _, classToken = UnitClass(unitToken)
            if UnitIsPlayer(unitToken) and classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            elseif UnitIsTapDenied and UnitIsTapDenied(unitToken) then
                bR, bG, bB = 0.6, 0.6, 0.6
            else
                local reaction = UnitReaction(unitToken, "player")
                if reaction then
                    local c = FACTION_BAR_COLORS[reaction]
                    if c then bR, bG, bB = c.r, c.g, c.b end
                end
            end
        else
            -- Fallback: player class color
            local _, classToken = UnitClass("player")
            if classToken then
                local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classToken]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end
    end

    -- Remove mask when not detached and reset texture positions
    if not isDetached then
        if backdrop._shapeMask then
            if backdrop._2d then backdrop._2d:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._class then backdrop._class:RemoveMaskTexture(backdrop._shapeMask) end
            if backdrop._bg then backdrop._bg:RemoveMaskTexture(backdrop._shapeMask) end
            backdrop._shapeMask:Hide()
        end
        if backdrop._shapeBorderTex then backdrop._shapeBorderTex:Hide() end
        if backdrop._sqBorderTexs then
            for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
        end
        -- Reset texture positions to default (detached mode expands them for mask fill)
        if backdrop._2d then
            backdrop._2d:ClearAllPoints()
            PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        if backdrop._class then
            backdrop._class:ClearAllPoints()
            local bh2 = backdrop:GetHeight()
            if bh2 < 1 then bh2 = 46 end
            local classInset = math.floor(bh2 * 0.08)
            PP.Point(backdrop._class, "TOPLEFT", backdrop, "TOPLEFT", classInset, -classInset)
            PP.Point(backdrop._class, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset, classInset)
        end
        if backdrop._3d then
            backdrop._3d:ClearAllPoints()
            PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
        return
    end

    -- === MASK ===
    local maskPath = PORTRAIT_MASKS[shape]
    if maskPath then
        if not backdrop._shapeMask then
            backdrop._shapeMask = backdrop:CreateMaskTexture()
        end
        -- Inset mask by 1px when border is visible so scaling can't make the
        -- mask edge poke out from behind the border art
        backdrop._shapeMask:ClearAllPoints()
        if rawBorderSize >= 1 then
            PP.Point(backdrop._shapeMask, "TOPLEFT", backdrop, "TOPLEFT", 1, -1)
            PP.Point(backdrop._shapeMask, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)
        else
            backdrop._shapeMask:SetAllPoints(backdrop)
        end
        backdrop._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        backdrop._shapeMask:Show()
        if backdrop._2d then backdrop._2d:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._class then backdrop._class:AddMaskTexture(backdrop._shapeMask) end
        if backdrop._bg then backdrop._bg:AddMaskTexture(backdrop._shapeMask) end
    end

    -- Hide old square border textures if they exist on this frame
    if backdrop._sqBorderTexs then
        for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
    end

    -- === TGA BORDER OVERLAY ===
    if not backdrop._shapeBorderTex then
        backdrop._shapeBorderTex = backdrop:CreateTexture(nil, "OVERLAY")
    end
    backdrop._shapeBorderTex:ClearAllPoints()
    PP.Point(backdrop._shapeBorderTex, "TOPLEFT", backdrop, "TOPLEFT", -bExp, bExp)
    PP.Point(backdrop._shapeBorderTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", bExp, -bExp)
    -- Add border to mask so the mask clips its inner edge
    if backdrop._shapeMask then
        pcall(backdrop._shapeBorderTex.RemoveMaskTexture, backdrop._shapeBorderTex, backdrop._shapeMask)
        backdrop._shapeBorderTex:AddMaskTexture(backdrop._shapeMask)
    end
    if showBorder then
        local borderPath = PORTRAIT_BORDERS[shape]
        if borderPath then
            backdrop._shapeBorderTex:SetTexture(borderPath)
            backdrop._shapeBorderTex:SetVertexColor(bR, bG, bB, borderOpacity)
            backdrop._shapeBorderTex:Show()
        else
            backdrop._shapeBorderTex:Hide()
        end
    else
        backdrop._shapeBorderTex:Hide()
    end

    -- === Content positioning within mask ===
    -- Scale portrait so its visible area fills the mask opening.
    -- MASK_INSETS[shape] = px from mask edge to visible area (in 128px mask).
    -- Content expands to fill mask; border size no longer affects content.
    local insetPx = MASK_INSETS[shape] or 17
    local bw = backdrop:GetWidth()
    local bh2 = backdrop:GetHeight()
    if bw < 1 then bw = 46 end
    if bh2 < 1 then bh2 = 46 end
    local visRatio = (128 - 2 * insetPx) / 128
    local cScale = 1 / visRatio
    -- Apply user art scale (100 = default, stored as percentage)
    local artScale = ((uSettings and uSettings.portraitArtScale) or 100) / 100
    cScale = cScale * artScale
    local expand = (cScale - 1) * 0.5
    local oL = -(expand * bw)
    local oR =  (expand * bw)
    local oT =  (expand * bh2)
    local oB = -(expand * bh2)
    if backdrop._2d then
        backdrop._2d:ClearAllPoints()
        PP.Point(backdrop._2d, "TOPLEFT", backdrop, "TOPLEFT", oL, oT)
        PP.Point(backdrop._2d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", oR, oB)
    end
    if backdrop._class then
        backdrop._class:ClearAllPoints()
        local classInset = math.floor(bh2 * 0.08)
        PP.Point(backdrop._class, "TOPLEFT", backdrop, "TOPLEFT", classInset + oL, -classInset + oT)
        PP.Point(backdrop._class, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset + oR, classInset + oB)
    end
    if backdrop._3d then
        -- 3D models ignore SetClipsChildren, so keep them within the backdrop
        -- bounds. Art scale is not applied to 3D (camera zoom is fixed).
        backdrop._3d:ClearAllPoints()
        PP.Point(backdrop._3d, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(backdrop._3d, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    end
end
-- Create the bottom text bar frame below the health+power area, above the castbar
local function CreateBottomTextBar(frame, unit, settings, anchorFrame, xOffset, overrideWidth)
    local btbH = settings.bottomTextBarHeight or 16
    local btbPos = settings.btbPosition or "bottom"
    local isDetached = (btbPos == "detached_top" or btbPos == "detached_bottom")
    local btbW = isDetached and (settings.btbWidth or 0) or 0
    local totalWidth = (btbW > 0 and isDetached) and btbW or (overrideWidth or settings.frameWidth)

    local btb = CreateFrame("Frame", nil, frame)
    PP.Size(btb, totalWidth, btbH)

    if btbPos == "top" then
        PP.Point(btb, "BOTTOMLEFT", frame.Health or anchorFrame, "TOPLEFT", xOffset or 0, 0)
    elseif btbPos == "detached_top" then
        btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
    elseif btbPos == "detached_bottom" then
        btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
    else -- "bottom"
        PP.Point(btb, "TOPLEFT", anchorFrame, "BOTTOMLEFT", xOffset or 0, 0)
    end

    local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
    local bga = settings.btbBgOpacity or 1.0
    local bg = btb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
    btb.bg = bg

    -- Text overlay (above unified border at frame+10)
    local textOvr = CreateFrame("Frame", nil, btb)
    textOvr:SetAllPoints()
    textOvr:SetFrameLevel(frame:GetFrameLevel() + 15)

    local leftFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftFS, settings.btbLeftSize or 11)
    leftFS:SetWordWrap(false)
    leftFS:SetTextColor(1, 1, 1)
    btb.LeftText = leftFS

    local rightFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightFS, settings.btbRightSize or 11)
    rightFS:SetWordWrap(false)
    rightFS:SetTextColor(1, 1, 1)
    btb.RightText = rightFS

    local centerFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerFS, settings.btbCenterSize or 11)
    centerFS:SetWordWrap(false)
    centerFS:SetTextColor(1, 1, 1)
    btb.CenterText = centerFS

    btb._textOverlay = textOvr

    -- Tag and position the BTB texts
    local function ApplyBTBTextTags(lc, rc, cc)
        local lt = ContentToTag(lc)
        local rt = ContentToTag(rc)
        local ct = ContentToTag(cc)
        if leftFS._curTag then frame:Untag(leftFS); leftFS._curTag = nil end
        if rightFS._curTag then frame:Untag(rightFS); rightFS._curTag = nil end
        if centerFS._curTag then frame:Untag(centerFS); centerFS._curTag = nil end
        if lt then frame:Tag(leftFS, lt); leftFS._curTag = lt end
        if rt then frame:Tag(rightFS, rt); rightFS._curTag = rt end
        if ct then frame:Tag(centerFS, ct); centerFS._curTag = ct end
        if frame.UpdateTags then frame:UpdateTags() end
    end

    local function ApplyBTBTextPositions(s)
        local lc = s.btbLeftContent or "none"
        local rc = s.btbRightContent or "none"
        local cc = s.btbCenterContent or "none"
        local lsz = s.btbLeftSize or 11
        local rsz = s.btbRightSize or 11
        local csz = s.btbCenterSize or 11

        SetFSFont(leftFS, lsz)
        leftFS:ClearAllPoints()
        if lc ~= "none" then
            leftFS:SetJustifyH("LEFT")
            PP.Point(leftFS, "LEFT", textOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
            leftFS:Show()
        else leftFS:Hide() end

        SetFSFont(rightFS, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            PP.Point(rightFS, "RIGHT", textOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
            rightFS:Show()
        else rightFS:Hide() end

        SetFSFont(centerFS, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            PP.Point(centerFS, "CENTER", textOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
            centerFS:Show()
        else centerFS:Hide() end

        ApplyClassColor(leftFS, unit, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB)
        ApplyClassColor(rightFS, unit, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB)
        ApplyClassColor(centerFS, unit, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB)
        -- Power color overrides (applied after class color, takes priority for power-related text)
        local function ApplyBTBPowerColor(fs, contentKey, usePowerColor)
            if not fs or not usePowerColor then return end
            if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
                local pType = UnitPowerType(unit)
                local info = PowerBarColor[pType]
                if info then
                    fs:SetTextColor(info.r, info.g, info.b)
                end
            end
        end
        ApplyBTBPowerColor(leftFS, lc, s.btbLeftPowerColor)
        ApplyBTBPowerColor(rightFS, rc, s.btbRightPowerColor)
        ApplyBTBPowerColor(centerFS, cc, s.btbCenterPowerColor)
    end

    ApplyBTBTextTags(
        settings.btbLeftContent or "none",
        settings.btbRightContent or "none",
        settings.btbCenterContent or "none"
    )
    ApplyBTBTextPositions(settings)

    btb._applyBTBTextTags = ApplyBTBTextTags
    btb._applyBTBTextPositions = ApplyBTBTextPositions

    -- Class icon overlay ? on a high-level frame so it renders above the border
    local classIconHolder = CreateFrame("Frame", nil, frame)
    classIconHolder:SetAllPoints(textOvr)
    classIconHolder:SetFrameLevel(frame:GetFrameLevel() + 12)
    local classIconTex = classIconHolder:CreateTexture(nil, "ARTWORK")
    classIconTex:SetTexCoord(0, 1, 0, 1)
    classIconTex:Hide()
    btb.ClassIcon = classIconTex

    local function ApplyBTBClassIcon(s)
        local style = s.btbClassIcon or "none"
        if style == "none" then classIconTex:Hide(); return end
        local _, classToken = UnitClass(unit)
        if not classToken then classIconTex:Hide(); return end
        if not ApplyClassIconTexture(classIconTex, classToken, style) then classIconTex:Hide(); return end
        local sz = s.btbClassIconSize or 14
        PP.Size(classIconTex, sz, sz)
        classIconTex:ClearAllPoints()
        local loc = s.btbClassIconLocation or "left"
        local ox = s.btbClassIconX or 0
        local oy = s.btbClassIconY or 0
        if loc == "center" then
            PP.Point(classIconTex, "CENTER", textOvr, "CENTER", ox, oy)
        elseif loc == "right" then
            PP.Point(classIconTex, "RIGHT", textOvr, "RIGHT", -3 + ox, oy)
        else
            PP.Point(classIconTex, "LEFT", textOvr, "LEFT", 3 + ox, oy)
        end
        classIconTex:Show()
    end

    ApplyBTBClassIcon(settings)
    btb._applyBTBClassIcon = ApplyBTBClassIcon

    return btb
end

-- SetFrameMovable removed � positioning is now handled by Unlock Mode

local function ApplyFramePosition(frame, unit)
    if not frame or not db.profile.positions[unit] then return end
    local pos = db.profile.positions[unit]
    local x, y = pos.x, pos.y
    -- Snap to physical pixel grid so positions are deterministic across reloads.
    -- For CENTER-anchored frames, use SnapCenterForDim with the frame's actual
    -- width/height: this preserves the +0.5 center offset that odd-pixel-dim
    -- frames need so their edges land on whole pixels (plain SnapForES rounds
    -- the center to whole pixels and forces edges to half pixels, causing
    -- 1px drift on save & exit / spec swap / profile change).
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and x and y then
        local es = frame:GetEffectiveScale()
        local isCenterAnchor = (pos.point == "CENTER" or pos.point == nil)
            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            local fw = frame:GetWidth() or 0
            local fh = frame:GetHeight() or 0
            x = PPa.SnapCenterForDim(x, fw, es)
            y = PPa.SnapCenterForDim(y, fh, es)
        elseif PPa.SnapForES then
            x = PPa.SnapForES(x, es)
            y = PPa.SnapForES(y, es)
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, x, y)
end

-- Clip container for health + power bars -- prevents sub-pixel overflow at
-- certain UI scales where independent pixel-snapping pushes edges 1px out.
-- The clip frame is inset by the border thickness so the GPU physically
-- cannot render bar pixels outside the border, regardless of rounding.
local function EnsureBarClip(frame)
    if frame._barClip then return frame._barClip end
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetAllPoints(frame)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(frame:GetFrameLevel())
    clip:EnableMouse(false)
    frame._barClip = clip
    return clip
end

local function ReparentBarsToClip(frame, powerPosition)
    local clip = EnsureBarClip(frame)
    if frame.Health and frame.Health:GetParent() ~= clip then
        frame.Health:SetParent(clip)
    end
    if frame.Power then
        local detached = (powerPosition == "detached_top" or powerPosition == "detached_bottom")
        if detached then
            if frame.Power:GetParent() == clip then
                frame.Power:SetParent(frame)
            end
        else
            if frame.Power:GetParent() ~= clip then
                frame.Power:SetParent(clip)
            end
        end
        -- Power bar must render above absorb overlay (health level + 1).
        -- SetParent resets frame level, so re-assert after every reparent.
        local hpLevel = frame.Health and frame.Health:GetFrameLevel() or clip:GetFrameLevel()
        frame.Power:SetFrameLevel(hpLevel + 2)
    end
end

-- Recalculate all element sizes after frame scale changes so everything remains
-- pixel-perfect within the border.  PixelUtil rounds each element independently,
-- which can cause their sum to exceed the frame's snapped total by 1px at certain
-- scales.  After re-snapping each element we check for overflow and trim the last
-- element in the stack so everything fits exactly inside the border.
local function UpdateBordersForScale(frame, unit)
    if not frame then return end
    local settings = GetSettingsForUnit(unit)
    if not settings then return end
    local borderSize = settings.borderSize or 1

    -- 1) Main frame border textures
    if frame.unifiedBorder then
        local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
        local textureKey = settings.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(frame.unifiedBorder, borderSize, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", borderSize)
    end

    -- 2) Gather layout info
    local ppPos = settings.powerPosition or "below"
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ppIsDet = (ppPos == "detached_top" or ppPos == "detached_bottom")
    local ph = settings.powerHeight or 6
    -- Simple frames (pet/tot/focustarget) have no power bar ? skip power height
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local powerH = (ppIsAtt and not isMini) and ph or 0

    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbH = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0

    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if isMini and pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    -- Use the actual side the frame was built with (stored on the frame) so that
    -- frames like the pet which hard-code "left" don't get treated as "right".
    local pSide = EllesmereUI._ufPortraitSide[frame] or settings.portraitSide or "right"
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end

    -- Class power above adds height (player only, and only if spec has a resource)
    local cpAboveH = 0
    if unit == "player" and SpecHasClassPower() then
        local cpSt = settings.classPowerStyle or "none"
        local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
        if cpSt == "modern" and cpPo == "above" then
            local cpSizeAdj = settings.classPowerSize or 8
            cpAboveH = math.max(3, math.floor(cpSizeAdj * 0.375))
        end
    end

    local barHeight = settings.healthHeight + powerH + cpAboveH
    local expectedFrameH = barHeight + btbH
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = barHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    local expectedFrameW
    if not showPortrait or not isAttached then
        expectedFrameW = settings.frameWidth
    else
        expectedFrameW = adjPortraitH + settings.frameWidth
    end

    -- 3) Re-snap the frame itself
    PP.Size(frame, expectedFrameW, expectedFrameH)
    local snappedFrameW = frame:GetWidth()
    local snappedFrameH = frame:GetHeight()

    -- 4) Re-snap portrait and health bar (width axis)
    local healthTargetW = settings.frameWidth
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached then
        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local snappedPortH = frame.Portrait.backdrop:GetHeight()
        -- Trim portrait width if it + health would exceed frame
        if snappedPortW + healthTargetW > snappedFrameW + 0.01 then
            PP.Width(frame.Portrait.backdrop, snappedFrameW - healthTargetW)
            snappedPortW = frame.Portrait.backdrop:GetWidth()
        end
        -- Trim portrait height to frame height if it overflows
        if snappedPortH > snappedFrameH + 0.01 then
            PP.Height(frame.Portrait.backdrop, snappedFrameH)
        end
    end

    -- 5) Re-snap health bar height and re-anchor to snapped portrait width
    if frame.Health then
        PP.Height(frame.Health, settings.healthHeight)
        -- Re-anchor health bar so it's flush against the snapped portrait edge
        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRightInset = (effectiveSide == "right") and snappedPortW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end
    end

    -- 6) Re-snap power bar
    if frame.Power and ppPos ~= "none" then
        local pw = settings.frameWidth
        if ppIsDet and (settings.powerWidth or 0) > 0 then
            pw = settings.powerWidth
        end
        PP.Size(frame.Power, pw, ph)
        if ppIsAtt and frame.Health then
            -- Height: ensure health + power don't exceed the bar area
            local snappedHealthH = frame.Health:GetHeight()
            local snappedPowerH = frame.Power:GetHeight()
            local expectedBarH = settings.healthHeight + ph
            if snappedHealthH + snappedPowerH > expectedBarH + 0.01 then
                PP.Height(frame.Power, snappedPowerH - (snappedHealthH + snappedPowerH - expectedBarH))
            end
            -- Width: match health bar width exactly
            local snappedHealthW = frame.Health:GetWidth()
            local snappedPowerW = frame.Power:GetWidth()
            if math.abs(snappedPowerW - snappedHealthW) > 0.01 then
                PP.Width(frame.Power, snappedHealthW)
            end
        elseif not ppIsDet then
            -- Non-attached non-detached shouldn't happen, but trim width to frame
            local snappedPowerW = frame.Power:GetWidth()
            if snappedPowerW > snappedFrameW + 0.01 then
                PP.Width(frame.Power, snappedFrameW)
            end
        end
    end

    -- 7) Re-snap BTB
    if frame.BottomTextBar and settings.bottomTextBar and btbIsAtt then
        PP.Size(frame.BottomTextBar, expectedFrameW, settings.bottomTextBarHeight or 16)
        local snappedBtbW = frame.BottomTextBar:GetWidth()
        local snappedBtbH = frame.BottomTextBar:GetHeight()
        -- Width: trim to frame width
        if snappedBtbW > snappedFrameW + 0.01 then
            PP.Width(frame.BottomTextBar, snappedFrameW)
        end
        -- Height: ensure full stack fits within frame height
        local usedH = cpAboveH
        if frame.Health then usedH = usedH + frame.Health:GetHeight() end
        if frame.Power and ppIsAtt then usedH = usedH + frame.Power:GetHeight() end
        if usedH + snappedBtbH > snappedFrameH + 0.01 then
            PP.Height(frame.BottomTextBar, snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
        end
    end

    -- 8) Castbar: re-snap background width + border textures
    if frame.Castbar then
        local castbarBg = frame.Castbar:GetParent()
        if castbarBg then
            -- Trim castbar bg width to match frame width, but only if the
            -- user hasn't set a custom width (castbarWidth > 0 means custom).
            local cbW = castbarBg:GetWidth()
            local cbSettings = GetSettingsForUnit(frame._unit or frame.unit)
            local hasCustomW = cbSettings and (cbSettings.castbarWidth or 0) > 0
            if not hasCustomW and cbW > snappedFrameW + 0.01 then
                PP.Width(castbarBg, snappedFrameW)
            end
            -- Re-snap border textures
            if PP.GetBorders(castbarBg) then
                PP.SetBorderSize(castbarBg, 1)
                frame.Castbar:ClearAllPoints()
                PP.Point(frame.Castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
                PP.Point(frame.Castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- 9) Inset the clip container by half a physical pixel. This is
    -- sub-pixel and invisible, but guarantees the GPU clips any StatusBar
    -- texture rounding that pushes the fill past the frame edge.
    -- Skip the inset on the portrait side so the health bar stays flush
    -- with the portrait (which is anchored to the frame, not _barClip).
    if frame._barClip and frame.Health then
        local es = frame:GetEffectiveScale()
        local halfPixel = es > 0 and (PP.perfect / es) * 0.5 or PP.mult * 0.5
        local clipL, clipR = halfPixel, halfPixel
        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
            if effectiveSide == "left" then clipL = 0
            elseif effectiveSide == "right" then clipR = 0 end
        end
        frame._barClip:ClearAllPoints()
        frame._barClip:SetPoint("TOPLEFT", frame, "TOPLEFT", clipL, -halfPixel)
        frame._barClip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -clipR, halfPixel)
        -- Re-anchor health bar to clip so coordinates are consistent
        local xOff = frame.Health._xOffset or 0
        local rInset = frame.Health._rightInset or 0
        local topOff = frame.Health._topOffset or 0
        frame.Health:ClearAllPoints()
        frame.Health:SetPoint("TOPLEFT", frame._barClip, "TOPLEFT", xOff, PP.Scale(-topOff))
        frame.Health:SetPoint("RIGHT", frame._barClip, "RIGHT", -rInset, 0)
        PP.Height(frame.Health, settings.healthHeight)
    end
end

-- Scale system removed -- all sizing is now width/height based.

-- ToggleLock removed � positioning is now handled by Unlock Mode

-- fakeFrames / CreateFakeFrame / ShowFakeFrames / HideFakeFrames removed
-- Positioning is now handled exclusively by Unlock Mode

local function GetFrameDimensions(unit)
    local settings = GetSettingsForUnit(unit)
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local miniUnit = unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$"))
    if miniUnit and pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSizeAdj = settings.portraitSize or 0
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and (settings.powerHeight or 6) or 0

    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    -- Snap returned dimensions to the physical pixel grid so width-
    -- matching and cog display always agree with the rendered frame size.
    local snap = PP.Snap
    if unit == "player" or unit == "target" then
        local ptH = settings.healthHeight + powerExtra
        local adjPH = ptH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
        if isAttached and pSide == "top" then pSide = (unit == "player") and "left" or "right" end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(ptH + btbExtra)
    elseif unit == "focus" then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(barH + btbExtra)
    elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
        return snap(settings.frameWidth), snap(settings.healthHeight)
    elseif unit:match("^boss") then
        local pH = powerIsAtt and (settings.powerHeight or 6) or 0
        local barH = settings.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then adjPH = 8 end
        local w = (showPortrait and isAttached) and (adjPH + settings.frameWidth) or settings.frameWidth
        return snap(w), snap(barH)
    end
    return 150, 30
end

-- ShowFakeFrames / HideFakeFrames removed � Unlock Mode handles all positioning

local function CreateHealthBar(frame, unit, height, xOffset, settings, rightInset)
    height = height or settings.healthHeight
    xOffset = xOffset or 0
    rightInset = rightInset or 0

    -- When power bar is "above", push health bar down by power bar height
    local ppPos = settings.powerPosition or "below"
    local powerAboveOff = (ppPos == "above") and (settings.powerHeight or 0) or 0

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetFrameStrata(frame:GetFrameStrata())
    health:SetFrameLevel(frame:GetFrameLevel() + 2)
    -- Two-point horizontal anchoring: width is derived from the frame so it can
    -- never exceed the frame boundary regardless of pixel-snapping rounding.
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", xOffset, -powerAboveOff)
    PP.Point(health, "RIGHT", frame, "RIGHT", -rightInset, 0)
    PP.Height(health, height)
    health._xOffset = xOffset  -- store for class power repositioning
    health._rightInset = rightInset  -- store for class power repositioning
    health._topOffset = powerAboveOff  -- store for SnapLayout re-anchoring
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    ApplyHealthBarTexture(health, UnitToSettingsKey(unit))
    ApplyHealthBarAlpha(health, UnitToSettingsKey(unit))
    ApplyDarkTheme(health)
    health:SetReverseFill(settings.healthReverseFill and true or false)

    return health
end

-- Shield texture path. DO NOT change this path -- users without the
-- top-level symlink have been corrected; this is the path that resolves.
local ABSORB_SHIELD_TEX = "Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga"

-- Absorb bar style textures and alpha values. "striped" and "blizzard"
-- textures will be added to Media/ when the user uploads them.
local ABSORB_STYLE_TEX = {
    striped  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
    clean    = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
}
local ABSORB_STYLE_ALPHA = {
    striped  = 0.8,
    clean    = 0.3,
    blizzard = 0.8,
}

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local tex = ABSORB_STYLE_TEX[style] or ABSORB_SHIELD_TEX
    local alpha = ABSORB_STYLE_ALPHA[style] or 0.8
    if style == "clean" and settings then
        alpha = (settings.absorbCleanAlpha or 30) / 100
    end
    local mask = absorbBar._absorbMask
    absorbBar:SetStatusBarTexture(tex)
    absorbBar:SetStatusBarColor(1, 1, 1, alpha)
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        if mask then fill:AddMaskTexture(mask) end
    end
    local fw = absorbBar._forward
    if fw then
        fw:SetStatusBarTexture(tex)
        fw:SetStatusBarColor(1, 1, 1, alpha)
        local fwFill = fw:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            if mask then fwFill:AddMaskTexture(mask) end
        end
    end
end

-- Two-segment absorb rendering using dynamic clip-frame trickery, so it
-- works with secret-valued absorbs (player absorbs in 12.0+). We cannot
-- split the absorb value in Lua (min/subtract on secret values is blocked),
-- so we use STATUSBAR CLIPPING to do the math visually:
--
--   curClip  bounds: hpBar.LEFT  ->  healthTexture.RIGHT  (dynamic)
--   missClip bounds: healthTexture.RIGHT -> hpBar.RIGHT   (dynamic)
--
-- The shield fills RIGHTWARD first (into the missing-health area) and only
-- backfills into the filled portion when absorb exceeds missing-health.
--
--   forward bar (primary): child of missClip, forward fill, TOPLEFT anchored
--     to healthTexture.TOPRIGHT (current-HP edge), width = hpBar width. Its
--     texture fills from the current-HP edge rightward by
--     (absorbAmt / maxHealth) * hpWidth. missClip clips anything past
--     hpBar.RIGHT, so the visible portion is exactly min(absorb, missing)
--     pixels wide.
--
--   backfill bar (overflow): child of curClip, reverse fill, TOPRIGHT
--     anchored to hpBar.TOPRIGHT, width = hpBar width. Its texture fills
--     from hpBar.RIGHT leftward by (absorbAmt / maxHealth) * hpWidth.
--     curClip clips anything past healthTexture.RIGHT, so the visible
--     portion is exactly max(0, absorb - missing) pixels wide -- only
--     shows when shield overflows past the missing-health area.
--
-- Both bars receive the raw (secret-safe) absorbAmt via SetValue. No Lua
-- arithmetic on the absorb value is ever performed. Wired into oUF via
-- HealthPrediction.Override so oUF still owns event registration
-- (UNIT_HEALTH, UNIT_ABSORB_AMOUNT_CHANGED, etc.) and enable/disable.

-- Re-anchor existing absorb bars for the current reverse fill state.
-- Called from the live-update path when the user toggles reverse fill.
local function UpdateAbsorbBarReverseFill(frame, isReversed)
    if not frame or not frame.HealthPrediction then return end
    local ab = frame.HealthPrediction.damageAbsorb
    if not ab then return end
    local fw = ab._forward
    local curClip = ab._curClip
    local missClip = ab._missClip
    local hpBar = ab._hpBar
    if not (fw and curClip and missClip and hpBar) then return end
    local hpTex = hpBar:GetStatusBarTexture()
    if not hpTex then return end

    curClip:ClearAllPoints()
    missClip:ClearAllPoints()
    ab:ClearAllPoints()
    fw:ClearAllPoints()

    if isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT", 0, 0)
        missClip:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT", 1, 0)
        missClip:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT", 0, 0)
        ab:SetReverseFill(false)
        ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        fw:SetReverseFill(true)
        fw:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT",    0, 0)
        fw:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        missClip:SetPoint("TOPLEFT",     hpTex, "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        fw:SetReverseFill(false)
        fw:SetPoint("TOPLEFT",    hpTex, "TOPRIGHT",    0, 0)
        fw:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
    end

    -- Heal absorb bar follows the same reverse-fill logic as the backfill bar
    local ha = ab._healAbsorb
    if ha then
        ha:ClearAllPoints()
        ha:SetReverseFill(not isReversed)
        if isReversed then
            ha:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ha:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            ha:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ha:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        end
    end
end

local function CreateAbsorbBar(frame, unit, settings)
    if not frame.Health then return end

    local hpBar = frame.Health

    -- Mask texture: constrains absorb rendering to exact health bar bounds
    -- at the GPU level. Prevents subpixel bleed where absorb textures
    -- extend 1px outside the health bar at certain frame positions.
    local absorbMask = hpBar:CreateMaskTexture()
    absorbMask:SetAllPoints(hpBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Reverse fill: when health fills right-to-left, mirror all absorb anchors.
    local isReversed = settings.healthReverseFill and true or false

    -- Current HP clip: bounds the backfill bar to the filled health area.
    local curClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    curClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area.
    local missClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        missClip:SetPoint("TOPRIGHT",    hpBar:GetStatusBarTexture(), "TOPLEFT", 1, 0)
        missClip:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT", 0, 0)
    else
        missClip:SetPoint("TOPLEFT",     hpBar:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    missClip:SetClipsChildren(true)

    -- Backfill bar (overflow): grows into filled health from the edge.
    local backfillBar = CreateFrame("StatusBar", nil, curClip)
    backfillBar:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local bfFill = backfillBar:GetStatusBarTexture()
    if bfFill then bfFill:SetDrawLayer("ARTWORK", 1); bfFill:AddMaskTexture(absorbMask) end
    backfillBar:SetStatusBarColor(1, 1, 1, 0.8)
    backfillBar:SetReverseFill(not isReversed)
    if isReversed then
        backfillBar:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        backfillBar:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    else
        backfillBar:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        backfillBar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    backfillBar:SetWidth(hpBar:GetWidth())
    backfillBar:SetHeight(hpBar:GetHeight())
    backfillBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    backfillBar:Hide()

    -- Forward bar (primary): grows into missing health from the HP edge.
    local forwardBar = CreateFrame("StatusBar", nil, missClip)
    forwardBar:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local fwFill = forwardBar:GetStatusBarTexture()
    if fwFill then fwFill:SetDrawLayer("ARTWORK", 1); fwFill:AddMaskTexture(absorbMask) end
    forwardBar:SetStatusBarColor(1, 1, 1, 0.8)
    forwardBar:SetReverseFill(isReversed)
    if isReversed then
        forwardBar:SetPoint("TOPRIGHT",    hpBar:GetStatusBarTexture(), "TOPLEFT",    0, 0)
        forwardBar:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        forwardBar:SetPoint("TOPLEFT",    hpBar:GetStatusBarTexture(), "TOPRIGHT",    0, 0)
        forwardBar:SetPoint("BOTTOMLEFT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    forwardBar:SetWidth(hpBar:GetWidth())
    forwardBar:SetHeight(hpBar:GetHeight())
    forwardBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    forwardBar:Hide()

    -- Per-frame calculator for reading the absorb value (secret-safe).
    -- Matches nameplate UpdateHealthValues init exactly.
    local hpCalc
    if CreateUnitHealPredictionCalculator then
        hpCalc = CreateUnitHealPredictionCalculator()
        if hpCalc.SetMaximumHealthMode then
            hpCalc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            hpCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
        end
    end

    -- Heal absorb bar: overlays the filled-health area in red.
    -- Uses curClip so it's clipped to the filled portion of the health bar.
    -- Reverse-fills from the health texture edge inward (eats into green).
    local healAbsorbBar = CreateFrame("StatusBar", nil, curClip)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local haFill = healAbsorbBar:GetStatusBarTexture()
    if haFill then haFill:SetDrawLayer("ARTWORK", 2); haFill:AddMaskTexture(absorbMask) end
    healAbsorbBar:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
    healAbsorbBar:SetReverseFill(not isReversed)
    if isReversed then
        healAbsorbBar:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        healAbsorbBar:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    else
        healAbsorbBar:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        healAbsorbBar:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end
    healAbsorbBar:SetWidth(hpBar:GetWidth())
    healAbsorbBar:SetHeight(hpBar:GetHeight())
    healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    healAbsorbBar:Hide()

    -- Attach extras to the main bar (backfill) so anything that references
    -- HealthPrediction.damageAbsorb can hide/show both segments together.
    backfillBar._forward      = forwardBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._hpBar        = hpBar
    backfillBar._hpCalculator = hpCalc
    backfillBar._curClip      = curClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask

    -- Raise power bar above absorb overlay so it renders on top
    local power = frame and frame.Power
    if power then
        power:SetFrameLevel(math.max(power:GetFrameLevel(), hpBar:GetFrameLevel() + 2))
    end

    backfillBar:HookScript("OnHide", function()
        forwardBar:Hide()
        healAbsorbBar:Hide()
    end)

    frame.HealthPrediction = {
        damageAbsorb = backfillBar,
        Override = function(self, event, updUnit)
            if self.unit ~= updUnit then return end

            local element = self.HealthPrediction
            local ab = element.damageAbsorb
            if not ab then return end
            local fw   = ab._forward
            local hp   = ab._hpBar
            local calc = ab._hpCalculator
            if not hp then return end

            -- Respect the user's absorb style setting: hide both segments
            -- and skip the update when absorbs are "none". Without this,
            -- every unit event would re-Show() them after ReloadFrames hid them.
            local s = GetSettingsForUnit(updUnit)
            local ha = ab._healAbsorb
            if s and (not s.showPlayerAbsorb or s.showPlayerAbsorb == "none") then
                ab:Hide()
                if fw then fw:Hide() end
                if ha then ha:Hide() end
                return
            end

            local maxHealth, absorbAmt
            if calc and UnitGetDetailedHealPrediction then
                UnitGetDetailedHealPrediction(updUnit, nil, calc)
                calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
                maxHealth = calc:GetMaximumHealth()
                absorbAmt = calc:GetDamageAbsorbs()
            else
                maxHealth = UnitHealthMax(updUnit) or 0
                absorbAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0
            end

            -- Keep bars sized to the health bar every update.
            local hpW, hpH = hp:GetWidth(), hp:GetHeight()
            ab:SetWidth(hpW); ab:SetHeight(hpH)
            if fw then fw:SetWidth(hpW); fw:SetHeight(hpH) end

            -- Re-apply absorb style only when the style setting changes
            -- (not on every health event). Calling SetStatusBarTexture on
            -- every update causes the bar to flash visible even at zero absorb.
            local absStyle = s and s.showPlayerAbsorb
            if absStyle and absStyle ~= "none" and ab._lastAbsStyle ~= absStyle then
                ab._lastAbsStyle = absStyle
                ApplyAbsorbStyle(ab, absStyle, s)
            end

            -- Both bars get the raw absorb value and the normal maxHealth.
            -- The clip frames do the "min(absorb, curHealth)" and
            -- "max(0, absorb - curHealth)" math visually so we never need
            -- Lua arithmetic on the (possibly secret) absorb value.
            ab:SetMinMaxValues(0, maxHealth)
            ab:SetValue(absorbAmt)
            ab:Show()

            if fw then
                fw:SetMinMaxValues(0, maxHealth)
                fw:SetValue(absorbAmt)
                fw:Show()
            end

            -- Heal absorb: red overlay eating into filled health.
            -- The value can be a secret number in 12.0+, so never compare
            -- it in Lua. Feed it directly to StatusBar:SetValue and let the
            -- bar render zero width when the value is 0.
            if ha then
                local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit) or 0
                ha:SetWidth(hpW); ha:SetHeight(hpH)
                ha:SetMinMaxValues(0, maxHealth)
                ha:SetValue(healAbsorbAmt)
                ha:Show()
            end
        end,
    }

    return backfillBar
end

local function CreatePowerBar(frame, unit, settings)
    local powerPos = settings.powerPosition or "below"

    local power = CreateFrame("StatusBar", nil, frame)
    local isDetached = (powerPos == "detached_top" or powerPos == "detached_bottom")
    if isDetached then
        -- Bump strata so the detached power bar renders above the border
        -- regardless of frame level. Frame level within the same strata is
        -- fragile (oUF and absorb bar code can reset it).
        power:SetFrameStrata("MEDIUM")
    else
        power:SetFrameStrata(frame:GetFrameStrata())
    end
    power:SetFrameLevel(frame:GetFrameLevel() + (isDetached and 12 or 3))
    local pw = settings.frameWidth
    if isDetached and (settings.powerWidth or 0) > 0 then
        pw = settings.powerWidth
    end
    PP.Size(power, pw, settings.powerHeight)

    if powerPos == "none" then
        power:Hide()
    elseif powerPos == "above" then
        PP.Point(power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
        PP.Point(power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
    elseif powerPos == "detached_top" then
        power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
    elseif powerPos == "detached_bottom" then
        power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
    else -- "below" (default)
        PP.Point(power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
        PP.Point(power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
    end

    -- Apply the same bar texture as health (respects user's texture selection).
    -- Falls back to WHITE8X8 if no texture is configured.
    local texKey = (settings and settings.healthBarTexture) or (db.profile.healthBarTexture) or "none"
    local texPath = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey, "Interface\\Buttons\\WHITE8X8")
    power:SetStatusBarTexture(texPath)
    power:GetStatusBarTexture():SetHorizTile(false)
    do
        local pFill = power:GetStatusBarTexture()
        if pFill then UnsnapTex(pFill) end
    end

    local bg = power:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", power, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
    local initBg = settings.customPowerBgColor
    if initBg then
        bg:SetColorTexture(initBg.r, initBg.g, initBg.b, 1)
    else
        bg:SetColorTexture(17/255, 17/255, 17/255, 1)
    end
    UnsnapTex(bg)
    power.bg = bg

    -- Power bar fill color: controlled by powerPercentPowerColor toggle
    local usePowerColor = settings.powerPercentPowerColor ~= false
    if usePowerColor then
        power.colorPower = true
    else
        power.colorPower = false
        local customFill = settings.customPowerFillColor
        if customFill then
            power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
            power.PostUpdateColor = function(self)
                local s2 = GetSettingsForUnit(unit)
                local cf = s2 and s2.customPowerFillColor
                if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) end
            end
        else
            power:SetStatusBarColor(0, 0, 1)
            power.PostUpdateColor = function(self)
                self:SetStatusBarColor(0, 0, 1)
            end
        end
    end

    -- Custom power bar background color
    local customBg = settings.customPowerBgColor
    if customBg then
        bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
    end

    power:SetReverseFill(settings.powerReverseFill and true or false)

    -- Power percent text overlay
    -- Parent to frame (not power) so text isn't clipped by the bar clip container
    local ppTextOvr = CreateFrame("Frame", nil, frame)
    ppTextOvr:SetAllPoints(power)
    ppTextOvr:SetFrameLevel(frame:GetFrameLevel() + 15)
    local ppFS = ppTextOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(ppFS, settings.powerPercentSize or 9)
    ppFS:Hide()
    power._ppFS = ppFS
    power._ppTextOvr = ppTextOvr

    local function ApplyPowerPercentText(s)
        local pos = s.powerPercentText or "none"
        local sz  = s.powerPercentSize or 9
        local ox  = s.powerPercentX or 0
        local oy  = s.powerPercentY or 0

        SetFSFont(ppFS, sz)
        ppFS:ClearAllPoints()

        if pos == "none" then
            ppFS:Hide()
            if ppFS._curTag then frame:Untag(ppFS); ppFS._curTag = nil end
            return
        end

        if pos == "left" then
            ppFS:SetJustifyH("LEFT")
            PP.Point(ppFS, "LEFT", ppTextOvr, "LEFT", 2 + ox, oy)
        elseif pos == "right" then
            ppFS:SetJustifyH("RIGHT")
            PP.Point(ppFS, "RIGHT", ppTextOvr, "RIGHT", -2 + ox, oy)
        else
            ppFS:SetJustifyH("CENTER")
            PP.Point(ppFS, "CENTER", ppTextOvr, "CENTER", ox, oy)
        end

        if ppFS._curTag then frame:Untag(ppFS); ppFS._curTag = nil end
        local showPct = s.powerShowPercent ~= false
        local pctSuffix = showPct and "%" or ""
        local fmt = s.powerTextFormat or "perpp"
        local tag
        if fmt == "curpp" then
            tag = "[eui-curpp]"
        elseif fmt == "both" then
            tag = "[eui-curpp] | [eui-perpp]" .. pctSuffix
        elseif fmt == "smart" then
            -- smart: percent for mana-based specs, numeric for others
            -- resolved at apply time; re-applied on spec change via ReloadAndUpdate
            local isPercent = EUI_IsSmartPowerPercent()
            tag = isPercent and ("[eui-perpp]" .. pctSuffix) or "[eui-curpp]"
        else -- "perpp" default
            tag = "[eui-perpp]" .. pctSuffix
        end
        frame:Tag(ppFS, tag); ppFS._curTag = tag
        if frame.UpdateTags then frame:UpdateTags() end

        -- Text color: power-colored > custom color > white
        if s.powerPercentTextPowerColor then
            local pType = UnitPowerType(unit)
            local info = PowerBarColor[pType]
            if info then ppFS:SetTextColor(info.r, info.g, info.b)
            else ppFS:SetTextColor(1, 1, 1) end
        elseif s.powerTextColor then
            local tc = s.powerTextColor
            ppFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        else
            ppFS:SetTextColor(1, 1, 1)
        end
        ppFS:Show()
    end

    ApplyPowerPercentText(settings)
    power._applyPowerPercentText = ApplyPowerPercentText

    ApplyPowerBarAlpha(power, UnitToSettingsKey(unit))

    -- Hide power bar for enemy NPCs that don't use power (melee mobs, etc.)
    -- Show power for: player, friendly units, enemy players, bosses, minibosses, casters
    power._grayedOut = false
    power.PostUpdate = function(self, u, cur, min, max)
        local s = GetSettingsForUnit(u)
        if not s then return end

        local pp = s.powerPosition or "below"
        if pp == "none" or pp == "detached_top" or pp == "detached_bottom" then return end

        -- Classification check: gray out power bar for generic melee NPCs
        local ok, shouldGray = pcall(function()
            if u == "player" or not UnitExists(u) then return false end
            if not UnitCanAttack("player", u) or UnitIsPlayer(u) then return false end
            local cls = UnitClassification(u)
            if cls == "worldboss" then return false end
            local isElite = (cls == "elite" or cls == "rareelite")
            local lvl = UnitLevel(u)
            local pLvl = UnitLevel("player")
            local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
            local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
            if isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1)) then return false end
            if UnitClassBase and UnitClassBase(u) == "PALADIN" then return false end
            return true
        end)
        if not ok then return end

        if shouldGray and not self._grayedOut then
            self._grayedOut = true
            if self.bg then
                self.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                self.bg:SetAlpha(1)
            end
        elseif not shouldGray and self._grayedOut then
            self._grayedOut = false
            local customBg = s.customPowerBgColor
            if customBg then
                if self.bg then self.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1) end
            else
                if self.bg then self.bg:SetColorTexture(17/255, 17/255, 17/255, 1) end
            end
            -- Restore bg alpha from unified opacity setting
            if self.bg then
                local opacity = s and (s.powerBarOpacity or 100) or 100
                self.bg:SetAlpha(opacity / 100)
            end
        end
    end

    -- Per-spec power type override: lets users choose an alternate power type
    -- on the player power bar (e.g. Balance Druid: Astral Power vs Mana).
    -- Shadow Priest defaults to Mana; other specs default to UnitPowerType.
    if unit == "player" then
        local _, classFile = UnitClass("player")
        -- Specs whose addon default differs from UnitPowerType (forced value)
        local SPEC_DEFAULT_POWER = {
            PRIEST = { [3] = 0 },   -- Shadow: default to Mana
        }
        -- Specs that have an alternative choice; value = powerType to force
        -- (nil means "remove override, let UnitPowerType decide")
        local SPEC_ALT_POWER = {
            DRUID  = { [1] = 0, [2] = 0, [3] = 0 },  -- Balance/Feral/Guardian -> Mana
            PRIEST = { [3] = nil },                     -- Shadow alt -> Insanity (UnitPowerType)
            SHAMAN = { [1] = 0 },                       -- Elemental -> Mana
        }
        local classDef = SPEC_DEFAULT_POWER[classFile]
        local classAlt = SPEC_ALT_POWER[classFile]
        if classDef or classAlt then
            power.displayAltPower = true
            power.GetDisplayPower = function(self, u)
                local spec = GetSpecialization and GetSpecialization()
                if not spec then return nil end
                local resolved
                -- Check user override
                local ps = GetSettingsForUnit("player")
                local ov = ps and ps.powerTypeOverride
                if ov and ov[spec] and classAlt then
                    resolved = classAlt[spec]  -- nil = UnitPowerType, number = forced
                elseif classDef and classDef[spec] ~= nil then
                    resolved = classDef[spec]
                end
                -- Publish for tags so text matches the bar
                _G._EUI_ResolvedPowerType[u or "player"] = resolved
                return resolved
            end
        end
    end

    return power
end

local function CreatePortrait(frame, side, frameHeight, unit)
    local portraitHeight = frameHeight or 46
    local uKey = UnitToSettingsKey(unit)
    local uSettings = uKey and db.profile[uKey]
    local portraitStyle = (uSettings and uSettings.portraitStyle) or db.profile.portraitStyle or "attached"
    -- Mini frames never use detached portraits
    local isMiniP = unit and (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
    if isMiniP and portraitStyle == "detached" then portraitStyle = "attached" end
    local isAttached = (portraitStyle == "attached")

    -- Per-unit size/offset adjustments
    local pSizeAdj = (uSettings and uSettings.portraitSize) or 0
    local pXOff = (uSettings and uSettings.portraitX) or 0
    local pYOff = (uSettings and uSettings.portraitY) or 0
    local baseHeight = portraitHeight
    if not isAttached and portraitStyle ~= "none" then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
    local adjustedHeight = baseHeight + pSizeAdj
    if adjustedHeight < 8 then adjustedHeight = 8 end

    -- For attached, "top" falls back to default side
    local effectiveSide = side
    if isAttached and side == "top" then
        effectiveSide = (unit == "player") and "left" or "right"
    end

    local backdrop = CreateFrame("Frame", nil, frame)
    backdrop:SetFrameStrata(frame:GetFrameStrata())
    backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
    PP.Size(backdrop, adjustedHeight, adjustedHeight)
    backdrop:SetClipsChildren(false)

    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0.1, 0.1, 0.1, 1)
    backdrop._bg = bgTex

    if portraitStyle == "none" then
        -- Portrait disabled: anchor backdrop to frame corner (it stays hidden).
        -- Avoids any dependency on frame.Health which may not exist yet.
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    elseif isAttached then
        if effectiveSide == "left" then
            PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        else
            PP.Point(backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end
    else
        -- Detached: float outside the health bar edge
        if effectiveSide == "top" then
            backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
        elseif effectiveSide == "left" then
            backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
        else
            backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
        end
        -- Raise detached portrait above border/text/power so it renders on top
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
    end

    -- Create 2D and class theme textures eagerly; 3D PlayerModel is deferred
    -- until actually needed (mode == "3d") to avoid GPU/memory cost when unused.
    local model3D = nil  -- lazy-created only when mode is "3d"

    local function EnsureModel3D()
        if model3D then return model3D end
        model3D = CreateFrame("PlayerModel", nil, backdrop)
        PP.Point(model3D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        PP.Point(model3D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        model3D:SetCamera(0)
        model3D:Hide()
        backdrop._3d = model3D
        return model3D
    end
    backdrop._ensureModel3D = EnsureModel3D

    local tex2D = backdrop:CreateTexture(nil, "ARTWORK")
    PP.Point(tex2D, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(tex2D, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    tex2D:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    tex2D:Hide()

    -- Class theme icon (static texture, no oUF element needed)
    local texClass = backdrop:CreateTexture(nil, "ARTWORK")
    local classInset = math.floor(portraitHeight * 0.08)
    PP.Point(texClass, "TOPLEFT", backdrop, "TOPLEFT", classInset, -classInset)
    PP.Point(texClass, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -classInset, classInset)
    texClass:SetAlpha(0.8)
    local _, classToken = UnitClass(unit)
    local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
    ApplyClassIconTexture(texClass, classToken or "WARRIOR", classStyle)
    texClass:Hide()

    texClass.Override = function(self, event, unit)
        local f = self.__owner
        if not f then return end
        local evUnit = (event == "OnUpdate" and f.unit) or unit
        if not evUnit or not UnitIsUnit(f.unit, evUnit) then return end
        local targetUnit = f.unit
        local _, ct = UnitClass(targetUnit)
        local uS = db.profile[UnitToSettingsKey(targetUnit)] or db.profile.player
        local cStyle = (uS and uS.classThemeStyle) or "modern"
        ApplyClassIconTexture(self, ct or "WARRIOR", cStyle)
        self:Show()
    end

    backdrop._3d = model3D
    backdrop._2d = tex2D
    backdrop._class = texClass

    local mode
    do
        mode = (uSettings and uSettings.portraitMode) or db.profile.portraitMode or "2d"
    end
    -- If portraitStyle or portraitMode is "none", hide the backdrop but keep
    -- the structure alive so ReloadFrames can show it again without a /reload.
    if portraitStyle == "none" or mode == "none" then
        backdrop:Hide()
        -- Return tex2D as a minimal placeholder so frame.Portrait is non-nil
        -- and has a backdrop reference. It stays hidden (backdrop is hidden).
        tex2D.backdrop = backdrop
        tex2D.is2D = true
        return tex2D
    end
    local active
    if mode == "class" then
        texClass:Show()
        tex2D:Hide()
        active = texClass
        active.isClass = true
    elseif mode == "2d" then
        tex2D:Show()
        active = tex2D
        active.is2D = true
    else
        local m3d = EnsureModel3D()
        m3d:Show()
        active = m3d
        active.is2D = false
    end
    active.backdrop = backdrop

    -- Re-apply pixel snap disable and re-anchor after oUF updates the portrait texture
    -- (SetPortraitTexture can reset snapping properties and anchor points)
    tex2D.PostUpdate = function(self)
        UnsnapTex(self)
        self:ClearAllPoints()
        -- When detached, ApplyDetachedPortraitShape sets expanded offsets for mask fill.
        -- Re-apply those offsets instead of resetting to default.
        local uKey2 = UnitToSettingsKey(unit)
        local uS2 = uKey2 and db.profile[uKey2]
        local isDetNow = ((uS2 and uS2.portraitStyle) or db.profile.portraitStyle or "attached") == "detached"
        if isDetNow and backdrop then
            local shape2 = (uS2 and uS2.detachedPortraitShape) or "portrait"
            local insetPx2 = MASK_INSETS[shape2] or 17
            local bw2 = backdrop:GetWidth()
            local bh3 = backdrop:GetHeight()
            if bw2 < 1 then bw2 = 46 end
            if bh3 < 1 then bh3 = 46 end
            local visR2 = (128 - 2 * insetPx2) / 128
            local cS2 = 1 / visR2
            local artS2 = ((uS2 and uS2.portraitArtScale) or 100) / 100
            cS2 = cS2 * artS2
            local exp2 = (cS2 - 1) * 0.5
            PP.Point(self, "TOPLEFT", backdrop, "TOPLEFT", -(exp2 * bw2), exp2 * bh3)
            PP.Point(self, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", exp2 * bw2, -(exp2 * bh3))
        else
            PP.Point(self, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
            PP.Point(self, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Apply detached portrait shape (mask + border) on creation
    ApplyDetachedPortraitShape(backdrop, uSettings, unit)

    return active
end

-- Returns the unlock position key for a unit's castbar, or nil
local function CastbarUnlockKey(unit)
    if unit == "player" then return "playerCastbar"
    elseif unit == "target" then return "targetCastbar"
    elseif unit == "focus" then return "focusCastbar"
    end
end

-- ApplyCastbarUnlockPos removed: cast bar positioning is now fully owned
-- by the centralized unlock/anchor system (ApplySavedPositions).

local function CreateCastBar(frame, unit, settings)
    local settings = GetSettingsForUnit(unit)
    
    -- Castbar is a standalone element parented to the oUF frame for
    -- compatibility, but sized and positioned independently.
    local castbarBg = CreateFrame("Frame", nil, frame)

    -- Determine width and height from settings (no auto-derive, always stored)
    local cbWidth, cbHeight
    if unit == "player" then
        cbWidth = db.profile.player.playerCastbarWidth or 181
        cbHeight = db.profile.player.playerCastbarHeight or 14
    else
        cbWidth = settings.castbarWidth or 181
        cbHeight = settings.castbarHeight or 14
    end
    PP.Size(castbarBg, cbWidth, cbHeight)

    -- Position is fully owned by the centralized unlock system.
    -- Set a temporary anchor so the frame has valid bounds until
    -- ApplySavedPositions runs. The unlock anchor (default: BOTTOM
    -- of parent unit frame) takes over at login.
    castbarBg:SetPoint("TOP", frame, "BOTTOM", 0, 0)

    local bgTex = castbarBg:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0, 0, 0, 0.5)

    local castbar = CreateFrame("StatusBar", nil, castbarBg)
    PP.Point(castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    PP.Point(castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    castbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castbar:GetStatusBarTexture():SetHorizTile(false)
    castbar:SetReverseFill(settings.castReverseFill and true or false)

    -- Castbar borders drawn on the castbar itself (same frame level as the
    -- fill texture) so the OVERLAY border sits above the ARTWORK fill.
    -- Drawing on castbarBg would put the border behind the fill because
    -- castbar is a child of castbarBg and draws above it.
    PP.CreateBorder(castbar, 0, 0, 0, 1, 1, "OVERLAY", 0)


    -- Three-zone cast bar text layout matching nameplates:
    -- [spell name LEFT 42%] [target RIGHT-of-center 42%] [timer RIGHT]
    -- All zones truncate with ellipsis (WordWrap off, MaxLines 1).
    local text = castbar:CreateFontString(nil, "OVERLAY")
    SetFSFont(text, settings.castSpellNameSize or 11)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    text:SetTextColor(1, 1, 1)
    castbar.Text = text

    local time = castbar:CreateFontString(nil, "OVERLAY")
    SetFSFont(time, settings.castDurationSize or 10)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetMaxLines(1)
    time:SetTextColor(1, 1, 1)
    castbar.Time = time

    local target = castbar:CreateFontString(nil, "OVERLAY")
    SetFSFont(target, settings.castSpellTargetSize or 11)
    target:SetJustifyH("RIGHT")
    target:SetWordWrap(false)
    target:SetMaxLines(1)
    target:SetTextColor(1, 1, 1)
    target:Hide()
    castbar.Target = target

    -- Layout: spell name 42% LEFT, timer RIGHT (sized to font), target 42% between them.
    -- Matches nameplate RefreshNamePosition exactly. Offsets from settings.
    local function LayoutCastTextZones(cb)
        local barW = cb:GetWidth()
        if not barW or barW <= 0 then return end
        local timerSz = cb._durationSize or 10
        local timerW = timerSz * 2.2
        local snX = cb._nameOX or 0
        local snY = cb._nameOY or 0
        local dtX = cb._durOX or 0
        local dtY = cb._durOY or 0
        local tgX = cb._tgtOX or 0
        local tgY = cb._tgtOY or 0
        cb.Text:ClearAllPoints()
        cb.Text:SetWidth(barW * 0.42)
        cb.Text:SetPoint("LEFT", cb, "LEFT", 5 + snX, 1 + snY)
        cb.Time:ClearAllPoints()
        cb.Time:SetWidth(timerW)
        cb.Time:SetPoint("RIGHT", cb, "RIGHT", -3 + dtX, dtY)
        cb.Target:ClearAllPoints()
        cb.Target:SetWidth(barW * 0.42)
        cb.Target:SetPoint("RIGHT", cb, "RIGHT", -3 - timerW + tgX, tgY)
    end
    castbar._durationSize = settings.castDurationSize or 10
    castbar._nameOX = settings.castSpellNameX or 0
    castbar._nameOY = settings.castSpellNameY or 0
    castbar._durOX = settings.castDurationX or 0
    castbar._durOY = settings.castDurationY or 0
    castbar._tgtOX = settings.castSpellTargetX or 0
    castbar._tgtOY = settings.castSpellTargetY or 0
    castbar._layoutTextZones = LayoutCastTextZones
    LayoutCastTextZones(castbar)

    -- Helper: sync all offset/size cache values from settings onto
    -- the castbar, then re-layout. Called from live refresh paths.
    castbar._syncOffsetsAndLayout = function(self, s)
        self._durationSize = s.castDurationSize or 10
        self._nameOX = s.castSpellNameX or 0
        self._nameOY = s.castSpellNameY or 0
        self._durOX  = s.castDurationX or 0
        self._durOY  = s.castDurationY or 0
        self._tgtOX  = s.castSpellTargetX or 0
        self._tgtOY  = s.castSpellTargetY or 0
        if self._layoutTextZones then self:_layoutTextZones() end
    end

    local shield = castbar:CreateTexture(nil, "OVERLAY")
    shield:SetSize(1, 1)
    shield:SetAlpha(0)
    shield:Hide()
    castbar.Shield = shield

    local castTintLayer = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
    castTintLayer:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    castTintLayer:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    castTintLayer:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = GetCastbarColor()
    castTintLayer:SetVertexColor(c.r, c.g, c.b)
    castTintLayer:SetAlpha(0)
    castbar.castTintLayer = castTintLayer

    local shieldedTint = castbar:CreateTexture(nil, "ARTWORK", nil, 2)
    shieldedTint:SetPoint("TOPLEFT", castbar:GetStatusBarTexture(), "TOPLEFT")
    shieldedTint:SetPoint("BOTTOMRIGHT", castbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    shieldedTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    shieldedTint:SetVertexColor(0.5, 0.5, 0.5)
    shieldedTint:SetAlpha(0)
    castbar._shieldedTint = shieldedTint

    castbar.PostCastStart = function(self)
        if self.castTintLayer then
            self.castTintLayer:SetAlpha(1)
            local cc
            local uSettings = self._eufSettings
            -- Class colored only applies to the player cast bar
            local ownerUnit = self.__owner and self.__owner.unit
            if uSettings and uSettings.castbarClassColored and ownerUnit == "player" then
                if ownerUnit then
                    local _, classToken = UnitClass(ownerUnit)
                    if classToken and EllesmereUI.GetClassColor then
                        cc = EllesmereUI.GetClassColor(classToken)
                    end
                end
            end
            if not cc then
                cc = (uSettings and uSettings.castbarFillColor) or GetCastbarColor()
            end
            self.castTintLayer:SetVertexColor(cc.r, cc.g, cc.b)
            if self._shieldedTint then
                self._shieldedTint:SetAlphaFromBoolean(self.notInterruptible, 1, 0)
            end
        end
    end
    castbar.PostChannelStart = castbar.PostCastStart

    castbar.PostCastInterruptible = castbar.PostCastStart

    castbar.CustomTimeText = function(self, durationObject)
        if self._showDuration == false then
            self.Time:SetText("")
            self.Time:Hide()
            return
        end
        self.Time:Show()
        if durationObject then
            local duration = durationObject:GetRemainingDuration()
            if self.delay and self.delay ~= 0 then
                self.Time:SetFormattedText('%.1f|cffff0000%s%.2f|r', duration, self.channeling and '-' or '+', self.delay)
            else
                self.Time:SetFormattedText('%.1f', duration)
            end
        end
    end
    castbar.CustomDelayText = castbar.CustomTimeText

    -- Cast spell icon (oUF sets castbar.Icon texture automatically)
    local cbH = castbarBg:GetHeight()
    local iconSize = cbH
    local iconFrame = CreateFrame("Frame", nil, castbarBg)
    iconFrame:SetSize(iconSize, iconSize)
    PP.Point(iconFrame, "TOPRIGHT", castbarBg, "TOPLEFT", 0, 0)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    -- 1px black border via unified PP system
    PP.CreateBorder(iconFrame, 0, 0, 0, 1)
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castbar.Icon = iconTex
    castbar._iconFrame = iconFrame

    return castbar
end

local function SetupShowOnCastBar(frame, unit)
    local castbar = frame.Castbar
    local castbarBg = castbar:GetParent()
    local iconFrame = castbar._iconFrame

    -- Read the hide-when-inactive flag dynamically so closures always
    -- reflect the current setting rather than a value captured at
    -- frame-creation time.
    local function shouldHideWhenInactive()
        -- Boss frames always hide castbar when inactive (no user toggle)
        if unit and unit:match("^boss") then return true end
        local s = GetSettingsForUnit(unit)
        if not s then return true end
        local v = s.castbarHideWhenInactive
        if v == nil then return true end
        return v
    end

    castbar:Hide()
    if iconFrame then iconFrame:Hide() end
    if castbarBg then
        if shouldHideWhenInactive() then
            castbarBg:Hide()
        else
            castbarBg:Show()
        end
    end

    local savedCastHook = castbar.PostCastStart

    castbar.PostCastStart = function(self, ...)
        local bg = self:GetParent()
        if bg then bg:Show() end
        self:Show()
        if self._iconFrame then
            local s = db and db.profile and GetSettingsForUnit(unit)
            local showIcon
            if unit == "player" then
                showIcon = (s and s.showPlayerCastIcon ~= false)
            else
                showIcon = (not s or s.showCastIcon ~= false)
            end
            if showIcon then
                self._iconFrame:Show()
            else
                self._iconFrame:Hide()
            end
        end
        -- Spell target text (who the unit is casting on)
        if self.Target then
            local spellTarget, spellTargetClass
            local ownerUnit = self.__owner and self.__owner.unit
            if ownerUnit and ownerUnit ~= "player"
               and UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(ownerUnit) then
                local rawTarget = UnitSpellTargetName and UnitSpellTargetName(ownerUnit)
                if rawTarget then
                    spellTarget = rawTarget
                    spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(ownerUnit)
                end
            end
            local hasTarget = spellTarget and true or false
            self.Target:SetText(spellTarget or "")
            self.Target:SetShown(hasTarget and self._showTarget ~= false)
            -- Class color the target name
            if hasTarget and spellTargetClass and C_ClassColor then
                local c = C_ClassColor.GetClassColor(spellTargetClass)
                if c then
                    self.Target:SetTextColor(c:GetRGB())
                else
                    local s2 = db and db.profile and GetSettingsForUnit(ownerUnit)
                    local tc = (s2 and s2.castSpellTargetColor) or { r=1, g=1, b=1 }
                    self.Target:SetTextColor(tc.r, tc.g, tc.b)
                end
            elseif hasTarget then
                local s2 = db and db.profile and GetSettingsForUnit(ownerUnit)
                local tc = (s2 and s2.castSpellTargetColor) or { r=1, g=1, b=1 }
                self.Target:SetTextColor(tc.r, tc.g, tc.b)
            end
            if self._layoutTextZones then self:_layoutTextZones() end
        end
        if savedCastHook then savedCastHook(self, ...) end
    end
    castbar.PostChannelStart = castbar.PostCastStart
    castbar.PostCastInterruptible = savedCastHook

    local function dismissCastBar(self)
        self:Hide()
        if self._iconFrame then self._iconFrame:Hide() end
        -- Read setting dynamically so changes take effect without a reload.
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end
    castbar.PostCastStop = dismissCastBar
    castbar.PostChannelStop = dismissCastBar
    castbar.PostCastFail = dismissCastBar

    -- Guard against nil stages from UnitEmpoweredStagePercentages during
    -- empower casts where stage data isn't available yet.
    castbar.UpdatePips = function(element, stages)
        if not stages then return end
        local isHoriz = element:GetOrientation() == "HORIZONTAL"
        local elementSize = isHoriz and element:GetWidth() or element:GetHeight()
        local lastOffset = 0
        for stage, stageSection in next, stages do
            local offset = lastOffset + (elementSize * stageSection)
            lastOffset = offset
            local pip = element.Pips[stage]
            if not pip then
                pip = (element.CreatePip or function(e)
                    return CreateFrame("Frame", nil, e, "CastingBarFrameStagePipTemplate")
                end)(element, stage)
                element.Pips[stage] = pip
            end
            pip:ClearAllPoints()
            if isHoriz then
                pip:SetPoint("CENTER", element, "LEFT", offset, 0)
            else
                pip:SetPoint("CENTER", element, "BOTTOM", 0, offset)
            end
            pip:Show()
        end
        for i = #stages + 1, #element.Pips do
            element.Pips[i]:Hide()
        end
    end

    -- Catch-all: hide the icon AND the background whenever the castbar
    -- hides for any reason (oUF holdTime expiry, target/focus switch, etc.)
    -- so neither ever gets stuck. Target/focus switching while the previous
    -- unit is mid-cast is the key case: oUF's CastStart hides the castbar
    -- but never fires PostCastStop, so dismissCastBar never runs and the
    -- background frame would otherwise remain visible as a black rectangle.
    castbar:HookScript("OnHide", function(self)
        if self._iconFrame then self._iconFrame:Hide() end
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end)
end


local function FrameBorderEnter(self)
    if not self.unifiedBorder then return end
    local unit = self.unit or "player"
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$")))
    local settings = isMini and GetMiniDonorSettings() or GetSettingsForUnit(unit)
    local hc = settings.highlightColor or { r = 1, g = 1, b = 1 }
    local ha = settings.highlightAlpha or 1
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, hc.r, hc.g, hc.b, ha)
end
local function FrameBorderLeave(self)
    if not self.unifiedBorder then return end
    local unit = self.unit or "player"
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or (unit and unit:match("^boss%d$")))
    local settings = isMini and GetMiniDonorSettings() or GetSettingsForUnit(unit)
    local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
    local ba = settings.borderAlpha or 1
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, bc.r, bc.g, bc.b, ba)
end

-- Unified border for unit frames using the PP border system
local function CreateUnifiedBorder(frame, unit)
    local settings = GetSettingsForUnit(unit or "player")
    local size = settings.borderSize or 1
    local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
    local textureKey = settings.borderTexture or "solid"

    local border = CreateFrame("Frame", nil, frame)
    PP.Point(border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PP.Point(border, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border:SetFrameLevel(frame:GetFrameLevel() + 10)

    EllesmereUI.ApplyBorderStyle(border, size, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", size)

    frame.unifiedBorder = border

    if size == 0 then
        border:Hide()
    end

    frame:HookScript("OnEnter", FrameBorderEnter)
    frame:HookScript("OnLeave", FrameBorderLeave)

    return border
end


-- Apply cooldown text settings to all existing buttons in an aura container.
-- Called from ReloadFrames to live-update without /reload.
local function ApplyAuraCooldownText(container, showCD, cdSize)
    if not container then return end
    for i = 1, (container.createdButtons or 0) do
        local btn = container[i]
        if btn and btn.Cooldown then
            btn.Cooldown:SetHideCountdownNumbers(not showCD)
            if showCD then
                local cdText = btn.Cooldown:GetRegions()
                if cdText and cdText.SetFont then
                    cdText:SetFont(cachedFontPath, cdSize, "OUTLINE")
                end
            end
        end
    end
end

local function CreateTargetAuras(frame, unit)
    local function SetupAuraIcon(container, button)
        if not button then return end

        if button.Icon then
            button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        if button.Cooldown then
            button.Cooldown:SetDrawEdge(false)
            button.Cooldown:SetReverse(true)
            -- Read settings fresh (the `settings` local is declared below this
            -- closure in the function body, so it's not captured as an upvalue).
            local isBuff = container and container.filter == "HELPFUL"
            local s = GetSettingsForUnit(unit or "target")
            local showText, textSize
            if isBuff then
                showText = s and s.buffShowCooldownText
                textSize = s and s.buffCooldownTextSize or 10
            elseif s and s.simpleDebuffs ~= false and unit and unit:match("^boss") then
                showText = s and s.simpleDebuffShowCooldownText
                textSize = s and s.simpleDebuffCooldownTextSize or 14
            else
                showText = s and s.debuffShowCooldownText
                textSize = s and s.debuffCooldownTextSize or 10
            end
            button.Cooldown:SetHideCountdownNumbers(not showText)
            if showText then
                local cdText = button.Cooldown:GetRegions()
                if cdText and cdText.SetFont then
                    cdText:SetFont(cachedFontPath, textSize, "OUTLINE")
                end
            end
        end

        if not button.Border then
            button.Border = CreateFrame("Frame", nil, button)
            button.Border:SetAllPoints()
            button.Border:SetFrameLevel(button:GetFrameLevel() + 1)
            PP.CreateBorder(button.Border, 0, 0, 0, 1)
        end
    end

    local gap = 1
    local perRow = 7
    local containerWidth = frame:GetWidth()

    local settings = GetSettingsForUnit(unit or 'target')
    local auraSize = (settings and settings.buffSize) or 22
    local debuffAuraSize = (settings and settings.debuffSize) or 22

    local showBuffs = true
    if settings and settings.showBuffs == false then
        showBuffs = false
    end

    -- Compute castbar offset for bottom-anchored auras so they sit below the cast bar
    local cbOffset = 0
    if settings.showCastbar then
        local cbH = settings.castbarHeight or 14
        if cbH <= 0 then cbH = 14 end
        cbOffset = -cbH
    end

    local buffs = CreateFrame("Frame", nil, frame)
    local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
        settings and settings.buffAnchor,
        settings and settings.buffGrowth
    )
    local buffCbOff = 0
    local bAnc = settings.buffAnchor or "topleft"
    if bAnc == "bottomleft" or bAnc == "bottomright" then
        buffCbOff = cbOffset
    end
    buffs:SetPoint(bia, frame, bfp, box * gap + (settings and settings.buffOffsetX or 0), boy * gap + buffCbOff + (settings and settings.buffOffsetY or 0))
    buffs:SetSize(containerWidth, auraSize)
    buffs.size = auraSize
    buffs.spacing = gap
    buffs.num = 4
    buffs.maxCols = AuraMaxCols(settings and settings.buffGrowth, settings and settings.maxBuffs or 4)
    buffs.initialAnchor = bia
    buffs.growthX = bgx
    buffs.growthY = bgy
    buffs.filter = "HELPFUL"
    buffs.PostCreateButton = SetupAuraIcon
    if not showBuffs then
        buffs:Hide()
        buffs.num = 0
    end
    frame.Buffs = buffs

    local maxDebuffs = (settings and settings.maxDebuffs) or 28

    -- Boss Simple Debuff Display: force Left anchor and frame-height-matched
    -- debuff size when the user has it enabled (default on).
    local unitIsBoss = unit and unit:match("^boss%d+$")
    if unitIsBoss and settings and settings.simpleDebuffs ~= false then
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        debuffAuraSize = settings.healthHeight + powerH
    end

    local dAnc = settings and settings.debuffAnchor or "bottomleft"
    if unitIsBoss and settings and settings.simpleDebuffs ~= false then
        dAnc = "left"
    end
    do
        local debuffs = CreateFrame("Frame", nil, frame)
        local effectiveAnc = (dAnc ~= "none") and dAnc or "bottomleft"
        local simpleOn = unitIsBoss and settings and settings.simpleDebuffs ~= false
        local effectiveGrowth = simpleOn and "auto" or (settings and settings.debuffGrowth or "auto")
        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(effectiveAnc, effectiveGrowth)
        local debuffCbOff = 0
        if effectiveAnc == "bottomleft" or effectiveAnc == "bottomright" then
            debuffCbOff = cbOffset
        end
        -- Simple Debuff Display: anchor to the top of the health bar, not the
        -- frame's vertical center (matches preview layout).
        local simpleAnchorParent = frame
        if simpleOn then
            dia = "TOPRIGHT"
            dfp = "TOPLEFT"
            dox = 0
            doy = 0
            debuffCbOff = 0
            simpleAnchorParent = frame.Health or frame
        end
        debuffs:SetPoint(dia, simpleAnchorParent, dfp, dox * gap + (settings and settings.debuffOffsetX or 0), doy * gap + debuffCbOff + (settings and settings.debuffOffsetY or 0))
        debuffs:SetSize(containerWidth, debuffAuraSize)
        debuffs.size = debuffAuraSize
        debuffs.spacing = gap
        debuffs.num = (dAnc ~= "none") and maxDebuffs or 0
        debuffs.maxCols = AuraMaxCols(effectiveGrowth, maxDebuffs)
        debuffs.initialAnchor = dia
        debuffs.growthX = dgx
        debuffs.growthY = dgy
        debuffs.filter = "HARMFUL"
        debuffs.PostCreateButton = SetupAuraIcon
        if settings and settings.onlyPlayerDebuffs then
            debuffs.onlyShowPlayer = true
        end
        if dAnc == "none" then
            debuffs:Hide()
        end
        frame.Debuffs = debuffs
    end
end

local function StyleFullFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and settings.powerHeight or 0
    local playerTargetHeight = settings.healthHeight + powerExtra
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local targetFrameHeight = playerTargetHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = playerTargetHeight
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"

    if unit == "player" then
        local pSide = settings.portraitSide or "left"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end
        -- Class power "above" adds height above health bar ("top" floats outside)
        local cpAboveH = 0
        if SpecHasClassPower() then
            local cpSt = settings.classPowerStyle or "none"
            local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
            if cpSt == "modern" and cpPo == "above" then
                local cpSizeAdj = settings.classPowerSize or 8
                local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                cpAboveH = cpPipH
            end
        end
        local playerHeightWithCp = playerTargetHeight + cpAboveH
        -- Apply portrait size adjustment
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerHeightWithCp + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if not showPortrait then
            totalWidth = settings.frameWidth
            portraitHeight = 0
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            -- Detached: portrait doesn't contribute to frame width
            totalWidth = settings.frameWidth
            portraitHeight = 0
        end
        -- Health bar xOffset: only offset when portrait is attached on the left
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, playerHeightWithCp + btbExtra)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        -- Always create absorb bar; oUF element disabled later if not wanted
        CreateAbsorbBar(frame, unit, settings)
        -- Always create portrait; hide backdrop when disabled
        frame.Portrait = CreatePortrait(frame, pSide, playerHeightWithCp, unit)
        EllesmereUI._ufPortraitSide[frame] = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and settings.powerHeight or 0
            local topOff = cpAboveH + powerAboveOff
            frame.Health:ClearAllPoints()
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -topOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
            PP.Height(frame.Health, settings.healthHeight)
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRI
            frame.Health._topOffset = topOff
        end

        -- Always create castbar; oUF element disabled later if not wanted
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, "player")

        -- Create player buffs and debuffs using shared aura setup
        CreateTargetAuras(frame, unit)
    elseif unit == "target" then
        local pSide = settings.portraitSide or "right"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "right" end
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerTargetHeight + pSizeAdj
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            totalWidth = settings.frameWidth
        end
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, targetFrameHeight)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        CreateAbsorbBar(frame, unit, settings)
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, unit)
        frame.Portrait = CreatePortrait(frame, pSide, playerTargetHeight, unit)
        EllesmereUI._ufPortraitSide[frame] = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and settings.powerHeight or 0
            frame.Health:ClearAllPoints()
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
            PP.Height(frame.Health, settings.healthHeight)
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRI
            frame.Health._topOffset = powerAboveOff
        end

        CreateTargetAuras(frame, unit)
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition)

    -- Raid target marker icon -- oUF's RaidTargetIndicator element manages
    -- visibility via RAID_TARGET_UPDATE. We only assign the element when
    -- enabled so oUF registers/unregisters the event accordingly.
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "right"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT"
            or (rmAlign == "center") and "TOP"
            or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", frame, rmAnchor, rmX, rmY)
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameStrata(frame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(frame:GetFrameLevel() + 20, frame.Health:GetFrameLevel() + 12))
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "both"
    local centerContent = settings.centerTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "both"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Center text: if active, hide left/right
        if cc ~= "none" then
            leftText:Hide()
            rightText:Hide()
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            centerText:SetWidth(0)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            leftText:ClearAllPoints()
            if lc ~= "none" then
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                -- Constrain width when opposing right text exists
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else leftText:Hide() end

            SetFSFont(rightText, rsz)
            rightText:ClearAllPoints()
            if rc ~= "none" then
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                -- Constrain width when opposing left text exists
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (powerIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached then
            local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
            local eSide = pSide
            if pSide == "top" then eSide = (unit == "player") and "left" or "right" end
            if eSide == "left" then
                local ppPos2 = settings.powerPosition or "below"
                local ppIsAtt2 = (ppPos2 == "below" or ppPos2 == "above")
                local barH = settings.healthHeight + (ppIsAtt2 and (settings.powerHeight or 6) or 0)
                local adj = barH + (settings.portraitSize or 0)
                if adj < 8 then adj = 8 end
                btbXOff = -adj
            end
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end


local function StyleFocusFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local fPpPos = settings.powerPosition or "below"
    local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
    local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
    local focusBarHeight = settings.healthHeight + powerHeight
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local focusFrameHeight = focusBarHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSide = settings.portraitSide or "right"
    -- For attached, "top" falls back to default side
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = focusBarHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    if not showPortrait then
        totalWidth = settings.frameWidth
    elseif isAttached then
        totalWidth = adjPortraitH + settings.frameWidth
    else
        totalWidth = settings.frameWidth
    end

    PP.Size(frame, totalWidth, focusFrameHeight)
    local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
    local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    CreateAbsorbBar(frame, unit, settings)
    frame.Castbar = CreateCastBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, focusBarHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local newXOff = (effectiveSide == "left") and snappedPortW or 0
        local newRI = (effectiveSide == "right") and snappedPortW or 0
        local powerAboveOff = (fPpPos == "above") and (settings.powerHeight or 6) or 0
        frame.Health:ClearAllPoints()
        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -powerAboveOff)
        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._xOffset = newXOff
        frame.Health._rightInset = newRI
        frame.Health._topOffset = powerAboveOff
    end

    PP.Size(frame, totalWidth, focusBarHeight)

    SetupShowOnCastBar(frame, "focus")

    CreateTargetAuras(frame, unit)

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition)

    -- Raid target marker icon
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "right"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT"
            or (rmAlign == "center") and "TOP"
            or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", frame, rmAnchor, rmX, rmY)
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, frame.Health)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content
    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Center text: if active, hide left/right
        if cc ~= "none" then
            leftText:Hide()
            rightText:Hide()
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            centerText:SetWidth(0)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            leftText:ClearAllPoints()
            if lc ~= "none" then
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    leftText:SetWidth(0)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else leftText:Hide() end

            SetFSFont(rightText, rsz)
            rightText:ClearAllPoints()
            if rc ~= "none" then
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    rightText:SetWidth(0)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (fPpIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached and effectiveSide == "left" then
            btbXOff = -adjPortraitH
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end

local function StyleSimpleFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local pSide = settings.portraitSide or "left"
    local totalWidth = settings.frameWidth
    local portraitOffset = 0  -- applied to Health TOPLEFT when portrait on left
    local healthRightInset = 0  -- applied to Health RIGHT when portrait on right
    if showPortrait then
        totalWidth = settings.healthHeight + settings.frameWidth
        if pSide == "right" then
            healthRightInset = settings.healthHeight
        else
            portraitOffset = settings.healthHeight
        end
    end

    PP.Size(frame, totalWidth, settings.healthHeight)

    local health = CreateFrame("StatusBar", nil, frame)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portraitOffset, 0)
    PP.Point(health, "RIGHT", frame, "RIGHT", -healthRightInset, 0)
    PP.Height(health, settings.healthHeight)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    -- Inherit health bar texture from donor frame (focus > target > player)
    local donor = GetMiniDonorSettings()
    local unitKey = UnitToSettingsKey(unit)
    local origTex = settings.healthBarTexture
    settings.healthBarTexture = donor.healthBarTexture
    ApplyHealthBarTexture(health, unitKey)
    settings.healthBarTexture = origTex
    ApplyHealthBarAlpha(health, unitKey)
    ApplyDarkTheme(health)
    health:SetReverseFill(settings.healthReverseFill and true or false)

    frame.Health = health

    -- Always create portrait; hide backdrop when disabled. Mirrors StylePetFrame.
    frame.Portrait = CreatePortrait(frame, pSide, settings.healthHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    if frame.Portrait and frame.Portrait.backdrop and showPortrait then
        local portW = math.max(settings.healthHeight, 1)
        health:ClearAllPoints()
        if pSide == "right" then
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 0, 0)
            PP.Point(health, "RIGHT", frame, "RIGHT", -portW, 0)
            health._xOffset = 0
            health._rightInset = portW
        else
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portW, 0)
            PP.Point(health, "RIGHT", frame, "RIGHT", 0, 0)
            health._xOffset = portW
            health._rightInset = 0
        end
        PP.Height(health, settings.healthHeight)
        health._topOffset = 0
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition)

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "none"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, settings.leftTextSize or settings.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, settings.rightTextSize or settings.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, settings.centerTextSize or settings.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "none"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    PP.Width(leftText, barW * 0.9)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else leftText:Hide() end
            SetFSFont(rightText, rsz)
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    PP.Width(rightText, barW * 0.9)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function StylePetFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local pSide = settings.portraitSide or "left"
    local totalWidth = settings.frameWidth
    local portraitOffset = 0
    local healthRightInset = 0

    if showPortrait then
        totalWidth = settings.healthHeight + settings.frameWidth
        if pSide == "right" then
            healthRightInset = settings.healthHeight
        else
            portraitOffset = settings.healthHeight
        end
    end

    PP.Size(frame, totalWidth, settings.healthHeight)

    local health = CreateFrame("StatusBar", nil, frame)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portraitOffset, 0)
    PP.Point(health, "RIGHT", frame, "RIGHT", -healthRightInset, 0)
    PP.Height(health, settings.healthHeight)
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bg

    health.colorClass = true
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    -- Inherit health bar texture from donor frame (focus > target > player)
    local donor = GetMiniDonorSettings()
    local unitKey = UnitToSettingsKey(unit)
    local origTex = settings.healthBarTexture
    settings.healthBarTexture = donor.healthBarTexture
    ApplyHealthBarTexture(health, unitKey)
    settings.healthBarTexture = origTex
    ApplyHealthBarAlpha(health, unitKey)
    ApplyDarkTheme(health)
    health:SetReverseFill(settings.healthReverseFill and true or false)

    frame.Health = health

    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, settings.healthHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then        frame.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar using healthHeight as the portrait width to avoid
    -- sub-pixel GetWidth() mismatches at frame creation time
    if frame.Portrait and frame.Portrait.backdrop and showPortrait then
        local portW = math.max(settings.healthHeight, 1)
        health:ClearAllPoints()
        if pSide == "right" then
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 0, 0)
            PP.Point(health, "RIGHT", frame, "RIGHT", -portW, 0)
            health._xOffset = 0
            health._rightInset = portW
        else
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portW, 0)
            PP.Point(health, "RIGHT", frame, "RIGHT", 0, 0)
            health._xOffset = portW
            health._rightInset = 0
        end
        PP.Height(health, settings.healthHeight)
        health._topOffset = 0
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition)

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "none"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, settings.leftTextSize or settings.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, settings.rightTextSize or settings.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, settings.centerTextSize or settings.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "none"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    PP.Width(leftText, barW * 0.9)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else leftText:Hide() end
            SetFSFont(rightText, rsz)
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    PP.Width(rightText, barW * 0.9)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function StyleBossFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local bPpPos = settings.powerPosition or "below"
    local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
    local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
    local bossBarHeight = settings.healthHeight + powerHeight
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    if not showPortrait then
        totalWidth = settings.frameWidth
    else
        totalWidth = bossBarHeight + settings.frameWidth
    end

    PP.Size(frame, totalWidth, bossBarHeight)
    local pSide = settings.portraitSide or "right"
    local healthRightInset = (showPortrait and pSide == "right") and bossBarHeight or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, portraitHeight, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, bossBarHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local powerAboveOff = (bPpPos == "above") and (settings.powerHeight or 6) or 0
        frame.Health:ClearAllPoints()
        if pSide == "left" then
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", snappedPortW, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
            frame.Health._xOffset = snappedPortW
            frame.Health._rightInset = 0
        else
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", 0, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -snappedPortW, 0)
            frame.Health._xOffset = 0
            frame.Health._rightInset = snappedPortW
        end
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._topOffset = powerAboveOff
    end

    PP.Size(frame, totalWidth, bossBarHeight)

    frame.Castbar = CreateCastBar(frame, unit, settings)
    SetupShowOnCastBar(frame, unit)

    CreateTargetAuras(frame, unit)

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition)

    -- Raid target marker icon (boss frames) -- anchored outside the LEFT edge
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "left"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        raidIcon:SetSize(rmSize, rmSize)
        if rmAlign == "left" then
            raidIcon:SetPoint("RIGHT", frame, "LEFT", rmX, rmY)
        elseif rmAlign == "center" then
            raidIcon:SetPoint("CENTER", frame, "CENTER", rmX, rmY)
        else
            raidIcon:SetPoint("LEFT", frame, "RIGHT", rmX, rmY)
        end
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, settings.leftTextSize or settings.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, settings.rightTextSize or settings.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, settings.centerTextSize or settings.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc)
        local rtag = ContentToTag(rc)
        local ctag = ContentToTag(cc)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 100
        if cc ~= "none" then
            SetFSFont(centerText, csz)
            centerText:ClearAllPoints()
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
            leftText:Hide(); rightText:Hide()
        else
            centerText:Hide()
            SetFSFont(leftText, lsz)
            if lc ~= "none" then
                leftText:ClearAllPoints()
                leftText:SetJustifyH("LEFT")
                PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
                if rc ~= "none" then
                    local rightUsed = EstimateUFTextWidth(rc)
                    PP.Width(leftText, math.max(barW - rightUsed - 10, 20))
                else
                    PP.Width(leftText, barW * 0.9)
                end
                leftText:Show()
                ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            else leftText:Hide() end
            SetFSFont(rightText, rsz)
            if rc ~= "none" then
                rightText:ClearAllPoints()
                rightText:SetJustifyH("RIGHT")
                PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
                if lc ~= "none" then
                    local leftUsed = EstimateUFTextWidth(lc)
                    PP.Width(rightText, math.max(barW - leftUsed - 10, 20))
                else
                    PP.Width(rightText, barW * 0.9)
                end
                rightText:Show()
                ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            else rightText:Hide() end
        end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


local function RegisterStylesOnce()
    if _G.EllesmereUF_StylesRegistered then
        return
    end
    _G.EllesmereUF_StylesRegistered = true

    oUF:RegisterStyle("EllesmerePlayer", function(frame, unit)
        StyleFullFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereTarget", function(frame, unit)
        StyleFullFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmereFocus", function(frame, unit)
        StyleFocusFrame(frame, unit)
    end)
    oUF:RegisterStyle("EllesmerePet", function(frame, unit)
        StylePetFrame(frame, unit)
    end)
    -- Skip unitIsUnit check in portrait Update for eventless frames to avoid
    -- secret boolean errors. These frames poll on OnUpdate so redundant
    -- portrait updates are harmless.
    local function ApplyPortraitOverride(frame)
        if not frame.Portrait then return end
        frame.Portrait.Override = function(self, event, evtUnit)
            local element = self.Portrait
            if not element then return end
            local u = self.unit
            if element.PreUpdate then element:PreUpdate(u) end
            local isAvailable = UnitIsConnected(u) and UnitIsVisible(u)
            if element:IsObjectType("PlayerModel") then
                if not isAvailable then
                    element:SetCamDistanceScale(0.25)
                    element:SetPortraitZoom(0)
                    element:SetPosition(0, 0, 0.25)
                    element:ClearModel()
                    element:SetModel([[Interface\Buttons\TalkToMeQuestionMark.m2]])
                else
                    element:SetCamDistanceScale(1)
                    element:SetPortraitZoom(1)
                    element:SetPosition(0, 0, 0)
                    element:SetUnit(u)
                end
            else
                if isAvailable then
                    SetPortraitTexture(element, u)
                else
                    element:SetTexture([[Interface\Icons\INV_Misc_QuestionMark]])
                end
            end
            if element.PostUpdate then element:PostUpdate(u, isAvailable) end
        end
    end
    oUF:RegisterStyle("EllesmereTargetTarget", function(frame, unit)
        StyleSimpleFrame(frame, unit)
        ApplyPortraitOverride(frame)
    end)
    oUF:RegisterStyle("EllesmereFocusTarget", function(frame, unit)
        StyleSimpleFrame(frame, unit)
        ApplyPortraitOverride(frame)
    end)
    oUF:RegisterStyle("EllesmereBoss", function(frame, unit)
        StyleBossFrame(frame, unit)
    end)
end


-- Swap portrait mode (3D / 2D / class theme) without recreating frames.
-- All three objects already exist on the backdrop; we just show/hide and reassign frame.Portrait.
-- Swap portrait mode (3D / 2D / class theme) without recreating frames.
-- 2D and class textures exist on the backdrop; 3D PlayerModel is lazy-created on first use.
local function SwapPortraitMode(frame)
    local portrait = frame.Portrait
    if not portrait or not portrait.backdrop then return end
    local bd = portrait.backdrop
    if not bd._2d then return end

    local wantMode
    do
        local unit2 = frame.unit or frame:GetAttribute("unit")
        local uKey = UnitToSettingsKey(unit2)
        local s = uKey and db.profile[uKey]
        wantMode = (s and s.portraitMode) or db.profile.portraitMode or "2d"
    end

    local unit = frame.unit or frame:GetAttribute("unit")

    local curMode
    if portrait.isClass then curMode = "class"
    elseif portrait.is2D then curMode = "2d"
    else curMode = "3d" end

    if wantMode == curMode then return end

    -- Disable the oUF element so it unregisters events for the old object
    if frame:IsElementEnabled("Portrait") then
        frame:DisableElement("Portrait")
    end

    -- Hide all
    if bd._3d then bd._3d:ClearModel(); bd._3d:Hide() end
    bd._2d:Hide()
    if bd._class then bd._class:Hide() end

    if wantMode == "class" and bd._class then
        -- Re-apply class art style texture (may have changed since creation)
        local uKey2 = UnitToSettingsKey(unit)
        local s2 = uKey2 and db.profile[uKey2]
        local classStyle = (s2 and s2.classThemeStyle) or "modern"
        local _, ct = UnitClass(unit)
        ApplyClassIconTexture(bd._class, ct or "WARRIOR", classStyle)
        bd._class:Show()
        bd._2d:Hide()
        bd._class.backdrop = bd
        bd._class.isClass = true
        frame.Portrait = bd._class
    elseif wantMode == "3d" then
        -- Lazily create the PlayerModel on first switch to 3D
        if bd._ensureModel3D then bd._ensureModel3D() end
        if not bd._3d then return end
        bd._3d:Show()
        bd._3d.backdrop = bd
        bd._3d.is2D = false
        bd._3d.isClass = nil
        frame.Portrait = bd._3d
    else
        bd._2d:Show()
        bd._2d.backdrop = bd
        bd._2d.is2D = true
        bd._2d.isClass = nil
        frame.Portrait = bd._2d
    end

    -- Re-enable the oUF element with the new object and force an update
    frame:EnableElement("Portrait")
    frame.Portrait:ForceUpdate()
end

-------------------------------------------------------------------------------
--  Custom Class Power Display (Bars / Circles styles)
-------------------------------------------------------------------------------
local CLASS_POWER_TYPES = {
    ROGUE       = Enum.PowerType.ComboPoints,
    DRUID       = { [103] = Enum.PowerType.ComboPoints,     -- Feral
                    [104] = Enum.PowerType.ComboPoints,     -- Guardian (cat form)
                    [105] = Enum.PowerType.ComboPoints },   -- Restoration (cat form)
    MAGE        = {
        [62] = { Enum.PowerType.ArcaneCharges, 4 }, -- Arcane
        [64] = { "ICICLES", 5 },                    -- Frost: aura-based pip stacks
    },
    WARLOCK     = Enum.PowerType.SoulShards,
    PALADIN     = Enum.PowerType.HolyPower,
    MONK        = {
        [269] = { Enum.PowerType.Chi, 5 },        -- Windwalker
        [268] = { "BREWMASTER_STAGGER", 1, "bar" },  -- Brewmaster: single bar
    },
    EVOKER      = Enum.PowerType.Essence,
    DEATHKNIGHT = Enum.PowerType.Runes,
    -- Spec-specific custom resources (resolved at creation time)
    DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 },
                    [1480] = { "SOUL_FRAGMENTS_DEVOURER", 50, "bar" } },
    SHAMAN      = { [263] = { "MAELSTROM_WEAPON", 10 } },
    HUNTER      = { [255] = { "TIP_OF_THE_SPEAR", 3 } },
    WARRIOR     = { [72]  = { "WHIRLWIND_STACKS", 4 } },
}

-- Returns true if the player's current spec has a class resource in CLASS_POWER_TYPES
SpecHasClassPower = function()
    local _, playerClass = UnitClass("player")
    local entry = CLASS_POWER_TYPES[playerClass]
    if not entry then return false end
    if type(entry) ~= "table" then return true end
    if entry[1] ~= nil then return true end
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
    return specID and entry[specID] ~= nil
end

local function DestroyCustomClassPower()
    if frames._customClassPower then
        frames._customClassPower:Hide()
        -- Unregister events on all children to prevent leaks
        local kids = { frames._customClassPower:GetChildren() }
        for _, child in ipairs(kids) do
            child:UnregisterAllEvents()
            child:SetScript("OnEvent", nil)
            child:Hide()
        end
        frames._customClassPower:SetParent(nil)
        frames._customClassPower = nil
    end
end

local function CreateCustomClassPower(playerFrame, style)
    local _, playerClass = UnitClass("player")
    local entry = CLASS_POWER_TYPES[playerClass]
    if not entry then return nil end

    -- Resolve spec-specific entries (table with specID keys)
    local powerType, customMax, isCustom, renderMode
    if type(entry) == "table" then
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        local specEntry = specID and entry[specID]
        if not specEntry then return nil end
        if type(specEntry) == "table" and type(specEntry[1]) == "string" then
            -- String-keyed custom resource (e.g. "SOUL_FRAGMENTS_VENGEANCE")
            powerType = specEntry[1]
            customMax = specEntry[2]
            renderMode = specEntry[3]  -- optional "bar" for continuous fill
            isCustom = true
        elseif type(specEntry) == "table" then
            -- Numeric powerType wrapped in a spec table (e.g. Chi for Windwalker)
            powerType = specEntry[1]
            customMax = specEntry[2]
            isCustom = false
        else
            powerType = specEntry
            isCustom = false
        end
    else
        powerType = entry
        isCustom = false
    end
    local isBarMode = (renderMode == "bar")

    local maxPower
    if isCustom then
        -- For custom resources, get live max from EllesmereUI helpers
        if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            maxPower = 6
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            local _, mMax = EllesmereUI.GetMaelstromWeapon()
            maxPower = (mMax and mMax > 0) and mMax or customMax
        elseif powerType == "TIP_OF_THE_SPEAR" then
            maxPower = customMax
        elseif powerType == "WHIRLWIND_STACKS" then
            maxPower = customMax
        elseif powerType == "ICICLES" then
            maxPower = customMax or 5
        elseif powerType == "SOUL_FRAGMENTS_DEVOURER" then
            local maxC = customMax or 50
            if EllesmereUI and EllesmereUI.GetSoulFragments then
                local _, m = EllesmereUI.GetSoulFragments()
                if m and m > 0 then maxC = m end
            end
            maxPower = maxC
            customMax = maxPower
        elseif powerType == "BREWMASTER_STAGGER" then
            -- Bar mode: "max" is player max HP; StatusBar fills with UnitStagger.
            local mh = UnitHealthMax("player") or 0
            if issecretvalue and issecretvalue(mh) then mh = 0 end
            maxPower = (mh > 0) and mh or 1
            customMax = maxPower
        else
            maxPower = customMax or 5
        end
    else
        maxPower = UnitPowerMax("player", powerType) or 5
        if maxPower <= 0 then maxPower = 5 end
    end

    local isModern = (style == "modern")
    local isCircle = (style == "circles")
    local sizeAdj = db.profile.player.classPowerSize or 8
    local spacingAdj = db.profile.player.classPowerSpacing or 2
    local pipSize = isModern and sizeAdj or (isCircle and (sizeAdj + 6) or (sizeAdj + 12))
    local pipH = isModern and math.max(3, math.floor(sizeAdj * 0.375)) or (isCircle and (sizeAdj + 6) or (sizeAdj))
    local gap = spacingAdj
    local pad = isModern and 0 or 4
    -- Snap all dimensions to physical pixel boundaries
    pipSize = PP.Scale(pipSize)
    pipH = PP.Scale(pipH)
    gap = PP.Scale(gap)
    pad = PP.Scale(pad)
    -- For bar-mode resources (stagger), "maxPower" is a raw game value
    -- (e.g. player max HP) and doesn't drive layout width. Use a 5-pip
    -- equivalent so the bar matches the visual footprint of Chi / Combo
    -- Points etc.
    local drawPipCount = isBarMode and 5 or maxPower
    local totalW = drawPipCount * pipSize + (drawPipCount - 1) * gap + pad
    local totalH = pipH + pad

    local container = CreateFrame("Frame", nil, UIParent)
    PP.Size(container, totalW, totalH)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(10)

    -- Background color behind all pips (spans left edge of first pip to right edge of last pip)
    local bgCol = db.profile.player.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
    local containerBg = container:CreateTexture(nil, "BACKGROUND")
    containerBg:SetAllPoints()
    containerBg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
    container._bg = containerBg

    -- Empty pip color (shown when pip is not filled)
    local emptyCol = db.profile.player.classPowerEmptyColor or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }

    if not isModern then
        -- Border
        MakeBorder(container, 0, 0, 0, 0.8)
    end

    -- 1px inset bottom border for "above" position (matches frame border color)
    -- Must be on a separate overlay frame at a higher frame level than pip child frames,
    -- because child frames always render over parent textures regardless of draw layer.
    local cpBdrOverlay = CreateFrame("Frame", nil, container)
    cpBdrOverlay:SetAllPoints()
    cpBdrOverlay:SetFrameLevel(container:GetFrameLevel() + 20)
    local cpBottomBdr = cpBdrOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    cpBottomBdr:SetHeight(1)
    PP.Point(cpBottomBdr, "BOTTOMLEFT", cpBdrOverlay, "BOTTOMLEFT", 0, 0)
    PP.Point(cpBottomBdr, "BOTTOMRIGHT", cpBdrOverlay, "BOTTOMRIGHT", 0, 0)
    cpBdrOverlay:Hide()  -- shown only when position is "above"
    container._bottomBdr = cpBottomBdr
    container._bottomBdrFrame = cpBdrOverlay

    local useClassColor = db.profile.player.classPowerClassColor ~= false
    local cr, cg, cb
    if not useClassColor then
        local cc = db.profile.player.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
        cr, cg, cb = cc.r, cc.g, cc.b
    else
        -- Pull from EUI global color system: resource color > class color
        local rc = EllesmereUI.GetResourceColor and EllesmereUI.GetResourceColor(playerClass)
        if rc then
            cr, cg, cb = rc.r, rc.g, rc.b
        else
            local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(playerClass)
            if cc then cr, cg, cb = cc.r, cc.g, cc.b else cr, cg, cb = 1, 1, 1 end
        end
    end

    local function MakePip(parent, index)
        local pip = CreateFrame("Frame", nil, parent)
        PP.Size(pip, pipSize, pipH)
        local x = (index - 1) * (pipSize + gap) + pad / 2
        PP.Point(pip, "LEFT", parent, "LEFT", x, 0)

        -- Empty bar color (visible when pip is not filled)
        local pipEmpty = pip:CreateTexture(nil, "ARTWORK", nil, 0)
        pipEmpty:SetAllPoints()
        if isCircle then
            pipEmpty:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipEmpty:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
        else
            pipEmpty:SetColorTexture(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
        end

        -- Fill color (on top of empty)
        local pipFill = pip:CreateTexture(nil, "ARTWORK", nil, 1)
        pipFill:SetAllPoints()

        if isCircle then
            pipFill:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipFill:SetVertexColor(cr, cg, cb, 1)
        else
            pipFill:SetColorTexture(cr, cg, cb, 1)
        end

        pip._fill = pipFill
        pip._empty = pipEmpty
        return pip
    end

    local pips = {}
    local staggerBar  -- set only in bar mode
    if isBarMode then
        -- Single StatusBar filling the container; color updates per-tier.
        local inset = pad / 2
        staggerBar = CreateFrame("StatusBar", nil, container)
        staggerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        staggerBar:GetStatusBarTexture():SetHorizTile(false)
        PP.Point(staggerBar, "TOPLEFT",     container, "TOPLEFT",     inset, 0)
        PP.Point(staggerBar, "BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, 0)
        staggerBar:SetMinMaxValues(0, maxPower)
        staggerBar:SetValue(0)
        staggerBar:GetStatusBarTexture():SetVertexColor(0.2, 0.8, 0.2, 1)
        container._staggerBar = staggerBar
    else
        for i = 1, maxPower do
            pips[i] = MakePip(container, i)
        end
    end

    -- Update function
    local isSecretResource = (powerType == "SOUL_FRAGMENTS_VENGEANCE")
    local function UpdatePips()
        -- Bar-mode resources fill a single StatusBar instead of discrete pips.
        if isBarMode and staggerBar then
            if powerType == "BREWMASTER_STAGGER" then
                local stagger = UnitStagger and UnitStagger("player") or 0
                local maxHP   = UnitHealthMax("player") or 0
                local tainted = issecretvalue
                             and (issecretvalue(stagger) or issecretvalue(maxHP))
                if tainted then
                    staggerBar:Hide()
                    return
                end
                if maxHP <= 0 then maxHP = 1 end
                if staggerBar._lastMax ~= maxHP then
                    staggerBar._lastMax = maxHP
                    staggerBar:SetMinMaxValues(0, maxHP)
                end
                staggerBar:SetValue(stagger)
                local pct = stagger / maxHP
                local sr, sg, sb
                if pct >= 0.6 then      sr, sg, sb = 1.0,  0.2,  0.2
                elseif pct >= 0.3 then  sr, sg, sb = 1.0,  0.85, 0.2
                else                    sr, sg, sb = 0.2,  0.8,  0.2 end
                if staggerBar._lastR ~= sr or staggerBar._lastG ~= sg or staggerBar._lastB ~= sb then
                    staggerBar._lastR, staggerBar._lastG, staggerBar._lastB = sr, sg, sb
                    staggerBar:GetStatusBarTexture():SetVertexColor(sr, sg, sb, 1)
                end
            elseif powerType == "SOUL_FRAGMENTS_DEVOURER" then
                local cur, maxC = 0, customMax or 50
                if EllesmereUI and EllesmereUI.GetSoulFragments then
                    cur, maxC = EllesmereUI.GetSoulFragments()
                    if not maxC or maxC <= 0 then maxC = customMax or 50 end
                end
                if staggerBar._lastMax ~= maxC then
                    staggerBar._lastMax = maxC
                    staggerBar:SetMinMaxValues(0, maxC)
                end
                staggerBar:SetValue(cur or 0)
                -- Use class color (DH)
                if not staggerBar._colorSet then
                    staggerBar._colorSet = true
                    local rc = EllesmereUI.GetResourceColor and EllesmereUI.GetResourceColor("DEMONHUNTER")
                    local cc = rc or (EllesmereUI.GetClassColor and EllesmereUI.GetClassColor("DEMONHUNTER"))
                    if cc then
                        staggerBar:GetStatusBarTexture():SetVertexColor(cc.r, cc.g, cc.b, 1)
                    end
                end
            end
            if not staggerBar:IsShown() then staggerBar:Show() end
            return
        end
        local cur, max
        if isCustom then
            -- Custom resource: use EllesmereUI tracker functions
            if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
                cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
                max = 6
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
                cur, max = EllesmereUI.GetMaelstromWeapon()
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
                cur, max = EllesmereUI.GetTipOfTheSpear()
            elseif powerType == "WHIRLWIND_STACKS" and EllesmereUI and EllesmereUI.GetWhirlwindStacks then
                cur, max = EllesmereUI.GetWhirlwindStacks()
            elseif powerType == "ICICLES" then
                -- Frost Mage Icicles: stack count from the Icicles aura (205473).
                local count = 0
                if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local aura = C_UnitAuras.GetPlayerAuraBySpellID(205473)
                    if aura then
                        count = aura.applications or aura.charges or aura.points or 0
                        if count > 5 then count = 5 end
                    end
                end
                cur, max = count, 5
            else
                cur, max = 0, maxPower
            end
            if not max or max <= 0 then max = maxPower end
        else
            cur = UnitPower("player", powerType) or 0
            max = UnitPowerMax("player", powerType) or maxPower

            -- Handle runes specially (count available runes)
            if powerType == Enum.PowerType.Runes then
                cur = 0
                for i = 1, max do
                    local start, duration, ready = GetRuneCooldown(i)
                    if ready then cur = cur + 1 end
                end
            end
        end

        -- Rebuild pips if max changed
        if max ~= #pips and max > 0 then
            for _, p in ipairs(pips) do p:Hide() end
            local newTotalW = max * pipSize + (max - 1) * gap + pad
            container:SetWidth(newTotalW)
            for i = 1, max do
                if not pips[i] then
                    pips[i] = MakePip(container, i)
                end
                local x = (i - 1) * (pipSize + gap) + pad / 2
                pips[i]:ClearAllPoints()
                PP.Point(pips[i], "TOPLEFT", container, "TOPLEFT", x, 0)
                PP.Size(pips[i], pipSize, pipH)
                pips[i]:Show()
            end
            -- Re-stretch pips if in "above" position
            if container._repositionForWidth then
                local fw = db and db.profile and db.profile.player and db.profile.player.frameWidth or 181
                container._repositionForWidth(fw)
            end
        end

        if isSecretResource then
            -- Secret-value path: use StatusBar overlays per pip
            for i = 1, #pips do
                if pips[i] then
                    if not pips[i]._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pips[i])
                        sb:SetAllPoints(pips[i]._fill or pips[i])
                        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        sb:SetStatusBarColor(cr, cg, cb, 1)
                        sb:SetFrameLevel(pips[i]:GetFrameLevel() + 1)
                        pips[i]._secretBar = sb
                    end
                    pips[i]._secretBar:SetMinMaxValues(i - 1, i)
                    pips[i]._secretBar:SetValue(cur)
                    pips[i]._secretBar:SetStatusBarColor(cr, cg, cb, 1)
                    pips[i]._secretBar:Show()
                    -- Hide normal fill; StatusBar replaces it
                    if pips[i]._fill then pips[i]._fill:Hide() end
                end
            end
        else
            -- Clean-value path
            for i = 1, #pips do
                if pips[i] then
                    if pips[i]._secretBar then pips[i]._secretBar:Hide() end
                    if pips[i]._fill then
                        if i <= cur then
                            pips[i]._fill:Show()
                        else
                            pips[i]._fill:Hide()
                        end
                    end
                end
            end
        end
    end

    -- Event driver
    local eventFrame = CreateFrame("Frame", nil, container)
    if isCustom then
        -- Per-resource event registration: only register what each resource
        -- actually needs to avoid unnecessary event traffic.
        -- Icicles are aura-driven; Maelstrom Weapon too. Everything else
        -- polls via OnUpdate (either Lua API changes mid-combat or there
        -- isn't a reliable event to hook).
        local auraDriven    = (powerType == "MAELSTROM_WEAPON" or powerType == "ICICLES")
        local needsOnUpdate = not auraDriven
        local needsAura     = auraDriven
        local needsCasts    = (powerType == "TIP_OF_THE_SPEAR" or powerType == "WHIRLWIND_STACKS")

        if needsOnUpdate then
            local elapsed = 0
            eventFrame:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 0.1 then return end
                elapsed = 0
                UpdatePips()
            end)
        end

        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

        if needsAura then
            eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        end
        if needsCasts then
            eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            eventFrame:RegisterEvent("PLAYER_DEAD")
            eventFrame:RegisterEvent("PLAYER_ALIVE")
        end
        if powerType == "WHIRLWIND_STACKS" then
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end

        eventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                DestroyCustomClassPower()
                frames._classPowerBar = nil
                -- Don't call ReloadFrames here. The profile system handles
                -- the full rebuild via RefreshAllAddons -> _EUF_ReloadFrames.
                -- Width/height matches are re-applied after CDM clears
                -- _specProfileSwitching in ProcessSpecChange.
                return
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                if not _G._ERB_AceDB and EllesmereUI then
                    local unit, castGUID, spellID = ...
                    if unit == "player" then
                        if EllesmereUI.HandleTipOfTheSpear then
                            EllesmereUI.HandleTipOfTheSpear(event, unit, castGUID, spellID)
                        end
                        if EllesmereUI.HandleWhirlwindStacks then
                            EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
                        end
                    end
                end
            elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                if not _G._ERB_AceDB and EllesmereUI then
                    if EllesmereUI.HandleTipOfTheSpear then
                        EllesmereUI.HandleTipOfTheSpear(event)
                    end
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event)
                    end
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not _G._ERB_AceDB and EllesmereUI and EllesmereUI.HandleWhirlwindStacks then
                    EllesmereUI.HandleWhirlwindStacks(event)
                end
            end
            UpdatePips()
        end)
    else
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if powerType == Enum.PowerType.Runes then
            eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
        end
        -- Guardian/Resto druids: show combo points only in cat form
        local druidFormToggle = false
        if playerClass == "DRUID" and powerType == Enum.PowerType.ComboPoints then
            local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
            local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
            if specID == 104 or specID == 105 then
                druidFormToggle = true
                eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            end
        end
        eventFrame:SetScript("OnEvent", function(_, event, unit)
            if druidFormToggle and (event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD") then
                local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
                container:SetShown(form == 1)
            end
            if event == "PLAYER_ENTERING_WORLD" or event == "RUNE_POWER_UPDATE"
               or (unit == "player") then
                UpdatePips()
            end
        end)
    end

    -- For druid form-toggle specs, start hidden if not in cat form
    if playerClass == "DRUID" and powerType == Enum.PowerType.ComboPoints then
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        if specID == 104 or specID == 105 then
            local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
            if form ~= 1 then container:Hide() end
        end
    end

    UpdatePips()
    container._updatePips = UpdatePips
    container._pips = pips
    container._pipSize = pipSize
    container._pipH = pipH
    container._gap = gap
    container._pad = pad

    -- Reposition pips to fill a given width (for "above" position)
    -- Uses Snap() to round all positions to physical pixel boundaries
    -- so gaps between pips are guaranteed identical.
    container._repositionForWidth = function(targetW)
        local n = #pips
        if n <= 0 then return end
        local efs = container:GetEffectiveScale()
        if efs <= 0 then efs = 1 end
        local function Snap(v) return math_floor(v * efs + 0.5) / efs end
        local intW = math_floor(targetW)
        local gapPx = Snap(gap)
        local totalGapW = (n - 1) * gapPx
        local totalPipW = intW - totalGapW
        local basePipW = totalPipW / n
        for i = 1, n do
            local leftEdge = Snap((i - 1) * (basePipW + gapPx))
            local rightEdge = Snap((i - 1) * (basePipW + gapPx) + basePipW)
            local w = rightEdge - leftEdge
            pips[i]:ClearAllPoints()
            pips[i]:SetSize(w, pipH)
            pips[i]:SetPoint("TOPLEFT", container, "TOPLEFT", leftEdge, 0)
        end
        container:SetWidth(intW)
        container:SetHeight(pipH)
    end

    return container
end

local function ReloadFrames()
    ResolveFontPath()
    if InCombatLockdown() then
        return
    end

    -- Reset cached settings map so it rebuilds with fresh DB references
    unitSettingsMap = nil

    -- Normalize opacity values: old profiles stored 0-1 floats, new format is 0-100 integers
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
        if prof.healthBarOpacity and prof.healthBarOpacity <= 1.0 then
            prof.healthBarOpacity = math.floor(prof.healthBarOpacity * 100 + 0.5)
        end
        if prof.powerBarOpacity and prof.powerBarOpacity <= 1.0 then
            prof.powerBarOpacity = math.floor(prof.powerBarOpacity * 100 + 0.5)
        end
        for _, uKey in ipairs(UNITS) do
            local s = prof[uKey]
            if s then
                if s.healthBarOpacity and s.healthBarOpacity <= 1.0 then
                    s.healthBarOpacity = math.floor(s.healthBarOpacity * 100 + 0.5)
                end
                if s.powerBarOpacity and s.powerBarOpacity <= 1.0 then
                    s.powerBarOpacity = math.floor(s.powerBarOpacity * 100 + 0.5)
                end
            end
        end
    end

    local profile = db.profile
    local castbarColor = GetCastbarColor()
    local castbarOpacity = profile.castbarOpacity
    local enabled = profile.enabledFrames

    -- Uses global font
    local donorFontPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    -- Live enable/disable frames without reload
    local function ToggleFrame(unit, frame)
        if not frame then return end
        local unitKey = unit:match("^boss%d$") and "boss" or unit
        local isEnabled = enabled[unitKey] ~= false
        -- Check group visibility for player/target/focus
        if isEnabled and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
            local s = profile[unitKey]
            if s then
                local inRaid = IsInRaid()
                local inParty = not inRaid and IsInGroup()
                local solo = not inRaid and not inParty
                local vis = (inRaid and (s.showInRaid ~= false))
                    or (inParty and (s.showInParty ~= false))
                    or (solo and (s.showSolo ~= false))
                if not vis then isEnabled = false end
            end
        end
        if isEnabled then
            if not frame:IsShown() and UnitExists(unit) then
                frame:SetAttribute("unit", unit)
                frame:Show()
                -- Re-enable core oUF elements; per-feature elements (Portrait,
                -- Buffs, HealthPrediction) are handled by the per-unit sections below
                for _, elem in ipairs({"Health", "Power", "Debuffs"}) do
                    if frame[elem] and not frame:IsElementEnabled(elem) then
                        frame:EnableElement(elem)
                    end
                end
                frame:UpdateAllElements("ToggleFrame")
            end
        else
            if frame:IsShown() then
                -- Disable all oUF elements for zero performance impact
                for _, elem in ipairs({"Health", "Power", "Portrait", "Castbar", "Buffs", "Debuffs", "HealthPrediction"}) do
                    if frame[elem] and frame:IsElementEnabled(elem) then
                        frame:DisableElement(elem)
                    end
                end
                frame:SetAttribute("unit", nil)
                frame:Hide()
            end
        end
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" then
            ToggleFrame(unit, frame)
        end
    end

    for unit, frame in pairs(frames) do
        if type(unit) == "string" and unit:sub(1,1) ~= "_" and frame then
            local unitKey = unit:match("^boss%d$") and "boss" or unit
            if enabled[unitKey] == false then
                -- skip disabled frames
            else
            -- Restore position and scale from profile
            if unitKey == "boss" then
                local bossPos = db.profile.positions.boss
                local bossSettings = db.profile.boss or {}
                local barHeight = (bossSettings.healthHeight or 34) + (bossSettings.powerHeight or 6) + (bossSettings.castbarHeight or 14)
                local gap = 10
                -- Prefer the user-configured Vertical Spacing slider; fall back to
                -- the computed barHeight+gap so an uninitialized profile is sane.
                local bossSpacing = db.profile.bossSpacing or (barHeight + gap)
                local bossIdx = tonumber(unit:match("(%d+)$"))
                local bossAnchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("boss")
                local canRepoBoss1 = bossPos
                                 and not (EllesmereUI and EllesmereUI._unlockActive)
                                 and (not bossAnchored or not frame:GetLeft())
                if bossIdx == 1 and canRepoBoss1 then
                    frame:ClearAllPoints()
                    frame:SetPoint(bossPos.point, UIParent, bossPos.relPoint or bossPos.point, bossPos.x, bossPos.y)
                elseif bossIdx and bossIdx > 1 and not (EllesmereUI and EllesmereUI._unlockActive) then
                    -- boss2..5 always re-chain off the previous boss with the
                    -- current Vertical Spacing value, regardless of saved pos.
                    local prev = frames["boss" .. (bossIdx - 1)]
                    if prev then
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -bossSpacing)
                    end
                end
            else
                if not (EllesmereUI and EllesmereUI._unlockActive) then
                    -- Skip for unlock-anchored elements (anchor system is authority)
                    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unit)
                    if not anchored or not frame:GetLeft() then
                        ApplyFramePosition(frame, unit)
                    end
                end
            end
            local settings = GetSettingsForUnit(unit)
            local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
            -- Mini frames never use detached portraits
            local unitIsMini = unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$")
            if unitIsMini and pStyle == "detached" then pStyle = "attached" end
            local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false

            -- Keep the cached portrait side in sync with user-edited settings.
            -- Downstream re-snap code (SnapLayout, health anchor math) reads
            -- the portrait side lookup, so without this update the side
            -- toggle wouldn't flip until a full UI reload.
            if settings.portraitSide then
                EllesmereUI._ufPortraitSide[frame] = settings.portraitSide
            end

            -- Re-anchor the attached-mode portrait backdrop when the side
            -- flips. Detached mode is re-anchored further below.
            if frame.Portrait and frame.Portrait.backdrop
               and pStyle == "attached"
               and settings.portraitSide then
                local bd = frame.Portrait.backdrop
                bd:ClearAllPoints()
                if settings.portraitSide == "left" then
                    PP.Point(bd, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                else
                    PP.Point(bd, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                end
            end

            -- Swap 2D/3D portrait mode if changed (no reload needed)
            if frame.Portrait then
                SwapPortraitMode(frame)
            end

            -- Refresh class art style texture (may have changed without mode change)
            if frame.Portrait and frame.Portrait.backdrop and frame.Portrait.backdrop._class then
                local uKey = UnitToSettingsKey(unit) or unit
                local uSettings = uKey and db.profile[uKey]
                local isClassMode = ((uSettings and uSettings.portraitMode) or "2d") == "class"
                if isClassMode then
                    local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
                    local _, ct = UnitClass(unit)
                    ApplyClassIconTexture(frame.Portrait.backdrop._class, ct or "WARRIOR", classStyle)
                end
            end

            -- Show/hide portrait live (no reload needed)
            if frame.Portrait and frame.Portrait.backdrop then
                local uKey = UnitToSettingsKey(unit) or unit
                local uSettings = uKey and db.profile[uKey]
                local isClassMode = ((uSettings and uSettings.portraitMode) or "2d") == "class"
                if showPortrait then
                    frame.Portrait.backdrop:Show()
                    if not frame:IsElementEnabled("Portrait") then
                        frame:EnableElement("Portrait")
                        frame.Portrait:ForceUpdate()
                    end
                else
                    frame.Portrait.backdrop:Hide()
                    if frame:IsElementEnabled("Portrait") then
                        frame:DisableElement("Portrait")
                    end
                end
                -- Live-update detached portrait shape/mask/border
                ApplyDetachedPortraitShape(frame.Portrait.backdrop, uSettings, unit)
                -- Raise detached portrait above border/text/power
                local isDetachedNow = pStyle == "detached"
                if isDetachedNow then
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 15)
                else
                    frame.Portrait.backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
                end
            end

            if unit == "player" or unit == "target" then
                local ppPos = settings.powerPosition or "below"
                local ppIsAtt = (ppPos == "below" or ppPos == "above")
                local ppExtra = ppIsAtt and settings.powerHeight or 0
                local playerTargetHeight = settings.healthHeight + ppExtra
                -- Class power "above" adds height above health bar (player only, "top" floats outside)
                local cpAboveH = 0
                if unit == "player" and SpecHasClassPower() then
                    local cpSt = settings.classPowerStyle or "none"
                    local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
                    if cpSt == "modern" and cpPo == "above" then
                        local cpSizeAdj = settings.classPowerSize or 8
                        local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                        cpAboveH = cpPipH
                    end
                end
                local playerTargetHeightWithCp = playerTargetHeight + cpAboveH
                local btbPos = settings.btbPosition or "bottom"
                local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
                local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
                local targetFrameHeight = playerTargetHeight + btbExtra
                local portraitHeight = 0
                local totalWidth = 0
                local isAttached = pStyle == "attached"
                local pSizeAdj = settings.portraitSize or 0
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end

                if unit == "player" then
                    local pSide = settings.portraitSide or "left"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "left" end
                    local adjPortraitH = playerTargetHeightWithCp + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, playerTargetHeightWithCp + btbExtra)

                    if frame.Portrait and frame.Portrait.backdrop then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        -- Reposition portrait for attached/detached
                        frame.Portrait.backdrop:ClearAllPoints()
                        local pBtbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -pBtbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -pBtbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        -- Use portrait's actual snapped width for flush alignment
                        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                            local snappedPortW = frame.Portrait.backdrop:GetWidth()
                            healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                            healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                        end
                        frame.Health._xOffset = healthXOffset
                        frame.Health._rightInset = healthRightInset
                        local powerAboveOff = (ppPos == "above") and settings.powerHeight or 0
                        local hTopOff = cpAboveH + powerAboveOff + (btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                        frame.Health._topOffset = hTopOff
                        frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", healthXOffset, PP.Scale(-hTopOff))
                        frame.Health:SetPoint("RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw = settings.frameWidth
                        local ppIsDetached = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached and (settings.powerWidth or 0) > 0 then
                            pw = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw, settings.powerHeight)
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                        -- Gray out power bar background for generic melee NPCs
                        if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                            local shouldGray = false
                            if unit ~= "player" and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                                local cls = UnitClassification(unit)
                                local isBoss = (cls == "worldboss")
                                local isElite = (cls == "elite" or cls == "rareelite")
                                local lvl = UnitLevel(unit)
                                local pLvl = UnitLevel("player")
                                local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                local isMB = isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                local isCst = (UnitClassBase and UnitClassBase(unit) == "PALADIN")
                                if not isBoss and not isMB and not isCst then shouldGray = true end
                            end
                            if shouldGray then
                                frame.Power._grayedOut = true
                                if frame.Power.bg then
                                    frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                    frame.Power.bg:SetAlpha(1)
                                end
                            else
                                frame.Power._grayedOut = false
                            end
                        end
                    end
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if settings.showPlayerCastbar then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            if castbarBg then
                                local cbW = db.profile.player.playerCastbarWidth or 181
                                local cbH = db.profile.player.playerCastbarHeight or 14
                                castbarBg:SetSize(cbW, cbH)
                                -- Resize cast icon to match castbar height
                                if frame.Castbar._iconFrame then
                                    frame.Castbar._iconFrame:SetSize(cbH, cbH)
                                    if not frame.Castbar:IsShown() or settings.showPlayerCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    end
                                end
                                -- Position owned by centralized unlock system (no manual anchor)
                                -- Respect hide-while-not-casting
                                if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                    castbarBg:Hide()
                                else
                                    castbarBg:Show()
                                end
                            end
                            -- Store per-unit settings for PostCastStart
                            frame.Castbar._eufSettings = settings
                            -- Resolve per-unit fill color
                            local pCbColor = castbarColor
                            if settings.castbarClassColored then
                                local _, classToken = UnitClass("player")
                                if classToken and EllesmereUI.GetClassColor then
                                    pCbColor = EllesmereUI.GetClassColor(classToken) or castbarColor
                                end
                            elseif settings.castbarFillColor then
                                pCbColor = settings.castbarFillColor
                            end
                            frame.Castbar:SetStatusBarColor(pCbColor.r, pCbColor.g, pCbColor.b, castbarOpacity)
                            -- Apply cast bar text settings
                            if frame.Castbar.Text then
                                local snSz = settings.castSpellNameSize or 11
                                SetFSFont(frame.Castbar.Text, snSz)
                                local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                                frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                            end
                            if frame.Castbar.Time then
                                local dtSz = settings.castDurationSize or 10
                                SetFSFont(frame.Castbar.Time, dtSz)
                                local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                                frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                                frame.Castbar._showDuration = settings.showCastDuration ~= false
                                frame.Castbar._durationSize = dtSz
                                -- Show/hide immediately (covers both toggle directions)
                                if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                                    frame.Castbar.Time:Show()
                                elseif not frame.Castbar._showDuration then
                                    frame.Castbar.Time:Hide()
                                end
                            end
                            if frame.Castbar.Target then
                                local tsSz = settings.castSpellTargetSize or 11
                                SetFSFont(frame.Castbar.Target, tsSz)
                                local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                                frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                                frame.Castbar._showTarget = settings.showCastTarget ~= false
                                if not frame.Castbar._showTarget then
                                    frame.Castbar.Target:Hide()
                                end
                                if frame.Castbar._layoutTextZones then
                                    frame.Castbar:_layoutTextZones()
                                end
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            if castbarBg then castbarBg:Hide() end
                        end
                    end

                    -- Live toggle + style player absorbs.
                    -- Never Enable/Disable the oUF HealthPrediction element
                    -- here: tearing down the element unregisters events and
                    -- resets the calculator, which causes the absorb display
                    -- to go stale over time on the player frame specifically
                    -- (target/focus don't do this toggle and stay accurate).
                    -- Instead, just Show/Hide the bar itself -- the element
                    -- keeps running in the background and the value stays
                    -- live whether the bar is visible or not.
                    if frame.HealthPrediction and frame.HealthPrediction.damageAbsorb then
                        local absStyle = settings.showPlayerAbsorb
                        if absStyle and absStyle ~= "none" then
                            ApplyAbsorbStyle(frame.HealthPrediction.damageAbsorb, absStyle, settings)
                            frame.HealthPrediction.damageAbsorb:Show()
                            -- Force an immediate value update so the bar doesn't
                            -- show stale/uninitialized fill covering the full frame.
                            if frame.HealthPrediction.Override then
                                frame.HealthPrediction.Override(frame, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
                            end
                        else
                            frame.HealthPrediction.damageAbsorb:Hide()
                        end
                    end

                    -- Live toggle player buffs
                    if frame.Buffs then
                        if settings.showBuffs then
                            if not frame:IsElementEnabled("Buffs") then
                                frame:EnableElement("Buffs")
                            end
                            frame.Buffs:Show()
                            frame.Buffs.num = settings.maxBuffs or 4
                            -- Reposition buffs based on anchor/growth settings
                            local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                                settings.buffAnchor, settings.buffGrowth
                            )
                            -- Offset bottom-anchored buffs below castbar when locked to frame
                            local buffCbOff = 0
                            if (settings.buffAnchor == "bottomleft" or settings.buffAnchor == "bottomright"
                                or settings.buffAnchor == "left" or settings.buffAnchor == "right")
                                and settings.showPlayerCastbar then
                                local cbH = settings.playerCastbarHeight or 0
                                if cbH <= 0 then cbH = 14 end
                                buffCbOff = -cbH
                            end
                            -- Only reanchor + ForceUpdate when layout actually changed
                            local buffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, buffCbOff, bgx or 0, bgy or 0, settings.maxBuffs or 4, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0)
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                frame.Buffs.size = settings.buffSize or 22
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + buffCbOff + (settings.buffOffsetY or 0))
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4)
                                if frame.Buffs.ForceUpdate then
                                    frame.Buffs:ForceUpdate()
                                end
                            end
                            ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10)
                        else
                            if frame:IsElementEnabled("Buffs") then
                                frame:DisableElement("Buffs")
                            end
                            frame.Buffs:Hide()
                            frame.Buffs.num = 0
                        end
                    end

                    -- Live toggle player debuffs
                    if frame.Debuffs then
                        local dAnc = settings.debuffAnchor or "none"
                        if dAnc == "none" then
                            if frame:IsElementEnabled("Debuffs") then
                                frame:DisableElement("Debuffs")
                            end
                            frame.Debuffs:Hide()
                            frame.Debuffs.num = 0
                        else
                            if not frame:IsElementEnabled("Debuffs") then
                                frame:EnableElement("Debuffs")
                            end
                            frame.Debuffs:Show()
                            frame.Debuffs.num = settings.maxDebuffs or 10
                            local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                            local debuffCbOff = 0
                            if (dAnc == "bottomleft" or dAnc == "bottomright") and settings.showPlayerCastbar then
                                local cbH = settings.playerCastbarHeight or 0
                                if cbH <= 0 then cbH = 14 end
                                debuffCbOff = -cbH
                            end
                            local debuffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, debuffCbOff, dgx or 0, dgy or 0, settings.maxDebuffs or 10, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0)
                            if frame.Debuffs._lastDebuffKey ~= debuffKey then
                                frame.Debuffs._lastDebuffKey = debuffKey
                                frame.Debuffs.size = settings.debuffSize or 22
                                frame.Debuffs:ClearAllPoints()
                                frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + debuffCbOff + (settings.debuffOffsetY or 0))
                                frame.Debuffs.initialAnchor = dia
                                frame.Debuffs.growthX = dgx
                                frame.Debuffs.growthY = dgy
                                frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10)
                                if frame.Debuffs.ForceUpdate then
                                    frame.Debuffs:ForceUpdate()
                                end
                            end
                            ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10)
                        end
                    end

                    -- Reposition name and health text (player)
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (player)
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        -- Compute BTB xOffset for left-side portrait (attached only)
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        local ppBtbAnchor = (ppIsAtt and frame.Power) or frame.Health
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, ppBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", ppBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            -- Update BTB bg color
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    UpdateBordersForScale(frame, unit)
                    ReparentBarsToClip(frame, settings.powerPosition)

                elseif unit == "target" then
                    local pSide = settings.portraitSide or "right"
                    local effectiveSide = pSide
                    if isAttached and pSide == "top" then effectiveSide = "right" end
                    local adjPortraitH = playerTargetHeight + pSizeAdj
                    if adjPortraitH < 8 then adjPortraitH = 8 end
                    if not showPortrait then
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    elseif isAttached then
                        totalWidth = adjPortraitH + settings.frameWidth
                        portraitHeight = adjPortraitH
                    else
                        totalWidth = settings.frameWidth
                        portraitHeight = 0
                    end
                    -- Health bar xOffset: only offset when portrait is attached on the left
                    local healthXOffset = 0
                    local healthRightInset = 0
                    if showPortrait and isAttached and effectiveSide == "left" then
                        healthXOffset = portraitHeight
                    elseif showPortrait and isAttached and effectiveSide == "right" then
                        healthRightInset = portraitHeight
                    end

                    PP.Size(frame, totalWidth, targetFrameHeight)

                    if frame.Portrait and frame.Portrait.backdrop then
                        PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                        frame.Portrait.backdrop:ClearAllPoints()
                        local btbTopOff = (btbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                        if isAttached then
                            if effectiveSide == "left" then
                                PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -btbTopOff)
                            else
                                PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -btbTopOff)
                            end
                        else
                            if effectiveSide == "top" then
                                frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                            elseif effectiveSide == "left" then
                                frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                            else
                                frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                            end
                        end
                        if frame.Portrait.backdrop._2d then
                            UnsnapTex(frame.Portrait.backdrop._2d)
                        end
                        if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                            frame.Portrait:ForceUpdate()
                        end
                    end
                    if frame.Health then
                        frame.Health:ClearAllPoints()
                        -- Use portrait's actual snapped width for flush alignment
                        if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                            local snappedPortW = frame.Portrait.backdrop:GetWidth()
                            healthXOffset = (effectiveSide == "left") and snappedPortW or 0
                            healthRightInset = (effectiveSide == "right") and snappedPortW or 0
                        end
                        local tBtbTopOff = (btbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                        local tPowerAboveOff = (ppPos == "above") and settings.powerHeight or 0
                        local tTopOff = tBtbTopOff + tPowerAboveOff
                        frame.Health._xOffset = healthXOffset
                        frame.Health._rightInset = healthRightInset
                        frame.Health._topOffset = tTopOff
                        frame.Health:SetPoint("TOPLEFT", frame, "TOPLEFT", healthXOffset, PP.Scale(-tTopOff))
                        frame.Health:SetPoint("RIGHT", frame, "RIGHT", -healthRightInset, 0)
                        PP.Height(frame.Health, settings.healthHeight)
                    end
                    if frame.Power then
                        local pw2 = settings.frameWidth
                        local ppIsDetached2 = (ppPos == "detached_top" or ppPos == "detached_bottom")
                        if ppIsDetached2 and (settings.powerWidth or 0) > 0 then
                            pw2 = settings.powerWidth
                        end
                        PP.Size(frame.Power, pw2, settings.powerHeight)
                        frame.Power:ClearAllPoints()
                        if ppPos == "none" then
                            frame.Power:Hide()
                        elseif ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                            frame.Power:Show()
                        elseif ppPos == "detached_top" then
                            frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                            frame.Power:Show()
                        elseif ppPos == "detached_bottom" then
                            frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                            frame.Power:Show()
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                            frame.Power:Show()
                        end
                        if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                        -- Gray out power bar background for generic melee NPCs
                        if ppPos ~= "none" and (ppPos == "below" or ppPos == "above") then
                            local shouldGray = false
                            if unit ~= "player" and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                                local cls = UnitClassification(unit)
                                local isBoss = (cls == "worldboss")
                                local isElite = (cls == "elite" or cls == "rareelite")
                                local lvl = UnitLevel(unit)
                                local pLvl = UnitLevel("player")
                                local lvlOk = lvl and not (issecretvalue and issecretvalue(lvl))
                                local pLvlOk = pLvl and not (issecretvalue and issecretvalue(pLvl))
                                local isMB = isElite and lvlOk and (lvl == -1 or (pLvlOk and lvl >= pLvl + 1))
                                local isCst = (UnitClassBase and UnitClassBase(unit) == "PALADIN")
                                if not isBoss and not isMB and not isCst then shouldGray = true end
                            end
                            if shouldGray then
                                frame.Power._grayedOut = true
                                if frame.Power.bg then
                                    frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                    frame.Power.bg:SetAlpha(1)
                                end
                            else
                                frame.Power._grayedOut = false
                            end
                        end
                    end

                    -- Reposition name and health text
                    if frame._applyTextTags then
                        frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "both", settings.centerTextContent or "none")
                    end
                    if frame._applyTextPositions then
                        frame._applyTextPositions(settings)
                    end

                    -- Bottom Text Bar update (target) ? must come before castbar so castbar can anchor to it
                    local tPpBtbAnchor = (ppIsAtt and (settings.powerHeight or 0) > 0 and frame.Power and frame.Power:IsShown()) and frame.Power or frame.Health
                    if settings.bottomTextBar then
                        local btbPos2 = settings.btbPosition or "bottom"
                        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
                        local btbIsDetached = not btbIsAtt
                        local btbW2 = btbIsDetached and (settings.btbWidth or 0) or 0
                        local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or totalWidth
                        local btbXOff = 0
                        if btbIsAtt and showPortrait and isAttached and effectiveSide == "left" then
                            btbXOff = -adjPortraitH
                        end
                        if not frame.BottomTextBar then
                            frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, tPpBtbAnchor, btbXOff, totalWidth)
                            frame._btb = frame.BottomTextBar
                        else
                            local btb = frame.BottomTextBar
                            PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                            btb:ClearAllPoints()
                            if btbPos2 == "top" then
                                PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                            elseif btbPos2 == "detached_top" then
                                btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                            elseif btbPos2 == "detached_bottom" then
                                btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                            else
                                PP.Point(btb, "TOPLEFT", tPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                            end
                            if btb.bg then
                                local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                                local bga = settings.btbBgOpacity or 1.0
                                btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                            end
                            if btb._applyBTBTextTags then
                                btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                            end
                            if btb._applyBTBTextPositions then
                                btb._applyBTBTextPositions(settings)
                                if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                            end
                            btb:Show()
                        end
                    elseif frame.BottomTextBar then
                        frame.BottomTextBar:Hide()
                    end

                    -- Castbar (target)
                    if frame.Castbar then
                        local castbarBg = frame.Castbar:GetParent()
                        if castbarBg then
                            if settings.showCastbar ~= false then
                                if not frame:IsElementEnabled("Castbar") then
                                    frame:EnableElement("Castbar")
                                end
                                local cbW2 = settings.castbarWidth or 181
                                local cbH2 = settings.castbarHeight or 14
                                castbarBg:SetSize(cbW2, cbH2)
                                if frame.Castbar._iconFrame then
                                    frame.Castbar._iconFrame:SetSize(cbH2, cbH2)
                                    if not frame.Castbar:IsShown() then
                                        frame.Castbar._iconFrame:Hide()
                                    elseif settings.showCastIcon == false then
                                        frame.Castbar._iconFrame:Hide()
                                    else
                                        frame.Castbar._iconFrame:Show()
                                    end
                                end
                                -- Position owned by centralized unlock system
                                -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                                if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                    castbarBg:Hide()
                                else
                                    castbarBg:Show()
                                end
                            else
                                if frame:IsElementEnabled("Castbar") then
                                    frame:DisableElement("Castbar")
                                end
                                frame.Castbar:Hide()
                                castbarBg:Hide()
                            end
                        end
                        -- Store per-unit settings for PostCastStart
                        frame.Castbar._eufSettings = settings
                        -- Resolve per-unit fill color
                        local tCbColor = castbarColor
                        if settings.castbarFillColor then
                            tCbColor = settings.castbarFillColor
                        end
                        frame.Castbar:SetStatusBarColor(tCbColor.r, tCbColor.g, tCbColor.b, castbarOpacity)
                        -- Apply cast bar text settings
                        if frame.Castbar.Text then
                            local snSz = settings.castSpellNameSize or 11
                            SetFSFont(frame.Castbar.Text, snSz)
                            local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                            frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                        end
                        if frame.Castbar.Time then
                            local dtSz = settings.castDurationSize or 10
                            SetFSFont(frame.Castbar.Time, dtSz)
                            local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                            frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                            frame.Castbar._showDuration = settings.showCastDuration ~= false
                            frame.Castbar._durationSize = dtSz
                            if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                                frame.Castbar.Time:Show()
                            elseif not frame.Castbar._showDuration then
                                frame.Castbar.Time:Hide()
                            end
                        end
                        if frame.Castbar.Target then
                            local tsSz = settings.castSpellTargetSize or 11
                            SetFSFont(frame.Castbar.Target, tsSz)
                            local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                            frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                            frame.Castbar._showTarget = settings.showCastTarget ~= false
                            if not frame.Castbar._showTarget then
                                frame.Castbar.Target:Hide()
                            end
                            if frame.Castbar._syncOffsetsAndLayout then
                                frame.Castbar:_syncOffsetsAndLayout(settings)
                            end
                        end
                    end

                    -- Buffs
                    if frame.Buffs then
                        local showBuffs = settings.showBuffs ~= false
                        if showBuffs then
                            if not frame:IsElementEnabled("Buffs") then
                                frame:EnableElement("Buffs")
                            end
                            frame.Buffs:Show()
                            frame.Buffs.num = settings.maxBuffs or 20
                            local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                                settings.buffAnchor, settings.buffGrowth
                            )
                            local liveCbOff = 0
                            if settings.showCastbar ~= false then
                                local bAnc = settings.buffAnchor or "topleft"
                                if bAnc == "bottomleft" or bAnc == "bottomright" then
                                    local cbH = settings.castbarHeight or 14
                                    if cbH <= 0 then cbH = 14 end
                                    liveCbOff = -cbH
                                end
                            end
                            local buffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, bgx or 0, bgy or 0, settings.maxBuffs or 20, liveCbOff, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0)
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                frame.Buffs.size = settings.buffSize or 22
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + liveCbOff + (settings.buffOffsetY or 0))
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4)
                                if frame.Buffs.ForceUpdate then
                                    frame.Buffs:ForceUpdate()
                                end
                            end
                        else
                            if frame:IsElementEnabled("Buffs") then
                                frame:DisableElement("Buffs")
                            end
                            frame.Buffs:Hide()
                            frame.Buffs.num = 0
                        end
                        ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10)
                    end

                    -- Debuffs
                    if frame.Debuffs then
                        local dAnc = settings.debuffAnchor or "bottomleft"
                        if dAnc == "none" then
                            if frame:IsElementEnabled("Debuffs") then
                                frame:DisableElement("Debuffs")
                            end
                            frame.Debuffs:Hide()
                            frame.Debuffs.num = 0
                        else
                            if not frame:IsElementEnabled("Debuffs") then
                                frame:EnableElement("Debuffs")
                            end
                            frame.Debuffs:Show()
                            frame.Debuffs.num = settings.maxDebuffs or 20
                            frame.Debuffs.onlyShowPlayer = settings.onlyPlayerDebuffs and true or nil
                            local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                            local liveDbCbOff = 0
                            if settings.showCastbar ~= false then
                                if dAnc == "bottomleft" or dAnc == "bottomright" then
                                    local cbH = settings.castbarHeight or 14
                                    if cbH <= 0 then cbH = 14 end
                                    liveDbCbOff = -cbH
                                end
                            end
                            local debuffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, dgx or 0, dgy or 0, settings.maxDebuffs or 20, liveDbCbOff, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0, settings.onlyPlayerDebuffs and 1 or 0)
                            if frame.Debuffs._lastDebuffKey ~= debuffKey then
                                frame.Debuffs._lastDebuffKey = debuffKey
                                frame.Debuffs.size = settings.debuffSize or 22
                                frame.Debuffs:ClearAllPoints()
                                frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + liveDbCbOff + (settings.debuffOffsetY or 0))
                                frame.Debuffs.initialAnchor = dia
                                frame.Debuffs.growthX = dgx
                                frame.Debuffs.growthY = dgy
                                frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10)
                                if frame.Debuffs.ForceUpdate then
                                    frame.Debuffs:ForceUpdate()
                                end
                            end
                        end
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10)
                    end

                    UpdateBordersForScale(frame, unit)
                    ReparentBarsToClip(frame, settings.powerPosition)
                end

                -- (health tag re-tagging now handled by _applyTextTags above)

            elseif unit == "focus" then
                local fPpPos = settings.powerPosition or "below"
                local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
                local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
                local focusBarHeight = settings.healthHeight + powerHeight
                local fBtbPos = settings.btbPosition or "bottom"
                local fBtbIsAtt = (fBtbPos == "top" or fBtbPos == "bottom")
                local fBtbExtra = (settings.bottomTextBar and fBtbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
                local totalWidth = 0
                local focusPStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
                local isAttached = focusPStyle == "attached"
                local pSide = settings.portraitSide or "right"
                local effectiveSide = pSide
                if isAttached and pSide == "top" then effectiveSide = "right" end
                local pSizeAdj = settings.portraitSize or 0
                if not isAttached then pSizeAdj = pSizeAdj + 10 end
                local pXOff = settings.portraitX or 0
                local pYOff = settings.portraitY or 0
                if not isAttached then pYOff = pYOff + 5 end
                local adjPortraitH = focusBarHeight + pSizeAdj
                if adjPortraitH < 8 then adjPortraitH = 8 end

                if not showPortrait then
                    totalWidth = settings.frameWidth
                elseif isAttached then
                    totalWidth = adjPortraitH + settings.frameWidth
                else
                    totalWidth = settings.frameWidth
                end

                PP.Size(frame, totalWidth, focusBarHeight + fBtbExtra)

                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
                    -- Trim portrait to stay within frame bounds
                    if showPortrait and isAttached then
                        local frameW = frame:GetWidth()
                        local frameH = frame:GetHeight()
                        local portW = frame.Portrait.backdrop:GetWidth()
                        local portH = frame.Portrait.backdrop:GetHeight()
                        if portW + settings.frameWidth > frameW + 0.01 then
                            PP.Width(frame.Portrait.backdrop, frameW - settings.frameWidth)
                        end
                        if portH > frameH + 0.01 then
                            PP.Height(frame.Portrait.backdrop, frameH)
                        end
                    end
                    -- Reposition portrait for attached/detached
                    frame.Portrait.backdrop:ClearAllPoints()
                    local fBtbTopOff = (fBtbPos == "top" and settings.bottomTextBar) and (settings.bottomTextBarHeight or 16) or 0
                    if isAttached then
                        if effectiveSide == "left" then
                            PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, -fBtbTopOff)
                        else
                            PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, -fBtbTopOff)
                        end
                    else
                        if effectiveSide == "top" then
                            frame.Portrait.backdrop:SetPoint("BOTTOM", frame.Health or frame, "TOP", pXOff, 15 + pYOff)
                        elseif effectiveSide == "left" then
                            frame.Portrait.backdrop:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -15 + pXOff, pYOff)
                        else
                            frame.Portrait.backdrop:SetPoint("TOPLEFT", frame.Health or frame, "TOPRIGHT", 15 + pXOff, pYOff)
                        end
                    end
                    -- Re-apply pixel snap disable after resize
                    if frame.Portrait.backdrop._2d then
                        UnsnapTex(frame.Portrait.backdrop._2d)
                    end
                    if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                        frame.Portrait:ForceUpdate()
                    end
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    local focusHealthXOff = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
                    local focusHealthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
                    -- Use portrait's actual snapped width for flush alignment
                    if showPortrait and isAttached and frame.Portrait and frame.Portrait.backdrop then
                        local snappedPortW = frame.Portrait.backdrop:GetWidth()
                        focusHealthXOff = (effectiveSide == "left") and snappedPortW or 0
                        focusHealthRightInset = (effectiveSide == "right") and snappedPortW or 0
                    end
                    local fHTopOff = (fBtbPos == "top" and settings.bottomTextBar and (settings.bottomTextBarHeight or 16) or 0)
                    local fPowerAboveOff = (fPpPos == "above") and (settings.powerHeight or 6) or 0
                    fHTopOff = fHTopOff + fPowerAboveOff
                    frame.Health._xOffset = focusHealthXOff
                    frame.Health._rightInset = focusHealthRightInset
                    frame.Health._topOffset = fHTopOff
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", focusHealthXOff, -fHTopOff)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -focusHealthRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                end
                if frame.Power then
                    local fpw = settings.frameWidth
                    local fPpIsDet = (fPpPos == "detached_top" or fPpPos == "detached_bottom")
                    if fPpIsDet and (settings.powerWidth or 0) > 0 then
                        fpw = settings.powerWidth
                    end
                    PP.Size(frame.Power, fpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if fPpPos == "none" then
                        frame.Power:Hide()
                    elseif fPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                        PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        frame.Power:Show()
                    elseif fPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif fPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                        PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end
                end
                if frame._applyTextTags then
                    frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "perhp", settings.centerTextContent or "none")
                end
                if frame._applyTextPositions then
                    frame._applyTextPositions(settings)
                end

                -- Bottom Text Bar update (focus) ? must come before castbar so castbar can anchor to it
                local fPpBtbAnchor = (fPpIsAtt and frame.Power) or frame.Health
                if settings.bottomTextBar then
                    local btbPos2 = settings.btbPosition or "bottom"
                    local btbIsAtt2 = (btbPos2 == "top" or btbPos2 == "bottom")
                    local btbIsDet2 = not btbIsAtt2
                    local btbW2 = btbIsDet2 and (settings.btbWidth or 0) or 0
                    local btbTW = (btbW2 > 0 and btbIsDet2) and btbW2 or totalWidth
                    local btbXOff = 0
                    if btbIsAtt2 and showPortrait and isAttached and effectiveSide == "left" then
                        btbXOff = -adjPortraitH
                    end
                    if not frame.BottomTextBar then
                        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, fPpBtbAnchor, btbXOff, totalWidth)
                        frame._btb = frame.BottomTextBar
                    else
                        local btb = frame.BottomTextBar
                        PP.Size(btb, btbTW, settings.bottomTextBarHeight or 16)
                        btb:ClearAllPoints()
                        if btbPos2 == "top" then
                            PP.Point(btb, "BOTTOMLEFT", frame.Health or frame, "TOPLEFT", btbXOff, 0)
                        elseif btbPos2 == "detached_top" then
                            btb:SetPoint("BOTTOM", frame, "TOP", settings.btbX or 0, 15 + (settings.btbY or 0))
                        elseif btbPos2 == "detached_bottom" then
                            btb:SetPoint("TOP", frame, "BOTTOM", settings.btbX or 0, -15 + (settings.btbY or 0))
                        else
                            PP.Point(btb, "TOPLEFT", fPpBtbAnchor, "BOTTOMLEFT", btbXOff, 0)
                        end
                        if btb.bg then
                            local bgc = settings.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                            local bga = settings.btbBgOpacity or 1.0
                            btb.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                        end
                        if btb._applyBTBTextTags then
                            btb._applyBTBTextTags(settings.btbLeftContent or "none", settings.btbRightContent or "none", settings.btbCenterContent or "none")
                        end
                        if btb._applyBTBTextPositions then
                            btb._applyBTBTextPositions(settings)
                            if btb._applyBTBClassIcon then btb._applyBTBClassIcon(settings) end
                        end
                        btb:Show()
                    end
                elseif frame.BottomTextBar then
                    frame.BottomTextBar:Hide()
                end

                -- Castbar (focus)
                if frame.Castbar then
                    local castbarBg = frame.Castbar:GetParent()
                    if castbarBg then
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            local cbW3 = settings.castbarWidth or 181
                            local cbH3 = settings.castbarHeight or 14
                            castbarBg:SetSize(cbW3, cbH3)
                            if frame.Castbar._iconFrame then
                                frame.Castbar._iconFrame:SetSize(cbH3, cbH3)
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            -- Position owned by centralized unlock system
                            -- Respect hide-while-not-casting: only show bg if inactive hiding is off or cast is active
                            if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                castbarBg:Hide()
                            else
                                castbarBg:Show()
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            castbarBg:Hide()
                        end
                    end
                    -- Store per-unit settings for PostCastStart
                    frame.Castbar._eufSettings = settings
                    -- Resolve per-unit fill color
                    local fCbColor = castbarColor
                    if settings.castbarFillColor then
                        fCbColor = settings.castbarFillColor
                    end
                    frame.Castbar:SetStatusBarColor(fCbColor.r, fCbColor.g, fCbColor.b, castbarOpacity)
                    -- Apply cast bar text settings
                    if frame.Castbar.Text then
                        local snSz = settings.castSpellNameSize or 11
                        SetFSFont(frame.Castbar.Text, snSz)
                        local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                        frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if frame.Castbar.Time then
                        local dtSz = settings.castDurationSize or 10
                        SetFSFont(frame.Castbar.Time, dtSz)
                        local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                        frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                        frame.Castbar._showDuration = settings.showCastDuration ~= false
                        frame.Castbar._durationSize = dtSz
                        if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                            frame.Castbar.Time:Show()
                        elseif not frame.Castbar._showDuration then
                            frame.Castbar.Time:Hide()
                        end
                    end
                    if frame.Castbar.Target then
                        local tsSz = settings.castSpellTargetSize or 11
                        SetFSFont(frame.Castbar.Target, tsSz)
                        local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                        frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                        frame.Castbar._showTarget = settings.showCastTarget ~= false
                        if not frame.Castbar._showTarget then
                            frame.Castbar.Target:Hide()
                        end
                        if frame.Castbar._layoutTextZones then
                            frame.Castbar:_layoutTextZones()
                        end
                    end
                end

                -- Debuffs (focus)
                if frame.Debuffs then
                    local dAnc = settings.debuffAnchor or "bottomleft"
                    if dAnc == "none" then
                        if frame:IsElementEnabled("Debuffs") then
                            frame:DisableElement("Debuffs")
                        end
                        frame.Debuffs:Hide()
                        frame.Debuffs.num = 0
                    else
                        if not frame:IsElementEnabled("Debuffs") then
                            frame:EnableElement("Debuffs")
                        end
                        frame.Debuffs:Show()
                        frame.Debuffs.num = settings.maxDebuffs or 10
                        frame.Debuffs.onlyShowPlayer = settings.onlyPlayerDebuffs and true or nil
                        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                        local focusDbCbOff = 0
                        if settings.showCastbar ~= false then
                            if dAnc == "bottomleft" or dAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                focusDbCbOff = -cbH
                            end
                        end
                        local debuffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, dgx or 0, dgy or 0, settings.maxDebuffs or 10, focusDbCbOff, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0, settings.onlyPlayerDebuffs and 1 or 0)
                        if frame.Debuffs._lastDebuffKey ~= debuffKey then
                            frame.Debuffs._lastDebuffKey = debuffKey
                            frame.Debuffs.size = settings.debuffSize or 22
                            frame.Debuffs:ClearAllPoints()
                            frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + focusDbCbOff + (settings.debuffOffsetY or 0))
                            frame.Debuffs.initialAnchor = dia
                            frame.Debuffs.growthX = dgx
                            frame.Debuffs.growthY = dgy
                            frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10)
                            if frame.Debuffs.ForceUpdate then
                                frame.Debuffs:ForceUpdate()
                            end
                        end
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10)
                    end
                end

                -- Buffs (focus)
                if frame.Buffs then
                    local showBuffs = settings.showBuffs ~= false
                    if showBuffs then
                        if not frame:IsElementEnabled("Buffs") then
                            frame:EnableElement("Buffs")
                        end
                        frame.Buffs:Show()
                        frame.Buffs.num = settings.maxBuffs or 4
                        local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                            settings.buffAnchor, settings.buffGrowth
                        )
                        local focusBfCbOff = 0
                        if settings.showCastbar ~= false then
                            local bAnc = settings.buffAnchor or "topleft"
                            if bAnc == "bottomleft" or bAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                focusBfCbOff = -cbH
                            end
                        end
                        local buffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, bgx or 0, bgy or 0, settings.maxBuffs or 4, focusBfCbOff, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0)
                        if frame.Buffs._lastBuffKey ~= buffKey then
                            frame.Buffs._lastBuffKey = buffKey
                            frame.Buffs.size = settings.buffSize or 22
                            frame.Buffs:ClearAllPoints()
                            frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + focusBfCbOff + (settings.buffOffsetY or 0))
                            frame.Buffs.initialAnchor = bia
                            frame.Buffs.growthX = bgx
                            frame.Buffs.growthY = bgy
                            frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4)
                            if frame.Buffs.ForceUpdate then
                                frame.Buffs:ForceUpdate()
                            end
                        end
                    else
                        if frame:IsElementEnabled("Buffs") then
                            frame:DisableElement("Buffs")
                        end
                        frame.Buffs:Hide()
                        frame.Buffs.num = 0
                    end
                    ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10)
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition)

            elseif unit == "pet" or unit == "targettarget" or unit == "focustarget" then
                -- Pet, ToT and FoT all share the same simple-frame layout:
                -- optional portrait on either side, health bar filling the rest.
                local miniPStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
                local showMiniPortrait = miniPStyle ~= "none" and settings.showPortrait ~= false
                local miniSide = settings.portraitSide or "left"
                local miniW = settings.frameWidth
                local miniLeftOff = 0
                local miniRightInset = 0
                if showMiniPortrait then
                    miniW = settings.healthHeight + settings.frameWidth
                    if miniSide == "right" then
                        miniRightInset = settings.healthHeight
                    else
                        miniLeftOff = settings.healthHeight
                    end
                end
                PP.Size(frame, miniW, settings.healthHeight)
                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, settings.healthHeight, settings.healthHeight)
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", miniLeftOff, 0)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -miniRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                    frame.Health._xOffset = miniLeftOff
                    frame.Health._rightInset = miniRightInset
                    frame.Health._topOffset = 0
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition)

            elseif unit:match("^boss%d$") then
                local bPpPos = settings.powerPosition or "below"
                local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
                local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
                local bossBarHeight = settings.healthHeight + powerHeight
                local totalWidth = 0

                if not showPortrait then
                    totalWidth = settings.frameWidth
                else
                    totalWidth = bossBarHeight + settings.frameWidth
                end

                PP.Size(frame, totalWidth, bossBarHeight)

                if frame.Portrait and frame.Portrait.backdrop then
                    PP.Size(frame.Portrait.backdrop, bossBarHeight, bossBarHeight)
                    local bossPSide = settings.portraitSide or "right"
                    frame.Portrait.backdrop:ClearAllPoints()
                    if bossPSide == "left" then
                        PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    else
                        PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    end
                    EllesmereUI._ufPortraitSide[frame] = bossPSide
                end
                if frame.Health then
                    frame.Health:ClearAllPoints()
                    -- Use portrait's actual snapped width for flush alignment
                    local bossPortW = 0
                    if showPortrait then
                        if frame.Portrait and frame.Portrait.backdrop then
                            bossPortW = frame.Portrait.backdrop:GetWidth()
                        else
                            bossPortW = bossBarHeight
                        end
                    end
                    local bossPSide = settings.portraitSide or "right"
                    local bossLeftOff  = (showPortrait and bossPSide == "left")  and bossPortW or 0
                    local bossRightInset = (showPortrait and bossPSide == "right") and bossPortW or 0
                    local bPowerAboveOff = (bPpPos == "above") and (settings.powerHeight or 6) or 0
                    PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", bossLeftOff, -bPowerAboveOff)
                    PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -bossRightInset, 0)
                    PP.Height(frame.Health, settings.healthHeight)
                    frame.Health._xOffset = bossLeftOff
                    frame.Health._rightInset = bossRightInset
                    frame.Health._topOffset = bPowerAboveOff
                end
                if frame.Power then
                    local bpw = settings.frameWidth
                    local bPpIsDet = (bPpPos == "detached_top" or bPpPos == "detached_bottom")
                    if bPpIsDet and (settings.powerWidth or 0) > 0 then
                        bpw = settings.powerWidth
                    end
                    frame.Power:SetSize(bpw, settings.powerHeight or 6)
                    frame.Power:ClearAllPoints()
                    if bPpPos == "none" then
                        frame.Power:Hide()
                    elseif bPpPos == "above" then
                        PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                        PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        frame.Power:Show()
                    elseif bPpPos == "detached_top" then
                        frame.Power:SetPoint("BOTTOM", frame.Health, "TOP", settings.powerX or 0, 15 + (settings.powerY or 0))
                        frame.Power:Show()
                    elseif bPpPos == "detached_bottom" then
                        frame.Power:SetPoint("TOP", frame.Health, "BOTTOM", settings.powerX or 0, -15 + (settings.powerY or 0))
                        frame.Power:Show()
                    else
                        PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                        PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        frame.Power:Show()
                    end
                    if frame.Power._applyPowerPercentText then frame.Power._applyPowerPercentText(settings) end

                    -- Gray out power bar background for generic melee NPCs
                    if bPpPos ~= "none" and (bPpPos == "below" or bPpPos == "above") then
                        local shouldGray = false
                        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) then
                            local cls = UnitClassification(unit)
                            local isBoss = (cls == "worldboss")
                            local isElite = (cls == "elite" or cls == "rareelite")
                            local lvl = UnitLevel(unit)
                            local pLvl = UnitLevel("player")
                            local isMB = isElite and (lvl == -1 or (pLvl and lvl >= pLvl + 1))
                            local isCst = (UnitClassBase and UnitClassBase(unit) == "PALADIN")
                            if not isBoss and not isMB and not isCst then shouldGray = true end
                        end
                        if shouldGray then
                            frame.Power._grayedOut = true
                            if frame.Power.bg then
                                frame.Power.bg:SetColorTexture(0.25, 0.25, 0.25, 1)
                                frame.Power.bg:SetAlpha(1)
                            end
                        else
                            frame.Power._grayedOut = false
                        end
                    end
                end

                -- Castbar (boss)
                if frame.Castbar then
                    local castbarBg = frame.Castbar:GetParent()
                    if castbarBg then
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            local castBarOffset = 0
                            if showPortrait then
                                castBarOffset = (bossBarHeight / 2)
                            end
                            castbarBg:SetSize(totalWidth, settings.castbarHeight or 14)
                            if frame.Castbar._iconFrame then
                                local cbH = settings.castbarHeight or 14
                                frame.Castbar._iconFrame:SetSize(cbH, cbH)
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            castbarBg:ClearAllPoints()
                            local bPpIsAtt2 = (bPpPos == "below" or bPpPos == "above")
                            local cbAnchor = (bPpIsAtt2 and frame.Power) or frame.Health
                            castbarBg:SetPoint("TOP", cbAnchor, "BOTTOM", castBarOffset, 0)
                            if settings.castbarHideWhenInactive and not frame.Castbar:IsShown() then
                                castbarBg:Hide()
                            else
                                castbarBg:Show()
                            end
                        else
                            if frame:IsElementEnabled("Castbar") then
                                frame:DisableElement("Castbar")
                            end
                            frame.Castbar:Hide()
                            castbarBg:Hide()
                        end
                    end
                    frame.Castbar._eufSettings = settings
                    local bCbColor = castbarColor
                    if settings.castbarFillColor then
                        bCbColor = settings.castbarFillColor
                    end
                    frame.Castbar:SetStatusBarColor(bCbColor.r, bCbColor.g, bCbColor.b, castbarOpacity)
                    if frame.Castbar.Text then
                        local snSz = settings.castSpellNameSize or 11
                        SetFSFont(frame.Castbar.Text, snSz)
                        local snC = settings.castSpellNameColor or { r=1, g=1, b=1 }
                        frame.Castbar.Text:SetTextColor(snC.r, snC.g, snC.b)
                    end
                    if frame.Castbar.Time then
                        local dtSz = settings.castDurationSize or 10
                        SetFSFont(frame.Castbar.Time, dtSz)
                        local dtC = settings.castDurationColor or { r=1, g=1, b=1 }
                        frame.Castbar.Time:SetTextColor(dtC.r, dtC.g, dtC.b)
                        frame.Castbar._showDuration = settings.showCastDuration ~= false
                        frame.Castbar._durationSize = dtSz
                        if frame.Castbar._showDuration and frame.Castbar:IsShown() then
                            frame.Castbar.Time:Show()
                        elseif not frame.Castbar._showDuration then
                            frame.Castbar.Time:Hide()
                        end
                    end
                    if frame.Castbar.Target then
                        local tsSz = settings.castSpellTargetSize or 11
                        SetFSFont(frame.Castbar.Target, tsSz)
                        local tsC = settings.castSpellTargetColor or { r=1, g=1, b=1 }
                        frame.Castbar.Target:SetTextColor(tsC.r, tsC.g, tsC.b)
                        frame.Castbar._showTarget = settings.showCastTarget ~= false
                        if not frame.Castbar._showTarget then
                            frame.Castbar.Target:Hide()
                        end
                        if frame.Castbar._layoutTextZones then
                            frame.Castbar:_layoutTextZones()
                        end
                    end
                end

                -- Debuffs (boss). Simple Debuff Display override forces Left
                -- anchor + frame-height-matched size when enabled.
                if frame.Debuffs then
                    local dAnc = settings.debuffAnchor or "bottomleft"
                    local effectiveDebuffSize = settings.debuffSize or 22
                    if settings.simpleDebuffs ~= false then
                        dAnc = "left"
                        local powerPos = settings.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
                        effectiveDebuffSize = settings.healthHeight + powerH
                    end
                    if dAnc == "none" then
                        if frame:IsElementEnabled("Debuffs") then
                            frame:DisableElement("Debuffs")
                        end
                        frame.Debuffs:Hide()
                        frame.Debuffs.num = 0
                    else
                        if not frame:IsElementEnabled("Debuffs") then
                            frame:EnableElement("Debuffs")
                        end
                        frame.Debuffs:Show()
                        frame.Debuffs.num = settings.maxDebuffs or 10
                        frame.Debuffs.onlyShowPlayer = settings.onlyPlayerDebuffs and true or nil
                        -- Boss frames: only show important debuffs unless the
                        -- user explicitly enabled onlyPlayerDebuffs.
                        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                        local liveDbCbOff = 0
                        if settings.showCastbar ~= false then
                            if dAnc == "bottomleft" or dAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                liveDbCbOff = -cbH
                            end
                        end
                        -- Simple Debuff Display: anchor the stack to the TOP
                        -- of the health bar instead of the frame's vertical
                        -- center so icons line up with the top edge. Matches
                        -- the preview's TOPRIGHT -> health.TOPLEFT anchor.
                        local simpleAnchorParent = frame
                        if settings.simpleDebuffs ~= false then
                            dia = "TOPRIGHT"
                            dfp = "TOPLEFT"
                            dox = 0
                            doy = 0
                            liveDbCbOff = 0
                            simpleAnchorParent = frame.Health or frame
                        end
                        local debuffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, dgx or 0, dgy or 0, settings.maxDebuffs or 10, liveDbCbOff, effectiveDebuffSize, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0, settings.onlyPlayerDebuffs and 1 or 0)
                        if frame.Debuffs._lastDebuffKey ~= debuffKey then
                            frame.Debuffs._lastDebuffKey = debuffKey
                            frame.Debuffs.size = effectiveDebuffSize
                            frame.Debuffs:ClearAllPoints()
                            frame.Debuffs:SetPoint(dia, simpleAnchorParent, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + liveDbCbOff + (settings.debuffOffsetY or 0))
                            frame.Debuffs.initialAnchor = dia
                            frame.Debuffs.growthX = dgx
                            frame.Debuffs.growthY = dgy
                            frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10)
                            if frame.Debuffs.ForceUpdate then
                                frame.Debuffs:ForceUpdate()
                            end
                        end
                    end
                    -- Use simple debuff cooldown text settings when simple display
                    -- is active, regular debuff settings otherwise.
                    if settings.simpleDebuffs ~= false then
                        ApplyAuraCooldownText(frame.Debuffs, settings.simpleDebuffShowCooldownText, settings.simpleDebuffCooldownTextSize or 14)
                    else
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10)
                    end
                end

                -- Buffs (boss)
                if frame.Buffs then
                    local showBuffs = settings.showBuffs ~= false
                    if showBuffs then
                        if not frame:IsElementEnabled("Buffs") then
                            frame:EnableElement("Buffs")
                        end
                        frame.Buffs:Show()
                        frame.Buffs.num = settings.maxBuffs or 4
                        local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                            settings.buffAnchor, settings.buffGrowth
                        )
                        local bossBfCbOff = 0
                        if settings.showCastbar ~= false then
                            local bAnc = settings.buffAnchor or "topleft"
                            if bAnc == "bottomleft" or bAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                bossBfCbOff = -cbH
                            end
                        end
                        local buffKey = string.format("%s%s%d%d%d%d%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, bgx or 0, bgy or 0, settings.maxBuffs or 4, bossBfCbOff, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0)
                        if frame.Buffs._lastBuffKey ~= buffKey then
                            frame.Buffs._lastBuffKey = buffKey
                            frame.Buffs.size = settings.buffSize or 22
                            frame.Buffs:ClearAllPoints()
                            frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + bossBfCbOff + (settings.buffOffsetY or 0))
                            frame.Buffs.initialAnchor = bia
                            frame.Buffs.growthX = bgx
                            frame.Buffs.growthY = bgy
                            frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4)
                            if frame.Buffs.ForceUpdate then
                                frame.Buffs:ForceUpdate()
                            end
                        end
                    else
                        if frame:IsElementEnabled("Buffs") then
                            frame:DisableElement("Buffs")
                        end
                        frame.Buffs:Hide()
                        frame.Buffs.num = 0
                    end
                    ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10)
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition)
            end

            -- Determine if this is a mini frame that inherits border/texture/font
            local isMiniFrame = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
            local donorSettings = isMiniFrame and GetMiniDonorSettings() or settings

            -- Apply health bar texture overlay (use donor for mini frames)
            if isMiniFrame then
                -- Override texture settings from donor
                local uKey = UnitToSettingsKey(unit)
                local origTex = settings.healthBarTexture
                settings.healthBarTexture = donorSettings.healthBarTexture
                ApplyHealthBarTexture(frame.Health, uKey)
                settings.healthBarTexture = origTex
                ApplyHealthBarAlpha(frame.Health, uKey)
            else
                ApplyHealthBarTexture(frame.Health, UnitToSettingsKey(unit))
                ApplyHealthBarAlpha(frame.Health, UnitToSettingsKey(unit))
            end
            ApplyDarkTheme(frame.Health)
            frame.Health:SetReverseFill(settings.healthReverseFill and true or false)
            UpdateAbsorbBarReverseFill(frame, settings.healthReverseFill and true or false)
            if frame.Health.ForceUpdate then
                frame.Health:ForceUpdate()
            end

            -- Apply power bar opacity
            if frame.Power then
                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))

                -- Re-apply power bar fill color based on powerPercentPowerColor toggle
                local usePowerColor = settings.powerPercentPowerColor ~= false
                if usePowerColor then
                    frame.Power.colorPower = true
                    frame.Power.PostUpdateColor = nil
                else
                    local customFill = settings.customPowerFillColor
                    frame.Power.colorPower = false
                    if customFill then
                        frame.Power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
                        frame.Power.PostUpdateColor = function(self)
                            local s2 = GetSettingsForUnit(unit)
                            local cf = s2 and s2.customPowerFillColor
                            if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) end
                        end
                    else
                        frame.Power:SetStatusBarColor(0, 0, 1)
                        frame.Power.PostUpdateColor = function(self)
                            self:SetStatusBarColor(0, 0, 1)
                        end
                    end
                end
                local customBg = settings.customPowerBgColor
                if customBg and frame.Power.bg then
                    frame.Power.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1)
                elseif frame.Power.bg then
                    frame.Power.bg:SetColorTexture(17/255, 17/255, 17/255, 1)
                end
                frame.Power:SetReverseFill(settings.powerReverseFill and true or false)
                if frame.Power.ForceUpdate then frame.Power:ForceUpdate() end
            end

            -- Apply castbar reverse fill
            if frame.Castbar then
                frame.Castbar:SetReverseFill(settings.castReverseFill and true or false)
            end

            if frame.unifiedBorder then
                frame.unifiedBorder:ClearAllPoints()
                local bs = donorSettings.borderSize or 1
                local bc = donorSettings.borderColor or { r = 0, g = 0, b = 0 }
                local btex = donorSettings.borderTexture or "solid"
                PP.Point(frame.unifiedBorder, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                PP.Point(frame.unifiedBorder, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                EllesmereUI.ApplyBorderStyle(frame.unifiedBorder, bs, bc.r, bc.g, bc.b, donorSettings.borderAlpha or 1, btex, donorSettings.borderTextureOffset, donorSettings.borderTextureOffsetY, donorSettings.borderTextureShiftX, donorSettings.borderTextureShiftY, "unitframes", bs)
            end

            -- Helper: set font on a FontString, using donor font for mini frames
            local function SetMiniFont(fs, sz)
                if not fs or not fs.SetFont then return end
                if isMiniFrame then
                    local f = (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("unitFrames")) or ""
                    fs:SetFont(donorFontPath, sz or 12, f)
                    if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
                    else fs:SetShadowOffset(0, 0) end
                else
                    SetFSFont(fs, sz)
                end
            end

            if frame.NameText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.leftTextSize or s.textSize or 12
                SetMiniFont(frame.NameText, rts)
                frame.NameText:SetWordWrap(false)
            end
            if frame.HealthValue then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local rts = s.rightTextSize or s.textSize or 12
                SetMiniFont(frame.HealthValue, rts)
                frame.HealthValue:SetWordWrap(false)
            end
            if frame.CenterText then
                local s = isMiniFrame and donorSettings or GetSettingsForUnit(unit)
                local cts = s.centerTextSize or s.textSize or 12
                SetMiniFont(frame.CenterText, cts)
                frame.CenterText:SetWordWrap(false)
            end

            -- Apply text tags and positions for mini frames
            if isMiniFrame and frame._applyTextTags then
                frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "none", settings.centerTextContent or "none")
            end
            if isMiniFrame and frame._applyTextPositions then
                frame._applyTextPositions(settings)
            end

            if frame.Castbar then
                local s = isMiniFrame and donorSettings or settings
                if frame.Castbar.Text then
                    local snSz = s.castSpellNameSize or 11
                    SetMiniFont(frame.Castbar.Text, snSz)
                end
                if frame.Castbar.Time then
                    local dtSz = s.castDurationSize or 10
                    SetMiniFont(frame.Castbar.Time, dtSz)
                end
            end
            end -- else (enabled frame processing)
        end
    end

    -- Refresh combat indicator on player frame after settings change
    if frames.player and frames.player._applyCombatTexture then
        frames.player._applyCombatTexture()
        if (db.profile.player.combatIndicatorStyle or "standard") ~= "none" and UnitAffectingCombat("player") then
            frames.player._combatIndicator:Show()
        else
            frames.player._combatIndicator:Hide()
        end
    end

    -- Refresh leader indicator on player frame after settings change
    if frames.player and frames.player._applyLeaderIndicator then
        frames.player._applyLeaderIndicator()
    end
    if frames.target and frames.target._applyLeaderIndicator then
        frames.target._applyLeaderIndicator()
    end

    ---------------------------------------------------------------------------
    --  Live-update raid target marker icon (size / alignment / X / Y / enabled)
    --  for player, target, focus, and boss frames.  Uses oUF's EnableElement /
    --  DisableElement so the RAID_TARGET_UPDATE event is properly toggled.
    ---------------------------------------------------------------------------
    local RAID_MARKER_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    for _, rmUnit in ipairs(RAID_MARKER_UNITS) do
        local rmFrame = frames[rmUnit]
        local icon = rmFrame and rmFrame._raidMarkerIcon
        if rmFrame and icon then
            local rmS = GetSettingsForUnit(rmUnit)
            local rmSize   = (rmS and rmS.raidMarkerSize)  or 28
            local rmAlign  = (rmS and rmS.raidMarkerAlign) or "right"
            local rmX      = (rmS and rmS.raidMarkerX)     or 0
            local rmY      = (rmS and rmS.raidMarkerY)     or 0
            local rmEnabled = rmS and rmS.raidMarkerEnabled
            local isBoss = rmUnit:match("^boss%d$")
            icon:SetSize(rmSize, rmSize)
            icon:ClearAllPoints()
            if isBoss then
                if rmAlign == "left" then
                    icon:SetPoint("RIGHT", rmFrame, "LEFT", rmX, rmY)
                elseif rmAlign == "center" then
                    icon:SetPoint("CENTER", rmFrame, "CENTER", rmX, rmY)
                else
                    icon:SetPoint("LEFT", rmFrame, "RIGHT", rmX, rmY)
                end
            else
                local rmAnchor = (rmAlign == "left") and "TOPLEFT"
                    or (rmAlign == "center") and "TOP"
                    or "TOPRIGHT"
                icon:SetPoint("CENTER", rmFrame, rmAnchor, rmX, rmY)
            end
            if rmEnabled then
                rmFrame.RaidTargetIndicator = icon
                rmFrame:EnableElement("RaidTargetIndicator")
                if icon.ForceUpdate then icon:ForceUpdate() end
            else
                rmFrame:DisableElement("RaidTargetIndicator")
                rmFrame.RaidTargetIndicator = nil
                icon:Hide()
            end
        end
    end
end

-- Manage Blizzard's player cast bar ownership based on whether UnitFrames is
-- rendering its own player cast bar. oUF already handles the event plumbing
-- for its own castbar element; this helper only coordinates suppression with
-- other EUI modules and releases control cleanly for external addons.
local function ApplyBlizzCastbarState()
    if EllesmereUI and EllesmereUI.SetPlayerCastBarSuppressed and db and db.profile and db.profile.player then
        EllesmereUI.SetPlayerCastBarSuppressed("UnitFrames", db.profile.player.showPlayerCastbar)
    end
end

local function UnitFrame_OnEnter(self)
    local unit = self.unit
    if not unit then return end
    local unitKey = unit:match("^boss%d$") and "boss" or unit
    local s = db and db.profile and db.profile[unitKey]
    if s and (s.barVisibility or "always") == "mouseover" then
        (self._visWrap or self):SetAlpha(1)
    end
    if unit and GameTooltip and GameTooltip_SetDefaultAnchor then
        local showTooltip = not s or s.showUnitTooltip ~= false
        if showTooltip then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end
end

local function UnitFrame_OnLeave(self)
    local unit = self.unit
    if not unit then return end
    local unitKey = unit:match("^boss%d$") and "boss" or unit
    local s = db and db.profile and db.profile[unitKey]
    if s and (s.barVisibility or "always") == "mouseover" then
        -- Mirror UpdateFrameVisibility's mouseover logic: when a positive
        -- "Hide if" override is configured and currently not triggering,
        -- keep the frame shown on mouse leave instead of re-hiding it.
        local hiddenByOpts = EllesmereUI and EllesmereUI.CheckVisibilityOptions
                             and EllesmereUI.CheckVisibilityOptions(s)
        local hasAnyHideOpt = s.visHideNoTarget
                           or s.visHideNoEnemy
                           or s.visHideMounted
                           or s.visHideHousing
                           or s.visOnlyInstances
        local keepShown = (not hiddenByOpts) and hasAnyHideOpt
        ;(self._visWrap or self):SetAlpha(keepShown and 1 or 0)
    end
    if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

function InitializeFrames()
    -- Sync EUI global power colors into oUF at init
    if EllesmereUI and EllesmereUI.ApplyColorsToOUF then
        EllesmereUI.ApplyColorsToOUF()
    end

    if oUF.Tags and oUF.Tags.SetEventUpdateTimer then
        oUF.Tags:SetEventUpdateTimer(0.25)
    end

    local classPowerStyle = db.profile.player.classPowerStyle or "none"
    -- Per-class Blizzard class power bar frame names
    local BLIZZARD_CP_FRAMES = {
        DEATHKNIGHT = "RuneFrame",
        DRUID       = "DruidComboPointBarFrame",
        EVOKER      = "EssencePlayerFrame",
        MAGE        = "MageArcaneChargesFrame",
        MONK        = "MonkHarmonyBarFrame",
        PALADIN     = "PaladinPowerBarFrame",
        ROGUE       = "RogueComboPointBarFrame",
        WARLOCK     = "WarlockPowerFrame",
    }
    -- External state for Blizzard class power bars (never write onto
    -- Blizzard frames -- see CLAUDE.md _FFD rule).
    local _blizzCPState = {}  -- { origParent, hooked }
    local savedClassPowerBar = nil
    if classPowerStyle == "blizzard" then
        local _, classFile = UnitClass("player")
        local frameName = BLIZZARD_CP_FRAMES[classFile]
        local cpFrame = frameName and _G[frameName]
        if cpFrame then
            savedClassPowerBar = cpFrame
            _blizzCPState.origParent = cpFrame:GetParent()
            cpFrame:SetParent(UIParent)
        end
    end

    local enabled = db.profile.enabledFrames

    RegisterStylesOnce()

    local function SetupUnitMenu(frame, unit)
        frame:RegisterForClicks("AnyUp")
        frame:SetAttribute("*type2", "togglemenu")
        frame:HookScript("OnEnter", UnitFrame_OnEnter)
        frame:HookScript("OnLeave", UnitFrame_OnLeave)
    end

    -- Always spawn all frames; hide disabled ones for zero performance impact
    oUF:SetActiveStyle("EllesmerePlayer")
    frames.player = oUF:Spawn("player", "EllesmereUIUnitFrames_Player")

    -- Visibility wrapper for the player frame only. Parent the player frame
    -- to a non-secure wrapper and drive visibility via the wrapper's alpha
    -- instead of the frame's own alpha. Alpha inherits multiplicatively down
    -- the parent chain, so the wrapper's alpha wins regardless of anything
    -- that touches the inner frame's alpha directly (oUF elements, combat
    -- transitions, etc.). Target/focus/pet frames don't need this because
    -- RegisterUnitWatch already handles their visibility via unit existence.
    --
    -- The wrapper is inserted between the player frame and whatever parent
    -- oUF originally gave it (PetBattleFrameHider), so the pet-battle state
    -- driver chain continues to work.
    local origParent = frames.player:GetParent() or UIParent
    local playerVisWrap = CreateFrame("Frame", nil, origParent)
    playerVisWrap:SetAllPoints(origParent)
    playerVisWrap:SetFrameStrata(frames.player:GetFrameStrata())
    frames.player:SetParent(playerVisWrap)
    frames.player._visWrap = playerVisWrap

    ApplyFramePosition(frames.player, "player")
    SetupUnitMenu(frames.player, "player")

    if enabled.player == false then
        frames.player:Hide()
        frames.player:SetAttribute("unit", nil)
    end

    -- Combat indicator overlay on player frame
    do
        local pf = frames.player
        local ps = db.profile.player
        local COMBAT_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\combat\\"

        -- Create holder + texture ONCE, reuse on subsequent calls
        if not pf._combatHolder then
            pf._combatHolder = CreateFrame("Frame", nil, pf)
            pf._combatHolder:SetAllPoints(pf)
            pf._combatIndicator = pf._combatHolder:CreateTexture(nil, "OVERLAY", nil, 7)
            pf._combatIndicator:Hide()
        end
        pf._combatHolder:SetFrameLevel(pf:GetFrameLevel() + 20)
        local combat = pf._combatIndicator

        -- Helper: resolve which texture file + coords to use
        local function ApplyCombatTexture()
            local style = ps.combatIndicatorStyle or "standard"
            if style == "none" then combat:Hide(); return end

            local colorMode = ps.combatIndicatorColor or "custom"
            local sz = ps.combatIndicatorSize or 22
            local ox = ps.combatIndicatorX or 0
            local oy = ps.combatIndicatorY or 0
            local pos = ps.combatIndicatorPosition or "healthbar"

            combat:SetSize(sz, sz)
            combat:ClearAllPoints()

            -- Determine anchor element
            local anchor = pf
            if pos == "healthbar" and pf.Health then
                anchor = pf.Health
            elseif pos == "textbar" and pf._btb then
                anchor = pf._btb
            elseif pos == "portrait" and pf.Portrait then
                anchor = pf.Portrait
            end
            combat:SetPoint("CENTER", anchor, "CENTER", ox, oy)

            -- Determine texture file (always use -custom / white base)
            local _, classToken = UnitClass("player")
            if style == "class" then
                combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-class-custom.png")
                local coords = CLASS_FULL_COORDS[classToken]
                if coords then
                    combat:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                else
                    combat:SetTexCoord(0, 1, 0, 1)
                end
            else
                combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-custom.png")
                combat:SetTexCoord(0, 1, 0, 1)
            end

            -- Apply color tint
            if colorMode == "classcolor" then
                local cc = (EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
            elseif colorMode == "custom" then
                local cc = ps.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
            else
                combat:SetVertexColor(1, 1, 1, 1)
            end
        end
        pf._applyCombatTexture = ApplyCombatTexture

        -- Event frame for combat state changes (reuse existing)
        if not pf._combatEventFrame then
            pf._combatEventFrame = CreateFrame("Frame", nil, pf)
            pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        local combatFrame = pf._combatEventFrame
        combatFrame:SetScript("OnEvent", function(_, event)
            local style = ps.combatIndicatorStyle or "standard"
            if style ~= "none" then
                if event == "PLAYER_REGEN_DISABLED" then
                    ApplyCombatTexture()
                    combat:Show()
                else
                    combat:Hide()
                end
            else
                combat:Hide()
            end
        end)

        -- Set correct initial state
        local style = ps.combatIndicatorStyle or "standard"
        if style ~= "none" and UnitAffectingCombat("player") then
            ApplyCombatTexture()
            combat:Show()
        end
    end

    -- Rested indicator ("ZZZ") on player health bar top-left
    do
        local pf = frames.player
        if pf and pf.Health then
            if not pf._restHolder then
                pf._restHolder = CreateFrame("Frame", nil, pf.Health)
                local restText = pf._restHolder:CreateFontString(nil, "OVERLAY")
                SetFSFont(restText, 9)
                restText:SetTextColor(1, 1, 1)
                restText:SetText("ZZZ")
                restText:Hide()
                pf._restIndicator = restText

                pf._restEventFrame = CreateFrame("Frame", nil, pf)
                pf._restEventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
                pf._restEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
                pf._restEventFrame:SetScript("OnEvent", function()
                    local enabled = EllesmereUIDB and EllesmereUIDB.showRestedIndicator == true
                    if enabled and IsResting() then
                        pf._restIndicator:Show()
                    else
                        pf._restIndicator:Hide()
                    end
                end)
            end
            pf._restHolder:SetAllPoints(pf.Health)
            pf._restHolder:SetFrameLevel(pf.Health:GetFrameLevel() + 5)
            pf._restIndicator:ClearAllPoints()
            local rxOff = (EllesmereUIDB and EllesmereUIDB.restedIndicatorXOffset) or 0
            local ryOff = (EllesmereUIDB and EllesmereUIDB.restedIndicatorYOffset) or 0
            pf._restIndicator:SetPoint("TOPLEFT", pf.Health, "TOPLEFT", 3 + rxOff, -2 + ryOff)

            local restEnabled = EllesmereUIDB and EllesmereUIDB.showRestedIndicator == true
            if restEnabled and IsResting() then pf._restIndicator:Show() else pf._restIndicator:Hide() end
        end
    end


    -- Castbar state is managed by ApplyBlizzCastbarState (called here and also
    -- from ReloadFrames so toggling the setting works without a /reload).
    ApplyBlizzCastbarState()

    -- Re-apply after zone changes and after Edit Mode closes, both of which
    -- can cause Blizzard to reparent or re-hide the cast bar.
    if not frames._cbSuppressFrame then
        frames._cbSuppressFrame = CreateFrame("Frame")
        frames._cbSuppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frames._cbSuppressFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        frames._cbSuppressFrame:SetScript("OnEvent", function()
            ApplyBlizzCastbarState()
        end)
        -- Edit Mode exit reparents the cast bar back into its layout frame
        -- (which gets hidden), so re-apply our state when the panel closes.
        if EditModeManagerFrame and not EllesmereUI._GetFFD(EditModeManagerFrame).castbarHooked then
            EllesmereUI._GetFFD(EditModeManagerFrame).castbarHooked = true
            hooksecurefunc(EditModeManagerFrame, "Hide", function()
                C_Timer.After(0, ApplyBlizzCastbarState)
            end)
        end
    end

    -- Resize frame and portrait to account for class power pips above health bar
    local function ResizeFrameForClassPower(cpAboveH)
        local frame = frames.player
        if not frame then return end
        local settings = GetSettingsForUnit("player")
        local ppPos = settings.powerPosition or "below"
        local ppIsAtt = (ppPos == "below" or ppPos == "above")
        local ppExtra = ppIsAtt and settings.powerHeight or 0
        local baseH = settings.healthHeight + ppExtra
        local btbPos2 = settings.btbPosition or "bottom"
        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
        local btbExtra = (settings.bottomTextBar and btbIsAtt) and (settings.bottomTextBarHeight or 16) or 0
        local totalH = baseH + cpAboveH + btbExtra

        local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
        local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
        local isAttached = pStyle == "attached"
        local pSizeAdj = settings.portraitSize or 0
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        local adjPortraitH = baseH + cpAboveH + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end

        local pSide = settings.portraitSide or "left"
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end

        local totalWidth
        local portraitW = 0
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
            portraitW = adjPortraitH
        else
            totalWidth = settings.frameWidth
        end

        if not InCombatLockdown() then
            PP.Size(frame, totalWidth, totalH)
        else
            frame._pendingSize = { totalWidth, totalH }
            if not frame._pendingSizeListener then
                frame._pendingSizeListener = CreateFrame("Frame")
                frame._pendingSizeListener:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    if frame._pendingSize and not InCombatLockdown() then
                        PP.Size(frame, frame._pendingSize[1], frame._pendingSize[2])
                    end
                    frame._pendingSize = nil
                end)
            end
            frame._pendingSizeListener:RegisterEvent("PLAYER_REGEN_ENABLED")
        end

        -- Update health bar xOffset when portrait width changes
        if frame.Health then
            local newXOff = (showPortrait and isAttached and effectiveSide == "left") and portraitW or 0
            local newRightInset = (showPortrait and isAttached and effectiveSide == "right") and portraitW or 0
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRightInset
        end

        if frame.Portrait and frame.Portrait.backdrop and showPortrait then
            PP.Size(frame.Portrait.backdrop, adjPortraitH, adjPortraitH)
            frame.Portrait.backdrop:ClearAllPoints()
            if isAttached then
                if effectiveSide == "left" then
                    PP.Point(frame.Portrait.backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                else
                    PP.Point(frame.Portrait.backdrop, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                end
            end
            if frame.Portrait.backdrop._2d then
                UnsnapTex(frame.Portrait.backdrop._2d)
            end
            if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                frame.Portrait:ForceUpdate()
            end
        end
    end

    local function PositionClassPowerBar(bar)
        if not bar or not frames.player then return end
        bar:ClearAllPoints()
        local style = db.profile.player.classPowerStyle or "none"
        local position = db.profile.player.classPowerPosition or "top"
        local offsetX = db.profile.player.classPowerBarX or 0
        local offsetY = db.profile.player.classPowerBarY or 0

        -- Stop castbar watcher by default; only re-enabled in the "bottom" branch
        if bar._castbarWatcher then
            bar._castbarWatcher:SetScript("OnUpdate", nil)
            bar._castbarWatcher:Hide()
        end

        if style == "modern" and position == "above" then
            -- Above health bar, inside the frame ? pips stretch to fill health bar width
            -- Bottom of pips flush with top of health bar, top of pips flush with top of border
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            local anchorFrame = frames.player.Health
            local pipH = bar._pipH or 3
            -- Resize frame/portrait BEFORE anchoring health bar so _xOffset is correct
            ResizeFrameForClassPower(pipH)
            local btbOff = 0
            local btbPos2 = db.profile.player.btbPosition or "bottom"
            if btbPos2 == "top" and db.profile.player.bottomTextBar then
                btbOff = db.profile.player.bottomTextBarHeight or 16
            end
            local cpPush = pipH + btbOff
            anchorFrame:ClearAllPoints()
            anchorFrame:SetPoint("TOPLEFT", frames.player, "TOPLEFT", anchorFrame._xOffset or 0, PP.Scale(-cpPush))
            anchorFrame:SetPoint("RIGHT", frames.player, "RIGHT", -(anchorFrame._rightInset or 0), 0)
            PP.Point(bar, "BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
            PP.Point(bar, "BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
            local fw = db.profile.player.frameWidth or 181
            if bar._repositionForWidth then
                bar._repositionForWidth(fw)
            end
            -- Show 1px bottom border matching frame border color
            if bar._bottomBdrFrame then
                local bdrC = db.profile.player.borderColor or { r = 0, g = 0, b = 0 }
                bar._bottomBdr:SetColorTexture(bdrC.r, bdrC.g, bdrC.b, 1)
                bar._bottomBdrFrame:Show()
            end
        elseif style == "modern" and position == "top" then
            -- "top" floats above the frame (like "bottom" floats below) ? does NOT become part of the frame
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            ResizeFrameForClassPower(0)
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- Center on health bar (ignores portrait)
            PP.Point(bar, "BOTTOM", frames.player.Health, "TOP", offsetX, offsetY)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
        elseif not db.profile.player.lockClassPowerToFrame then
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            _cpExpectedParent = UIParent
            bar:SetParent(UIParent)
            local pos = db.profile.positions.classPower
            if pos then
                PP.Point(bar, pos.point, UIParent, pos.point, pos.x, pos.y)
            else
                PP.Point(bar, "CENTER", UIParent, "CENTER", 0, -220)
            end
            ResizeFrameForClassPower(0)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
        else
            -- Reset health bar to normal position
            if frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            -- "bottom" position -- flush with bottom of frame; shifts below castbar when visible (unless user set Y offset)
            _cpExpectedParent = frames.player
            bar:SetParent(frames.player)
            if bar._bottomBdrFrame then bar._bottomBdrFrame:Hide() end
            local function AnchorBottom()
                bar:ClearAllPoints()
                local baseY = -1 + offsetY
                if offsetY == 0 then
                    local castbarBg = frames.player.Castbar and frames.player.Castbar:GetParent()
                    local castVisible = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if castVisible then
                        baseY = -1 - castbarBg:GetHeight()
                    end
                end
                PP.Point(bar, "TOP", frames.player, "BOTTOM", offsetX, baseY)
            end
            AnchorBottom()
            -- Only run the castbar watcher if the player castbar is enabled
            if db.profile.player.showPlayerCastbar then
                if not bar._castbarWatcher then
                    bar._castbarWatcher = CreateFrame("Frame", nil, bar)
                end
                local cbElapsed = 0
                local playerFrame = frames.player
                bar._castbarWatcher:SetScript("OnUpdate", function(_, dt)
                    cbElapsed = cbElapsed + dt
                    if cbElapsed < 0.1 then return end
                    cbElapsed = 0
                    local cb = playerFrame and playerFrame.Castbar
                    local castbarBg = cb and cb:GetParent()
                    local nowVis = castbarBg and castbarBg:IsShown() and db.profile.player.showPlayerCastbar
                    if nowVis ~= bar._lastCastVis then
                        bar._lastCastVis = nowVis
                        AnchorBottom()
                    end
                end)
                bar._castbarWatcher:Show()
            end
            ResizeFrameForClassPower(0)
        end
        bar:SetFrameStrata(frames.player:GetFrameStrata())
        bar:SetFrameLevel(frames.player:GetFrameLevel() + 5)
        bar:Show()
    end

    -- Hook Blizzard class power bar so form changes / spec changes can't
    -- steal it back. Hooks SetParent to re-assert our parent, and Show/Hide
    -- to keep it visible. Only active while classPowerStyle == "blizzard".
    local _blizzCPHooked = false
    local _blizzCPActive = false  -- true while we own the bar

    -- The expected parent for the Blizzard class power bar after positioning.
    -- Set by PositionClassPowerBar so the SetParent hook knows what's correct.
    local _cpExpectedParent = nil

    local function HookBlizzardClassPower(cpFrame)
        if _blizzCPHooked then return end
        _blizzCPHooked = true
        local _cpSetParentGuard = false
        -- Re-assert position when Blizzard reparents (form/spec changes).
        hooksecurefunc(cpFrame, "SetParent", function(self, newParent)
            if not _blizzCPActive or _cpSetParentGuard then return end
            local wanted = _cpExpectedParent or frames.player or UIParent
            if newParent ~= wanted then
                _cpSetParentGuard = true
                PositionClassPowerBar(self)
                -- Blizzard may have re-stolen during PositionClassPowerBar.
                -- The anchor is already correct, so just fix the parent directly.
                local cur = self:GetParent()
                wanted = _cpExpectedParent or frames.player or UIParent
                if cur ~= wanted then
                    self:SetParent(wanted)
                end
                _cpSetParentGuard = false
            end
        end)
        hooksecurefunc(cpFrame, "Hide", function(self)
            if not _blizzCPActive then return end
            if not InCombatLockdown() then self:Show() end
        end)
    end

    if classPowerStyle ~= "none" and frames.player then
        if classPowerStyle == "blizzard" then
            if savedClassPowerBar then
                _blizzCPActive = true
                HookBlizzardClassPower(savedClassPowerBar)
                PositionClassPowerBar(savedClassPowerBar)
                frames._classPowerBar = savedClassPowerBar
            end
        else
            -- Modern custom style
            DestroyCustomClassPower()
            local custom = CreateCustomClassPower(frames.player, classPowerStyle)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Live toggle for class power bar (no reload needed)
    -- Called with the style string: "none", "modern", or "blizzard"
    frames._toggleClassPower = function(style)
        style = style or db.profile.player.classPowerStyle or "none"
        -- Keep showClassPowerBar in sync with style
        db.profile.player.showClassPowerBar = (style ~= "none")
        db.profile.player.classPowerStyle = style

        -- Clean up existing
        _blizzCPActive = false
        if frames._customClassPower then
            DestroyCustomClassPower()
            frames._classPowerBar = nil
        elseif frames._classPowerBar then
            frames._classPowerBar:Hide()
            frames._classPowerBar:ClearAllPoints()
            local origParent = _blizzCPState.origParent or PlayerFrame or UIParent
            frames._classPowerBar:SetParent(origParent)
            frames._classPowerBar = nil
        end

        if style == "none" then
            -- Reset health bar to normal position
            if frames.player and frames.player.Health then
                local btbOff = 0
                local btbPos2 = db.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and db.profile.player.bottomTextBar then
                    btbOff = db.profile.player.bottomTextBarHeight or 16
                end
                frames.player.Health:ClearAllPoints()
                frames.player.Health:SetPoint("TOPLEFT", frames.player, "TOPLEFT", frames.player.Health._xOffset or 0, PP.Scale(-btbOff))
                frames.player.Health:SetPoint("RIGHT", frames.player, "RIGHT", -(frames.player.Health._rightInset or 0), 0)
            end
            ResizeFrameForClassPower(0)
            return
        end

        if style == "blizzard" then
            local _, classFile = UnitClass("player")
            local frameName = BLIZZARD_CP_FRAMES[classFile]
            local cpFrame = frameName and _G[frameName]
            if cpFrame then
                _blizzCPState.origParent = cpFrame:GetParent()
                _blizzCPActive = true
                HookBlizzardClassPower(cpFrame)
                cpFrame:SetParent(UIParent)
                frames._classPowerBar = cpFrame
            end
            if frames._classPowerBar and frames.player then
                PositionClassPowerBar(frames._classPowerBar)
            end
        else
            -- Modern
            local custom = CreateCustomClassPower(frames.player, style)
            if custom then
                frames._customClassPower = custom
                frames._classPowerBar = custom
                PositionClassPowerBar(custom)
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Persistent spec-change watcher for class power rebuild.
    -- Lives outside the class power container so it survives DestroyCustomClassPower.
    local cpSpecWatcher = CreateFrame("Frame")
    local cpSpecInitDone = false
    cpSpecWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    cpSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    cpSpecWatcher:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            cpSpecInitDone = true
            cpSpecWatcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
            return
        end
        if unit ~= "player" then return end
        if not cpSpecInitDone then return end
        DestroyCustomClassPower()
        frames._classPowerBar = nil
        C_Timer.After(0.1, function()
            if ns.ReloadFrames then ns.ReloadFrames() end
            if frames._toggleClassPower then
                frames._toggleClassPower()
            end
        end)
    end)

    oUF:SetActiveStyle("EllesmereTarget")
    frames.target = oUF:Spawn("target", "EllesmereUIUnitFrames_Target")
    ApplyFramePosition(frames.target, "target")
    SetupUnitMenu(frames.target, "target")
    if enabled.target == false then
        frames.target:Hide()
        frames.target:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereFocus")
    frames.focus = oUF:Spawn("focus", "EllesmereUIUnitFrames_Focus")
    ApplyFramePosition(frames.focus, "focus")
    SetupUnitMenu(frames.focus, "focus")
    if enabled.focus == false then
        frames.focus:Hide()
        frames.focus:SetAttribute("unit", nil)
    end

    -- Leader indicator (crown when unit is the group/raid leader). oUF doesn't
    -- attach LeaderIndicator dynamically after Spawn(), so we drive the texture
    -- ourselves: own events, own UnitIsGroupLeader check, own show/hide.
    -- Must run after target frame is spawned (right above) so the texture can
    -- be parented to it.
    do
        local LEADER_ATLAS = "plunderstorm-glues-icon-leader"
        local _leaderUnits = {}

        local function _leaderRefresh(uf)
            local s = uf and uf._leaderSettings
            if not (uf and uf._leaderIndicator and s) then return end
            local tex = uf._leaderIndicator
            if s.leaderIndicatorEnabled == false then tex:Hide(); return end
            local unit = uf.unit
            if unit and UnitExists(unit) and UnitIsGroupLeader(unit) then
                tex:SetAtlas(LEADER_ATLAS)
                tex:Show()
            else
                tex:Hide()
            end
        end

        local function _setupLeaderIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._leaderIndicator then
                local leaderTex = uf:CreateTexture(nil, "OVERLAY", nil, 7)
                leaderTex:Hide()
                uf._leaderIndicator = leaderTex
                _leaderUnits[#_leaderUnits + 1] = uf
            end
            uf._leaderSettings = settings

            local function ApplyLeaderIndicator()
                local sz  = settings.leaderIndicatorSize or 16
                local pos = settings.leaderIndicatorPosition or "topleft"
                local ox  = settings.leaderIndicatorX or 0
                local oy  = settings.leaderIndicatorY or 0
                local leader = uf._leaderIndicator
                leader:SetSize(sz, sz)
                leader:ClearAllPoints()
                if pos == "portrait" and uf.Portrait and uf.Portrait.backdrop then
                    leader:SetPoint("CENTER", uf.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor =
                        (pos == "topright"    and "TOPRIGHT")    or
                        (pos == "bottomleft"  and "BOTTOMLEFT")  or
                        (pos == "bottomright" and "BOTTOMRIGHT") or
                        "TOPLEFT"
                    leader:SetPoint(anchor, uf.Health or uf, anchor, ox, oy)
                end
                _leaderRefresh(uf)
            end
            uf._applyLeaderIndicator = ApplyLeaderIndicator
            ApplyLeaderIndicator()
        end

        _setupLeaderIndicator(frames.player, db.profile.player)
        _setupLeaderIndicator(frames.target, db.profile.target)

        if #_leaderUnits > 0 then
            local leaderEvents = CreateFrame("Frame")
            leaderEvents:RegisterEvent("PARTY_LEADER_CHANGED")
            leaderEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
            leaderEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
            leaderEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
            leaderEvents:SetScript("OnEvent", function()
                for i = 1, #_leaderUnits do _leaderRefresh(_leaderUnits[i]) end
            end)
        end
    end

    oUF:SetActiveStyle("EllesmerePet")
    frames.pet = oUF:Spawn("pet", "EllesmereUIUnitFrames_Pet")
    ApplyFramePosition(frames.pet, "pet")
    SetupUnitMenu(frames.pet, "pet")
    if enabled.pet == false then
        frames.pet:Hide()
        frames.pet:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereTargetTarget")
    frames.targettarget = oUF:Spawn("targettarget", "EllesmereUIUnitFrames_TargetTarget")
    ApplyFramePosition(frames.targettarget, "targettarget")
    SetupUnitMenu(frames.targettarget, "targettarget")
    if enabled.targettarget == false then
        frames.targettarget:Hide()
        frames.targettarget:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereFocusTarget")
    frames.focustarget = oUF:Spawn("focustarget", "EllesmereUIUnitFrames_FocusTarget")
    ApplyFramePosition(frames.focustarget, "focustarget")
    SetupUnitMenu(frames.focustarget, "focustarget")
    if enabled.focustarget == false then
        frames.focustarget:Hide()
        frames.focustarget:SetAttribute("unit", nil)
    end

    oUF:SetActiveStyle("EllesmereBoss")
    local bossPos = db.profile.positions.boss

    local bossSettings = db.profile.boss or {}
    local barHeight = (bossSettings.healthHeight or 34) + (bossSettings.powerHeight or 6) + (bossSettings.castbarHeight or 14)
    local gap = 10
    local spacing = db.profile.bossSpacing or (barHeight + gap)
    for i = 1, 5 do
        local bossUnit = "boss" .. i
        local bossFrame = oUF:Spawn(bossUnit, "EllesmereUIUnitFrames_Boss" .. i)
        frames[bossUnit] = bossFrame

        -- boss1 anchors to UIParent; boss2..5 chain off boss1 with spacing.
        -- This keeps the whole stack moving together when unlock mode drags
        -- boss1 -- the only draggable boss frame.
        if i == 1 then
            if bossPos then
                bossFrame:ClearAllPoints()
                bossFrame:SetPoint(bossPos.point, UIParent, bossPos.relPoint or bossPos.point, bossPos.x, bossPos.y)
            end
        else
            local prev = frames["boss" .. (i - 1)]
            if prev then
                bossFrame:ClearAllPoints()
                bossFrame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
            end
        end

        SetupUnitMenu(bossFrame, bossUnit)

        if enabled.boss == false then
            bossFrame:Hide()
            bossFrame:SetAttribute("unit", nil)
        end
    end

    for i = 1, 5 do
        local blizzBoss = _G["Boss" .. i .. "TargetFrame"]
        if blizzBoss then
            blizzBoss:UnregisterAllEvents()
            blizzBoss:Hide()
        end
    end

    -- Disable oUF elements for frames where features are initially off.
    -- Portrait backdrop is already hidden by style functions, but oUF
    -- auto-enables the element at spawn time since frame.Portrait is always set.
    for unit, frame in pairs(frames) do
        if type(frame) ~= "table" or not frame.Portrait then -- skip non-frame entries
        elseif frame.Portrait.backdrop then
            local settings = GetSettingsForUnit(unit)
            if settings.showPortrait == false or (settings.portraitStyle or db.profile.portraitStyle or "attached") == "none" then
                if frame:IsElementEnabled("Portrait") then
                    frame:DisableElement("Portrait")
                end
            elseif settings.portraitMode == "class" and unit == "player" then
                -- Class theme is a static texture -- disable oUF Portrait element (player only)
                if frame:IsElementEnabled("Portrait") then
                    frame:DisableElement("Portrait")
                end
            end
        end
    end

    -- Absorbs: apply style and hide if "none" for player, target, focus.
    -- Leave the oUF HealthPrediction element enabled so events keep flowing
    -- and the calculator stays in sync.
    for _, uKey in ipairs({ "player", "target", "focus" }) do
        local f = frames[uKey]
        if f and f.HealthPrediction and f.HealthPrediction.damageAbsorb then
            local absStyle = db.profile[uKey] and db.profile[uKey].showPlayerAbsorb
            if absStyle and absStyle ~= "none" then
                ApplyAbsorbStyle(f.HealthPrediction.damageAbsorb, absStyle, db.profile[uKey])
                f.HealthPrediction.damageAbsorb:Show()
                if f.HealthPrediction.damageAbsorb._forward then
                    f.HealthPrediction.damageAbsorb._forward:Show()
                end
            else
                f.HealthPrediction.damageAbsorb:Hide()
                if f.HealthPrediction.damageAbsorb._forward then
                    f.HealthPrediction.damageAbsorb._forward:Hide()
                end
            end
            -- Force oUF to re-run the HealthPrediction element so the new
            -- texture is visible immediately without waiting for a health event
            if f.HealthPrediction and f.HealthPrediction.ForceUpdate then
                f.HealthPrediction:ForceUpdate()
            end
        end
    end

    -- Player buffs: disable oUF element if not wanted (frame is always created)
    if frames.player and frames.player.Buffs then
        if not db.profile.player.showBuffs then
            if frames.player:IsElementEnabled("Buffs") then
                frames.player:DisableElement("Buffs")
            end
            frames.player.Buffs:Hide()
        end
    end

    -- Player castbar: disable oUF element if not wanted (always created now)
    if frames.player and frames.player.Castbar then
        if not db.profile.player.showPlayerCastbar then
            if frames.player:IsElementEnabled("Castbar") then
                frames.player:DisableElement("Castbar")
            end
            frames.player.Castbar:Hide()
            local castbarBg = frames.player.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.player.showPlayerCastIcon == false and frames.player.Castbar._iconFrame then
            frames.player.Castbar._iconFrame:Hide()
        end
    end

    -- Target castbar: disable oUF element if not wanted
    if frames.target and frames.target.Castbar then
        if db.profile.target.showCastbar == false then
            if frames.target:IsElementEnabled("Castbar") then
                frames.target:DisableElement("Castbar")
            end
            frames.target.Castbar:Hide()
            local castbarBg = frames.target.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.target.showCastIcon == false and frames.target.Castbar._iconFrame then
            frames.target.Castbar._iconFrame:Hide()
        end
    end

    -- Focus castbar: disable oUF element if not wanted
    if frames.focus and frames.focus.Castbar then
        if db.profile.focus.showCastbar == false then
            if frames.focus:IsElementEnabled("Castbar") then
                frames.focus:DisableElement("Castbar")
            end
            frames.focus.Castbar:Hide()
            local castbarBg = frames.focus.Castbar:GetParent()
            if castbarBg then castbarBg:Hide() end
        elseif db.profile.focus.showCastIcon == false and frames.focus.Castbar._iconFrame then
            frames.focus.Castbar._iconFrame:Hide()
        end
    end

    ---------------------------------------------------------------------------
    --  Group visibility: show/hide player/target/focus based on group state
    ---------------------------------------------------------------------------
    local _ufInCombat = InCombatLockdown()
    local function UpdateFrameVisibility()
        -- Do NOT return early during combat lockdown. Alpha operations
        -- (SetAlpha) are not restricted and must run on combat transitions.
        -- Show/Hide and SetAttribute ARE restricted; those are guarded below.
        local isLocked = InCombatLockdown()
        local enabled2 = db.profile.enabledFrames
        local inRaid = IsInRaid()
        local inParty = not inRaid and IsInGroup()
        local solo = not inRaid and not inParty
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local s = db.profile[unitKey]
            local frame = frames[unitKey]
            if frame and enabled2[unitKey] ~= false and s then
                local hiddenByOpts = EllesmereUI and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(s)
                local vis = s.barVisibility or "always"

                -- Combat-sensitive and mouseover modes use SetAlpha to show/hide
                -- (SetAlpha is not a restricted API). The frame stays technically
                -- shown so it can transition instantly; alpha controls visibility.
                --
                -- For the player frame we drive alpha on a non-secure wrapper
                -- (see _visWrap) so nothing that touches the inner frame's
                -- alpha (oUF updates, secure templates, etc.) can make it
                -- reappear/disappear against our will. Alpha inherits down the
                -- parent chain so wrapper alpha 0 always wins.
                local alphaTarget = frame._visWrap or frame
                if vis == "in_combat" then
                    alphaTarget:SetAlpha((not hiddenByOpts and _ufInCombat) and 1 or 0)
                elseif vis == "out_of_combat" then
                    alphaTarget:SetAlpha((not hiddenByOpts and not _ufInCombat) and 1 or 0)
                elseif vis == "mouseover" then
                    -- Mouseover: hidden by default; hover toggles alpha.
                    -- But when the user has configured any positive "Hide if"
                    -- override (no target, no enemy, mounted, etc.) and that
                    -- override is NOT currently triggering, treat the frame
                    -- as a positive-show so it doesn't require hover to see.
                    -- This fixes "dismount while in combat keeps frame hidden"
                    -- and "hide if no target behaves inverted" reports.
                    local hasAnyHideOpt = s.visHideNoTarget
                                       or s.visHideNoEnemy
                                       or s.visHideMounted
                                       or s.visHideHousing
                                       or s.visOnlyInstances
                    if hiddenByOpts then
                        alphaTarget:SetAlpha(0)
                    elseif hasAnyHideOpt then
                        alphaTarget:SetAlpha(1)
                    else
                        alphaTarget:SetAlpha(0)
                    end
                else
                    -- Non-combat modes: restore full alpha; Show/Hide controls
                    -- visibility in the block below.
                    alphaTarget:SetAlpha(1)
                end

                -- Alpha-only hide for the "visHide*" overrides (mounted,
                -- no target, housing, etc). Force alpha 0 now so the frame
                -- still looks hidden, but leave the secure Show/Hide state
                -- alone below -- otherwise a dismount that lands inside a
                -- combat lockdown would leave the frame permanently hidden
                -- (Show/SetAttribute are restricted in combat, so we can't
                -- re-show it until combat ends).
                if hiddenByOpts then
                    alphaTarget:SetAlpha(0)
                end

                -- 3D PlayerModel frames don't inherit parent alpha, so
                -- explicitly sync the model's alpha with the visibility state.
                local bd3d = frame.Portrait and frame.Portrait.backdrop and frame.Portrait.backdrop._3d
                if bd3d then
                    bd3d:SetAlpha(hiddenByOpts and 0 or 1)
                end

                -- Show/Hide and SetAttribute are restricted during lockdown.
                if not isLocked then
                    local shouldShow
                    if vis == "never" then
                        shouldShow = false
                    elseif vis == "in_combat" or vis == "out_of_combat" or vis == "mouseover" then
                        -- Frame is kept shown; alpha (above) drives visibility.
                        shouldShow = true
                    elseif vis == "in_raid" then
                        shouldShow = inRaid
                    elseif vis == "in_party" then
                        shouldShow = inRaid or inParty
                    elseif vis == "solo" then
                        shouldShow = solo
                    else
                        -- "always" is the default -- always Shown at secure
                        -- level; alpha controls actual visibility.
                        shouldShow = true
                    end

                    if shouldShow then
                        if not frame:IsShown() and UnitExists(unitKey) then
                            frame:SetAttribute("unit", unitKey)
                            -- Re-enable oUF elements that were disabled on hide.
                            -- Castbar is handled separately below to respect the
                            -- user's show/hide setting -- never blindly re-enable it.
                            for _, elem in ipairs({"Health", "Power", "Portrait", "Buffs", "Debuffs", "HealthPrediction"}) do
                                if frame[elem] and not frame:IsElementEnabled(elem) then
                                    frame:EnableElement(elem)
                                end
                            end
                            -- Restore castbar state based on saved setting
                            if frame.Castbar then
                                local wantsCastbar
                                if unitKey == "player" then
                                    wantsCastbar = s.showPlayerCastbar
                                else
                                    wantsCastbar = s.showCastbar ~= false
                                end
                                if wantsCastbar then
                                    if not frame:IsElementEnabled("Castbar") then
                                        frame:EnableElement("Castbar")
                                    end
                                else
                                    if frame:IsElementEnabled("Castbar") then
                                        frame:DisableElement("Castbar")
                                    end
                                    frame.Castbar:Hide()
                                    local castbarBg = frame.Castbar:GetParent()
                                    if castbarBg then castbarBg:Hide() end
                                end
                            end
                            frame:Show()
                            frame:UpdateAllElements("GroupVisibility")
                        end
                    else
                        if frame:IsShown() then
                            -- Disable oUF elements before hiding to prevent a
                            -- single-frame flash when the unit attribute is cleared
                            for _, elem in ipairs({"Health", "Power", "Portrait", "Castbar", "Buffs", "Debuffs", "HealthPrediction"}) do
                                if frame[elem] and frame:IsElementEnabled(elem) then
                                    frame:DisableElement(elem)
                                end
                            end
                            frame:Hide()
                            frame:SetAttribute("unit", nil)
                        end
                    end
                end
            end
        end
    end
    ns.UpdateFrameVisibility = UpdateFrameVisibility

    if not frames._visFrame then
        frames._visFrame = CreateFrame("Frame")
        frames._visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frames._visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frames._visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frames._visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frames._visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        frames._visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        frames._visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frames._visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    frames._visFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _ufInCombat = true
            -- Alpha-only update (SetAlpha is not restricted during lockdown).
            -- Show/Hide paths inside UpdateFrameVisibility are guarded by isLocked.
            UpdateFrameVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            _ufInCombat = false
            UpdateFrameVisibility()
        else
            -- Defer to next frame to avoid taint from secure execution paths
            C_Timer.After(0, UpdateFrameVisibility)
        end
    end)
    UpdateFrameVisibility()

    ---------------------------------------------------------------------------
    --  Portrait border color: update when target/focus unit changes
    --  so "class color" mode reflects the new unit's color.
    ---------------------------------------------------------------------------
    if not frames._portraitBorderUpdater then
        frames._portraitBorderUpdater = CreateFrame("Frame")
        frames._portraitBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._portraitBorderUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    frames._portraitBorderUpdater:SetScript("OnEvent", function(_, event)
        local unitKey = (event == "PLAYER_TARGET_CHANGED") and "target" or "focus"
        local frame = frames[unitKey]
        if frame and (unitKey == "target" or unitKey == "focus") then
            local s = db.profile[unitKey]
            if frame.LeftText and s and s.leftTextClassColor ~= nil then
                ApplyClassColor(frame.LeftText, unitKey, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
            end
            if frame.RightText and s and s.rightTextClassColor ~= nil then
                ApplyClassColor(frame.RightText, unitKey, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
            end
            if frame.CenterText and s and s.centerTextClassColor ~= nil then
                ApplyClassColor(frame.CenterText, unitKey, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
            end
            -- Text bar class colors
            local btb = frame._btb
            if btb and s then
                if btb.LeftText then ApplyClassColor(btb.LeftText, unitKey, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB) end
                if btb.RightText then ApplyClassColor(btb.RightText, unitKey, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB) end
                if btb.CenterText then ApplyClassColor(btb.CenterText, unitKey, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB) end
            end
        end
        if not frame or not frame.Portrait then return end
        local backdrop = frame.Portrait.backdrop
        if not backdrop then return end
        local uSettings = db.profile[unitKey]
        -- Refresh detached portrait border class color
        if uSettings and uSettings.detachedPortraitClassColor then
            ApplyDetachedPortraitShape(backdrop, uSettings, unitKey)
        end
        -- Refresh class icon texture so it shows the actual unit class (not WARRIOR fallback)
        if backdrop._class and uSettings and (uSettings.portraitMode or "2d") == "class" then
            local _, ct = UnitClass(unitKey)
            if ct then
                local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
                ApplyClassIconTexture(backdrop._class, ct, classStyle)
            end
        end
    end)

    -- Deferred class portrait fix: at frame creation time UnitClass() may return nil
    -- for dynamic units (target, focus) because no unit is selected yet on login/reload.
    -- This causes the WARRIOR fallback. Re-apply the correct class icon once the
    -- client has finished loading and unit data is available.
    C_Timer.After(0, function()
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local frame = frames[unitKey]
            if frame and frame.Portrait then
                local backdrop = frame.Portrait.backdrop
                if backdrop and backdrop._class then
                    local uSettings = db.profile[unitKey]
                    if uSettings and (uSettings.portraitMode or "2d") == "class" then
                        local _, ct = UnitClass(unitKey)
                        if ct then
                            local classStyle = (uSettings and uSettings.classThemeStyle) or "modern"
                            ApplyClassIconTexture(backdrop._class, ct, classStyle)
                        end
                    end
                end
            end
        end
    end)

    -- Deferred normalization: some late-login updates can re-anchor power bars
    -- after frame construction. Re-apply two-point attached anchors once more.
    C_Timer.After(0, function()
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local frame = frames[unitKey]
            if frame and frame.Power and frame.Health then
                local s = GetSettingsForUnit(unitKey)
                if s then
                    local ppPos = s.powerPosition or "below"
                    if ppPos == "below" or ppPos == "above" then
                        frame.Power:ClearAllPoints()
                        if ppPos == "above" then
                            PP.Point(frame.Power, "BOTTOMLEFT", frame.Health, "TOPLEFT", 0, 0)
                            PP.Point(frame.Power, "BOTTOMRIGHT", frame.Health, "TOPRIGHT", 0, 0)
                        else
                            PP.Point(frame.Power, "TOPLEFT", frame.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(frame.Power, "TOPRIGHT", frame.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
        for i = 1, 5 do
            local bf = frames["boss" .. i]
            if bf and bf.Power and bf.Health then
                local s = GetSettingsForUnit("boss")
                if s then
                    local ppPos = s.powerPosition or "below"
                    if ppPos == "below" or ppPos == "above" then
                        bf.Power:ClearAllPoints()
                        if ppPos == "above" then
                            PP.Point(bf.Power, "BOTTOMLEFT", bf.Health, "TOPLEFT", 0, 0)
                            PP.Point(bf.Power, "BOTTOMRIGHT", bf.Health, "TOPRIGHT", 0, 0)
                        else
                            PP.Point(bf.Power, "TOPLEFT", bf.Health, "BOTTOMLEFT", 0, 0)
                            PP.Point(bf.Power, "TOPRIGHT", bf.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
    end)

    -- Apply all settings (cast bar colors, text, sizes, etc.) now that
    -- frames are spawned and anchored.
    ReloadFrames()
end


function SetupOptionsPanel()
    ns.db = db
    ns.frames = frames
    ns.ApplyFramePosition = ApplyFramePosition
    ns.GetFrameDimensions = GetFrameDimensions
    local reloadPending = false
    local reloadThrottle = CreateFrame("Frame")
    reloadThrottle:Hide()
    reloadThrottle:SetScript("OnUpdate", function(self)
        self:Hide()
        reloadPending = false
        ReloadFrames()
        ApplyBlizzCastbarState()
    end)
    ns.ReloadFrames = function()
        if not reloadPending then
            reloadPending = true
            reloadThrottle:Show()
        end
    end
    _G._EUF_ReloadFrames = ns.ReloadFrames

    -- Fake debuff icons for the boss preview. Three square icons anchored
    -- where the real Debuffs frame would live, sized to match the Simple
    -- Debuff Display layout (frame bar height, growing right-to-left off
    -- the frame's left edge). Created on demand and torn down on preview
    -- disable.
    local FAKE_DEBUFF_SPELLS = { 122, 172, 1714 }  -- Frost Nova, Corruption, Curse of Tongues
    local function AttachFakeDebuffs(frame)
        -- Tear down any prior holder so size/anchor refresh on every call.
        if frame._previewDebuffs then
            frame._previewDebuffs:Hide()
            frame._previewDebuffs:SetParent(nil)
            frame._previewDebuffs = nil
        end
        local settings = db.profile.boss or {}
        local simple = settings.simpleDebuffs ~= false
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        local iconSize
        if simple then
            iconSize = (settings.healthHeight or 34) + powerH
        else
            iconSize = settings.debuffSize or 22
        end
        local count = #FAKE_DEBUFF_SPELLS
        local gap = 1
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetSize(iconSize * count + gap * (count - 1), iconSize)
        holder:SetFrameLevel(frame:GetFrameLevel() + 5)
        holder:ClearAllPoints()
        -- The boss cast bar lives as a sibling parented to the frame but
        -- anchored BELOW frame bottom, so frame:GetHeight() excludes it.
        -- Mirror the live runtime behavior where bottom-anchored debuffs
        -- push down by the cast bar height to avoid overlap.
        local castBg = frame.Castbar and frame.Castbar:GetParent()
        local castbarH = (settings.showCastbar ~= false and castBg)
                         and castBg:GetHeight() or 0
        if simple then
            -- Simple mode: align debuff stack with the health bar top so
            -- they never encroach on the cast bar area.
            holder:SetPoint("TOPRIGHT", frame.Health or frame, "TOPLEFT", -1, 0)
        else
            local dAnc = settings.debuffAnchor or "bottomleft"
            if dAnc == "topleft" then
                holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, gap)
            elseif dAnc == "topright" then
                holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, gap)
            elseif dAnc == "bottomleft" then
                holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -gap - castbarH)
            elseif dAnc == "bottomright" then
                holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -gap - castbarH)
            elseif dAnc == "right" then
                holder:SetPoint("LEFT", frame, "RIGHT", gap, 0)
            else  -- "left" or fallback
                holder:SetPoint("RIGHT", frame, "LEFT", -gap, 0)
            end
        end
        for idx, spellID in ipairs(FAKE_DEBUFF_SPELLS) do
            local icon = holder:CreateTexture(nil, "ARTWORK")
            icon:SetSize(iconSize, iconSize)
            icon:SetPoint("RIGHT", holder, "RIGHT", -(idx - 1) * (iconSize + gap), 0)
            local tex = GetSpellTexture and GetSpellTexture(spellID)
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            if tex then icon:SetTexture(tex) end
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local border = CreateFrame("Frame", nil, holder)
            border:SetAllPoints(icon)
            border:SetFrameLevel(holder:GetFrameLevel() + 1)
            if PP and PP.CreateBorder then PP.CreateBorder(border, 0, 0, 0, 1) end
        end
        frame._previewDebuffs = holder
    end
    local function DetachFakeDebuffs(frame)
        if frame._previewDebuffs then frame._previewDebuffs:Hide() end
    end

    -- Refresh the in-game boss preview's fake debuffs when boss settings that
    -- affect them (simpleDebuffs, debuffAnchor, debuffSize) change.
    ns.RefreshBossPreviewDebuffs = function()
        if not ns._bossPreviewActive then return end
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then AttachFakeDebuffs(f) end
        end
    end

    -- Apply / clear a hostile-red health bar override on a boss frame while
    -- preview is active. Real boss frames never class-color (no player class),
    -- so piggybacking on unit="player" would otherwise paint the bar in the
    -- user's class color -- wrong for a preview.
    local PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B = 0.8, 0.2, 0.2
    local function ApplyBossPreviewColor(f)
        local h = f.Health
        if not h then return end
        f._previewColorSaved = f._previewColorSaved or {
            colorClass       = h.colorClass,
            colorReaction    = h.colorReaction,
            colorTapped      = h.colorTapped,
            colorDisconnected= h.colorDisconnected,
        }
        h.colorClass = false
        h.colorReaction = false
        h.colorTapped = false
        h.colorDisconnected = false
        h:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B)
        -- oUF's own update may re-color on the next tick; this PostUpdate
        -- keeps our override sticky for the duration of the preview.
        h.PostUpdateColor = function(self) self:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B) end
    end
    local function ClearBossPreviewColor(f)
        local h = f.Health
        if not h then return end
        local s = f._previewColorSaved
        if s then
            h.colorClass = s.colorClass
            h.colorReaction = s.colorReaction
            h.colorTapped = s.colorTapped
            h.colorDisconnected = s.colorDisconnected
            f._previewColorSaved = nil
        end
        h.PostUpdateColor = nil
    end

    -- Boss preview: force boss1/2/3 to render with the player's unit data so
    -- the user can see the boss frame styling live in-game without a real
    -- encounter. Gated out of combat to avoid taint; caller is responsible
    -- for auto-clearing on EUI options window close.
    ns.SetBossPreview = function(enabled)
        if InCombatLockdown() then return false end
        ns._bossPreviewActive = enabled and true or false
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then
                if enabled then
                    f:SetAttribute("unit", "player")
                    f:Show()
                    ApplyBossPreviewColor(f)
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    AttachFakeDebuffs(f)
                else
                    ClearBossPreviewColor(f)
                    f:SetAttribute("unit", "boss" .. i)
                    if not UnitExists("boss" .. i) then f:Hide() end
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    DetachFakeDebuffs(f)
                end
            end
        end
        return true
    end
    ns.ResolveFontPath = ResolveFontPath

    -- Trigger the EllesmereUI options module registration now that ns.db is ready
    if ns._InitEUIModule then
        ns._InitEUIModule()
    end

    ---------------------------------------------------------------------------
    --  Register unit frame elements with Unlock Mode
    ---------------------------------------------------------------------------
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local UNIT_LABELS = {
            player = "Player", target = "Target", focus = "Focus",
            pet = "Pet", targettarget = "Target of Target",
            focustarget = "Focus Target", boss = "Boss Frames",
            classPower = "Class Resource",
            playerCastbar = "Player Cast Bar",
            targetCastbar = "Target Cast Bar",
            focusCastbar = "Focus Cast Bar",
        }
        local elements = {}
        local orderBase = 100

        local function Rebuild() ns.ReloadFrames() end

        local function MakeUFElement(key, order)
            return MK({
                key = key,
                label = UNIT_LABELS[key] or key,
                group = "Unit Frames",
                order = orderBase + order,
                getFrame = function(k)
                    if k == "boss" then return frames["boss1"] end
                    if k == "classPower" then return frames._classPowerBar end
                    return frames[k]
                end,
                getSize = function(k)
                    if k == "classPower" then
                        if frames._classPowerBar then
                            local w = frames._classPowerBar:GetWidth()
                            local h = frames._classPowerBar:GetHeight()
                            if w < 10 then w = 120 end
                            if h < 5 then h = 14 end
                            return w, h
                        end
                        return 120, 14
                    end
                    if k == "boss" then return GetFrameDimensions("boss1") end
                    return GetFrameDimensions(k)
                end,
                setWidth = function(k, w)
                    if k == "classPower" then return end
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch then Rebuild(); return end
                    local unit = (k == "boss") and "boss1" or k
                    local s = GetSettingsForUnit(unit)
                    if not s then return end
                    local wPStyle = s.portraitStyle or db.profile.portraitStyle or "attached"
                    local showPortrait = wPStyle ~= "none" and s.showPortrait ~= false
                    local isAttached = wPStyle == "attached"
                    if showPortrait and isAttached then
                        local pSizeAdj = s.portraitSize or 0
                        if not isAttached then pSizeAdj = pSizeAdj + 10 end
                        local powerPos = s.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        local ptH = s.healthHeight + (powerIsAtt and (s.powerHeight or 6) or 0)
                        local adjPH = ptH + pSizeAdj
                        if adjPH < 8 then adjPH = 8 end
                        s.frameWidth = math.max(PP.Snap(w - adjPH), 50)
                    else
                        s.frameWidth = math.max(PP.Snap(w), 50)
                    end
                    Rebuild()
                end,
                setHeight = function(k, h)
                    if k == "classPower" then return end
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch then Rebuild(); return end
                    local unit = (k == "boss") and "boss1" or k
                    local s = GetSettingsForUnit(unit)
                    if not s then return end
                    local powerPos = s.powerPosition or "below"
                    local powerIsAtt = (powerPos == "below" or powerPos == "above")
                    local powerH = powerIsAtt and (s.powerHeight or 6) or 0
                    local btbPos = s.btbPosition or "bottom"
                    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
                    local btbH = (s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
                    s.healthHeight = math.max(PP.Snap(h - powerH - btbH), 8)
                    Rebuild()
                end,
                loadPos = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                savePos = function(k, point, relPoint, x, y)
                    db.profile.positions[k] = { point = point, relPoint = relPoint, x = x, y = y }
                    if EllesmereUI._unlockActive then return end
                    if k == "boss" then
                        local spacing = db.profile.bossSpacing or 60
                        -- boss1 to UIParent; chain 2..5 from the previous boss.
                        if frames.boss1 then
                            frames.boss1:ClearAllPoints()
                            frames.boss1:SetPoint(point, UIParent, relPoint, x, y)
                        end
                        for i = 2, 5 do
                            local bf = frames["boss" .. i]
                            local prev = frames["boss" .. (i - 1)]
                            if bf and prev then
                                bf:ClearAllPoints()
                                bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                            end
                        end
                    elseif k == "classPower" then
                        if frames._classPowerBar then
                            frames._classPowerBar:ClearAllPoints()
                            frames._classPowerBar:SetPoint(point, UIParent, relPoint, x, y)
                        end
                    else
                        local fr = frames[k]
                        if fr then
                            fr:ClearAllPoints()
                            fr:SetPoint(point, UIParent, relPoint, x, y)
                        end
                    end
                end,
                clearPos = function(k)
                    db.profile.positions[k] = nil
                end,
                applyPos = function(k)
                    local pos = db.profile.positions[k]
                    if not pos then return end
                    local pt = pos.point
                    local rpt = pos.relPoint or pt
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    -- Helper: snap (x, y) for a frame using SnapCenterForDim for
                    -- CENTER anchors and SnapForES otherwise. CENTER snap needs
                    -- the frame's actual size to handle odd-pixel-dim frames
                    -- correctly (cy must be integer + 0.5 for odd heights).
                    local function SnapForFrame(fr, x, y)
                        if not PPa or not fr or not x or not y then return x, y end
                        local es = fr:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER")
                            and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            return PPa.SnapCenterForDim(x, fr:GetWidth() or 0, es),
                                   PPa.SnapCenterForDim(y, fr:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            return PPa.SnapForES(x, es), PPa.SnapForES(y, es)
                        end
                        return x, y
                    end
                    if k == "boss" then
                        local spacing = db.profile.bossSpacing or 60
                        if frames.boss1 then
                            local bx, by = SnapForFrame(frames.boss1, pos.x, pos.y)
                            frames.boss1:ClearAllPoints()
                            frames.boss1:SetPoint(pt, UIParent, rpt, bx, by)
                        end
                        for i = 2, 5 do
                            local bf = frames["boss" .. i]
                            local prev = frames["boss" .. (i - 1)]
                            if bf and prev then
                                bf:ClearAllPoints()
                                bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                            end
                        end
                    elseif k == "classPower" then
                        if frames._classPowerBar then
                            px, py = SnapForFrame(frames._classPowerBar, px, py)
                            frames._classPowerBar:ClearAllPoints()
                            frames._classPowerBar:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    else
                        local fr = frames[k]
                        if fr then
                            px, py = SnapForFrame(fr, px, py)
                            fr:ClearAllPoints()
                            fr:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    end
                end,
            })
        end

        -- Core unit frames
        elements[#elements + 1] = MakeUFElement("player", 1)
        elements[#elements + 1] = MakeUFElement("target", 2)
        elements[#elements + 1] = MakeUFElement("focus", 3)
        elements[#elements + 1] = MakeUFElement("pet", 4)
        elements[#elements + 1] = MakeUFElement("targettarget", 5)
        elements[#elements + 1] = MakeUFElement("focustarget", 6)
        do
            local bossElem = MakeUFElement("boss", 7)
            -- Boss is a stack of 5 chained frames; resize / match actions
            -- don't make sense on the aggregate element. Boss can still
            -- anchor to other elements; it just can't be used as an anchor
            -- target.
            bossElem.noResize       = true   -- removes Width/Height Match + resize handles
            bossElem.noAnchorTarget = true   -- others cannot anchor to boss
            elements[#elements + 1] = bossElem
        end

        -- Conditional elements
        if db.profile.player.showClassPowerBar and not db.profile.player.lockClassPowerToFrame then
            elements[#elements + 1] = MakeUFElement("classPower", 9)
        end

        -- Cast bar elements: standalone registration, no special-case branching
        local function MakeCastBarElement(cbKey, unitKey, order)
            local function GetCBFrame()
                local uf = frames[unitKey]
                return uf and uf.Castbar and uf.Castbar:GetParent()
            end
            local function GetCBSettings()
                if unitKey == "player" then return db.profile.player end
                return GetSettingsForUnit(unitKey)
            end
            local function GetWidthKey()
                return unitKey == "player" and "playerCastbarWidth" or "castbarWidth"
            end
            local function GetHeightKey()
                return unitKey == "player" and "playerCastbarHeight" or "castbarHeight"
            end
            return MK({
                key = cbKey,
                label = UNIT_LABELS[cbKey] or cbKey,
                group = "Unit Frames",
                order = orderBase + order,
                getFrame = function() return GetCBFrame() end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local s = GetCBSettings()
                    if s then
                        local w = s[GetWidthKey()] or 181
                        local h = s[GetHeightKey()] or 14
                        return w, h
                    end
                    return 100, 14
                end,
                setWidth = function(_, w)
                    local s = GetCBSettings()
                    if not s then return end
                    local newW = math.max(PP.Snap(w), 30)
                    s[GetWidthKey()] = newW
                    local f = GetCBFrame()
                    if f then PP.Size(f, newW, f:GetHeight()) end
                end,
                setHeight = function(_, h)
                    if not EllesmereUI._unlockActive then return end
                    local s = GetCBSettings()
                    if not s then return end
                    local newH = math.max(PP.Snap(h), 5)
                    s[GetHeightKey()] = newH
                    local f = GetCBFrame()
                    if f then PP.Size(f, f:GetWidth(), newH) end
                    local uf = frames[unitKey]
                    local ico = uf and uf.Castbar and uf.Castbar._iconFrame
                    if ico then ico:SetSize(newH, newH) end
                end,
                loadPos = function()
                    local pos = db.profile.positions[cbKey]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                savePos = function(_, point, relPoint, x, y)
                    db.profile.positions[cbKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    if EllesmereUI._unlockActive then return end
                    local f = GetCBFrame()
                    if f then
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint, x, y)
                    end
                end,
                clearPos = function()
                    db.profile.positions[cbKey] = nil
                end,
                applyPos = function()
                    local pos = db.profile.positions[cbKey]
                    if not pos then return end
                    local f = GetCBFrame()
                    if not f then return end
                    local pt, rpt = pos.point, pos.relPoint or pos.point
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    if PPa and px and py then
                        local es = f:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, f:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, f:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    f:ClearAllPoints()
                    f:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                end,
            })
        end

        if db.profile.player.showPlayerCastbar then
            elements[#elements + 1] = MakeCastBarElement("playerCastbar", "player", 10)
        end
        if db.profile.target and db.profile.target.showCastbar ~= false then
            elements[#elements + 1] = MakeCastBarElement("targetCastbar", "target", 11)
        end
        if db.profile.focus and db.profile.focus.showCastbar ~= false then
            elements[#elements + 1] = MakeCastBarElement("focusCastbar", "focus", 12)
        end

        EllesmereUI:RegisterUnlockElements(elements)

        -- Seed default anchor + width-match for castbars so they start
        -- anchored to their parent frame with matched width out of the box.
        -- Only seed if the user has NEVER configured this castbar in unlock
        -- mode. Once they have (tracked by _castbarUnlockSeeded), stop
        -- overwriting their choices.
        if EllesmereUIDB then
            if not EllesmereUIDB.unlockAnchors then EllesmereUIDB.unlockAnchors = {} end
            if not EllesmereUIDB.unlockWidthMatch then EllesmereUIDB.unlockWidthMatch = {} end
            if not EllesmereUIDB._castbarUnlockSeeded then EllesmereUIDB._castbarUnlockSeeded = {} end
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar",  parent = "focus" },
            }
            local cbPositions = db and db.profile and db.profile.positions
            for _, def in ipairs(CB_DEFAULTS) do
                if not EllesmereUIDB._castbarUnlockSeeded[def.cb] then
                    -- Skip seeding if the user already has a saved position
                    -- (they moved the cast bar freely without anchoring)
                    local hasPos = cbPositions and cbPositions[def.cb]
                    if not hasPos then
                        if not EllesmereUIDB.unlockAnchors[def.cb] then
                            EllesmereUIDB.unlockAnchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                        end
                        if not EllesmereUIDB.unlockWidthMatch[def.cb] then
                            EllesmereUIDB.unlockWidthMatch[def.cb] = def.parent
                        end
                    end
                    -- Mark as seeded so we never overwrite user changes
                    EllesmereUIDB._castbarUnlockSeeded[def.cb] = true
                end
            end
        end
    end
end

StaticPopupDialogs["ELLESMERE_RELOAD_UI"] = {
    text = "Ellesmere Unit Frames setting changed. Reload UI to apply?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ELLESMERE_RESET_DEFAULTS"] = {
    text = "Reset all Ellesmere Unit Frames settings to defaults? This cannot be undone.",
    button1 = "Reset & Reload",
    button2 = "Cancel",
    OnAccept = function()
        if db then db:ResetProfile() end
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")
    end,
}

-- 3D portrait warning popup is now handled by EllesmereUI:ShowConfirmPopup
-- in EUI_UnitFrames_Options.lua (portrait mode dropdown handler).

local EllesmereUF = EllesmereUI.Lite.NewAddon("EllesmereUIUnitFrames")

function EllesmereUF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIUnitFramesDB", defaults, true)

    ResolveFontPath()

    -- Append SharedMedia textures to runtime tables so SM texture keys resolve
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(
            healthBarTextureNames,
            healthBarTextureOrder,
            nil,
            healthBarTextures
        )
    end

    -- Blizzard options panel is registered centrally in EllesmereUI.lua
end

function EllesmereUF:OnEnable()
    InitializeFrames()
    C_Timer.After(0, SetupOptionsPanel)
    C_Timer.After(0, function()
        if EllesmereUI and EllesmereUI.ApplyColorsToOUF then
            EllesmereUI.ApplyColorsToOUF()
        end
    end)

    -- Incompatible addon detection is handled globally by EllesmereUI
end
