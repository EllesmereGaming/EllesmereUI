local addonName, ns = ...

local math_floor, math_ceil, math_max, math_min, math_abs =
    math.floor, math.ceil, math.max, math.min, math.abs
local string_format = string.format
local issecretvalue = issecretvalue

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
            buffIconZoom   = 0.055,
            debuffIconZoom = 0.055,
            durationFormat = "blizzard",
        },
        castbarOpacity = 1.0,
        castbarColor = { r = 0.114, g = 0.655, b = 0.514 },
        portraitMode = "2d",
        portraitStyle = "attached",
        healthBarTexture = "none",
        darkTheme = false,
        -- Show one decimal on abbreviated values (240.5k) and percents (77.3%).
        -- Global, default off; read by the unit-frame text tags via _G flags.
        showDecimalOnText = false,
        -- When decimals are on, boss frames show two decimals (240.55k / 77.30%)
        -- instead of one. Default on. Inline cog on "Show Decimal on Health Text".
        showDecimalBoss2 = true,
        -- When decimals are on, "Only Show for % Health" keeps the decimal on the
        -- health PERCENT (77.3%) but leaves health VALUES whole (240k). Default
        -- off. Inline cog on "Show Decimal on Health Text".
        showDecimalPercentOnly = false,
        -- Player Threat (Non-Tank): additive "Shadow" border on the PLAYER frame
        -- when the player is pulling/has aggro, in instanced content only. Global,
        -- default off (zero cost until enabled). Colors mirror the nameplate
        -- non-tank threat defaults (has aggro / close to aggro).
        playerThreatBorderEnabled  = false,
        playerThreatHasAggroColor  = { r = 1.00, g = 0.50, b = 0.00 },
        playerThreatNearAggroColor = { r = 0.81, g = 0.72, b = 0.19 },
        -- Custom enemy reaction colors (empty = use Blizzard FACTION_BAR_COLORS).
        -- Keys: hostile (reactions 1-3), neutral (4), friendly (5-8), tapped.
        enemyColors = {},
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
            powerBgPowerColored = false,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
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
            -- Private Auras (Blizzard-rendered personal boss-mechanic icons).
            -- Player frame only. Opt-in; zero cost until paEnabled is true.
            paEnabled        = false,
            paSize           = 20,
            paShowCountdown  = false,
            paHideTooltip    = true,
            paPosition       = "center",
            paOffsetX        = 0,
            paOffsetY        = 0,
            paGrowDirection  = "RIGHT",
            paSpacing        = 0,
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
            extraTextContent = "none",
            extraTextSize = 12,
            extraTextX = 0,
            extraTextY = 0,
            extraTextClassColor = false,
            extraTextAlign = "left",
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            extraTextShortNameLength = 0,
            extraTextShortNameEllipsis = true,
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
            btbLeftShortNameLength = 0,
            btbLeftShortNameEllipsis = true,
            btbRightShortNameLength = 0,
            btbRightShortNameEllipsis = true,
            btbCenterShortNameLength = 0,
            btbCenterShortNameEllipsis = true,
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
            -- Absorb Bar / Heal Absorb Bar: separate strips (see Raid Frames)
            absorbBarPosition     = "none",
            absorbBarHeight       = 4,
            absorbBarColor        = { r = 1, g = 1, b = 1 },
            healAbsorbBarPosition = "none",
            healAbsorbBarHeight   = 4,
            healAbsorbBarColor    = { r = 200/255, g = 29/255, b = 29/255 },
            showPlayerCastbar = false,
            showPlayerCastIcon = true,
            playerCastbarIconInWidth = true,
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
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha       = 0.5,    -- whole-frame alpha while out of combat
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
            smoothBars = false,
            powerReverseFill = false,
        },
        target = {
            frameWidth = 181,
            -- Combat indicator (target frame): same option set as the player
            -- frame, but opt-in -- defaults to "none" so nothing changes for
            -- existing users until they pick a style.
            combatIndicatorStyle = "none",
            combatIndicatorColor = "custom",
            combatIndicatorCustomColor = { r = 1, g = 1, b = 1 },
            combatIndicatorPosition = "healthbar",
            combatIndicatorSize = 22,
            combatIndicatorX = 0,
            combatIndicatorY = 0,
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
            powerBgPowerColored = false,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
            castbarHeight = 14,
            castbarWidth = 181,
            showCastbar = true,
            showCastIcon = true,
            castbarIconInWidth = true,
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
            castbarInterruptReadyColor = { r = 0.92, g = 0.35, b = 0.20 },
            castbarKickTickEnabled = true,
            castbarInterruptMidCastEnabled = false,
            castbarInterruptMidCastColor = { r = 0.318, g = 0.820, b = 0.357 },
            castbarUninterruptibleColor = { r = 0.5, g = 0.5, b = 0.5 },
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
            extraTextContent = "none",
            extraTextSize = 12,
            extraTextX = 0,
            extraTextY = 0,
            extraTextClassColor = false,
            extraTextAlign = "left",
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            extraTextShortNameLength = 0,
            extraTextShortNameEllipsis = true,
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
            btbLeftShortNameLength = 0,
            btbLeftShortNameEllipsis = true,
            btbRightShortNameLength = 0,
            btbRightShortNameEllipsis = true,
            btbCenterShortNameLength = 0,
            btbCenterShortNameEllipsis = true,
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
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha       = 0.5,    -- whole-frame alpha while out of combat
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
            smoothBars = false,
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
            powerBgPowerColored = false,
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
            -- Absorb Bar / Heal Absorb Bar: separate strips (see Raid Frames)
            absorbBarPosition     = "none",
            absorbBarHeight       = 4,
            absorbBarColor        = { r = 1, g = 1, b = 1 },
            healAbsorbBarPosition = "none",
            healAbsorbBarHeight   = 4,
            healAbsorbBarColor    = { r = 200/255, g = 29/255, b = 29/255 },
            showPlayerCastbar = false,
            showClassPowerBar = false,
            classPowerBarX = 0,
            classPowerBarY = 0,
            playerCastbarX = 0,
            playerCastbarY = 0,
            playerCastbarWidth = 181,
            playerCastbarHeight = 14,
            healthReverseFill = false,
            smoothBars = false,
            powerReverseFill = false,
        },
        targettarget = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
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
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
            healthReverseFill = false,
            smoothBars = false,
        },
        -- Focus Target: independent clone of Target of Target defaults.
        -- MUST stay byte-identical to the targettarget block above so existing
        -- users (whose old shared totPet is migrated into BOTH tables) render
        -- identically; StripDefaults/DeepMergeDefaults rely on the match.
        focustarget = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
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
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
            healthReverseFill = false,
            smoothBars = false,
        },
        pet = {
            frameWidth = 101,
            healthHeight = 25,
            healthClassColored = false,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
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
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            powerPosition = "none",
            healthReverseFill = false,
            smoothBars = false,
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
            powerBgPowerColored = false,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
            castbarHeight = 14,
            castbarWidth = 160,
            showCastbar = true,
            showCastIcon = true,
            castbarIconInWidth = true,
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
            castbarInterruptReadyColor = { r = 0.92, g = 0.35, b = 0.20 },
            castbarKickTickEnabled = true,
            castbarInterruptMidCastEnabled = false,
            castbarInterruptMidCastColor = { r = 0.318, g = 0.820, b = 0.357 },
            castbarUninterruptibleColor = { r = 0.5, g = 0.5, b = 0.5 },
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
            extraTextContent = "none",
            extraTextSize = 12,
            extraTextX = 0,
            extraTextY = 0,
            extraTextClassColor = false,
            extraTextAlign = "left",
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            extraTextShortNameLength = 0,
            extraTextShortNameEllipsis = true,
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
            btbLeftShortNameLength = 0,
            btbLeftShortNameEllipsis = true,
            btbRightShortNameLength = 0,
            btbRightShortNameEllipsis = true,
            btbCenterShortNameLength = 0,
            btbCenterShortNameEllipsis = true,
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
            -- Absorb Bar / Heal Absorb Bar: separate strips (see Raid Frames)
            absorbBarPosition     = "none",
            absorbBarHeight       = 4,
            absorbBarColor        = { r = 1, g = 1, b = 1 },
            healAbsorbBarPosition = "none",
            healAbsorbBarHeight   = 4,
            healAbsorbBarColor    = { r = 200/255, g = 29/255, b = 29/255 },
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
            oocFadeEnabled = false,  -- "Fade Out of Combat" toggle (off by default)
            oocAlpha       = 0.5,    -- whole-frame alpha while out of combat
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
            smoothBars = false,
            powerReverseFill = false,
        },
        boss = {
            frameWidth = 160,
            healthHeight = 34,
            oorAlpha = 0.4,
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
            powerBgPowerColored = false,
            powerPercentTextPowerColor = false,
            healthClassColored = true,
            customBgColor = { r = 0.067, g = 0.067, b = 0.067 },
            bgClassColored = false,
            castbarHeight = 14,
            castbarWidth = 0,
            castbarOffsetX = 0,
            castbarOffsetY = 0,
            showCastbar = true,
            showCastIcon = true,
            castbarIconInWidth = true,
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
            buffCooldownTextColor = {r=1, g=1, b=1},
            buffStackTextColor = {r=1, g=1, b=1},
            debuffShowCooldownText = false,
            debuffCooldownTextSize = 10,
            debuffCooldownTextColor = {r=1, g=1, b=1},
            debuffStackTextColor = {r=1, g=1, b=1},
            simpleDebuffShowCooldownText = false,
            simpleDebuffCooldownTextSize = 14,
            simpleDebuffs = "left",  -- "none"/"left"/"right": simple display forces that-side anchor + frame-height-matched debuff size (legacy boolean true=left / false=none honored at read time)
            simpleBuffs = "none",  -- "none"/"left"/"right": simple BUFF display (mirrors simpleDebuffs but defaults off)
            simpleBuffShowCooldownText = false,
            simpleBuffCooldownTextSize = 14,
            buffSpacing = 1,
            debuffSpacing = 1,
            simpleBuffSpacing = 1,
            simpleDebuffSpacing = 1,
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
            leftTextShortNameLength = 0,
            leftTextShortNameEllipsis = true,
            rightTextShortNameLength = 0,
            rightTextShortNameEllipsis = true,
            centerTextShortNameLength = 0,
            centerTextShortNameEllipsis = true,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            borderTexture = "solid",
            highlightColor = { r = 1, g = 1, b = 1 },
            -- Boss Hover / Target border recolor (mirrors Raid Frames "Hover
            -- Borders"). Both default OFF; enabling one recolors the existing
            -- border to that color (hover takes priority over target).
            bossHoverBorderEnabled = false,
            bossHoverBorderColor = { r = 1, g = 1, b = 1 },
            bossHoverBorderAlpha = 1,
            bossTargetBorderEnabled = false,
            bossTargetBorderColor = { r = 1, g = 1, b = 1 },
            bossTargetBorderAlpha = 1,
            raidMarkerEnabled = true,
            raidMarkerSize = 28,
            raidMarkerAlign = "left",
            raidMarkerX = 0,
            raidMarkerY = 0,
            bossStackDirection = "down",
            healthReverseFill = false,
            smoothBars = false,
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
        -- Per-unit frame source: "eui" (EllesmereUI skinned frame), "blizzard"
        -- (leave Blizzard's default frame in place), or "hidden" (no frame).
        -- Resolved through ns.GetUnitFrameSource, which also honours the legacy
        -- enabledFrames flag (false => "hidden") for backward compatibility.
        frameSource = {},
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

        -- Player dispel overlay (player frame only; keys mirror Raid Frames)
        dispelOverlay        = "none",   -- "none", "fill", "full", "gradient", "gradient_sharp"
        dispelOverlayOpacity = 100,
        dispelOverlayByMe    = false,    -- only debuffs the player can dispel (engine filter token)
        dispelColorMagic   = { r = 0.349, g = 0.475, b = 1.0 },
        dispelColorCurse   = { r = 0.636, g = 0.0,   b = 0.64 },
        dispelColorDisease = { r = 0.671, g = 0.384, b = 0.098 },
        dispelColorPoison  = { r = 0.0,   g = 0.706, b = 0.286 },
        dispelColorBleed   = { r = 0.75,  g = 0.15,  b = 0.15 },
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

-- Additive bar gradients use two REUSED color objects so re-applying the gradient
-- allocates nothing (CreateColor would allocate two tables per call). oUF re-flattens
-- the bar color on every health/power event, so the gradient must be repainted in
-- PostUpdateColor each event -- this keeps that correct while removing the per-event
-- garbage. SetGradient copies the color values at call time, so one shared pair is
-- safe across every frame (player/target/focus/party/boss).
local _gradColorA = CreateColor(1, 1, 1, 1)
local _gradColorB = CreateColor(1, 1, 1, 1)

local function ApplyBarGradient(ft, dir, br, bg, bb, ba, er, eg, eb, ea)
    ft:SetVertexColor(1, 1, 1, 1)
    _gradColorA:SetRGBA(br, bg, bb, ba)
    _gradColorB:SetRGBA(er, eg, eb, ea)
    ft:SetGradient(dir, _gradColorA, _gradColorB)
end

local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }

-- Font resolution routes through the shared EllesmereUI.GetFontPath("unitFrames"),
-- which already handles glyph-restricted locales (CJK/Cyrillic): it keeps a
-- user-installed SharedMedia font that can render the locale's glyphs and only
-- falls back to the system glyph font otherwise. Unit frames must NOT re-decide
-- the locale fallback locally, or a locale client could never use a custom font
-- here even when every other module honors it.
local cachedFontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local cachedFontPaths = {}  -- per-unit font cache
local function ResolveFontPath(unitKey)
    local gPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    cachedFontPath = gPath
    for _, uKey in ipairs({"player", "target", "focus", "boss", "pet", "targettarget", "focustarget"}) do
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
  -- Outline flag is already slug-gated at the source (GetFontOutlineFlag).
  local f = flags or (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("unitFrames")) or ""
  -- 12.0.7: drop shadows only render from a FontObject; prime before SetFont.
  if EllesmereUI and EllesmereUI.PrimeFontShadow then
    EllesmereUI.PrimeFontShadow(fs, f == "")
  end
  fs:SetFont(GetSelectedFont(), size or 12, f)
end

-- Shared cast-bar text anchoring (mirrors the nameplate cast text system). The
-- cast bar text line holds three elements -- spell name, spell target, duration --
-- each assigned a side ("left" | "right" | "center"). The duration reserves a fixed
-- slot of width on its side; a non-center element sharing the duration's side is
-- shifted inward by that width. Center elements anchor to the bar center and are
-- never pushed.
--   side    : "left" | "right" | "center"
--   pushed  : true when the duration occupies this same side and this element moves inward
--   reserve : duration reserved width (only consumed when pushed)
--   isTimer : the duration uses slightly tighter base insets than text
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
-- a fresh build does. Clearing then re-setting the text forces the new alignment to
-- take effect, and it MUST be a real change -- re-setting the identical string is
-- deduped and skips the re-layout. GetText may return a secret (cast name/target);
-- SetText accepts secrets and the value is never inspected, so the round-trip is safe.
function ns.ReflowFontString(fs)
    if not fs then return end
    local t = fs:GetText()
    fs:SetText("")
    fs:SetText(t or "")
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
    ["blinkii-diamonds"] = TEXTURE_BASE .. "blinkii-diamonds.tga",
    ["kringel-window"]   = TEXTURE_BASE .. "kringel-window.tga",
}
local healthBarTextureOrder = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
    "blinkii-diamonds", "kringel-window",
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
    ["blinkii-diamonds"] = "Blinkii Diamonds",
    ["kringel-window"]   = "Kringel Window",
}
ns.healthBarTextures = healthBarTextures
ns.healthBarTextureOrder = healthBarTextureOrder
ns.healthBarTextureNames = healthBarTextureNames

-- Map a WoW unit ID ("player", "target", "boss1", "targettarget", etc.)
-- to the settings sub-table key in db.profile.
local function UnitToSettingsKey(unit)
    if not unit then return nil end
    if unit:match("^boss%d$") then return "boss" end
    if unit == "pet" then return "pet" end
    if db.profile[unit] then return unit end
    return nil
end

local function ApplyHealthBarTexture(health, unitKey, texKeyOverride)
    if not health then return end
    local texKey = texKeyOverride
    if not texKey then
        local s = unitKey and db.profile[unitKey]
        texKey = (s and s.healthBarTexture) or db.profile.healthBarTexture or "none"
    end
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

-- Resolve a unit's effective health bar texture KEY. Main frames use their own
-- key (falling back to the global default). Mini frames (pet, target of target,
-- focus target, boss) inherit the donor frame's texture (focus > target >
-- player) by default; a non-nil, non-"inherit" own key overrides that for this
-- frame only. Used by both the live frames and the options preview so they match.
ns.ResolveHealthBarTextureKey = function(ownSettings, donorSettings)
    local own = ownSettings and ownSettings.healthBarTexture
    if own and own ~= "inherit" then return own end
    if donorSettings then
        local d = donorSettings.healthBarTexture
        if d and d ~= "inherit" then return d end
    end
    return db.profile.healthBarTexture or "none"
end

-- Cast bars reuse the unit's health bar texture so every bar matches. The cast
-- bar stacks three textures over the fill bounds (base StatusBar fill + cast
-- tint + shielded tint), all defaulting to WHITE8X8, so apply the texture to
-- each. Attached to ns (not a file local) to avoid the Lua 200-local cap.
ns.ApplyCastBarTexture = function(castbar, texKey)
    if not castbar then return end
    local path = EllesmereUI.ResolveTexturePath(healthBarTextures, texKey or "none", "Interface\\Buttons\\WHITE8X8")
    castbar:SetStatusBarTexture(path)
    local fill = castbar:GetStatusBarTexture()
    if fill then
        fill:SetHorizTile(false)
        UnsnapTex(fill)
    end
    if castbar.castTintLayer then castbar.castTintLayer:SetTexture(path) end
    if castbar._shieldedTint then castbar._shieldedTint:SetTexture(path) end
end

-------------------------------------------------------------------------------
--  Health Bar Opacity -- controls the overall alpha of the health bar fill
-------------------------------------------------------------------------------
local function ApplyHealthBarAlpha(health, unitKey)
    if not health then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.healthBarOpacity or 90) or 90
    -- Handle old profiles that stored opacity as a 0-1 float instead of 0-100 int
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = health:GetStatusBarTexture()
    -- When a gradient is active the opacity is baked into the gradient endpoints,
    -- so the texture region alpha must stay 1 to avoid double-dimming.
    if fillTex then fillTex:SetAlpha((s and s.gradientEnabled) and 1 or fillA) end
    if health.bg then health.bg:SetAlpha((s and (s.customBgAlpha or 100) or 100) / 100) end
end

-------------------------------------------------------------------------------
--  Power Bar Opacity -- controls the overall alpha of the power bar
-------------------------------------------------------------------------------
local function ApplyPowerBarAlpha(power, unitKey)
    if not power then return end
    local s = unitKey and db.profile[unitKey]
    local opacity = s and (s.powerBarOpacity or 100) or 100
    -- Handle old profiles that stored opacity as a 0-1 float instead of 0-100 int
    if opacity <= 1.0 then opacity = opacity * 100 end
    local fillA = opacity / 100
    local fillTex = power:GetStatusBarTexture()
    -- Gradient bakes opacity into its endpoints, so keep region alpha at 1 then.
    if fillTex then fillTex:SetAlpha((s and s.powerGradientEnabled) and 1 or fillA) end
    if power.bg then power.bg:SetAlpha((s and (s.customPowerBgAlpha or 100) or 100) / 100) end
end

-------------------------------------------------------------------------------
--  Dark Mode -- flat dark health bar with gray background
-------------------------------------------------------------------------------
-- Non-dark fallback bg colour (#111) used when no class/custom colour source is
-- available. The Dark Mode fill/background come from the global per-profile
-- palette via EllesmereUI.GetDarkModeFill() / GetDarkModeBg() (see ApplyDarkTheme).
local DARK_HEALTH_R, DARK_HEALTH_G, DARK_HEALTH_B = 0x11/255, 0x11/255, 0x11/255  -- #111111

-- Anchor the health bg to cover ONLY the empty (missing-health) portion so a
-- reduced fill opacity never reveals the bg behind the filled section. The empty
-- side flips with reverse fill: a normal bar empties on the RIGHT, a reverse-fill
-- bar empties on the LEFT. Anchoring to the wrong side collapses the bg to zero
-- width whenever the bar is not full -- the reverse-fill "transparent background"
-- bug. The anchor is relational, so the edge tracks the fill as health changes.
local function AnchorHealthBg(health)
    local bg = health and health.bg
    local tex = health and health.GetStatusBarTexture and health:GetStatusBarTexture()
    if not bg or not tex then return end
    bg:ClearAllPoints()
    if health.GetReverseFill and health:GetReverseFill() then
        bg:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", tex, "BOTTOMLEFT", 0, 0)
    else
        bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    end
end

local function ClassColorSourceUnit(unitKey, unit)
    if unitKey == "pet" then return "player" end
    return unit or unitKey
end

local function ApplyDarkTheme(health)
    if not health then return end
    local isDark = db and db.profile and db.profile.darkTheme
    if isDark then
        health.colorClass = false
        health.colorClassPet = false
        health.colorReaction = false
        health.colorTapped = false
        health.colorDisconnected = false
        -- Dark fill/background pulled from the global per-profile Dark Mode palette.
        local dfr, dfg, dfb, dfa = EllesmereUI.GetDarkModeFill()
        local dbr, dbg, dbb, dba = EllesmereUI.GetDarkModeBg()
        health:SetStatusBarColor(dfr, dfg, dfb)
        local darkFillTex = health:GetStatusBarTexture()
        if darkFillTex then darkFillTex:SetAlpha(dfa) end
        if health.bg then
            -- Anchor bg to only cover the empty (missing-health) portion so the
            -- bar opacity fill shows the world behind it, not the bg color.
            AnchorHealthBg(health)
            -- Background opacity carried in the texture alpha; region alpha stays 1
            -- so the two never multiply into a double-darkened background.
            health.bg:SetColorTexture(dbr, dbg, dbb, dba)
            health.bg:SetAlpha(1)
        end
        -- PostUpdateColor: re-apply dark color after oUF tries to class-color,
        -- and re-anchor bg to track the fill edge.
        -- Alpha is NOT re-applied here -- SetStatusBarColor(r,g,b) with 3 args
        -- preserves existing texture alpha, so the alpha set by
        -- ApplyHealthBarAlpha persists through oUF recolors.
        health.PostUpdateColor = function(self)
            local fr, fg, fb = EllesmereUI.GetDarkModeFill()
            self:SetStatusBarColor(fr, fg, fb)
            if self.bg then
                AnchorHealthBg(self)
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
        health.colorClassPet = false
        if unitKey == "pet" then
            health.colorClass = false
            if unitSettings and unitSettings.healthClassColored then
                health.colorReaction = false
                health.colorTapped = false
                health.colorDisconnected = false
                local _, ct = UnitClass("player")
                local cc = ct and not issecretvalue(ct) and EllesmereUI.GetClassColor(ct)
                if cc then health:SetStatusBarColor(cc.r, cc.g, cc.b) end
            end
        end
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
        -- Alpha is NOT re-applied -- SetStatusBarColor(r,g,b) preserves
        -- existing texture alpha through oUF recolors.
        health.PostUpdateColor = function(self, unit, color)
            local uKey = self._euiUnitKey
            local uSettings = uKey and db.profile[uKey]
            local cFill = uSettings and uSettings.customFillColor
            local cBg   = uSettings and uSettings.customBgColor
            local classColored = uSettings and uSettings.healthClassColored
            local bgClassColored = uSettings and uSettings.bgClassColored
            -- Resolve base fill color (custom, or oUF's class/reaction color), then apply
            -- gradient additively when enabled; otherwise the existing flat behavior.
            local bR, bG, bB
            if cFill and not classColored then
                bR, bG, bB = cFill.r, cFill.g, cFill.b
            elseif classColored and uKey == "pet" then
                local _, ct = UnitClass("player")
                local cc = ct and not issecretvalue(ct) and EllesmereUI.GetClassColor(ct)
                if cc then bR, bG, bB = cc.r, cc.g, cc.b end
            elseif color and color.GetRGB then
                bR, bG, bB = color:GetRGB()
            end
            if uSettings and uSettings.gradientEnabled and bR then
                local gc = uSettings.gradientColor
                -- A gradient overrides the texture's region alpha, so Bar Opacity
                -- is baked into the gradient endpoint alphas instead of SetAlpha.
                local ga = uSettings.healthBarOpacity or 90
                if ga > 1.0 then ga = ga / 100 end
                ApplyBarGradient(self:GetStatusBarTexture(), uSettings.gradientDir or "HORIZONTAL",
                    bR, bG, bB, ga,
                    gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
            elseif classColored and uKey == "pet" and bR then
                self:SetStatusBarColor(bR, bG, bB)
            elseif cFill and not classColored then
                self:SetStatusBarColor(cFill.r, cFill.g, cFill.b)
            end
            if self.bg then
                -- Keep bg covering only the empty (missing-health) portion as
                -- health changes, so a reduced fill opacity never reveals the bg
                -- behind the filled section. Matches the dark-mode path.
                AnchorHealthBg(self)
                local bgClassR, bgClassG, bgClassB
                if bgClassColored then
                    local classUnit = ClassColorSourceUnit(uKey, unit or self.unit or uKey)
                    if classUnit then
                        local _, ct = UnitClass(classUnit)
                        -- ct can be a secret value (out-of-range/uninspectable units); skip if so.
                        local cc = ct and not issecretvalue(ct) and EllesmereUI.GetClassColor(ct)
                        if cc then bgClassR, bgClassG, bgClassB = cc.r, cc.g, cc.b end
                    end
                end
                if bgClassR then
                    -- Full class color; opacity is controlled by customBgAlpha (SetAlpha).
                    self.bg:SetColorTexture(bgClassR, bgClassG, bgClassB, 1)
                elseif cBg then
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
            -- Anchor bg to only cover the empty (missing-health) portion so the
            -- bar opacity fill shows the world behind it, not the bg color. The
            -- anchor is relational, so the left edge tracks the fill as health
            -- changes; PostUpdateColor re-applies it to survive texture swaps.
            AnchorHealthBg(health)
            local bgClassColored = unitSettings and unitSettings.bgClassColored
            local bgClassR, bgClassG, bgClassB
            if bgClassColored then
                local classUnit = ClassColorSourceUnit(unitKey, unitKey or (health.__owner and health.__owner.unit))
                if classUnit then
                    local _, ct = UnitClass(classUnit)
                    -- ct can be a secret value (out-of-range/uninspectable units); skip if so.
                    local cc = ct and not issecretvalue(ct) and EllesmereUI.GetClassColor(ct)
                    if cc then bgClassR, bgClassG, bgClassB = cc.r, cc.g, cc.b end
                end
            end
            if bgClassR then
                -- Full class color; PostUpdateColor keeps it correct on updates.
                health.bg:SetColorTexture(bgClassR, bgClassG, bgClassB, 1)
            elseif customBg then
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

-- Re-apply the dark theme to every frame when the global Dark Mode palette
-- changes (fill/background colour + opacity). Class/power darken propagates via
-- ApplyColorsToOUF, which RefreshDarkMode() calls right after these refreshers.
if EllesmereUI.RegisterDarkModeRefresh then
    EllesmereUI.RegisterDarkModeRefresh(function()
        local oUF = _G.EllesmereUF
        if oUF and oUF.objects then
            for _, obj in next, oUF.objects do
                if obj.Health then ApplyDarkTheme(obj.Health) end
            end
        end
        -- The boss "Activate Preview" fake frames need their red class-color
        -- substitute re-applied after the dark repaint above.
        if ns._bossPreviewActive and ns._ReapplyBossPreviewColor then
            ns._ReapplyBossPreviewColor()
        end
    end)
end

-- Global Dark Mode master: expose Unit Frames' darkTheme flag so the parent
-- addon's master toggle can flip it alongside the other modules. setOn mirrors
-- the individual Dark Mode toggle (write the flag + reload the frames).
if EllesmereUI.RegisterDarkModeToggle then
    EllesmereUI.RegisterDarkModeToggle({
        id = "unitFrames",
        isOn = function()
            return (db and db.profile and db.profile.darkTheme) or false
        end,
        setOn = function(on)
            if not (db and db.profile) then return end
            db.profile.darkTheme = on
            if ns.ReloadFrames then ns.ReloadFrames() end
        end,
    })
end

-- Smart power text: percent for healers/prot pally/arcane mage, numeric for everyone else.
-- Shared helper used by both the oUF tag and the resource bars renderer.
-- `displayedPowerType` (optional, an Enum.PowerType value) is the power the
-- caller's bar is actually showing. For form/spec-shifting classes (Druid,
-- Monk) the decision must follow the displayed power, NOT UnitPowerType: a
-- Balance druid's UnitPowerType is Astral Power even while the power bar shows
-- Mana, so without this the mana number would render raw instead of percent.
local function EUI_IsSmartPowerPercent(displayedPowerType)
    local _, cls = UnitClass("player")
    if not cls then return false end
    -- Druid / Monk both shift their displayed power with form/spec. Percent
    -- only while the bar shows Mana (Druid caster/Tree/travel + Mistweaver),
    -- raw value otherwise (Cat=Energy, Bear=Rage, Moonkin=Astral, WW/BRM=Energy).
    -- This is consistent across every spec, including Restoration weaving
    -- Cat/Bear where the bar is really Energy/Rage. Prefer the caller-supplied
    -- displayed power; fall back to the live primary power type.
    if cls == "DRUID" or cls == "MONK" then
        local pt = displayedPowerType or UnitPowerType("player")
        return pt == Enum.PowerType.Mana
    end
    if cls == "PRIEST" or cls == "SHAMAN" then
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

-- Show Decimal on Text (global, default off). A Blizzard AbbreviateNumbers config
-- that emits one decimal per magnitude band: 240500 -> "240.5k", 2405000 -> "2.4m".
-- AbbreviateNumbers runs in Blizzard's secure context, so feeding it a secret value
-- PLUS this config stays secret-safe (exactly like the no-config call we already use
-- on secret health/power). Tags read two _G flags (sandbox falls back to _G):
--   _G._EUI_AbbrevDecimalCfg = this table when on, nil when off (nil == today's call)
--   _G._EUI_TextDecimals     = true/false, selects "%.1f" vs "%d" for percents
ns._decimalAbbrevConfig = { breakpointData = {
    { breakpoint = 1e9, abbreviation = "b", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
} }
-- Two-decimal variant for boss frames ("Show 2 for Boss"): 240.55k / 2.45m.
-- Per band: significandDivisor = breakpoint / 100, fractionDivisor = 100.
ns._decimalAbbrevConfig2 = { breakpointData = {
    { breakpoint = 1e9, abbreviation = "b", significandDivisor = 1e7, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e4, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e1, fractionDivisor = 100, abbreviationIsGlobal = false },
} }
function ns.ApplyTextDecimalGlobals()
    if db and db.profile and db.profile.showDecimalOnText then
        _G._EUI_TextDecimals = true
        -- "Only Show for % Health": keep the decimal on the health PERCENT but
        -- leave health/absorb VALUES whole. Achieved by withholding the abbreviate
        -- configs (values fall back to the plain whole-number AbbreviateNumbers)
        -- while _EUI_TextDecimals stays true for the percent tags.
        local percentOnly = db.profile.showDecimalPercentOnly
        _G._EUI_AbbrevDecimalCfg = ns._decimalAbbrevConfig
        if percentOnly then _G._EUI_AbbrevDecimalCfg = nil end
        -- Boss frames get a second decimal place (default on). Tags fall back
        -- to the 1-decimal path for every non-boss unit when the flag is set,
        -- and ignore it entirely when nil.
        if db.profile.showDecimalBoss2 ~= false then
            _G._EUI_BossExtraDecimal = true
            _G._EUI_AbbrevDecimalCfg2 = ns._decimalAbbrevConfig2
            if percentOnly then _G._EUI_AbbrevDecimalCfg2 = nil end
        else
            _G._EUI_BossExtraDecimal = false
            _G._EUI_AbbrevDecimalCfg2 = nil
        end
    else
        _G._EUI_TextDecimals = false
        _G._EUI_AbbrevDecimalCfg = nil
        _G._EUI_BossExtraDecimal = false
        _G._EUI_AbbrevDecimalCfg2 = nil
    end
end

do
  local tagName = "curhpshort"
  local function AbbrevHP(unit)
    if not unit or not UnitExists(unit) then return "" end
    if not UnitIsConnected(unit) then return "OFFLINE" end
    if UnitIsDeadOrGhost(unit) then return "DEAD" end
    local hp = UnitHealth(unit) or 0
    local cfg = _G._EUI_AbbrevDecimalCfg
    -- Boss frames use the 2-decimal config when "Show 2 for Boss" is on.
    if _G._EUI_BossExtraDecimal and string.sub(unit, 1, 4) == "boss" then
      cfg = _G._EUI_AbbrevDecimalCfg2
    end
    return cfg and AbbreviateNumbers(hp, cfg) or AbbreviateNumbers(hp)
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
    if _G._EUI_BossExtraDecimal and string.sub(unit, 1, 4) == "boss" then
      return string_format("%.2f", pct)
    end
    return string_format(_G._EUI_TextDecimals and "%.1f" or "%d", pct)
  end
  oUF.Tags.Events["perhpnosign"] = "UNIT_HEALTH UNIT_MAXHEALTH"
end

-- Resolved power type per unit. Updated by GetDisplayPower override so
-- tags match the power bar when powerTypeOverride is active (e.g. Balance
-- Druid showing Mana instead of Astral Power).
_G._EUI_ResolvedPowerType = _G._EUI_ResolvedPowerType or {}

-- eui-perpp: power percent using resolved power type (runs in oUF _PROXY env)
-- Power percent is intentionally NOT decimal-gated: "Show Decimal on Text"
-- applies to health text only, so power keeps integer percents.
oUF.Tags.Methods["eui-perpp"] = [[function(u)
    local pType = _EUI_ResolvedPowerType[u] or UnitPowerType(u)
    return string.format('%d', UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100))
end]]
oUF.Tags.Events["eui-perpp"] = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"

-- eui-perhp: health percent, EUI-owned so "Show Decimal on Text" can switch
-- %d / %.1f without editing the vendored oUF [perhp]. Mirrors [perhp] otherwise.
oUF.Tags.Methods["eui-perhp"] = [[function(u)
    local fmt = _EUI_TextDecimals and '%.1f' or '%d'
    if _EUI_BossExtraDecimal and string.sub(u, 1, 4) == 'boss' then fmt = '%.2f' end
    return string.format(fmt, UnitHealthPercent(u, true, CurveConstants.ScaleTo100))
end]]
oUF.Tags.Events["eui-perhp"] = "UNIT_HEALTH UNIT_MAXHEALTH"

-- eui-curpp: current power as abbreviated number
-- Power value is intentionally NOT decimal-gated (health-only feature).
oUF.Tags.Methods["eui-curpp"] = [[function(u)
    local pType = _EUI_ResolvedPowerType[u] or UnitPowerType(u)
    return AbbreviateNumbers(UnitPower(u, pType))
end]]
oUF.Tags.Events["eui-curpp"] = "UNIT_POWER_UPDATE UNIT_MAXPOWER UNIT_DISPLAYPOWER"

-- eui-absorb: full absorb amount, blank when zero
oUF.Tags.Methods["eui-absorb"] = [[function(u)
    if not u or not UnitExists(u) then return "" end
    return string.format("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0))
end]]
oUF.Tags.Events["eui-absorb"] = "UNIT_ABSORB_AMOUNT_CHANGED"

-- eui-absorbshort: absorb amount abbreviated (e.g. 236k). AbbreviateNumbers is
-- secret-safe -- the same call the [curhpshort] health tag uses on the secret
-- health value. Shows "0" when there is no shield (AbbreviateNumbers has no
-- blank-at-zero; only the full TruncateWhenZero variant blanks).
oUF.Tags.Methods["eui-absorbshort"] = [[function(u)
    if not u or not UnitExists(u) then return "" end
    local cfg = _EUI_AbbrevDecimalCfg
    return cfg and AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0, cfg) or AbbreviateNumbers(UnitGetTotalAbsorbs(u) or 0)
end]]
oUF.Tags.Events["eui-absorbshort"] = "UNIT_ABSORB_AMOUNT_CHANGED"

-- eui-healabsorb: full heal-absorb amount, blank when zero (mirrors eui-absorb
-- with UnitGetTotalHealAbsorbs). TruncateWhenZero blanks naturally at zero.
oUF.Tags.Methods["eui-healabsorb"] = [[function(u)
    if not u or not UnitExists(u) then return "" end
    return string.format("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalHealAbsorbs(u) or 0))
end]]
oUF.Tags.Events["eui-healabsorb"] = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"

-- eui-healabsorbshort: heal-absorb abbreviated (e.g. 80k). Like eui-absorbshort
-- it shows "0" at zero, so the "Heal Absorb Short" text gate hides it then.
oUF.Tags.Methods["eui-healabsorbshort"] = [[function(u)
    if not u or not UnitExists(u) then return "" end
    local cfg = _EUI_AbbrevDecimalCfg
    return cfg and AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0, cfg) or AbbreviateNumbers(UnitGetTotalHealAbsorbs(u) or 0)
end]]
oUF.Tags.Events["eui-healabsorbshort"] = "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"

-- Resolve the class/reaction color for a unit's NAME, enemy-aware: players (and
-- AI party members) get their class color; NPCs use reaction color (hostile red,
-- neutral yellow, friendly green, tap-denied gray) so enemies tint correctly --
-- the custom Enemy Colors override is honored because it is baked into
-- oUF.colors.reaction. Returns r, g, b (0-1) or nil (caller uses its own default).
-- Secret-value safe for uninspectable units. Namespaced (not a new file local) to
-- stay under the local cap; shared by ApplyClassColor and the eui-tgtname tag
-- so the target name in "Name > Target" colors identically to the unit frame name.
ns.ResolveUnitNameColor = function(unit)
    if not unit then return nil end
    if UnitIsPlayer(unit) or (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
        local _, class = UnitClass(unit)
        if class and not issecretvalue(class) then
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if c then return c.r, c.g, c.b end
        end
        return nil
    end
    if UnitExists(unit) then
        if UnitIsTapDenied and UnitIsTapDenied(unit) then
            return 0.6, 0.6, 0.6
        end
        local reaction = UnitReaction(unit, "player")
        if reaction and not issecretvalue(reaction) then
            local c = (oUF.colors and oUF.colors.reaction and oUF.colors.reaction[reaction])
                or FACTION_BAR_COLORS[reaction]
            if c then return c.r, c.g, c.b end
        end
    end
    return nil
end

-- External nickname providers (Northern Sky Raid Tools / Timeline Reminders /
-- Liquid) key us by this addon name. Suite = the brand "EllesmereUI" (the parent
-- they registered support for) so a single provider checkbox controls every EUI
-- module; standalone = our renamed folder name (which contains "Standalone", a
-- token the standalone rename never touches, so detection is rename-immune). On
-- ns (not a new file-scope local) to respect the Lua 5.1 200-local ceiling.
ns.NICK_ADDON = addonName:find("Standalone") and addonName or "EllesmereUI"

-- Resolve a unit's display name, consulting nickname providers in order: NSRT
-- (NSAPI) -> MethodInternal (EasyNicknameAPI) -> Timeline Reminders
-- (TimelineReminders) -> Liquid (LiquidAPI), then the raw unit name. Each provider
-- is pcall-wrapped so a misbehaving external API can never break names.
--
-- SECRET-SAFE for target/focus/etc.: an enemy unit's UnitName is a secret value
-- in protected content, and any Lua op on it (==, .., format) throws. Nicknames
-- only ever apply to your own group members, so:
--   * non-players short-circuit to the raw name (no provider can have a nickname),
--   * name-keyed providers (NSRT, Liquid) are skipped when the name is secret,
--   * Timeline Reminders is UNIT-keyed (GetNickname(unit)), so it is safe to
--     consult regardless -- its result is still re-validated as a clean string.
-- The final return may be the raw (possibly secret) name; that is display-safe
-- because oUF feeds tag returns to SetFormattedText as a %s arg, never inspecting
-- them (exactly how the stock [name] tag stays safe).
function ns.ResolveUnitNickname(unit)
    local name = UnitName(unit)
    if not name then return "" end
    -- Master toggle (Unit Frames > main frames > Display, default OFF): when off,
    -- skip every provider lookup and show the raw unit name. One switch for all
    -- main frames. Returning the raw (possibly secret) name here is display-safe.
    if not (db and db.profile and db.profile.showNicknames) then return name end
    -- Nicknames are a player-only concept; NPCs (bosses, etc.) keep their name.
    if not UnitIsPlayer(unit) then return name end
    local nameSecret = issecretvalue and issecretvalue(name)
    local display
    if not nameSecret and NSAPI and NSAPI.GetName then
        local ok, dn = pcall(NSAPI.GetName, NSAPI, name, "EUI")
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    if not display and not nameSecret and EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnit then
        local ok, dn = pcall(EasyNicknameAPI.GetNicknameForUnit, unit)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" and dn ~= name then
            display = dn
        end
    end
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, ns.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unit)
                if okHas and has then
                    local ok, dn = pcall(TR.GetNickname, TR, unit)
                    if ok and type(dn) == "string"
                       and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                        display = dn
                    end
                end
            end
        end
    end
    if not display and not nameSecret and LiquidAPI and LiquidAPI.GetNicknameForEllesmereUI then
        local ok, dn = pcall(LiquidAPI.GetNicknameForEllesmereUI, name)
        if ok and type(dn) == "string"
           and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    if display then return display end
    return name
end

-- Nickname-aware replacement for the stock [name] tag (see ContentToTag). Returns
-- the nickname when one applies, else the raw unit name -- identical to [name] for
-- everyone without a nickname.
oUF.Tags.Methods["eui-name"] = function(unit, realUnit, lenStr, ellipsisStr)
    local name = ns.ResolveUnitNickname(unit)
    local maxLen = tonumber(lenStr) or 0
    if maxLen <= 0 then return name end
    -- Secret names (enemy target/focus in protected content) cannot be
    -- inspected: #, sub and concat all throw. Return the secret raw -- the
    -- display sink accepts it -- so those names render untruncated.
    if issecretvalue and issecretvalue(name) then return name end
    -- Truncate by UTF-8 codepoints, never bytes: multibyte names (Cyrillic,
    -- CJK, accents) must cut on a character boundary, and byte length would
    -- overcount their character count.
    local i, chars = 1, 0
    local len = #name
    while i <= len do
        if chars == maxLen then
            local cut = name:sub(1, i - 1)
            if ellipsisStr ~= "0" then return cut .. "..." end
            return cut
        end
        local b = name:byte(i)
        i = i + ((b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1)
        chars = chars + 1
    end
    return name
end
oUF.Tags.Events["eui-name"] = "UNIT_NAME_UPDATE"

-- Live name refresh: re-run every spawned frame's tags so added/removed nicknames
-- (or a flipped provider checkbox) apply instantly without a /reload. Fired by the
-- provider callbacks below; cheap (a handful of frames).
function ns.RefreshAllUnitNames()
    for _, f in pairs(frames) do
        if type(f) == "table" and f.UpdateTags then f:UpdateTags() end
    end
end
-- Name tags only re-render on name events or via the refresh above, so a raw
-- db restore (Spec Overrides apply, profile swap) needs this exported.
_G._EUF_RefreshUnitNames = ns.RefreshAllUnitNames

-- Cold-login text repaint: on a first (uncached) login a unit-frame text
-- fontstring can hold the correct string yet render blank until a /reload. A
-- fontstring only repaints when its text changes, and re-running the tag sets the
-- same string (a no-op), so shortly after login we force a "" -> value transition
-- on every tagged fontstring, repeated a few times as the timing varies. Only
-- ._curTag strings are blanked (UpdateTags restores them) and the blank+restore is
-- synchronous, so there is no visible flicker.
do
    local TEXT_FIELDS = { "LeftText", "RightText", "CenterText", "ExtraText" }

    local function ForceTextRepaint()
        for _, f in pairs(frames) do
            if type(f) == "table" then
                local changed = false
                for _, host in ipairs({ f, f.BottomTextBar }) do
                    if type(host) == "table" then
                        for _, key in ipairs(TEXT_FIELDS) do
                            local fs = host[key]
                            if fs and fs._curTag and fs.SetText then
                                fs:SetText("")
                                changed = true
                            end
                        end
                    end
                end
                if changed and f.UpdateTags then f:UpdateTags() end
            end
        end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        for _, delay in ipairs({ 0.25, 1, 3 }) do
            C_Timer.After(delay, ForceTextRepaint)
        end
    end)
end

-- Provider callbacks. NSRT (NSAPI) and Timeline Reminders (TR) may load after us,
-- so registration retries on PLAYER_LOGIN / PLAYER_ENTERING_WORLD until it sticks.
-- Registrant key is "EllesmereUIUnitFrames" (NOT "EllesmereUI" -- Raid Frames
-- already owns that key, and CallbackHandler keys registrations by it, so reusing
-- it would clobber one module). The provider CHECKBOX key stays the shared
-- ns.NICK_ADDON / "EUI", so one provider toggle drives raid AND unit frames.
do
    local function RefreshNames() if ns.RefreshAllUnitNames then ns.RefreshAllUnitNames() end end
    local function RegisterNSRT()
        if ns._nsrtNickHooked then return true end
        if NSAPI and NSAPI.RegisterCallback then
            NSAPI.RegisterCallback("EllesmereUIUnitFrames", "NSRT_NICKNAME_UPDATED", RefreshNames)
            NSAPI.RegisterCallback("EllesmereUIUnitFrames", "EUI_NICKNAME_TOGGLE", RefreshNames)
            ns._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterTR()
        if ns._trNickHooked then return true end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            TR.RegisterCallback("EllesmereUIUnitFrames", "TimelineReminders_NicknameToggle", function(_, _, addOnName)
                if addOnName == ns.NICK_ADDON then RefreshNames() end
            end)
            TR.RegisterCallback("EllesmereUIUnitFrames", "TimelineReminders_NicknameUpdate", function()
                RefreshNames()
            end)
            ns._trNickHooked = true
            return true
        end
        return false
    end
    if not (RegisterNSRT() and RegisterTR()) then
        local nf = CreateFrame("Frame")
        nf:RegisterEvent("PLAYER_LOGIN")
        nf:RegisterEvent("PLAYER_ENTERING_WORLD")
        nf:SetScript("OnEvent", function(self, event)
            local a = RegisterNSRT()
            local b = RegisterTR()
            if (a and b) or event == "PLAYER_ENTERING_WORLD" then self:UnregisterAllEvents() end
        end)
    end
end

-- "Name > Target" is built from FOUR tags so the (possibly SECRET) target name is
-- never compared/concatenated/string.format'd in Lua -- oUF joins the tag returns via
-- SetFormattedText, where the name is only a %s display arg (exactly how the stock
-- [name] tag stays safe). ContentToTag maps "nametotarget" to
-- "[name][eui-tgtsep(...)][eui-tgtcol][eui-tgtname]":
--   [name]        -> the unit's own name (zone-colored, stock oUF tag)
--   [eui-tgtsep]  -> the indicator between the names, only when the unit has a
--                    target. Per-slot separator string and indicator color ride
--                    in the tag ARGS (see BuildTgtSepTag); no args = " > ".
--   [eui-tgtcol]  -> the target's class/reaction COLOR escape (no name involved)
--   [eui-tgtname] -> the target's name, returned RAW
-- The colour escape precedes the raw name and runs to the end of the string, so the
-- target name is class-coloured IDENTICALLY to the Target of Target frame name (both
-- colours come from ns.ResolveUnitNameColor). It works even for a SECRET name, because
-- the colour and the name are SEPARATE tags joined by SetFormattedText -- never touched
-- together in Lua (UnitName for an enemy target in protected content is secret, and any
-- Lua op on it -- ==, .., string.format -- throws).
--
-- PLAYER_TARGET_CHANGED is unitless in oUF (refreshes every frame), covering the
-- player frame's target; UNIT_TARGET covers target/focus frames' own target.

-- Separator/indicator between the names, shown only when the unit has a target.
-- Plain literal plus color escapes -- no secret is ever touched. Args:
--   sepHex    -> the separator string, hex-encoded per byte (any character the
--                user types is safe inside the tag brackets); rendered with a
--                space on each side, exactly like the stock " > ".
--   colorSpec -> "class" = the TARGET's class/reaction color (same resolver as
--                the target name), else a fixed "rrggbb" hex. The escape is
--                closed with |r so a missing [eui-tgtcol] cannot inherit it.
-- Decoded separators and custom escapes are cached: the tag fires on every
-- target change and must not allocate after warmup.
do
    local sepCache = {}   -- sepHex -> " sep " (decoded, space-padded)
    local escCache = {}   -- rrggbb -> "|cffrrggbb"
    local function HexToChar(h) return string.char(tonumber(h, 16)) end
    oUF.Tags.Methods["eui-tgtsep"] = function(unit, _, sepHex, colorSpec)
        if not (unit and UnitExists(unit .. "target")) then return "" end
        local sep = " > "
        if sepHex then
            sep = sepCache[sepHex]
            if not sep then
                sep = " " .. sepHex:gsub("%x%x", HexToChar) .. " "
                sepCache[sepHex] = sep
            end
        end
        if colorSpec == "class" then
            local r, g, b = ns.ResolveUnitNameColor(unit .. "target")
            if r then
                return string.format("|cff%02x%02x%02x%s|r",
                    math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                    math.floor(b * 255 + 0.5), sep)
            end
            return sep
        elseif colorSpec then
            local esc = escCache[colorSpec]
            if not esc then esc = "|cff" .. colorSpec; escCache[colorSpec] = esc end
            return esc .. sep .. "|r"
        end
        return sep
    end
end
-- UNIT_FACTION mirrors [eui-tgtcol]: the class-colored indicator must recolor
-- when the target's reaction flips, exactly like the target name it precedes.
oUF.Tags.Events["eui-tgtsep"] = "UNIT_TARGET PLAYER_TARGET_CHANGED UNIT_FACTION"

-- The target's class/reaction colour escape (e.g. "|cffc41f3b"), or "" when none. Uses
-- ns.ResolveUnitNameColor -- the SAME resolver ApplyClassColor uses for the Target of
-- Target name. No unit NAME is touched, so it is fully secret-safe.
oUF.Tags.Methods["eui-tgtcol"] = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    local r, g, b = ns.ResolveUnitNameColor(tunit)
    if not r then return "" end
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
oUF.Tags.Events["eui-tgtcol"] = "UNIT_TARGET PLAYER_TARGET_CHANGED UNIT_FACTION"

-- The unit's target NAME (nickname-aware via ResolveUnitNickname; raw name
-- otherwise, possibly secret -- display-safe via SetFormattedText, never
-- inspected). The colour comes from [eui-tgtcol] in front of it.
oUF.Tags.Methods["eui-tgtname"] = function(unit)
    local tunit = unit and (unit .. "target")
    if not tunit or not UnitExists(tunit) then return "" end
    return ns.ResolveUnitNickname(tunit)
end
oUF.Tags.Events["eui-tgtname"] = "UNIT_TARGET PLAYER_TARGET_CHANGED UNIT_NAME_UPDATE"

local optionsFrame
local optionsCategoryID
_G.EllesmereUF_StylesRegistered = _G.EllesmereUF_StylesRegistered or false

local unitSettingsMap
local function GetSettingsForUnit(unit)
    if not unitSettingsMap then
        unitSettingsMap = {
            player = db.profile.player,
            target = db.profile.target,
            targettarget = db.profile.targettarget,
            pet = db.profile.pet,
            focus = db.profile.focus,
            focustarget = db.profile.focustarget,
        }
        for i = 1, 5 do
            unitSettingsMap["boss" .. i] = db.profile.boss
        end
    end
    return unitSettingsMap[unit] or db.profile.player
end

-- Per-unit frame source resolver. Returns one of:
--   "eui"      -- spawn the EllesmereUI skinned frame (default)
--   "blizzard" -- do not spawn; leave Blizzard's default frame in place
--   "hidden"   -- do not spawn; actively disable Blizzard's frame too
-- "hidden" has the highest precedence so a legacy disabled frame
-- (enabledFrames[unit] == false, e.g. Visibility set to "never" or an
-- "Enable X Frame" toggle turned off) keeps meaning "no frame at all".
function ns.GetUnitFrameSource(unit)
    if not db or not db.profile then return "eui" end
    if db.profile.enabledFrames[unit] == false then return "hidden" end
    local fs = db.profile.frameSource and db.profile.frameSource[unit]
    if fs == "blizzard" then
        -- Target-of-target / focus-target have no standalone Blizzard frame -- the
        -- native one is a child of the parent TargetFrame/FocusFrame and only lives
        -- while that parent frame does. So "blizzard" is honoured for them ONLY when
        -- the parent (target/focus) is itself on Blizzard's frame; otherwise there
        -- is no live native child to show, so fall back to the EllesmereUI frame.
        if unit == "targettarget" then
            return ns.GetUnitFrameSource("target") == "blizzard" and "blizzard" or "eui"
        elseif unit == "focustarget" then
            return ns.GetUnitFrameSource("focus") == "blizzard" and "blizzard" or "eui"
        end
        return "blizzard"
    end
    return "eui"
end

-- Writes a unit's frame source, keeping the legacy enabledFrames flag and the
-- per-unit "never" visibility in sync so all existing readers stay correct.
-- Switching source only takes full effect after a UI reload (oUF permanently
-- disables the Blizzard frame at spawn, and secure frames cannot be created or
-- torn down in combat), so callers should also prompt a reload.
function ns.SetUnitFrameSource(unit, source)
    if not db or not db.profile then return end
    db.profile.frameSource = db.profile.frameSource or {}
    db.profile.frameSource[unit] = source
    db.profile.enabledFrames[unit] = (source ~= "hidden")
    -- Keep the player/target/focus "Visibility" dropdown ("never") consistent
    -- with the hidden state; other units have no barVisibility key.
    local s = db.profile[unit]
    if s and s.barVisibility ~= nil then
        if source == "hidden" then
            -- Remember the visible mode so a hidden -> visible round trip does
            -- not lose an "in_combat"/"mouseover"/etc. preference. A
            -- multi-selection set is stashed the same way -- it must also be
            -- cleared, or it would stay authoritative over the forced
            -- "never" and the frame would keep showing.
            if type(s.visibilityModes) == "table" and next(s.visibilityModes) then
                s._preHiddenVisibilityModes = s.visibilityModes
            end
            s.visibilityModes = nil
            if s.barVisibility ~= "never" then
                s._preHiddenBarVisibility = s.barVisibility
            end
            s.barVisibility = "never"
        elseif s.barVisibility == "never" then
            s.barVisibility = s._preHiddenBarVisibility or "always"
            s._preHiddenBarVisibility = nil
            s.visibilityModes = s._preHiddenVisibilityModes
            s._preHiddenVisibilityModes = nil
        end
    end
end

-- Cast-bar icon "part of the bar" resolver. Returns true when the spell icon
-- should be counted inside the cast bar's width (icon sits inside the footprint
-- and the fill is inset to its right -- the same way the Resource Bars cast bar
-- works). False = legacy behavior (icon placed to the left, outside the width).
-- Requires the icon to actually be shown; a hidden icon is never "in width".
local function CastIconInWidth(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return true end
    if unit == "player" then
        return s.showPlayerCastIcon ~= false and s.playerCastbarIconInWidth ~= false
    end
    return s.showCastIcon ~= false and s.castbarIconInWidth ~= false
end

-- Whether the cast spell icon sits on the RIGHT of the bar instead of the
-- default left. Independent of "part of the bar"; defaults off (left).
local function CastIconOnRight(unit, s)
    s = s or GetSettingsForUnit(unit)
    if not s then return false end
    if unit == "player" then
        return s.playerCastbarIconRight == true
    end
    return s.castbarIconRight == true
end

-- Anchor the cast spell icon and inset the fill based on whether the icon is
-- part of the bar width. inWidth=true -> icon at the bar's left edge, fill
-- inset by the icon width (castbarBg becomes the full footprint, so unlock
-- mode / width matching count the icon for free). inWidth=false -> icon hangs
-- to the left of the bar (outside its width), fill fills the whole bar.
--
-- The icon HEIGHT is anchored to the bar background's top AND bottom, so it
-- always equals the bar height exactly. A live bg:GetHeight() read was
-- unreliable during initial frame creation/login (the bar background was not
-- yet at its final height/scale), so the icon was sized wrong -- usually too
-- big -- until a later refresh happened to re-run with the correct value. With
-- top+bottom anchored, height tracks the bar no matter the layout timing.
-- iconH is the configured cast bar height (castbarHeight / playerCastbarHeight),
-- used only for the square WIDTH and the matching fill inset so those are
-- deterministic too; it falls back to bg:GetHeight() when omitted.
local function LayoutCastbarIcon(castbar, inWidth, iconH, onRight)
    if not castbar then return end
    local bg = castbar:GetParent()
    if not bg then return end
    local side = iconH or bg:GetHeight()
    local iconFrame = castbar._iconFrame
    if iconFrame then
        iconFrame:ClearAllPoints()
        if inWidth then
            -- Icon inside the footprint, flush with the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPRIGHT", 0, 0)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
            else
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPLEFT", 0, 0)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
            end
        else
            -- Icon hangs outside the bar, off the chosen edge.
            if onRight then
                PP.Point(iconFrame, "TOPLEFT", bg, "TOPRIGHT", 0, 0)
                PP.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMRIGHT", 0, 0)
            else
                PP.Point(iconFrame, "TOPRIGHT", bg, "TOPLEFT", 0, 0)
                PP.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMLEFT", 0, 0)
            end
        end
        iconFrame:SetWidth(side)
    end
    castbar:ClearAllPoints()
    if inWidth and onRight then
        -- Bar occupies the left of the footprint; icon takes the right edge.
        PP.Point(castbar, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        PP.Point(castbar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", -side, 0)
    else
        PP.Point(castbar, "TOPLEFT", bg, "TOPLEFT", inWidth and side or 0, 0)
        PP.Point(castbar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    end
end

-- Returns the donor settings table for mini frames (focus > target > player)
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
local function AuraMaxCols(growth, maxCount, maxPerRow)
    -- An explicit "Max Per Row" caps each row at that many icons and wraps the
    -- rest into new rows. It only overrides the growth-based default when it
    -- actually constrains below the total count; at or above the count it is a
    -- no-op so the growth direction's natural single-row/column layout stays.
    if maxPerRow and maxPerRow >= 1 and maxPerRow < (maxCount or 1) then
        return maxPerRow
    end
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

    -- initialAnchor: first icon always starts at the anchor corner. Left/Right
    -- use the vertical-CENTER side point (not a bottom corner) so the row stays
    -- centered on the frame's side and grows up/down evenly when the icon size
    -- changes -- matching the in-game boss preview.
    local iaMap = {
        topleft     = "BOTTOMLEFT",
        topright    = "BOTTOMRIGHT",
        bottomleft  = "TOPLEFT",
        bottomright = "TOPRIGHT",
        left        = "RIGHT",
        right       = "LEFT",
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

-- Boss "Simple Debuff Display" mode: "none" | "left" | "right".
-- Tolerates legacy boolean values (true/nil = "left", false = "none") so existing
-- and imported profiles read correctly without a migration pass. "left"/"right"
-- both force the frame-height-matched single column; only the side differs.
function ns.GetBossSimpleDebuffMode(s)
    local v = s and s.simpleDebuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == false then return "none" end
    return "left"  -- nil or legacy true
end

-- Boss Simple Debuff Display X/Y offsets. Returns the dedicated
-- simpleDebuffOffsetX/Y if set, otherwise falls back to the regular debuff
-- offsets so existing users' debuff offsets carry over as the defaults for
-- simple mode (zero-migration view; import-safe -- no migration flag to skip).
-- Once the user edits the Simple Debuff Display cog, the dedicated keys take
-- over and the two offsets are fully independent.
function ns.GetBossSimpleDebuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleDebuffOffsetX
    if x == nil then x = s.debuffOffsetX or 0 end
    local y = s.simpleDebuffOffsetY
    if y == nil then y = s.debuffOffsetY or 0 end
    return x, y
end

-- Boss "Simple Buff Display" mode: "none" | "left" | "right". Brand-new feature
-- so it defaults OFF (nil/false/unknown -> "none"); a stray legacy boolean true
-- is tolerated as "left" for symmetry with the debuff resolver.
function ns.GetBossSimpleBuffMode(s)
    local v = s and s.simpleBuffs
    if v == "none" or v == "left" or v == "right" then return v end
    if v == true then return "left" end
    return "none"
end

-- Boss Simple Buff Display X/Y offsets. Mirrors ns.GetBossSimpleDebuffOffset:
-- returns simpleBuffOffsetX/Y if set, otherwise falls back to the regular buff
-- offsets so existing users' buff offsets carry over as the simple defaults
-- (zero-migration view; import-safe). Independent once the user edits the cog.
function ns.GetBossSimpleBuffOffset(s)
    if not s then return 0, 0 end
    local x = s.simpleBuffOffsetX
    if x == nil then x = s.buffOffsetX or 0 end
    local y = s.simpleBuffOffsetY
    if y == nil then y = s.buffOffsetY or 0 end
    return x, y
end

-- Boss aura icon spacing, in PHYSICAL pixels. Simple display modes use their
-- own dedicated keys (simpleBuffSpacing/simpleDebuffSpacing); regular buffs and
-- debuffs use buffSpacing/debuffSpacing. A brand-new setting with no legacy
-- equivalent, so every variant defaults to 1 independently (no offset-style
-- fallback). Callers convert the returned pixel count to coordinate space with
-- PP.FromPixels so the gap between icons is physical-pixel-perfect at any scale.
-- (0 and negative values are truthy in Lua, so `or 1` only fills nil.)
function ns.GetBossBuffSpacing(s, simpleOn)
    if simpleOn then return (s and s.simpleBuffSpacing) or 1 end
    return (s and s.buffSpacing) or 1
end
function ns.GetBossDebuffSpacing(s, simpleOn)
    if simpleOn then return (s and s.simpleDebuffSpacing) or 1 end
    return (s and s.debuffSpacing) or 1
end

local function GetPlayerTargetHealthTag(unit)
    local tbl = (unit == "target") and db.profile.target or db.profile.player
    local display = tbl.healthDisplay or "both"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "perhp" then
        return "[eui-perhp]%"
    else
        return "[curhpshort] | [eui-perhp]%"
    end
end

local function GetFocusHealthTag()
    local display = db.profile.focus.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [eui-perhp]%"
    else
        return "[eui-perhp]%"
    end
end

local function GetBossHealthTag()
    local display = db.profile.boss.healthDisplay or "perhp"
    if display == "curhpshort" then
        return "[curhpshort]"
    elseif display == "both" then
        return "[curhpshort] | [eui-perhp]%"
    else
        return "[eui-perhp]%"
    end
end

-- Build a truncated name tag for the given settings prefix (e.g. "leftText", "btbLeft").
local function BuildShortNameTag(prefix, settings)
    local len = settings[prefix .. "ShortNameLength"] or 0
    if len <= 0 then return "[eui-name]" end
    local ellipsis = settings[prefix .. "ShortNameEllipsis"] ~= false and "1" or "0"
    return "[eui-name(" .. len .. "," .. ellipsis .. ")]"
end

-- Build the per-slot "Name > Target" indicator tag. The separator string is
-- hex-encoded per byte so any user-typed character (commas, parens, multibyte
-- symbols) survives the tag brackets; the indicator color rides as "class" or
-- a fixed rrggbb hex (default white).
local function BuildTgtSepTag(prefix, settings)
    local sep = settings[prefix .. "TargetSep"]
    if type(sep) ~= "string" or sep == "" then sep = ">" end
    local hex = sep:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)
    local col
    if settings[prefix .. "TargetSepClassColor"] then
        col = "class"
    else
        local c = settings[prefix .. "TargetSepColor"]
        if type(c) == "table" then
            col = string.format("%02x%02x%02x",
                math.floor((c.r or 1) * 255 + 0.5),
                math.floor((c.g or 1) * 255 + 0.5),
                math.floor((c.b or 1) * 255 + 0.5))
        else
            col = "ffffff"
        end
    end
    return "[eui-tgtsep(" .. hex .. "," .. col .. ")]"
end

-- Resolve a leftTextContent / rightTextContent value to an oUF tag string.
-- content: "name", "both", "curhpshort", "perhp", "perhpnosign", "perhpnum", "none"
local function ContentToTag(content, prefix, settings)
    if content == "name" then return BuildShortNameTag(prefix, settings)
    elseif content == "nametotarget" then
        return BuildShortNameTag(prefix, settings)
            .. BuildTgtSepTag(prefix, settings) .. "[eui-tgtcol][eui-tgtname]"
    elseif content == "both" then return "[curhpshort] | [eui-perhp]%"
    elseif content == "bothdash" then return "[curhpshort] - [eui-perhp]%"
    elseif content == "perhpnum" then return "[eui-perhp]% | [curhpshort]"
    elseif content == "perhpnumdash" then return "[eui-perhp]% - [curhpshort]"
    elseif content == "curhpshort" then return "[curhpshort]"
    elseif content == "perhp" then return "[eui-perhp]%"
    elseif content == "perhpnosign" then return "[perhpnosign]"
    -- Power content uses the secret-safe eui- power tags (identical to the power
    -- bar text). The stock [curpp]/[perpp] tags read raw UnitPower, which is a
    -- secret value for enemies and bugs out the fontstring on target change; the
    -- eui- tags resolve power type from the cache and stay display-safe.
    elseif content == "perpp" then return "[eui-perpp]%"
    elseif content == "curpp" then return "[eui-curpp]"
    elseif content == "curhp_curpp" then return "[curhpshort] | [eui-curpp]"
    elseif content == "perhp_perpp" then return "[eui-perhp]% | [eui-perpp]%"
    elseif content == "absorb" then return "[eui-absorb]"
    elseif content == "absorbshort" then return "[eui-absorbshort]"
    elseif content == "healabsorb" then return "[eui-healabsorb]"
    elseif content == "healabsorbshort" then return "[eui-healabsorbshort]"
    elseif content == "group" then return "[group]"
    else return nil end
end

-- Estimate pixel width of a text content type for name truncation.
-- Flat pixel assumptions matching the nameplate system.
local UF_TEXT_PADDING = 10
local ufTextWidths = {
    both        = 75,  -- "132 K | 86%"
    bothdash    = 75,  -- "132 K - 86%"
    perhpnum    = 75,  -- "86% | 132 K"
    perhpnumdash = 75, -- "86% - 132 K"
    curhpshort  = 38,  -- "132 K"
    perhp       = 38,  -- "86%"
    perhpnosign = 30,  -- "86"
    perpp       = 38,  -- "86%"
    curpp       = 38,  -- "132"
    curhp_curpp = 75,  -- "132 K | 132"
    perhp_perpp = 75,  -- "86% | 86%"
    absorb      = 38,  -- "12.3 K"
}
local function EstimateUFTextWidth(content)
    return (ufTextWidths[content] or 0) + UF_TEXT_PADDING
end

-- Apply class color to a FontString based on the unit
local function ApplyClassColor(fs, unit, useClassColor, customR, customG, customB)
    if not fs then return end
    if useClassColor and unit then
        -- Class color for players (and AI party members); reaction color for NPCs so
        -- hostiles are red, neutral yellow, friendly green, matching the health bar
        -- and the custom Enemy Colors override. Shared with the eui-tgtname tag
        -- via ns.ResolveUnitNameColor so the two color identically.
        local r, g, b = ns.ResolveUnitNameColor(unit)
        if r then fs:SetTextColor(r, g, b); return end
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
                    -- Prefer oUF's reaction table (carries the custom Enemy Colors
                    -- override) so the border matches the health bar; fall back to
                    -- the Blizzard default.
                    local c = (oUF.colors and oUF.colors.reaction and oUF.colors.reaction[reaction])
                        or FACTION_BAR_COLORS[reaction]
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
    local maskPath = shape ~= "none" and PORTRAIT_MASKS[shape] or nil
    if shape == "none" then
        -- "None": remove mask, border, and background
        if backdrop._bg then backdrop._bg:Hide() end
        if backdrop._shapeMask then
            if backdrop._2d then pcall(backdrop._2d.RemoveMaskTexture, backdrop._2d, backdrop._shapeMask) end
            if backdrop._class then pcall(backdrop._class.RemoveMaskTexture, backdrop._class, backdrop._shapeMask) end
            if backdrop._bg then pcall(backdrop._bg.RemoveMaskTexture, backdrop._bg, backdrop._shapeMask) end
            backdrop._shapeMask:Hide()
        end
        if backdrop._shapeBorderTex then backdrop._shapeBorderTex:Hide() end
        if backdrop._sqBorderTexs then
            for _, t in ipairs(backdrop._sqBorderTexs) do t:Hide() end
        end
        -- Reset content to fill backdrop
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
    if backdrop._bg then backdrop._bg:Show() end
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
    btb._isDetached = isDetached

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
        local lt = ContentToTag(lc, "btbLeft", settings)
        local rt = ContentToTag(rc, "btbRight", settings)
        local ct = ContentToTag(cc, "btbCenter", settings)
        if leftFS._curTag then frame:Untag(leftFS); leftFS._curTag = nil end
        if rightFS._curTag then frame:Untag(rightFS); rightFS._curTag = nil end
        if centerFS._curTag then frame:Untag(centerFS); centerFS._curTag = nil end
        if lt then frame:Tag(leftFS, lt); leftFS._curTag = lt end
        if rt then frame:Tag(rightFS, rt); rightFS._curTag = rt end
        if ct then frame:Tag(centerFS, ct); centerFS._curTag = ct end
        if frame.UpdateTags then frame:UpdateTags() end
    end

    -- Power-color override for power-content text. Mirrors the power bar text
    -- logic: the unit's own power type, white fallback when the token can't
    -- resolve. ApplyBTBPowerColors re-applies all three slots; it runs at layout
    -- time AND continuously from the power element's PostUpdateColor, so the color
    -- survives tag updates and power-type changes (identical to the power bar text).
    -- The per-slot early-out (no power-color flag) keeps it ~free when unused.
    local function ApplyBTBPowerColor(fs, contentKey, usePowerColor)
        if not fs or not usePowerColor then return end
        if contentKey == "perpp" or contentKey == "curpp" or contentKey == "curhp_curpp" or contentKey == "perhp_perpp" then
            -- Secret-safe per-unit power color: player resolves via the clean
            -- string token (identical to before); non-player units recover it
            -- from the clean integer power type instead of falling back to white.
            local r, g, b = EllesmereUI.ResolveUnitPowerColor(unit)
            if r then fs:SetTextColor(r, g, b)
            else fs:SetTextColor(1, 1, 1) end
        end
    end
    local function ApplyBTBPowerColors(s)
        ApplyBTBPowerColor(leftFS, s.btbLeftContent or "none", s.btbLeftPowerColor)
        ApplyBTBPowerColor(rightFS, s.btbRightContent or "none", s.btbRightPowerColor)
        ApplyBTBPowerColor(centerFS, s.btbCenterContent or "none", s.btbCenterPowerColor)
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
        -- Power color: applied after class color; also re-applied continuously
        -- from the power element's PostUpdateColor (btb._applyBTBPowerColors) so it
        -- survives tag updates / power-type changes, identical to the power bar text.
        ApplyBTBPowerColors(s)
    end

    ApplyBTBTextTags(
        settings.btbLeftContent or "none",
        settings.btbRightContent or "none",
        settings.btbCenterContent or "none"
    )
    ApplyBTBTextPositions(settings)

    btb._applyBTBTextTags = ApplyBTBTextTags
    btb._applyBTBTextPositions = ApplyBTBTextPositions
    btb._applyBTBPowerColors = ApplyBTBPowerColors

    -- Class icon overlay -- on a high-level frame so it renders above the border
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

-- SetFrameMovable removed -- positioning is now handled by Unlock Mode

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

local function ReparentBarsToClip(frame, powerPosition, settings)
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
        -- SetParent resets frame level, so re-assert after every reparent.
        if detached then
            -- Detached bars are reparented onto `frame` itself (not the bar
            -- clip), which also holds the border (frame:GetFrameLevel() + 10,
            -- see CreateUnifiedBorder/UpdatePowerBorder). hpLevel + 2 (below)
            -- sits well under that and let the border render over a detached
            -- power bar dragged onto its edge -- match CreatePowerBar's own
            -- detached offset instead so this stays consistently above it.
            frame.Power:SetFrameLevel(frame:GetFrameLevel() + 12)
        else
            -- Power bar must render above absorb overlay (health level + 1).
            local hpLevel = frame.Health and frame.Health:GetFrameLevel() or clip:GetFrameLevel()
            frame.Power:SetFrameLevel(hpLevel + 2)
        end
        -- Reparent/SetFrameLevel leave the border and text overlay at stale
        -- absolute levels; re-apply after the final level is set.
        if settings then
            ns.UpdatePowerBorder(frame.Power, settings)
        end
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
    -- Simple frames (pet/tot/focustarget) have no power bar -- skip power height
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
    local pSideSnap = settings.portraitSide or "left"
    local isInsideSnap = pSideSnap == "insideleft" or pSideSnap == "insideright" or pSideSnap == "insidecenter"
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached and not isInsideSnap then pSizeAdj = pSizeAdj + 10 end
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
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and not isInsideSnap then
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
            -- Use the settings already resolved from this function's unit
            -- parameter, NOT frame.unit: boss preview swaps frame.unit to
            -- "player", which has no castbarWidth and made this trim eat the
            -- boss castbar's custom width while previewing.
            local cbW = castbarBg:GetWidth()
            local hasCustomW = (settings.castbarWidth or 0) > 0
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

-- ToggleLock removed -- positioning is now handled by Unlock Mode

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

-- ShowFakeFrames / HideFakeFrames removed -- Unlock Mode handles all positioning

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
    health:SetReverseFill(settings.healthReverseFill and true or false)
    ApplyDarkTheme(health)

    -- Smooth bar interpolation (opt-in; defaults off)
    if settings.smoothBars then
        health.smoothing = Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
    end

    return health
end

-- Shield texture path. DO NOT change this path -- users without the
-- top-level symlink have been corrected; this is the path that resolves.
local ABSORB_SHIELD_TEX = "Interface\\AddOns\\EllesmereUIUnitFrames\\Media\\shield.tga"

-- Absorb bar style textures and alpha values. "striped" and "blizzard"
-- textures will be added to Media/ when the user uploads them.
local ABSORB_STYLE_TEX = {
    striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
    stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
    clean           = "Interface\\Buttons\\WHITE8X8",
    blizzard        = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
    largeOutlinedStripes  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-left.png",
    largeOutlinedStripesR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-right.png",
    largeStripes          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-left.png",
    largeStripesR         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-right.png",
}
local ABSORB_STYLE_ALPHA = {
    striped         = 0.8,
    stripedReversed = 0.8,
    clean           = 0.3,
    blizzard        = 0.8,
}

-- Resolve an absorb-style key to a texture path. Built-in styles come from
-- ABSORB_STYLE_TEX; "sm:" SharedMedia keys (shared with the Bar Texture
-- dropdown, appended into healthBarTextures by AppendSharedMediaTextures) fall
-- through to the health-bar texture lookup. Used by both the live render
-- (ApplyAbsorbStyle / ApplyHealAbsorbStyle) and the options preview, so a saved
-- SM key paints identically everywhere.
function ns.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-- Effective absorb opacity: the per-unit absorbOpacity once set, otherwise the
-- pre-split behavior (clean uses absorbCleanAlpha, other styles the fixed 0.8).
-- Read-time fallback so existing user settings render identically with no
-- migration; the options slider shows the same effective value.
local function GetAbsorbOpacity(style, settings)
    if settings and settings.absorbOpacity then
        return settings.absorbOpacity / 100
    end
    if style == "clean" and settings then
        return (settings.absorbCleanAlpha or 30) / 100
    end
    return ABSORB_STYLE_ALPHA[style] or 0.8
end

local function ApplyAbsorbStyle(absorbBar, style, settings)
    if not absorbBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, ABSORB_SHIELD_TEX)
    local alpha = GetAbsorbOpacity(style, settings)
    local ac = (settings and settings.absorbColor) or { r = 1, g = 1, b = 1 }
    -- striped-5-reversed.png is a repeating tile (the striped3 shield texture
    -- is a stretch texture; do not change how it renders)
    local tiled = (style == "stripedReversed" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local mask = absorbBar._absorbMask
    absorbBar:SetStatusBarTexture(tex)
    absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
    local fill = absorbBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 1)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
    end
    local fw = absorbBar._forward
    if fw then
        fw:SetStatusBarTexture(tex)
        fw:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
        local fwFill = fw:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            fwFill:SetHorizTile(tiled)
            fwFill:SetVertTile(tiled)
            if mask then fwFill:AddMaskTexture(mask) end
        end
    end
end

-- Heal absorb styling (mirrors the raid frames Absorbs section). Defaults
-- reproduce the pre-split hardcoded look: clean white8x8, red, 0.65 alpha.
local function ApplyHealAbsorbStyle(haBar, style, settings)
    if not haBar then return end
    local tex = ns.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = ((settings and settings.healAbsorbOpacity) or 65) / 100
    local hc = (settings and settings.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
    -- The "Large Outlined Stripes" styles are pre-colored; render them untinted.
    if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then hc = { r = 1, g = 1, b = 1 } end
    local tiled = (style == "stripedReversed" or style == "largeStripes" or style == "largeStripesR" or style == "largeOutlinedStripes" or style == "largeOutlinedStripesR")
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(tex)
    haBar:SetStatusBarColor(hc.r, hc.g, hc.b, alpha)
    local fill = haBar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK", 2)
        fill:SetHorizTile(tiled)
        fill:SetVertTile(tiled)
        if mask then fill:AddMaskTexture(mask) end
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

    ab._isReversed = isReversed and true or false

    -- Placement settings (mirror the raid frames Absorbs section):
    --   overlay = backfill into the filled health from the HP edge (default)
    --   right   = full bar, fill from the frame's right edge
    --   left    = full bar, fill from the frame's left edge
    local s = GetSettingsForUnit(frame.unit)
    local absorbMode = (s and s.absorbEdgeMode) or "overlay"
    local healMode = (s and s.healAbsorbEdgeMode) or "overlay"

    curClip:ClearAllPoints()
    missClip:ClearAllPoints()
    ab:ClearAllPoints()
    fw:ClearAllPoints()

    -- missClip + forward bar always use the overlay layout; in the edge modes
    -- the full-bar backfill shows the whole absorb and the Override hides fw.
    if isReversed then
        missClip:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT", 1, 0)
        missClip:SetPoint("BOTTOMLEFT",  hpBar, "BOTTOMLEFT", 0, 0)
        fw:SetReverseFill(true)
        fw:SetPoint("TOPRIGHT",    hpTex, "TOPLEFT",    0, 0)
        fw:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
    else
        missClip:SetPoint("TOPLEFT",     hpTex, "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        fw:SetReverseFill(false)
        fw:SetPoint("TOPLEFT",    hpTex, "TOPRIGHT",    0, 0)
        fw:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
    end

    -- Shield absorb placement
    if absorbMode == "right" or absorbMode == "left" then
        -- Full bar: clip covers the whole health bar, backfill anchors to the
        -- chosen frame edge (absolute, independent of reverse fill).
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        if absorbMode == "left" then
            ab:SetReverseFill(false)
            ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            ab:SetReverseFill(true)
            ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        end
    elseif isReversed then
        curClip:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT", 0, 0)
        curClip:SetPoint("BOTTOMLEFT",  hpTex, "BOTTOMLEFT", 0, 0)
        ab:SetReverseFill(false)
        ab:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
        ab:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
    else
        curClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",  0, 0)
        curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
        ab:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
    end

    -- Heal absorb placement (independent of shield absorb). The heal absorb
    -- has its OWN clip frame (ab._healClip) so right/left span the full bar
    -- (filled + missing health) while overlay stays clipped to filled health.
    local ha = ab._healAbsorb
    local healClip = ab._healClip
    if healClip then
        healClip:ClearAllPoints()
        if healMode == "right" or healMode == "left" then
            healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            healClip:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        elseif isReversed then
            healClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT",   0, 0)
            healClip:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
        else
            healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT",     0, 0)
            healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
        end
    end
    if ha then
        ha:ClearAllPoints()
        if healMode == "right" then
            ha:SetReverseFill(true)
            ha:SetPoint("TOPRIGHT",    hpBar, "TOPRIGHT",    0, 0)
            ha:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        elseif healMode == "left" then
            ha:SetReverseFill(false)
            ha:SetPoint("TOPLEFT",    hpBar, "TOPLEFT",    0, 0)
            ha:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT", 0, 0)
        else
            -- Overlay (default): eat into the filled health from the HP edge,
            -- mirrored for reverse-filled health bars.
            ha:SetReverseFill(not isReversed)
            if isReversed then
                ha:SetPoint("TOPLEFT",    hpTex, "TOPLEFT",    0, 0)
                ha:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
            else
                ha:SetPoint("TOPRIGHT",    hpTex, "TOPRIGHT",    0, 0)
                ha:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
end

-- Absorb / Heal Absorb strip-bar position resolvers + layout (mirrors Raid
-- Frames). On ns so the options-panel preview can reuse the layout.
ns.UF_GetAbsorbBarPos     = function(s) return (s and s.absorbBarPosition)     or "none" end
ns.UF_GetHealAbsorbBarPos = function(s) return (s and s.healAbsorbBarPosition) or "none" end

-- Anchor/orient a strip bar (Absorb Bar or Heal Absorb Bar). "above*" sit on top
-- of the health bar; "top*" sit inside at its top, drawn just above the absorb
-- texture; "belowAbsorb" (heal bar only) sits flush below the Absorb Bar's bottom
-- edge, derived from the Absorb Bar's POSITION (not its live visibility, so it
-- never shifts up). "*Right" fills from the right edge. `absorbLevel` is the
-- absorb-overlay frame level (inside strips render at +1 above it).
ns.UF_ApplyStripBarLayout = function(stripBar, hp, position, height, absorbLevel, absorbPos, absorbHeight)
    if not stripBar or not hp then return end
    stripBar:ClearAllPoints()
    stripBar:SetHeight(PP.Scale(height or 4))
    local insideLevel = (absorbLevel or (hp:GetFrameLevel() + 1)) + 1
    if position == "belowAbsorb" then
        absorbPos = absorbPos or "none"
        local yOff = 0
        if absorbPos == "topRight" or absorbPos == "topLeft" then
            yOff = -PP.Scale(absorbHeight or 4)
        end
        stripBar:SetReverseFill(absorbPos ~= "aboveLeft" and absorbPos ~= "topLeft")
        stripBar:SetPoint("TOPLEFT",  hp, "TOPLEFT",  0, yOff)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, yOff)
        stripBar:SetFrameLevel(insideLevel)
    elseif position == "topRight" or position == "topLeft" then
        stripBar:SetReverseFill(position == "topRight")
        stripBar:SetPoint("TOPLEFT",  hp, "TOPLEFT",  0, 0)
        stripBar:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(insideLevel)
    else
        stripBar:SetReverseFill(position == "aboveRight")
        stripBar:SetPoint("BOTTOMLEFT",  hp, "TOPLEFT",  0, 0)
        stripBar:SetPoint("BOTTOMRIGHT", hp, "TOPRIGHT", 0, 0)
        stripBar:SetFrameLevel(hp:GetFrameLevel() + 3)
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
    -- Reverse-fills from the health texture edge inward (eats into green).
    -- Heal absorb has its OWN clip frame (not the shield's curClip) so its
    -- placement is independent: overlay clips to the filled health, while
    -- right/left span the FULL bar (filled + missing health). Bounds are set
    -- per healAbsorbEdgeMode in UpdateAbsorbBarReverseFill.
    local healClip = CreateFrame("Frame", nil, hpBar)
    if isReversed then
        healClip:SetPoint("TOPRIGHT",   hpBar, "TOPRIGHT", 0, 0)
        healClip:SetPoint("BOTTOMLEFT", hpBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        healClip:SetPoint("TOPLEFT",     hpBar, "TOPLEFT", 0, 0)
        healClip:SetPoint("BOTTOMRIGHT", hpBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    healClip:SetClipsChildren(true)
    local healAbsorbBar = CreateFrame("StatusBar", nil, healClip)
    healAbsorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbBar._absorbMask = absorbMask
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

    -- Black backing behind the heal-absorb texture (all styles; opacity user-set
    -- via healAbsorbBgOpacity). Drawn UNDER the fill (ARTWORK sublevel 1 < the
    -- fill's 2), masked + SetAllPoints'd to the fill rect each update so it
    -- tracks the secret heal-absorb amount and collapses when there is none.
    local haBg = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.15)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbBar._bg = haBg

    -- Absorb Bar + Heal Absorb Bar: separate strips (mirrors Raid Frames), each
    -- showing the shield / heal-absorb amount at a configurable position.
    -- Parented to the frame so "above" positions can sit outside the health bar.
    -- Always created hidden; the Override drives them.
    local absorbTopBar = CreateFrame("StatusBar", nil, frame)
    absorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    absorbTopBar:SetStatusBarColor(1, 1, 1, 1)
    absorbTopBar:SetReverseFill(true)
    absorbTopBar:SetPoint("BOTTOMLEFT",  hpBar, "TOPLEFT",  0, 0)
    absorbTopBar:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, 0)
    absorbTopBar:SetHeight(4)
    absorbTopBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    absorbTopBar:Hide()

    local healAbsorbTopBar = CreateFrame("StatusBar", nil, frame)
    healAbsorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbTopBar:SetStatusBarColor(200/255, 29/255, 29/255, 1)
    healAbsorbTopBar:SetReverseFill(true)
    healAbsorbTopBar:SetPoint("BOTTOMLEFT",  hpBar, "TOPLEFT",  0, 0)
    healAbsorbTopBar:SetPoint("BOTTOMRIGHT", hpBar, "TOPRIGHT", 0, 0)
    healAbsorbTopBar:SetHeight(4)
    healAbsorbTopBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    healAbsorbTopBar:Hide()

    -- Attach extras to the main bar (backfill) so anything that references
    -- HealthPrediction.damageAbsorb can hide/show both segments together.
    backfillBar._forward      = forwardBar
    backfillBar._healAbsorb   = healAbsorbBar
    backfillBar._topBar       = absorbTopBar
    backfillBar._healTopBar   = healAbsorbTopBar
    backfillBar._hpBar        = hpBar
    backfillBar._hpCalculator = hpCalc
    backfillBar._curClip      = curClip
    backfillBar._healClip     = healClip
    backfillBar._missClip     = missClip
    backfillBar._absorbMask   = absorbMask
    backfillBar._isReversed   = isReversed

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

            -- Drive the "Absorb Short" health-text gate(s) on absorb changes: feed
            -- the raw absorb so the clip reveals/collapses, AND refresh the text in
            -- LOCKSTEP so the revealed text never flashes the stale "0" (oUF tags
            -- update on a throttled cycle, so a bare tag lags the synchronous clip
            -- reveal by a frame). Only the absorb event moves the gate. Runs before
            -- the bar-style early return so it works with the absorb BAR disabled.
            -- Secret-safe: the absorb is only fed to SetValue and AbbreviateNumbers,
            -- never compared to zero (SetText takes the same value the tag would).
            -- Each gate feeds its own value source: shield gates use total
            -- absorbs, heal gates (g._euiHealGate) use total heal absorbs. Both
            -- absorb events drive the loop; each amount is fetched lazily once.
            if self._absGate and (event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED") then
                local shieldAmt, healAmt, fsZone
                for zone, g in pairs(self._absGate) do
                    if g:IsShown() then
                        local amt
                        if g._euiHealGate then
                            if not healAmt then healAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0 end
                            amt = healAmt
                        else
                            if not shieldAmt then shieldAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0 end
                            amt = shieldAmt
                        end
                        g:SetValue(amt)
                        fsZone = fsZone or { left = self.LeftText, right = self.RightText, center = self.CenterText, extra = self.ExtraText }
                        local fs = fsZone[zone]
                        if fs then
                            local cfg = _G._EUI_AbbrevDecimalCfg
                            fs:SetText(cfg and AbbreviateNumbers(amt, cfg) or AbbreviateNumbers(amt))
                        end
                    end
                end
            end

            local element = self.HealthPrediction
            local ab = element.damageAbsorb
            if not ab then return end
            local fw   = ab._forward
            local hp   = ab._hpBar
            local calc = ab._hpCalculator
            if not hp then return end

            -- Heal absorb renders independently of the shield absorb. The
            -- shield "none" setting hides only the shield segments below; we
            -- skip the whole update only when BOTH the shield and the heal
            -- absorb are off, so unit events don't re-Show() bars ReloadFrames
            -- hid. (Heal Absorb Style defaults to "clean", so it shows even
            -- when the shield Absorb Style is "none".)
            local s = GetSettingsForUnit(updUnit)
            -- Boss frames have no absorb settings of their own: render with
            -- the TARGET frame's absorb styling (donor convention, no
            -- per-boss customization), behind the single "Show on Boss
            -- Frames" toggle in the absorb cog (nil = enabled).
            local bossAbsorbOff
            if updUnit and updUnit:match("^boss") then
                bossAbsorbOff = db.profile.boss and db.profile.boss.showAbsorbs == false
                s = db.profile.target or s
            end
            local ha = ab._healAbsorb
            local topBar = ab._topBar
            local healTopBar = ab._healTopBar
            local barPos = ns.UF_GetAbsorbBarPos(s)
            local barOn = topBar and barPos ~= "none"
            local healBarPos = ns.UF_GetHealAbsorbBarPos(s)
            local healBarOn = healTopBar and healBarPos ~= "none"
            local shieldOff = s and (not s.showPlayerAbsorb or s.showPlayerAbsorb == "none")
            local healOff = (((s and s.healAbsorbStyle) or "clean") == "none")
            if bossAbsorbOff or (shieldOff and healOff and not barOn and not healBarOn) then
                ab:Hide()
                if fw then fw:Hide() end
                if ha then ha:Hide() end
                if topBar then topBar:Hide() end
                if healTopBar then healTopBar:Hide() end
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

            -- Strip bars (mirrors Raid Frames): independent of the overlay styles.
            if topBar then
                if barOn then
                    local bc = (s and s.absorbBarColor) or { r = 1, g = 1, b = 1 }
                    local bh = (s and s.absorbBarHeight) or 4
                    -- Re-layout only when position/height changes (no per-update SetPoint churn).
                    if topBar._lpPos ~= barPos or topBar._lpH ~= bh then
                        topBar._lpPos = barPos; topBar._lpH = bh
                        ns.UF_ApplyStripBarLayout(topBar, hp, barPos, bh, ab:GetFrameLevel())
                    end
                    topBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                    topBar:SetMinMaxValues(0, maxHealth)
                    topBar:SetValue(absorbAmt)
                    topBar:Show()
                else
                    topBar:Hide()
                end
            end
            if healTopBar then
                if healBarOn then
                    local hbc = (s and s.healAbsorbBarColor) or { r = 200/255, g = 29/255, b = 29/255 }
                    local hbh = (s and s.healAbsorbBarHeight) or 4
                    local abh = (s and s.absorbBarHeight) or 4
                    -- Re-layout only when its or the Absorb Bar's position/height changes.
                    if healTopBar._lpPos ~= healBarPos or healTopBar._lpH ~= hbh
                       or healTopBar._lpAP ~= barPos or healTopBar._lpAH ~= abh then
                        healTopBar._lpPos = healBarPos; healTopBar._lpH = hbh
                        healTopBar._lpAP = barPos; healTopBar._lpAH = abh
                        ns.UF_ApplyStripBarLayout(healTopBar, hp, healBarPos, hbh, ab:GetFrameLevel(), barPos, abh)
                    end
                    healTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                    healTopBar:SetMinMaxValues(0, maxHealth)
                    healTopBar:SetValue((UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0)
                    healTopBar:Show()
                else
                    healTopBar:Hide()
                end
            end

            -- Re-anchor when the placement settings change. The key starts
            -- nil, so this also applies the saved placement on first update.
            local absorbMode = (s and s.absorbEdgeMode) or "overlay"
            local edgeKey = absorbMode .. ":" .. ((s and s.healAbsorbEdgeMode) or "overlay")
            if ab._lastEdgeKey ~= edgeKey then
                ab._lastEdgeKey = edgeKey
                UpdateAbsorbBarReverseFill(self, ab._isReversed)
            end

            -- Shield (damage) absorb segments render only when enabled. When
            -- the shield style is "none" we hide them and fall through to the
            -- heal absorb below (which is independent of the shield).
            if shieldOff then
                ab:Hide()
                if fw then fw:Hide() end
            else
                -- Re-apply absorb style only when the style setting changes
                -- (not on every health event). Calling SetStatusBarTexture on
                -- every update causes the bar to flash visible even at zero absorb.
                -- Opacity/color edits re-apply via ReloadFrames' direct call.
                local absStyle = s and s.showPlayerAbsorb
                if absStyle and absStyle ~= "none" and ab._lastAbsStyle ~= absStyle then
                    ab._lastAbsStyle = absStyle
                    ApplyAbsorbStyle(ab, absStyle, s)
                end

                -- Show Overshield (opt-in, default ON). The "overshield" is the
                -- absorb that exceeds the empty health and backfills over current
                -- health -- drawn by the backfill bar (ab), which is clipped to the
                -- filled region. When the toggle is OFF (overlay mode only) we feed
                -- the backfill 0 so only the empty health fills; the forward bar
                -- (clipped to the missing-health region) still caps at the right
                -- edge. Right/left edge modes draw the WHOLE absorb through ab (fw
                -- hidden below), so they are left untouched. ON = byte-identical.
                local overshieldOn = (not s) or s.showOvershield ~= false
                local abValue = absorbAmt
                if not overshieldOn and absorbMode == "overlay" then abValue = 0 end

                -- Both bars get the raw absorb value and the normal maxHealth.
                -- The clip frames do the "min(absorb, curHealth)" and
                -- "max(0, absorb - curHealth)" math visually so we never need
                -- Lua arithmetic on the (possibly secret) absorb value.
                ab:SetMinMaxValues(0, maxHealth)
                ab:SetValue(abValue)
                ab:Show()

                if fw then
                    fw:SetMinMaxValues(0, maxHealth)
                    fw:SetValue(absorbAmt)
                    fw:Show()
                    -- Edge modes: the full-bar backfill shows the whole absorb,
                    -- so the overlay-only forward bar is not needed.
                    if absorbMode ~= "overlay" then fw:Hide() end
                end
            end

            -- Heal absorb: overlay eating into filled health.
            -- The value can be a secret number in 12.0+, so never compare
            -- it in Lua. Feed it directly to StatusBar:SetValue and let the
            -- bar render zero width when the value is 0.
            if ha then
                local haStyle = (s and s.healAbsorbStyle) or "clean"
                if haStyle == "none" then
                    ha:Hide()
                else
                    local hc = (s and s.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
                    local haKey = haStyle .. ((s and s.healAbsorbOpacity) or 65) .. hc.r .. hc.g .. hc.b
                    if ha._lastHaKey ~= haKey then
                        ha._lastHaKey = haKey
                        ApplyHealAbsorbStyle(ha, haStyle, s)
                    end
                    local healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit) or 0
                    ha:SetWidth(hpW); ha:SetHeight(hpH)
                    ha:SetMinMaxValues(0, maxHealth)
                    ha:SetValue(healAbsorbAmt)
                    ha:Show()
                    -- Black backing: track the heal-absorb fill rect, opacity from settings.
                    local hbg = ha._bg
                    if hbg then
                        hbg:SetColorTexture(0, 0, 0, ((s and s.healAbsorbBgOpacity) or 15) / 100)
                        hbg:SetAllPoints(ha:GetStatusBarTexture())
                        hbg:Show()
                    end
                end
            end
        end,
    }

    return backfillBar
end

-- Detached power bar border: create lazily, then restyle/show/hide from the
-- current settings. Lazy creation is what lets a bar switched to a detached
-- position (or a Border Size raised from 0) gain its border live -- the old
-- create-only-at-spawn path needed a /reload. Shown only while the position is
-- detached AND Border Size > 0. Shared by the creation path and the player/
-- target/focus refresh branches (the target branch previously tested a local
-- that only existed in the player branch, so its border was force-hidden on
-- every refresh; focus had no refresh at all). On ns (not a new file-scope
-- local) to respect the Lua 5.1 200-local ceiling.
function ns.UpdatePowerBorder(power, settings)
    if not power or not settings then return end
    local pos = settings.powerPosition or "below"
    local isDet = (pos == "detached_top" or pos == "detached_bottom")
    local size = settings.powerBorderSize or 0
    local border = power._pbBorder
    if not border then
        -- Nothing to render and nothing to hide: stay lazy.
        if not (isDet and size > 0) then return end
        border = CreateFrame("Frame", nil, power)
        PP.Point(border, "TOPLEFT", power, "TOPLEFT", 0, 0)
        PP.Point(border, "BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
        power._pbBorder = border
    end
    local c = settings.powerBorderColor or { r = 0, g = 0, b = 0 }
    EllesmereUI.ApplyBorderStyle(border, size, c.r, c.g, c.b,
        settings.powerBorderAlpha or 1, settings.powerBorderStyle or "solid",
        settings.powerBorderOffsetX, settings.powerBorderOffsetY,
        settings.powerBorderShiftX, settings.powerBorderShiftY, "unitframes", size)
    local borderLevel = settings.powerBorderBehind
        and math.max(0, power:GetFrameLevel() - 1) or (power:GetFrameLevel() + 5)
    border:SetFrameLevel(borderLevel)
    local showBorder = isDet and size > 0
    if showBorder then border:Show() else border:Hide() end

    -- Power text overlay must clear the border: it shares the bar's strata and can
    -- sit above the overlay's default level, so match strata and lift past it.
    local ovr = power._ppTextOvr
    if ovr then
        ovr:SetFrameStrata(power:GetFrameStrata())
        if showBorder then
            ovr:SetFrameLevel(borderLevel + 5)
        else
            local pf = power:GetParent()
            ovr:SetFrameLevel((pf and pf:GetFrameLevel() or power:GetFrameLevel()) + 15)
        end
    end
end

local function CreatePowerBar(frame, unit, settings)
    local powerPos = settings.powerPosition or "below"

    local power = CreateFrame("StatusBar", nil, frame)
    local isDetached = (powerPos == "detached_top" or powerPos == "detached_bottom")
    if isDetached then
        -- Custom strata if user has enabled it, otherwise default MEDIUM
        if db.profile.enableCustomBarStratas then
            power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
        else
            power:SetFrameStrata("MEDIUM")
        end
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

    -- Power bar fill color: controlled by powerPercentPowerColor toggle.
    -- Gradient (additive) layers on top of the resolved custom/power-type color.
    local usePowerColor = settings.powerPercentPowerColor ~= false
    power.colorPower = usePowerColor
    if not usePowerColor then
        local customFill = settings.customPowerFillColor
        if customFill then
            power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
        else
            power:SetStatusBarColor(0, 0, 1)
        end
    end
    power.PostUpdateColor = function(self)
        local s2 = GetSettingsForUnit(unit)
        if not s2 then return end
        local useP = s2.powerPercentPowerColor ~= false
        local bR, bG, bB
        if not useP then
            local cf = s2.customPowerFillColor
            if cf then bR, bG, bB = cf.r, cf.g, cf.b else bR, bG, bB = 0, 0, 1 end
        else
            -- Secret-safe: player via the clean token, non-player via the clean
            -- integer power type, so the custom power color applies on EVERY unit
            -- (the bar no longer depends on oUF's colors.power sync). Unmapped
            -- power types return nil and keep oUF's resolved color.
            bR, bG, bB = EllesmereUI.ResolveUnitPowerColor(unit)
        end
        if s2.powerGradientEnabled and bR then
            local gc = s2.powerGradientColor
            -- Bake Bar Opacity into the gradient endpoint alphas (a gradient
            -- overrides the texture's region alpha).
            local ga = s2.powerBarOpacity or 100
            if ga > 1.0 then ga = ga / 100 end
            ApplyBarGradient(self:GetStatusBarTexture(), s2.powerGradientDir or "HORIZONTAL",
                bR, bG, bB, ga,
                gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
        elseif not useP then
            local cf = s2.customPowerFillColor
            if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) else self:SetStatusBarColor(0, 0, 1) end
        elseif bR then
            -- Power-color mode, no gradient: apply EUI's GLOBAL power color.
            -- oUF.colors.power is not overridden, so oUF would otherwise leave
            -- the bar on its built-in default color instead of the user's.
            self:SetStatusBarColor(bR, bG, bB)
        end
        -- Bar Background: when power-colored, track this unit's power color each
        -- update so the bg follows target / power-type changes (mirrors the fill).
        -- Opacity stays driven by customPowerBgAlpha (SetAlpha), so a full-color
        -- set is correct here. Gated -> when off, the custom/dark bg set at
        -- creation/refresh stands, for zero per-update cost in the default case.
        if s2.powerBgPowerColored and self.bg then
            local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(unit)
            if pr then
                local f = EllesmereUI.GetPowerBgDarkenFactor()
                self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
            end
        end
        -- Keep the power-percent text color in sync with THIS unit (fires on
        -- target/focus change + UNIT_DISPLAYPOWER, so the text follows the unit
        -- instead of the color resolved at creation). Gated on the feature being
        -- active (power-colored AND text shown) -> short-circuits to no cost
        -- for every other frame.
        if s2.powerPercentTextPowerColor and (s2.powerPercentText or "none") ~= "none" and self._applyPowerTextColor then
            self._applyPowerTextColor(s2)
        end
        -- Same continuous re-application for the Bottom Text Bar's power-colored
        -- text (per-slot early-out keeps it ~free when no slot uses power color).
        local btb = frame.BottomTextBar
        if btb and btb._applyBTBPowerColors then btb._applyBTBPowerColors(s2) end
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

    -- Power-percent text color for the CURRENT unit (applied per-unit so
    -- target/focus follow the unit, not the player). Power-color mode resolves
    -- the unit's own power type; some enemies return a secret token that can't
    -- map to a color, so those fall back to white (matching the reference
    -- approach). No-power units are NOT special-cased -- they keep showing 0%.
    local function ApplyPowerTextColor(s)
        if s.powerPercentTextPowerColor then
            -- Secret-safe per-unit power color (see EllesmereUI.ResolveUnitPowerColor):
            -- player keeps the exact token color; non-player units recover it from
            -- the clean integer power type instead of falling back to white.
            local r, g, b = EllesmereUI.ResolveUnitPowerColor(unit)
            if r then ppFS:SetTextColor(r, g, b)
            else ppFS:SetTextColor(1, 1, 1) end
        elseif s.powerTextColor then
            local tc = s.powerTextColor
            ppFS:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        else
            ppFS:SetTextColor(1, 1, 1)
        end
    end
    power._applyPowerTextColor = ApplyPowerTextColor

    local function ApplyPowerPercentText(s)
        local pos = s.powerPercentText or "none"
        local sz  = s.powerPercentSize or 9
        local ox  = s.powerPercentX or 0
        local oy  = s.powerPercentY or 0

        -- Height-0 hotfix (purely additive; only triggers when Power Bar Height is 0).
        -- At height 0 the power bar collapses to a ZERO-HEIGHT frame, and WoW does not
        -- resolve a zero-height frame's rect -- GetLeft() returns nil -- so any overlay
        -- anchored to it collapses to a 0-width, unpositioned strip and the text never
        -- renders. Anchor the text overlay to the HEALTH bar instead (always a real,
        -- resolved frame), giving it a real text height in the row the power bar would
        -- occupy. The _euiHeight0 flag keeps frames that never hit height 0 completely
        -- untouched; returning to a positive height restores the original SetAllPoints.
        if (s.powerHeight or 6) <= 0 then
            local pPos = s.powerPosition or "below"
            local anchorTo = frame.Health or power
            ppTextOvr:ClearAllPoints()
            if pPos == "above" or pPos == "detached_top" then
                -- Power row is ABOVE health: text strip sits just above the health bar.
                ppTextOvr:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", 0, 0)
                ppTextOvr:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", 0, 0)
            else
                -- "below"/"detached_bottom": text strip sits just below the health bar.
                ppTextOvr:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 0)
                ppTextOvr:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
            end
            ppTextOvr:SetHeight(sz + 6)
            ppTextOvr._euiHeight0 = true
        elseif ppTextOvr._euiHeight0 then
            ppTextOvr:ClearAllPoints()
            ppTextOvr:SetAllPoints(power)
            ppTextOvr._euiHeight0 = nil
        end

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

        -- Text color: power-colored (per-unit) > custom color > white
        ApplyPowerTextColor(s)
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
            if s.powerBgPowerColored and self.bg then
                -- Power-colored bg: restore this unit's power color (mirrors fill);
                -- the next PostUpdateColor keeps it tracking thereafter.
                local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(u)
                if pr then
                    local f = EllesmereUI.GetPowerBgDarkenFactor()
                    self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                else self.bg:SetColorTexture(17/255, 17/255, 17/255, 1) end
            else
                local customBg = s.customPowerBgColor
                if customBg then
                    if self.bg then self.bg:SetColorTexture(customBg.r, customBg.g, customBg.b, 1) end
                else
                    if self.bg then self.bg:SetColorTexture(17/255, 17/255, 17/255, 1) end
                end
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

    -- Power bar border (detached positions only; lazily created in the helper)
    ns.UpdatePowerBorder(power, settings)

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
    if not isAttached and not isInside and portraitStyle ~= "none" then pSizeAdj = pSizeAdj + 10; pYOff = pYOff + 5 end
    local adjustedHeight = baseHeight + pSizeAdj
    if adjustedHeight < 8 then adjustedHeight = 8 end

    -- For attached, "top" and "inside*" fall back to default side
    local effectiveSide = side
    local isInside = (side == "insideleft" or side == "insideright" or side == "insidecenter")
    if isAttached and (side == "top" or isInside) then
        effectiveSide = (unit == "player") and "left" or "right"
        isInside = false
    end

    local backdrop = CreateFrame("Frame", nil, frame)
    backdrop:SetFrameStrata(frame:GetFrameStrata())
    backdrop:SetFrameLevel(frame:GetFrameLevel() + 1)
    if isInside then
        -- Inside mode: portrait fills the frame height, width = adjusted portrait size
        PP.Size(backdrop, adjustedHeight, portraitHeight)
    else
        PP.Size(backdrop, adjustedHeight, adjustedHeight)
    end
    backdrop:SetClipsChildren(false)

    local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
    PP.Point(bgTex, "TOPLEFT", backdrop, "TOPLEFT", 0, 0)
    PP.Point(bgTex, "BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0.1, 0.1, 0.1, 1)
    if isInside then bgTex:Hide() end
    backdrop._bg = bgTex

    if portraitStyle == "none" then
        -- Portrait disabled: anchor backdrop to frame corner (it stays hidden).
        -- Avoids any dependency on frame.Health which may not exist yet.
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    elseif isInside then
        -- Inside: portrait overlays the health bar. Anchor to frame initially;
        -- ReloadFrames re-anchors to frame.Health after layout resolves.
        backdrop._isInside = true
        backdrop:SetFrameLevel(frame:GetFrameLevel() + 3)
        PP.Point(backdrop, "TOPLEFT", frame, "TOPLEFT", pXOff, pYOff)
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
        local camScale = ((uSettings and uSettings.portrait3dZoom) or 100) / 100
        model3D:SetCamDistanceScale(camScale)
        -- PostUpdate: re-apply zoom after oUF calls SetUnit (which resets camera)
        model3D.PostUpdate = function(self)
            local u = self.__owner and self.__owner.unit
            if not u then return end
            local uk = UnitToSettingsKey(u)
            local us = uk and db.profile[uk]
            local cs = ((us and us.portrait3dZoom) or 100) / 100
            self:SetCamDistanceScale(cs)
        end
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

local function GetActiveKickSpell()
    return EllesmereUI and EllesmereUI.GetActiveKickSpell and EllesmereUI.GetActiveKickSpell()
end
local function ComputeCastBarTint(readyTint, baseTint)
    if EllesmereUI and EllesmereUI.ComputeCastBarTint then
        return EllesmereUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function IsKickCastbarUnit(unit)
    return unit == "target" or unit == "focus"
end
local function GetCastbarKickTickEnabled(settings)
    if not settings then return true end
    if settings.castbarKickTickEnabled ~= nil then return settings.castbarKickTickEnabled end
    return true
end
local function GetCastbarInterruptMidCastEnabled(settings)
    if not settings then return false end
    if settings.castbarInterruptMidCastEnabled ~= nil then return settings.castbarInterruptMidCastEnabled end
    return false
end
local function GetCastbarUninterruptible(castbar)
    local v = castbar and castbar.notInterruptible
    if type(v) == "nil" then return false end
    return v
end
local function HideUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    castbar.kickPositioner:Hide()
    castbar.kickMarker:Hide()
    castbar.kickReadyFill:Hide()
    if castbar._kickTicker then
        castbar._kickTicker:Cancel()
        castbar._kickTicker = nil
    end
end
local function ApplyUnitFrameCastColor(castbar)
    if not castbar or not castbar.castTintLayer then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner.unit
    local cc
    if settings and settings.castbarClassColored and ownerUnit == "player" then
        if ownerUnit then
            local _, classToken = UnitClass(ownerUnit)
            if classToken and EllesmereUI.GetClassColor then
                cc = EllesmereUI.GetClassColor(classToken)
            end
        end
    end
    if not cc then
        local baseTint = (settings and settings.castbarFillColor) or GetCastbarColor()
        if IsKickCastbarUnit(ownerUnit) then
            local readyTint = (settings and settings.castbarInterruptReadyColor) or { r = 0.92, g = 0.35, b = 0.20 }
            local cr, cg, cb = ComputeCastBarTint(readyTint, baseTint)
            cc = { r = cr, g = cg, b = cb }
        else
            cc = baseTint
        end
    end
    castbar.castTintLayer:SetVertexColor(cc.r, cc.g, cc.b)
    if castbar._shieldedTint then
        -- Uninterruptible overlay colour (customizable; defaults to the
        -- previously-hardcoded grey). The overlay's alpha is toggled from the
        -- secret "not interruptible" flag, so the colour is always set and only
        -- becomes visible on uninterruptible casts.
        local uc = (settings and settings.castbarUninterruptibleColor) or { r = 0.5, g = 0.5, b = 0.5 }
        castbar._shieldedTint:SetVertexColor(uc.r, uc.g, uc.b)
        local uninterruptible = GetCastbarUninterruptible(castbar)
        if castbar._shieldedTint.SetAlphaFromBoolean then
            castbar._shieldedTint:SetAlphaFromBoolean(uninterruptible, 1, 0)
        else
            castbar._shieldedTint:SetAlpha(uninterruptible and 1 or 0)
        end
    end
end
local function UpdateUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    local settings = castbar._eufSettings
    local ownerUnit = castbar.__owner and castbar.__owner.unit
    if not IsKickCastbarUnit(ownerUnit) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local tickOn = GetCastbarKickTickEnabled(settings)
    local midOn = GetCastbarInterruptMidCastEnabled(settings)
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        HideUnitFrameKickTick(castbar)
        return
    end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local kickProtected = GetCastbarUninterruptible(castbar)
    castbar._kickProtected = kickProtected
    local isChannel = castbar.channeling and true or false
    local isEmpowered = false
    if not (UnitCastingDuration and ownerUnit) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local castDuration
    if isChannel then
        if UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
            if castDuration then isEmpowered = true end
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss during an ongoing cast: skip, do not hide. This
        -- Hide/re-Show cycle on every SPELL_UPDATE_COOLDOWN (the full update
        -- re-runs per event) is what made the kick tick blink during the
        -- player's rotation. Cast end is handled by the cast-stop path.
        return
    end
    -- Cache cast identity so the light per-event refresh re-pins the bar values
    -- from it without re-deriving channel/empower or re-minting fill geometry.
    castbar._kickIsChannel = isChannel
    castbar._kickIsEmpowered = isEmpowered
    local totalDur = castDuration:GetTotalDuration()
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    local barW = castbar:GetWidth()
    local barH = castbar:GetHeight()
    if not barW or barW <= 0 then
        -- Transient zero-width during resize: skip, do not hide.
        return
    end
    castbar.kickPositioner:SetSize(barW, barH)
    castbar.kickPositioner:SetMinMaxValues(0, totalDur)
    castbar.kickMarker:SetMinMaxValues(0, totalDur)
    castbar.kickMarker:SetSize(barW, barH)
    castbar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castbar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    castbar.kickTick:SetColorTexture(1, 1, 1, 1)
    if isChannel and not isEmpowered then
        castbar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        castbar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the
        -- global hook will not re-fire on a cached bar. Re-disable snap so the
        -- summed elapsed+remaining edge stays an exact float (no per-event dance).
        local pt = castbar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
        local mt = castbar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
        castbar.kickMarker:ClearAllPoints()
        castbar.kickTick:ClearAllPoints()
        castbar.kickMarker:SetPoint("RIGHT", castbar.kickPositioner:GetStatusBarTexture(), "LEFT")
        castbar.kickTick:SetPoint("TOP", castbar.kickMarker, "TOP", 0, 0)
        castbar.kickTick:SetPoint("BOTTOM", castbar.kickMarker, "BOTTOM", 0, 0)
        castbar.kickTick:SetPoint("RIGHT", castbar.kickMarker:GetStatusBarTexture(), "LEFT")
        -- Reverse fill (draining channel): kick-ready point is the marker texture
        -- LEFT edge; the available window runs from the channel end (bar left) to
        -- it. Not-in-time pushes the marker edge past the left edge, crossing the
        -- anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar, "LEFT", 0, 0)
        castbar.kickReadyFill:SetPoint("RIGHT", castbar.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        castbar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        castbar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the
        -- reverse branch) so the tick is stationary across every re-pin.
        local pt = castbar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then pt:SetSnapToPixelGrid(false); pt:SetTexelSnappingBias(0) end
        local mt = castbar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then mt:SetSnapToPixelGrid(false); mt:SetTexelSnappingBias(0) end
        castbar.kickMarker:ClearAllPoints()
        castbar.kickTick:ClearAllPoints()
        castbar.kickMarker:SetPoint("LEFT", castbar.kickPositioner:GetStatusBarTexture(), "RIGHT")
        castbar.kickTick:SetPoint("TOP", castbar.kickMarker, "TOP", 0, 0)
        castbar.kickTick:SetPoint("BOTTOM", castbar.kickMarker, "BOTTOM", 0, 0)
        castbar.kickTick:SetPoint("LEFT", castbar.kickMarker:GetStatusBarTexture(), "RIGHT")
        -- Standard fill (cast / empowered channel): kick-ready point is the marker
        -- texture RIGHT edge; the available window runs from it to the cast end
        -- (bar right). Not-in-time pushes the marker edge past the right edge,
        -- crossing the anchors to zero width.
        castbar.kickReadyFill:ClearAllPoints()
        castbar.kickReadyFill:SetPoint("TOP", castbar, "TOP", 0, 0)
        castbar.kickReadyFill:SetPoint("BOTTOM", castbar, "BOTTOM", 0, 0)
        castbar.kickReadyFill:SetPoint("LEFT", castbar.kickMarker:GetStatusBarTexture(), "RIGHT")
        castbar.kickReadyFill:SetPoint("RIGHT", castbar, "RIGHT", 0, 0)
    end
    castbar.kickPositioner:Show()
    castbar.kickMarker:Show()
    -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility. Its alpha
    -- (the SECRET on-CD x interruptible gate) is applied with the tick alpha
    -- below. Geometry above runs whenever the tick OR the fill is enabled;
    -- SetShown gates each element to its own toggle so one never forces the other.
    local mc = (settings and settings.castbarInterruptMidCastColor) or { r = 0.318, g = 0.820, b = 0.357 }
    castbar.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
    castbar.kickTick:SetShown(tickOn)
    castbar.kickReadyFill:SetShown(midOn)
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(kickProtected, 0, 1)
        local kickReady = interruptCD:IsZero()
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
        castbar.kickTick:SetAlpha(alpha)
        castbar.kickReadyFill:SetAlpha(alpha)
    else
        castbar.kickTick:SetAlpha(0)
        castbar.kickReadyFill:SetAlpha(0)
    end
    if castbar._kickTicker then castbar._kickTicker:Cancel() end
    castbar._kickTicker = C_Timer.NewTicker(0.1, function()
        if not castbar:IsShown() or not ownerUnit then
            HideUnitFrameKickTick(castbar)
            return
        end
        if not GetActiveKickSpell() then
            HideUnitFrameKickTick(castbar)
            return
        end
        local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castbar._kickProtected, 0, 1)
            local kickReady = icd:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            castbar.kickTick:SetAlpha(alpha)
            castbar.kickReadyFill:SetAlpha(alpha)
        end
    end)
end

-- Light per-cooldown-event refresh: bar values + tick alpha only. The geometry
-- (SetSize, anchors, SetFillStyle, color) is cast-identity work done once by
-- UpdateUnitFrameKickTick. Re-pinning positioner(elapsed) and marker(remaining)
-- together keeps the tick stationary; never re-pin one without the other.
local function RefreshUnitFrameKickTick(castbar)
    if not castbar or not castbar.kickPositioner then return end
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castbar)
        return
    end
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss during an ongoing cast: skip, do not hide.
        return
    end
    local ownerUnit = castbar.__owner and castbar.__owner.unit
    if not (UnitCastingDuration and ownerUnit) then return end
    local castDuration
    if castbar._kickIsChannel then
        if castbar._kickIsEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    castbar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castbar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castbar._kickProtected, 0, 1)
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(interruptCD:IsZero(), 0, interruptible)
        castbar.kickTick:SetAlpha(alpha)
        castbar.kickReadyFill:SetAlpha(alpha)
    end
end

ns._castingCastbars = {}
local activeCastbarCount = 0
local _ufCastColorTicker
local ufKickWatcher = CreateFrame("Frame")
ufKickWatcher:SetScript("OnEvent", function(_, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        for cb in pairs(ns._castingCastbars) do
            if cb:IsShown() and cb.__owner and cb.__owner.unit then
                ApplyUnitFrameCastColor(cb)
                -- Light refresh once the kick bars are set up; only re-run the
                -- full geometry/fill setup when they are not shown (kick learned
                -- mid-cast, CD info late, toggle flipped on). This stops
                -- SetFillStyle from re-minting the inner fill textures every
                -- cooldown event, which re-snapped them to the pixel grid in
                -- lockstep with the nameplate kick churn.
                if cb.kickPositioner and not cb.kickPositioner:IsShown() then
                    UpdateUnitFrameKickTick(cb)
                else
                    RefreshUnitFrameKickTick(cb)
                end
            end
        end
    end
end)
local function NotifyCastbarStarted(castbar)
    if not castbar or not castbar.__owner then return end
    if not IsKickCastbarUnit(castbar.__owner.unit) then return end
    if ns._castingCastbars[castbar] then return end
    ns._castingCastbars[castbar] = true
    activeCastbarCount = activeCastbarCount + 1
    if activeCastbarCount == 1 then
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _ufCastColorTicker then
            _ufCastColorTicker = C_Timer.NewTicker(0.2, function()
                for cb in pairs(ns._castingCastbars) do
                    if cb:IsShown() then
                        ApplyUnitFrameCastColor(cb)
                    end
                end
            end)
        end
    end
end
local function NotifyCastbarEnded(castbar)
    if not castbar or not ns._castingCastbars[castbar] then return end
    ns._castingCastbars[castbar] = nil
    activeCastbarCount = activeCastbarCount - 1
    if activeCastbarCount <= 0 then
        activeCastbarCount = 0
        wipe(ns._castingCastbars)
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _ufCastColorTicker then
            _ufCastColorTicker:Cancel()
            _ufCastColorTicker = nil
        end
    end
end

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
        -- castbarWidth 0 = auto (boss frames: match frame width; the boss
        -- update pass re-sizes to the live frame width right after creation).
        local cbw = settings.castbarWidth or 0
        cbWidth = cbw > 0 and cbw or 181
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
    -- Background color/alpha: nil settings fall back to the original black 0.5 so
    -- existing frames are unchanged unless the user sets castBgColor/castBgAlpha.
    local _cbgC = settings.castBgColor
    bgTex:SetColorTexture(_cbgC and _cbgC.r or 0, _cbgC and _cbgC.g or 0, _cbgC and _cbgC.b or 0, settings.castBgAlpha or 0.5)
    castbarBg._bgTex = bgTex

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
    -- Text overlay must sit above the unified border (frame +10).
    local textOverlay = CreateFrame("Frame", nil, castbar)
    textOverlay:SetAllPoints(castbar)
    textOverlay:SetFrameLevel(frame:GetFrameLevel() + 11)

    local text = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(text, settings.castSpellNameSize or 11)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    text:SetTextColor(1, 1, 1)
    castbar.Text = text

    local time = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(time, settings.castDurationSize or 10)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetMaxLines(1)
    time:SetTextColor(1, 1, 1)
    castbar.Time = time

    local target = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(target, settings.castSpellTargetSize or 11)
    target:SetJustifyH("RIGHT")
    target:SetWordWrap(false)
    target:SetMaxLines(1)
    target:SetTextColor(1, 1, 1)
    target:Hide()
    castbar.Target = target

    -- Side-aware three-zone layout (mirrors the nameplate cast text system). Each
    -- element has a side ("left"/"right"/"center"); the duration reserves its slot and
    -- pushes whichever non-center element shares its side. Center is never pushed.
    -- Spell name hides on the "none" side; target/duration visibility is governed by
    -- _showTarget / _showDuration (their dropdown "None" sets those flags false).
    local function LayoutCastTextZones(cb)
        local barW = cb:GetWidth()
        if not barW or barW <= 0 then return end
        -- +5px so the timer text has a little extra room before it truncates.
        local timerW = (cb._durationSize or 10) * 2.2 + 5
        local showDur = cb._showDuration ~= false
        local nameSide = cb._nameSide or "left"
        local tgtSide  = cb._tgtSide or "right"
        local durSide  = cb._durSide or "right"
        local textW = barW * 0.42
        -- Spell name width: the 42% above reserves the opposite half for the cast
        -- target. When this unit never shows a target (boss frames -- showCastTarget
        -- is false with no UI to enable it), the name has the row to itself, so let
        -- it use 80% of the bar before truncating.
        local nameW = (cb._showTarget == false) and (barW * 0.80) or textW
        -- Spell name
        cb.Text:ClearAllPoints()
        if nameSide == "none" then
            cb.Text:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(nameSide, showDur and durSide == nameSide, timerW, false)
            cb.Text:SetWidth(nameW)
            cb.Text:SetJustifyH(jh)
            cb.Text:SetPoint(pt, cb, pt, xb + (cb._nameOX or 0), 1 + (cb._nameOY or 0))
            cb.Text:Show()
        end
        -- Spell target (visibility handled by _showTarget / hasTarget elsewhere)
        do
            local pt, xb, jh = ns.GetCastTextAnchor(tgtSide, showDur and durSide == tgtSide, timerW, false)
            cb.Target:ClearAllPoints()
            cb.Target:SetWidth(textW)
            cb.Target:SetJustifyH(jh)
            cb.Target:SetPoint(pt, cb, pt, xb + (cb._tgtOX or 0), (cb._tgtOY or 0))
        end
        -- Duration / timer (side only "left"/"right"; visibility via _showDuration)
        do
            local pt, xb, jh = ns.GetCastTextAnchor(durSide, false, timerW, true)
            cb.Time:ClearAllPoints()
            cb.Time:SetWidth(timerW)
            cb.Time:SetJustifyH(jh)
            cb.Time:SetPoint(pt, cb, pt, xb + (cb._durOX or 0), (cb._durOY or 0))
        end
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        ns.ReflowFontString(cb.Text)
        ns.ReflowFontString(cb.Target)
        ns.ReflowFontString(cb.Time)
    end
    castbar._durationSize = settings.castDurationSize or 10
    castbar._nameOX = settings.castSpellNameX or 0
    castbar._nameOY = settings.castSpellNameY or 0
    castbar._durOX = settings.castDurationX or 0
    castbar._durOY = settings.castDurationY or 0
    castbar._tgtOX = settings.castSpellTargetX or 0
    castbar._tgtOY = settings.castSpellTargetY or 0
    castbar._nameSide = settings.castSpellNameSide or "left"
    castbar._tgtSide  = settings.castSpellTargetSide or "right"
    castbar._durSide  = settings.castDurationSide or "right"
    castbar._showDuration = settings.showCastDuration ~= false
    castbar._showTarget = settings.showCastTarget ~= false
    castbar._layoutTextZones = LayoutCastTextZones
    LayoutCastTextZones(castbar)

    -- Helper: sync all offset/size/side cache values from settings onto
    -- the castbar, then re-layout. Called from live refresh paths.
    castbar._syncOffsetsAndLayout = function(self, s)
        self._durationSize = s.castDurationSize or 10
        self._nameOX = s.castSpellNameX or 0
        self._nameOY = s.castSpellNameY or 0
        self._durOX  = s.castDurationX or 0
        self._durOY  = s.castDurationY or 0
        self._tgtOX  = s.castSpellTargetX or 0
        self._tgtOY  = s.castSpellTargetY or 0
        self._nameSide = s.castSpellNameSide or "left"
        self._tgtSide  = s.castSpellTargetSide or "right"
        self._durSide  = s.castDurationSide or "right"
        self._showDuration = s.showCastDuration ~= false
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

    -- Cast bar reuses the unit's health bar texture (overridden donor-aware in ReloadFrames).
    ns.ApplyCastBarTexture(castbar, (settings and settings.healthBarTexture) or db.profile.healthBarTexture or "none")

    local function OnCastbarCastActive(self)
        if self.castTintLayer then
            self.castTintLayer:SetAlpha(1)
            ApplyUnitFrameCastColor(self)
        end
    end
    castbar.PostCastStart = OnCastbarCastActive
    castbar.PostChannelStart = OnCastbarCastActive

    castbar.PostCastInterruptible = function(self)
        ApplyUnitFrameCastColor(self)
        UpdateUnitFrameKickTick(self)
    end

    if IsKickCastbarUnit(unit) then
        local kickClip = CreateFrame("Frame", nil, castbar)
        kickClip:SetAllPoints(castbar)
        kickClip:SetClipsChildren(true)
        castbar.kickClip = kickClip
        local kickPositioner = CreateFrame("StatusBar", nil, kickClip)
        kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickPositioner:GetStatusBarTexture():SetAlpha(0)
        -- Pixel-snap OFF on the fill texture (mirrors Nameplates). The tick sits
        -- at positioner_width + marker_width; independent per-fill snapping makes
        -- round(a) + round(b) wobble 1px even though the summed fraction is
        -- invariant. Load-bearing unsnap is after each SetFillStyle below.
        if kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
            kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickPositioner:SetPoint("CENTER", castbar)
        kickPositioner:SetFrameLevel(castbar:GetFrameLevel() + 1)
        kickPositioner:Hide()
        castbar.kickPositioner = kickPositioner
        local kickMarker = CreateFrame("StatusBar", nil, kickClip)
        kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickMarker:GetStatusBarTexture():SetAlpha(0)
        if kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
            kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickMarker:SetPoint("LEFT", kickPositioner:GetStatusBarTexture(), "RIGHT")
        kickMarker:SetSize(1, 1)
        kickMarker:SetFrameLevel(castbar:GetFrameLevel() + 2)
        kickMarker:Hide()
        castbar.kickMarker = kickMarker
        local kickTick = kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
        kickTick:SetColorTexture(1, 1, 1, 1)
        kickTick:SetWidth(2)
        kickTick:SetPoint("TOP", kickMarker, "TOP", 0, 0)
        kickTick:SetPoint("BOTTOM", kickMarker, "BOTTOM", 0, 0)
        kickTick:SetPoint("LEFT", kickMarker:GetStatusBarTexture(), "RIGHT")
        castbar.kickTick = kickTick
        -- Interrupt-ready mid-cast fill: colors the cast-bar segment from the
        -- "kick ready here" point to the cast end (the window during which the
        -- player's interrupt will be available) when the kick is on cooldown now
        -- but comes off cooldown before the cast finishes. Rides the SAME
        -- kickMarker geometry as the tick; the "ready in time" two-secret test is
        -- resolved by where the marker texture edge lands -- when the kick will
        -- NOT be ready in time the fill anchors cross to zero width and it self-
        -- hides with no Lua branch on a secret. ARTWORK sublevel 1 (created after
        -- castTintLayer so it draws above the fill colour) sits below the cast
        -- text (OVERLAY) and the uninterruptible grey (sublevel 2). Anchors are
        -- (re)applied per cast in UpdateUnitFrameKickTick.
        local kickReadyFill = castbar:CreateTexture(nil, "ARTWORK", nil, 1)
        kickReadyFill:SetColorTexture(1, 1, 1, 1)
        kickReadyFill:SetAlpha(0)
        kickReadyFill:Hide()
        castbar.kickReadyFill = kickReadyFill
    end

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

    -- Cast spell icon (oUF sets castbar.Icon texture automatically).
    -- Size from the CONFIGURED height (cbHeight), not a live castbarBg:GetHeight()
    -- which is unreliable this early in layout; LayoutCastbarIcon anchors the
    -- height to the bar regardless, this is just the initial square.
    local iconSize = cbHeight
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

    -- Initial icon/fill layout (re-applied on every reload by the per-unit
    -- update paths and whenever the cast-bar height changes).
    LayoutCastbarIcon(castbar, CastIconInWidth(unit, settings), cbHeight, CastIconOnRight(unit, settings))

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
    local savedInterruptHook = castbar.PostCastInterruptible

    castbar.PostCastStart = function(self, ...)
        local bg = self:GetParent()
        if bg then
            -- Boss: re-assert the configured width (castbarWidth > 0 = custom,
            -- 0 = match frame width) at cast start, so a live cast always shows
            -- the right width even if no settings pass ran since the frame
            -- was resized or another path touched the bg.
            if unit and unit:match("^boss") then
                local s = db and db.profile and GetSettingsForUnit(unit)
                local cw = (s and s.castbarWidth) or 0
                if cw > 0 and cw < 30 then cw = 30 end
                if s then PP.Width(bg, cw > 0 and cw or frame:GetWidth()) end
            end
            bg:Show()
        end
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
        UpdateUnitFrameKickTick(self)
        NotifyCastbarStarted(self)
    end
    castbar.PostChannelStart = castbar.PostCastStart
    castbar.PostCastInterruptible = function(self, ...)
        if savedInterruptHook then savedInterruptHook(self) end
    end

    local function dismissCastBar(self)
        HideUnitFrameKickTick(self)
        NotifyCastbarEnded(self)
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
        HideUnitFrameKickTick(self)
        NotifyCastbarEnded(self)
        if self._iconFrame then self._iconFrame:Hide() end
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then bg:Hide() end
        end
    end)
end


-- Boss frames have an independent Hover / Target border recolor (mirrors the
-- Raid Frames "Hover Borders" control); both default OFF. Priority: hover (while
-- moused over) > target (while this boss is the current target) > the frame's
-- normal border color. Recolors the existing unified border in place. _hovered is
-- maintained by the OnEnter/OnLeave hooks; _isTarget by the boss target updater.
-- Defined on ns (not a file local) to avoid the Lua 200-local cap.
ns.ApplyBossBorderState = function(self)
    if not self.unifiedBorder then return end
    local s = db.profile.boss
    if not s then return end
    local r, g, b, a
    if self._hovered and s.bossHoverBorderEnabled then
        local c = s.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
        r, g, b, a = c.r, c.g, c.b, s.bossHoverBorderAlpha or 1
    elseif self._isTarget and s.bossTargetBorderEnabled then
        local c = s.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
        r, g, b, a = c.r, c.g, c.b, s.bossTargetBorderAlpha or 1
    else
        local c = s.borderColor or { r = 0, g = 0, b = 0 }
        r, g, b, a = c.r, c.g, c.b, s.borderAlpha or 1
    end
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, r, g, b, a)
end

local function FrameBorderEnter(self)
    if not self.unifiedBorder then return end
    local unit = self.unit or "player"
    if unit:match("^boss%d$") then
        self._hovered = true
        ns.ApplyBossBorderState(self)
        return
    end
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local settings = isMini and GetMiniDonorSettings() or GetSettingsForUnit(unit)
    -- Highlight defaults ON (nil == enabled); only an explicit false disables it.
    if settings.highlightEnabled == false then return end
    -- Per-mini-frame opt-out: with "Show Highlight Border" off, a mini frame never
    -- recolors on hover even when the donor (main frame) highlight is enabled. (When the
    -- donor highlight is off we already returned above, so this has no effect then.)
    if isMini and GetSettingsForUnit(unit).showHighlightBorder == false then return end
    local hc = settings.highlightColor or { r = 1, g = 1, b = 1 }
    local ha = settings.highlightAlpha or 1
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, hc.r, hc.g, hc.b, ha)
end
local function FrameBorderLeave(self)
    if not self.unifiedBorder then return end
    local unit = self.unit or "player"
    if unit:match("^boss%d$") then
        self._hovered = false
        ns.ApplyBossBorderState(self)
        return
    end
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
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
    local borderBehind = settings.borderBehind
    border:SetFrameLevel(borderBehind and math.max(0, frame:GetFrameLevel() - 1) or (frame:GetFrameLevel() + 10))

    EllesmereUI.ApplyBorderStyle(border, size, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", size)

    frame.unifiedBorder = border

    if size == 0 then
        border:Hide()
    end

    frame:HookScript("OnEnter", FrameBorderEnter)
    frame:HookScript("OnLeave", FrameBorderLeave)

    return border
end

-------------------------------------------------------------------------------
--  Player Threat border (additive "Shadow" style on the PLAYER frame)
--
--  Zero cost unless enabled: no frame is created and no event is registered
--  until the option is turned on. When on we watch ONLY the player's own threat
--  (RegisterUnitEvent ... "player") plus the minimal combat / zone boundaries
--  needed to clear it, and the effect shows only in instanced content
--  (party/raid/delve) while grouped -- mirroring the nameplate non-tank logic.
-------------------------------------------------------------------------------
local _ptWatcher       -- lazily-created event frame
local _ptShownState    -- nil / "has" / "near" -- skip redundant re-apply

-- party/raid/delve instances only (mirrors the nameplate threat-context gate)
local function PT_InInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if (tonumber(difficultyID) or 0) == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then return false end
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    return instanceType == "party" or instanceType == "raid" or isDelve
end

-- Lazily create the dedicated additive shadow border on the player frame. It
-- sits behind the frame like the real "Shadow" border style, separate from the
-- unified border so it ADDS to whatever border the user already has.
local function PT_EnsureBorder(pf)
    if pf._threatShadowBorder then return pf._threatShadowBorder end
    local b = CreateFrame("Frame", nil, pf)
    PP.Point(b, "TOPLEFT", pf, "TOPLEFT", 0, 0)
    PP.Point(b, "BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
    b:SetFrameLevel(math.max(0, pf:GetFrameLevel() - 1))
    b:Hide()
    pf._threatShadowBorder = b
    return b
end

local function PT_Hide()
    local pf = frames.player
    if pf and pf._threatShadowBorder then pf._threatShadowBorder:Hide() end
    _ptShownState = nil
end

-- Render the additive Shadow border (size 2) tinted with the threat color --
-- identical to picking "Shadow" at size 2 from the Border Style dropdown.
local function PT_Show(state, c)
    local pf = frames.player
    if not pf then return end
    local b = PT_EnsureBorder(pf)
    if _ptShownState ~= state then
        _ptShownState = state
        EllesmereUI.ApplyBorderStyle(b, 2, c.r, c.g, c.b, 1, "shadow", nil, nil, nil, nil, "unitframes", 2)
    else
        EllesmereUI.SetBorderStyleColor(b, c.r, c.g, c.b, 1)
    end
    b:Show()
end

-- Re-evaluate the player's threat and paint/clear the additive shadow border.
function ns.UpdatePlayerThreatBorder()
    if not (db and db.profile and db.profile.playerThreatBorderEnabled) then PT_Hide(); return end
    if not frames.player then return end
    if not PT_InInstancedContent() or not IsInGroup() then PT_Hide(); return end
    local status = UnitThreatSituation("player")
    if status and status >= 2 then
        -- status 2/3: the mob is on you -- you have aggro.
        PT_Show("has", db.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 })
    elseif status == 1 then
        -- status 1: higher threat than the tank but not tanking yet -- close to aggro.
        PT_Show("near", db.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 })
    else
        PT_Hide()
    end
end

-- Enable/disable the watcher. Registers ONLY the player's own threat event plus
-- the minimal boundaries to clear it; tears everything down and hides when off.
function ns.SetPlayerThreatEnabled(on)
    if on then
        if not _ptWatcher then
            _ptWatcher = CreateFrame("Frame")
            _ptWatcher:SetScript("OnEvent", function() ns.UpdatePlayerThreatBorder() end)
        end
        _ptWatcher:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        _ptWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        _ptWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
        ns.UpdatePlayerThreatBorder()
    else
        if _ptWatcher then _ptWatcher:UnregisterAllEvents() end
        PT_Hide()
    end
end


-- Cropped aura icons: the button becomes a rectangle (height = 80% of width)
-- and the texture is trimmed top/bottom so the visible art keeps its aspect
-- ratio (no vertical squish), matching the action bar "cropped" shape.
-- Horizontal keeps the normal 0.07 zoom (span 0.86); the vertical span is
-- derived from the button's ACTUAL width/height (height = uSpan * h/w, centered)
-- so the shown texture's width:height always equals the frame's exactly -- even
-- after the height is rounded to whole pixels.
local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function SetAuraIconCrop(icon, cropped, w, h, zoom)
    if not icon then return end
    local z = zoom or AURA_ZOOM
    if cropped and w and h and w > 0 then
        local uSpan = 1 - 2 * z
        local vSpan = uSpan * (h / w)
        local v0 = 0.5 - vSpan / 2
        icon:SetTexCoord(z, 1 - z, v0, 1 - v0)
    else
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
end
-- Exposed so the options live preview can apply the exact same crop math
-- (rectangular height = 80% of width + aspect-preserving texcoord trim).
ns.AURA_CROP_HEIGHT = AURA_CROP_HEIGHT
ns.SetAuraIconCrop = SetAuraIconCrop
function ns.GetAuraCropHeight(cropped, w)
    if cropped then return math_floor(w * AURA_CROP_HEIGHT + 0.5) end
    return w
end

-- Apply cooldown text + stack count settings to all existing buttons in an aura
-- container. Called from ReloadFrames to live-update without /reload.
-- auraSize/cropped (optional) drive the cropped-icon rectangle + texcoord.
-- Anchor a stack-count FontString per the "Position" setting. Default anchor
-- matches oUF (BOTTOMRIGHT -1,0); corner anchors tuck the number just inside the
-- icon edge, center sits dead-center. The user X/Y offset adds on top. On ns (not
-- a local) to stay clear of the main-chunk 200-local cap.
function ns.ApplyStackAnchor(fs, parent, pos, offX, offY)
    if not fs or not parent then return end
    local point, baseX = "BOTTOMRIGHT", -1
    if pos == "bottomleft" then point, baseX = "BOTTOMLEFT", 1
    elseif pos == "topright" then point, baseX = "TOPRIGHT", -1
    elseif pos == "topleft" then point, baseX = "TOPLEFT", 1
    elseif pos == "center" then point, baseX = "CENTER", 0 end
    fs:ClearAllPoints()
    fs:SetPoint(point, parent, point, baseX + (offX or 0), offY or 0)
end

local function ApplyAuraCooldownText(container, showCD, cdSize, stackSize, cdOffX, cdOffY, stackOffX, stackOffY, auraSize, cropped, stackPos, cdTextColor, stackTextColor, iconZoom)
    if not container then return end
    -- Cropped style: make the buttons rectangular (height = 80% of width). oUF
    -- sizes each button to element.width x element.height and uses them for the
    -- grid spacing, so we set both and re-layout when they change. Texcoord is
    -- applied per button below (and at creation in SetupAuraIcon).
    local cropW, cropH
    if auraSize then
        cropW = auraSize
        cropH = cropped and math.floor(auraSize * AURA_CROP_HEIGHT + 0.5) or auraSize
        if container.width ~= cropW or container.height ~= cropH then
            container.width = cropW
            container.height = cropH
            if container.ForceUpdate then container:ForceUpdate() end
        end
    elseif container.width ~= nil or container.height ~= nil then
        -- No explicit size (e.g. boss simple debuffs): fall back to element.size.
        container.width = nil
        container.height = nil
        if container.ForceUpdate then container:ForceUpdate() end
    end
    for i = 1, (container.createdButtons or 0) do
        local btn = container[i]
        if btn and btn.Icon then SetAuraIconCrop(btn.Icon, cropped, cropW, cropH, iconZoom) end
        if btn and btn.Cooldown then
            btn.Cooldown:SetHideCountdownNumbers(not showCD)
            local cdText = btn.Cooldown:GetRegions()
            if cdText and cdText.SetFont then
                if showCD then
                    EllesmereUI.ApplyIconTextFont(cdText, cachedFontPath, cdSize, "unitFrames")
                    if cdTextColor then
                        cdText:SetTextColor(cdTextColor.r or 1, cdTextColor.g or 1, cdTextColor.b or 1)
                    end
                end
                -- Default cooldown text is centered; offset 0,0 == default.
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", btn.Cooldown, "CENTER", cdOffX or 0, cdOffY or 0)
            end
        end
        -- Stack count: our font (same as duration text), outline + slug hardcoded.
        -- Size defaults to 14 (the old NumberFontNormal size) so numbers stay the
        -- same size unless the Stack Size slider is changed. Default anchor matches
        -- oUF (BOTTOMRIGHT -1,0); offset 0,0 == default.
        if btn and btn.Count then
            EllesmereUI.ApplyIconTextFont(btn.Count, cachedFontPath, stackSize or 14, "unitFrames")
            if stackTextColor then
                btn.Count:SetTextColor(stackTextColor.r or 1, stackTextColor.g or 1, stackTextColor.b or 1)
            end
            ns.ApplyStackAnchor(btn.Count, btn, stackPos, stackOffX, stackOffY)
        end
    end
end

-- Resolve the per-unit classification toggles for an aura element's base
-- ("HELPFUL" buffs / "HARMFUL" debuffs) from its unit settings table. Returns
-- five flags in order: ownOnly, raidFrames, crowdControl, bigDefensive,
-- externalDefensive. Shared by ComposeAuraFilter (signature) and the runtime
-- FilterAura so new classifications only need adding in one place. On ns (not a
-- local) to stay clear of the main-chunk 200-local cap.
function ns.ResolveAuraFlags(base, settings)
    if base == "HELPFUL" then
        return settings.onlyPlayerBuffs, settings.buffRaid,
               settings.buffCrowdControl, settings.buffBigDefensive, settings.buffExternalDefensive
    end
    return settings.onlyPlayerDebuffs, settings.debuffRaid,
           settings.debuffCrowdControl, settings.debuffBigDefensive, settings.debuffExternalDefensive
end

-- Build a SIGNATURE string from the per-unit filter toggles. This is no longer
-- the actual fetch filter -- it's only used as part of each element's change-
-- detection key so a ForceUpdate fires when a toggle flips. The real fetch uses
-- the broad base filter + the per-aura OR FilterAura below.
function ns.ComposeAuraFilter(base, settings)
    local own, raid, cc, bigDef, extDef = ns.ResolveAuraFlags(base, settings)
    if own    then base = base .. "|PLAYER" end
    if raid   then base = base .. "|RAID" end
    if cc     then base = base .. "|CROWD_CONTROL" end
    if bigDef then base = base .. "|BIG_DEFENSIVE" end
    if extDef then base = base .. "|EXTERNAL_DEFENSIVE" end
    return base
end

-- Per-aura OR filter: when one or more of the 3 classification toggles is on, an
-- aura shows if it matches ANY selected classification (union) instead of ANDing
-- the tokens into the slot fetch (which would intersect). The element fetches
-- with the broad base filter (HELPFUL/HARMFUL); per-classification membership is
-- resolved here via IsAuraFilteredOutByInstanceID -- the same secret-safe API
-- processData already uses to set data.isPlayerAura. No toggles -> show all.
local IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
-- Sated/Exhaustion spell IDs (the lust debuff variants). Blizzard keeps these
-- readable, so spellId is safe to match. Mirrors the Raid Frames list.
local SATED_DEBUFFS = {
    [57723]  = true,  -- Exhaustion (Heroism)
    [57724]  = true,  -- Sated (Bloodlust)
    [80354]  = true,  -- Temporal Displacement (Time Warp)
    [95809]  = true,  -- Insanity (Ancient Hysteria)
    [160455] = true,  -- Fatigued (Netherwinds)
    [264689] = true,  -- Fatigued (Primal Rage)
    [390435] = true,  -- Exhaustion (Fury of the Aspects)
    [428628] = true,  -- Exhaustion (variant)
}
-- Debuffs permanently hidden from all unit frames (no toggle, ever). Blizzard
-- keeps these spellIds readable, so spellId matching is safe. Mirrors the Raid
-- Frames list.
local ALWAYS_HIDE_DEBUFFS = {
    [1254550] = true,  -- Arcane Empowerment
    [308312]  = true,  -- Time Trial Practice
}
function ns.EUIAuraFilter(element, unit, data, filter)
    if not data then return false end
    local f = element._euiAuraFlags
    local sid = data.spellId
    if sid and not issecretvalue(sid) then
        -- Permanently hidden debuffs -- never shown, no toggle.
        if ALWAYS_HIDE_DEBUFFS[sid] then return false end
        -- Lust/Sated debuff: handled OUTSIDE the filter system -- gated solely by
        -- the Show Lust Debuff toggle (off by default = hidden, on = always
        -- shown), independent of the classification filters below.
        if SATED_DEBUFFS[sid] then return (f and f.showLust) and true or false end
    end
    -- "Own Only" never applies to the player's OWN debuffs -- ignore the player
    -- flag for player + HARMFUL so a stale onlyPlayerDebuffs value has no effect.
    local usePlayer = f and f.player
    if usePlayer and unit == "player" and filter == "HARMFUL" then usePlayer = false end
    if not f or not (usePlayer or f.raid or f.cc or f.bigDef or f.extDef) then return true end
    local iid = data.auraInstanceID
    if not iid then return true end
    if usePlayer and data.isPlayerAura then return true end
    local base = filter or "HELPFUL"
    if IsAuraFilteredOut then
        if f.raid   and not IsAuraFilteredOut(unit, iid, base .. "|RAID") then return true end
        if f.cc     and not IsAuraFilteredOut(unit, iid, base .. "|CROWD_CONTROL") then return true end
        if f.bigDef and not IsAuraFilteredOut(unit, iid, base .. "|BIG_DEFENSIVE") then return true end
        if f.extDef and not IsAuraFilteredOut(unit, iid, base .. "|EXTERNAL_DEFENSIVE") then return true end
    end
    return false
end

-- Point an aura element at the broad base filter + our OR FilterAura, recording
-- the current classification toggles (and the lust-debuff override) for it to
-- read. Flags are resolved from the unit settings table by base (buff/debuff).
function ns.ApplyEUIAuraFilter(element, base, settings)
    element.filter = base
    element.FilterAura = ns.EUIAuraFilter
    local f = element._euiAuraFlags
    if not f then f = {}; element._euiAuraFlags = f end
    f.player, f.raid, f.cc, f.bigDef, f.extDef = ns.ResolveAuraFlags(base, settings)
    f.showLust = (base == "HARMFUL") and settings.showLustDebuff
end

local function CreateTargetAuras(frame, unit)
    -- 12.1 aura containers: migrated units render through the container system
    -- in EUI_UnitFrames_AuraContainers.lua. frame.Buffs/frame.Debuffs stay nil
    -- for those units, which self-neutralizes every legacy element touchpoint
    -- (all reload/startup/toggle sites are frame.Buffs-guarded).
    if ns.UF_CreateAuraContainers and ns.UF_ContainerUnits and ns.UF_ContainerUnits[unit or "target"] then
        ns.UF_GetSettings = GetSettingsForUnit -- always-fresh settings access for the container file
        ns.UF_GetProfile = ns.UF_GetProfile or function() return db and db.profile end
        return ns.UF_CreateAuraContainers(frame, unit or "target")
    end
    local function SetupAuraIcon(container, button)
        if not button then return end

        -- Read settings fresh (the `settings` local is declared below this
        -- closure in the function body, so it's not captured as an upvalue).
        local isBuff = container and container.filter == "HELPFUL"
        local s = GetSettingsForUnit(unit or "target")
        if button.Icon then
            -- Cropped icons trim the texture top/bottom to keep aspect ratio.
            local cropped, aSize, zoom
            if isBuff then cropped = s and s.buffCropIcons; aSize = (s and s.buffSize) or 22; zoom = s and s.buffIconZoom
            else cropped = s and s.debuffCropIcons; aSize = (s and s.debuffSize) or 22; zoom = s and s.debuffIconZoom end
            local cH = cropped and math.floor(aSize * AURA_CROP_HEIGHT + 0.5) or aSize
            SetAuraIconCrop(button.Icon, cropped, aSize, cH, zoom)
        end

        if button.Cooldown then
            button.Cooldown:SetDrawEdge(false)
            button.Cooldown:SetReverse(true)
            local showText, textSize, cdOffX, cdOffY, cdTextColor
            if isBuff then
                if s and unit and unit:match("^boss") and ns.GetBossSimpleBuffMode(s) ~= "none" then
                    showText = s and s.simpleBuffShowCooldownText
                    textSize = s and s.simpleBuffCooldownTextSize or 14
                    cdOffX = (s and s.buffCooldownTextOffsetX) or 0
                    cdOffY = (s and s.buffCooldownTextOffsetY) or 0
                else
                    showText = s and s.buffShowCooldownText
                    textSize = s and s.buffCooldownTextSize or 10
                    cdOffX = (s and s.buffCooldownTextOffsetX) or 0
                    cdOffY = (s and s.buffCooldownTextOffsetY) or 0
                end
                cdTextColor = (s and s.buffCooldownTextColor) or {r=1, g=1, b=1}
            elseif s and unit and unit:match("^boss") and ns.GetBossSimpleDebuffMode(s) ~= "none" then
                showText = s and s.simpleDebuffShowCooldownText
                textSize = s and s.simpleDebuffCooldownTextSize or 14
                cdOffX = (s and s.debuffCooldownTextOffsetX) or 0
                cdOffY = (s and s.debuffCooldownTextOffsetY) or 0
                cdTextColor = (s and s.debuffCooldownTextColor) or {r=1, g=1, b=1}
            else
                showText = s and s.debuffShowCooldownText
                textSize = s and s.debuffCooldownTextSize or 10
                cdOffX = (s and s.debuffCooldownTextOffsetX) or 0
                cdOffY = (s and s.debuffCooldownTextOffsetY) or 0
                cdTextColor = (s and s.debuffCooldownTextColor) or {r=1, g=1, b=1}
            end
            button.Cooldown:SetHideCountdownNumbers(not showText)
            local cdText = button.Cooldown:GetRegions()
            if cdText and cdText.SetFont then
                if showText then EllesmereUI.ApplyIconTextFont(cdText, cachedFontPath, textSize, "unitFrames") end
                cdText:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)

                -- Default cooldown text is centered; offset 0,0 == default (no change).
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", button.Cooldown, "CENTER", cdOffX, cdOffY)
            end
        end

        -- Stack count: our font (same as duration text), outline + slug hardcoded.
        -- Size defaults to 14 (the old NumberFontNormal size) so numbers stay the
        -- same size unless the Stack Size slider is changed. Default anchor matches
        -- oUF (BOTTOMRIGHT -1,0); offset 0,0 == default (no change).
        if button.Count then
            local s2 = GetSettingsForUnit(unit or "target")
            local stackSize, sOffX, sOffY, sPos, sTextColor
            if container and container.filter == "HELPFUL" then
                stackSize = s2 and s2.buffStackTextSize
                sOffX = (s2 and s2.buffStackTextOffsetX) or 0
                sOffY = (s2 and s2.buffStackTextOffsetY) or 0
                sPos = s2 and s2.buffStackTextPosition
                sTextColor = (s2 and s2.buffStackTextColor) or {r=1, g=1, b=1}
            else
                stackSize = s2 and s2.debuffStackTextSize
                sOffX = (s2 and s2.debuffStackTextOffsetX) or 0
                sOffY = (s2 and s2.debuffStackTextOffsetY) or 0
                sPos = s2 and s2.debuffStackTextPosition
                sTextColor = (s2 and s2.debuffStackTextColor) or {r=1, g=1, b=1}
            end
            EllesmereUI.ApplyIconTextFont(button.Count, cachedFontPath, stackSize or 14, "unitFrames")
            button.Count:SetTextColor(sTextColor.r, sTextColor.g, sTextColor.b)
            ns.ApplyStackAnchor(button.Count, button, sPos, sOffX, sOffY)
        end

        if not button.Border then
            button.Border = CreateFrame("Frame", nil, button)
            button.Border:SetAllPoints()
            button.Border:SetFrameLevel(button:GetFrameLevel() + 1)
            PP.CreateBorder(button.Border, 0, 0, 0, 1)
        end

        -- Keep the duration and stack text above the icon border. The PP border
        -- textures live on a container ONE level above button.Border, so lifting
        -- the cooldown to button.Border+1 would only tie the container's level and
        -- let it draw over the duration number. Go TWO levels above button.Border
        -- so the cooldown (its built-in countdown/duration text) clears the border
        -- container, then re-park oUF's stack-count frame one level above that so
        -- the stack number stays on top too (its creation-time level was relative
        -- to the cooldown's OLD level, so it no longer tracks after this bump).
        if button.Cooldown and button.Border then
            button.Cooldown:SetFrameLevel(button.Border:GetFrameLevel() + 2)
            local countFrame = button.Count and button.Count:GetParent()
            if countFrame then
                countFrame:SetFrameLevel(button.Cooldown:GetFrameLevel() + 1)
            end
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

    local unitIsBoss = unit and unit:match("^boss%d+$")

    -- Boss Simple Buff Display: force Left/Right anchor + frame-height-matched
    -- buff size when enabled (default None). Mirrors the Simple Debuff Display
    -- logic below. "left"/"right" pick the side; size matches the frame height.
    local simpleBuffMode = (unitIsBoss and settings and ns.GetBossSimpleBuffMode(settings)) or "none"
    local simpleBuffOn = simpleBuffMode ~= "none"
    if simpleBuffOn then
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        auraSize = PP.Scale(settings.healthHeight + powerH)
    end

    local buffs = CreateFrame("Frame", nil, frame)
    -- Boss frames: lift auras above the unified border so it renders BEHIND the
    -- buffs/debuffs instead of over their flush edge. The border FRAME is at
    -- frame+10, but its solid PP border textures live on a sub-container at
    -- frame+11, so the auras must clear frame+11 (not merely the border frame).
    -- frame+13 also clears the class-icon holder (frame+12) and stays below the
    -- portrait (frame+15) and health-text (frame+20) overlays.
    if unitIsBoss then buffs:SetFrameLevel(frame:GetFrameLevel() + 13) end
    local buffGrowthEff = simpleBuffOn and "auto" or (settings and settings.buffGrowth)
    local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
        simpleBuffOn and simpleBuffMode or (settings and settings.buffAnchor),
        buffGrowthEff
    )
    local buffCbOff = 0
    local bAnc = settings.buffAnchor or "topleft"
    if not simpleBuffOn and (bAnc == "bottomleft" or bAnc == "bottomright") then
        buffCbOff = cbOffset
    end
    -- Simple Buff Display anchors the column to the top of the health bar,
    -- side-based (Left grows off the left edge, Right off the right edge).
    local buffAnchorParent = frame
    if simpleBuffOn then
        if simpleBuffMode == "right" then
            bia = "TOPLEFT"
            bfp = "TOPRIGHT"
        else
            bia = "TOPRIGHT"
            bfp = "TOPLEFT"
        end
        box = 0
        boy = 0
        buffCbOff = 0
        -- Anchor to the pixel-snapped frame (not frame.Health, which is
        -- reparented into the half-pixel-inset bar clip) so the icon top is
        -- pixel-perfect flush with the frame's top edge / health bar top.
        buffAnchorParent = frame
    end
    -- Simple mode uses its own X/Y offsets (falling back to the regular buff
    -- offsets for existing users); normal mode keeps the regular ones.
    local bfOffX = settings and settings.buffOffsetX or 0
    local bfOffY = settings and settings.buffOffsetY or 0
    if simpleBuffOn then bfOffX, bfOffY = ns.GetBossSimpleBuffOffset(settings) end
    buffs:SetPoint(bia, buffAnchorParent, bfp, box * gap + bfOffX, boy * gap + buffCbOff + bfOffY)
    buffs:SetSize(containerWidth, auraSize)
    buffs.size = auraSize
    -- Icon spacing, physical-pixel-perfect at any scale. Boss uses one Spacing
    -- value (its own simple-display key when simpleBuffOn); main frames have
    -- independent X (column) / Y (row) spacing.
    if unitIsBoss then
        buffs.spacing = PP.FromPixels(ns.GetBossBuffSpacing(settings, simpleBuffOn))
    else
        buffs.spacingX = PP.FromPixels((settings and settings.buffSpacingX) or 1)
        buffs.spacingY = PP.FromPixels((settings and settings.buffSpacingY) or 1)
    end
    buffs.num = 4
    buffs.maxCols = AuraMaxCols(buffGrowthEff, settings and settings.maxBuffs or 4, settings and settings.buffMaxPerRow)
    buffs.initialAnchor = bia
    buffs.growthX = bgx
    buffs.growthY = bgy
    ns.ApplyEUIAuraFilter(buffs, "HELPFUL", settings)
    buffs.PostCreateButton = SetupAuraIcon
    if not showBuffs and not simpleBuffOn then
        buffs:Hide()
        buffs.num = 0
    end
    frame.Buffs = buffs

    local maxDebuffs = (settings and settings.maxDebuffs) or 28

    -- Boss Simple Debuff Display: force Left/Right anchor and frame-height-matched
    -- debuff size when enabled (default Left). "left"/"right" pick the side.
    local simpleMode = (unitIsBoss and settings and ns.GetBossSimpleDebuffMode(settings)) or "none"
    local simpleOn = simpleMode ~= "none"
    if simpleOn then
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        -- Snap to the frame's pixel grid so the icon height equals the frame's
        -- snapped height exactly (PP.Scale(healthHeight + powerH) == frame:GetHeight());
        -- the raw sum is up to ~1px taller than the snapped bar stack.
        debuffAuraSize = PP.Scale(settings.healthHeight + powerH)
    end

    local dAnc = settings and settings.debuffAnchor or "bottomleft"
    if simpleOn then
        dAnc = simpleMode  -- "left" or "right"
    end
    do
        local debuffs = CreateFrame("Frame", nil, frame)
        -- Boss frames: lift auras above the unified border so it renders BEHIND
        -- them. The border FRAME is frame+10 but its solid PP border textures sit
        -- on a sub-container at frame+11, so clear frame+11 (frame+13 also clears
        -- the class-icon holder at frame+12). See the Buffs container above.
        if unitIsBoss then debuffs:SetFrameLevel(frame:GetFrameLevel() + 13) end
        local effectiveAnc = (dAnc ~= "none") and dAnc or "bottomleft"
        local effectiveGrowth = simpleOn and "auto" or (settings and settings.debuffGrowth or "auto")
        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(effectiveAnc, effectiveGrowth)
        local debuffCbOff = 0
        if effectiveAnc == "bottomleft" or effectiveAnc == "bottomright" then
            debuffCbOff = cbOffset
        end
        -- Simple Debuff Display: anchor to the top of the health bar, not the
        -- frame's vertical center (matches preview layout). Left grows off the
        -- frame's left edge; Right grows off the right edge.
        local simpleAnchorParent = frame
        if simpleOn then
            if simpleMode == "right" then
                dia = "TOPLEFT"
                dfp = "TOPRIGHT"
            else
                dia = "TOPRIGHT"
                dfp = "TOPLEFT"
            end
            dox = 0
            doy = 0
            debuffCbOff = 0
            -- Anchor to the pixel-snapped frame (not frame.Health, which is
            -- reparented into the half-pixel-inset bar clip) so the icon top is
            -- pixel-perfect flush with the frame's top edge / health bar top.
            simpleAnchorParent = frame
        end
        -- Simple mode uses its own X/Y offsets (falling back to the regular
        -- debuff offsets for existing users); normal mode keeps the regular ones.
        local dbOffX = settings and settings.debuffOffsetX or 0
        local dbOffY = settings and settings.debuffOffsetY or 0
        if simpleOn then dbOffX, dbOffY = ns.GetBossSimpleDebuffOffset(settings) end
        debuffs:SetPoint(dia, simpleAnchorParent, dfp, dox * gap + dbOffX, doy * gap + debuffCbOff + dbOffY)
        debuffs:SetSize(containerWidth, debuffAuraSize)
        debuffs.size = debuffAuraSize
        -- Boss uses one Spacing value; main frames have independent X/Y spacing.
        if unitIsBoss then
            debuffs.spacing = PP.FromPixels(ns.GetBossDebuffSpacing(settings, simpleOn))
        else
            debuffs.spacingX = PP.FromPixels((settings and settings.debuffSpacingX) or 1)
            debuffs.spacingY = PP.FromPixels((settings and settings.debuffSpacingY) or 1)
        end
        debuffs.num = (dAnc ~= "none") and maxDebuffs or 0
        debuffs.maxCols = AuraMaxCols(effectiveGrowth, maxDebuffs, settings and settings.debuffMaxPerRow)
        debuffs.initialAnchor = dia
        debuffs.growthX = dgx
        debuffs.growthY = dgy
        ns.ApplyEUIAuraFilter(debuffs, "HARMFUL", settings)
        debuffs.PostCreateButton = SetupAuraIcon
        -- Dispel-type border recolor; reads the per-unit setting live so the
        -- options toggle applies on the next aura update without a rebuild.
        debuffs.PostUpdateButton = function(_, button, u, data)
            if ns.UF_ColorDebuffDispelBorder then ns.UF_ColorDebuffDispelBorder(button, u, data) end
        end
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
    ReparentBarsToClip(frame, settings.powerPosition, settings)

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
    local extraContent = settings.extraTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12
    local ets = settings.extraTextSize or settings.textSize or 12

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

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- it only anchors per extraTextAlign and is capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw
    -- absorb clips the abbreviated absorb text away at zero shield, secret-safely
    -- (the absorb is only fed to SetValue, never compared to zero). The clip
    -- frame tracks the gate's fill texture; the zone FontString is reparented
    -- into it. Driven every absorb update by the HealthPrediction Override.
    -- Lazy: _absGate/_absClip stay nil until a zone is actually set to Absorb
    -- Short, so frames that never use it pay ZERO cost (the Override below skips
    -- entirely when self._absGate is nil).
    -- content is the zone's resolved content key; "absorbshort" gates on shield
    -- absorbs, "healabsorbshort" gates on heal absorbs (g._euiHealGate marks the
    -- value source so the Override driver feeds the right amount). Anything else
    -- tears the gate down. Lazy: no gate frame is created until a zone needs one.
    local function ApplyAbsorbGate(zone, fs, content)
        local isHeal = (content == "healabsorbshort")
        local wantGate = (content == "absorbshort" or isHeal)
        local g = frame._absGate and frame._absGate[zone]
        if wantGate then
            if not g then
                frame._absGate = frame._absGate or {}
                frame._absClip = frame._absClip or {}
                g = CreateFrame("StatusBar", nil, textOverlay)
                g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
                g:SetMinMaxValues(0, 1)
                g:SetValue(0)
                local clip = CreateFrame("Frame", nil, textOverlay)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
                clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                frame._absGate[zone] = g
                frame._absClip[zone] = clip
            end
            local clip = frame._absClip[zone]
            g._euiHealGate = isHeal
            g:ClearAllPoints()
            g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
            if fs:GetParent() ~= clip then fs:SetParent(clip) end
            g:Show(); clip:Show()
            local amt
            if isHeal then
                amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
            else
                amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
            end
            g:SetValue(amt)
        elseif g then
            local clip = frame._absClip[zone]
            if fs:GetParent() == clip then fs:SetParent(textOverlay) end
            g:Hide(); if clip then clip:Hide() end
        end
    end

    -- Apply tags based on content. The Extra Text zone is handled identically to the
    -- other zones (same ContentToTag + absorb gate); it only differs in positioning:
    -- alignment-based anchor and a 95%-of-bar-width clamp (ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        local ltag = ContentToTag(lc, "leftText", settings)
        local rtag = ContentToTag(rc, "rightText", settings)
        local ctag = ContentToTag(cc, "centerText", settings)
        local etag = ContentToTag(ec, "extraText", settings)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if extraText._curTag then frame:Untag(extraText); extraText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if etag then frame:Tag(extraText, etag); extraText._curTag = etag end
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ApplyAbsorbGate("extra", extraText, ec)
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
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

        -- Extra Text: anchored per extraTextAlign (left/right/center). Truncated
        -- with an ellipsis when the text would exceed 95% of the health bar width
        -- (SetWordWrap(false) + the capped width below), matching the other zones.
        local ec = s.extraTextContent or "none"
        SetFSFont(extraText, s.extraTextSize or s.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                PP.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                PP.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                PP.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            PP.Width(extraText, barW * 0.95)
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

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
                PP.Width(leftText, barW * 0.9)
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
                PP.Width(rightText, barW * 0.9)
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
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
    ReparentBarsToClip(frame, settings.powerPosition, settings)

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

    -- Text overlay frame -- sits above the StatusBar and unified border.
    -- Parented to frame (not Health) so text is not clipped by the health bar.
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameStrata(frame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(frame:GetFrameLevel() + 20, frame.Health:GetFrameLevel() + 12))
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"
    local extraContent = settings.extraTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12
    local ets = settings.extraTextSize or settings.textSize or 12

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

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- it only anchors per extraTextAlign and is capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw
    -- absorb clips the abbreviated absorb text away at zero shield, secret-safely
    -- (the absorb is only fed to SetValue, never compared to zero). The clip
    -- frame tracks the gate's fill texture; the zone FontString is reparented
    -- into it. Driven every absorb update by the HealthPrediction Override.
    -- Lazy: _absGate/_absClip stay nil until a zone is actually set to Absorb
    -- Short, so frames that never use it pay ZERO cost (the Override below skips
    -- entirely when self._absGate is nil).
    -- content is the zone's resolved content key; "absorbshort" gates on shield
    -- absorbs, "healabsorbshort" gates on heal absorbs (g._euiHealGate marks the
    -- value source so the Override driver feeds the right amount). Anything else
    -- tears the gate down. Lazy: no gate frame is created until a zone needs one.
    local function ApplyAbsorbGate(zone, fs, content)
        local isHeal = (content == "healabsorbshort")
        local wantGate = (content == "absorbshort" or isHeal)
        local g = frame._absGate and frame._absGate[zone]
        if wantGate then
            if not g then
                frame._absGate = frame._absGate or {}
                frame._absClip = frame._absClip or {}
                g = CreateFrame("StatusBar", nil, textOverlay)
                g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
                g:SetMinMaxValues(0, 1)
                g:SetValue(0)
                local clip = CreateFrame("Frame", nil, textOverlay)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
                clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                frame._absGate[zone] = g
                frame._absClip[zone] = clip
            end
            local clip = frame._absClip[zone]
            g._euiHealGate = isHeal
            g:ClearAllPoints()
            g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
            if fs:GetParent() ~= clip then fs:SetParent(clip) end
            g:Show(); clip:Show()
            local amt
            if isHeal then
                amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
            else
                amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
            end
            g:SetValue(amt)
        elseif g then
            local clip = frame._absClip[zone]
            if fs:GetParent() == clip then fs:SetParent(textOverlay) end
            g:Hide(); if clip then clip:Hide() end
        end
    end

    -- Apply tags based on content. The Extra Text zone is handled identically to the
    -- other zones (same ContentToTag + absorb gate); it only differs in positioning:
    -- alignment-based anchor and a 95%-of-bar-width clamp (ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        local ltag = ContentToTag(lc, "leftText", settings)
        local rtag = ContentToTag(rc, "rightText", settings)
        local ctag = ContentToTag(cc, "centerText", settings)
        local etag = ContentToTag(ec, "extraText", settings)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if extraText._curTag then frame:Untag(extraText); extraText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        if etag then frame:Tag(extraText, etag); extraText._curTag = etag end
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
        ApplyAbsorbGate("extra", extraText, ec)
        if frame.UpdateTags then frame:UpdateTags() end
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
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

        -- Extra Text: anchored per extraTextAlign (left/right/center). Truncated
        -- with an ellipsis when the text would exceed 95% of the health bar width
        -- (SetWordWrap(false) + the capped width below), matching the other zones.
        local ec = s.extraTextContent or "none"
        SetFSFont(extraText, s.extraTextSize or s.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                PP.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                PP.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                PP.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            PP.Width(extraText, barW * 0.95)
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

        SetFSFont(leftText, lsz)
        leftText:ClearAllPoints()
        if lc ~= "none" then
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
        rightText:ClearAllPoints()
        if rc ~= "none" then
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

    -- Inherit health bar texture from donor frame (focus > target > player),
    -- unless this frame set its own override.
    local donor = GetMiniDonorSettings()
    local unitKey = UnitToSettingsKey(unit)
    ApplyHealthBarTexture(health, unitKey, ns.ResolveHealthBarTextureKey(settings, donor))
    ApplyHealthBarAlpha(health, unitKey)
    health:SetReverseFill(settings.healthReverseFill and true or false)
    ApplyDarkTheme(health)

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
    ReparentBarsToClip(frame, settings.powerPosition, settings)

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

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated
    -- absorb but cannot blank at zero (no has-absorb boolean exists). Instead we
    -- clip the text away when there is no shield, secret-safely: a binary
    -- StatusBar gate (max 1) is fed the raw absorb so its fill texture is full
    -- width with any shield and zero width with none; a clip frame tracks that
    -- fill rect and the zone FontString is reparented into it, so the text is
    -- clipped to nothing at zero absorb. The absorb is never compared to zero in
    -- Lua -- only fed to SetValue (which accepts secret values natively). The
    -- gate is driven every absorb update by the HealthPrediction Override.
    -- Lazy: _absGate/_absClip stay nil until a zone is actually set to Absorb
    -- Short, so frames that never use it pay ZERO cost (the Override below skips
    -- entirely when self._absGate is nil).
    -- content is the zone's resolved content key; "absorbshort" gates on shield
    -- absorbs, "healabsorbshort" gates on heal absorbs (g._euiHealGate marks the
    -- value source so the Override driver feeds the right amount). Anything else
    -- tears the gate down. Lazy: no gate frame is created until a zone needs one.
    local function ApplyAbsorbGate(zone, fs, content)
        local isHeal = (content == "healabsorbshort")
        local wantGate = (content == "absorbshort" or isHeal)
        local g = frame._absGate and frame._absGate[zone]
        if wantGate then
            if not g then
                frame._absGate = frame._absGate or {}
                frame._absClip = frame._absClip or {}
                g = CreateFrame("StatusBar", nil, textOverlay)
                g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
                g:SetMinMaxValues(0, 1)
                g:SetValue(0)
                local clip = CreateFrame("Frame", nil, textOverlay)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
                clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                frame._absGate[zone] = g
                frame._absClip[zone] = clip
            end
            local clip = frame._absClip[zone]
            g._euiHealGate = isHeal
            g:ClearAllPoints()
            g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
            if fs:GetParent() ~= clip then fs:SetParent(clip) end
            g:Show(); clip:Show()
            -- Seed once so the text is correct before the next absorb event.
            local amt
            if isHeal then
                amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
            else
                amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
            end
            g:SetValue(amt)
        elseif g then
            local clip = frame._absClip[zone]
            if fs:GetParent() == clip then fs:SetParent(textOverlay) end
            g:Hide(); if clip then clip:Hide() end
        end
    end

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc, "leftText", settings)
        local rtag = ContentToTag(rc, "rightText", settings)
        local ctag = ContentToTag(cc, "centerText", settings)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
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
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

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

    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    -- Inherit health bar texture from donor frame (focus > target > player),
    -- unless this frame set its own override.
    local donor = GetMiniDonorSettings()
    local unitKey = UnitToSettingsKey(unit)
    ApplyHealthBarTexture(health, unitKey, ns.ResolveHealthBarTextureKey(settings, donor))
    ApplyHealthBarAlpha(health, unitKey)
    health:SetReverseFill(settings.healthReverseFill and true or false)
    ApplyDarkTheme(health)

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
    ReparentBarsToClip(frame, settings.powerPosition, settings)

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

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated
    -- absorb but cannot blank at zero (no has-absorb boolean exists). Instead we
    -- clip the text away when there is no shield, secret-safely: a binary
    -- StatusBar gate (max 1) is fed the raw absorb so its fill texture is full
    -- width with any shield and zero width with none; a clip frame tracks that
    -- fill rect and the zone FontString is reparented into it, so the text is
    -- clipped to nothing at zero absorb. The absorb is never compared to zero in
    -- Lua -- only fed to SetValue (which accepts secret values natively). The
    -- gate is driven every absorb update by the HealthPrediction Override.
    -- Lazy: _absGate/_absClip stay nil until a zone is actually set to Absorb
    -- Short, so frames that never use it pay ZERO cost (the Override below skips
    -- entirely when self._absGate is nil).
    -- content is the zone's resolved content key; "absorbshort" gates on shield
    -- absorbs, "healabsorbshort" gates on heal absorbs (g._euiHealGate marks the
    -- value source so the Override driver feeds the right amount). Anything else
    -- tears the gate down. Lazy: no gate frame is created until a zone needs one.
    local function ApplyAbsorbGate(zone, fs, content)
        local isHeal = (content == "healabsorbshort")
        local wantGate = (content == "absorbshort" or isHeal)
        local g = frame._absGate and frame._absGate[zone]
        if wantGate then
            if not g then
                frame._absGate = frame._absGate or {}
                frame._absClip = frame._absClip or {}
                g = CreateFrame("StatusBar", nil, textOverlay)
                g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
                g:SetMinMaxValues(0, 1)
                g:SetValue(0)
                local clip = CreateFrame("Frame", nil, textOverlay)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
                clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                frame._absGate[zone] = g
                frame._absClip[zone] = clip
            end
            local clip = frame._absClip[zone]
            g._euiHealGate = isHeal
            g:ClearAllPoints()
            g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
            if fs:GetParent() ~= clip then fs:SetParent(clip) end
            g:Show(); clip:Show()
            -- Seed once so the text is correct before the next absorb event.
            local amt
            if isHeal then
                amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
            else
                amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
            end
            g:SetValue(amt)
        elseif g then
            local clip = frame._absClip[zone]
            if fs:GetParent() == clip then fs:SetParent(textOverlay) end
            g:Hide(); if clip then clip:Hide() end
        end
    end

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc, "leftText", settings)
        local rtag = ContentToTag(rc, "rightText", settings)
        local ctag = ContentToTag(cc, "centerText", settings)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
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
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

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
    -- Always create the absorb bar (visibility gated at render time). Boss
    -- frames carry no absorb settings of their own: they render with the
    -- TARGET frame's absorb styling (donor convention, like textures) behind
    -- the "Show on Boss Frames" toggle in the absorb cog. Geometry (reverse
    -- fill) still comes from the boss block via `settings`.
    CreateAbsorbBar(frame, unit, settings)
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
    ReparentBarsToClip(frame, settings.powerPosition, settings)

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

    -- "Absorb Short" zero-hide: the [eui-absorbshort] tag shows the abbreviated
    -- absorb but cannot blank at zero (no has-absorb boolean exists). Instead we
    -- clip the text away when there is no shield, secret-safely: a binary
    -- StatusBar gate (max 1) is fed the raw absorb so its fill texture is full
    -- width with any shield and zero width with none; a clip frame tracks that
    -- fill rect and the zone FontString is reparented into it, so the text is
    -- clipped to nothing at zero absorb. The absorb is never compared to zero in
    -- Lua -- only fed to SetValue (which accepts secret values natively). The
    -- gate is driven every absorb update by the HealthPrediction Override.
    -- Lazy: _absGate/_absClip stay nil until a zone is actually set to Absorb
    -- Short, so frames that never use it pay ZERO cost (the Override below skips
    -- entirely when self._absGate is nil).
    -- content is the zone's resolved content key; "absorbshort" gates on shield
    -- absorbs, "healabsorbshort" gates on heal absorbs (g._euiHealGate marks the
    -- value source so the Override driver feeds the right amount). Anything else
    -- tears the gate down. Lazy: no gate frame is created until a zone needs one.
    local function ApplyAbsorbGate(zone, fs, content)
        local isHeal = (content == "healabsorbshort")
        local wantGate = (content == "absorbshort" or isHeal)
        local g = frame._absGate and frame._absGate[zone]
        if wantGate then
            if not g then
                frame._absGate = frame._absGate or {}
                frame._absClip = frame._absClip or {}
                g = CreateFrame("StatusBar", nil, textOverlay)
                g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
                g:SetMinMaxValues(0, 1)
                g:SetValue(0)
                local clip = CreateFrame("Frame", nil, textOverlay)
                clip:SetClipsChildren(true)
                clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
                clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                frame._absGate[zone] = g
                frame._absClip[zone] = clip
            end
            local clip = frame._absClip[zone]
            g._euiHealGate = isHeal
            g:ClearAllPoints()
            g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
            if fs:GetParent() ~= clip then fs:SetParent(clip) end
            g:Show(); clip:Show()
            -- Seed once so the text is correct before the next absorb event.
            local amt
            if isHeal then
                amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
            else
                amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
            end
            g:SetValue(amt)
        elseif g then
            local clip = frame._absClip[zone]
            if fs:GetParent() == clip then fs:SetParent(textOverlay) end
            g:Hide(); if clip then clip:Hide() end
        end
    end

    local function ApplyTextTags(lc, rc, cc)
        local ltag = ContentToTag(lc, "leftText", settings)
        local rtag = ContentToTag(rc, "rightText", settings)
        local ctag = ContentToTag(cc, "centerText", settings)
        if leftText._curTag then frame:Untag(leftText); leftText._curTag = nil end
        if rightText._curTag then frame:Untag(rightText); rightText._curTag = nil end
        if centerText._curTag then frame:Untag(centerText); centerText._curTag = nil end
        if ltag then frame:Tag(leftText, ltag); leftText._curTag = ltag end
        if rtag then frame:Tag(rightText, rtag); rightText._curTag = rtag end
        if ctag then frame:Tag(centerText, ctag); centerText._curTag = ctag end
        ApplyAbsorbGate("left", leftText, lc)
        ApplyAbsorbGate("right", rightText, rc)
        ApplyAbsorbGate("center", centerText, cc)
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
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9)
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

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
                    local uKey3d = UnitToSettingsKey(u)
                    local uS3d = uKey3d and db.profile[uKey3d]
                    local camScale = ((uS3d and uS3d.portrait3dZoom) or 100) / 100
                    element:SetUnit(u)
                    element:SetPortraitZoom(1)
                    element:SetPosition(0, 0, 0)
                    element:SetCamDistanceScale(camScale)
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
    WARRIOR     = { [72]  = { "WHIRLWIND_STACKS", 4 },
                    [71]  = { "SWEEPING_STRIKES", 12 } },
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
        elseif powerType == "SWEEPING_STRIKES" then
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
            elseif powerType == "SWEEPING_STRIKES" and EllesmereUI and EllesmereUI.GetSweepingStrikes then
                cur, max = EllesmereUI.GetSweepingStrikes()
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
        local needsCasts    = (powerType == "TIP_OF_THE_SPEAR" or powerType == "WHIRLWIND_STACKS"
                               or powerType == "SWEEPING_STRIKES")

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
        if powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES" then
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
                        if EllesmereUI.HandleSweepingStrikes then
                            EllesmereUI.HandleSweepingStrikes(event, unit, castGUID, spellID)
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
                    if EllesmereUI.HandleSweepingStrikes then
                        EllesmereUI.HandleSweepingStrikes(event)
                    end
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if not _G._ERB_AceDB and EllesmereUI then
                    if EllesmereUI.HandleWhirlwindStacks then
                        EllesmereUI.HandleWhirlwindStacks(event)
                    end
                    if EllesmereUI.HandleSweepingStrikes then
                        EllesmereUI.HandleSweepingStrikes(event)
                    end
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

-- Custom enemy reaction colors: override oUF's shared reaction/tapped color table
-- from db.profile.enemyColors, then repaint live frames. Each entry defaults to the
-- Blizzard FACTION_BAR_COLORS value when unset, so this is idempotent and reset-safe
-- (and re-applies the active profile's colors on profile swap). Hostile = reactions
-- 1-3, Neutral = 4, Friendly = 5-8.
local function ApplyEnemyColors()
    if not (oUF and oUF.colors and oUF.colors.reaction and FACTION_BAR_COLORS) then return end
    local ec = (db and db.profile and db.profile.enemyColors) or {}
    local function setIdx(idx, custom)
        local f = FACTION_BAR_COLORS[idx]
        local r = (custom and custom.r) or (f and f.r) or 1
        local g = (custom and custom.g) or (f and f.g) or 1
        local b = (custom and custom.b) or (f and f.b) or 1
        oUF.colors.reaction[idx] = oUF:CreateColor(r, g, b)
    end
    for i = 1, 3 do setIdx(i, ec.hostile)  end
    setIdx(4, ec.neutral)
    for i = 5, 8 do setIdx(i, ec.friendly) end
    local tc = ec.tapped
    oUF.colors.tapped = oUF:CreateColor((tc and tc.r) or 0.6, (tc and tc.g) or 0.6, (tc and tc.b) or 0.6)
    if oUF.objects then
        for _, obj in next, oUF.objects do
            if obj.UpdateAllElements then obj:UpdateAllElements("OnShow") end
        end
    end
end
ns.ApplyEnemyColors = ApplyEnemyColors

local function ReloadFrames()
    ResolveFontPath()
    -- Refresh the tag-readable decimal globals before the combat early-return so
    -- tags pick up the saved state at login and on any settings change.
    ns.ApplyTextDecimalGlobals()
    if InCombatLockdown() then
        return
    end

    ApplyEnemyColors()

    -- Reset cached settings map so it rebuilds with fresh DB references
    unitSettingsMap = nil

    -- Normalize opacity values: old profiles stored 0-1 floats, new format is 0-100 integers
    do
        local prof = db.profile
        local UNITS = { "player", "target", "focus", "boss", "pet", "targettarget", "focustarget" }
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

    -- Apply frame strata to all spawned unit frames
    local ufStrata = profile.frameStrata or "MEDIUM"
    for unitKey, frame in pairs(frames) do
        if type(frame) == "table" and frame.SetFrameStrata then
            -- Mini frames (ToT / Focus Target / Pet) can override the global strata.
            local strata = ufStrata
            if unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "pet" then
                local us = profile[unitKey]
                if us and us.frameStrata then strata = us.frameStrata end
            end
            frame:SetFrameStrata(strata)
            -- Re-apply or reset custom strata for detached bars
            if frame.BottomTextBar and frame.BottomTextBar._isDetached then
                if profile.enableCustomBarStratas then
                    frame.BottomTextBar:SetFrameStrata(profile.detachedTextBarStrata or "DIALOG")
                else
                    frame.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar. frame:SetFrameStrata above
            -- just reset it to the frame's strata (same reason the cast bar needs
            -- re-lifting below), so without this a detached power bar silently
            -- falls back to the frame's strata and can end up behind the frame's
            -- own border, however "Detached Power Bar" strata is configured.
            if frame.Power then
                local us2 = GetSettingsForUnit(unitKey)
                local ppPos = us2 and us2.powerPosition or "below"
                if ppPos == "detached_top" or ppPos == "detached_bottom" then
                    if profile.enableCustomBarStratas then
                        frame.Power:SetFrameStrata(profile.detachedPowerStrata or "HIGH")
                    else
                        frame.Power:SetFrameStrata("MEDIUM")
                    end
                end
            end
            -- The cast bar is a child of the frame, so the SetFrameStrata above
            -- reset it to the frame's strata. Lift player/target/focus cast bars
            -- to HIGH so they never hide behind other MEDIUM-strata frames -- unless
            -- the global "Raise Cast Bar Strata (All)" toggle is off, in which case the
            -- cast bar is explicitly left at the frame's strata.
            if frame.Castbar and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
                local cbg = frame.Castbar:GetParent()
                if cbg then
                    if profile.raiseCastbarStrata ~= false then
                        cbg:SetFrameStrata("HIGH")
                    else
                        cbg:SetFrameStrata(strata)
                    end
                end
            end
            -- SetFrameStrata re-stacks children; lift the raid marker holder back
            -- above the text overlay so the marker is never hidden behind name/health text.
            if frame._raidMarkerHolder and frame._textOverlay then
                frame._raidMarkerHolder:SetFrameLevel(frame._textOverlay:GetFrameLevel() + 5)
            end
        end
    end

    -- Uses global font
    local donorFontPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

    -- Live enable/disable frames without reload
    local function ToggleFrame(unit, frame)
        if not frame then return end
        if frame._euiVisDriver then
            -- A secure condition driver owns this frame's Show/Hide (its
            -- group gating included); manual toggling here would de-sync
            -- it until the next driver re-evaluation. The visibility pass
            -- converts the driver when the frame is disabled.
            return
        end
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
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
                        if bossStackDir == "up" then
                            frame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, bossSpacing)
                        else
                            frame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -bossSpacing)
                        end
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

            -- Re-anchor portrait backdrop based on style + side.
            if frame.Portrait and frame.Portrait.backdrop and settings.portraitSide then
                local bd = frame.Portrait.backdrop
                local pSide = settings.portraitSide
                local isInsideNow = pSide == "insideleft" or pSide == "insideright" or pSide == "insidecenter"
                bd._isInside = isInsideNow
                if isInsideNow then
                    if bd._bg then bd._bg:Hide() end
                    local healthAnchor = frame.Health or frame
                    local pXO = settings.portraitX or 0
                    local pYO = settings.portraitY or 0
                    local pSizeAdj = settings.portraitSize or 0
                    local frameH = frame:GetHeight()
                    if frameH < 1 then frameH = 46 end
                    local pDim = frameH + pSizeAdj
                    if pDim < 8 then pDim = 8 end
                    bd:SetClipsChildren(true)
                    bd:SetFrameLevel(frame:GetFrameLevel() + 3)
                    -- Raise border above 3D model (PlayerModel ignores frame level)
                    local is3d = (settings.portraitMode or "2d") == "3d"
                    if is3d and frame.unifiedBorder and not settings.borderBehind then
                        frame.unifiedBorder:SetFrameLevel(frame:GetFrameLevel() + 20)
                    end
                    bd:ClearAllPoints()
                    bd:SetWidth(pDim)
                    if pSide == "insideleft" then
                        bd:SetPoint("TOPLEFT", healthAnchor, "TOPLEFT", pXO, pYO)
                        bd:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pXO, 0)
                    elseif pSide == "insideright" then
                        bd:SetPoint("TOPRIGHT", healthAnchor, "TOPRIGHT", pXO, pYO)
                        bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pXO, 0)
                    else
                        bd:SetPoint("TOP", healthAnchor, "TOP", pXO, pYO)
                        bd:SetPoint("BOTTOM", frame, "BOTTOM", pXO, 0)
                    end
                elseif pStyle == "attached" then
                    if bd._bg then bd._bg:Show() end
                    bd:SetClipsChildren(false)
                    bd:ClearAllPoints()
                    if pSide == "left" then
                        PP.Point(bd, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    else
                        PP.Point(bd, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    end
                end
                -- Restore border level when not inside+3D
                if not isInsideNow and frame.unifiedBorder then
                    local bBehind = settings.borderBehind
                    frame.unifiedBorder:SetFrameLevel(bBehind and math.max(0, frame:GetFrameLevel() - 1) or (frame:GetFrameLevel() + 10))
                end
            end

            -- Swap 2D/3D portrait mode if changed (no reload needed)
            if frame.Portrait then
                SwapPortraitMode(frame)
                -- Always ForceUpdate so zoom/camDistanceScale applies even without mode change
                if frame:IsElementEnabled("Portrait") and frame.Portrait.ForceUpdate then
                    frame.Portrait:ForceUpdate()
                end
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

                    if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
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
                        -- Apply custom strata for detached power bar
                        if ppIsDetached and db.profile.enableCustomBarStratas then
                            frame.Power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
                        elseif ppIsDetached then
                            frame.Power:SetFrameStrata("MEDIUM")
                        end
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

                        -- Update power bar border (detached only; lazily created)
                        ns.UpdatePowerBorder(frame.Power, settings)

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
                                PP.Size(castbarBg, cbW, cbH)
                                if castbarBg._bgTex then
                                    local cbg = settings.castBgColor
                                    castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                                end
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("player", settings), nil, CastIconOnRight("player", settings))
                                -- Resize cast icon to match castbar height
                                if frame.Castbar._iconFrame then
                                    PP.Size(frame.Castbar._iconFrame, cbH, cbH)
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
                                frame.Castbar._nameSide = settings.castSpellNameSide or "left"
                                frame.Castbar._tgtSide  = settings.castSpellTargetSide or "right"
                                frame.Castbar._durSide  = settings.castDurationSide or "right"
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
                        -- Boss frames style from the TARGET donor block,
                        -- behind the "Show on Boss Frames" toggle (nil = on).
                        local absSettings = settings
                        local absStyle = settings.showPlayerAbsorb
                        if unit and unit:match("^boss") then
                            if db.profile.boss and db.profile.boss.showAbsorbs == false then
                                absStyle = nil
                            else
                                absSettings = db.profile.target or settings
                                absStyle = absSettings.showPlayerAbsorb
                            end
                        end
                        if absStyle and absStyle ~= "none" then
                            ApplyAbsorbStyle(frame.HealthPrediction.damageAbsorb, absStyle, absSettings)
                            frame.HealthPrediction.damageAbsorb:Show()
                            -- Force an immediate value update so the bar doesn't
                            -- show stale/uninitialized fill covering the full frame.
                            if frame.HealthPrediction.Override then
                                frame.HealthPrediction.Override(frame, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
                            end
                        else
                            frame.HealthPrediction.damageAbsorb:Hide()
                            -- Decoupled heal absorb: hiding the shield bar above
                            -- cascades (via the backfill OnHide hook) into hiding
                            -- the heal-absorb bar too. Re-run the prediction so the
                            -- heal absorb re-shows immediately after a reload even
                            -- with the shield absorb off, instead of staying hidden
                            -- until the next UNIT_ABSORB_AMOUNT_CHANGED event.
                            if frame.HealthPrediction.Override then
                                frame.HealthPrediction.Override(frame, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
                            end
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
                            local buffFilter = ns.ComposeAuraFilter("HELPFUL", settings)
                            local buffKey = string.format("%s%s%d%d%d%s%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, buffCbOff, settings.buffGrowth or "auto", settings.maxBuffs or 4, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0) .. "p" .. (settings.buffMaxPerRow or 0) .. "spx" .. (settings.buffSpacingX or 1) .. "spy" .. (settings.buffSpacingY or 1) .. buffFilter
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                ns.ApplyEUIAuraFilter(frame.Buffs, "HELPFUL", settings)
                                frame.Buffs.size = settings.buffSize or 22
                                frame.Buffs.spacingX = PP.FromPixels(settings.buffSpacingX or 1); frame.Buffs.spacingY = PP.FromPixels(settings.buffSpacingY or 1)
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + buffCbOff + (settings.buffOffsetY or 0))
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4, settings.buffMaxPerRow)
                                if frame.Buffs.ForceUpdate then
                                    frame.Buffs:ForceUpdate()
                                end
                            end
                            ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10, settings.buffStackTextSize, settings.buffCooldownTextOffsetX, settings.buffCooldownTextOffsetY, settings.buffStackTextOffsetX, settings.buffStackTextOffsetY, settings.buffSize or 22, settings.buffCropIcons, settings.buffStackTextPosition, nil, nil, settings.buffIconZoom or 0.07)
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
                            local debuffFilter = ns.ComposeAuraFilter("HARMFUL", settings) .. (settings.showLustDebuff and "|LUST" or "")
                            local debuffKey = string.format("%s%s%d%d%d%s%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, debuffCbOff, settings.debuffGrowth or "auto", settings.maxDebuffs or 10, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0) .. "p" .. (settings.debuffMaxPerRow or 0) .. "spx" .. (settings.debuffSpacingX or 1) .. "spy" .. (settings.debuffSpacingY or 1) .. debuffFilter
                            if frame.Debuffs._lastDebuffKey ~= debuffKey then
                                frame.Debuffs._lastDebuffKey = debuffKey
                                ns.ApplyEUIAuraFilter(frame.Debuffs, "HARMFUL", settings)
                                frame.Debuffs.onlyShowPlayer = nil
                                frame.Debuffs.size = settings.debuffSize or 22
                                frame.Debuffs.spacingX = PP.FromPixels(settings.debuffSpacingX or 1); frame.Debuffs.spacingY = PP.FromPixels(settings.debuffSpacingY or 1)
                                frame.Debuffs:ClearAllPoints()
                                frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + debuffCbOff + (settings.debuffOffsetY or 0))
                                frame.Debuffs.initialAnchor = dia
                                frame.Debuffs.growthX = dgx
                                frame.Debuffs.growthY = dgy
                                frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10, settings.debuffMaxPerRow)
                                if frame.Debuffs.ForceUpdate then
                                    frame.Debuffs:ForceUpdate()
                                end
                            end
                            ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10, settings.debuffStackTextSize, settings.debuffCooldownTextOffsetX, settings.debuffCooldownTextOffsetY, settings.debuffStackTextOffsetX, settings.debuffStackTextOffsetY, settings.debuffSize or 22, settings.debuffCropIcons, settings.debuffStackTextPosition, nil, nil, settings.debuffIconZoom or 0.07)
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
                    ReparentBarsToClip(frame, settings.powerPosition, settings)

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

                    if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
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

                        -- Update power bar border (detached only; lazily created)
                        ns.UpdatePowerBorder(frame.Power, settings)

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

                    -- Bottom Text Bar update (target) -- must come before castbar so castbar can anchor to it
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
                                PP.Size(castbarBg, cbW2, cbH2)
                                if castbarBg._bgTex then
                                    local cbg = settings.castBgColor
                                    castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                                end
                                LayoutCastbarIcon(frame.Castbar, CastIconInWidth("target", settings), nil, CastIconOnRight("target", settings))
                                if frame.Castbar._iconFrame then
                                    PP.Size(frame.Castbar._iconFrame, cbH2, cbH2)
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
                        if frame.Castbar:IsShown() then
                            ApplyUnitFrameCastColor(frame.Castbar)
                            UpdateUnitFrameKickTick(frame.Castbar)
                        end
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
                            local buffFilter = ns.ComposeAuraFilter("HELPFUL", settings)
                            local buffKey = string.format("%s%s%d%d%s%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, settings.buffGrowth or "auto", settings.maxBuffs or 20, liveCbOff, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0) .. "p" .. (settings.buffMaxPerRow or 0) .. "spx" .. (settings.buffSpacingX or 1) .. "spy" .. (settings.buffSpacingY or 1) .. buffFilter
                            if frame.Buffs._lastBuffKey ~= buffKey then
                                frame.Buffs._lastBuffKey = buffKey
                                ns.ApplyEUIAuraFilter(frame.Buffs, "HELPFUL", settings)
                                frame.Buffs.size = settings.buffSize or 22
                                frame.Buffs.spacingX = PP.FromPixels(settings.buffSpacingX or 1); frame.Buffs.spacingY = PP.FromPixels(settings.buffSpacingY or 1)
                                frame.Buffs:ClearAllPoints()
                                frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + liveCbOff + (settings.buffOffsetY or 0))
                                frame.Buffs.initialAnchor = bia
                                frame.Buffs.growthX = bgx
                                frame.Buffs.growthY = bgy
                                frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4, settings.buffMaxPerRow)
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
                        ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10, settings.buffStackTextSize, settings.buffCooldownTextOffsetX, settings.buffCooldownTextOffsetY, settings.buffStackTextOffsetX, settings.buffStackTextOffsetY, settings.buffSize or 22, settings.buffCropIcons, settings.buffStackTextPosition, nil, nil, settings.buffIconZoom or 0.07)
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
                            local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                            local liveDbCbOff = 0
                            if settings.showCastbar ~= false then
                                if dAnc == "bottomleft" or dAnc == "bottomright" then
                                    local cbH = settings.castbarHeight or 14
                                    if cbH <= 0 then cbH = 14 end
                                    liveDbCbOff = -cbH
                                end
                            end
                            local debuffFilter = ns.ComposeAuraFilter("HARMFUL", settings) .. (settings.showLustDebuff and "|LUST" or "")
                            local debuffKey = string.format("%s%s%d%d%s%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, settings.debuffGrowth or "auto", settings.maxDebuffs or 20, liveDbCbOff, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0, settings.onlyPlayerDebuffs and 1 or 0) .. "p" .. (settings.debuffMaxPerRow or 0) .. "spx" .. (settings.debuffSpacingX or 1) .. "spy" .. (settings.debuffSpacingY or 1) .. debuffFilter
                            if frame.Debuffs._lastDebuffKey ~= debuffKey then
                                frame.Debuffs._lastDebuffKey = debuffKey
                                ns.ApplyEUIAuraFilter(frame.Debuffs, "HARMFUL", settings)
                                frame.Debuffs.onlyShowPlayer = nil
                                frame.Debuffs.size = settings.debuffSize or 22
                                frame.Debuffs.spacingX = PP.FromPixels(settings.debuffSpacingX or 1); frame.Debuffs.spacingY = PP.FromPixels(settings.debuffSpacingY or 1)
                                frame.Debuffs:ClearAllPoints()
                                frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + liveDbCbOff + (settings.debuffOffsetY or 0))
                                frame.Debuffs.initialAnchor = dia
                                frame.Debuffs.growthX = dgx
                                frame.Debuffs.growthY = dgy
                                frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10, settings.debuffMaxPerRow)
                                if frame.Debuffs.ForceUpdate then
                                    frame.Debuffs:ForceUpdate()
                                end
                            end
                        end
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10, settings.debuffStackTextSize, settings.debuffCooldownTextOffsetX, settings.debuffCooldownTextOffsetY, settings.debuffStackTextOffsetX, settings.debuffStackTextOffsetY, settings.debuffSize or 22, settings.debuffCropIcons, settings.debuffStackTextPosition, nil, nil, settings.debuffIconZoom or 0.07)
                    end

                    UpdateBordersForScale(frame, unit)
                    ReparentBarsToClip(frame, settings.powerPosition, settings)
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

                if frame.Portrait and frame.Portrait.backdrop and not frame.Portrait.backdrop._isInside then
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
                    -- Update power bar border (detached only; lazily created)
                    ns.UpdatePowerBorder(frame.Power, settings)
                end
                if frame._applyTextTags then
                    frame._applyTextTags(settings.leftTextContent or "name", settings.rightTextContent or "perhp", settings.centerTextContent or "none")
                end
                if frame._applyTextPositions then
                    frame._applyTextPositions(settings)
                end

                -- Bottom Text Bar update (focus) -- must come before castbar so castbar can anchor to it
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
                            PP.Size(castbarBg, cbW3, cbH3)
                            if castbarBg._bgTex then
                                local cbg = settings.castBgColor
                                castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                            end
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("focus", settings), nil, CastIconOnRight("focus", settings))
                            if frame.Castbar._iconFrame then
                                PP.Size(frame.Castbar._iconFrame, cbH3, cbH3)
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
                    if frame.Castbar:IsShown() then
                        ApplyUnitFrameCastColor(frame.Castbar)
                        UpdateUnitFrameKickTick(frame.Castbar)
                    end
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
                        frame.Castbar._nameSide = settings.castSpellNameSide or "left"
                        frame.Castbar._tgtSide  = settings.castSpellTargetSide or "right"
                        frame.Castbar._durSide  = settings.castDurationSide or "right"
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
                        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, settings.debuffGrowth or "auto")
                        local focusDbCbOff = 0
                        if settings.showCastbar ~= false then
                            if dAnc == "bottomleft" or dAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                focusDbCbOff = -cbH
                            end
                        end
                        local debuffFilter = ns.ComposeAuraFilter("HARMFUL", settings) .. (settings.showLustDebuff and "|LUST" or "")
                        local debuffKey = string.format("%s%s%d%d%s%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, settings.debuffGrowth or "auto", settings.maxDebuffs or 10, focusDbCbOff, settings.debuffSize or 22, settings.debuffOffsetX or 0, settings.debuffOffsetY or 0, settings.onlyPlayerDebuffs and 1 or 0) .. "p" .. (settings.debuffMaxPerRow or 0) .. "spx" .. (settings.debuffSpacingX or 1) .. "spy" .. (settings.debuffSpacingY or 1) .. debuffFilter
                        if frame.Debuffs._lastDebuffKey ~= debuffKey then
                            frame.Debuffs._lastDebuffKey = debuffKey
                            ns.ApplyEUIAuraFilter(frame.Debuffs, "HARMFUL", settings)
                            frame.Debuffs.onlyShowPlayer = nil
                            frame.Debuffs.size = settings.debuffSize or 22
                            frame.Debuffs.spacingX = PP.FromPixels(settings.debuffSpacingX or 1); frame.Debuffs.spacingY = PP.FromPixels(settings.debuffSpacingY or 1)
                            frame.Debuffs:ClearAllPoints()
                            frame.Debuffs:SetPoint(dia, frame, dfp, dox * 1 + (settings.debuffOffsetX or 0), doy * 1 + focusDbCbOff + (settings.debuffOffsetY or 0))
                            frame.Debuffs.initialAnchor = dia
                            frame.Debuffs.growthX = dgx
                            frame.Debuffs.growthY = dgy
                            frame.Debuffs.maxCols = AuraMaxCols(settings.debuffGrowth, settings.maxDebuffs or 10, settings.debuffMaxPerRow)
                            if frame.Debuffs.ForceUpdate then
                                frame.Debuffs:ForceUpdate()
                            end
                        end
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10, settings.debuffStackTextSize, settings.debuffCooldownTextOffsetX, settings.debuffCooldownTextOffsetY, settings.debuffStackTextOffsetX, settings.debuffStackTextOffsetY, settings.debuffSize or 22, settings.debuffCropIcons, settings.debuffStackTextPosition, nil, nil, settings.debuffIconZoom or 0.07)
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
                        local buffFilter = ns.ComposeAuraFilter("HELPFUL", settings)
                        local buffKey = string.format("%s%s%d%d%s%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, settings.buffGrowth or "auto", settings.maxBuffs or 4, focusBfCbOff, settings.buffSize or 22, settings.buffOffsetX or 0, settings.buffOffsetY or 0) .. "p" .. (settings.buffMaxPerRow or 0) .. "spx" .. (settings.buffSpacingX or 1) .. "spy" .. (settings.buffSpacingY or 1) .. buffFilter
                        if frame.Buffs._lastBuffKey ~= buffKey then
                            frame.Buffs._lastBuffKey = buffKey
                            ns.ApplyEUIAuraFilter(frame.Buffs, "HELPFUL", settings)
                            frame.Buffs.size = settings.buffSize or 22
                            frame.Buffs.spacingX = PP.FromPixels(settings.buffSpacingX or 1); frame.Buffs.spacingY = PP.FromPixels(settings.buffSpacingY or 1)
                            frame.Buffs:ClearAllPoints()
                            frame.Buffs:SetPoint(bia, frame, bfp, box * 1 + (settings.buffOffsetX or 0), boy * 1 + focusBfCbOff + (settings.buffOffsetY or 0))
                            frame.Buffs.initialAnchor = bia
                            frame.Buffs.growthX = bgx
                            frame.Buffs.growthY = bgy
                            frame.Buffs.maxCols = AuraMaxCols(settings.buffGrowth, settings.maxBuffs or 4, settings.buffMaxPerRow)
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
                    ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10, settings.buffStackTextSize, settings.buffCooldownTextOffsetX, settings.buffCooldownTextOffsetY, settings.buffStackTextOffsetX, settings.buffStackTextOffsetY, settings.buffSize or 22, settings.buffCropIcons, settings.buffStackTextPosition, nil, nil, settings.buffIconZoom or 0.07)
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition, settings)

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
                ReparentBarsToClip(frame, settings.powerPosition, settings)

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
                        if castbarBg._bgTex then
                            local cbg = settings.castBgColor
                            castbarBg._bgTex:SetColorTexture(cbg and cbg.r or 0, cbg and cbg.g or 0, cbg and cbg.b or 0, settings.castBgAlpha or 0.5)
                        end
                        if settings.showCastbar ~= false then
                            if not frame:IsElementEnabled("Castbar") then
                                frame:EnableElement("Castbar")
                            end
                            -- castbarWidth > 0 = user-set custom width; 0 = match frame width.
                            -- Custom widths floor at 30: below the cast icon size the
                            -- icon-in-width inset inverts the bar's anchor rect.
                            local bCbW = settings.castbarWidth or 0
                            if bCbW > 0 and bCbW < 30 then bCbW = 30 end
                            PP.Size(castbarBg, bCbW > 0 and bCbW or totalWidth, settings.castbarHeight or 14)
                            LayoutCastbarIcon(frame.Castbar, CastIconInWidth("boss1", settings), nil, CastIconOnRight("boss1", settings))
                            if frame.Castbar._iconFrame then
                                local cbH = settings.castbarHeight or 14
                                PP.Size(frame.Castbar._iconFrame, cbH, cbH)
                                if not frame.Castbar:IsShown() then
                                    frame.Castbar._iconFrame:Hide()
                                elseif settings.showCastIcon == false then
                                    frame.Castbar._iconFrame:Hide()
                                else
                                    frame.Castbar._iconFrame:Show()
                                end
                            end
                            castbarBg:ClearAllPoints()
                            -- Anchor to the frame's own (pixel-snapped) bottom edge, not the
                            -- bar's bottom: the health/power bars live in the half-pixel-inset
                            -- bar clip, which left a ~1px gap below the frame. The cast bar is
                            -- full frame width, so frame bottom-center keeps it centered + flush.
                            -- castbarOffsetX/Y nudge the whole cast bar (positive = right/up).
                            castbarBg:SetPoint("TOP", frame, "BOTTOM", settings.castbarOffsetX or 0, settings.castbarOffsetY or 0)
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
                        frame.Castbar._nameSide = settings.castSpellNameSide or "left"
                        frame.Castbar._tgtSide  = settings.castSpellTargetSide or "right"
                        frame.Castbar._durSide  = settings.castDurationSide or "right"
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
                    local simpleMode = ns.GetBossSimpleDebuffMode(settings)
                    local simpleOn = simpleMode ~= "none"
                    local dAnc = settings.debuffAnchor or "bottomleft"
                    local effectiveDebuffSize = settings.debuffSize or 22
                    if simpleOn then
                        dAnc = simpleMode  -- "left" or "right"
                        local powerPos = settings.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
                        -- Pixel-snap to match the frame's snapped height exactly
                        -- (== frame:GetHeight()); the raw sum overhangs ~1px.
                        effectiveDebuffSize = PP.Scale(settings.healthHeight + powerH)
                    end
                    -- Boss preview: the fake debuff overlay handles display, so
                    -- suppress the real (player-unit) debuffs to keep the preview
                    -- to exactly the fake set.
                    if ns._bossPreviewActive then dAnc = "none" end
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
                        -- Simple mode fixes the column to the chosen side; ignore any
                        -- stored debuff growth so the side determines direction
                        -- (mirrors CreateTargetAuras and both previews).
                        local effGrowth = simpleOn and "auto" or (settings.debuffGrowth or "auto")
                        local dfp, dia, dgx, dgy, dox, doy = ResolveBuffLayout(dAnc, effGrowth)
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
                        if simpleOn then
                            if simpleMode == "right" then
                                dia = "TOPLEFT"
                                dfp = "TOPRIGHT"
                            else
                                dia = "TOPRIGHT"
                                dfp = "TOPLEFT"
                            end
                            dox = 0
                            doy = 0
                            liveDbCbOff = 0
                            -- Anchor to the pixel-snapped frame (not frame.Health, which is
                            -- reparented into the half-pixel-inset bar clip) so the icon top
                            -- is pixel-perfect flush with the frame's top edge / health top.
                            simpleAnchorParent = frame
                        end
                        local debuffFilter = ns.ComposeAuraFilter("HARMFUL", settings) .. (settings.showLustDebuff and "|LUST" or "")
                        -- Simple mode uses its own X/Y offsets (falling back to the
                        -- regular debuff offsets for existing users); normal mode
                        -- keeps the regular ones. Folded into the key so a change
                        -- re-anchors the stack.
                        local dbOffX = settings.debuffOffsetX or 0
                        local dbOffY = settings.debuffOffsetY or 0
                        if simpleOn then dbOffX, dbOffY = ns.GetBossSimpleDebuffOffset(settings) end
                        -- Physical-pixel icon spacing (folded into the key so a
                        -- spacing change re-anchors the stack on the next refresh).
                        local debuffSpacingVal = ns.GetBossDebuffSpacing(settings, simpleOn)
                        local debuffKey = string.format("%s%s%d%d%s%d%d%d%d%d%d", dia or "", dfp or "", dox or 0, doy or 0, effGrowth, settings.maxDebuffs or 10, liveDbCbOff, effectiveDebuffSize, dbOffX, dbOffY, settings.onlyPlayerDebuffs and 1 or 0) .. "p" .. (settings.debuffMaxPerRow or 0) .. "sp" .. debuffSpacingVal .. debuffFilter
                        if frame.Debuffs._lastDebuffKey ~= debuffKey then
                            frame.Debuffs._lastDebuffKey = debuffKey
                            ns.ApplyEUIAuraFilter(frame.Debuffs, "HARMFUL", settings)
                            frame.Debuffs.onlyShowPlayer = nil
                            frame.Debuffs.size = effectiveDebuffSize
                            frame.Debuffs.spacing = PP.FromPixels(debuffSpacingVal)
                            frame.Debuffs:ClearAllPoints()
                            frame.Debuffs:SetPoint(dia, simpleAnchorParent, dfp, dox * 1 + dbOffX, doy * 1 + liveDbCbOff + dbOffY)
                            frame.Debuffs.initialAnchor = dia
                            frame.Debuffs.growthX = dgx
                            frame.Debuffs.growthY = dgy
                            frame.Debuffs.maxCols = AuraMaxCols(effGrowth, settings.maxDebuffs or 10, settings.debuffMaxPerRow)
                            if frame.Debuffs.ForceUpdate then
                                frame.Debuffs:ForceUpdate()
                            end
                        end
                    end
                    -- Use simple debuff cooldown text settings when simple display
                    -- is active, regular debuff settings otherwise.
                    if simpleOn then
                        ApplyAuraCooldownText(frame.Debuffs, settings.simpleDebuffShowCooldownText, settings.simpleDebuffCooldownTextSize or 14, settings.debuffStackTextSize, settings.simpleDebuffCooldownTextOffsetX, settings.simpleDebuffCooldownTextOffsetY, settings.debuffStackTextOffsetX, settings.debuffStackTextOffsetY, nil, nil, settings.debuffStackTextPosition, settings.debuffCooldownTextColor, settings.debuffStackTextColor, settings.debuffIconZoom or 0.07)
                    else
                        ApplyAuraCooldownText(frame.Debuffs, settings.debuffShowCooldownText, settings.debuffCooldownTextSize or 10, settings.debuffStackTextSize, settings.debuffCooldownTextOffsetX, settings.debuffCooldownTextOffsetY, settings.debuffStackTextOffsetX, settings.debuffStackTextOffsetY, settings.debuffSize or 22, settings.debuffCropIcons, settings.debuffStackTextPosition, settings.debuffCooldownTextColor, settings.debuffStackTextColor, settings.debuffIconZoom or 0.07)
                    end
                end

                -- Buffs (boss)
                if frame.Buffs then
                    local simpleBuffMode = ns.GetBossSimpleBuffMode(settings)
                    local simpleBuffOn = simpleBuffMode ~= "none"
                    local effectiveBuffSize = settings.buffSize or 22
                    if simpleBuffOn then
                        local powerPos = settings.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
                        effectiveBuffSize = PP.Scale(settings.healthHeight + powerH)
                    end
                    local showBuffs = settings.showBuffs ~= false
                    -- Simple Buff Display forces buffs on regardless of Buffs Location.
                    if simpleBuffOn then showBuffs = true end
                    -- Boss preview: the fake buff overlay handles display, so
                    -- suppress the real (player-unit) buffs during preview.
                    if ns._bossPreviewActive then showBuffs = false end
                    if showBuffs then
                        if not frame:IsElementEnabled("Buffs") then
                            frame:EnableElement("Buffs")
                        end
                        frame.Buffs:Show()
                        frame.Buffs.num = settings.maxBuffs or 4
                        local bGrowthEff = simpleBuffOn and "auto" or (settings.buffGrowth or "auto")
                        local bfp, bia, bgx, bgy, box, boy = ResolveBuffLayout(
                            simpleBuffOn and simpleBuffMode or settings.buffAnchor, bGrowthEff
                        )
                        local bossBfCbOff = 0
                        if not simpleBuffOn and settings.showCastbar ~= false then
                            local bAnc = settings.buffAnchor or "topleft"
                            if bAnc == "bottomleft" or bAnc == "bottomright" then
                                local cbH = settings.castbarHeight or 14
                                if cbH <= 0 then cbH = 14 end
                                bossBfCbOff = -cbH
                            end
                        end
                        -- Simple Buff Display: anchor the column to the TOP of the
                        -- health bar, side-based, mirroring Simple Debuff Display.
                        local buffAnchorParent = frame
                        if simpleBuffOn then
                            if simpleBuffMode == "right" then
                                bia = "TOPLEFT"
                                bfp = "TOPRIGHT"
                            else
                                bia = "TOPRIGHT"
                                bfp = "TOPLEFT"
                            end
                            box = 0
                            boy = 0
                            bossBfCbOff = 0
                            -- Anchor to the pixel-snapped frame (not frame.Health, which is
                            -- reparented into the half-pixel-inset bar clip) so the icon top
                            -- is pixel-perfect flush with the frame's top edge / health top.
                            buffAnchorParent = frame
                        end
                        -- Boss buffs are NEVER filtered -- always show all HELPFUL auras.
                        local buffFilter = "HELPFUL"
                        -- Simple mode uses its own X/Y offsets (fallback to the regular
                        -- buff offsets for existing users). Folded into the key.
                        local bfOffX = settings.buffOffsetX or 0
                        local bfOffY = settings.buffOffsetY or 0
                        if simpleBuffOn then bfOffX, bfOffY = ns.GetBossSimpleBuffOffset(settings) end
                        -- Physical-pixel icon spacing (folded into the key so a
                        -- spacing change re-anchors the column on the next refresh).
                        local buffSpacingVal = ns.GetBossBuffSpacing(settings, simpleBuffOn)
                        local buffKey = string.format("%s%s%d%d%s%d%d%d%d%d", bia or "", bfp or "", box or 0, boy or 0, bGrowthEff, settings.maxBuffs or 4, bossBfCbOff, effectiveBuffSize, bfOffX, bfOffY) .. "p" .. (settings.buffMaxPerRow or 0) .. "sp" .. buffSpacingVal .. buffFilter
                        if frame.Buffs._lastBuffKey ~= buffKey then
                            frame.Buffs._lastBuffKey = buffKey
                            ns.ApplyEUIAuraFilter(frame.Buffs, "HELPFUL", {})  -- boss buffs: no filtering
                            frame.Buffs.size = effectiveBuffSize
                            frame.Buffs.spacing = PP.FromPixels(buffSpacingVal)
                            frame.Buffs:ClearAllPoints()
                            frame.Buffs:SetPoint(bia, buffAnchorParent, bfp, box * 1 + bfOffX, boy * 1 + bossBfCbOff + bfOffY)
                            frame.Buffs.initialAnchor = bia
                            frame.Buffs.growthX = bgx
                            frame.Buffs.growthY = bgy
                            frame.Buffs.maxCols = AuraMaxCols(bGrowthEff, settings.maxBuffs or 4, settings.buffMaxPerRow)
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
                    -- Cooldown/stack text: simple uses the simpleBuff* keys (sharing the
                    -- regular buff stack settings), regular buff keys otherwise.
                    if simpleBuffOn then
                        ApplyAuraCooldownText(frame.Buffs, settings.simpleBuffShowCooldownText, settings.simpleBuffCooldownTextSize or 14, settings.buffStackTextSize, settings.simpleBuffCooldownTextOffsetX, settings.simpleBuffCooldownTextOffsetY, settings.buffStackTextOffsetX, settings.buffStackTextOffsetY, nil, nil, settings.buffStackTextPosition, settings.buffCooldownTextColor, settings.buffStackTextColor, settings.buffIconZoom or 0.07)
                    else
                        ApplyAuraCooldownText(frame.Buffs, settings.buffShowCooldownText, settings.buffCooldownTextSize or 10, settings.buffStackTextSize, settings.buffCooldownTextOffsetX, settings.buffCooldownTextOffsetY, settings.buffStackTextOffsetX, settings.buffStackTextOffsetY, settings.buffSize or 22, settings.buffCropIcons, settings.buffStackTextPosition, settings.buffCooldownTextColor, settings.buffStackTextColor, settings.buffIconZoom or 0.07)
                    end
                end

                UpdateBordersForScale(frame, unit)
                ReparentBarsToClip(frame, settings.powerPosition, settings)
            end

            -- Determine if this is a mini frame that inherits border/texture/font
            local isMiniFrame = (unit == "pet" or unit == "targettarget" or unit == "focustarget" or unit:match("^boss%d$"))
            local donorSettings = isMiniFrame and GetMiniDonorSettings() or settings

            -- Apply health bar texture overlay (mini frames inherit the donor
            -- texture unless they set their own override).
            if isMiniFrame then
                local uKey = UnitToSettingsKey(unit)
                ApplyHealthBarTexture(frame.Health, uKey, ns.ResolveHealthBarTextureKey(settings, donorSettings))
                ApplyHealthBarAlpha(frame.Health, uKey)
            else
                ApplyHealthBarTexture(frame.Health, UnitToSettingsKey(unit))
                ApplyHealthBarAlpha(frame.Health, UnitToSettingsKey(unit))
            end
            -- Cast bar reuses the same bar texture as the health bar.
            if frame.Castbar then
                local cbTexKey
                if isMiniFrame then
                    cbTexKey = ns.ResolveHealthBarTextureKey(settings, donorSettings)
                else
                    cbTexKey = settings.healthBarTexture or db.profile.healthBarTexture or "none"
                end
                ns.ApplyCastBarTexture(frame.Castbar, cbTexKey)
            end
            -- Boss Hover/Target border: the border was just restyled to its normal
            -- color above, so re-apply the hover/target recolor (both default off,
            -- so this is a no-op unless the user enabled a boss border).
            if unit:match("^boss%d$") then
                local isT = UnitIsUnit(unit, "target")
                frame._isTarget = (isT and not issecretvalue(isT)) and true or false
                ns.ApplyBossBorderState(frame)
            end
            frame.Health:SetReverseFill(settings.healthReverseFill and true or false)
            ApplyDarkTheme(frame.Health)
            UpdateAbsorbBarReverseFill(frame, settings.healthReverseFill and true or false)
            -- Smooth bar interpolation (live toggle without /reload)
            if settings.smoothBars then
                frame.Health.smoothing = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.ExponentialEaseOut
            else
                frame.Health.smoothing = Enum and Enum.StatusBarInterpolation
                    and Enum.StatusBarInterpolation.Immediate
            end
            if frame.Health.ForceUpdate then
                frame.Health:ForceUpdate()
            end

            -- Apply power bar opacity
            if frame.Power then
                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))

                -- Re-apply power bar fill color based on powerPercentPowerColor toggle.
                -- Gradient (additive) layers on top of the resolved custom/power-type color.
                local usePowerColor = settings.powerPercentPowerColor ~= false
                frame.Power.colorPower = usePowerColor
                if not usePowerColor then
                    local customFill = settings.customPowerFillColor
                    if customFill then
                        frame.Power:SetStatusBarColor(customFill.r, customFill.g, customFill.b)
                    else
                        frame.Power:SetStatusBarColor(0, 0, 1)
                    end
                end
                frame.Power.PostUpdateColor = function(self)
                    local s2 = GetSettingsForUnit(unit)
                    if not s2 then return end
                    local useP = s2.powerPercentPowerColor ~= false
                    local bR, bG, bB
                    if not useP then
                        local cf = s2.customPowerFillColor
                        if cf then bR, bG, bB = cf.r, cf.g, cf.b else bR, bG, bB = 0, 0, 1 end
                    else
                        -- Secret-safe per-unit power color (player via token,
                        -- non-player via the clean integer type), so custom power
                        -- colors apply on EVERY unit independent of oUF's sync.
                        bR, bG, bB = EllesmereUI.ResolveUnitPowerColor(unit)
                    end
                    if s2.powerGradientEnabled and bR then
                        local gc = s2.powerGradientColor
                        local ga = s2.powerBarOpacity or 100
                        if ga > 1.0 then ga = ga / 100 end
                        ApplyBarGradient(self:GetStatusBarTexture(), s2.powerGradientDir or "HORIZONTAL",
                            bR, bG, bB, ga,
                            gc and gc.r or 0.20, gc and gc.g or 0.20, gc and gc.b or 0.80, ga)
                    elseif not useP then
                        local cf = s2.customPowerFillColor
                        if cf then self:SetStatusBarColor(cf.r, cf.g, cf.b) else self:SetStatusBarColor(0, 0, 1) end
                    elseif bR then
                        -- Power-color mode (no gradient): explicitly paint the bar
                        -- so it does not depend on oUF's colors.power being synced
                        -- (block 1 does this; this settings-refresh copy did not,
                        -- which is why non-player bars showed oUF's default color).
                        self:SetStatusBarColor(bR, bG, bB)
                    end
                    -- Bar Background: power-colored bg tracks this unit's power
                    -- color each update (mirrors the fill); see CreatePowerBar.
                    if s2.powerBgPowerColored and self.bg then
                        local pr, pg, pb = EllesmereUI.ResolveUnitPowerColor(unit)
                        if pr then
                            local f = EllesmereUI.GetPowerBgDarkenFactor()
                            self.bg:SetColorTexture(pr * f, pg * f, pb * f, 1)
                        end
                    end
                    -- Keep the power-percent text color in sync with this unit
                    -- (per-unit power color; set up in CreatePowerBar). Gated on
                    -- the feature being active (power-colored AND text shown) ->
                    -- short-circuits to no cost for every other frame.
                    if s2.powerPercentTextPowerColor and (s2.powerPercentText or "none") ~= "none" and self._applyPowerTextColor then
                        self._applyPowerTextColor(s2)
                    end
                    -- Same continuous re-application for the Bottom Text Bar's
                    -- power-colored text (per-slot early-out keeps it ~free).
                    local btb = frame.BottomTextBar
                    if btb and btb._applyBTBPowerColors then btb._applyBTBPowerColors(s2) end
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
                -- Mini frames (ToT/Focus Target/Pet) may override ONLY the border
                -- size per frame (settings.borderSizeOverride); color and texture
                -- still inherit from the donor. nil = inherit the donor size.
                local bs = settings.borderSizeOverride or donorSettings.borderSize or 1
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
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, f == "") end
                    fs:SetFont(donorFontPath, sz or 12, f)
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
                -- Boss frames get their full cast text refresh in the boss branch above
                -- (colors / show / sides / bg). Two gaps remain here: the donor-font line
                -- just above set the boss cast text to the DONOR size, and the boss branch
                -- re-runs layout from the CACHED offsets. Re-apply the size from the boss
                -- settings (keeping the donor typeface) and sync the X/Y offsets + side
                -- layout so live boss frames update on every cast-text option change.
                if unit:match("^boss") then
                    local cb = frame.Castbar
                    if cb.Text then SetMiniFont(cb.Text, settings.castSpellNameSize or 11) end
                    if cb.Time then SetMiniFont(cb.Time, settings.castDurationSize or 10) end
                    if cb.Target then SetMiniFont(cb.Target, settings.castSpellTargetSize or 11) end
                    if cb._syncOffsetsAndLayout then cb:_syncOffsetsAndLayout(settings) end
                end
            end
            end -- else (enabled frame processing)
        end
    end

    -- Refresh combat indicator on player + target frames after settings change
    for _, ciu in ipairs({ "player", "target" }) do
        local cif = frames[ciu]
        if cif and cif._applyCombatTexture then
            cif._applyCombatTexture()
            local ciDefStyle = (ciu == "player") and "standard" or "none"
            if (db.profile[ciu].combatIndicatorStyle or ciDefStyle) ~= "none" and UnitAffectingCombat(ciu) then
                cif._combatIndicator:Show()
            else
                cif._combatIndicator:Hide()
            end
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
        -- Only suppress Blizzard's player cast bar when EUI actually provides a
        -- replacement. If the player is on the Blizzard (or hidden) frame source,
        -- there is no EUI cast bar, so leave Blizzard's alone.
        local suppress = (db.profile.player.showPlayerCastbar
            and ns.GetUnitFrameSource("player") == "eui") or false
        EllesmereUI.SetPlayerCastBarSuppressed("UnitFrames", suppress)
    end
end

-- Effective whole-frame alpha for a unit frame. When "Fade Out of Combat" is
-- enabled and the player is out of combat, the frame shows at its chosen
-- oocAlpha; otherwise full opacity. Off by default, so existing setups are
-- unchanged. Every "shown" SetAlpha site (visibility loop + mouseover hover)
-- routes through this so a combat transition or hover can't clobber the fade.
-- Combat state is passed in by the caller (the visibility loop uses its own
-- event-tracked _ufInCombat, which leads InCombatLockdown() on regen events).
-- On ns (not a new file-scope local) to respect the Lua 200-locals cap.
function ns.ResolveFrameAlpha(s, inCombat)
    if s and s.oocFadeEnabled and not inCombat then
        return s.oocAlpha or 0.5
    end
    return 1
end

local function UnitFrame_OnEnter(self)
    local unit = self.unit
    if not unit then return end
    local unitKey = unit:match("^boss%d$") and "boss" or unit
    local s = db and db.profile and db.profile[unitKey]
    if s and (s.barVisibility or "always") == "mouseover" then
        -- Hover-gated sets only reveal while their conditions pass; a
        -- legacy single "mouseover" reveals unconditionally as before.
        local eligible = true
        if EllesmereUI.VisWantsMouseover then
            eligible = EllesmereUI.VisWantsMouseover(s, "barVisibility", nil, EllesmereUI.VIS_CAPS_INCLUSIVE)
        end
        if eligible then
            local a = ns.ResolveFrameAlpha(s, InCombatLockdown())
            ;(self._visWrap or self):SetAlpha(a)
            -- 3D models don't inherit parent alpha: reveal the portrait too
            local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
            if bd3d then bd3d:SetAlpha(a) end
            -- Mini-frame inheritance: the companion frame reveals with us
            local mini = ns.UF_MINI_OF and frames[ns.UF_MINI_OF[unitKey]]
            if mini then mini:SetAlpha(a) end
        end
    end
    if unit and GameTooltip and GameTooltip_SetDefaultAnchor then
        local showTooltip = not s or s.showUnitTooltip ~= false
        if showTooltip then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            if GameTooltip:SetUnit(unit) then
                GameTooltip:Show()
            end
            if self._tooltipTicker then self._tooltipTicker:Cancel() end
            self._tooltipTicker = C_Timer.NewTicker(0.5, function()
                if not self:IsMouseOver() then
                    if self._tooltipTicker then self._tooltipTicker:Cancel(); self._tooltipTicker = nil end
                    return
                end
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                if GameTooltip:SetUnit(self.unit) then
                    GameTooltip:Show()
                end
            end)
        end
    end
end

local function UnitFrame_OnLeave(self)
    local unit = self.unit
    if not unit then return end
    local unitKey = unit:match("^boss%d$") and "boss" or unit
    local s = db and db.profile and db.profile[unitKey]
    if s and (s.barVisibility or "always") == "mouseover" then
        local vmActive = EllesmereUI.GetActiveVisibilityModes
            and EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
        local leaveAlpha
        if vmActive then
            -- Hover-gated set: hidden again on leave; the visibility pass
            -- re-evaluates the conditions on the next event.
            leaveAlpha = 0
        else
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
            leaveAlpha = keepShown and ns.ResolveFrameAlpha(s, InCombatLockdown()) or 0
        end
        ;(self._visWrap or self):SetAlpha(leaveAlpha)
        -- 3D models don't inherit parent alpha: hide/dim the portrait too
        local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
        if bd3d then bd3d:SetAlpha(leaveAlpha) end
        -- Mini-frame inheritance: the companion frame hides/dims with us
        local mini = ns.UF_MINI_OF and frames[ns.UF_MINI_OF[unitKey]]
        if mini then mini:SetAlpha(leaveAlpha) end
    end
    if self._tooltipTicker then self._tooltipTicker:Cancel(); self._tooltipTicker = nil end
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
    -- Per-unit frame source, resolved once for this build. When a unit is set to
    -- "blizzard" (leave Blizzard's default frame) or "hidden", the EllesmereUI
    -- frame is not spawned at all -- which is the ONLY way to keep Blizzard's own
    -- frame alive, because oUF:Spawn() permanently disables it.
    local playerFrameSource = ns.GetUnitFrameSource("player")
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
    -- Only take over the Blizzard class power bar when the EUI player frame is
    -- actually being spawned; otherwise leave it to Blizzard's player frame.
    if classPowerStyle == "blizzard" and playerFrameSource == "eui" then
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
        -- 12.0.7 gates SecureUnitButton's togglemenu; route right-click securely
        -- through a SecureActionButton proxy so the menu (and its protected items
        -- like Set Focus) work without taint.
        if EllesmereUI.AttachSecureUnitMenu then
            EllesmereUI.AttachSecureUnitMenu(frame)
        else
            frame:SetAttribute("*type2", "togglemenu")
        end
        frame:HookScript("OnEnter", UnitFrame_OnEnter)
        frame:HookScript("OnLeave", UnitFrame_OnLeave)
        -- Expose to click-casting via the standard global table. The EUI unit
        -- frames replace the Blizzard ones, which the click-cast engine registers
        -- by name -- but those are hidden, so the engine never reaches the visible
        -- frames. Registering ours here lets click-casting (EUI's engine when "All
        -- Unit Frames" is on, or Clique otherwise) apply the same bindings + the
        -- unbound-click suppression it uses on raid/party. The engine captures and
        -- restores each frame's native click attrs, so these keep their own
        -- defaults (no forced left-click target) when click-cast is off.
        if type(ClickCastFrames) ~= "table" then ClickCastFrames = {} end
        ClickCastFrames[frame] = true
    end

    -- Spawn each unit's EllesmereUI frame only when its source is "eui". A unit
    -- set to "blizzard" keeps Blizzard's own frame (we never call oUF:Spawn for
    -- it, so oUF never disables it); "hidden" removes Blizzard's frame too.
    oUF:SetActiveStyle("EllesmerePlayer")
    if playerFrameSource == "eui" then
        frames.player = oUF:Spawn("player", "EllesmereUIUnitFrames_Player")
    elseif playerFrameSource == "hidden" then
        oUF:DisableBlizzard("player")
    end

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
    if frames.player then
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
    end

    -- (Combat indicator overlay moved below the target/focus spawns -- the
    -- target frame does not exist yet at this point in the setup.)

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

        if frame.Portrait and frame.Portrait.backdrop and showPortrait and not frame.Portrait.backdrop._isInside then
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

    -- The expected parent for the Blizzard class power bar after positioning.
    -- Set by PositionClassPowerBar so the SetParent hook knows what's correct.
    -- MUST be declared before PositionClassPowerBar: a later declaration made
    -- the function assign a global while the hook read this always-nil local,
    -- so the hook fell back to frames.player even for UIParent-parented bars.
    local _cpExpectedParent = nil

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
            -- Above health bar, inside the frame -- pips stretch to fill health bar width
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
            -- "top" floats above the frame (like "bottom" floats below) -- does NOT become part of the frame
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
        -- Class power is a player-frame feature; if the player is on Blizzard's
        -- default frame (or hidden), there is no EUI frame to attach it to.
        if not frames.player then return end
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

    -- Durably suppress a live Blizzard child frame (target-of-target /
    -- focus-target). These are PROTECTED CHILDREN of TargetFrame/FocusFrame: when
    -- the parent uses Blizzard's source it stays alive and re-drives the child
    -- (TargetOfTargetMixin:Update) on every target change, so a one-shot Hide is
    -- undone. We unregister its events and re-hide on OnShow.
    --
    -- KNOWN LIMITATION (in-combat double frame): the child is a protected frame, so
    -- Hide() is blocked in combat. If the player changes target mid-combat, Blizzard
    -- (secure) re-Shows the native child and our OnShow re-hide cannot fire until
    -- PLAYER_REGEN_ENABLED -- so with the parent on Blizzard Default and this mini
    -- frame on EllesmereUI/Hidden, the native child stays visible for the WHOLE of
    -- combat (not just a flash): once Blizzard shows it we cannot re-hide until combat
    -- ends, so it sits alongside the EllesmereUI frame (or shows despite "Hidden").
    -- Not fixable without reparenting/overriding a secure frame in combat, so it's
    -- surfaced in the mini-frame "Frame Source" tooltip (see BuildFoTToTOptions), which
    -- recommends matching the parent's source instead of mixing them.
    local _suppressedChildren, _suppressWatcher
    local function SuppressBlizzardChildFrame(frame)
        if not frame then return end
        frame:UnregisterAllEvents()
        if not InCombatLockdown() then frame:Hide() end
        _suppressedChildren = _suppressedChildren or {}
        if not _suppressWatcher then
            _suppressWatcher = CreateFrame("Frame")
            _suppressWatcher:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if InCombatLockdown() then return end
                for f in pairs(_suppressedChildren) do f:Hide() end
            end)
        end
        if not _suppressedChildren[frame] then
            _suppressedChildren[frame] = true
            frame:HookScript("OnShow", function(self)
                if InCombatLockdown() then
                    _suppressWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
                else
                    self:Hide()
                end
            end)
        end
    end

    local targetFrameSource = ns.GetUnitFrameSource("target")
    if targetFrameSource == "eui" then
        oUF:SetActiveStyle("EllesmereTarget")
        frames.target = oUF:Spawn("target", "EllesmereUIUnitFrames_Target")
        ApplyFramePosition(frames.target, "target")
        SetupUnitMenu(frames.target, "target")
    elseif targetFrameSource == "hidden" then
        oUF:DisableBlizzard("target")
    end

    local focusFrameSource = ns.GetUnitFrameSource("focus")
    if focusFrameSource == "eui" then
        oUF:SetActiveStyle("EllesmereFocus")
        frames.focus = oUF:Spawn("focus", "EllesmereUIUnitFrames_Focus")
        ApplyFramePosition(frames.focus, "focus")
        SetupUnitMenu(frames.focus, "focus")
    elseif focusFrameSource == "hidden" then
        oUF:DisableBlizzard("focus")
    end

    -- Combat indicator overlay on the player + target frames. Each frame shows
    -- its OWN unit's combat state: player via the exact regen events, target via
    -- UNIT_FLAGS (combat flag changes) + PLAYER_TARGET_CHANGED re-evaluation.
    -- Target defaults to "none" (opt-in); player keeps its legacy default.
    -- Must run after the target frame is spawned (right above).
    for _, ciDef in ipairs({
        { unit = "player", defStyle = "standard" },
        { unit = "target", defStyle = "none" },
    }) do
        local pf = frames[ciDef.unit]
        if pf then
        local ciUnit = ciDef.unit
        local ciDefStyle = ciDef.defStyle
        local ps = db.profile[ciUnit]
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
            local style = ps.combatIndicatorStyle or ciDefStyle
            if style == "none" then combat:Hide(); return end

            local colorMode = ps.combatIndicatorColor or "custom"
            local sz = ps.combatIndicatorSize or 22
            local ox = ps.combatIndicatorX or 0
            local oy = ps.combatIndicatorY or 0
            local pos = ps.combatIndicatorPosition or "healthbar"

            combat:SetSize(sz, sz)
            combat:ClearAllPoints()

            -- "healthbar" is the stored value shown as "Center" in the dropdown;
            -- "center" is a render alias for it.
            if pos == "portrait" and pf.Portrait then
                combat:SetPoint("CENTER", pf.Portrait, "CENTER", ox, oy)
            elseif pos == "textbar" then
                combat:SetPoint("CENTER", pf._btb or pf, "CENTER", ox, oy)
            elseif pos == "healthbar" or pos == "center" then
                combat:SetPoint("CENTER", pf.Health or pf, "CENTER", ox, oy)
            else
                local anchor =
                    (pos == "topright"    and "TOPRIGHT")    or
                    (pos == "bottomleft"  and "BOTTOMLEFT")  or
                    (pos == "bottomright" and "BOTTOMRIGHT") or
                    "TOPLEFT"
                combat:SetPoint(anchor, pf.Health or pf, anchor, ox, oy)
            end

            -- Determine texture file (always use -custom / white base).
            -- Class theming resolves the FRAME's unit (player class on the
            -- player frame, current target's class on the target frame).
            local _, classToken = UnitClass(ciUnit)
            -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/Square =
            -- combat0..5) are shown exactly as authored: no class theming, no tint, no
            -- desaturation. Standard/Class Theme below are tinted by the colour mode.
            if style:find("^combat%d") then
                combat:SetTexture(COMBAT_MEDIA .. style .. ".tga")
                combat:SetTexCoord(0, 1, 0, 1)
                if combat.SetDesaturated then combat:SetDesaturated(false) end
                combat:SetVertexColor(1, 1, 1, 1)
            else
                if style == "class" then
                    combat:SetTexture(COMBAT_MEDIA .. "combat-indicator-class-custom.png")
                    local coords = classToken and CLASS_FULL_COORDS[classToken]
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
                    local cc = (classToken and EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
                    combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
                elseif colorMode == "custom" then
                    local cc = ps.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                    combat:SetVertexColor(cc.r, cc.g, cc.b, 1)
                else
                    combat:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
        pf._applyCombatTexture = ApplyCombatTexture

        -- Event frame for combat state changes (reuse existing)
        if not pf._combatEventFrame then
            pf._combatEventFrame = CreateFrame("Frame", nil, pf)
            if ciUnit == "player" then
                pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                pf._combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                -- UNIT_FLAGS fires on the unit's combat flag flips; target
                -- change re-evaluates for the new unit.
                pf._combatEventFrame:RegisterUnitEvent("UNIT_FLAGS", ciUnit)
                pf._combatEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
            end
        end
        local combatFrame = pf._combatEventFrame
        combatFrame:SetScript("OnEvent", function()
            local style = ps.combatIndicatorStyle or ciDefStyle
            if style ~= "none" and UnitAffectingCombat(ciUnit) then
                ApplyCombatTexture()
                combat:Show()
            else
                combat:Hide()
            end
        end)

        -- Set correct initial state
        local style = ps.combatIndicatorStyle or ciDefStyle
        if style ~= "none" and UnitAffectingCombat(ciUnit) then
            ApplyCombatTexture()
            combat:Show()
        end
        end
    end

    -- Leader indicator (crown when unit is the group/raid leader). oUF doesn't
    -- attach LeaderIndicator dynamically after Spawn(), so we drive the texture
    -- ourselves: own events, own UnitIsGroupLeader check, own show/hide.
    -- Must run after target frame is spawned (right above) so the texture can
    -- be parented to it.
    do
        local _leaderUnits = {}

        local function _leaderRefresh(uf)
            local s = uf and uf._leaderSettings
            if not (uf and uf._leaderIndicator and s) then return end
            local tex = uf._leaderIndicator
            if s.leaderIndicatorEnabled == false then tex:Hide(); return end
            local unit = uf.unit
            local isLeader = UnitIsGroupLeader(unit)
            local isAssist = UnitIsGroupAssistant(unit)
            if isLeader and not issecretvalue(isLeader) then
                tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                tex:Show()
            elseif isAssist and not issecretvalue(isAssist) then
                tex:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                tex:Show()
            else
                tex:Hide()
            end
        end

        local function _setupLeaderIndicator(uf, settings)
            if not (uf and uf.Health and settings) then return end
            if not uf._leaderIndicator then
                -- Parent to the health-bar text overlay (same frame level as the
                -- health text) on a higher OVERLAY sublevel than the text strings
                -- (which are sublevel 0), so the crown draws just above the text
                -- instead of beneath it. Falls back to the frame if the text
                -- overlay isn't present.
                local leaderParent = uf._textOverlay or uf
                local leaderTex = leaderParent:CreateTexture(nil, "OVERLAY", nil, 7)
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

    local petFrameSource = ns.GetUnitFrameSource("pet")
    if petFrameSource == "eui" then
        oUF:SetActiveStyle("EllesmerePet")
        frames.pet = oUF:Spawn("pet", "EllesmereUIUnitFrames_Pet")
        ApplyFramePosition(frames.pet, "pet")
        SetupUnitMenu(frames.pet, "pet")
    elseif petFrameSource == "hidden" then
        oUF:DisableBlizzard("pet")
    end

    local totFrameSource = ns.GetUnitFrameSource("targettarget")
    if totFrameSource == "eui" then
        oUF:SetActiveStyle("EllesmereTargetTarget")
        frames.targettarget = oUF:Spawn("targettarget", "EllesmereUIUnitFrames_TargetTarget")
        ApplyFramePosition(frames.targettarget, "targettarget")
        SetupUnitMenu(frames.targettarget, "targettarget")
    end
    -- Blizzard's target-of-target is a child of TargetFrame. When the target
    -- frame itself is EUI or hidden, oUF/our code already disabled TargetFrame so
    -- the child is gone with it. It only needs suppressing when the target uses
    -- Blizzard's live frame but the user does NOT want Blizzard's ToT (EUI or
    -- hidden) -- otherwise the EUI ToT and Blizzard's would both show.
    if totFrameSource ~= "blizzard" and targetFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(TargetFrame and TargetFrame.totFrame)
    end

    local ftFrameSource = ns.GetUnitFrameSource("focustarget")
    if ftFrameSource == "eui" then
        oUF:SetActiveStyle("EllesmereFocusTarget")
        frames.focustarget = oUF:Spawn("focustarget", "EllesmereUIUnitFrames_FocusTarget")
        ApplyFramePosition(frames.focustarget, "focustarget")
        SetupUnitMenu(frames.focustarget, "focustarget")
    end
    -- Same as target-of-target: FocusFrame's native focus-target is a child of
    -- FocusFrame, so it only needs suppressing when focus uses Blizzard's live
    -- frame and the user does not want the native focus-target.
    if ftFrameSource ~= "blizzard" and focusFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(FocusFrame and FocusFrame.totFrame)
    end

    local bossFrameSource = ns.GetUnitFrameSource("boss")
    if bossFrameSource == "eui" then
    oUF:SetActiveStyle("EllesmereBoss")
    local bossPos = db.profile.positions.boss

    local bossSettings = db.profile.boss or {}
    local barHeight = (bossSettings.healthHeight or 34) + (bossSettings.powerHeight or 6) + (bossSettings.castbarHeight or 14)
    local gap = 10
    local spacing = db.profile.bossSpacing or (barHeight + gap)
    local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
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
                if bossStackDir == "up" then
                    bossFrame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                else
                    bossFrame:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                end
            end
        end

        SetupUnitMenu(bossFrame, bossUnit)
    end
    elseif bossFrameSource == "hidden" then
        -- Disabling boss1 makes oUF hide the whole BossTargetFrameContainer
        -- (and all five Boss*TargetFrame children).
        oUF:DisableBlizzard("boss1")
    end

    -- Kill Blizzard's boss frames for every source except "blizzard" (where the
    -- user wants them). For "eui" oUF already disabled them at spawn; this pass
    -- is belt-and-suspenders and also runs for "hidden".
    if bossFrameSource ~= "blizzard" then
        for i = 1, 5 do
            local blizzBoss = _G["Boss" .. i .. "TargetFrame"]
            if blizzBoss then
                blizzBoss:UnregisterAllEvents()
                blizzBoss:Hide()
            end
        end
    end

    -- Apply user-selected frame strata to all unit frames
    local ufStrata = db.profile.frameStrata or "MEDIUM"
    for unitKey, frame in pairs(frames) do
        if type(frame) == "table" and frame.SetFrameStrata then
            -- Mini frames (ToT / Focus Target / Pet) can override the global strata.
            local strata = ufStrata
            if unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "pet" then
                local us = db.profile[unitKey]
                if us and us.frameStrata then strata = us.frameStrata end
            end
            frame:SetFrameStrata(strata)
            if frame.BottomTextBar and frame.BottomTextBar._isDetached then
                if db.profile.enableCustomBarStratas then
                    frame.BottomTextBar:SetFrameStrata(db.profile.detachedTextBarStrata or "DIALOG")
                else
                    frame.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar -- see the matching comment
            -- in the other frameStrata-apply pass above for why this is needed.
            if frame.Power then
                local us2 = GetSettingsForUnit(unitKey)
                local ppPos = us2 and us2.powerPosition or "below"
                if ppPos == "detached_top" or ppPos == "detached_bottom" then
                    if db.profile.enableCustomBarStratas then
                        frame.Power:SetFrameStrata(db.profile.detachedPowerStrata or "HIGH")
                    else
                        frame.Power:SetFrameStrata("MEDIUM")
                    end
                end
            end
            -- The cast bar is a child of the frame, so the SetFrameStrata above
            -- reset it to the frame's strata. Lift player/target/focus cast bars
            -- to HIGH so they never hide behind other MEDIUM-strata frames -- unless
            -- the global "Raise Cast Bar Strata (All)" toggle is off, in which case the
            -- cast bar is explicitly left at the frame's strata.
            if frame.Castbar and (unitKey == "player" or unitKey == "target" or unitKey == "focus") then
                local cbg = frame.Castbar:GetParent()
                if cbg then
                    if db.profile.raiseCastbarStrata ~= false then
                        cbg:SetFrameStrata("HIGH")
                    else
                        cbg:SetFrameStrata(strata)
                    end
                end
            end
            -- SetFrameStrata re-stacks children; lift the raid marker holder back
            -- above the text overlay so the marker is never hidden behind name/health text.
            if frame._raidMarkerHolder and frame._textOverlay then
                frame._raidMarkerHolder:SetFrameLevel(frame._textOverlay:GetFrameLevel() + 5)
            end
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

    -- Boss frames: same absorb refresh, styled from the TARGET donor block
    -- and gated by the "Show on Boss Frames" toggle (nil = enabled).
    do
        local bossOff = db.profile.boss and db.profile.boss.showAbsorbs == false
        local donor = db.profile.target
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f and f.HealthPrediction and f.HealthPrediction.damageAbsorb then
                local absStyle
                if not bossOff and donor then absStyle = donor.showPlayerAbsorb end
                if absStyle and absStyle ~= "none" then
                    ApplyAbsorbStyle(f.HealthPrediction.damageAbsorb, absStyle, donor)
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
                if f.HealthPrediction.ForceUpdate then
                    f.HealthPrediction:ForceUpdate()
                end
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
    -- Companion mini frame for each main frame: the mini inherits its
    -- parent's FULL effective visibility (modes, multi-selections, hide
    -- options, fade, mouseover reveals, Never/disabled).
    ns.UF_MINI_OF = { player = "pet", target = "targettarget", focus = "focustarget" }

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
        -- One state table per pass for the multi-select visibility engine
        local visState = { inCombat = _ufInCombat, inRaid = inRaid, inParty = inParty }
        for _, unitKey in ipairs({"player", "target", "focus"}) do
            local s = db.profile[unitKey]
            local frame = frames[unitKey]
            if frame and enabled2[unitKey] ~= false and s then
                local hiddenByOpts = EllesmereUI and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(s)
                local vis = s.barVisibility or "always"

                -- Multi-select / dragonriding path: non-nil = engine-owned.
                -- nil = legacy single mode, untouched.
                local ext = EllesmereUI.EvalVisibilityExtended
                    and EllesmereUI.EvalVisibilityExtended(s, "barVisibility", visState, EllesmereUI.VIS_CAPS_INCLUSIVE)

                -- Secure condition driver: an engine-owned selection
                -- compiles into a state-visibility driver (the action bar
                -- mechanism), replacing the frame's unit watch. A
                -- driver-hidden frame is TRULY hidden -- it absorbs no
                -- clicks -- and the secure engine flips it mid-combat
                -- natively. Mouseover sets keep the frame shown while their
                -- conditions pass (the compiler ignores the mouseover key);
                -- the alpha bucket + hover handlers do the revealing.
                -- Registration is out-of-combat only; a selection changed
                -- during combat rides on alpha until the regen pass
                -- registers the driver.
                local drvSet = EllesmereUI.GetActiveVisibilityModes
                    and EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
                -- Condition scalars ride the driver too: dragonriding (the
                -- engine owns it everywhere) and the combat pair, whose
                -- legacy alpha-hide left an invisible click-absorbing frame
                -- out of combat. Visibility is unchanged; the driver just
                -- hides for real and flips frame-exactly at the combat edge.
                if not drvSet and (vis == "show_dragonriding" or vis == "show_not_dragonriding"
                    or vis == "in_combat" or vis == "out_of_combat") then
                    drvSet = { [vis] = true }
                end
                local wantDriver
                if drvSet and EllesmereUI.BuildVisibilityDriverString then
                    wantDriver = EllesmereUI.BuildVisibilityDriverString(
                        "[@" .. unitKey .. ",noexists] hide; ", drvSet)
                end
                if frame._euiVisDriver ~= wantDriver and not isLocked then
                    if wantDriver then
                        UnregisterUnitWatch(frame)
                        RegisterAttributeDriver(frame, "state-visibility", wantDriver)
                    else
                        UnregisterAttributeDriver(frame, "state-visibility")
                        RegisterUnitWatch(frame)
                    end
                    frame._euiVisDriver = wantDriver
                end

                -- Whole-frame out-of-combat fade: the alpha to use whenever the
                -- frame is "shown" below. 1 unless "Fade Out of Combat" is on and
                -- we are out of combat, in which case the chosen oocAlpha. Uses the
                -- event-tracked _ufInCombat (authoritative on regen transitions,
                -- which lead InCombatLockdown()) so the fade flips instantly.
                local shownAlpha = ns.ResolveFrameAlpha(s, _ufInCombat)

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
                local bodyAlpha
                if ext == "mouseover" then
                    -- Hover-gated set with passing conditions: hidden until
                    -- hovered (the hover handlers reveal it).
                    bodyAlpha = 0
                elseif ext ~= nil then
                    if frame._euiVisDriver then
                        -- The driver owns hiding; alpha only carries the
                        -- ooc fade (hide-options still force 0 below).
                        bodyAlpha = shownAlpha
                    else
                        -- Driver not registered yet (selection changed in
                        -- combat): alpha covers until the regen pass.
                        bodyAlpha = (not hiddenByOpts and ext) and shownAlpha or 0
                    end
                elseif vis == "in_combat" then
                    bodyAlpha = (not hiddenByOpts and _ufInCombat) and shownAlpha or 0
                elseif vis == "out_of_combat" then
                    bodyAlpha = (not hiddenByOpts and not _ufInCombat) and shownAlpha or 0
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
                        bodyAlpha = 0
                    elseif hasAnyHideOpt then
                        bodyAlpha = shownAlpha
                    else
                        bodyAlpha = 0
                    end
                else
                    -- Non-combat modes: restore the resting alpha (full, or the
                    -- out-of-combat fade); Show/Hide controls visibility below.
                    bodyAlpha = shownAlpha
                end

                -- Alpha-only hide for the "visHide*" overrides (mounted,
                -- no target, housing, etc). Force alpha 0 now so the frame
                -- still looks hidden, but leave the secure Show/Hide state
                -- alone below -- otherwise a dismount that lands inside a
                -- combat lockdown would leave the frame permanently hidden
                -- (Show/SetAttribute are restricted in combat, so we can't
                -- re-show it until combat ends).
                if hiddenByOpts then
                    bodyAlpha = 0
                end
                alphaTarget:SetAlpha(bodyAlpha)

                -- 3D PlayerModel frames don't inherit parent alpha, so the
                -- model must mirror the EXACT body alpha computed above --
                -- every alpha-hidden state (engine-owned, in_combat,
                -- out_of_combat, mouseover, hide-opts) would otherwise leave
                -- a floating portrait over an invisible frame. The hover
                -- handlers mirror it too when they reveal a mouseover frame.
                local bd3d = frame.Portrait and frame.Portrait.backdrop and frame.Portrait.backdrop._3d
                if bd3d then
                    bd3d:SetAlpha(bodyAlpha)
                end

                -- Show/Hide and SetAttribute are restricted during lockdown.
                -- When a condition driver is registered it owns Show/Hide
                -- entirely -- a manual toggle would de-sync it until its
                -- next re-evaluation -- so this whole bucket steps aside.
                if not isLocked and not frame._euiVisDriver then
                    local shouldShow
                    if ext ~= nil then
                        -- Engine-owned: frame stays secure-Shown; the alpha
                        -- bucket above drives visibility.
                        shouldShow = true
                    elseif vis == "never" then
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

                local mini = frames[ns.UF_MINI_OF[unitKey]]

                -- The companion mini frame gets its own condition driver
                -- (parent conditions + its own unit existence), so a
                -- condition-hidden mini absorbs no clicks either.
                if mini then
                    local miniWant
                    if drvSet and EllesmereUI.BuildVisibilityDriverString then
                        miniWant = EllesmereUI.BuildVisibilityDriverString(
                            "[@" .. ns.UF_MINI_OF[unitKey] .. ",noexists] hide; ", drvSet)
                    end
                    if mini._euiVisDriver ~= miniWant and not isLocked then
                        if miniWant then
                            UnregisterUnitWatch(mini)
                            RegisterAttributeDriver(mini, "state-visibility", miniWant)
                        else
                            UnregisterAttributeDriver(mini, "state-visibility")
                            RegisterUnitWatch(mini)
                        end
                        mini._euiVisDriver = miniWant
                    end
                end

                -- Mini-frame visibility inheritance: pet follows player,
                -- target-of-target follows target, focus-target follows
                -- focus. The mini mirrors the parent's effective state --
                -- the body alpha computed above (modes, multi-selections,
                -- hide options, ooc fade, mouseover default) plus the
                -- secure Show/Hide bucket via IsShown() -- so every way the
                -- parent hides takes its mini along. RegisterUnitWatch
                -- keeps owning the mini's own Show/Hide (unit existence);
                -- alpha never conflicts with it. Hover reveals mirror in
                -- the OnEnter/OnLeave handlers.
                if mini then
                    mini:SetAlpha(frame:IsShown() and bodyAlpha or 0)
                end
            elseif frame then
                -- Parent disabled ("Never" clears enabledFrames): a
                -- leftover condition driver must not keep re-showing the
                -- frame, so pin it to a constant hide. Frames that never
                -- had a driver keep the legacy disabled path untouched.
                -- The mini inherits both.
                if not isLocked and frame._euiVisDriver and frame._euiVisDriver ~= "hide" then
                    RegisterAttributeDriver(frame, "state-visibility", "hide")
                    frame._euiVisDriver = "hide"
                end
                local mini = frames[ns.UF_MINI_OF[unitKey]]
                if mini then
                    if not isLocked and mini._euiVisDriver and mini._euiVisDriver ~= "hide" then
                        RegisterAttributeDriver(mini, "state-visibility", "hide")
                        mini._euiVisDriver = "hide"
                    end
                    mini:SetAlpha(0)
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
        -- Dragonriding visibility modes: capability edge plus the airborne
        -- edge (probed at load in EllesmereUI_Visibility.lua)
        frames._visFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
        if EllesmereUI._hasGlidingEvent then
            frames._visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
        end
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
            if frame.ExtraText and s and s.extraTextClassColor ~= nil then
                ApplyClassColor(frame.ExtraText, unitKey, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
            end
            -- Text bar class colors
            local btb = frame._btb
            if btb and s then
                if btb.LeftText then ApplyClassColor(btb.LeftText, unitKey, s.btbLeftClassColor, s.btbLeftColorR, s.btbLeftColorG, s.btbLeftColorB) end
                if btb.RightText then ApplyClassColor(btb.RightText, unitKey, s.btbRightClassColor, s.btbRightColorR, s.btbRightColorG, s.btbRightColorB) end
                if btb.CenterText then ApplyClassColor(btb.CenterText, unitKey, s.btbCenterClassColor, s.btbCenterColorR, s.btbCenterColorG, s.btbCenterColorB) end
                -- Power color must win for power-colored slots: the ApplyClassColor
                -- calls above drop any non-class slot to its custom/white color, which
                -- clobbers the power color PostUpdateColor set. Re-apply power color
                -- after (class -> power, same order as ApplyBTBTextPositions). The
                -- per-slot early-out keeps it free for slots not using power color.
                if btb._applyBTBPowerColors then btb._applyBTBPowerColors(s) end
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

    -- Target-of-target / focus-target text class colors must re-apply when their
    -- unit changes or first becomes available (login/reload). Unlike target/focus,
    -- the mini frames have no PLAYER_*_CHANGED of their own, so a class color set at
    -- style time -- when "targettarget"/"focustarget" was not yet a resolvable
    -- player -- falls back to white and never recovers (the reported ToT center
    -- text bug). Re-apply on the parent's target change and on its UNIT_TARGET.
    local function ReapplyFrameTextClassColors(unitKey)
        local frame = frames[unitKey]
        local s = frame and db.profile[unitKey]
        if not s then return end
        if frame.LeftText and s.leftTextClassColor ~= nil then
            ApplyClassColor(frame.LeftText, unitKey, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        end
        if frame.RightText and s.rightTextClassColor ~= nil then
            ApplyClassColor(frame.RightText, unitKey, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        end
        if frame.CenterText and s.centerTextClassColor ~= nil then
            ApplyClassColor(frame.CenterText, unitKey, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        end
    end
    if not frames._miniTextClassUpdater then
        frames._miniTextClassUpdater = CreateFrame("Frame")
        frames._miniTextClassUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._miniTextClassUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
        frames._miniTextClassUpdater:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
    end
    frames._miniTextClassUpdater:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_TARGET_CHANGED" then
            ReapplyFrameTextClassColors("targettarget")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            ReapplyFrameTextClassColors("focustarget")
        elseif arg1 == "target" then
            ReapplyFrameTextClassColors("targettarget")
        elseif arg1 == "focus" then
            ReapplyFrameTextClassColors("focustarget")
        end
    end)

    -- Boss Hover/Target border: refresh each boss frame's target state when the
    -- player's target changes or boss units (dis)appear. Hover is handled by the
    -- OnEnter/OnLeave hooks; this only tracks target. Both borders default off, so
    -- this is a cheap no-op unless the user enabled a boss border.
    -- Defined on ns (not a local) to avoid the Lua 200-local cap.
    ns.UpdateBossTargetBorders = function()
        local s = db.profile.boss
        for i = 1, 5 do
            local bUnit = "boss" .. i
            local f = frames[bUnit]
            if f then
                if f.unifiedBorder then
                    local isT = UnitIsUnit(bUnit, "target")
                    f._isTarget = (isT and not issecretvalue(isT)) and true or false
                    ns.ApplyBossBorderState(f)
                end
                if s then
                    if f.LeftText and s.leftTextClassColor ~= nil then
                        ApplyClassColor(f.LeftText, bUnit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
                    end
                    if f.RightText and s.rightTextClassColor ~= nil then
                        ApplyClassColor(f.RightText, bUnit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
                    end
                    if f.CenterText and s.centerTextClassColor ~= nil then
                        ApplyClassColor(f.CenterText, bUnit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
                    end
                end
            end
        end
    end
    if not frames._bossTargetBorderUpdater then
        frames._bossTargetBorderUpdater = CreateFrame("Frame")
        frames._bossTargetBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frames._bossTargetBorderUpdater:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        frames._bossTargetBorderUpdater:RegisterEvent("UNIT_TARGETABLE_CHANGED")
        frames._bossTargetBorderUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    frames._bossTargetBorderUpdater:SetScript("OnEvent", ns.UpdateBossTargetBorders)
    ns.UpdateBossTargetBorders()

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
        -- A reload restyles the boss frames and re-colors their health to the
        -- player's class color (preview rides on unit="player") + re-tags the
        -- name. Re-assert the preview (red color + fake name) so a settings
        -- change doesn't revert it. Secret-safe: no health values are read.
        if ns._bossPreviewActive and ns.SetBossPreview then ns.SetBossPreview(true) end
        -- ReloadFrames rebuilds frames but never touches the top-level wrapper /
        -- 3D-portrait alpha, so recompute the out-of-combat fade here. Without
        -- this, a profile/spec swap (or first switch to a 3D portrait, whose
        -- PlayerModel is created at alpha 1) leaves player/target/focus stuck at
        -- the old opacity until the next combat/target/zone event. Safe from the
        -- throttle: UpdateFrameVisibility guards its restricted Show/Hide behind
        -- InCombatLockdown, and SetAlpha is unrestricted.
        if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
        -- 12.1 aura containers reload with every real pass (direct call --
        -- ns.ReloadFrames is just the throttle-arming stub, so wrapping it
        -- from the container file is timing-unreliable).
        if ns.UF_ReloadAllAuraContainers then ns.UF_ReloadAllAuraContainers() end
        -- Player private auras re-register with fresh geometry (one boolean
        -- check + return when disabled).
        if ns.PlayerPA_Apply then ns.PlayerPA_Apply() end
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
    local FAKE_DEBUFF_STACKS = { [2] = 3 }          -- one fake stack (icon 2 only)
    local FAKE_DEBUFF_FRACS  = { 0.35, 0.62, 0.88 } -- static fake swipe fraction remaining
    local FAKE_DEBUFF_SECS   = { 8, 15, 23 }         -- static fake duration-text seconds
    local function AttachFakeDebuffs(frame)
        -- Tear down any prior holder so size/anchor refresh on every call.
        if frame._previewDebuffs then
            frame._previewDebuffs:Hide()
            frame._previewDebuffs:SetParent(nil)
            frame._previewDebuffs = nil
        end
        -- Suppress the real (player-unit) debuffs while the fake overlay is up so
        -- the preview shows exactly the fake set. Restored by ReloadFrames when
        -- the preview is disabled.
        if frame.Debuffs then
            if frame:IsElementEnabled("Debuffs") then frame:DisableElement("Debuffs") end
            frame.Debuffs:Hide()
            frame.Debuffs.num = 0
        end
        if ns.UF_HideAuraContainers then ns.UF_HideAuraContainers(frame) end
        local settings = db.profile.boss or {}
        local simpleMode = ns.GetBossSimpleDebuffMode(settings)
        local simple = simpleMode ~= "none"
        -- No debuffs shown at all (Simple Debuff Display None + Debuffs Location
        -- None): the prior holder was already torn down above, so bail without
        -- drawing any fake debuffs (mirrors AttachFakeBuffs' none guard).
        if not simple and (settings.debuffAnchor or "bottomleft") == "none" then return end
        local dOffX = settings.debuffOffsetX or 0
        local dOffY = settings.debuffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular
        -- debuff offsets for existing users) so the preview matches live.
        if simple then dOffX, dOffY = ns.GetBossSimpleDebuffOffset(settings) end
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss debuffs.
            iconSize = PP.Scale((settings.healthHeight or 34) + powerH)
        else
            iconSize = settings.debuffSize or 22
        end
        local count = #FAKE_DEBUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = PP.FromPixels(ns.GetBossDebuffSpacing(settings, simple))
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetSize(iconSize * count + iconGap * (count - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview debuffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holder:SetFrameLevel(frame:GetFrameLevel() + 13)
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
            -- they never encroach on the cast bar area. Left grows off the
            -- frame's left edge; Right grows off the right edge.
            if simpleMode == "right" then
                holder:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1 + dOffX, dOffY)
            else
                holder:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1 + dOffX, dOffY)
            end
        else
            local dAnc = settings.debuffAnchor or "bottomleft"
            if dAnc == "topleft" then
                holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "topright" then
                holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "bottomleft" then
                holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "bottomright" then
                holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "right" then
                holder:SetPoint("LEFT", frame, "RIGHT", gap + dOffX, 0 + dOffY)
            else  -- "left" or fallback
                holder:SetPoint("RIGHT", frame, "LEFT", -gap + dOffX, 0 + dOffY)
            end
        end
        -- Cooldown-text + stack settings, mode-aware so the preview mirrors the
        -- live boss aura buttons (simple keys in Simple Debuff Display, regular
        -- debuff keys otherwise).
        local showCD, cdSize, cdOffX, cdOffY
        if simple then
            showCD = settings.simpleDebuffShowCooldownText
            cdSize = settings.simpleDebuffCooldownTextSize or 14
            cdOffX = settings.simpleDebuffCooldownTextOffsetX or 0
            cdOffY = settings.simpleDebuffCooldownTextOffsetY or 0
        else
            showCD = settings.debuffShowCooldownText
            cdSize = settings.debuffCooldownTextSize or 10
            cdOffX = settings.debuffCooldownTextOffsetX or 0
            cdOffY = settings.debuffCooldownTextOffsetY or 0
        end
        local stackSize = settings.debuffStackTextSize or 14
        local stackOffX = settings.debuffStackTextOffsetX or 0
        local stackOffY = settings.debuffStackTextOffsetY or 0
        local stackPos = settings.debuffStackTextPosition
        local cdTextColor = settings.debuffCooldownTextColor or {r=1, g=1, b=1}
        local stackTextColor = settings.debuffStackTextColor or {r=1, g=1, b=1}
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        local now = GetTime()
        for idx, spellID in ipairs(FAKE_DEBUFF_SPELLS) do
            local iconFrame = CreateFrame("Frame", nil, holder)
            iconFrame:SetSize(iconSize, iconSize)
            if simpleMode == "right" then
                iconFrame:SetPoint("LEFT", holder, "LEFT", (idx - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("RIGHT", holder, "RIGHT", -(idx - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holder:GetFrameLevel())
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            local tex = GetSpellTexture and GetSpellTexture(spellID)
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            if tex then icon:SetTexture(tex) end
            local z = settings.debuffIconZoom or 0.07
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
            -- Static fake cooldown swipe: a huge duration parked at a fixed
            -- fraction so the wedge never visibly moves. Native countdown
            -- numbers stay hidden; the duration text below is a manual static
            -- FontString instead.
            local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
            cd:SetAllPoints(iconFrame)
            -- Swipe sits above the border (border at +1, PP container at +2) so
            -- the layering matches the live boss aura buttons.
            cd:SetFrameLevel(iconFrame:GetFrameLevel() + 3)
            cd:SetDrawEdge(false)
            cd:SetDrawBling(false)
            cd:SetReverse(false)
            cd:SetDrawSwipe(true)
            cd:SetSwipeColor(0, 0, 0, 0.6)
            cd:SetHideCountdownNumbers(true)
            local frac = FAKE_DEBUFF_FRACS[idx] or 0.6
            cd:SetCooldown(now - 3600 * (1 - frac), 3600)
            -- Text host above the swipe AND the border container so the
            -- duration/stack text renders over the icon border, not under it.
            local textHost = CreateFrame("Frame", nil, iconFrame)
            textHost:SetAllPoints(iconFrame)
            textHost:SetFrameLevel(iconFrame:GetFrameLevel() + 4)
            local durText = textHost:CreateFontString(nil, "OVERLAY")
            durText:SetDrawLayer("OVERLAY", 7)
            EllesmereUI.ApplyIconTextFont(durText, fontPath, cdSize, "unitFrames")
            durText:SetPoint("CENTER", iconFrame, "CENTER", cdOffX, cdOffY)
            durText:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)
            durText:SetText(FAKE_DEBUFF_SECS[idx] or 10)
            if not showCD then durText:Hide() end
            -- Stack text on a single icon only (looks natural; most debuffs are
            -- unstacked). Driven by the Stack Size / Stack X / Stack Y controls.
            if FAKE_DEBUFF_STACKS[idx] then
                local stack = textHost:CreateFontString(nil, "OVERLAY")
                stack:SetDrawLayer("OVERLAY", 7)
                EllesmereUI.ApplyIconTextFont(stack, fontPath, stackSize, "unitFrames")
                ns.ApplyStackAnchor(stack, iconFrame, stackPos, stackOffX, stackOffY)
                stack:SetTextColor(stackTextColor.r, stackTextColor.g, stackTextColor.b)
                stack:SetText(FAKE_DEBUFF_STACKS[idx])
            end
            -- Border just above the icon; its PP container renders at border+1
            -- (iconFrame+2), below the swipe and text host so both stay on top.
            local border = CreateFrame("Frame", nil, iconFrame)
            border:SetAllPoints(icon)
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            if PP and PP.CreateBorder then PP.CreateBorder(border, 0, 0, 0, 1) end
        end
        frame._previewDebuffs = holder
    end
    local function DetachFakeDebuffs(frame)
        if frame._previewDebuffs then frame._previewDebuffs:Hide() end
    end

    -- Fake buff icons for the boss preview. Two square icons anchored where the
    -- real Buffs frame would live, sized to the buff size. Created on demand and
    -- torn down on preview disable. Capped at 2 regardless of Max Count.
    local FAKE_BUFF_SPELLS = { 21562, 1459 }  -- Power Word: Fortitude, Arcane Intellect
    local function AttachFakeBuffs(frame)
        if frame._previewBuffs then
            frame._previewBuffs:Hide()
            frame._previewBuffs:SetParent(nil)
            frame._previewBuffs = nil
        end
        -- Suppress the real (player-unit) buffs while preview is up. Restored by
        -- ReloadFrames when the preview is disabled.
        if frame.Buffs then
            if frame:IsElementEnabled("Buffs") then frame:DisableElement("Buffs") end
            frame.Buffs:Hide()
            frame.Buffs.num = 0
        end
        if ns.UF_HideAuraContainers then ns.UF_HideAuraContainers(frame) end
        local settings = db.profile.boss or {}
        local simpleMode = ns.GetBossSimpleBuffMode(settings)
        local simple = simpleMode ~= "none"
        -- Simple Buff Display overrides Buffs Location, so only bail on the
        -- location/visibility guards when simple mode is off.
        if not simple and (settings.showBuffs == false or (settings.buffAnchor or "topleft") == "none") then return end
        local anchor = settings.buffAnchor or "topleft"
        local bOffX = settings.buffOffsetX or 0
        local bOffY = settings.buffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular buff
        -- offsets for existing users) so the preview matches live.
        if simple then bOffX, bOffY = ns.GetBossSimpleBuffOffset(settings) end
        local powerPos = settings.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (settings.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss buffs.
            iconSize = PP.Scale((settings.healthHeight or 34) + powerH)
        else
            iconSize = settings.buffSize or 22
        end
        local count = #FAKE_BUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = PP.FromPixels(ns.GetBossBuffSpacing(settings, simple))
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetSize(iconSize * count + iconGap * (count - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview buffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holder:SetFrameLevel(frame:GetFrameLevel() + 13)
        holder:ClearAllPoints()
        local castBg = frame.Castbar and frame.Castbar:GetParent()
        local castbarH = (settings.showCastbar ~= false and castBg)
                         and castBg:GetHeight() or 0
        if simple then
            -- Align the column with the health bar top, side-based (matches the
            -- live runtime + Simple Debuff Display).
            if simpleMode == "right" then
                holder:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1 + bOffX, bOffY)
            else
                holder:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1 + bOffX, bOffY)
            end
        elseif anchor == "topleft" then
            holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0 + bOffX, gap + bOffY)
        elseif anchor == "topright" then
            holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0 + bOffX, gap + bOffY)
        elseif anchor == "bottomleft" then
            holder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "bottomright" then
            holder:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "right" then
            holder:SetPoint("LEFT", frame, "RIGHT", gap + bOffX, 0 + bOffY)
        else  -- "left" or fallback
            holder:SetPoint("RIGHT", frame, "LEFT", -gap + bOffX, 0 + bOffY)
        end
        for idx, spellID in ipairs(FAKE_BUFF_SPELLS) do
            local iconFrame = CreateFrame("Frame", nil, holder)
            iconFrame:SetSize(iconSize, iconSize)
            if simple and simpleMode == "left" then
                -- Left mode grows leftward from the right edge of the holder.
                iconFrame:SetPoint("RIGHT", holder, "RIGHT", -(idx - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("LEFT", holder, "LEFT", (idx - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holder:GetFrameLevel())
            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            local tex = GetSpellTexture and GetSpellTexture(spellID)
                     or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
            if tex then icon:SetTexture(tex) end
            local z = settings.buffIconZoom or 0.07
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
            local border = CreateFrame("Frame", nil, iconFrame)
            border:SetAllPoints(icon)
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            if PP and PP.CreateBorder then PP.CreateBorder(border, 0, 0, 0, 1) end
        end
        frame._previewBuffs = holder
    end
    local function DetachFakeBuffs(frame)
        if frame._previewBuffs then frame._previewBuffs:Hide() end
    end

    -- Fake static cast bar for the boss preview (boss2 only). This drives the
    -- REAL cast bar so it is 100% identical to a live cast: it disables the oUF
    -- Castbar element (so oUF never resets our frozen state), then shows the bar
    -- with a fixed mid-cast fill + spell name / timer / icon and the active-cast
    -- tint -- the same state OnCastbarCastActive produces during a real cast.
    local FAKE_CAST_SPELL_NAME = "Shadow Bolt"
    local FAKE_CAST_SPELL_ICON = 136197
    local function DetachFakeCastBar(frame)
        if not frame._fakeCastActive then return end
        frame._fakeCastActive = nil
        local castbar = frame.Castbar
        local castbarBg = castbar and castbar:GetParent()
        if castbar then
            if castbar.castTintLayer then castbar.castTintLayer:SetAlpha(0) end
            castbar:Hide()
        end
        if castbarBg then castbarBg:Hide() end
        -- The real Castbar element is re-enabled by ReloadFrames when the preview
        -- is turned off, so no manual re-enable is needed here.
    end
    local function AttachFakeCastBar(frame)
        local castbar = frame.Castbar
        local castbarBg = castbar and castbar:GetParent()
        if not castbar or not castbarBg then return end
        local settings = db.profile.boss or {}
        if settings.showCastbar == false then
            castbarBg:Hide()
            return
        end
        -- Suppress the real Castbar element so oUF can't reset the frozen cast.
        if frame:IsElementEnabled("Castbar") then frame:DisableElement("Castbar") end
        castbar._eufSettings = settings
        -- Frozen mid-cast fill (respects the configured reverse-fill direction).
        castbar:SetMinMaxValues(0, 1)
        castbar:SetValue(0.65)
        if castbar.Text then castbar.Text:SetText(FAKE_CAST_SPELL_NAME) end
        if castbar.Time then
            if settings.showCastDuration == false then
                castbar.Time:SetText(""); castbar.Time:Hide()
            else
                castbar.Time:Show(); castbar.Time:SetText("1.8")
            end
        end
        if castbar.Icon then
            castbar.Icon:SetTexture(FAKE_CAST_SPELL_ICON)
            -- SetTexture resets the crop; re-apply the cast icon's fixed zoom.
            castbar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        -- Active-cast tint -- same path a real cast uses.
        if castbar.castTintLayer then
            castbar.castTintLayer:SetAlpha(1)
            ApplyUnitFrameCastColor(castbar)
        end
        castbarBg:Show()
        castbar:Show()
        if castbar._iconFrame then
            if settings.showCastIcon == false then castbar._iconFrame:Hide()
            else castbar._iconFrame:Show() end
        end
        if castbar._layoutTextZones then castbar:_layoutTextZones() end
        frame._fakeCastActive = true
    end

    -- Refresh the in-game boss preview's fake auras when boss settings that
    -- affect them (simpleDebuffs, debuffAnchor, debuffSize, buffAnchor, etc.)
    -- change.
    ns.RefreshBossPreviewDebuffs = function()
        if not ns._bossPreviewActive then return end
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then
                AttachFakeDebuffs(f); AttachFakeBuffs(f)
                -- Only the 2nd boss frame shows a sample cast bar.
                if i == 2 then AttachFakeCastBar(f) end
            end
        end
    end

    -- Apply / clear a hostile-red health bar override on a boss frame while
    -- preview is active. Real boss frames never class-color (no player class),
    -- so piggybacking on unit="player" would otherwise paint the bar in the
    -- user's class color -- wrong for a preview.
    local PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B = 0.8, 0.2, 0.2

    -- Fake boss names for the preview. Generated once per activation (stable
    -- across reloads), regenerated on a fresh activation. Health is intentionally
    -- NOT faked: the health max is a secret value in Midnight and cannot be read
    -- or compared, so the bar keeps the player's real (filled) health.
    local PREVIEW_BOSS_NAMES = {
        "The Lich King", "Ragnaros", "Kel'Thuzad", "Archimonde", "Kil'jaeden",
        "Deathwing", "Yogg-Saron", "C'Thun", "Cenarius", "Varimathras",
    }
    local function GenBossPreviewNames()
        local pool = {}
        for i = 1, #PREVIEW_BOSS_NAMES do pool[i] = PREVIEW_BOSS_NAMES[i] end
        for i = #pool, 2, -1 do
            local j = math.random(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        return { pool[1], pool[2], pool[3] }
    end

    -- Override the name fontstring with a fake boss name. Untag it so the [name]
    -- tag (driven by unit="player") stops overwriting it. SetText with a literal
    -- string is secret-safe. Restored on clear.
    local function BossPreviewNameFS(f)
        local s = db.profile.boss
        local lc = (s and s.leftTextContent) or "name"
        local rc = (s and s.rightTextContent) or "perhp"
        local cc = (s and s.centerTextContent) or "none"
        if lc == "name" then return f.LeftText end
        if rc == "name" then return f.RightText end
        if cc == "name" then return f.CenterText end
        return nil
    end
    local function ApplyBossPreviewName(f, name)
        local fs = BossPreviewNameFS(f)
        if not fs then return end
        f._previewNameFS = fs
        if fs._curTag then fs._previewSavedTag = fs._curTag; f:Untag(fs); fs._curTag = nil end
        fs:SetText(name)
    end
    local function ClearBossPreviewName(f)
        local fs = f._previewNameFS
        if not fs then return end
        if fs._previewSavedTag then f:Tag(fs, fs._previewSavedTag); fs._curTag = fs._previewSavedTag; fs._previewSavedTag = nil end
        f._previewNameFS = nil
        if f.UpdateTags then f:UpdateTags() end
    end

    local function ApplyBossPreviewColor(f)
        local h = f.Health
        if not h then return end
        f._previewColorSaved = f._previewColorSaved or {
            colorClass       = h.colorClass,
            colorReaction    = h.colorReaction,
            colorTapped      = h.colorTapped,
            colorDisconnected= h.colorDisconnected,
        }
        -- Color the fake boss frames exactly as a real boss frame would: Dark Mode
        -- dark fill/bg, or a Custom Colored Fill, via ApplyDarkTheme (both leave
        -- colorClass off). The ONE exception: where a real frame would show the live
        -- unit's class/reaction color (ApplyDarkTheme leaves colorClass ON), our fake
        -- unit is the player and has no boss classification -- so substitute the red
        -- preview color instead of the player's class color.
        ApplyDarkTheme(h)
        if h.colorClass then
            h.colorClass = false
            h.colorReaction = false
            h.colorTapped = false
            h.colorDisconnected = false
            h:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B)
            -- oUF's own update may re-color on the next tick; this PostUpdate keeps
            -- the override sticky for the duration of the preview.
            h.PostUpdateColor = function(self) self:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B) end
        end
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

    -- Re-apply the boss preview colors after a Dark Mode change: the dark refresher
    -- repaints every frame via ApplyDarkTheme, which would drop our red class-color
    -- substitute. Called from the dark-mode refresher while the preview is active.
    ns._ReapplyBossPreviewColor = function()
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then ApplyBossPreviewColor(f) end
        end
    end

    -- Boss preview: force boss1/2/3 to render with the player's unit data so
    -- the user can see the boss frame styling live in-game without a real
    -- encounter. Gated out of combat to avoid taint; caller is responsible
    -- for auto-clearing on EUI options window close.
    ns.SetBossPreview = function(enabled)
        if InCombatLockdown() then return false end
        ns._bossPreviewActive = enabled and true or false
        if enabled and not ns._bossPreviewNames then
            ns._bossPreviewNames = GenBossPreviewNames()
        end
        for i = 1, 3 do
            local f = frames["boss" .. i]
            if f then
                if enabled then
                    f:SetAttribute("unit", "player")
                    f:Show()
                    ApplyBossPreviewColor(f)
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    -- After UpdateAllElements re-tags the name, override it with a fake boss name.
                    ApplyBossPreviewName(f, (ns._bossPreviewNames and ns._bossPreviewNames[i]) or PREVIEW_BOSS_NAMES[i] or "Boss")
                    AttachFakeDebuffs(f)
                    AttachFakeBuffs(f)
                    -- Only the 2nd boss frame shows a sample cast bar.
                    if i == 2 then AttachFakeCastBar(f) end
                else
                    ClearBossPreviewColor(f)
                    ClearBossPreviewName(f)
                    f:SetAttribute("unit", "boss" .. i)
                    if not UnitExists("boss" .. i) then f:Hide() end
                    if f.UpdateAllElements then f:UpdateAllElements("BossPreview") end
                    DetachFakeDebuffs(f)
                    DetachFakeBuffs(f)
                    DetachFakeCastBar(f)
                end
            end
        end
        if not enabled then
            ns._bossPreviewNames = nil
            -- Restore the real Buffs/Debuffs elements (and their anchors/counts)
            -- that the fake overlay disabled while preview was active.
            if ns.ReloadFrames then ns.ReloadFrames() end
        end
        return true
    end
    ns.ResolveFontPath = ResolveFontPath

    -- Trigger the EllesmereUI options module registration now that ns.db is ready
    if ns._InitEUIModule then
        ns._InitEUIModule()
    end
end

-------------------------------------------------------------------------------
--  Register unit frame elements with Unlock Mode
--  Called synchronously from OnEnable (right after InitializeFrames) so the
--  elements are registered inside the PLAYER_LOGIN pre-lockdown window on a
--  combat reload. This block used to live at the end of SetupOptionsPanel,
--  which OnEnable runs via C_Timer.After(0) -- and timers never fire during
--  the loading screen, so registration always landed on the first post-load
--  frame, after combat lockdown had re-engaged. Anchored unit frames then
--  could not be positioned until combat dropped.
-------------------------------------------------------------------------------
local function RegisterUFUnlockElements()
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local UNIT_LABELS = {
            player = "Player", target = "Target", focus = "Focus",
            pet = "Pet", targettarget = "Target of Target",
            focustarget = "Focus Target", boss = "Boss Frames",
            classPower = "Class Resource",
            playerCastbar = "Player Frame Mini Cast Bar",
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
                -- Extra height the unlock overlay should extend BELOW the frame.
                -- Boss frames have a castbar anchored under the frame (not a
                -- separate movable element like the player/target cast bars), so
                -- the overlay grows down to wrap it. Other units return 0.
                getBottomExtra = function(k)
                    if k ~= "boss" then return 0 end
                    local b = db.profile.boss
                    if b and b.showCastbar ~= false then return b.castbarHeight or 14 end
                    return 0
                end,
                setWidth = function(k, w)
                    if k == "classPower" then return end
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch
                       and not EllesmereUI._unlockLayerApplying then Rebuild(); return end
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
                    if not EllesmereUI._unlockActive and not EllesmereUI._propagatingMatch
                       and not EllesmereUI._unlockLayerApplying then Rebuild(); return end
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
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
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
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                                end
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
                    -- Unlock-anchored elements: the anchor system is the
                    -- position authority. Only bootstrap from the saved
                    -- standalone position while the frame has no bounds yet
                    -- (first placement); otherwise leave it alone so the
                    -- anchor position is never clobbered.
                    local anchored = EllesmereUI.IsUnlockAnchored
                        and EllesmereUI.IsUnlockAnchored(k)
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
                        local bossStackDir = db.profile.boss and db.profile.boss.bossStackDirection or "down"
                        if frames.boss1 and not (anchored and frames.boss1:GetLeft()) then
                            local bx, by = SnapForFrame(frames.boss1, pos.x, pos.y)
                            frames.boss1:ClearAllPoints()
                            frames.boss1:SetPoint(pt, UIParent, rpt, bx, by)
                        end
                        for i = 2, 5 do
                            local bf = frames["boss" .. i]
                            local prev = frames["boss" .. (i - 1)]
                            if bf and prev then
                                bf:ClearAllPoints()
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", prev, "TOPLEFT", 0, -spacing)
                                end
                            end
                        end
                    elseif k == "classPower" then
                        local cpb = frames._classPowerBar
                        if cpb and not (anchored and cpb:GetLeft()) then
                            px, py = SnapForFrame(cpb, px, py)
                            cpb:ClearAllPoints()
                            cpb:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    else
                        local fr = frames[k]
                        if fr and not (anchored and fr:GetLeft()) then
                            px, py = SnapForFrame(fr, px, py)
                            fr:ClearAllPoints()
                            fr:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    end
                end,
            })
        end

        -- Core unit frames. Only register a mover for units that actually use
        -- the EllesmereUI frame; a unit set to Blizzard-default or Hidden has no
        -- EUI frame to move.
        local function AddUFElement(u, order)
            if ns.GetUnitFrameSource(u) == "eui" then
                elements[#elements + 1] = MakeUFElement(u, order)
            end
        end
        AddUFElement("player", 1)
        AddUFElement("target", 2)
        AddUFElement("focus", 3)
        AddUFElement("pet", 4)
        AddUFElement("targettarget", 5)
        AddUFElement("focustarget", 6)
        if ns.GetUnitFrameSource("boss") == "eui" then
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
        if ns.GetUnitFrameSource("player") == "eui" and db.profile.player.showClassPowerBar and not db.profile.player.lockClassPowerToFrame then
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
                isHidden = function()
                    -- Live show/hide: mirror the per-unit cast bar enable setting
                    -- (player defaults off; target/focus default on). The mover is
                    -- gated on each unlock-mode open, so toggling the setting takes
                    -- effect without a /reload.
                    local s = GetCBSettings()
                    if not s then return true end
                    if unitKey == "player" then return not s.showPlayerCastbar end
                    return s.showCastbar == false
                end,
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
                    if not EllesmereUI._unlockActive and not EllesmereUI._unlockLayerApplying then return end
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
                    -- Unlock-anchored castbars: the anchor system owns the
                    -- position (castbars are anchored to their unit frame by
                    -- default). Only bootstrap while the frame has no bounds.
                    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(cbKey)
                       and f:GetLeft() then
                        return
                    end
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

        -- Always register all three cast bars; visibility is gated live via each
        -- element's isHidden (mirrors the show setting), so toggling a cast bar
        -- on/off takes effect on the next unlock-mode open -- no /reload needed.
        if ns.GetUnitFrameSource("player") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("playerCastbar", "player", 10)
        end
        if ns.GetUnitFrameSource("target") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("targetCastbar", "target", 11)
        end
        if ns.GetUnitFrameSource("focus") == "eui" then
            elements[#elements + 1] = MakeCastBarElement("focusCastbar", "focus", 12)
        end

        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIUnitFrames")

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

-------------------------------------------------------------------------------
--  Private Auras (player frame only, 12.0.5+)
--  Blizzard renders personal boss-mechanic aura icons through
--  C_UnitAuras.AddPrivateAuraAnchor; we register one non-container anchor per
--  slot frame, mirroring the raid frames implementation. Opt-in: no frames,
--  no events, and no anchors exist until paEnabled is true. The player unit
--  token never changes, so anchors are registered once and re-registered only
--  on PLAYER_ENTERING_WORLD (Blizzard drops anchors on unit reassignment and
--  a static player unit never fires OnAttributeChanged) or settings changes.
-------------------------------------------------------------------------------
do
    local C_UnitAuras_AddPrivateAuraAnchor    = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
    local C_UnitAuras_RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

    -- Private aura icons render behind the parent unless the slot frame's
    -- strata sits one level above it (12.0.5 rendering bug).
    local PA_STRATA_FIX = {
        BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    }
    local PA_SLOT_COUNT = 5   -- fixed pool; player boss mechanics are few
    local PA_LVL_AURA   = 13  -- frame level offset, matches the raid frames aura layer

    -- Snap to the physical pixel grid (same approach as the raid frames
    -- helper): EllesmereUI.PP.perfect is the real pixel-perfect multiplier.
    local function PA_PixelSnap(value)
        if value == 0 then return 0 end
        local realPP = EllesmereUI and EllesmereUI.PP
        local perfect = realPP and realPP.perfect
        if not perfect then return value end
        local pf = frames.player
        local es = (pf and pf:GetEffectiveScale()) or (UIParent and UIParent:GetEffectiveScale()) or 1
        local onePixel = perfect / es
        return math.floor(value / onePixel + 0.5 + 0.001) * onePixel
    end

    local st = { frames = nil, anchorIDs = {}, active = false, ev = nil }
    ns._playerPA = st

    -- Lazily create the slot frames the first time the feature is enabled.
    local function CreateSlots(frame)
        if st.frames then return end
        local sz = db.profile.player.paSize or 20
        st.frames = {}
        for i = 1, PA_SLOT_COUNT do
            local f = CreateFrame("Frame", nil, frame)
            f:SetFrameLevel(frame:GetFrameLevel() + PA_LVL_AURA)
            f:SetSize(sz, sz)
            f:EnableMouse(false)
            if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
            f:Hide()
            st.frames[i] = f
        end
    end

    -- Remove all live anchors and hide the slot frames (frames persist for
    -- cheap re-enable).
    local function Unregister()
        if C_UnitAuras_RemovePrivateAuraAnchor then
            for _, aid in ipairs(st.anchorIDs) do
                C_UnitAuras_RemovePrivateAuraAnchor(aid)
            end
            wipe(st.anchorIDs)
        end
        if st.frames then
            for _, f in ipairs(st.frames) do f:Hide() end
        end
    end
    ns.UnregisterPlayerPrivateAuras = Unregister

    -- Position the slot frames and register one per-slot anchor each.
    local function Register(frame)
        if not C_UnitAuras_AddPrivateAuraAnchor then return end
        if not st.frames then return end
        local unit = "player"
        if not UnitExists(unit) then return end

        -- Remove old anchors before re-adding
        for _, aid in ipairs(st.anchorIDs) do
            C_UnitAuras_RemovePrivateAuraAnchor(aid)
        end
        wipe(st.anchorIDs)

        local d = db.profile.player
        local health = frame.Health
        if not health then return end
        local sz = d.paSize or 20
        local showCD = d.paShowCountdown ~= false

        local pos = d.paPosition or "center"
        -- "None": private auras hidden. Old anchors were already removed above;
        -- hide the slot frames and skip registration so Blizzard's secure layer
        -- draws nothing.
        if pos == "none" then
            for _, f in ipairs(st.frames) do f:Hide() end
            return
        end
        local ox = d.paOffsetX or 0
        local oy = d.paOffsetY or 0
        local grow = d.paGrowDirection or "RIGHT"
        local spc = PA_PixelSnap(d.paSpacing or 0)

        -- Hide Tooltips: Blizzard draws each private aura icon at iconInfo size
        -- centered on the slot frame, but the icon's HOVER area comes from the
        -- slot frame's own rect (the C-side icon ignores Lua mouse flags set on
        -- the parent). Collapsing each slot to a sub-pixel point leaves the icon
        -- rendering at full size with no surface left to hover, so the tooltip
        -- can never trigger. The offset shift below moves the point to where the
        -- full-size slot's CENTER used to sit, and the chain spacing regains the
        -- icon width the collapsed frames no longer contribute -- the rendered
        -- icons land pixel-identical to normal mode.
        local slotSz = sz
        if d.paHideTooltip then
            slotSz = 0.001
            local half = sz / 2
            if pos == "topleft" or pos == "left" or pos == "bottomleft" then
                ox = ox + half
            elseif pos == "topright" or pos == "right" or pos == "bottomright" then
                ox = ox - half
            end
            if pos == "topleft" or pos == "top" or pos == "topright" then
                oy = oy - half
            elseif pos == "bottomleft" or pos == "bottom" or pos == "bottomright" then
                oy = oy + half
            end
            spc = spc + sz
        end

        local parentStrata = frame:GetFrameStrata()
        local fixedStrata = PA_STRATA_FIX[parentStrata] or "DIALOG"

        -- Countdown text scale-trick: Blizzard draws the timer/stack text as a
        -- child of the slot frame, so its on-screen size follows the frame's
        -- SCALE, not the iconInfo pixel size. Scaling the frame by (size / 32)
        -- makes the text track the icon size; the icon dimension is compensated
        -- back to a constant 32 local units so the rendered icon stays exactly
        -- paSize pixels. SetPoint offsets and spacing live in the frame's local
        -- (pre-scale) space, so they are divided by the same factor.
        local ts = sz / 32
        if ts <= 0 then ts = 1 end
        local comp = 32               -- icon size in local units; renders at comp*ts = paSize px
        local oxL, oyL, spcL = ox / ts, oy / ts, spc / ts

        for i, paFrame in ipairs(st.frames) do
            paFrame:SetScale(ts)
            paFrame:SetSize(slotSz / ts, slotSz / ts)
            paFrame:SetFrameStrata(fixedStrata)
            paFrame:SetFrameLevel(frame:GetFrameLevel() + PA_LVL_AURA)
            paFrame:ClearAllPoints()

            if i == 1 then
                -- Private auras anchor flush to the health bar edge (no inset),
                -- matching the raid frames behavior.
                if pos == "topleft" then
                    paFrame:SetPoint("TOPLEFT", health, "TOPLEFT", oxL, oyL)
                elseif pos == "top" then
                    paFrame:SetPoint("TOP", health, "TOP", oxL, oyL)
                elseif pos == "topright" then
                    paFrame:SetPoint("TOPRIGHT", health, "TOPRIGHT", oxL, oyL)
                elseif pos == "left" then
                    paFrame:SetPoint("LEFT", health, "LEFT", oxL, oyL)
                elseif pos == "center" then
                    paFrame:SetPoint("CENTER", health, "CENTER", oxL, oyL)
                elseif pos == "right" then
                    paFrame:SetPoint("RIGHT", health, "RIGHT", oxL, oyL)
                elseif pos == "bottomright" then
                    paFrame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", oxL, oyL)
                elseif pos == "bottom" then
                    paFrame:SetPoint("BOTTOM", health, "BOTTOM", oxL, oyL)
                else
                    paFrame:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", oxL, oyL)
                end
            else
                local prev = st.frames[i - 1]
                if grow == "RIGHT" then
                    paFrame:SetPoint("LEFT", prev, "RIGHT", spcL, 0)
                elseif grow == "LEFT" then
                    paFrame:SetPoint("RIGHT", prev, "LEFT", -spcL, 0)
                elseif grow == "UP" then
                    paFrame:SetPoint("BOTTOM", prev, "TOP", 0, spcL)
                elseif grow == "DOWN" then
                    paFrame:SetPoint("TOP", prev, "BOTTOM", 0, -spcL)
                end
            end

            paFrame:Show()

            -- Register per-slot anchor
            local iconInfoTbl = {
                iconWidth  = comp,
                iconHeight = comp,
                iconAnchor = {
                    point         = "CENTER",
                    relativeTo    = paFrame,
                    relativePoint = "CENTER",
                    offsetX       = 0,
                    offsetY       = 0,
                },
            }
            -- Scale Blizzard's native border 1:1 to OUR icon size. The border
            -- art is authored for a 32px icon, so iconSize/32*2 makes it fit
            -- any size. Divide by the frame scale (ts) so the visible border
            -- stays identical to the pre-scale-trick size.
            iconInfoTbl.borderScale = (sz / 32 * 2) / ts
            local ok, anchorID = pcall(function()
                return C_UnitAuras_AddPrivateAuraAnchor({
                    unitToken     = unit,
                    auraIndex     = i,
                    parent        = paFrame,
                    isContainer   = false,
                    -- 12.1 renamed this anchor key; retail keeps the old spelling.
                    [EllesmereUI.IS_121 and "showCooldownFrame" or "showCountdownFrame"] = true,
                    showCountdownNumbers = showCD,
                    iconInfo = iconInfoTbl,
                })
            end)
            if ok and anchorID then
                st.anchorIDs[i] = anchorID
            end
        end
    end

    -- Master apply: safe to call any time after OnInitialize. The disabled
    -- path costs one boolean check.
    local function Apply()
        local d = db and db.profile and db.profile.player
        if not d then return end
        if not d.paEnabled then
            if st.active then
                Unregister()
                if st.ev then st.ev:UnregisterAllEvents() end
                st.active = false
            end
            return
        end
        if not C_UnitAuras_AddPrivateAuraAnchor then return end
        local pf = frames.player
        if not pf or not pf.Health then return end

        CreateSlots(pf)
        -- Lazy PEW watcher: exists and is registered only while enabled.
        if not st.ev then
            st.ev = CreateFrame("Frame")
            st.ev:SetScript("OnEvent", function() Apply() end)
        end
        st.ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        st.active = true
        Register(pf)
    end
    ns.PlayerPA_Apply = Apply
end

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
    -- Register with unlock mode synchronously: on a combat reload this runs
    -- inside the pre-lockdown window, so the login position pass can resolve
    -- and place anchored unit frames before SetPoint gets blocked.
    RegisterUFUnlockElements()
    C_Timer.After(0, SetupOptionsPanel)
    C_Timer.After(0, function()
        if EllesmereUI and EllesmereUI.ApplyColorsToOUF then
            EllesmereUI.ApplyColorsToOUF()
        end
        -- Restore the player-threat watcher if the option was saved enabled
        -- (zero cost otherwise -- nothing is registered when off).
        if db and db.profile and db.profile.playerThreatBorderEnabled and ns.SetPlayerThreatEnabled then
            ns.SetPlayerThreatEnabled(true)
        end
        -- Restore player private auras if the saved setting has them enabled
        -- (zero cost otherwise -- nothing is created when off).
        if db and db.profile and db.profile.player and db.profile.player.paEnabled
            and ns.PlayerPA_Apply then
            ns.PlayerPA_Apply()
        end
    end)

    -- Incompatible addon detection is handled globally by EllesmereUI
end

-------------------------------------------------------------------------------
--  Boss Frame Range Dimming
--  Boss units sit outside UnitInRange's group-member domain, so range is
--  measured against a known spell instead: a harm spell for attackable
--  bosses (all specs, first known spell in the class chain wins), or the
--  class baseline heal for friendly bosses (healer specs only). Whole-frame
--  alpha follows db.profile.boss.oorAlpha; 100% means no fade and the check
--  short-circuits. The ticker exists only while a boss frame is shown.
--  (do-block: zero persistent main-chunk locals.)
-------------------------------------------------------------------------------
do
    local HARM_CHAIN = {
        DEATHKNIGHT = { 49576, 47541 },           -- Death Grip, Death Coil
        DEMONHUNTER = { 185123, 183752, 204021 }, -- Throw Glaive, Consume Magic, Fiery Brand
        DRUID       = { 8921, 5176, 6795 },       -- Moonfire, Wrath, Growl
        EVOKER      = { 362969 },                 -- Azure Strike (25yd native)
        HUNTER      = { 75, 466930, 190925 },     -- Auto Shot, Black Arrow, Harpoon
        MAGE        = { 116, 133, 44425, 118 },   -- Frostbolt, Fireball, Arcane Barrage, Polymorph
        MONK        = { 117952, 115546 },         -- Crackling Jade Lightning, Provoke
        PALADIN     = { 20271, 62124 },           -- Judgment, Hand of Reckoning
        PRIEST      = { 589, 585, 8092 },         -- Shadow Word: Pain, Smite, Mind Blast
        ROGUE       = { 36554, 185763, 2094 },    -- Shadowstep, Pistol Shot, Blind
        SHAMAN      = { 188196, 370 },            -- Lightning Bolt, Purge
        WARLOCK     = { 234153, 232670, 686, 348, 172, 5782 }, -- Drain Life, Shadow Bolt (both ids), Immolate, Corruption, Fear
        WARRIOR     = { 355, 100 },               -- Taunt, Charge
    }
    local HELP_HEAL = {
        PRIEST = 2061, PALADIN = 19750, SHAMAN = 8004,
        DRUID = 8936, MONK = 116670, EVOKER = 361469,
    }

    local harmSpell, helpSpell
    local visCount, ticker = 0, nil

    local function Known(sid)
        if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank then
            return C_SpellBook.IsSpellInSpellBook(sid, Enum.SpellBookSpellBank.Player, true)
        end
        return IsSpellKnown and IsSpellKnown(sid)
    end

    local function ResolveRangeSpells()
        harmSpell, helpSpell = nil, nil
        local _, pClass = UnitClass("player")
        for _, sid in ipairs(HARM_CHAIN[pClass] or {}) do
            if Known(sid) then harmSpell = sid; break end
        end
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role == "HEALER" then helpSpell = HELP_HEAL[pClass] end
    end

    local function TickOne(f, unit)
        if not db then return end
        local oor = (db.profile.boss and db.profile.boss.oorAlpha) or 0.4
        if oor >= 1 or not UnitExists(unit) then
            f:SetAlpha(1)
            return
        end
        local spell
        if UnitCanAttack("player", unit) then
            spell = harmSpell
        else
            spell = helpSpell
        end
        if spell then
            -- Secret-safe: the result may be secret in instances, which
            -- SetAlphaFromBoolean accepts natively -- but it can also be NIL
            -- (unit not range-checkable right now / spell momentarily not
            -- evaluable), which it rejects. issecretvalue runs first so the
            -- nil check never touches a secret.
            local inRange = C_Spell.IsSpellInRange(spell, unit)
            if issecretvalue(inRange) or inRange ~= nil then
                f:SetAlphaFromBoolean(inRange, 1, oor)
            else
                f:SetAlpha(1)
            end
        else
            f:SetAlpha(1)
        end
    end

    local function Tick()
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f and f:IsVisible() then TickOne(f, "boss" .. i) end
        end
    end

    local function UpdateTicker()
        local want = visCount > 0
        if want and not ticker then
            ticker = C_Timer.NewTicker(0.4, Tick)
        elseif not want and ticker then
            ticker:Cancel()
            ticker = nil
        end
    end

    local hooked = false
    local function InstallHooks()
        if hooked or not frames["boss1"] then return end
        hooked = true
        for i = 1, 5 do
            local f = frames["boss" .. i]
            if f then
                local unit = "boss" .. i
                if f:IsVisible() then visCount = visCount + 1 end
                f:HookScript("OnShow", function(self)
                    visCount = visCount + 1
                    TickOne(self, unit)
                    UpdateTicker()
                end)
                f:HookScript("OnHide", function(self)
                    visCount = math.max(0, visCount - 1)
                    self:SetAlpha(1)
                    UpdateTicker()
                end)
            end
        end
        UpdateTicker()
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:SetScript("OnEvent", function()
        ResolveRangeSpells()
        InstallHooks()
    end)
end

-------------------------------------------------------------------------------
--  Player Dispel Overlay (player frame only, health bar only)
--  Settings mirror the raid frames' Dispel Overlay / Dispel Colors keys 1:1.
--  SECRET-SAFE, same as the raid frames: in raid content even the player's
--  own debuffs can carry a secret dispelName (boss/raid auras), so detection
--  is the bare `dispelName ~= nil` test (a permitted secret nil-check) and
--  the color comes from GetAuraDispelTypeColor evaluating a Step color curve
--  seeded from the user's dispel colors -- the secret type is never read,
--  indexed or branched on. Curve indices are Blizzard's dispel enum:
--  0 none, 1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed.
--  (do-block: zero persistent main-chunk locals.)
-------------------------------------------------------------------------------
do
    local olTex
    local curve

    local function RebuildCurve()
        if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
        local p = db and db.profile
        curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        local function add(idx, key, dr, dg, dbv)
            local col = p and p[key]
            curve:AddPoint(idx, CreateColor(col and col.r or dr, col and col.g or dg, col and col.b or dbv))
        end
        add(0,  "dispelColorMagic",   0.349, 0.475, 1.0)   -- none: harmless default
        add(1,  "dispelColorMagic",   0.349, 0.475, 1.0)
        add(2,  "dispelColorCurse",   0.636, 0.0,   0.64)
        add(3,  "dispelColorDisease", 0.671, 0.384, 0.098)
        add(4,  "dispelColorPoison",  0.0,   0.706, 0.286)
        add(9,  "dispelColorBleed",   0.75,  0.15,  0.15)
        add(11, "dispelColorBleed",   0.75,  0.15,  0.15)
    end

    local function Update()
        if not db then return end
        -- 12.1: dispel display is owned by the container dispel slots once the
        -- player frame migrates (the index scan below errors while auras are
        -- secret). The slots live in EUI_UnitFrames_AuraContainers.lua.
        if ns.UF_DispelOverlayDisabled then
            if olTex then olTex:Hide() end
            return
        end
        local pf = frames and frames["player"]
        local health = pf and pf.Health
        if not health then return end
        local p = db.profile
        local mode = p.dispelOverlay or "none"

        if not olTex then
            if mode == "none" then return end
            olTex = health:CreateTexture(nil, "ARTWORK", nil, 3)
            olTex:SetTexture("Interface\\Buttons\\WHITE8X8")
            olTex:Hide()
        end
        if mode == "none" then olTex:Hide(); return end

        -- First harmful aura with a dispel type. dispelName can be SECRET on
        -- the player in raid content: only the nil-test is permitted -- never
        -- index a table with it or branch on its value.
        -- "Only Dispellable by You" delegates entirely to the engine filter
        -- token (class/spec/talents evaluated live, no addon tables) -- the
        -- same token the Raid Frames dispel system uses.
        local scanFilter = p.dispelOverlayByMe and "HARMFUL|RAID_PLAYER_DISPELLABLE" or "HARMFUL"
        local found
        for i = 1, 40 do
            local ad = C_UnitAuras.GetAuraDataByIndex("player", i, scanFilter)
            if not ad then break end
            if ad.dispelName ~= nil then
                found = ad
                break
            end
        end
        if not found then olTex:Hide(); return end

        -- Resolve the color through the curve. The components may be secret;
        -- they pass straight into SetColorTexture/SetVertexColor natively.
        if not curve then RebuildCurve() end
        local r, g, b = 0.349, 0.475, 1.0
        if curve and C_UnitAuras.GetAuraDispelTypeColor then
            local col = C_UnitAuras.GetAuraDispelTypeColor("player", found.auraInstanceID, curve)
            if col then
                r, g, b = col:GetRGB()
            end
        end
        local alpha = (p.dispelOverlayOpacity or 100) / 100

        olTex:ClearAllPoints()
        olTex:SetVertexColor(1, 1, 1, 1)
        if mode == "full" then
            olTex:SetAllPoints(health)
            olTex:SetColorTexture(r, g, b, alpha)
        elseif mode == "gradient" or mode == "gradient_sharp" then
            -- Pre-baked vertical gradient tinted via vertex color (CreateColor
            -- cannot wrap secret components; SetVertexColor passes them natively)
            olTex:SetAllPoints(health)
            olTex:SetTexture(mode == "gradient_sharp"
                and "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"
                or "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga")
            olTex:SetVertexColor(r, g, b, alpha)
        else -- "fill": cover only the filled health portion
            local fillTex = health:GetStatusBarTexture()
            if fillTex then
                olTex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
                olTex:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
            else
                olTex:SetAllPoints(health)
            end
            olTex:SetColorTexture(r, g, b, alpha)
        end
        olTex:Show()
    end

    ns.UpdatePlayerDispelOverlay = function()
        RebuildCurve()
        Update()
        -- 12.1: the container dispel slots own the overlay (Update() bails
        -- above); poke their fingerprinted reload so dropdown/cog edits
        -- apply live instead of waiting for the next full container pass.
        if ns.UF_DispelOverlayDisabled and ns.UF_ReloadPlayerDispelSlots then
            ns.UF_ReloadPlayerDispelSlots()
        end
    end

    -- Debuff dispel-type borders (per-unit debuffDispelBorder, default off):
    -- recolors a debuff icon's PP border by dispel type on the legacy oUF
    -- aura path, sharing this block's palette-seeded curve. Same secret
    -- discipline as the overlay: presence = the permitted nil-test, color =
    -- curve evaluation whose components pass natively into the border
    -- setters. Untyped debuffs (and the feature off) restore the standard
    -- black border. On 12.1 the containers own UF auras and render the
    -- engine dispel border instead (style.dispelBorder in
    -- EUI_UnitFrames_AuraContainers.lua) -- engine-picked colors there.
    ns.UF_ColorDebuffDispelBorder = function(button, unit, data)
        local border = button and button.Border
        if not border then return end
        local s = GetSettingsForUnit(unit)
        local dispelName = data and data.dispelName
        if s and s.debuffDispelBorder and dispelName ~= nil then
            if not curve then RebuildCurve() end
            local r, g, b
            if curve and C_UnitAuras.GetAuraDispelTypeColor then
                local col = C_UnitAuras.GetAuraDispelTypeColor(unit, data.auraInstanceID, curve)
                if col then r, g, b = col:GetRGB() end
            end
            if r then
                PP.SetBorderColor(border, r, g, b, 1)
                button._euiDispelTinted = true
                return
            end
        end
        -- Restore the standard border only when we tinted it (pooled buttons
        -- recycle across auras; never churn untouched borders).
        if button._euiDispelTinted then
            button._euiDispelTinted = nil
            PP.SetBorderColor(border, 0, 0, 0, 1)
        end
    end

    -- Re-seed the curve + re-apply after any frame reload (settings changes
    -- and profile swaps route through ns.ReloadFrames / _EUF_ReloadFrames).
    -- ns.ReloadFrames is assigned during OnEnable, so the wrap is deferred to
    -- the first event after login; the global export is re-pointed too.
    local wrapped = false
    local function EnsureReloadHook()
        if wrapped or not ns.ReloadFrames then return end
        wrapped = true
        local orig = ns.ReloadFrames
        local function hookedReload(...)
            orig(...)
            RebuildCurve()
            Update()
        end
        ns.ReloadFrames = hookedReload
        if _G._EUF_ReloadFrames == orig then
            _G._EUF_ReloadFrames = hookedReload
        end
    end

    local ev2 = CreateFrame("Frame")
    ev2:RegisterUnitEvent("UNIT_AURA", "player")
    ev2:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev2:SetScript("OnEvent", function()
        EnsureReloadHook()
        Update()
    end)
end
